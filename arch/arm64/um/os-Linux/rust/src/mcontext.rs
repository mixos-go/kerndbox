// SPDX-License-Identifier: GPL-2.0
//! arm64 mcontext → uml_pt_regs conversion.
//!
//! Replaces arch/arm64/um/os-Linux/mcontext.c.
//!
//! arm64 glibc mcontext_t layout (sys/ucontext.h):
//!   regs[0..30]  = x0..x30 (general purpose)
//!   regs[31]     = sp
//!   regs[32]     = pc
//!   regs[33]     = pstate

use crate::ffi::{UmlPtRegs, SP, PC, PSTATE};

/// Populate uml_pt_regs from a signal mcontext_t.
///
/// Called when UML catches SIGSEGV/SIGBUS to extract register state
/// from the host signal frame for guest fault handling.
///
/// # Safety
/// Both pointers must be valid and properly aligned.
#[no_mangle]
pub unsafe extern "C" fn get_regs_from_mc(
    regs: *mut UmlPtRegs,
    mc: *const libc::c_void,  // actually *const mcontext_t
) {
    // arm64 glibc mcontext_t: gregset_t = unsigned long long [34]
    // At offset 0 in the struct (no padding before regs[]).
    let mc_regs = mc as *const u64;

    let r = &mut (*regs).gp;

    // x0..x30
    for i in 0..31usize {
        r[i] = *mc_regs.add(i);
    }
    // sp, pc, pstate
    r[SP]     = *mc_regs.add(31);
    r[PC]     = *mc_regs.add(32);
    r[PSTATE] = *mc_regs.add(33);
}
