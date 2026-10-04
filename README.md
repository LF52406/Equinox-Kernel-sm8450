<div align="center">

<img src="assets/equinox-banner.png" alt="Equinox Kernel" width="100%">

<br>

[![Latest Release](https://img.shields.io/github/v/release/LF52406/Equinox-Kernel-sm8450?display_name=tag&style=for-the-badge&label=RELEASE&labelColor=0b1020&color=f59e0b)](../../releases)
[![Linux](https://img.shields.io/badge/Linux-5.10.269-38bdf8?style=for-the-badge&labelColor=0b1020)](https://www.kernel.org/)
[![KernelSU Next](https://img.shields.io/badge/KernelSU--Next-3.4.0-a78bfa?style=for-the-badge&labelColor=0b1020)](https://github.com/KernelSU-Next/KernelSU-Next)
[![SUSFS](https://img.shields.io/badge/SUSFS-2.3.0-f59e0b?style=for-the-badge&labelColor=0b1020)](https://gitlab.com/simonpunk/susfs4ksu)
[![KMI](https://img.shields.io/badge/KMI-VERIFIED-22c55e?style=for-the-badge&labelColor=0b1020)](#07--build--integrity)
[![Downloads](https://img.shields.io/github/downloads/LF52406/Equinox-Kernel-sm8450/total?style=for-the-badge&label=DOWNLOADS&labelColor=0b1020&color=22c55e)](../../releases)

### Custom Android kernel for POCO F5 Pro / Redmi K60

`mondrian` · Qualcomm SM8475 / waipio · Snapdragon 8+ Gen 1 · Android 17

### [⬇ Download Equinox Kernel](../../releases)

</div>

---

## ![01](https://img.shields.io/badge/01-f59e0b?style=flat-square&labelColor=0b1020) Current Build

| Component | Current |
|:--|:--|
| **Kernel** | `5.10.269-Equinox` |
| **Device** | POCO F5 Pro / Redmi K60 |
| **Codename** | `mondrian` |
| **Platform** | Qualcomm SM8475 / waipio |
| **KernelSU-Next** | `3.4.0` |
| **SUSFS** | `2.3.0` |
| **DroidSpaces** | Supported |
| **TCP BBR** | Supported and verified |
| **Default TCP CC** | CUBIC |
| **Toolchain** | Neutron Clang `24.0.0git` |
| **KMI** | Verified |

> Exact build information and checksums are published with each GitHub Release.

---

## ![02](https://img.shields.io/badge/02-38bdf8?style=flat-square&labelColor=0b1020) Features

### Root & Hiding

| Feature | Status |
|:--|:--:|
| KernelSU-Next | ✅ Built-in |
| SUSFS | ✅ Supported |
| Production root stack | ✅ Integrated |

### Containers

| Feature | Status |
|:--|:--:|
| DroidSpaces | ✅ Supported |
| PID namespaces | ✅ Enabled |
| IPC / SYSVIPC | ✅ Enabled |
| KMI-safe integration | ✅ Verified |
| Linux container startup | ✅ Tested |

### Networking

| Feature | Status |
|:--|:--:|
| TCP BBR | ✅ Supported and verified |
| CUBIC | ✅ Default |
| Runtime TCP congestion-control switching | ✅ Supported |

BBR is built into Equinox and has been verified on real TCP connections. CUBIC remains the default congestion-control algorithm.

### Kernel & Build

| Feature | Status |
|:--|:--:|
| Full LTO | ✅ Enabled |
| Clang CFI | ✅ Enabled |
| MODVERSIONS | ✅ Enabled |
| Production KMI validation | ✅ Enabled |
| Pinned external dependencies | ✅ Enabled |
| AnyKernel3 packaging | ✅ Verified |

### Device-specific

- Goodix touch stability fixes for mondrian
- POCO F5 Pro / Redmi K60 production configuration
- Android 17 compatible kernel branch

---

## ![03](https://img.shields.io/badge/03-a78bfa?style=flat-square&labelColor=0b1020) Latest Changes

### Linux 5.10.269

- Updated KernelSU-Next to `3.4.0`
- Integrated SUSFS `2.3.0`
- Added DroidSpaces support using the KMI-safe production profile
- Added TCP BBR congestion-control support
- Verified BBR operation on real TCP connections
- Kept CUBIC as the default TCP congestion-control algorithm
- Added strict production KMI validation
- Added verified AnyKernel3 production packaging

[**View releases and full release notes →**](../../releases)

---

## ![04](https://img.shields.io/badge/04-22c55e?style=flat-square&labelColor=0b1020) Downloads

Official Equinox builds are distributed through **GitHub Releases**.

### [⬇ Download latest available build](../../releases)

Current package:

`Equinox-5.10.269-mondrian.zip`

Use the Equinox flashable ZIP from **Assets**. GitHub-generated `Source code` archives are not flashable kernel packages.

---

## ![05](https://img.shields.io/badge/05-f97316?style=flat-square&labelColor=0b1020) Installation

1. Back up your current working kernel or `boot.img`.
2. Make sure you have a working recovery or fastboot restore method.
3. Download the Equinox ZIP from **Releases**.
4. Verify the published SHA256 checksum when possible.
5. Flash the AnyKernel3 package and reboot.

Equinox release packages replace the kernel Image while preserving the ROM boot environment.

---

## ![06](https://img.shields.io/badge/06-ef4444?style=flat-square&labelColor=0b1020) Bug Reports

When reporting a problem, include the Equinox kernel version, a clear description and the steps required to reproduce it.

Useful logs:

- `adb bugreport`
- `logcat`
- `dmesg`
- `pstore / ramoops`
- kernel panic / watchdog logs when available

Reports with logs are significantly easier to investigate.

---

## ![07](https://img.shields.io/badge/07-14b8a6?style=flat-square&labelColor=0b1020) Build & Integrity

Official Equinox builds are produced through the project production pipeline using pinned external dependencies. The production kernel is compared against a known-good baseline before packaging, and release packaging proceeds only after the required KMI checks pass.

---

## ![08](https://img.shields.io/badge/08-60a5fa?style=flat-square&labelColor=0b1020) Credits & Upstreams

Equinox Kernel is built on open-source Android and Linux kernel work. Thanks to all upstream developers and contributors whose work makes this project possible.

- **[LF52406](https://github.com/LF52406)**  
  Developer of Equinox Kernel.

- **[LineageOS/android_kernel_xiaomi_sm8450](https://github.com/LineageOS/android_kernel_xiaomi_sm8450)**  
  Xiaomi SM8450 device-kernel base and upstream source used by Equinox.

- **[LineageOS/android_kernel_qcom_sm8450](https://github.com/LineageOS/android_kernel_qcom_sm8450)**  
  Qualcomm SM8450 common-kernel upstream and source of platform fixes.

- **[Android Common Kernel](https://android.googlesource.com/kernel/common)**  
  Android kernel infrastructure, GKI/KMI work and Android-specific kernel changes.

- **[Linux Kernel](https://www.kernel.org/)**  
  Linux upstream and stable kernel development.

- **[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)**  
  Kernel root implementation used by Equinox.

- **[SUSFS](https://gitlab.com/simonpunk/susfs4ksu)** by **simonpunk**  
  Original SUSFS project.

- **[Zhanfg/susfs4ksu](https://github.com/Zhanfg/susfs4ksu)**  
  Android 13 / Linux 5.10 SUSFS integration source used by the Equinox production build.

- **[DroidSpaces](https://github.com/ravindu644/Droidspaces-OSS)** by **ravindu644**  
  Android/Linux container runtime supported by Equinox.

- **[Neutron Clang](https://github.com/Neutron-Toolchains/clang-build-catalogue)**  
  LLVM/Clang toolchain used for official Equinox production builds.

- **[Neutron antman](https://github.com/Neutron-Toolchains/antman)**  
  Toolchain compatibility utility used by the Equinox build system when required by the build host.

- **[AnyKernel3](https://github.com/osm0sis/AnyKernel3)** by **osm0sis**  
  Flashable kernel packaging framework used for Equinox releases.

- **Qualcomm, Xiaomi, LineageOS and Linux kernel contributors**  
  Device, SoC, driver and kernel work used by the mondrian / SM8475 platform.

---

## ![09](https://img.shields.io/badge/09-ec4899?style=flat-square&labelColor=0b1020) Support Development

Equinox Kernel is developed independently.

If you find Equinox useful and would like to support its continued development, you can make a voluntary donation. Contributions help cover build-server costs, development infrastructure, testing and future kernel work.

Support is completely optional, and every contribution is appreciated.

<div align="center">

[![PayPal](https://img.shields.io/badge/PayPal-Support-003087?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.me/LF52406)
[![Patreon](https://img.shields.io/badge/Patreon-Support-FF424D?style=for-the-badge&logo=patreon&logoColor=white)](https://patreon.com/InfernalGT)
[![Boosty](https://img.shields.io/badge/Boosty-Support-F15F2C?style=for-the-badge&logo=boosty&logoColor=white)](https://boosty.to/infernalgt/donate)

</div>

---

<div align="center">

### Equinox Kernel

**Developer:** [LF52406](https://github.com/LF52406)

POCO F5 Pro / Redmi K60 · `mondrian`

[Releases](../../releases) · [Issues](../../issues)

</div>
