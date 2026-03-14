// SPDX-License-Identifier: GPL-2.0
//! arm64 TLS register management.
//!
//! Replaces arch/arm64/um/os-Linux/tls.c.
//!
//! TPIDR_EL0 is the arm64 thread-pointer register used by glibc for TLS.
//! The host kernel exposes it via PTRACE_SETREGSET with NT_ARM_TLS (0x401).
//! Without this, all threads share TLS pointer = 0 → immediate SIGSEGV.

use libc::{c_int, c_ulong, pid_t};
use crate::ffi::NT_ARM_TLS;

/// Set TPIDR_EL0 (TLS register) for tracee via PTRACE_SETREGSET NT_ARM_TLS.
///
/// Called once per clone(CLONE_SETTLS) — i.e., every pthread_create().
#[no_mangle]
pub extern "C" fn os_set_tls(pid: c_int, tls: c_ulong) -> c_int {
    let val = tls as u64;
    let mut iov = libc::iovec {
        iov_base: &val as *const u64 as *mut libc::c_void,
        iov_len:  std::mem::size_of::<u64>(),
    };
    let r = unsafe {
        libc::ptrace(
            libc::PTRACE_SETREGSET,
            pid as pid_t,
            NT_ARM_TLS as usize as *mut libc::c_void,
            &mut iov as *mut _ as *mut libc::c_void,
        )
    };
    if r < 0 {
        -(std::io::Error::last_os_error().raw_os_error().unwrap_or(libc::EIO))
    } else {
        0
    }
}
