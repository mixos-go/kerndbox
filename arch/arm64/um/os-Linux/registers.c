// SPDX-License-Identifier: GPL-2.0
/* C fallback — replaced by Rust (rust/src/ptrace.rs) when libarm64_um_os.a available */
#include <errno.h>
#include <string.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#include <elf.h>
#include "os.h"
#include <sysdep/ptrace.h>
#include <registers.h>

#ifndef NT_PRSTATUS
#define NT_PRSTATUS 1
#endif
#ifndef NT_PRFPREG
#define NT_PRFPREG 2
#endif

int save_registers(int pid, struct uml_pt_regs *regs) {
    struct iovec iov = { regs->gp, sizeof(regs->gp) };
    if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
        return -errno;
    return 0;
}
int restore_registers(int pid, struct uml_pt_regs *regs) {
    struct iovec iov = { regs->gp, sizeof(regs->gp) };
    if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
        return -errno;
    return 0;
}
int ptrace_getregs(long pid, unsigned long *regs_out) {
    struct iovec iov = { regs_out, 34 * sizeof(unsigned long long) };
    if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
        return -errno;
    return 0;
}
int ptrace_setregs(long pid, unsigned long *regs_in) {
    struct iovec iov = { (void *)regs_in, 34 * sizeof(unsigned long long) };
    if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRSTATUS, &iov) < 0)
        return -errno;
    return 0;
}
int get_fp_registers(int pid, unsigned long *regs) {
    struct iovec iov = { regs, 65 * sizeof(unsigned long) };
    if (ptrace(PTRACE_GETREGSET, pid, (void *)(long)NT_PRFPREG, &iov) < 0)
        return -errno;
    return 0;
}
int put_fp_registers(int pid, unsigned long *regs) {
    struct iovec iov = { regs, 65 * sizeof(unsigned long) };
    if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_PRFPREG, &iov) < 0)
        return -errno;
    return 0;
}
void get_safe_registers(unsigned long *regs, unsigned long *fp_regs) {
    if (regs)    memset(regs,    0, 34 * sizeof(unsigned long));
    if (fp_regs) memset(fp_regs, 0, 65 * sizeof(unsigned long));
}
void arch_init_registers(int pid) { (void)pid; }
unsigned long get_thread_reg(int reg, jmp_buf *buf) {
    /* JB_IP=11, JB_SP=12 for arm64 glibc jmp_buf */
    switch (reg) {
    case 32: return ((unsigned long *)buf)[11]; /* HOST_PC */
    case 31: return ((unsigned long *)buf)[12]; /* HOST_SP */
    default: return 0;
    }
}
