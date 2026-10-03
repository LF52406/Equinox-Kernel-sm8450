#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source scripts/equinox/pins.env

MAIN_SHA="$(git rev-parse HEAD)"
WORKROOT="${EQUINOX_WORKTREES:-$HOME/build/equinox-worktrees}"
BASE_WT="$WORKROOT/baseline"
FINAL_WT="$WORKROOT/production"
BASE_OUT="${BASE_OUT:-$HOME/out/equinox-baseline}"
FINAL_OUT="${OUT:-$HOME/out/equinox-production}"
DIST="${DIST:-$HOME/dist/equinox-production}"
TC="${NEUTRON_DIR:-$HOME/toolchains/neutron-$NEUTRON_BUILD}"
DEPS="${EQUINOX_DEPS:-$HOME/equinox-deps}"
JOBS="${JOBS:-$(nproc --all)}"
[ "$JOBS" -le 16 ] || JOBS=16

for cmd in git curl sha256sum tar zstd python3 make patch realpath zip unzip; do
    command -v "$cmd" >/dev/null || { echo "[!] missing host tool: $cmd"; exit 1; }
done

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo '[!] main kernel checkout has tracked modifications'
    echo '[!] commit/stash them before a production build'
    exit 1
fi

git merge-base --is-ancestor "$BASE_COMMIT" "$MAIN_SHA" || {
    echo "[!] current branch is not based on known-good Equinox commit $BASE_COMMIT"
    exit 1
}

mkdir -p "$HOME/toolchains" "$WORKROOT" "$DIST" "$DEPS"

echo "[*] Equinox production build"
echo "    source   : $MAIN_SHA"
echo "    base     : $BASE_COMMIT"
echo "    jobs     : $JOBS"
echo "    toolchain: $TC"

# -----------------------------------------------------------------------------
# Prepare one pinned toolchain used by both baseline and candidate builds.
# -----------------------------------------------------------------------------
if [ ! -x "$TC/bin/clang" ]; then
    echo "[*] fetching Neutron Clang $NEUTRON_BUILD"
    rm -rf "$TC"
    mkdir -p "$TC"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    archive="$tmp/neutron-clang-$NEUTRON_BUILD.tar.zst"

    curl -fL --retry 4 --retry-delay 5 \
        "https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/$NEUTRON_BUILD/neutron-clang-$NEUTRON_BUILD.tar.zst" \
        -o "$archive"
    echo "$NEUTRON_SHA256  $archive" | sha256sum -c -
    tar -I zstd -xf "$archive" -C "$TC"

    curl -fL --retry 4 --retry-delay 5 \
        "https://raw.githubusercontent.com/Neutron-Toolchains/antman/$ANTMAN_COMMIT/antman" \
        -o "$TC/antman"
    echo "$ANTMAN_SHA256  $TC/antman" | sha256sum -c -
    chmod +x "$TC/antman"

    patched=0
    for attempt in 1 2 3 4; do
        if (cd "$TC" && ./antman --patch=glibc); then
            patched=1
            break
        fi
        [ "$attempt" -eq 4 ] && break
        echo "[*] antman retry $attempt"
        sleep $((attempt * 20))
    done
    [ "$patched" -eq 1 ] || { echo '[!] antman glibc patch failed'; exit 1; }
fi

export PATH="$TC/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-LF52406}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-Equinox}"

clang_line="$(clang --version | sed -n '1p')"
echo "[*] toolchain: $clang_line"
echo "$clang_line" | grep -qi 'Neutron clang' || { echo '[!] selected compiler is not Neutron Clang'; exit 1; }

# -----------------------------------------------------------------------------
# Create clean detached worktrees. The main checkout is never patched by the
# KernelSU/SUSFS/DroidSpaces integration scripts.
# -----------------------------------------------------------------------------
for wt in "$BASE_WT" "$FINAL_WT"; do
    if [ -e "$wt" ] || [ -L "$wt" ]; then
        git worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    fi
done
git worktree prune

git worktree add --detach "$BASE_WT" "$BASE_COMMIT"
git worktree add --detach "$FINAL_WT" "$MAIN_SHA"

# -----------------------------------------------------------------------------
# Build a clean baseline from the exact boot-tested source commit, using the
# same Neutron toolchain and the same base config stack as the candidate.
# -----------------------------------------------------------------------------
echo "[*] building KMI baseline"
rm -rf "$BASE_OUT"
mkdir -p "$BASE_OUT" "$DIST"

(
    cd "$BASE_WT"
    make -s O="$BASE_OUT" LOCALVERSION= gki_defconfig
    scripts/kconfig/merge_config.sh -m -O "$BASE_OUT" \
        "$BASE_OUT/.config" \
        arch/arm64/configs/vendor/waipio_GKI.config \
        arch/arm64/configs/vendor/xiaomi_GKI.config \
        arch/arm64/configs/vendor/mondrian_GKI.config \
        arch/arm64/configs/vendor/debugfs.config

    make -s -j"$JOBS" O="$BASE_OUT" LOCALVERSION= olddefconfig
    rm -f "$BASE_OUT/include/config/auto.conf" "$BASE_OUT/include/config/auto.conf.cmd"
    make -s O="$BASE_OUT" LOCALVERSION= olddefconfig
    make -s O="$BASE_OUT" LOCALVERSION= prepare

    release="$(make -s O="$BASE_OUT" LOCALVERSION= kernelrelease)"
    [ "$release" = "$EXPECTED_KERNEL_RELEASE" ] || {
        echo "[!] baseline kernel release mismatch: $release"
        exit 1
    }

    set -o pipefail
    make -j"$JOBS" O="$BASE_OUT" LOCALVERSION= Image modules 2>&1 | tee "$DIST/build-baseline.log"
)

BASE_IMAGE="$BASE_OUT/arch/arm64/boot/Image"
BASE_SYMVERS="$BASE_OUT/Module.symvers"
[ -s "$BASE_IMAGE" ] || { echo '[!] baseline Image missing'; exit 1; }
[ -s "$BASE_SYMVERS" ] || { echo '[!] baseline Module.symvers missing'; exit 1; }

cp "$BASE_IMAGE" "$DIST/Image-baseline-neutron"
cp "$BASE_OUT/.config" "$DIST/config-baseline-neutron"
cp "$BASE_SYMVERS" "$DIST/Module.symvers-baseline-neutron"
sha256sum "$DIST/Image-baseline-neutron" > "$DIST/Image-baseline-neutron.sha256"

if grep -Eqi '(^|[[:space:]])(error:|fatal error:|undefined reference|ld\.lld: error|make: \*\*\*)' "$DIST/build-baseline.log"; then
    echo '[!] compiler/linker error signature found in baseline build log'
    exit 1
fi

echo '[+] baseline build complete'

# -----------------------------------------------------------------------------
# Build the actual production kernel in a separate clean worktree.
# build-rootstack.sh performs source validation and a mandatory strict KMI gate.
# -----------------------------------------------------------------------------
echo "[*] building KernelSU-Next + SUSFS + DroidSpaces production candidate"

BASELINE_SYMVERS="$BASE_SYMVERS" \
OUT="$FINAL_OUT" \
DIST="$DIST" \
NEUTRON_DIR="$TC" \
EQUINOX_DEPS="$DEPS" \
JOBS="$JOBS" \
DROIDSPACES_PROFILE=kmi-safe \
bash "$FINAL_WT/scripts/equinox/build-rootstack.sh"

# -----------------------------------------------------------------------------
# Package only after the strict KMI gate has passed.
# -----------------------------------------------------------------------------
echo '[*] packaging verified production Image'

OUT="$FINAL_OUT" \
DIST="$DIST" \
NEUTRON_DIR="$TC" \
KMI_REPORT="$DIST/kmi-kmi-safe.txt" \
bash "$FINAL_WT/scripts/equinox/package-anykernel.sh"

FINAL_IMAGE="$FINAL_OUT/arch/arm64/boot/Image"
FINAL_ZIP="$DIST/Equinox-5.10.269-mondrian.zip"

[ -s "$FINAL_IMAGE" ] || { echo '[!] final Image disappeared after packaging'; exit 1; }
[ -s "$FINAL_ZIP" ] || { echo '[!] final ZIP missing'; exit 1; }

echo
echo '=========================================='
echo '        EQUINOX PRODUCTION READY'
echo '=========================================='
echo "Kernel release : $EXPECTED_KERNEL_RELEASE"
echo 'KernelSU-Next  : 3.3.0'
echo 'SUSFS          : 2.3.0'
echo 'DroidSpaces    : supported, KMI-safe profile'
echo 'KMI            : PASS (changed_crc=0, removed=0)'
echo "Image          : $FINAL_IMAGE"
echo "ZIP            : $FINAL_ZIP"
echo "ZIP SHA256     : $(awk '{print $1}' "$FINAL_ZIP.sha256")"
echo '=========================================='
