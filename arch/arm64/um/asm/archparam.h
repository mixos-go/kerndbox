/* SPDX-License-Identifier: GPL-2.0 */
/* arm64 stub - LAST_PKMAP is x86-32 only */
#ifndef __UM_ARCHPARAM_ARM64_H
#define __UM_ARCHPARAM_ARM64_H

/* Required for arch_mmap_rnd() in mm/util.c */
#define ARCH_MMAP_RND_BITS_MIN 18
#define ARCH_MMAP_RND_BITS_MAX 33
#define ARCH_MMAP_RND_BITS     28
extern int mmap_rnd_bits;

#endif
