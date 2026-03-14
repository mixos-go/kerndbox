// SPDX-License-Identifier: GPL-2.0
//! arm64 UML host-side (os-Linux) implementation in Rust.
//!
//! This crate runs as **userspace** code on the host Linux arm64 system —
//! it is NOT in-kernel Rust. It uses std and libc normally, compiles to a
//! static library, and exports `extern "C"` symbols that the UML C code
//! (arch/um/os-Linux/skas/process.c etc.) calls directly.
//!
//! Modules:
//!   ptrace    — register access, syscall neutralization, startup check
//!   tls       — TPIDR_EL0 management via NT_ARM_TLS
//!   signal    — sigaltstack + arch signal hooks
//!   mcontext  — mcontext_t → uml_pt_regs conversion
//!   prctl     — PAC key reset (pointer authentication compat)

#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]

mod ffi;
mod ptrace;
mod tls;
mod signal;
mod mcontext;
mod prctl;

// Re-export all extern "C" symbols so they are visible at link time.
pub use ptrace::*;
pub use tls::*;
pub use signal::*;
pub use mcontext::*;
pub use prctl::*;
