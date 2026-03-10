# SPDX-License-Identifier: GPL-2.0-only
# arch/arm64/um/vdso/Makefile

# Objects that make up the vDSO .so
vobjs-y := vdso-note.o um_vdso.o

# Kernel-side: embed vdso.so binary + VMA mapping
obj-y := vdso.o vma.o

vobjs := $(foreach F,$(vobjs-y),$(obj)/$F)

targets += vdso.so vdso.so.dbg $(vobjs-y)

VDSO_LDFLAGS = -fPIC -shared \
               -Wl,--hash-style=sysv \
               -Wl,--build-id=sha1 \
               -Wl,-soname=linux-vdso.so.1 \
               -Wl,-z,max-page-size=4096 \
               -z noexecstack

# vDSO objects need -mcmodel=small (kernel injects -mcmodel=large which
# is incompatible with -fPIC on aarch64) and full include paths for
# linux/time.h etc. Use KBUILD_CFLAGS filter+append, NOT c_flags := override.
CFL := -mcmodel=small -fPIC -O2 -fasynchronous-unwind-tables \
       -fno-stack-protector -fno-omit-frame-pointer \
       $(filter -g%, $(KBUILD_CFLAGS))

$(vobjs): KBUILD_CFLAGS := $(filter-out -mcmodel=large -mcmodel=kernel, \
                             $(KBUILD_CFLAGS)) $(CFL)

CFLAGS_REMOVE_vdso-note.o = -pg -fprofile-arcs -ftest-coverage
CFLAGS_REMOVE_um_vdso.o   = -pg -fprofile-arcs -ftest-coverage

$(obj)/vdso.o: $(obj)/vdso.so

$(obj)/vdso.so.dbg: $(src)/vdso.lds $(vobjs) FORCE
	$(call if_changed,vdso_ld)

$(obj)/%.so: OBJCOPYFLAGS := -S
$(obj)/%.so: $(obj)/%.so.dbg FORCE
	$(call if_changed,objcopy)

quiet_cmd_vdso_ld = VDSO    $@
      cmd_vdso_ld = $(CC) -nostdlib $(VDSO_LDFLAGS) \
                    -T $(filter %.lds,$^) $(filter %.o,$^) -o $@
