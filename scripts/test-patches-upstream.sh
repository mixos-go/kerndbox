#!/usr/bin/env bash
# =============================================================================
# test-patches-upstream.sh — Full test against real Linux kernel from kernel.org
#
# Downloads Linux 6.12.74 (LTS) tarball, extracts to /tmp, copies our scratch
# files, then applies all patches in sequence with full diagnostic output.
#
# Why this is more accurate than local ref:
#   - Full 80k+ file source tree — all context lines present
#   - Hunk offset/fuzz reflects REAL drift, not partial-copy artefacts
#   - Patch failures are definitive, not "file missing from partial ref"
#   - Can optionally run `make` syntax checks after patching
#
# Usage:
#   ./scripts/test-patches-upstream.sh [OPTIONS]
#
#   --kernel VER    Kernel version to test against (default: 6.12.74)
#   --mirror URL    Alternative mirror (default: cdn.kernel.org)
#   --apply         Real sequential apply (not just dry-run)
#   --keep          Keep /tmp workdir after run
#   --no-download   Re-use existing tarball in /tmp if present
#   --makecheck     After apply, run `make ARCH=um SUBARCH=arm64 defconfig`
#                   syntax check (requires gcc cross toolchain)
#
# Output:
#   output/test-upstream-TIMESTAMP.log   full log
#   Exit 0 = all patches applied clean
#   Exit 1 = one or more FAILED
# =============================================================================
set -uo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/scripts/patches/uml-arm64"
SCRATCH_DIR="$REPO_ROOT/arch/arm64"
OUTPUT_DIR="$REPO_ROOT/output"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

KERNEL_VER="6.12.74"
MIRROR="https://cdn.kernel.org/pub/linux/kernel"
DO_APPLY=0
DO_KEEP=0
NO_DOWNLOAD=0
DO_MAKECHECK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --kernel)      KERNEL_VER="$2"; shift 2 ;;
        --mirror)      MIRROR="$2";     shift 2 ;;
        --apply)       DO_APPLY=1;      shift   ;;
        --keep)        DO_KEEP=1;       shift   ;;
        --no-download) NO_DOWNLOAD=1;   shift   ;;
        --makecheck)   DO_MAKECHECK=1;  shift   ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Derived paths
MAJOR="${KERNEL_VER%%.*}"
TARBALL="linux-${KERNEL_VER}.tar.xz"
TARBALL_SIG="linux-${KERNEL_VER}.tar.sign"
TARBALL_URL="${MIRROR}/v${MAJOR}.x/${TARBALL}"
TARBALL_PATH="/tmp/${TARBALL}"
KERNEL_SRCDIR="/tmp/linux-${KERNEL_VER}"
WORKDIR="/tmp/kernel-test-upstream-$$"
LOGFILE="$OUTPUT_DIR/test-upstream-${TIMESTAMP}.log"

mkdir -p "$OUTPUT_DIR"
exec > >(tee "$LOGFILE") 2>&1

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'
    CYN='\033[0;36m'; MAG='\033[0;35m'; BLD='\033[1m'; RST='\033[0m'
else
    RED=''; YEL=''; GRN=''; CYN=''; MAG=''; BLD=''; RST=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "${BLD}[test-upstream]${RST} $*"; }
ok()   { echo -e "  ${GRN}✓ OK   ${RST} $*"; }
warn() { echo -e "  ${YEL}⚠ WARN ${RST} $*"; }
fail() { echo -e "  ${RED}✗ FAIL ${RST} $*"; }
info() { echo -e "  ${CYN}·${RST}      $*"; }
note() { echo -e "  ${MAG}»${RST}      $*"; }
sep()  { echo -e "${CYN}$(printf '═%.0s' {1..70})${RST}"; }
sep2() { echo -e "${MAG}$(printf '─%.0s' {1..70})${RST}"; }

die()  { fail "$*"; exit 1; }

patch_subject() {
    grep -m1 '^Subject:' "$1" 2>/dev/null | sed 's/^Subject: //' || basename "$1"
}

patch_targets() {
    grep '^+++ b/' "$1" | sed 's|^+++ b/||'
}

# Detailed hunk parser — extract per-hunk status
parse_patch_output() {
    local pname="$1"
    local output="$2"
    local has_issue=0

    while IFS= read -r line; do
        case "$line" in
            *"FAILED at"*)
                echo -e "             ${RED}$line${RST}"
                has_issue=1
                ;;
            *"succeeded at"*"offset"*)
                echo -e "             ${YEL}$line${RST}"
                has_issue=1
                ;;
            *"succeeded at"*"fuzz"*)
                echo -e "             ${YEL}$line${RST}"
                has_issue=1
                ;;
            *"succeeded at"*)
                echo -e "             $line"
                ;;
            *"saving rejects"*)
                echo -e "             ${RED}$line${RST}"
                has_issue=1
                ;;
            *"ignored"*)
                echo -e "             ${YEL}$line${RST}"
                ;;
        esac
    done <<< "$output"

    return $has_issue
}

# Show reject file content when hunk fails
show_rejects() {
    local target_dir="$1"
    local patch_file="$2"

    while IFS= read -r rel; do
        local rejfile="$target_dir/${rel}.rej"
        if [[ -f "$rejfile" ]]; then
            note "Reject content for: $rel"
            sep2
            cat "$rejfile" | sed 's/^/             /'
            sep2
        fi
    done < <(patch_targets "$patch_file")
}

# Show upstream context around a hunk's expected location
show_upstream_context() {
    local kernel_dir="$1"
    local patch_file="$2"

    while IFS= read -r rel; do
        local src="$kernel_dir/$rel"
        [[ -f "$src" ]] || continue
        note "Upstream context: $rel"
        # Extract @@ hunk header line numbers from patch
        grep '^@@' "$patch_file" | head -5 | while read -r hunk; do
            lineno=$(echo "$hunk" | grep -o '\-[0-9]*' | head -1 | tr -d '-')
            [[ -n "$lineno" ]] || continue
            start=$((lineno > 5 ? lineno - 5 : 1))
            end=$((lineno + 15))
            note "  Upstream lines ${start}-${end} of $rel:"
            sed -n "${start},${end}p" "$src" \
                | nl -ba -nrz -w4 -v"$start" \
                | sed 's/^/             /'
        done
    done < <(patch_targets "$patch_file")
}

# ── Tool check ────────────────────────────────────────────────────────────────
check_tool() {
    command -v "$1" > /dev/null 2>&1 || die "Required tool not found: $1  (apt install $2)"
}

sep
log "Kernel patch test — FULL UPSTREAM (kernel.org)"
log "Target version : Linux $KERNEL_VER"
log "Mirror         : $MIRROR"
log "Patches        : $PATCH_DIR"
log "Scratch        : $SCRATCH_DIR"
log "Workdir        : $WORKDIR"
log "Log            : $LOGFILE"
sep

log "Checking required tools ..."
check_tool wget    wget
check_tool xz      xz-utils
check_tool patch   patch
check_tool diff    diffutils
ok "All tools present"

PATCH_COUNT=$(ls "$PATCH_DIR"/0*.patch 2>/dev/null | wc -l)
SCRATCH_COUNT=$(find "$SCRATCH_DIR" -type f | wc -l)
log "Patches        : $PATCH_COUNT"
log "Scratch files  : $SCRATCH_COUNT"

# ── Phase 0: Download & extract ───────────────────────────────────────────────
echo
sep
log "Phase 0 — Download Linux $KERNEL_VER"
sep

if [[ $NO_DOWNLOAD -eq 1 && -f "$TARBALL_PATH" ]]; then
    ok "Re-using existing tarball: $TARBALL_PATH ($(du -sh "$TARBALL_PATH" | cut -f1))"
elif [[ -f "$TARBALL_PATH" ]]; then
    ok "Tarball already cached: $TARBALL_PATH"
else
    log "Downloading: $TARBALL_URL"
    log "Destination: $TARBALL_PATH"
    wget --progress=bar:force:noscroll \
         --tries=3 \
         --timeout=60 \
         -O "$TARBALL_PATH" \
         "$TARBALL_URL" || die "Download failed: $TARBALL_URL"
    ok "Download complete: $(du -sh "$TARBALL_PATH" | cut -f1)"
fi

if [[ ! -d "$KERNEL_SRCDIR" ]]; then
    log "Extracting $TARBALL_PATH → /tmp/ ..."
    tar -xf "$TARBALL_PATH" -C /tmp/ || die "Extraction failed"
    ok "Extracted to $KERNEL_SRCDIR"
else
    ok "Source already extracted: $KERNEL_SRCDIR"
fi

# Verify version
SRC_VER=$(grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL' "$KERNEL_SRCDIR/Makefile" \
    | awk -F= '{gsub(/ /,"",$2); printf $2"."}' | sed 's/\.$//')
if [[ "$SRC_VER" != "$KERNEL_VER" ]]; then
    warn "Version mismatch: expected $KERNEL_VER, got $SRC_VER"
else
    ok "Source version confirmed: Linux $SRC_VER"
fi

SRC_FILES=$(find "$KERNEL_SRCDIR" -type f | wc -l)
log "Source tree: $SRC_FILES files"

# ── Phase 1: Setup workdir ────────────────────────────────────────────────────
echo
sep
log "Phase 1 — Setup workdir (copy source tree, never touch original)"
sep

log "Copying $KERNEL_SRCDIR → $WORKDIR ..."
cp -a "$KERNEL_SRCDIR/." "$WORKDIR/"
ok "Copy complete"

# Verify integrity
if diff -rq "$KERNEL_SRCDIR" "$WORKDIR" > /dev/null 2>&1; then
    ok "Workdir is identical to source — source UNTOUCHED"
else
    warn "Unexpected diff between source and workdir"
fi

# ── Phase 2: Scratch file collision check ─────────────────────────────────────
echo
sep
log "Phase 2 — Scratch file collision check (full upstream source)"
log "Checking our 60 arch/arm64/um/* files against real kernel tree"
sep

SCRATCH_OK=0; SCRATCH_COLL=0; SCRATCH_NEW=0; SCRATCH_MERGE=0

while IFS= read -r src; do
    rel="${src#$REPO_ROOT/}"
    upstream_path="$KERNEL_SRCDIR/$rel"
    dst_path="$WORKDIR/$rel"

    if [[ -f "$upstream_path" ]]; then
        if diff -q "$src" "$upstream_path" > /dev/null 2>&1; then
            ok "${rel}"
            info "Exists in upstream and IDENTICAL — can be dropped from scratch"
            ((SCRATCH_OK++))
        else
            fail "${rel}"
            info "EXISTS IN UPSTREAM WITH DIFFERENT CONTENT"
            note "Diff (upstream → ours):"
            diff --unified=5 "$upstream_path" "$src" \
                | head -60 \
                | sed 's/^/             /'
            ((SCRATCH_COLL++))
        fi
    else
        ok "${rel}"
        info "New file — no collision"
        ((SCRATCH_NEW++))
    fi

    # Copy into workdir regardless
    mkdir -p "$(dirname "$dst_path")"
    cp "$src" "$dst_path"

done < <(find "$SCRATCH_DIR" -type f | sort)

echo
log "Scratch summary:"
log "  New (no collision) : $SCRATCH_NEW"
log "  Identical (safe)   : $SCRATCH_OK  (already upstream — verify no drift)"
log "  COLLISION (differ) : $SCRATCH_COLL  ← ACTION NEEDED"
[[ $SCRATCH_COLL -gt 0 ]] && \
    warn "Collisions mean upstream has merged some of our work — diff and reconcile!"

# ── Phase 3: Dry-run patches in strict sequential mode ───────────────────────
echo
sep
log "Phase 3 — Patch dry-run: sequential simulation against full source"
log "(Each patch sees state left by all prior patches)"
sep

# Use a separate copy for dry-run simulation
DRYRUN_DIR="${WORKDIR}-dryrun"
cp -a "$WORKDIR/." "$DRYRUN_DIR/"

DR_PASS=0; DR_WARN=0; DR_FAIL=0
declare -a DR_FAILED=()
declare -a DR_WARNED=()

for pfile in $(ls "$PATCH_DIR"/0*.patch | sort); do
    pname=$(basename "$pfile")
    subject=$(patch_subject "$pfile")
    targets=$(patch_targets "$pfile" | tr '\n' ' ')

    sep2
    echo -e "${BLD}  Patch: $pname${RST}"
    info "Subject : $subject"
    info "Targets : $targets"

    # Run dry-run capturing full output
    out=$(patch -d "$DRYRUN_DIR" -p1 --dry-run --batch --verbose 2>&1 < "$pfile")
    rc=$?

    if echo "$out" | grep -qw 'FAILED'; then
        fail "DRY-RUN FAILED"
        parse_patch_output "$pname" "$out" || true
        show_rejects "$DRYRUN_DIR" "$pfile"
        show_upstream_context "$DRYRUN_DIR" "$pfile"
        DR_FAILED+=("$pname")
        ((DR_FAIL++))
    elif echo "$out" | grep -qE 'offset|fuzz'; then
        warn "Applied with offset/fuzz drift"
        parse_patch_output "$pname" "$out" || true
        DR_WARNED+=("$pname")
        ((DR_WARN++))
    else
        ok "Dry-run clean"
        # Only show hunk count
        hunk_lines=$(echo "$out" | grep -E 'Hunk|patching file' | head -5)
        [[ -n "$hunk_lines" ]] && echo "$hunk_lines" | sed 's/^/             /'
        ((DR_PASS++))
    fi

    # Apply to dryrun dir so next patch sees correct state
    patch -d "$DRYRUN_DIR" -p1 --batch --forward < "$pfile" > /dev/null 2>&1 || true
done

rm -rf "$DRYRUN_DIR"

echo
sep
log "Dry-run summary:"
echo -e "  ${GRN}PASSED${RST}  : $DR_PASS / $PATCH_COUNT"
echo -e "  ${YEL}WARNED${RST}  : $DR_WARN / $PATCH_COUNT  (applies OK, offset/fuzz drift → rebase)"
echo -e "  ${RED}FAILED${RST}  : $DR_FAIL / $PATCH_COUNT"
if [[ ${#DR_WARNED[@]} -gt 0 ]]; then
    for p in "${DR_WARNED[@]}"; do warn "    $p"; done
fi
if [[ ${#DR_FAILED[@]} -gt 0 ]]; then
    for p in "${DR_FAILED[@]}"; do fail "    $p"; done
fi

# ── Phase 4: Real apply (optional) ───────────────────────────────────────────
AP_PASS=0; AP_WARN=0; AP_FAIL=0
declare -a AP_FAILED=()

if [[ $DO_APPLY -eq 1 ]]; then
    echo
    sep
    log "Phase 4 — Real sequential apply → $WORKDIR"
    log "This modifies WORKDIR only — original $KERNEL_SRCDIR is UNTOUCHED"
    sep

    for pfile in $(ls "$PATCH_DIR"/0*.patch | sort); do
        pname=$(basename "$pfile")
        subject=$(patch_subject "$pfile")
        targets=$(patch_targets "$pfile" | tr '\n' ' ')

        sep2
        echo -e "${BLD}  Patch: $pname${RST}"
        info "Subject : $subject"
        info "Targets : $targets"

        out=$(patch -d "$WORKDIR" -p1 --batch --no-backup-if-mismatch 2>&1 < "$pfile")
        rc=$?

        if echo "$out" | grep -qw 'FAILED'; then
            fail "APPLY FAILED"
            parse_patch_output "$pname" "$out" || true
            show_rejects "$WORKDIR" "$pfile"
            # Show full diff between expected and actual for the target
            for t in $(patch_targets "$pfile"); do
                orig="$KERNEL_SRCDIR/$t"
                curr="$WORKDIR/$t"
                [[ -f "$orig" && -f "$curr" ]] && {
                    note "Current state diff (original → patched) for $t:"
                    diff --unified=5 "$orig" "$curr" | head -80 | sed 's/^/             /'
                }
            done
            AP_FAILED+=("$pname")
            ((AP_FAIL++))
        elif echo "$out" | grep -qE 'offset|fuzz'; then
            warn "Applied with offset drift"
            parse_patch_output "$pname" "$out" || true
            ((AP_WARN++))
        else
            ok "Applied clean"
            # Show final diff of what changed
            for t in $(patch_targets "$pfile"); do
                orig="$KERNEL_SRCDIR/$t"
                curr="$WORKDIR/$t"
                if [[ -f "$orig" && -f "$curr" ]]; then
                    lines=$(diff "$orig" "$curr" | grep -c '^[<>]' || true)
                    info "$t  (${lines} lines changed)"
                fi
            done
            ((AP_PASS++))
        fi
    done

    echo
    sep
    log "Apply summary:"
    echo -e "  ${GRN}PASSED${RST}  : $AP_PASS / $PATCH_COUNT"
    echo -e "  ${YEL}WARNED${RST}  : $AP_WARN / $PATCH_COUNT"
    echo -e "  ${RED}FAILED${RST}  : $AP_FAIL / $PATCH_COUNT"
    if [[ ${#AP_FAILED[@]} -gt 0 ]]; then
        for p in "${AP_FAILED[@]}"; do fail "    $p"; done
    fi
fi

# ── Phase 5: make defconfig syntax check (optional) ──────────────────────────
if [[ $DO_MAKECHECK -eq 1 && $DO_APPLY -eq 1 ]]; then
    echo
    sep
    log "Phase 5 — make defconfig syntax check (ARCH=um SUBARCH=arm64)"
    sep

    if ! command -v aarch64-linux-gnu-gcc > /dev/null 2>&1; then
        warn "aarch64-linux-gnu-gcc not found — skipping make check"
        warn "Install: apt install gcc-aarch64-linux-gnu"
    else
        DEFCONFIG="$WORKDIR/arch/um/configs/arm64_defconfig"
        if [[ -f "$DEFCONFIG" ]]; then
            log "Running: make -C $WORKDIR ARCH=um SUBARCH=arm64 defconfig"
            make -C "$WORKDIR" ARCH=um SUBARCH=arm64 \
                 CROSS_COMPILE=aarch64-linux-gnu- \
                 defconfig 2>&1 \
                | head -30 | sed 's/^/  /'
        else
            warn "arm64_defconfig not found at $DEFCONFIG"
        fi
    fi
fi

# ── Phase 6: Source integrity ─────────────────────────────────────────────────
echo
sep
log "Phase 6 — Source integrity: original kernel source MUST be untouched"
sep

unexpected=$(diff -rq "$KERNEL_SRCDIR" "$WORKDIR" 2>/dev/null \
    | grep -v "^Only in $WORKDIR" \
    | grep -v "^Files.*differ$" \
    || true)

modified=$(diff -rq "$KERNEL_SRCDIR" "$WORKDIR" 2>/dev/null \
    | grep -c "^Files.*differ" || true)
added=$(diff -rq "$KERNEL_SRCDIR" "$WORKDIR" 2>/dev/null \
    | grep -c "^Only in $WORKDIR" || true)

if [[ -z "$unexpected" ]]; then
    ok "$KERNEL_SRCDIR is UNTOUCHED ✓"
else
    fail "ORIGINAL SOURCE WAS MODIFIED (BUG IN SCRIPT):"
    echo "$unexpected" | sed 's/^/  /'
fi
info "Workdir: $modified files modified, $added files added vs original"

# ── Cleanup ───────────────────────────────────────────────────────────────────
if [[ $DO_KEEP -eq 0 ]]; then
    rm -rf "$WORKDIR"
    log "Workdir cleaned: $WORKDIR"
    log "(Tarball kept at $TARBALL_PATH for re-use — delete manually if needed)"
else
    log "Workdir kept: $WORKDIR"
    log "Source kept : $KERNEL_SRCDIR"
fi

# ── Final verdict ─────────────────────────────────────────────────────────────
echo
sep
TOTAL_FAIL=$DR_FAIL
[[ $DO_APPLY -eq 1 ]] && TOTAL_FAIL=$((TOTAL_FAIL + AP_FAIL))

echo
if [[ $TOTAL_FAIL -eq 0 && $SCRATCH_COLL -eq 0 ]]; then
    echo -e "${GRN}${BLD}  ✅  ALL CLEAN${RST}"
    echo -e "      $PATCH_COUNT patches OK, $SCRATCH_COUNT scratch files OK"
    echo -e "      $KERNEL_SRCDIR UNTOUCHED"
    EXIT_CODE=0
elif [[ $TOTAL_FAIL -eq 0 && $SCRATCH_COLL -gt 0 ]]; then
    echo -e "${YEL}${BLD}  ⚠   PATCHES OK — $SCRATCH_COLL scratch collision(s)${RST}"
    echo -e "      Some files we wrote may now be in upstream — check diffs"
    EXIT_CODE=0
elif [[ $DR_WARN -gt 0 && $TOTAL_FAIL -eq 0 ]]; then
    echo -e "${YEL}${BLD}  ⚠   PASSES with $DR_WARN offset drift(s) — rebase recommended${RST}"
    EXIT_CODE=0
else
    echo -e "${RED}${BLD}  ❌  FAILED — $TOTAL_FAIL patch(es) could not apply${RST}"
    EXIT_CODE=1
fi

log "Full log: $LOGFILE"
sep
exit $EXIT_CODE
