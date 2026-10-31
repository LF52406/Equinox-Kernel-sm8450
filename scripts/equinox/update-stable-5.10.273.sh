#!/usr/bin/env bash
# Integrate the complete upstream Linux stable patch series v5.10.270..v5.10.273.
# Staging only: refuse conflicts; never silently discard Qualcomm/Android changes.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

TARGET_BRANCH="update/equinox-linux-5.10.273-staging-20261031"
EXPECTED_BASE_SHA="4ba940b5b8c5361d23c21923e92116c560a3345c"
PATCH_URL_BASE="https://cdn.kernel.org/pub/linux/kernel/v5.x/incr"

fail() { printf '[!] %s\n' "$*" >&2; exit 1; }
for tool in git curl xz python3 sha256sum grep sed; do
    command -v "$tool" >/dev/null || fail "Missing host tool: $tool"
done

[[ "$(git branch --show-current)" == "$TARGET_BRANCH" ]] ||
    fail "Must run in the dedicated staging branch: $TARGET_BRANCH"
[[ -z "$(git status --porcelain)" ]] ||
    fail "Worktree must be completely clean; commit/stash local changes"
git merge-base --is-ancestor "$EXPECTED_BASE_SHA" HEAD ||
    fail "Branch does not descend from pinned production HEAD"
grep -Eq '^SUBLEVEL = 269$' Makefile ||
    fail "Expected unmodified Linux 5.10.269 source"
grep -Fxq 'EXPECTED_KERNEL_RELEASE=5.10.269-Equinox' scripts/equinox/pins.env ||
    fail "Unexpected release pin; review before updating"

BASE_HEAD="$(git rev-parse HEAD)"
WORK_DIR="$(mktemp -d)"
WT="$WORK_DIR/source"
cleanup() {
    git worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
git worktree add --detach --quiet "$WT" "$BASE_HEAD"

for patchlevel in 270 271 272 273; do
    version="5.10.$patchlevel"
    url="$PATCH_URL_BASE/patch-5.10.$((patchlevel - 1))-$patchlevel.xz"
    compressed="$WORK_DIR/patch-$version.xz"
    patch="$WORK_DIR/patch-$version"
    printf '[*] Downloading official Linux %s patch\n' "$version"
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        "$url" --output "$compressed"
    xz --test "$compressed"
    sha256sum "$compressed"
    xz --decompress --stdout "$compressed" > "$patch"
    [[ -s "$patch" ]] || fail "Empty patch: $version"

    printf '[*] Checking full patch %s, never automatically discarding rejects\n' "$version"
    if ! git -C "$WT" apply --check "$patch" > "$WORK_DIR/apply.log" 2>&1; then
        printf '[!] Upstream %s does not apply cleanly to this Qualcomm/Android tree.\n' "$version" >&2
        sed -n '1,100p' "$WORK_DIR/apply.log" >&2
        printf '[!] No kernel code was pushed. Manual reconciliation is required.\n' >&2
        exit 2
    fi
    git -C "$WT" apply --index "$patch"
    git -C "$WT" -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
        commit --quiet -m "stable: integrate complete Linux $version release"
    grep -Fxq "SUBLEVEL = $patchlevel" "$WT/Makefile" ||
        fail "Makefile version mismatch after $version"
done

# Production still builds the old boot-tested 5.10.269 KMI baseline.
python3 - "$WT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
changes = {
    "scripts/equinox/pins.env": [
        ("EXPECTED_KERNEL_RELEASE=5.10.269-Equinox",
         "BASELINE_KERNEL_RELEASE=5.10.269-Equinox\nEXPECTED_KERNEL_RELEASE=5.10.273-Equinox"),
    ],
    "scripts/equinox/build-production.sh": [
        ('[ "$release" = "$EXPECTED_KERNEL_RELEASE" ] || {',
         '[ "$release" = "$BASELINE_KERNEL_RELEASE" ] || {'),
        ("Equinox-5.10.269-mondrian.zip", "Equinox-5.10.273-mondrian.zip"),
    ],
    "scripts/equinox/package-anykernel.sh": [
        ("5.10.269", "5.10.273"),
    ],
    "scripts/equinox/README.md": [
        ("5.10.269", "5.10.273"),
    ],
}
for file, replacements in changes.items():
    path = root / file
    old = path.read_text()
    new = old
    for needle, replacement in replacements:
        count = new.count(needle)
        if count != 1 and file not in ("scripts/equinox/package-anykernel.sh", "scripts/equinox/README.md"):
            raise SystemExit(f"Expected one occurrence in {file}: {needle!r}; found {count}")
        if count == 0:
            raise SystemExit(f"Missing expected text in {file}: {needle!r}")
        new = new.replace(needle, replacement)
    if new == old:
        raise SystemExit(f"No changes in {file}")
    path.write_text(new)
PY

grep -Fxq 'BASELINE_KERNEL_RELEASE=5.10.269-Equinox' "$WT/scripts/equinox/pins.env" ||
    fail "Baseline release unexpectedly changed"
grep -Fxq 'EXPECTED_KERNEL_RELEASE=5.10.273-Equinox' "$WT/scripts/equinox/pins.env" ||
    fail "Candidate release mismatch"
grep -Eq '^SUBLEVEL = 273$' "$WT/Makefile" ||
    fail "Final source does not identify as 5.10.273"
for file in scripts/equinox/build-production.sh scripts/equinox/build-rootstack.sh \
    scripts/equinox/package-anykernel.sh scripts/equinox/integrate-ksun-susfs.sh \
    scripts/equinox/integrate-droidspaces.sh; do
    bash -n "$WT/$file" || fail "Shell syntax error: $file"
done
git -C "$WT" diff --check || fail "Whitespace errors in metadata changes"
git -C "$WT" add scripts/equinox
git -C "$WT" -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    commit --quiet -m 'equinox: adapt production version checks while keeping 5.10.269 KMI baseline'

printf '[+] All four upstream releases applied without rejected hunks.\n'
printf '[+] KernelSU, SUSFS, DroidSpaces pins and original KMI baseline preserved.\n'
printf '[!] No kernel build, KMI comparison, or device boot test has been performed.\n'
printf '[+] Prepared candidate commit %s\n' "$(git -C "$WT" rev-parse HEAD)"
if [[ "$(printenv EQUINOX_PUSH_STAGING || true)" == "1" ]]; then
    printf '[*] Pushing complete integration to staging branch (fast-forward only)\n'
    git -C "$WT" push origin "HEAD:refs/heads/$TARGET_BRANCH"
else
    printf '[*] Dry run only; set EQUINOX_PUSH_STAGING=1 to push a complete integration.\n'
fi
