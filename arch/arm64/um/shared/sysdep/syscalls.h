/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __SYSDEP_ARM64_SYSCALLS_H
#define __SYSDEP_ARM64_SYSCALLS_H

#include <linux/msg.h>
#include <linux/shm.h>

typedef long syscall_handler_t(long, long, long, long, long, long);

extern syscall_handler_t *sys_call_table[];

/*
 * EXECUTE_SYSCALL — dispatches a UML guest syscall through sys_call_table[].
 *
 * arm64 ABI: x0..x5 = args, x8 = syscall nr, x0 = return value.
 * This matches UPT_SYSCALL_ARG1..6 defined in sysdep/ptrace.h.
 */
#define EXECUTE_SYSCALL(syscall, regs) \
	(((*sys_call_table[syscall]))( \
		UPT_SYSCALL_ARG1(&regs->regs), \
		UPT_SYSCALL_ARG2(&regs->regs), \
		UPT_SYSCALL_ARG3(&regs->regs), \
		UPT_SYSCALL_ARG4(&regs->regs), \
		UPT_SYSCALL_ARG5(&regs->regs), \
		UPT_SYSCALL_ARG6(&regs->regs)))

#endif /* __SYSDEP_ARM64_SYSCALLS_H */
