// SPDX-License-Identifier: GPL-2.0
//! FFI type definitions matching UML C structs.
//!
//! These must stay ABI-compatible with the C definitions in:
//!   arch/um/include/shared/sysdep/ptrace.h
//!   arch/arm64/um/shared/sysdep/ptrace.h

use libc::c_int;

/// Number of GP registers in arm64 user_pt_regs:
///   x0..x30 (31) + sp (1) + pc (1) + pstate (1) = 34
pub const GP_REGS: usize = 34;

/// Register indices within gp[] array
pub const X0: usize = 0;
pub const X8: usize = 8;   // syscall number register
pub const X30: usize = 30; // link register
pub const SP: usize = 31;
pub const PC: usize = 32;
pub const PSTATE: usize = 33;

/// FP_SIZE: size of user_fpsimd_state in unsigned longs
/// struct user_fpsimd_state { __uint128_t vregs[32]; u32 fpsr; u32 fpcr; }
/// = 32*16 + 4 + 4 = 520 bytes = 65 × u64
pub const FP_SIZE: usize = 65;

/// Mirror of struct uml_pt_regs (arch/um/include/shared/sysdep/ptrace.h)
/// Layout must match exactly — accessed by C code via pointer cast.
#[repr(C)]
pub struct UmlPtRegs {
    pub gp:      [u64; GP_REGS],
    pub fp:      [u64; FP_SIZE],
    pub is_user: c_int,
    _pad:        [u8; 4],        // align to 8 bytes
}

/// NT_PRSTATUS note type for PTRACE_GETREGSET/SETREGSET (GP regs)
pub const NT_PRSTATUS: u64 = 1;

/// NT_PRFPREG note type (FP/SIMD regs)
pub const NT_PRFPREG: u64 = 2;

/// NT_ARM_TLS — TPIDR_EL0 thread-local storage register
pub const NT_ARM_TLS: u64 = 0x401;

/// PTRACE_SET_SYSCALL (arm64-specific, request 23)
/// May return EIO on some VM environments — use PTRACE_SETREGSET fallback.
pub const PTRACE_SET_SYSCALL: libc::c_int = 23;

/// Safe NR to substitute for real syscall during neutralization.
/// getpid() always succeeds and has no side effects.
pub const NR_GETPID: u64 = libc::SYS_getpid as u64;
