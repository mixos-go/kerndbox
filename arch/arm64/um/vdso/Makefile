# SPDX-License-Identifier: GPL-2.0-only
# arch/arm64/um/vdso/Makefile
# Build UML arm64 vDSO shared object and embed it into the kernel image.
# Adapted from arch/x86/um/vdso/Makefile.

KBUILD_CFLAGS_REMOVE := -pg -fstack-protector -fstack-protector-strong \
                         $(CC_FLAGS_CFI) \
                         -mcmodel=large -mcmodel=kernel
# vDSO is a user-space PIC shared library — must use small code model.
# Kernel KBUILD_CFLAGS injects -mcmodel=large which is incompatible with -fPIC
# on aarch64 (cc1: sorry, unimplemented: code model 'large' with '-fPIC').
# Upstream arm64 vDSO uses -mcmodel=tiny; small is safer across gcc versions.
KBUILD_CFLAGS += -mcmodel=small

# vDSO is a user-space shared library — build with user-space flags
CPPFLAGS_vdso.lds.tmp = -P -C -U$(ARCH)

# Objects that make up the vDSO binary
obj-vdso := vdso-note.o um_vdso.o

# Build the vDSO shared object
$(obj)/vdso.so: $(obj)/vdso.lds.tmp $(addprefix $(obj)/,$(obj-vdso)) FORCE
	$(call if_changed,vdso_ld)

targets += vdso.so vdso.so.dbg vdso.lds.tmp $(obj-vdso)

# Kernel-side objects: embed vdso.so + VMA management
obj-y := vdso.o vma.o
$(obj)/vdso.o: $(obj)/vdso.so

# Rules to compile vDSO objects with USER_CFLAGS (no kernel defines)
$(obj)/um_vdso.o: c_flags := -Wp,-MD,$(depfile) $(USER_CFLAGS) \
	-shared -fPIC -nostdlib -fno-stack-protector \
	-mcmodel=small \
	-Wl,-soname=linux-vdso.so.1,-z,max-page-size=4096

# Linker command to produce the vDSO .so
quiet_cmd_vdso_ld = VDSO    $@
      cmd_vdso_ld = $(CC) -nostdlib -shared -Wl,-soname=linux-vdso.so.1 \
                    -Wl,--hash-style=sysv \
                    -Wl,--build-id=sha1 \
                    -Wl,-z,max-page-size=4096 \
                    -T $(word 1,$^) $(filter-out FORCE,$^) -o $@

$(obj)/vdso.lds.tmp: $(src)/vdso.lds.S FORCE
	$(call if_changed_dep,cpp_lds_S)
