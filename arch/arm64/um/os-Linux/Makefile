# SPDX-License-Identifier: GPL-2.0
#
# arch/arm64/um/os-Linux/Makefile
#
# All host-side C replaced by Rust staticlib (libarm64_um_os.a).
# Built by build-arm64.sh (cargo build --release) and placed here
# before kernel make runs.

# Link the Rust staticlib
EXTRA_LDFLAGS += -L$(obj) -larm64_um_os

# helpers_embed_user.c: userspace stub, still C, compiled as USER_OBJ
obj-y      := helpers_embed_user.o
USER_OBJS  := helpers_embed_user.o

include $(srctree)/arch/um/scripts/Makefile.rules
