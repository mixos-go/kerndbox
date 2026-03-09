// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/sys_call_table.c — arm64 UML syscall table
 *
 * arm64 UML uses asm-generic/unistd.h (same table as arm64 native).
 * We build it with the same two-pass technique as arch/x86/um:
 *
 *   Pass 1: emit  "extern asmlinkage long sym(unsigned long x6);"
 *           for every entry → gives each sym the correct prototype.
 *
 *   Pass 2: emit  "sym,"  as the array initialiser.
 *
 * Because the prototype in Pass 1 matches sys_call_ptr_t exactly,
 * no cast is needed and -Wcast-function-type cannot fire.
 *
 * __SC_COMP and __SC_3264 are intentionally NOT pre-defined here.
 * asm-generic/unistd.h already defines them in terms of __SYSCALL —
 * pre-defining them would cause -Wmacro-redefined. We only define
 * __SYSCALL and let the header expand the rest correctly.
 *
 * Syscall ABI (arm64 / EABI64):
 *   x8       = syscall number
 *   x0..x5   = arguments
 *   x0       = return value
 */

#include <linux/cache.h>
#include <asm/syscall.h>   /* sys_call_ptr_t = long(*)(ulong x6) */

/* sys_ni_syscall: stub for unimplemented syscalls */
extern asmlinkage long sys_ni_syscall(unsigned long, unsigned long,
				      unsigned long, unsigned long,
				      unsigned long, unsigned long);

/* ── Pass 1: forward-declare every syscall symbol ─────────────────────────
 * Define only __SYSCALL — __SC_COMP and __SC_3264 are defined by
 * asm-generic/unistd.h itself in terms of __SYSCALL, so no redefinition.
 */
#undef  __SYSCALL
#undef  __SC_COMP
#undef  __SC_3264
#define __SYSCALL(nr, sym) \
	asmlinkage long sym(unsigned long, unsigned long, unsigned long, \
			    unsigned long, unsigned long, unsigned long);

#include <asm-generic/unistd.h>

/* ── Pass 2: build the table ───────────────────────────────────────────────
 * Now that every sym has a declared prototype matching sys_call_ptr_t,
 * placing &sym in the array requires no cast at all.
 */
#undef  __SYSCALL
#undef  __SC_COMP
#undef  __SC_3264
#define __SYSCALL(nr, sym) [nr] = sym,

const sys_call_ptr_t sys_call_table[] ____cacheline_aligned = {
	[0 ... __NR_syscalls - 1] = sys_ni_syscall,
#include <asm-generic/unistd.h>
};

int syscall_table_size = sizeof(sys_call_table);
