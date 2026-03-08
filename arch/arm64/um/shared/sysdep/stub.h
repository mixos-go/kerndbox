/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __SYSDEP_STUB_ARM64_H
#define __SYSDEP_STUB_ARM64_H

#include <sys/mman.h>
#include <signal.h>
#include <asm/unistd.h>
#include <as-layout.h>
#include <stub-data.h>
#include <linux/stddef.h>

/*
 * arm64 inline syscall helpers for the UML stub.
 * Syscall ABI: x0-x5 = args, x8 = syscall nr, x0 = return value.
 * SVC #0 triggers the syscall.
 */

#define STUB_MMAP_NR  __NR_mmap
#define MMAP_OFFSET(o) (o)

/* SIGSEGV handler in stub (defined in stub_segv.c, lives at STUB_CODE) */
extern void stub_segv_handler(int sig, siginfo_t *info, void *p);

static __always_inline long stub_syscall0(long syscall)
{
	register long x8 __asm__("x8") = syscall;
	register long x0 __asm__("x0");
	__asm__ volatile("svc #0" : "=r"(x0) : "r"(x8) : "memory", "cc");
	return x0;
}

static __always_inline long stub_syscall2(long syscall, long arg1, long arg2)
{
	register long x8 __asm__("x8") = syscall;
	register long x0 __asm__("x0") = arg1;
	register long x1 __asm__("x1") = arg2;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1) : "memory", "cc");
	return x0;
}

static __always_inline long stub_syscall3(long syscall, long arg1, long arg2,
					  long arg3)
{
	register long x8 __asm__("x8") = syscall;
	register long x0 __asm__("x0") = arg1;
	register long x1 __asm__("x1") = arg2;
	register long x2 __asm__("x2") = arg3;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2)
			 : "memory", "cc");
	return x0;
}

static __always_inline long stub_syscall4(long syscall, long arg1, long arg2,
					  long arg3, long arg4)
{
	register long x8 __asm__("x8") = syscall;
	register long x0 __asm__("x0") = arg1;
	register long x1 __asm__("x1") = arg2;
	register long x2 __asm__("x2") = arg3;
	register long x3 __asm__("x3") = arg4;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2),
			 "r"(x3) : "memory", "cc");
	return x0;
}

static __always_inline long stub_syscall5(long syscall, long arg1, long arg2,
					  long arg3, long arg4, long arg5)
{
	register long x8 __asm__("x8") = syscall;
	register long x0 __asm__("x0") = arg1;
	register long x1 __asm__("x1") = arg2;
	register long x2 __asm__("x2") = arg3;
	register long x3 __asm__("x3") = arg4;
	register long x4 __asm__("x4") = arg5;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2),
			 "r"(x3), "r"(x4) : "memory", "cc");
	return x0;
}

static __always_inline long stub_syscall6(long syscall, long arg1, long arg2,
					  long arg3, long arg4, long arg5,
					  long arg6)
{
	register long x8 __asm__("x8") = syscall;
	register long x0 __asm__("x0") = arg1;
	register long x1 __asm__("x1") = arg2;
	register long x2 __asm__("x2") = arg3;
	register long x3 __asm__("x3") = arg4;
	register long x4 __asm__("x4") = arg5;
	register long x5 __asm__("x5") = arg6;
	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2),
			 "r"(x3), "r"(x4), "r"(x5) : "memory", "cc");
	return x0;
}

/* BRK #0 — arm64 software breakpoint, triggers SIGTRAP in the stub */
static __always_inline void trap_myself(void)
{
	__asm__ volatile("brk #0");
}

static __always_inline void *get_stub_data(void)
{
	unsigned long sp;
	__asm__ volatile("mov %0, sp" : "=r"(sp));
	return (void *)(sp & ~(STUB_DATA_PAGES * UM_KERN_PAGE_SIZE - 1));
}

extern void stub_syscall_handler(void);

#endif /* __SYSDEP_STUB_ARM64_H */
