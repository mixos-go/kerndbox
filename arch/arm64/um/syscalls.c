// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/syscalls.c
 * mmap syscall for arm64 UML.
 */
#include <linux/sched.h>
#include <linux/mm.h>
#include <linux/syscalls.h>

SYSCALL_DEFINE6(mmap, unsigned long, addr, unsigned long, len,
		unsigned long, prot, unsigned long, flags,
		unsigned long, fd, unsigned long, off)
{
	if (off & ~PAGE_MASK)
		return -EINVAL;
	return ksys_mmap_pgoff(addr, len, prot, flags, fd, off >> PAGE_SHIFT);
}
