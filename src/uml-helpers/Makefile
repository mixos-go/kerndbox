# UML helper utilities — statically linked for embedding in kernel ELF
#
# KERNEL-CALLED (must embed — kernel exec()s these at runtime):
#   port-helper    — console bridge for port:/xterm: channels
#   uml_watchdog   — hardware watchdog daemon
#
# OPERATOR TOOLS (embed for self-contained binary convenience):
#   uml_mconsole   — management console client
#   uml_mkcow      — create COW disk images
#   tunctl         — create/delete TAP devices
#
# NOTE: uml_switch is built from kernel tools/uml/ (not here)
#       uml_net requires setuid root — cannot embed usefully

CC      ?= gcc
CFLAGS  := -O2 -Wall -static -fno-pie -no-pie
LDFLAGS := -static

# kernel-called: MUST be present for UML to function correctly
KERNEL_HELPERS := port-helper uml_watchdog

# operator tools: useful but not strictly required
OPERATOR_TOOLS := uml_mconsole uml_mkcow tunctl

ALL_HELPERS := $(KERNEL_HELPERS) $(OPERATOR_TOOLS)

.PHONY: all kernel-helpers clean

all: $(ALL_HELPERS)

kernel-helpers: $(KERNEL_HELPERS)

port-helper:   port-helper.c
uml_watchdog:  uml_watchdog.c
uml_mconsole:  uml_mconsole.c
uml_mkcow:     uml_mkcow.c
tunctl:        tunctl.c

$(ALL_HELPERS):
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)
	strip $@
	@echo "  ✓ $@ ($(shell wc -c < $@) bytes)"

clean:
	rm -f $(ALL_HELPERS)
