/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/ptrace-abi.h
 * Minimal stub — UML arm64 does not use x86-style register offsets.
 * The generic arch/um/kernel/ptrace.c includes this file; it only needs
 * an include guard and nothing else for arm64.
 */
#ifndef __UM_ASM_ARM64_PTRACE_ABI_H
#define __UM_ASM_ARM64_PTRACE_ABI_H

/* arm64 does not have a GDT/TLS thread-area; provide stubs */
#define PTRACE_GET_THREAD_AREA  25
#define PTRACE_SET_THREAD_AREA  26

static inline long ptrace_get_thread_area(struct task_struct *t,
			int idx, void __user *info) { return -EIO; }
static inline long ptrace_set_thread_area(struct task_struct *t,
			int idx, void __user *info) { return -EIO; }

#endif /* __UM_ASM_ARM64_PTRACE_ABI_H */
