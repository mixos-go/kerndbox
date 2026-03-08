/* SPDX-License-Identifier: GPL-2.0 */
/*
 * UML stub for asm/cpufeatures.h.
 * The native arm64 version requires EL1 CPU capability infrastructure
 * not available in UML context. UML does not use CPU feature bits directly.
 */
#ifndef __UM_ARM64_ASM_CPUFEATURES_H
#define __UM_ARM64_ASM_CPUFEATURES_H
/*
 * arm64 UML uses processor-generic.h which references NCAPINTS/NBUGINTS
 * for the cpuinfo_um struct (x86 heritage). Provide minimal stubs.
 */
#define NCAPINTS  1
#define NBUGINTS  1

#endif
