/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __UM_ARM64_WORD_AT_A_TIME_H
#define __UM_ARM64_WORD_AT_A_TIME_H

/*
 * Block native arch/arm64/include/asm/word-at-a-time.h — it uses
 * MTE intrinsics and inline asm that are incompatible with UML builds.
 * Use the portable generic implementation instead.
 */
#define __ASM_WORD_AT_A_TIME_H

#include <asm-generic/word-at-a-time.h>

#endif /* __UM_ARM64_WORD_AT_A_TIME_H */
