/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/xor.h
 *
 * UML's generic asm/xor.h falls back to arch/x86/include/asm/xor.h which
 * requires asm/xor_64.h (x86 SSE/AVX SIMD). That file does not exist for
 * arm64, so we override here with the pure-C generic implementation.
 */
#ifndef __UM_ASM_ARM64_XOR_H
#define __UM_ASM_ARM64_XOR_H

#include <asm-generic/xor.h>

#endif
