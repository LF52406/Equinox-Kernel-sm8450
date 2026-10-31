# Linux 5.10.273 source port — Equinox / mondrian

## Current status: INCOMPLETE — NOT FOR FLASHING

- Production reference: `equinox-5.10.269-ksun-susfs-droidspaces` @ `4ba940b5b8c5361d23c21923e92116c560a3345c`.
- Isolated source port: `update/equinox-linux-5.10.273-staging-20261031`.
- Android 17 / POCO F5 Pro / Redmi K60 (mondrian).
- The original source port staged actual upstream edits from Linux 5.10.270 through 5.10.273 in 1572 files, but recorded 41 conflicting files. See `stable-5.10.273-merge-report.txt` for the **original snapshot**, not a current unresolved count.
- `Makefile` intentionally remains at `SUBLEVEL = 269`. Do not announce or flash as 5.10.273.

## Manually reviewed conflicts ported after the source snapshot

- `b8d969d`: Qualcomm BAM DMA: disable runtime autosuspend on removal.
- `a123cac`: libertas_tf: synchronously stop the timer before releasing commands.
- `15901a5`: IRQ domain: upstream declaration and instantiate API.
- `3201997`: MM: upstream KMAP_LOCAL option.
- `4522652`: Bluetooth HCI: handle device-name registration errors.
- `ae64e29`: TCP: matching syn_recv_sock callback declaration, retaining Android KABI.
- `fd54f36`: F2FS: check writeback failure in collapse_range.
- `51cd5d4`: fsnotify: flag used by staged upstream connector teardown.
- Qualcomm QRTR's allocation-failure node-release fix was already present in the vendor implementation; no duplicate change was made.

These are source reviews and commits, **not** build or hardware validation. Many source conflicts remain.

## Upstream source

- Official Linux 5.10.269 / 5.10.273 tarballs and the 270, 271, 272, 273 incremental patches from `cdn.kernel.org`, downloaded and compared by the original staging job.
- Branch history preserves the upstream integration source, the initial merge report, and manual conflict-fix commits.

## Release criteria

1. Resolve and review **all** remaining conflicts, including Qualcomm remoteproc/GLINK, arm64, F2FS, NFS and networking; verify all target changes are present or already backported.
2. Cross-check Android/Qualcomm and Linux Stable behavior, preserving KernelSU-Next v3.4.2, SUSFS v2.3.0, DroidSpaces and Xiaomi device drivers.
3. Set 5.10.273 only when the complete source port is ready; keep the original 5.10.269 KMI baseline separately for comparison.
4. Compile with the pinned Neutron toolchain, check `Module.symvers` CRC and symbol compatibility with shipped vendor modules.
5. Verify boot and F2FS, Wi-Fi, Bluetooth, touch, display, USB, thermal and charging on mondrian.

Do not merge this branch into the production release until every gate passes.
