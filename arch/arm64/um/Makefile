# SPDX-License-Identifier: GPL-2.0
obj-y = bugs.o \
        fault.o \
        mem.o \
        ptrace.o \
        delay.o \
        setjmp.o \
        signal.o \
        stub_segv.o \
        sys_call_table.o \
        syscalls.o \
        sysrq.o \
        task_size.o \
        tls.o \
        module.o

obj-y  += os-Linux/
obj-y  += vdso/

# stub_segv is mapped into every child process - must not be PIC or profiled
UNPROFILE_OBJS := stub_segv.o
CFLAGS_stub_segv.o := $(CFLAGS_NO_HARDENING)

# Files compiled with USER_CFLAGS (interact directly with host userspace ABI)
USER_OBJS := bugs.o fault.o task_size.o

# Generate user_constants.h from user-offsets.s (same mechanism as x86/um)
$(obj)/user-offsets.s: c_flags = -Wp,-MD,$(depfile) $(USER_CFLAGS) \
	-Iarch/arm64/include/generated
targets += user-offsets.s

include/generated/user_constants.h: $(obj)/user-offsets.s FORCE
	$(call filechk,offsets,__USER_CONSTANT_H__)

# archheaders: generate arm64-specific headers (cpucap-defs.h, sysreg-defs.h)
# called by arch/um/Makefile archheaders rule via ARCH=$(HEADER_ARCH)
archheaders:
	$(Q)$(MAKE) $(build)=arch/arm64/tools kapi

include $(srctree)/arch/um/scripts/Makefile.rules
