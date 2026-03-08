/* SPDX-License-Identifier: GPL-2.0 */
/*
 * arch/arm64/um/asm/text-patching.h
 *
 * arm64 UML does not use x86 text-patching / alternative infrastructure.
 * The functions below are stubbed in arch/um/kernel/um_arch.c.
 * Declarations are provided here so the compiler sees proper prototypes
 * (avoids -Wmissing-prototypes, matching x86 UML where these come from
 * arch/x86/include/asm/alternative.h and text-patching.h).
 */
#ifndef __UM_ARM64_TEXT_PATCHING_H
#define __UM_ARM64_TEXT_PATCHING_H

#include <linux/types.h>

/* Stubbed in arch/um/kernel/um_arch.c — no-ops on arm64 UML */
struct alt_instr;
extern void apply_seal_endbr(s32 *start, s32 *end);
extern void apply_retpolines(s32 *start, s32 *end);
extern void apply_returns(s32 *start, s32 *end);
extern void apply_fineibt(s32 *start_retpoline, s32 *end_retpoline,
			  s32 *start_cfi, s32 *end_cfi);
extern void apply_alternatives(struct alt_instr *start, struct alt_instr *end);
extern void *text_poke(void *addr, const void *opcode, size_t len);
extern void text_poke_sync(void);

#endif /* __UM_ARM64_TEXT_PATCHING_H */
