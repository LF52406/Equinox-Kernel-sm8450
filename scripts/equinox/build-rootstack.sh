#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

source scripts/equinox/pins.env

PROFILE="${DROIDSPACES_PROFILE:-full}"
OUT="${OUT:-$HOME/out/equinox-rootstack}"
DIST="${DIST:-$HOME/dist/equinox-rootstack}"
DEPS="${EQUINOX_DEPS:-$HOME/equinox-deps}"
TC="${NEUTRON_DIR:-$HOME/toolchains/neutron-$NEUTRON_BUILD}"
BASELINE_SYMVERS="${BASELINE_SYMVERS:-$HOME/out/equinox/Module.symvers}"
JOBS="${JOBS:-$(nproc --all)}"
[ "$JOBS" -le 16 ] || JOBS=16

case "$PROFILE" in
    full) DROID_CFG="scripts/equinox/configs/droidspaces-full.config" ;;
    kmi-safe) DROID_CFG="scripts/equinox/configs/droidspaces-kmi-safe.config" ;;
    *) echo "[!] DROIDSPACES_PROFILE must be full or kmi-safe"; exit 2 ;;
esac

for c in git curl sha256sum tar zstd python3 make patch realpath; do
    command -v "$c" >/dev/null || { echo "[!] missing host tool: $c"; exit 1; }
done

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "[!] tracked kernel tree is dirty. Use a fresh checkout/worktree for this build."
    exit 1
fi

mkdir -p "$HOME/toolchains" "$DEPS" "$OUT" "$DIST"

echo "[*] Equinox root stack"
echo "    profile : $PROFILE"
echo "    jobs    : $JOBS"
echo "    out     : $OUT"

# -----------------------------------------------------------------------------
# Neutron Clang, pinned and checksummed
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
    (cd "$TC" && ./antman --patch=glibc)
fi

export PATH="$TC/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-LF52406}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-Equinox}"

clang_line="$(clang --version | head -n1)"
echo "[*] toolchain: $clang_line"
echo "$clang_line" | grep -qi 'Neutron clang' || { echo "[!] selected compiler is not Neutron Clang"; exit 1; }

# -----------------------------------------------------------------------------
# Exact third-party source pins
# -----------------------------------------------------------------------------
KSUN="$DEPS/KernelSU-Next-$KSUN_TAG"
SUSFS="$DEPS/susfs4ksu-$SUSFS_PIN"

if [ ! -d "$KSUN/.git" ]; then
    rm -rf "$KSUN"
    git clone "$KSUN_REPO" "$KSUN"
fi
git -C "$KSUN" fetch --tags origin
git -C "$KSUN" checkout --detach "$KSUN_PIN"
[ "$(git -C "$KSUN" rev-parse HEAD)" = "$KSUN_PIN" ] || { echo '[!] KernelSU pin mismatch'; exit 1; }
git -C "$KSUN" describe --tags --exact-match HEAD | grep -qx "$KSUN_TAG" || { echo '[!] KernelSU tag mismatch'; exit 1; }

if [ ! -d "$SUSFS/.git" ]; then
    rm -rf "$SUSFS"
    git clone --branch "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS"
fi
git -C "$SUSFS" fetch origin "$SUSFS_BRANCH"
git -C "$SUSFS" checkout --detach "$SUSFS_PIN"
[ "$(git -C "$SUSFS" rev-parse HEAD)" = "$SUSFS_PIN" ] || { echo '[!] SUSFS pin mismatch'; exit 1; }
grep -q '#define SUSFS_VERSION "v2.3.0"' "$SUSFS/kernel_patches/include/linux/susfs.h" || { echo '[!] SUSFS v2.3.0 check failed'; exit 1; }

echo "[*] KernelSU-Next: $KSUN_TAG @ ${KSUN_PIN:0:12}"
echo "[*] SUSFS: $SUSFS_EXPECT_VERSION @ ${SUSFS_PIN:0:12}"

# -----------------------------------------------------------------------------
# Source integration. Strict: no fuzzy fallback, no module CRC bypass.
# -----------------------------------------------------------------------------
bash scripts/equinox/integrate-ksun-susfs.sh "$KSUN" "$SUSFS" "$ROOT"
bash scripts/equinox/integrate-droidspaces.sh "$ROOT"

# -----------------------------------------------------------------------------
# Kernel configuration
# -----------------------------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT" "$DIST"

make -s O="$OUT" LOCALVERSION= gki_defconfig

scripts/kconfig/merge_config.sh -m -O "$OUT" \
    "$OUT/.config" \
    arch/arm64/configs/vendor/waipio_GKI.config \
    arch/arm64/configs/vendor/xiaomi_GKI.config \
    arch/arm64/configs/vendor/mondrian_GKI.config \
    arch/arm64/configs/vendor/debugfs.config \
    scripts/equinox/configs/rootstack.config \
    "$DROID_CFG"

make -s -j"$JOBS" O="$OUT" LOCALVERSION= olddefconfig
CFG="$OUT/.config"

python3 - "$CFG" scripts/equinox/configs/rootstack.config "$DROID_CFG" <<'PY'
import sys
cfg = {}
for line in open(sys.argv[1], encoding='utf-8'):
    line=line.strip()
    if line.startswith('CONFIG_') and '=' in line:
        k,v=line.split('=',1); cfg[k]=v
    elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
        cfg[line[2:-11]]='n'
errors=[]
for frag in sys.argv[2:]:
    for raw in open(frag, encoding='utf-8'):
        line=raw.strip()
        if not line or (line.startswith('#') and not line.startswith('# CONFIG_')):
            continue
        if line.startswith('CONFIG_') and '=' in line:
            k,v=line.split('=',1)
            if cfg.get(k) != v:
                errors.append(f'{k}: requested {v}, final {cfg.get(k, "<missing>")}')
        elif line.startswith('# CONFIG_') and line.endswith(' is not set'):
            k=line[2:-11]
            # Missing optional legacy symbols are equivalent to disabled.
            if cfg.get(k, 'n') != 'n':
                errors.append(f'{k}: requested n, final {cfg.get(k)}')
if errors:
    print('[!] final Kconfig does not satisfy requested root stack:')
    for e in errors: print('    ' + e)
    raise SystemExit(1)
print('[+] final Kconfig matches requested root stack/profile')
PY

# Protect the security/integrity settings of the known-good Equinox base.
grep -q '^CONFIG_LTO_CLANG_FULL=y' "$CFG" || { echo '[!] Full LTO dropped'; exit 1; }
grep -q '^CONFIG_CFI_CLANG=y' "$CFG" || { echo '[!] Clang CFI dropped'; exit 1; }
grep -q '^CONFIG_MODVERSIONS=y' "$CFG" || { echo '[!] MODVERSIONS dropped'; exit 1; }
grep -q '^CONFIG_LOCALVERSION="-Equinox"' "$CFG" || { echo '[!] Equinox branding dropped'; exit 1; }

release="$(make -s O="$OUT" LOCALVERSION= kernelrelease)"
[ "$release" = "5.10.269-Equinox" ] || { echo "[!] unexpected kernel release: $release"; exit 1; }
echo "[*] kernel release: $release"

# -----------------------------------------------------------------------------
# Build Image + in-tree modules. Module.symvers is required for the KMI gate.
# -----------------------------------------------------------------------------
echo "[*] building with Neutron Clang"
set -o pipefail
make -j"$JOBS" O="$OUT" LOCALVERSION= Image modules 2>&1 | tee "$DIST/build-$PROFILE.log"

IMAGE="$OUT/arch/arm64/boot/Image"
[ -s "$IMAGE" ] || { echo '[!] Image was not produced'; exit 1; }
[ -s "$OUT/Module.symvers" ] || { echo '[!] Module.symvers was not produced'; exit 1; }

cp "$IMAGE" "$DIST/Image-$PROFILE"
cp "$CFG" "$DIST/config-$PROFILE"
cp "$OUT/Module.symvers" "$DIST/Module.symvers-$PROFILE"
sha256sum "$DIST/Image-$PROFILE" | tee "$DIST/Image-$PROFILE.sha256"

# -----------------------------------------------------------------------------
# KMI comparison against the already boot-tested Equinox base.
# Added exports are reported but do not break existing modules. Changed/removed
# CRCs are the important signal for prebuilt vendor modules.
# -----------------------------------------------------------------------------
if [ -f "$BASELINE_SYMVERS" ]; then
    python3 - "$BASELINE_SYMVERS" "$OUT/Module.symvers" "$DIST/kmi-$PROFILE.txt" <<'PY'
import sys
oldf,newf,outf=sys.argv[1:]
def load(p):
    d={}
    with open(p, errors='replace') as f:
        for ln in f:
            x=ln.split()
            if len(x)>=2: d[x[1]]=x[0]
    return d
old,new=load(oldf),load(newf)
changed=sorted((k,old[k],new[k]) for k in old.keys() & new.keys() if old[k] != new[k])
removed=sorted(k for k in old.keys()-new.keys())
added=sorted(k for k in new.keys()-old.keys())
with open(outf,'w') as o:
    o.write(f'changed_crc={len(changed)}\nremoved={len(removed)}\nadded={len(added)}\n\n')
    for k,a,b in changed: o.write(f'CHANGED {k} {a} -> {b}\n')
    for k in removed: o.write(f'REMOVED {k}\n')
    for k in added: o.write(f'ADDED {k}\n')
print(f'[KMI] changed CRC: {len(changed)}, removed: {len(removed)}, added: {len(added)}')
if changed or removed:
    print('[KMI] existing vendor modules must NOT be assumed compatible with this Image')
else:
    print('[KMI] no existing exported symbol CRC was changed or removed')
PY
else
    echo "[!] baseline Module.symvers not found: $BASELINE_SYMVERS"
    echo "[!] build is valid, but module compatibility has not been checked"
fi

echo "[+] build complete"
echo "    Image : $DIST/Image-$PROFILE"
echo "    config: $DIST/config-$PROFILE"
echo "    KMI   : $DIST/kmi-$PROFILE.txt"

if [ "$PROFILE" = full ]; then
    echo "[i] Full DroidSpaces profile is intentionally NOT packaged as an Image-only AnyKernel ZIP here."
    echo "[i] Review KMI first, then rebuild/package the vendor module stack if CRCs moved."
fi
