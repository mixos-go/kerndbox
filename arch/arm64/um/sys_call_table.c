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
 * No -Wmacro-redefined suppression needed because we undef/redefine
 * the macros in a clean sequence before each include.
 *
 * Syscall ABI (arm64 / EABI64):
 *   x8       = syscall number
 *   x0..x5   = arguments
 *   x0       = return value
 */

#include <linux/syscalls.h>
#include <linux/cache.h>
#include <asm/syscall.h>   /* sys_call_ptr_t = long(*)(ulong x6) */

/* sys_ni_syscall: stub for unimplemented syscalls */
extern asmlinkage long sys_ni_syscall(unsigned long, unsigned long,
				      unsigned long, unsigned long,
				      unsigned long, unsigned long);

/* ── Pass 1: forward-declare every syscall symbol ─────────────────────────
 * This gives the compiler the correct prototype before we take the address
 * of each function.  Without this, the implicit (void *) → sys_call_ptr_t
 * cast would trigger -Wcast-function-type.
 */
#undef  __SYSCALL
#undef  __SC_COMP
#undef  __SC_3264
#define __SYSCALL(nr, sym) \
	asmlinkage long sym(unsigned long, unsigned long, unsigned long, \
			    unsigned long, unsigned long, unsigned long);
#define __SC_COMP(nr, sym, csym)    __SYSCALL(nr, sym)
#define __SC_3264(nr, sym32, sym64) __SYSCALL(nr, sym64)

#include <asm-generic/unistd.h>

/* ── Pass 2: build the table ───────────────────────────────────────────────
 * Now that every sym has a declared prototype matching sys_call_ptr_t,
 * placing &sym in the array requires no cast at all.
 */
#undef  __SYSCALL
#undef  __SC_COMP
#undef  __SC_3264
#define __SYSCALL(nr, sym)          [nr] = sym,
#define __SC_COMP(nr, sym, csym)    __SYSCALL(nr, sym)
#define __SC_3264(nr, sym32, sym64) __SYSCALL(nr, sym64)

const sys_call_ptr_t sys_call_table[] ____cacheline_aligned = {
	[0 ... __NR_syscalls - 1] = sys_ni_syscall,
#include <asm-generic/unistd.h>
};

int syscall_table_size = sizeof(sys_call_table);
