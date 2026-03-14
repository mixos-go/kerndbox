// SPDX-License-Identifier: GPL-2.0
/* C fallback — replaced by Rust (rust/src/tls.rs) */
#include <errno.h>
#include <sys/ptrace.h>
#include <sys/uio.h>
#ifndef NT_ARM_TLS
#define NT_ARM_TLS 0x401
#endif
int os_set_tls(int pid, unsigned long tls) {
    struct iovec iov = { &tls, sizeof(tls) };
    if (ptrace(PTRACE_SETREGSET, pid, (void *)(long)NT_ARM_TLS, &iov) < 0)
        return -errno;
    return 0;
}
