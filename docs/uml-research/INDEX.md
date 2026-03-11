# UML Documentation — Scraped & Converted

**Archived:** 2026-03-10

This folder contains documentation from the User Mode Linux SourceForge site
and the official Linux kernel docs, converted from HTML to clean Markdown.

---

## Files

| # | File | Sources | Notes |
|---|------|---------|-------|
| 1 | [01_compiling-and-switches.md](./01_compiling-and-switches.md) | compile.html + switches.html | **Merged** — build + runtime config |
| 2 | [02_porting-to-new-architecture.md](./02_porting-to-new-architecture.md) | arch-port.html | Standalone |
| 3 | [03_creating-filesystems.md](./03_creating-filesystems.md) | fs_making.html | Standalone |
| 4 | [04_uml-howto-v2-kernel-org.md](./04_uml-howto-v2-kernel-org.md) | kernel.org (Linux v6.6) | Standalone — modern reference |

---

## Merge Decisions

### Merged: `01_compiling-and-switches.md`

**Pages combined:**
- `compile.html` — Step-by-step UML kernel compilation guide
- `switches.html` — Reference for all UML kernel command-line parameters

**Reason:** Compilation and runtime configuration are sequential steps in the same
workflow. The user first builds the kernel (compile.html), then runs it using
the switches documented in switches.html. Merging them creates a self-contained
"build and run" guide.

### Standalone: `02_porting-to-new-architecture.md`

**Page:** `arch-port.html`

Architecture porting is a kernel developer task entirely separate from end-user
compilation. It describes modifying UML internals to support a new CPU ISA.

### Standalone: `03_creating-filesystems.md`

**Page:** `fs_making.html`

Filesystem creation is an independent task — users need root filesystems
to boot UML, but this is separate from compiling or configuring the kernel.

### Standalone: `04_uml-howto-v2-kernel-org.md`

**Page:** kernel.org v6.6 HOWTO v2

This is the authoritative modern reference from the Linux kernel source tree.
It covers a superset of the SourceForge docs (build + config + networking + etc.)
for modern kernels (5.x+). It stands alone as the primary reference document.

---

## Original Sources

| URL | Notes |
|-----|-------|
| https://user-mode-linux.sourceforge.net/old/compile.html | Compilation guide (2.4/2.6 era) |
| https://user-mode-linux.sourceforge.net/old/switches.html | CLI switch reference |
| https://user-mode-linux.sourceforge.net/old/arch-port.html | Architecture porting guide |
| https://user-mode-linux.sourceforge.net/old/fs_making.html | Filesystem creation guide |
| https://www.kernel.org/doc/html/v6.6/virt/uml/user_mode_linux_howto_v2.html | Official modern HOWTO |
