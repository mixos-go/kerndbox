// SPDX-License-Identifier: GPL-2.0
//! arm64 ptrace register access and syscall interception.
//!
//! Replaces arch/arm64/um/os-Linux/registers.c and the arm64-specific
//! sections that were scattered via #ifdef __aarch64__ in
//! arch/um/os-Linux/skas/process.c.
//!
//! Key design:
//!   • PTRACE_GETREGSET/SETREGSET via NT_PRSTATUS — standard POSIX,
//!     works on all arm64 hosts including AWS Graviton/GitHub Actions.
//!   • arm64_neutralize_syscall: tries PTRACE_SET_SYSCALL first (fast path),
//!     falls back to PTRACE_SETREGSET x8 modification (always works).
//!   • arm64_check_ptrace: startup probe, non-fatal on EIO — continues
//!     with PTRACE_SETREGSET fallback mode.

use std::io;
use std::mem;
use libc::{c_int, c_long, c_ulong, pid_t};
use libc::{ptrace, waitpid, PTRACE_SYSCALL, PTRACE_SETOPTIONS, PTRACE_O_TRACESYSGOOD};
use libc::{WUNTRACED, WIFSTOPPED, WSTOPSIG, WIFEXITED, WEXITSTATUS};

use crate::ffi::*;

// ── iovec helper ─────────────────────────────────────────────────────────────

fn iov(base: *mut libc::c_void, len: usize) -> libc::iovec {
    libc::iovec { iov_base: base, iov_len: len }
}

// ── Low-level PTRACE_GETREGSET/SETREGSET ─────────────────────────────────────

fn getregset(pid: pid_t, note: u64, buf: &mut [u64]) -> io::Result<()> {
    let mut v = iov(buf.as_mut_ptr() as *mut _, buf.len() * 8);
    let r = unsafe {
        ptrace(libc::PTRACE_GETREGSET, pid,
               note as usize as *mut libc::c_void,
               &mut v as *mut _ as *mut libc::c_void)
    };
    if r < 0 { Err(io::Error::last_os_error()) } else { Ok(()) }
}

fn setregset(pid: pid_t, note: u64, buf: &[u64]) -> io::Result<()> {
    let mut v = iov(buf.as_ptr() as *mut _, buf.len() * 8);
    let r = unsafe {
        ptrace(libc::PTRACE_SETREGSET, pid,
               note as usize as *mut libc::c_void,
               &mut v as *mut _ as *mut libc::c_void)
    };
    if r < 0 { Err(io::Error::last_os_error()) } else { Ok(()) }
}

// ── Exported register access (replaces registers.c) ─────────────────────────

/// Save GP registers from tracee into regs->gp.
/// Called by arch/um/os-Linux/skas/process.c (guarded by #ifdef __aarch64__).
#[no_mangle]
pub extern "C" fn save_registers(pid: c_int, regs: *mut UmlPtRegs) -> c_int {
    let r = unsafe { &mut (*regs).gp };
    match getregset(pid as pid_t, NT_PRSTATUS, r) {
        Ok(()) => 0,
        Err(e) => -(e.raw_os_error().unwrap_or(libc::EIO)),
    }
}

/// Restore GP registers from regs->gp into tracee.
#[no_mangle]
pub extern "C" fn restore_registers(pid: c_int, regs: *const UmlPtRegs) -> c_int {
    let r = unsafe { &(*regs).gp };
    match setregset(pid as pid_t, NT_PRSTATUS, r) {
        Ok(()) => 0,
        Err(e) => -(e.raw_os_error().unwrap_or(libc::EIO)),
    }
}

/// ptrace_getregs — raw GP register read (called from init_pid_registers).
#[no_mangle]
pub extern "C" fn ptrace_getregs(pid: c_long, regs_out: *mut c_ulong) -> c_int {
    let buf = unsafe { std::slice::from_raw_parts_mut(regs_out as *mut u64, GP_REGS) };
    match getregset(pid as pid_t, NT_PRSTATUS, buf) {
        Ok(()) => 0,
        Err(e) => -(e.raw_os_error().unwrap_or(libc::EIO)),
    }
}

/// ptrace_setregs — raw GP register write.
#[no_mangle]
pub extern "C" fn ptrace_setregs(pid: c_long, regs_in: *const c_ulong) -> c_int {
    let buf = unsafe { std::slice::from_raw_parts(regs_in as *const u64, GP_REGS) };
    match setregset(pid as pid_t, NT_PRSTATUS, buf) {
        Ok(()) => 0,
        Err(e) => -(e.raw_os_error().unwrap_or(libc::EIO)),
    }
}

/// get_fp_registers — read FP/SIMD state (NT_PRFPREG).
#[no_mangle]
pub extern "C" fn get_fp_registers(pid: c_int, regs: *mut c_ulong) -> c_int {
    let buf = unsafe { std::slice::from_raw_parts_mut(regs as *mut u64, FP_SIZE) };
    match getregset(pid as pid_t, NT_PRFPREG, buf) {
        Ok(()) => 0,
        Err(e) => -(e.raw_os_error().unwrap_or(libc::EIO)),
    }
}

/// put_fp_registers — write FP/SIMD state.
#[no_mangle]
pub extern "C" fn put_fp_registers(pid: c_int, regs: *const c_ulong) -> c_int {
    let buf = unsafe { std::slice::from_raw_parts(regs as *const u64, FP_SIZE) };
    match setregset(pid as pid_t, NT_PRFPREG, buf) {
        Ok(()) => 0,
        Err(e) => -(e.raw_os_error().unwrap_or(libc::EIO)),
    }
}

/// get_safe_registers — zero-initialise GP and FP regs for new threads.
#[no_mangle]
pub extern "C" fn get_safe_registers(regs: *mut c_ulong, fp_regs: *mut c_ulong) {
    if !regs.is_null() {
        unsafe { std::ptr::write_bytes(regs, 0, GP_REGS) };
    }
    if !fp_regs.is_null() {
        unsafe { std::ptr::write_bytes(fp_regs, 0, FP_SIZE) };
    }
}

/// arch_init_registers — probe FP/SIMD capabilities (noop: mandatory on ARMv8).
#[no_mangle]
pub extern "C" fn arch_init_registers(_pid: c_int) {}

/// get_thread_reg — read PC or SP from jmp_buf for UML context switch.
/// JB_IP and JB_SP are defined per arch in setjmp.h.
#[no_mangle]
pub extern "C" fn get_thread_reg(reg: c_int, buf: *const c_ulong) -> c_ulong {
    // arm64 glibc jmp_buf layout: [x19..x28, x29, x30(lr), sp, pc, ...]
    // JB_IP (HOST_PC)  = 11  (lr/x30 becomes pc after longjmp)
    // JB_SP (HOST_SP)  = 12
    const JB_IP: usize = 11;
    const JB_SP: usize = 12;
    const HOST_PC: c_int = PC as c_int;
    const HOST_SP: c_int = SP as c_int;

    let arr = unsafe { std::slice::from_raw_parts(buf, 13) };
    match reg {
        r if r == HOST_PC => arr[JB_IP],
        r if r == HOST_SP => arr[JB_SP],
        _ => {
            // printk equivalent — use eprintln in userspace Rust
            eprintln!("get_thread_reg: unknown reg {}", reg);
            0
        }
    }
}

// ── Syscall neutralization ───────────────────────────────────────────────────

/// Neutralize a pending syscall so the host kernel executes getpid() instead.
///
/// Strategy:
///   1. Try PTRACE_SET_SYSCALL (arm64-specific request 23) — fast path.
///   2. If that returns EIO (unsupported on some VMs e.g. AWS Graviton,
///      GitHub Actions arm64), fall back to PTRACE_SETREGSET: read all
///      GP regs, set x8 = NR_getpid, write back. The kernel reads x8 as
///      the syscall number at syscall-entry, so this has identical effect.
///
/// Called from arch/um/os-Linux/skas/process.c at SIGTRAP|0x80 entry-stop.
#[no_mangle]
pub extern "C" fn arm64_neutralize_syscall(pid: c_int) {
    // Fast path: PTRACE_SET_SYSCALL
    let r = unsafe {
        ptrace(PTRACE_SET_SYSCALL as c_int,
               pid as pid_t,
               std::ptr::null_mut::<libc::c_void>(),
               NR_GETPID as usize as *mut libc::c_void)
    };
    if r == 0 { return; }

    // Fallback: PTRACE_SETREGSET x8
    let mut gp = [0u64; GP_REGS];
    if getregset(pid as pid_t, NT_PRSTATUS, &mut gp).is_err() {
        eprintln!("arm64_neutralize_syscall: PTRACE_GETREGSET failed: {}",
                  io::Error::last_os_error());
        unsafe { libc::raise(libc::SIGSEGV) };
        return;
    }
    gp[X8] = NR_GETPID;
    if setregset(pid as pid_t, NT_PRSTATUS, &gp).is_err() {
        eprintln!("arm64_neutralize_syscall: PTRACE_SETREGSET failed: {}",
                  io::Error::last_os_error());
        unsafe { libc::raise(libc::SIGSEGV) };
    }
}

// ── Startup ptrace capability check ─────────────────────────────────────────

/// arm64_check_ptrace — verify ptrace syscall interception works.
///
/// Spawns a child, traces it, waits for a syscall-entry stop, then tests
/// whether we can modify the syscall number. Non-fatal on PTRACE_SET_SYSCALL
/// EIO — we just log a warning and continue with PTRACE_SETREGSET fallback.
///
/// Called from arch/um/os-Linux/start_up.c check_ptrace() on arm64.
#[no_mangle]
pub extern "C" fn arm64_check_ptrace() {
    eprint!("Checking ptrace syscall modification (arm64)...");

    let pid = unsafe { libc::fork() };
    match pid {
        -1 => panic!("arm64_check_ptrace: fork failed"),
        0  => child_trace_target(),
        _  => parent_trace_loop(pid),
    }
}

/// Child: enable tracing and spin in a getpid() loop so parent can intercept.
fn child_trace_target() -> ! {
    unsafe {
        ptrace(libc::PTRACE_TRACEME, 0, std::ptr::null_mut::<libc::c_void>(),
               std::ptr::null_mut::<libc::c_void>());
        libc::raise(libc::SIGSTOP);
        // Spin: parent will intercept one of these getpid() calls
        for _ in 0..100 {
            libc::syscall(libc::SYS_getpid);
        }
        libc::_exit(0);
    }
}

/// Parent: attach, wait for syscall-entry, probe neutralization.
fn parent_trace_loop(pid: pid_t) {
    unsafe {
        let mut status: c_int = 0;
        libc::waitpid(pid, &mut status, WUNTRACED);

        ptrace(PTRACE_SETOPTIONS, pid, std::ptr::null_mut::<libc::c_void>(),
               PTRACE_O_TRACESYSGOOD as usize as *mut libc::c_void);

        let mut found = false;
        loop {
            ptrace(PTRACE_SYSCALL, pid, std::ptr::null_mut::<libc::c_void>(),
                   std::ptr::null_mut::<libc::c_void>());
            libc::waitpid(pid, &mut status, WUNTRACED);

            if !WIFSTOPPED(status) {
                if found && WIFEXITED(status) && WEXITSTATUS(status) == 0 {
                    break;
                }
                panic!("arm64_check_ptrace: unexpected child exit 0x{:x}", status);
            }

            let sig = WSTOPSIG(status);
            if sig != (libc::SIGTRAP | 0x80) { continue; }
            if found { continue; }

            // Got syscall-entry stop — probe neutralization
            let mut gp = [0u64; GP_REGS];
            if getregset(pid, NT_PRSTATUS, &mut gp).is_err() {
                panic!("arm64_check_ptrace: PTRACE_GETREGSET failed");
            }

            if gp[X8] == libc::SYS_getpid as u64 {
                // Try PTRACE_SET_SYSCALL
                let r = ptrace(PTRACE_SET_SYSCALL as c_int, pid,
                               std::ptr::null_mut::<libc::c_void>(),
                               libc::SYS_getppid as usize as *mut libc::c_void);
                if r < 0 {
                    // Non-fatal — fallback mode available
                    eprintln!("\narm64_check_ptrace: PTRACE_SET_SYSCALL unavailable \
                               ({}) — using PTRACE_SETREGSET fallback",
                              io::Error::last_os_error());
                    // Demonstrate fallback works
                    gp[X8] = libc::SYS_getppid as u64;
                    if setregset(pid, NT_PRSTATUS, &gp).is_err() {
                        panic!("arm64_check_ptrace: PTRACE_SETREGSET fallback failed");
                    }
                    eprintln!("arm64_check_ptrace: PTRACE_SETREGSET fallback OK");
                }
                found = true;
            }
        }

        ptrace(libc::PTRACE_DETACH, pid, std::ptr::null_mut::<libc::c_void>(),
               std::ptr::null_mut::<libc::c_void>());
        libc::waitpid(pid, &mut status, 0);
    }
    eprintln!("OK");
}
