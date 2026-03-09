// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/module.c — ELF module relocation for UML arm64.
 *
 * UML runs entirely in userspace: all modules are loaded into the same
 * process virtual address space as the UML kernel binary.  There is no
 * need for PLT trampolines or ADRP veneers because the distance between
 * any two addresses in a single userspace process fits comfortably inside
 * a 26-bit branch offset on modern 64-bit Linux (mmap base > 512 MB,
 * but module area is allocated nearby via vmalloc-equivalent).
 *
 * We therefore implement apply_relocate_add() from scratch, using only
 * the standard AArch64 ELF relocation types that GCC/clang actually emit
 * for kernel modules.  Helper logic is adapted from
 * arch/arm64/kernel/module.c (same SPDX, same author lineage).
 */

#include <linux/elf.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleloader.h>

enum aarch64_reloc_op {
	RELOC_OP_ABS,
	RELOC_OP_PREL,
	RELOC_OP_PAGE,
};

static s64 do_reloc(enum aarch64_reloc_op op, __le32 *place, u64 val)
{
	switch (op) {
	case RELOC_OP_ABS:  return (s64)val;
	case RELOC_OP_PREL: return (s64)(val - (u64)place);
	case RELOC_OP_PAGE: return (s64)((val & ~0xfffULL) -
					 ((u64)place & ~0xfffULL));
	}
	return 0;
}

static int reloc_data(enum aarch64_reloc_op op, void *place, u64 val, int len)
{
	s64 sval = do_reloc(op, place, val);

	switch (len) {
	case 16:
		*(s16 *)place = sval;
		if (op == RELOC_OP_ABS && (sval < 0 || sval > U16_MAX))
			return -ERANGE;
		if (op == RELOC_OP_PREL && (sval < S16_MIN || sval > S16_MAX))
			return -ERANGE;
		break;
	case 32:
		*(s32 *)place = sval;
		if (op == RELOC_OP_ABS && (sval < 0 || sval > U32_MAX))
			return -ERANGE;
		if (op == RELOC_OP_PREL && (sval < S32_MIN || sval > S32_MAX))
			return -ERANGE;
		break;
	case 64:
		*(s64 *)place = sval;
		break;
	default:
		return -EINVAL;
	}
	return 0;
}

/*
 * Encode a 26-bit PC-relative branch offset (CALL26 / JUMP26).
 * In UML we assume the target is reachable — no PLT needed.
 */
static int reloc_insn_imm26(__le32 *place, u64 val)
{
	s64 sval = (s64)(val - (u64)place) >> 2;
	u32 insn = le32_to_cpu(*place);

	if (sval < -(1 << 25) || sval >= (1 << 25))
		return -ERANGE;

	insn = (insn & ~0x03ffffffU) | ((u32)sval & 0x03ffffffU);
	*place = cpu_to_le32(insn);
	return 0;
}

int apply_relocate_add(Elf64_Shdr *sechdrs,
		       const char *strtab,
		       unsigned int symindex,
		       unsigned int relsec,
		       struct module *me)
{
	unsigned int i;
	Elf64_Rela *rel = (void *)sechdrs[relsec].sh_addr;

	for (i = 0; i < sechdrs[relsec].sh_size / sizeof(*rel); i++) {
		void *loc = (void *)sechdrs[sechdrs[relsec].sh_info].sh_addr
				+ rel[i].r_offset;
		Elf64_Sym *sym = (Elf64_Sym *)sechdrs[symindex].sh_addr
				+ ELF64_R_SYM(rel[i].r_info);
		u64 val = sym->st_value + rel[i].r_addend;
		int ovf = 0;

		switch (ELF64_R_TYPE(rel[i].r_info)) {
		/* Null */
		case R_ARM_NONE:
		case R_AARCH64_NONE:
			break;

		/* 64-bit absolute */
		case R_AARCH64_ABS64:
			ovf = reloc_data(RELOC_OP_ABS, loc, val, 64);
			break;

		/* 32-bit absolute / PC-relative */
		case R_AARCH64_ABS32:
			ovf = reloc_data(RELOC_OP_ABS, loc, val, 32);
			break;
		case R_AARCH64_ABS16:
			ovf = reloc_data(RELOC_OP_ABS, loc, val, 16);
			break;
		case R_AARCH64_PREL64:
			ovf = reloc_data(RELOC_OP_PREL, loc, val, 64);
			break;
		case R_AARCH64_PREL32:
			ovf = reloc_data(RELOC_OP_PREL, loc, val, 32);
			break;
		case R_AARCH64_PREL16:
			ovf = reloc_data(RELOC_OP_PREL, loc, val, 16);
			break;

		/* Branch instructions — no PLT in UML */
		case R_AARCH64_JUMP26:
		case R_AARCH64_CALL26:
			ovf = reloc_insn_imm26(loc, val);
			break;

		default:
			pr_err("%s: unsupported RELA reloc %llu\n",
			       me->name, ELF64_R_TYPE(rel[i].r_info));
			return -ENOEXEC;
		}

		if (ovf == -ERANGE) {
			pr_err("%s: relocation overflow type %llu val %#llx\n",
			       me->name, ELF64_R_TYPE(rel[i].r_info), val);
			return -ENOEXEC;
		}
	}
	return 0;
}
