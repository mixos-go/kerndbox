/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __UM_ELF_ARM64_H
#define __UM_ELF_ARM64_H

/* Block native arm64/include/asm/elf.h which pulls in native processor.h */
#define __ASM_ELF_H

/*
 * Define ELF_CLASS and ELF_DATA *before* including linux/elf.h —
 * linux/elf.h:38 tests #if ELF_CLASS == ELFCLASS32 at include time.
 */
#define ELF_CLASS          ELFCLASS64
#define ELF_DATA           ELFDATA2LSB
#define ELF_ARCH           EM_AARCH64

/*
 * linux/elf.h defines SET_PERSONALITY. We override it below.
 */
#include <linux/elf.h>

/* Minimal definition - mirrors uapi/asm/ptrace.h without pulling hwcap.h */
#ifndef __STRUCT_USER_FPSIMD_STATE
#define __STRUCT_USER_FPSIMD_STATE
struct user_fpsimd_state {
	__uint128_t	vregs[32];
	__u32		fpsr;
	__u32		fpcr;
	__u32		__reserved[2];
};
#endif

#define ELF_PLATFORM       "aarch64"

/* arm64 has no vsyscall page */
#define FIXADDR_USER_START     0
#define FIXADDR_USER_END       0

#define ELF_HWCAP          (0)
#define ELF_HWCAP2         (0)

typedef unsigned long      elf_greg_t;
#define ELF_NGREG          34   /* 31 GPR + sp + pc + pstate */
typedef elf_greg_t         elf_gregset_t[ELF_NGREG];

typedef struct user_fpsimd_state elf_fpregset_t;

#define ELF_CORE_COPY_REGS(pr_reg, regs)				\
	do {								\
		int __i;						\
		for (__i = 0; __i < 34; __i++)				\
			(pr_reg)[__i] = (regs)->regs.gp[__i];		\
	} while (0);

/* linux/elf.h:16 defines SET_PERSONALITY — override it for UML arm64 */
#undef SET_PERSONALITY
#define SET_PERSONALITY(ex)   do { } while (0)

/* arm64 UML: no vDSO */
#define ARCH_HAS_SETUP_ADDITIONAL_PAGES 1
#define arch_setup_additional_pages(bprm, uses_interp) (0)

#define ELF_EXEC_PAGESIZE   PAGE_SIZE
#define ELF_ET_DYN_BASE     (TASK_SIZE / 3 * 2)

#define elf_check_arch(x)  ((x)->e_machine == EM_AARCH64)

#endif /* __UM_ELF_ARM64_H */
