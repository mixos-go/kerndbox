// SPDX-License-Identifier: GPL-2.0
/* arm64 UML: show_regs - dump guest register state */
#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/sched/debug.h>
#include <asm/ptrace.h>

void show_regs(struct pt_regs *regs)
{
	int i;

	printk(KERN_INFO "\n");
	printk(KERN_INFO "pc : %016lx  sp : %016lx\n",
	       PT_REGS_IP(regs), PT_REGS_SP(regs));
	printk(KERN_INFO "pstate: %016lx\n",
	       regs->regs.gp[HOST_PSTATE]);
	for (i = 0; i < 30; i += 2) {
		printk(KERN_INFO "x%-2d: %016lx  x%-2d: %016lx\n",
		       i,   regs->regs.gp[i],
		       i+1, regs->regs.gp[i+1]);
	}
	printk(KERN_INFO "x30: %016lx\n", regs->regs.gp[30]);
}
