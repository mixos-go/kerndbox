# User Mode Linux (UML) — Complete Download Archive

**Source:** https://user-mode-linux.sourceforge.net/old/dl-sf.html  
**Archived:** 2026-03-10  
**SourceForge Project:** https://sourceforge.net/projects/user-mode-linux/

---

## About User Mode Linux

User Mode Linux (UML) allows you to run a Linux kernel as a user-space process
on another Linux system. It is useful for kernel development, testing, and
creating lightweight virtual machines.

---

## Archive Contents

| Folder | Contents | Count |
|--------|----------|-------|
| `patches/01_kernel-uml-patches/` | UML kernel patches (.bz2) | 16 files |
| `patches/02_host-skas-patches/` | Host SKAS patches (.patch) | 8 files |
| `patches/03_host-devanon-patches/` | Host /dev/anon patches (.patch) | 2 files |
| `utilities/` | UML userspace utilities (latest 3 versions) | 3 files |
| `tests/` | UML test suites | 3 files |
| `jails/` | jail_dns packages | 2 files |
| `rootfs/` | Root filesystem placeholders (.txt) | 34 files |
| `kernels/` | Prebuilt kernel placeholders (.txt) | 22 files |
| `changelogs/` | Per-file changelogs (Markdown) | 323 files |
| `docs/` | Download pages converted to Markdown | 10 files |

---

## Patches

### UML Kernel Patches (`patches/01_kernel-uml-patches/`)

These patches apply the UML (User Mode Linux) changes to a vanilla Linux kernel source tree.

| File | Kernel Version |
|------|---------------|
| uml-patch-2.4.19-1.bz2 | Linux 2.4.19 |
| uml-patch-2.4.20-6.bz2 | Linux 2.4.20 |
| uml-patch-2.4.21-5.bz2 | Linux 2.4.21 |
| uml-patch-2.4.22-5.bz2 | Linux 2.4.22 |
| uml-patch-2.4.23-2.bz2 | Linux 2.4.23 |
| uml-patch-2.4.24-3.bz2 | Linux 2.4.24 |
| uml-patch-2.4.25-1.bz2 | Linux 2.4.25 |
| uml-patch-2.4.26-1.bz2 | Linux 2.4.26 (release 1) |
| uml-patch-2.4.26-2.bz2 | Linux 2.4.26 (release 2) |
| uml-patch-2.4.26-3.bz2 | Linux 2.4.26 (release 3) |
| uml-patch-2.4.27-1.bz2 | Linux 2.4.27 |
| uml-patch-2.6.6-1.bz2 | Linux 2.6.6 |
| uml-patch-2.6.7-1.bz2 | Linux 2.6.7 (release 1) |
| uml-patch-2.6.7-2.bz2 | Linux 2.6.7 (release 2) |
| uml-patch-2.6.8.1-1.bz2 | Linux 2.6.8.1 |
| uml-patch-x86-64-2.6.4.bz2 | Linux 2.6.4 (x86-64) |

### Host SKAS Patches (`patches/02_host-skas-patches/`)

SKAS (Separate Kernel Address Space) mode patches improve UML performance
and security by giving UML its own kernel address space on the host.

| File | Description |
|------|-------------|
| host-skas1.patch | SKAS version 1 |
| host-skas2.patch | SKAS version 2 |
| host-skas3.patch | SKAS version 3 (baseline) |
| host-skas3-2.4.25.patch | SKAS3 for kernel 2.4.25 |
| host-skas3-2.6.3-v1.patch | SKAS3 for kernel 2.6.3 |
| host-skas3-2.6.6-v1.patch | SKAS3 for kernel 2.6.6 |
| host-skas3-2.6.7-v1.patch | SKAS3 for kernel 2.6.7 |
| host-skas3a-RH8.patch | SKAS3a for Red Hat 8 |

### Host /dev/anon Patches (`patches/03_host-devanon-patches/`)

The /dev/anon driver allows UML to map physical memory more efficiently,
freeing host memory when not needed.

| File | Description |
|------|-------------|
| devanon-2.4.23.patch | /dev/anon for kernel 2.4.23 |
| devanon-RH8.patch | /dev/anon for Red Hat 8 kernel |

---

## Root Filesystems (`rootfs/`)

> **Note:** Root filesystem images are large binary files (100MB–500MB each).
> Each file in this folder is a **placeholder (.txt)** containing the
> original download URL.

Distributions included:

- Debian 3.0 (Woody) — full ext2 image
- Mandrake 8.1 and 8.2 (various server/client/DNS/email configurations)
- Red Hat 7.2 and 6.2 (various configurations)
- Cobalt OS 6.0
- Slackware 8.1
- Tom's Root/Boot (tiny)
- Debian 2.2 (small)

To download, use `wget` with the URL found in each .txt placeholder file.

---

## Prebuilt Kernels (`kernels/`)

> **Note:** Prebuilt UML kernel binaries are large files.
> Each file in this folder is a **placeholder (.txt)** with the download URL.

Covers kernels 2.4.0 through 2.4.19.

---

## Utilities (`utilities/`)

UML userspace tools (uml_switch, mconsole, etc.) — latest 3 releases included.

---

## Tests (`tests/`)

UML test suites for verifying kernel functionality.

---

## Changelogs (`changelogs/`)

323 changelog files converted from HTML to Markdown.
One changelog per file, covering patches, rootfs images, utilities, and tests.

---

## Documentation (`docs/`)

Original download listing pages from the UML SourceForge site,
saved as both HTML and Markdown:

- `dl-sf.md` — Main download page (this archive's source)
- `dl-2.4-patches-sf.md` — Full list of 2.4.x patches
- `dl-2.5-patches-sf.md` — Full list of 2.5.x patches
- `dl-fs-sf.md` — Full filesystem images list
- `dl-kernels-sf.md` — Full prebuilt kernels list
- `dl-tools-sf.md` — Full utilities list
- `dl-tests-sf.md` — Full test suites list
- `dl-jails-sf.md` — Jail packages list
- `dl-host-patches-sf.md` — Host patches list
- `dl-host-devanon-sf.md` — /dev/anon patches list

---

## Usage

### Applying a Kernel Patch

```bash
# Download vanilla kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v2.4/linux-2.4.27.tar.bz2
tar xjf linux-2.4.27.tar.bz2

# Apply UML patch
bzcat patches/01_kernel-uml-patches/uml-patch-2.4.27-1.bz2 | patch -p1 -d linux-2.4.27/

# Build
cd linux-2.4.27
make defconfig ARCH=um
make linux ARCH=um
```

### Applying a Host SKAS Patch

```bash
# Apply to your host kernel source tree
patch -p1 < patches/02_host-skas-patches/host-skas3-2.6.7-v1.patch
```

---

## Links

- SourceForge Project: https://sourceforge.net/projects/user-mode-linux/
- Original download page: https://user-mode-linux.sourceforge.net/old/dl-sf.html
- UML HOWTO: https://user-mode-linux.sourceforge.net/old/UserModeLinux-HOWTO.html

---

_Archive generated Tue, 10 Mar 2026 18:30:12 GMT_
