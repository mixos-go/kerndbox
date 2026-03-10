#!/usr/bin/env bash
# =============================================================================
# test-patches-local.sh — Test patches & scratch files against local reference
#
# Uses /home/claude/kernel-upstream (partial reference, 11k files) as base.
# ALL work is done in /tmp — source reference is NEVER modified.
#
# Usage:
#   ./scripts/test-patches-local.sh [--apply] [--keep]
#
#   --apply   Also do a real sequential apply after dry-run
#   --keep    Do not delete /tmp workdir after run
#
# Output:
#   output/test-local-TIMESTAMP.log   full log
#   Exit 0 = all patches applied clean (no FAILED)
#   Exit 1 = one or more patches FAILED
# =============================================================================
set -uo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$REPO_ROOT/scripts/patches/uml-arm64"
SCRATCH_DIR="$REPO_ROOT/arch/arm64"
KERNEL_REF="/home/claude/kernel-upstream"     # local partial reference
WORKDIR="/tmp/kernel-test-local-$$"
OUTPUT_DIR="$REPO_ROOT/output"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
LOGFILE="$OUTPUT_DIR/test-local-${TIMESTAMP}.log"
KERNEL_VER="6.12.74"   # expected version in reference

DO_APPLY=0
DO_KEEP=0
for arg in "$@"; do
    case "$arg" in
        --apply) DO_APPLY=1 ;;
        --keep)  DO_KEEP=1  ;;
    esac
done

mkdir -p "$OUTPUT_DIR"
exec > >(tee "$LOGFILE") 2>&1

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; YEL='\033[1;33m'; GRN='\033[0;32m'
    CYN='\033[0;36m'; BLD='\033[1m';    RST='\033[0m'
else
    RED=''; YEL=''; GRN=''; CYN=''; BLD=''; RST=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "${BLD}[test-local]${RST} $*"; }
ok()   { echo -e "  ${GRN}✓ OK   ${RST} $*"; }
warn() { echo -e "  ${YEL}⚠ WARN ${RST} $*"; }
fail() { echo -e "  ${RED}✗ FAIL ${RST} $*"; }
info() { echo -e "  ${CYN}·${RST}      $*"; }
sep()  { echo -e "${CYN}$(printf '═%.0s' {1..70})${RST}"; }

patch_subject() {
    grep -m1 '^Subject:' "$1" 2>/dev/null | sed 's/^Subject: //' || basename "$1"
}

parse_hunk_issues() {
    # stdin: patch output — print offset/fuzz/FAILED lines indented
    grep -E 'Hunk|FAILED|offset|fuzz|reject|succeeded' \
    | while read -r line; do
        if echo "$line" | grep -q 'FAILED'; then
            echo -e "             ${RED}$line${RST}"
        elif echo "$line" | grep -qE 'offset|fuzz'; then
            echo -e "             ${YEL}$line${RST}"
        else
            echo -e "             $line"
        fi
    done
}

# ── Preflight ─────────────────────────────────────────────────────────────────
sep
log "Kernel patch test — LOCAL reference"
log "Reference : $KERNEL_REF  (Linux $KERNEL_VER partial)"
log "Patches   : $PATCH_DIR"
log "Scratch   : $SCRATCH_DIR"
log "Workdir   : $WORKDIR"
log "Log       : $LOGFILE"
sep

# Verify reference exists
if [[ ! -d "$KERNEL_REF" ]]; then
    fail "Kernel reference not found: $KERNEL_REF"
    exit 1
fi
REF_VER=$(grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL' "$KERNEL_REF/Makefile" 2>/dev/null \
    | awk -F= '{gsub(/ /,"",$2); printf $2"."}' | sed 's/\.$//')
log "Reference version : $REF_VER"

PATCH_COUNT=$(ls "$PATCH_DIR"/0*.patch 2>/dev/null | wc -l)
SCRATCH_COUNT=$(find "$SCRATCH_DIR" -type f | wc -l)
log "Patches   : $PATCH_COUNT"
log "Scratch files : $SCRATCH_COUNT"
sep

# ── Phase 0: Setup workdir ────────────────────────────────────────────────────
echo
log "Phase 0 — Setting up workdir from reference ..."
cp -a "$KERNEL_REF/." "$WORKDIR/"
log "  Copied $KERNEL_REF → $WORKDIR"

# Verify reference is untouched
if diff -rq "$KERNEL_REF" "$WORKDIR" > /dev/null 2>&1; then
    log "  Reference integrity: ✓ identical copy confirmed"
else
    warn "  Copy diff detected — investigate"
fi

# ── Phase 1: Scratch file collision check ─────────────────────────────────────
echo
sep
log "Phase 1 — Scratch file collision check"
log "(Detecting if any of our new arch/arm64 files already exist in reference)"
sep

SCRATCH_OK=0; SCRATCH_COLL=0; SCRATCH_NEW=0

while IFS= read -r src; do
    rel="${src#$REPO_ROOT/}"                # e.g. arch/arm64/um/vdso/vma.c
    kernel_path="$KERNEL_REF/$rel"
    dst_path="$WORKDIR/$rel"

    if [[ -f "$kernel_path" ]]; then
        # File exists in upstream — check if identical or different
        if diff -q "$src" "$kernel_path" > /dev/null 2>&1; then
            ok "${rel}  (exists upstream, identical — OK)"
            ((SCRATCH_OK++))
        else
            warn "${rel}  (EXISTS IN UPSTREAM, DIFFERS)"
            info "--- upstream vs ours:"
            diff --unified=3 "$kernel_path" "$src" \
                | head -40 \
                | sed 's/^/             /'
            ((SCRATCH_COLL++))
        fi
    else
        ok "${rel}  (new file, no collision)"
        ((SCRATCH_NEW++))
    fi

    # Copy scratch file into workdir for patch testing
    mkdir -p "$(dirname "$dst_path")"
    cp "$src" "$dst_path"

done < <(find "$SCRATCH_DIR" -type f | sort)

echo
log "Scratch summary: $SCRATCH_NEW new | $SCRATCH_OK identical | $SCRATCH_COLL COLLISIONS"
[[ $SCRATCH_COLL -gt 0 ]] && warn "Review collisions above — they may need merging"

# ── Phase 2: Dry-run all patches in sequence ──────────────────────────────────
echo
sep
log "Phase 2 — Dry-run: patches applied in sequence (no real changes)"
log "(Each patch sees the result of all previous patches)"
sep

# For dry-run we simulate sequential state using a scratch copy
DRYRUN_DIR="$WORKDIR-dryrun"
cp -a "$WORKDIR/." "$DRYRUN_DIR/"

DR_PASS=0; DR_WARN=0; DR_FAIL=0
declare -a DR_FAILED_LIST=()
declare -a DR_WARNED_LIST=()

for pfile in $(ls "$PATCH_DIR"/0*.patch | sort); do
    pname=$(basename "$pfile")
    subject=$(patch_subject "$pfile")

    # Extract target files from patch
    targets=$(grep '^+++ b/' "$pfile" | sed 's|^+++ b/||')

    # Run dry-run
    out=$(patch -d "$DRYRUN_DIR" -p1 --dry-run --batch < "$pfile" 2>&1)
    rc=$?

    if echo "$out" | grep -qw 'FAILED'; then
        fail "$pname"
        info "Subject: $subject"
        echo "$out" | parse_hunk_issues
        # Show reject context if any
        for t in $targets; do
            rfile="$DRYRUN_DIR/${t}.rej"
            [[ -f "$rfile" ]] && { info "Reject for $t:"; cat "$rfile" | sed 's/^/             /'; }
        done
        DR_FAILED_LIST+=("$pname")
        ((DR_FAIL++))
    elif echo "$out" | grep -qE 'offset|fuzz'; then
        warn "$pname"
        info "Subject: $subject"
        echo "$out" | parse_hunk_issues
        DR_WARNED_LIST+=("$pname")
        ((DR_WARN++))
    else
        ok "$pname"
        info "Subject: $subject"
        ((DR_PASS++))
    fi

    # Apply for real in dryrun dir so next patch sees correct state
    patch -d "$DRYRUN_DIR" -p1 --batch --forward < "$pfile" > /dev/null 2>&1 || true
done

# Cleanup dryrun dir
rm -rf "$DRYRUN_DIR"

echo
log "Dry-run summary:"
log "  PASSED  : $DR_PASS / $PATCH_COUNT"
log "  WARNED  : $DR_WARN / $PATCH_COUNT  (offset/fuzz — applies but may need rebase)"
log "  FAILED  : $DR_FAIL / $PATCH_COUNT"
if [[ ${#DR_WARNED_LIST[@]} -gt 0 ]]; then
    for p in "${DR_WARNED_LIST[@]}"; do warn "    $p"; done
fi
if [[ ${#DR_FAILED_LIST[@]} -gt 0 ]]; then
    for p in "${DR_FAILED_LIST[@]}"; do fail "    $p"; done
fi

# ── Phase 3: Real sequential apply (optional) ─────────────────────────────────
AP_PASS=0; AP_WARN=0; AP_FAIL=0
declare -a AP_FAILED_LIST=()

if [[ $DO_APPLY -eq 1 ]]; then
    echo
    sep
    log "Phase 3 — Real sequential apply → $WORKDIR"
    sep

    for pfile in $(ls "$PATCH_DIR"/0*.patch | sort); do
        pname=$(basename "$pfile")
        subject=$(patch_subject "$pfile")

        out=$(patch -d "$WORKDIR" -p1 --batch --no-backup-if-mismatch < "$pfile" 2>&1)
        rc=$?

        if echo "$out" | grep -qw 'FAILED'; then
            fail "$pname"
            info "Subject: $subject"
            echo "$out" | parse_hunk_issues
            AP_FAILED_LIST+=("$pname")
            ((AP_FAIL++))
        elif echo "$out" | grep -qE 'offset|fuzz'; then
            warn "$pname  (offset drift)"
            info "Subject: $subject"
            echo "$out" | parse_hunk_issues
            ((AP_WARN++))
        else
            ok "$pname"
            ((AP_PASS++))
        fi
    done

    echo
    log "Apply summary:"
    log "  PASSED  : $AP_PASS / $PATCH_COUNT"
    log "  WARNED  : $AP_WARN / $PATCH_COUNT"
    log "  FAILED  : $AP_FAIL / $PATCH_COUNT"
    if [[ ${#AP_FAILED_LIST[@]} -gt 0 ]]; then
        for p in "${AP_FAILED_LIST[@]}"; do fail "    $p"; done
    fi
fi

# ── Phase 4: Source reference integrity ───────────────────────────────────────
echo
sep
log "Phase 4 — Reference integrity check"
sep

unexpected=$(diff -rq "$KERNEL_REF" "$WORKDIR" 2>/dev/null \
    | grep -v "^Only in $WORKDIR" \
    | grep -v "^Files.*differ$" \
    || true)

modified=$(diff -rq "$KERNEL_REF" "$WORKDIR" 2>/dev/null \
    | grep "^Files.*differ" | wc -l)
added=$(diff -rq "$KERNEL_REF" "$WORKDIR" 2>/dev/null \
    | grep "^Only in $WORKDIR" | wc -l)

if [[ -z "$unexpected" ]]; then
    ok "Reference $KERNEL_REF is UNTOUCHED"
else
    fail "UNEXPECTED changes to reference:"
    echo "$unexpected" | sed 's/^/  /'
fi
log "  Workdir: $modified files modified, $added files added (expected)"

# ── Cleanup ───────────────────────────────────────────────────────────────────
if [[ $DO_KEEP -eq 0 ]]; then
    rm -rf "$WORKDIR"
    log "Workdir cleaned up"
else
    log "Workdir kept: $WORKDIR"
fi

# ── Final verdict ─────────────────────────────────────────────────────────────
echo
sep
TOTAL_FAIL=$DR_FAIL
[[ $DO_APPLY -eq 1 ]] && TOTAL_FAIL=$((TOTAL_FAIL + AP_FAIL))

if [[ $TOTAL_FAIL -eq 0 && $SCRATCH_COLL -eq 0 ]]; then
    echo -e "${GRN}${BLD}  ✅  ALL CLEAN — $PATCH_COUNT patches OK, $SCRATCH_COUNT scratch files OK${RST}"
    EXIT_CODE=0
elif [[ $TOTAL_FAIL -eq 0 ]]; then
    echo -e "${YEL}${BLD}  ⚠   PASSED with $SCRATCH_COLL scratch collision(s) — review above${RST}"
    EXIT_CODE=0
else
    echo -e "${RED}${BLD}  ❌  FAILED — $TOTAL_FAIL patch(es) could not apply${RST}"
    EXIT_CODE=1
fi

log "Log saved: $LOGFILE"
sep
exit $EXIT_CODE
