// SPDX-License-Identifier: GPL-2.0-only
/*
 * arch/arm64/um/vdso/um_vdso.c
 *
 * UML arm64 vDSO — turns all vDSO calls into real syscalls via svc #0.
 *
 * UML intercepts the child process's syscall instruction (svc #0 on arm64)
 * via ptrace. So the most correct vDSO is one that issues svc #0 for every
 * call — UML will trap and handle it normally.
 *
 * Adapted from arch/x86/um/vdso/um_vdso.c by Richard Weinberger.
 */

#define DISABLE_BRANCH_PROFILING

#include <linux/time.h>
#include <linux/getcpu.h>
#include <asm/unistd.h>

/* workaround for -Wmissing-prototypes */
int __vdso_clock_gettime(clockid_t clock, struct __kernel_old_timespec *ts);
int __vdso_gettimeofday(struct __kernel_old_timeval *tv, struct timezone *tz);
__kernel_old_time_t __vdso_time(__kernel_old_time_t *t);
long __vdso_getcpu(unsigned int *cpu, unsigned int *node,
		   struct getcpu_cache *unused);

int __vdso_clock_gettime(clockid_t clock, struct __kernel_old_timespec *ts)
{
	register long x8 asm("x8") = __NR_clock_gettime;
	register clockid_t x0 asm("x0") = clock;
	register struct __kernel_old_timespec *x1 asm("x1") = ts;
	register long ret asm("x0");

	asm volatile("svc #0"
		     : "=r" (ret)
		     : "r" (x8), "0" (x0), "r" (x1)
		     : "memory", "cc");
	return ret;
}
int clock_gettime(clockid_t, struct __kernel_old_timespec *)
	__attribute__((weak, alias("__vdso_clock_gettime")));

int __vdso_gettimeofday(struct __kernel_old_timeval *tv, struct timezone *tz)
{
	register long x8 asm("x8") = __NR_gettimeofday;
	register struct __kernel_old_timeval *x0 asm("x0") = tv;
	register struct timezone *x1 asm("x1") = tz;
	register long ret asm("x0");

	asm volatile("svc #0"
		     : "=r" (ret)
		     : "r" (x8), "0" (x0), "r" (x1)
		     : "memory", "cc");
	return ret;
}
int gettimeofday(struct __kernel_old_timeval *, struct timezone *)
	__attribute__((weak, alias("__vdso_gettimeofday")));

__kernel_old_time_t __vdso_time(__kernel_old_time_t *t)
{
	register long x8 asm("x8") = __NR_time;
	register __kernel_old_time_t *x0 asm("x0") = t;
	register long ret asm("x0");

	asm volatile("svc #0"
		     : "=r" (ret)
		     : "r" (x8), "0" (x0)
		     : "memory", "cc");
	return ret;
}
__kernel_old_time_t time(__kernel_old_time_t *t)
	__attribute__((weak, alias("__vdso_time")));

long __vdso_getcpu(unsigned int *cpu, unsigned int *node,
		   struct getcpu_cache *unused)
{
	/* UML does not support SMP */
	if (cpu)
		*cpu = 0;
	if (node)
		*node = 0;
	return 0;
}
long getcpu(unsigned int *cpu, unsigned int *node, struct getcpu_cache *tcache)
	__attribute__((weak, alias("__vdso_getcpu")));
