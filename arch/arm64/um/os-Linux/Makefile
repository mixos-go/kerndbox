# SPDX-License-Identifier: GPL-2.0
#
# arch/arm64/um/os-Linux/Makefile
#
# Preferred: Rust staticlib (libarm64_um_os.a) built by build-arm64.sh.
# Fallback: C implementations for CI environments without Rust.

# If Rust staticlib was pre-built and placed here, link it.
# Otherwise fall back to C files (legacy path).
RUST_LIB := $(obj)/libarm64_um_os.a

ifneq ($(wildcard $(RUST_LIB)),)
# Rust path: link staticlib, only need helpers_embed_user.c
EXTRA_LDFLAGS += -L$(obj) -larm64_um_os
obj-y     := helpers_embed_user.o
USER_OBJS := helpers_embed_user.o
else
# C fallback path
obj-y = registers.o \
        tls.o \
        signal.o \
        mcontext.o \
        prctl.o \
        uaccess.o \
        helpers_embed_user.o

USER_OBJS := $(obj-y)
endif

include $(srctree)/arch/um/scripts/Makefile.rules
