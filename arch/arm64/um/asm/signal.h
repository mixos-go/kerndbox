/* SPDX-License-Identifier: GPL-2.0 */
/*
 * UML override for arm64 asm/signal.h.
 * The native arm64 version pulls in asm/memory.h which conflicts with UML's
 * own PAGE_OFFSET / THREAD_SIZE / __pa / __va definitions.
 */
#ifndef __UM_ARM64_ASM_SIGNAL_H
#define __UM_ARM64_ASM_SIGNAL_H

#include <uapi/asm/signal.h>
#include <uapi/asm/siginfo.h>

#endif
