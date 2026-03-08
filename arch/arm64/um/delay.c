// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/delay.c - delay functions for UML on arm64.
 */

#include <linux/export.h>
#include <linux/kernel.h>
#include <linux/delay.h>
#include <asm/param.h>

void __delay(unsigned long loops)
{
	asm volatile(
		"1: subs %0, %0, #1\n"
		"   b.ne 1b\n"
		: "+r" (loops)
	);
}
EXPORT_SYMBOL(__delay);

void __const_udelay(unsigned long xloops)
{
	unsigned long loops = (xloops * loops_per_jiffy * HZ) >> 32;

	__delay(loops + 1);
}
EXPORT_SYMBOL(__const_udelay);

void __udelay(unsigned long usecs)
{
	__const_udelay(usecs * 0x000010c7); /* 2**32 / 1000000 */
}
EXPORT_SYMBOL(__udelay);

void __ndelay(unsigned long nsecs)
{
	__const_udelay(nsecs * 0x00005); /* 2**32 / 1000000000 */
}
EXPORT_SYMBOL(__ndelay);
