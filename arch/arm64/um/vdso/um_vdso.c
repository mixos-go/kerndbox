// SPDX-License-Identifier: GPL-2.0-only
/*
 * arch/arm64/um/vdso/um_vdso.c
 *
 * UML arm64 vDSO — turns all vDSO calls into real syscalls via svc #0.
 *
 * UML intercepts the child process's svc #0 via ptrace, so the vDSO
 * just needs to issue the real syscall and UML handles it normally.
 *
 * Note: arm64 does not have a time() syscall (__NR_time is absent from
 * asm-generic/unistd.h since kernel 5.1). clock_gettime(CLOCK_REALTIME)
 * is the correct replacement and is what glibc uses.
 *
 * Adapted from arch/x86/um/vdso/um_vdso.c by Richard Weinberger.
 */

#define DISABLE_BRANCH_PROFILING

#include <linux/time.h>
#include <linux/getcpu.h>
#include <asm/unistd.h>

/* Prototypes — suppress -Wmissing-prototypes */
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

/*
 * time() — arm64 has no __NR_time syscall. Implement via
 * clock_gettime(CLOCK_REALTIME), which UML will trap normally.
 */
__kernel_old_time_t __vdso_time(__kernel_old_time_t *t)
{
	struct __kernel_old_timespec ts;
	register long x8 asm("x8") = __NR_clock_gettime;
	register clockid_t x0 asm("x0") = CLOCK_REALTIME;
	register struct __kernel_old_timespec *x1 asm("x1") = &ts;
	register long ret asm("x0");

	asm volatile("svc #0"
		     : "=r" (ret)
		     : "r" (x8), "0" (x0), "r" (x1)
		     : "memory", "cc");

	if (ret == 0) {
		if (t)
			*t = ts.tv_sec;
		return ts.tv_sec;
	}
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
