#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

source scripts/equinox/pins.env

PROFILE="${DROIDSPACES_PROFILE:-kmi-safe}"
OUT="${OUT:-$HOME/out/equinox-production}"
DIST="${DIST:-$HOME/dist/equinox-production}"
DEPS="${EQUINOX_DEPS:-$HOME/equinox-deps}"
TC="${NEUTRON_DIR:-$HOME/toolchains/neutron-$NEUTRON_BUILD}"
BASELINE_SYMVERS="${BASELINE_SYMVERS:?BASELINE_SYMVERS is required for the production KMI gate}"
JOBS="${JOBS:-$(nproc --all)}"
[ "$JOBS" -le 16 ] || JOBS=16

case "$PROFILE" in
    kmi-safe)
        DROID_CFG="scripts/equinox/configs/droidspaces-kmi-safe.config"
        ;;
    full)
        [ "${ALLOW_EXPERIMENTAL_FULL_DROIDSPACES:-0}" = 1 ] || {
            echo '[!] full DroidSpaces is intentionally blocked for Image-only production builds.'
            echo '[!] use kmi-safe, or set ALLOW_EXPERIMENTAL_FULL_DROIDSPACES=1 only for ABI research.'
            exit 2
        }
        DROID_CFG="scripts/equinox/configs/droidspaces-full.config"
        ;;
    *)
        echo "[!] DROIDSPACES_PROFILE must be kmi-safe or full"
        exit 2
        ;;
esac

for cmd in git curl sha256sum tar zstd python3 perl make patch realpath; do
    command -v "$cmd" >/dev/null || { echo "[!] missing host tool: $cmd"; exit 1; }
done

[ -s "$BASELINE_SYMVERS" ] || {
    echo "[!] baseline Module.symvers missing: $BASELINE_SYMVERS"
    echo '[!] production Image will not be built without a KMI baseline'
    exit 1
}

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "[!] tracked kernel tree is dirty before integration"
    echo "[!] run this script in the detached worktree created by build-production.sh"
    exit 1
fi

mkdir -p "$HOME/toolchains" "$DEPS" "$DIST"

echo "[*] Equinox production root stack"
echo "    profile : $PROFILE"
echo "    jobs    : $JOBS"
echo "    out     : $OUT"
echo "    baseline: $BASELINE_SYMVERS"
echo "    python  : $(python3 --version 2>&1)"

# -----------------------------------------------------------------------------
# Pinned Neutron Clang
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
# Exact KernelSU-Next and SUSFS pins
# -----------------------------------------------------------------------------
KSUN="$DEPS/KernelSU-Next-$KSUN_TAG"
SUSFS="$DEPS/susfs4ksu-$SUSFS_PIN"

if [ ! -d "$KSUN/.git" ]; then
    rm -rf "$KSUN"
    git clone "$KSUN_REPO" "$KSUN"
fi
git -C "$KSUN" fetch --tags origin
git -C "$KSUN" checkout --detach "$KSUN_PIN"
git -C "$KSUN" reset --hard "$KSUN_PIN"
git -C "$KSUN" clean -ffdx
[ "$(git -C "$KSUN" rev-parse HEAD)" = "$KSUN_PIN" ] || { echo '[!] KernelSU pin mismatch'; exit 1; }
[ "$(git -C "$KSUN" rev-parse --is-shallow-repository)" = false ] || { echo '[!] KernelSU checkout is shallow'; exit 1; }
[ "$(git -C "$KSUN" describe --tags --exact-match HEAD)" = "$KSUN_TAG" ] || { echo '[!] KernelSU tag mismatch'; exit 1; }

if [ ! -d "$SUSFS/.git" ]; then
    rm -rf "$SUSFS"
    git clone --branch "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS"
fi
git -C "$SUSFS" fetch origin "$SUSFS_BRANCH"
git -C "$SUSFS" checkout --detach "$SUSFS_PIN"
git -C "$SUSFS" reset --hard "$SUSFS_PIN"
git -C "$SUSFS" clean -ffdx
[ "$(git -C "$SUSFS" rev-parse HEAD)" = "$SUSFS_PIN" ] || { echo '[!] SUSFS pin mismatch'; exit 1; }
grep -q '#define SUSFS_VERSION "v2.3.0"' "$SUSFS/kernel_patches/include/linux/susfs.h" || { echo '[!] SUSFS v2.3.0 check failed'; exit 1; }

echo "[*] KernelSU-Next: $KSUN_TAG @ ${KSUN_PIN:0:12}"
echo "[*] SUSFS: $SUSFS_EXPECT_VERSION @ ${SUSFS_PIN:0:12}"

# -----------------------------------------------------------------------------
# Source integration
# -----------------------------------------------------------------------------
bash scripts/equinox/integrate-ksun-susfs.sh "$KSUN" "$SUSFS" "$ROOT"
bash scripts/equinox/integrate-droidspaces.sh "$ROOT"
git diff --check
git -C "$KSUN" diff --check

# -----------------------------------------------------------------------------
# Kernel configuration
# -----------------------------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT" "$DIST"

make -s O="$OUT" LOCALVERSION= PYTHON=python3 gki_defconfig

scripts/kconfig/merge_config.sh -m -O "$OUT" \
    "$OUT/.config" \
    arch/arm64/configs/vendor/waipio_GKI.config \
    arch/arm64/configs/vendor/xiaomi_GKI.config \
    arch/arm64/configs/vendor/mondrian_GKI.config \
    arch/arm64/configs/vendor/debugfs.config \
    scripts/equinox/configs/rootstack.config \
    "$DROID_CFG"

make -s -j"$JOBS" O="$OUT" LOCALVERSION= PYTHON=python3 olddefconfig
CFG="$OUT/.config"

python3 - "$CFG" scripts/equinox/configs/rootstack.config "$DROID_CFG" <<'PY'
import sys

cfg = {}
for raw in open(sys.argv[1], encoding='utf-8'):
    line = raw.strip()
    if line.startswith('CONFIG_') and '=' in line:
        key, value = line.split('=', 1)
        cfg[key] = value
    elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
        cfg[line[2:-11]] = 'n'

errors = []
for fragment in sys.argv[2:]:
    for raw in open(fragment, encoding='utf-8'):
        line = raw.strip()
        if not line or (line.startswith('#') and not line.startswith('# CONFIG_')):
            continue
        if line.startswith('CONFIG_') and '=' in line:
            key, value = line.split('=', 1)
            if cfg.get(key) != value:
                errors.append(f'{key}: requested {value}, final {cfg.get(key, "<missing>")}')
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            key = line[2:-11]
            if cfg.get(key, 'n') != 'n':
                errors.append(f'{key}: requested n, final {cfg.get(key)}')

if errors:
    print('[!] final Kconfig does not satisfy requested production profile:')
    for error in errors:
        print('    ' + error)
    raise SystemExit(1)

print('[+] final Kconfig matches root stack and DroidSpaces profile')
PY

# Base integrity and branding.
grep -q '^CONFIG_LTO_CLANG_FULL=y' "$CFG" || { echo '[!] Full LTO dropped'; exit 1; }
grep -q '^CONFIG_CFI_CLANG=y' "$CFG" || { echo '[!] Clang CFI dropped'; exit 1; }
grep -q '^CONFIG_MODVERSIONS=y' "$CFG" || { echo '[!] MODVERSIONS dropped'; exit 1; }
grep -q '^CONFIG_LOCALVERSION="-Equinox"' "$CFG" || { echo '[!] Equinox branding dropped'; exit 1; }
grep -q '^CONFIG_KSU=y' "$CFG" || { echo '[!] KernelSU-Next is not enabled'; exit 1; }
grep -q '^CONFIG_KSU_SUSFS=y' "$CFG" || { echo '[!] SUSFS is not enabled'; exit 1; }
grep -q '^CONFIG_SYSVIPC=y' "$CFG" || { echo '[!] DroidSpaces SYSVIPC support missing'; exit 1; }

if [ "$PROFILE" = kmi-safe ]; then
    for option in CGROUP_DEVICE CGROUP_PIDS BRIDGE_NETFILTER NF_TABLES; do
        if grep -q "^CONFIG_${option}=y" "$CFG"; then
            echo "[!] unsafe production option enabled: CONFIG_${option}=y"
            exit 1
        fi
    done
fi

# DroidSpaces SYSVIPC must live in Android KABI reserves, never in its original
# task_struct position.
grep -q 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)' include/linux/sched.h || { echo '[!] SYSVIPC KABI relocation missing'; exit 1; }
grep -q '_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(7); ANDROID_KABI_RESERVE(8)' include/linux/sched.h || { echo '[!] SYSVIPC shm KABI relocation missing'; exit 1; }

# Regenerate auto.conf/kernel.release after all fragment merges. This avoids a
# stale generated release string when the integration worktree is dirty.
rm -f "$OUT/include/config/auto.conf" "$OUT/include/config/auto.conf.cmd"
make -s O="$OUT" LOCALVERSION= PYTHON=python3 olddefconfig
make -s O="$OUT" LOCALVERSION= PYTHON=python3 prepare

release="$(make -s O="$OUT" LOCALVERSION= PYTHON=python3 kernelrelease)"
[ "$release" = "$EXPECTED_KERNEL_RELEASE" ] || { echo "[!] unexpected kernel release: $release"; exit 1; }
echo "[*] kernel release: $release"

# -----------------------------------------------------------------------------
# Build Image and modules
# -----------------------------------------------------------------------------
echo "[*] building production Image with Neutron Clang"
set -o pipefail
make -j"$JOBS" O="$OUT" LOCALVERSION= PYTHON=python3 Image modules 2>&1 | tee "$DIST/build-$PROFILE.log"

IMAGE="$OUT/arch/arm64/boot/Image"
[ -s "$IMAGE" ] || { echo '[!] Image was not produced'; exit 1; }
[ -s "$OUT/Module.symvers" ] || { echo '[!] Module.symvers was not produced'; exit 1; }

cp "$IMAGE" "$DIST/Image-$PROFILE"
cp "$CFG" "$DIST/config-$PROFILE"
cp "$OUT/Module.symvers" "$DIST/Module.symvers-$PROFILE"
sha256sum "$DIST/Image-$PROFILE" | tee "$DIST/Image-$PROFILE.sha256"

# -----------------------------------------------------------------------------
# Mandatory KMI gate
# -----------------------------------------------------------------------------
KMI_REPORT="$DIST/kmi-$PROFILE.txt"
bash scripts/equinox/symvers-diff.sh "$BASELINE_SYMVERS" "$OUT/Module.symvers" "$KMI_REPORT"

# Source/compile sanity after the build.
if grep -Eqi '(^|[[:space:]])(error:|fatal error:|undefined reference|ld\.lld: error|make: \*\*\*)' "$DIST/build-$PROFILE.log"; then
    echo '[!] compiler/linker error signature found in build log'
    exit 1
fi

git diff --check

echo "[+] production kernel build passed"
echo "    Image : $DIST/Image-$PROFILE"
echo "    config: $DIST/config-$PROFILE"
echo "    KMI   : $KMI_REPORT"
