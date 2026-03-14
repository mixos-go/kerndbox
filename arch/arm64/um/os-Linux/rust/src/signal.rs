// SPDX-License-Identifier: GPL-2.0
//! arm64 UML signal hooks.
//!
//! Replaces arch/arm64/um/os-Linux/signal.c.
//!
//! Most signal handling is arch-independent (arch/um/os-Linux/signal.c).
//! These are the arm64-specific hooks called from the generic code.

use libc::c_int;

/// remove_sigstack — disable sigaltstack.
/// Called during UML shutdown or when tearing down signal infrastructure.
#[no_mangle]
pub extern "C" fn remove_sigstack() {
    let ss = libc::stack_t {
        ss_sp:    std::ptr::null_mut(),
        ss_flags: libc::SS_DISABLE,
        ss_size:  0,
    };
    unsafe { libc::sigaltstack(&ss, std::ptr::null_mut()) };
}

/// arch_get_signal_handler — return arch-specific signal handler override.
/// Returns NULL on arm64: no override needed, use generic UML handler.
#[no_mangle]
pub extern "C" fn arch_get_signal_handler(
    _sig: c_int,
) -> Option<unsafe extern "C" fn(c_int, *mut libc::siginfo_t, *mut libc::c_void)> {
    None
}

/// arch_do_signal — arch-specific pre-processing before signal delivery.
/// No-op on arm64: FP/SIMD state is already in regs->fp[] from get_fp_registers().
#[no_mangle]
pub extern "C" fn arch_do_signal(
    _regs: *mut libc::c_void,
    _sig: c_int,
) {
    // arm64: nothing needed here
}
