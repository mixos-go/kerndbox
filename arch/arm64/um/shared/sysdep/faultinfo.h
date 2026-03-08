/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __FAULTINFO_ARM64_H
#define __FAULTINFO_ARM64_H

/*
 * arm64 fault info.
 * On arm64 there is no CR2 equivalent accessible from userspace ptrace;
 * the fault address comes from siginfo.si_addr delivered to the UML process.
 * PTRACE_FULL_FAULTINFO=1 means UML will call get_skas_faultinfo() which
 * delivers SIGSEGV to the stub and reads the fault address from the stub
 * data page (filled in by stub_segv_handler).
 */
struct faultinfo {
	int error_code;          /* ESR_EL1 syndrome bits (is_write in ptrace) */
	unsigned long fault_address; /* FAR_EL1 equivalent, from si_addr */
	int trap_no;             /* always 0 on arm64 UML */
};

#define FAULT_WRITE(fi)        ((fi).error_code & 2)
#define FAULT_ADDRESS(fi)      ((fi).fault_address)

/* Data Abort (page fault) instruction class on arm64 */
#define SEGV_IS_FIXABLE(fi)    ((fi)->trap_no == 0)

/*
 * PTRACE_FULL_FAULTINFO=1: UML will use get_skas_faultinfo() path,
 * delivering SIGSEGV to the stub so the stub_segv_handler fills in
 * the faultinfo on the stub data page.
 */
#define PTRACE_FULL_FAULTINFO  1

#endif /* __FAULTINFO_ARM64_H */
