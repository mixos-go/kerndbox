/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/os-Linux/arm64_um_os.h
 * Forward declarations for arm64-specific UML os-Linux functions.
 *
 * NOTE: Do NOT include <setjmp.h> here — it conflicts with the kernel's
 * archsetjmp.h (different jmp_buf struct). Files that need get_thread_reg()
 * must include <longjmp.h> or <os.h> first to get the correct jmp_buf.
 */
#ifndef __ARM64_UM_OS_H
#define __ARM64_UM_OS_H

#include <signal.h>

struct uml_pt_regs;
struct pt_regs;

/* registers.c — caller must have included longjmp.h for jmp_buf */
int  save_registers(int pid, struct uml_pt_regs *regs);
int  restore_registers(int pid, struct uml_pt_regs *regs);
int  ptrace_getregs(long pid, unsigned long *regs_out);
int  ptrace_setregs(long pid, unsigned long *regs_in);
int  get_fp_registers(int pid, unsigned long *regs);
int  put_fp_registers(int pid, unsigned long *regs);
void get_safe_registers(unsigned long *regs, unsigned long *fp_regs);
void arch_init_registers(int pid);
void arm64_neutralize_syscall(int pid);
void arm64_check_ptrace(void);

/* signal.c — set_sigstack() is in arch/um/os-Linux/signal.c (generic) */
void remove_sigstack(void);
void (*arch_get_signal_handler(int sig))(int, siginfo_t *, void *);
void arch_do_signal(struct pt_regs *regs, int sig);

/* tls.c */
int os_set_tls(int pid, unsigned long tls);

/* prctl.c */
void arch_prctl_defaults(void);

/* uaccess.c */
int arch_fixup(unsigned long address, struct uml_pt_regs *regs);

/* task_size.c */
unsigned long os_get_top_address(void);

#endif /* __ARM64_UM_OS_H */
