# Linux 5.10.273 integration status (mondrian)

This is a staging branch. **Do not ship as Linux 5.10.273 until the source and build have been validated.**

## Starting point
- Original source: Equinox 5.10.269 (commit `4ba940b5b8c5361d23c21923e92116c560a3345c`).
- Device: POCO F5 Pro / Redmi K60 (mondrian), Android 17.
- Existing feature stack: KernelSU-Next v3.4.2, SUSFS v2.3.0, DroidSpaces KMI-safe.
- Existing toolchain and build pins are unchanged.

## Source
- Linux stable incremental archives, in order:
  1. `patch-5.10.269-270.xz`
  2. `patch-5.10.270-271.xz`
  3. `patch-5.10.271-272.xz`
  4. `patch-5.10.272-273.xz`
- Official upstream: https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/
- The full Linux stable patch cannot be assumed to apply to the heavily modified Android/Qualcomm kernel. The integration tool refuses any patch rejected by `git apply --check`. It never silently prefers upstream or vendor changes.

## Execute

```bash
git switch update/equinox-linux-5.10.273-staging-20261031
bash scripts/equinox/update-stable-5.10.273.sh
```

The default is a **non-pushing** integration check. To publish a *fully clean* application to this staging branch only:

```bash
EQUINOX_PUSH_STAGING=1 bash scripts/equinox/update-stable-5.10.273.sh
```

The GitHub Actions workflow performs the same guarded check and attempts to update staging only if all four official patches apply without rejects.

## Release gates

1. Full source integration: every upstream change accounted for, conflicts reviewed individually, and no skipped security fixes.
2. Update candidate kernel-release metadata, while **retaining 5.10.269 as the original boot-tested KMI baseline** in `build-production.sh`.
3. Build with the pinned Neutron Clang and pinned KernelSU/SUSFS/DroidSpaces stack.
4. Verify `Module.symvers`: no removed symbols and no changed CRC in the prebuilt vendor-module ABI.
5. Verify source/device module compatibility, boots, F2FS, Wi-Fi, Bluetooth, Goodix touch, display, and charge behavior on mondrian.
6. Only then tag, package, and announce Linux 5.10.273.

**No compatibility, successful build, or device boot is implied by this staging branch.**
