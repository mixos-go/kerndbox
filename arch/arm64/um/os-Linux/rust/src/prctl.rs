// SPDX-License-Identifier: GPL-2.0
//! arm64 prctl defaults.
//!
//! Replaces arch/arm64/um/os-Linux/prctl.c.
//!
//! Disables PAC (Pointer Authentication Code) keys so ptrace register
//! reads are not corrupted on cores with PAuth enabled (ARMv8.3+).
//! Without this, SP/PC values read via PTRACE_GETREGSET will have
//! authentication bits set, making them look like garbage addresses.

/// Reset all PAC keys for the calling process.
///
/// Called from arch/um/os-Linux/start_up.c (arm64 path) during UML init.
/// Also called at startup via arch_prctl_defaults().
#[no_mangle]
pub extern "C" fn arch_prctl_defaults() {
    // PR_PAC_RESET_KEYS = 54 (since Linux 5.0)
    // Bitmask of all key types: IA, IB, DA, DB, GA
    const PR_PAC_RESET_KEYS: libc::c_int = 54;
    const PR_PAC_APIAKEY: libc::c_ulong = 1 << 0;
    const PR_PAC_APIBKEY: libc::c_ulong = 1 << 1;
    const PR_PAC_APDAKEY: libc::c_ulong = 1 << 2;
    const PR_PAC_APDBKEY: libc::c_ulong = 1 << 3;
    const PR_PAC_APGAKEY: libc::c_ulong = 1 << 4;
    const ALL_PAC_KEYS: libc::c_ulong =
        PR_PAC_APIAKEY | PR_PAC_APIBKEY | PR_PAC_APDAKEY |
        PR_PAC_APDBKEY | PR_PAC_APGAKEY;

    unsafe {
        libc::prctl(PR_PAC_RESET_KEYS, ALL_PAC_KEYS, 0, 0, 0);
    }
    // Ignore errors: PR_PAC_RESET_KEYS is a no-op on cores without PAuth.
}
