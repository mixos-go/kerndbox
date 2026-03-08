/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/checksum.h
 *
 * For UML on arm64 we use the generic pure-C checksum implementation.
 * We deliberately do NOT define _HAVE_ARCH_IPV6_CSUM or _HAVE_ARCH_CSUM_ADD
 * so the generic versions from lib/checksum.c are used instead of
 * hardware-specific asm from arch/arm64/lib/csum.S.
 */
#ifndef __UM_ARM64_CHECKSUM_H
#define __UM_ARM64_CHECKSUM_H

/* Block native arm64 checksum.h which declares hardware-specific functions */
#define __ASM_CHECKSUM_H

#include <asm-generic/checksum.h>

#endif /* __UM_ARM64_CHECKSUM_H */
