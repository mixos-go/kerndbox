/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __UM_PROCESSOR_ARM64_H
#define __UM_PROCESSOR_ARM64_H

#include <linux/time-internal.h>
#include <sysdep/faultinfo.h>

/*
 * arm64 UML per-thread arch state.
 */
struct arch_thread {
	struct faultinfo faultinfo;
};

#define INIT_ARCH_THREAD { .faultinfo = { 0, 0, 0 } }

/* Block native arm64/include/asm/processor.h — it uses a stack-top trick
 * for task_pt_regs that is wrong for UML. */
#define __ASM_PROCESSOR_H

/* processor-generic.h defines struct thread_struct (with .regs field) */
#include <asm/processor-generic.h>

/* Define task_pt_regs AFTER processor-generic.h so struct thread_struct
 * is complete. Nothing in the processor-generic.h include chain calls
 * task_pt_regs directly, so this ordering is safe. */
#define task_pt_regs(t) (&(t)->thread.regs)

/* cpu_relax: native arm64 gets this from arch/arm64/include/asm/processor.h
 * which we block above. Honour time-travel mode first, then yield hint. */
static __always_inline void cpu_relax(void)
{
	if (time_travel_mode == TT_MODE_INFCPU ||
	    time_travel_mode == TT_MODE_EXTERNAL)
		time_travel_ndelay(1);
	else
		asm volatile("yield" ::: "memory");
}

/* declared in arch/arm64/um/os-Linux/registers.c */
extern unsigned long get_thread_reg(int reg, jmp_buf *buf);

#define STACKSLOTS_PER_LINE 4

static inline void arch_flush_thread(struct arch_thread *thread)
{
}

static inline void arch_copy_thread(struct arch_thread *from,
                                    struct arch_thread *to)
{
}

/* current_sp/current_bp: used by arch/um/include/asm/stacktrace.h
 * Must return unsigned long* to match get_stack_pointer() return type. */
#define current_sp() ({ unsigned long __sp; asm("mov %0, sp" : "=r"(__sp)); (unsigned long *)__sp; })
#define current_bp() ({ unsigned long __fp; asm("mov %0, x29" : "=r"(__fp)); __fp; })

#endif /* __UM_PROCESSOR_ARM64_H */
