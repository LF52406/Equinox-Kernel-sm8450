<div align="center">

<img src="assets/equinox-banner.png" alt="Equinox Kernel" width="100%">

# Equinox Kernel

[![Linux](https://img.shields.io/badge/Linux-5.10.269-38bdf8?style=for-the-badge&labelColor=0b1020)](https://www.kernel.org/)
[![KernelSU Next](https://img.shields.io/badge/KernelSU--Next-3.4.0-a78bfa?style=for-the-badge&labelColor=0b1020)](https://github.com/KernelSU-Next/KernelSU-Next)
[![SUSFS](https://img.shields.io/badge/SUSFS-2.3.0-f59e0b?style=for-the-badge&labelColor=0b1020)](https://gitlab.com/simonpunk/susfs4ksu)
[![BBR](https://img.shields.io/badge/TCP-BBR-22c55e?style=for-the-badge&labelColor=0b1020)](#features)
[![KMI](https://img.shields.io/badge/KMI-VERIFIED-14b8a6?style=for-the-badge&labelColor=0b1020)](#current-build)

**Custom kernel for POCO F5 Pro / Redmi K60**  
`mondrian` · Qualcomm SM8475 / waipio · Snapdragon 8+ Gen 1

**Developer:** [LF52406](https://github.com/LF52406)

### [Download builds](../../releases)

</div>

---

## Current Build

| Component | Current |
|:--|:--|
| **Kernel** | `5.10.269-Equinox` |
| **Toolchain** | Neutron Clang `24.0.0git` |
| **Root stack** | KernelSU-Next `3.4.0` + SUSFS `2.3.0` |
| **Containers** | DroidSpaces supported |
| **TCP** | BBR supported and verified · CUBIC default |
| **Build** | Full LTO · Clang CFI · MODVERSIONS · KMI verified |

---

## Features

| Group | Included |
|:--|:--|
| **Root & hiding** | KernelSU-Next · SUSFS |
| **Containers** | DroidSpaces · PID namespaces · IPC / SYSVIPC |
| **Networking** | TCP BBR · runtime congestion-control switching · CUBIC default |
| **Kernel build** | Full LTO · Clang CFI · MODVERSIONS · strict KMI validation |
| **Device** | mondrian production config · Goodix touch stability fixes |
| **Packaging** | Verified AnyKernel3 release package |

---

## Latest Changes

### Linux 5.10.269

- KernelSU-Next updated to `3.4.0`
- SUSFS `2.3.0` integrated
- DroidSpaces support added with the KMI-safe production profile
- TCP BBR support added and verified on-device
- Production KMI validation and verified AnyKernel3 packaging added

[View full release notes](../../releases)

---

## Downloads & Flashing

Official Equinox builds are published through **GitHub Releases**.

Current package: `Equinox-5.10.269-mondrian.zip`

Before flashing, back up your current `boot.img` or working kernel and make sure you have a recovery or fastboot restore method. Flash the Equinox AnyKernel3 ZIP from **Assets** and reboot.

> GitHub-generated `Source code` archives are not flashable kernel packages.

---

## Reporting Issues

When reporting a problem, include the kernel version, a short reproduction description and relevant logs: `dmesg`, `logcat`, `pstore / ramoops`, or watchdog / panic logs when available.

[Open an issue](../../issues)

---

## Support Development

If you like **Equinox Kernel** and want to support its continued development, voluntary donations help cover build-server costs, development infrastructure and testing.

Support is completely optional and always appreciated.

<div align="center">

[![PayPal](https://img.shields.io/badge/PayPal-Support-003087?style=for-the-badge&logo=paypal&logoColor=white)](https://www.paypal.me/LF52406)
[![Patreon](https://img.shields.io/badge/Patreon-Support-FF424D?style=for-the-badge&logo=patreon&logoColor=white)](https://patreon.com/InfernalGT)
[![Boosty](https://img.shields.io/badge/Boosty-Support-F15F2C?style=for-the-badge&logo=boosty&logoColor=white)](https://boosty.to/infernalgt/donate)

</div>

---

## Credits & Upstreams

Thanks to the developers and projects whose work is used by Equinox Kernel:

- **LineageOS** - Xiaomi SM8450 device kernel and Qualcomm SM8450 common-kernel upstream
- **Android Common Kernel / Linux Kernel** - Android kernel infrastructure and upstream Linux development
- **KernelSU-Next** - kernel root implementation
- **simonpunk / SUSFS** and **Zhanfg/susfs4ksu** - SUSFS and Linux 5.10 integration
- **ravindu644 / DroidSpaces** - container runtime and kernel requirements
- **Neutron Toolchains** - LLVM/Clang toolchain used for Equinox production builds
- **osm0sis / AnyKernel3** - flashable kernel packaging framework
- **Qualcomm, Xiaomi, LineageOS and Linux kernel contributors** - platform, driver and upstream kernel work
