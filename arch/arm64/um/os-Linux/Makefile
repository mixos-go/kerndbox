# SPDX-License-Identifier: GPL-2.0
#
# arch/arm64/um/os-Linux/Makefile
#
# Host-side (userspace) code for arm64 UML.
# If Rust staticlib (libarm64_um_os.a) is pre-built by build-arm64.sh,
# use it. Otherwise fall back to C implementations.

RUST_LIB := $(obj)/libarm64_um_os.a

ifneq ($(wildcard $(RUST_LIB)),)
# Rust path — all symbols from staticlib
EXTRA_LDFLAGS += -L$(obj) -larm64_um_os
obj-y     :=
USER_OBJS :=
else
# C fallback path
obj-y = registers.o \
        tls.o \
        signal.o \
        mcontext.o \
        prctl.o \
        uaccess.o

USER_OBJS := $(obj-y)
endif

include $(srctree)/arch/um/scripts/Makefile.rules
