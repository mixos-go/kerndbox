# SPDX-License-Identifier: GPL-2.0-only
# arch/arm64/um/vdso/Makefile

# vDSO is a user-space PIC shared library compiled with kernel source access.
# Follow the same pattern as arch/x86/um/vdso/Makefile.

# Objects that make up the vDSO .so
vobjs-y := vdso-note.o um_vdso.o

# Kernel-side: embed vdso.so binary + VMA mapping
obj-y := vdso.o vma.o

vobjs := $(foreach F,$(vobjs-y),$(obj)/$F)

targets += vdso.so vdso.so.dbg $(vobjs-y)

CPPFLAGS_vdso.lds.tmp = -P -C -U$(ARCH)

VDSO_LDFLAGS = -fPIC -shared -Wl,--hash-style=sysv \
               -Wl,--build-id=sha1 \
               -Wl,-z,max-page-size=4096 \
               -z noexecstack

VDSO_LDFLAGS_vdso.lds = -Wl,-soname=linux-vdso.so.1

# Compiler flags for vDSO objects.
# -mcmodel=small: arm64 gcc does not support -mcmodel=large with -fPIC.
#                 Kernel injects -mcmodel=large via KBUILD_CFLAGS; remove it.
# -fPIC / -shared: required for a position-independent shared library.
# Do NOT use c_flags := (override) — that strips all -I include paths and
# breaks linux/time.h includes (clockid_t undefined). Use KBUILD_CFLAGS +=.
CFL := -mcmodel=small -fPIC -O2 -fasynchronous-unwind-tables \
       -fno-stack-protector -fno-omit-frame-pointer \
       $(filter -g%, $(KBUILD_CFLAGS))

$(vobjs): KBUILD_CFLAGS := $(filter-out -mcmodel=large -mcmodel=kernel, \
                             $(KBUILD_CFLAGS)) $(CFL)

CFLAGS_REMOVE_vdso-note.o = -pg -fprofile-arcs -ftest-coverage
CFLAGS_REMOVE_um_vdso.o   = -pg -fprofile-arcs -ftest-coverage

$(obj)/vdso.o: $(obj)/vdso.so

$(obj)/vdso.so.dbg: $(obj)/vdso.lds.tmp $(vobjs) FORCE
	$(call if_changed,vdso_ld)

$(obj)/%.so: OBJCOPYFLAGS := -S
$(obj)/%.so: $(obj)/%.so.dbg FORCE
	$(call if_changed,objcopy)

quiet_cmd_vdso_ld = VDSO    $@
      cmd_vdso_ld = $(CC) -nostdlib $(VDSO_LDFLAGS) \
                    $(VDSO_LDFLAGS_$(filter %.lds,$(^F))) \
                    -T $(filter %.lds.tmp,$^) $(filter %.o,$^) -o $@

$(obj)/vdso.lds.tmp: $(src)/vdso.lds.S FORCE
	$(call if_changed_dep,cpp_lds_S)
