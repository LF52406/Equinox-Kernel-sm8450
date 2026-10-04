#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source scripts/equinox/pins.env

OUT="${OUT:-$HOME/out/equinox-production}"
DIST="${DIST:-$HOME/dist/equinox-production}"
TC="${NEUTRON_DIR:-$HOME/toolchains/neutron-$NEUTRON_BUILD}"
KMI_REPORT="${KMI_REPORT:-$DIST/kmi-kmi-safe.txt}"
AK3="${ANYKERNEL_DIR:-$HOME/build/AnyKernel3-equinox}"
ZIP_NAME="${ZIP_NAME:-Equinox-5.10.269-mondrian.zip}"
IMAGE="$OUT/arch/arm64/boot/Image"
KSUN_VERSION="${KSUN_TAG#v}"

for cmd in git zip unzip sha256sum make; do
    command -v "$cmd" >/dev/null || { echo "[!] missing host tool: $cmd"; exit 1; }
done

[ -s "$IMAGE" ] || { echo "[!] missing kernel Image: $IMAGE"; exit 1; }
[ -s "$KMI_REPORT" ] || { echo "[!] missing KMI report: $KMI_REPORT"; exit 1; }
grep -qx 'changed_crc=0' "$KMI_REPORT" || { echo '[!] KMI changed_crc is not zero; refusing to package'; exit 1; }
grep -qx 'removed=0' "$KMI_REPORT" || { echo '[!] KMI removed count is not zero; refusing to package'; exit 1; }

export PATH="$TC/bin:$PATH"
export ARCH=arm64 LLVM=1 LLVM_IAS=1

release="$(make -s O="$OUT" LOCALVERSION= kernelrelease)"
[ "$release" = "$EXPECTED_KERNEL_RELEASE" ] || { echo "[!] unexpected kernel release: $release"; exit 1; }

clang_line="$(clang --version | sed -n '1p')"
echo "$clang_line" | grep -qi 'Neutron clang' || { echo '[!] package toolchain metadata is not Neutron Clang'; exit 1; }

source_commit="$(git rev-parse --short=12 HEAD)"
image_sha="$(sha256sum "$IMAGE" | awk '{print $1}')"

rm -rf "$AK3"
mkdir -p "$DIST"
git clone "$ANYKERNEL_REPO" "$AK3"
git -C "$AK3" checkout --detach "$ANYKERNEL_PIN"
[ "$(git -C "$AK3" rev-parse HEAD)" = "$ANYKERNEL_PIN" ] || { echo '[!] AnyKernel3 pin mismatch'; exit 1; }

rm -rf "$AK3/.git" "$AK3/.github" "$AK3/README.md" "$AK3/modules" "$AK3/patch" "$AK3/ramdisk"
cp "$IMAGE" "$AK3/Image"
chmod 0644 "$AK3/Image"

cat > "$AK3/anykernel.sh" <<'AK3EOF'
### AnyKernel3 Ramdisk Mod Script
## Equinox Kernel for POCO F5 Pro / Redmi K60 (mondrian)

properties() { '
kernel.string=Equinox Kernel 5.10.269
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=mondrian
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

. tools/ak3-core.sh

case "$SLOT" in
    _a) active_slot="A" ;;
    _b) active_slot="B" ;;
    *) abort "Unable to determine active A/B slot. Aborting..." ;;
esac

ui_print " "
ui_print " =========================================="
ui_print "              EQUINOX KERNEL"
ui_print " =========================================="
ui_print " Device   : POCO F5 Pro / Redmi K60"
ui_print " Codename : mondrian"
ui_print " Kernel   : 5.10.269-Equinox"
ui_print " KSUN     : @KSUN_VERSION@"
ui_print " SUSFS    : 2.3.0"
ui_print " Spaces   : DroidSpaces support"
ui_print " Slot     : ${active_slot}"
ui_print " Target   : ${BLOCK}"
ui_print " =========================================="
ui_print " "
ui_print " Replacing kernel Image..."
ui_print " "

# Image-only replacement. Preserve the ROM's existing ramdisk/header/bootconfig.
split_boot
flash_boot

ui_print " "
ui_print " Equinox installation complete."
ui_print " "
AK3EOF
sed -i "s/@KSUN_VERSION@/$KSUN_VERSION/g" "$AK3/anykernel.sh"
chmod 0755 "$AK3/anykernel.sh"
sh -n "$AK3/anykernel.sh"

cat > "$AK3/version" <<EOF2
Equinox Kernel

Kernel: $release
Device: POCO F5 Pro / Redmi K60
Codename: mondrian
Platform: SM8475 / waipio
Builder: LF52406
Toolchain: $clang_line

Changes:
- Updated kernel base to Linux 5.10.269
- Built with pinned Neutron Clang
- Integrated KernelSU-Next $KSUN_VERSION
- Integrated SUSFS 2.3.0
- Added DroidSpaces GKI support
- Applied Android KABI relocation for SYSVIPC task_struct fields
- Applied Android KABI relocation for POSIX_MQUEUE user_struct mq_bytes
- Used minimal DroidSpaces GKI production configuration
- Full LTO enabled
- Clang CFI enabled
- MODVERSIONS enabled
- Strict KMI gate passed: changed_crc=0, removed=0

Source commit: $source_commit
Base commit: $BASE_COMMIT
KernelSU-Next pin: $KSUN_PIN
SUSFS pin: $SUSFS_PIN
AnyKernel3 pin: $ANYKERNEL_PIN
Image SHA256: $image_sha
EOF2

rm -f "$DIST/$ZIP_NAME" "$DIST/$ZIP_NAME.sha256"
(
    cd "$AK3"
    zip -r9 "$DIST/$ZIP_NAME" . -x '*.git*' '*.zip'
)

unzip -t "$DIST/$ZIP_NAME" >/dev/null

zip_image_sha="$(unzip -p "$DIST/$ZIP_NAME" Image | sha256sum | awk '{print $1}')"
[ "$zip_image_sha" = "$image_sha" ] || {
    echo '[!] Image SHA256 changed during packaging'
    echo "    source: $image_sha"
    echo "    zip   : $zip_image_sha"
    exit 1
}

zip_list="$(unzip -Z1 "$DIST/$ZIP_NAME")"
for required in Image anykernel.sh version META-INF/com/google/android/update-binary tools/ak3-core.sh; do
    grep -Fxq "$required" <<<"$zip_list" || { echo "[!] package missing $required"; exit 1; }
done

sha256sum "$DIST/$ZIP_NAME" > "$DIST/$ZIP_NAME.sha256"

echo "[+] flashable package verified"
echo "    ZIP   : $DIST/$ZIP_NAME"
echo "    SHA256: $(awk '{print $1}' "$DIST/$ZIP_NAME.sha256")"
echo "    Image : $image_sha"
