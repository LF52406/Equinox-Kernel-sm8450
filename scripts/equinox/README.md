# Equinox production build

Target: POCO F5 Pro / Redmi K60 (`mondrian`), Linux 5.10.269.

Production builds must use:

```bash
bash scripts/equinox/build-production.sh
```

The production flow is intentionally strict:

- base source is pinned to the known-good Equinox commit;
- Neutron Clang, KernelSU-Next 3.3.0, SUSFS 2.3.0 and AnyKernel3 are pinned;
- a clean baseline `Module.symvers` is built first with the same compiler/config stack;
- DroidSpaces uses the GKI KMI-safe profile;
- SYSVIPC fields are relocated into Android KABI reserve slots;
- any changed CRC or removed existing export fails the build before packaging;
- the flashable ZIP is created only after `changed_crc=0` and `removed=0`.

The `full` DroidSpaces config is kept only for ABI research. It is blocked from the normal Image-only production flow because options such as `CGROUP_DEVICE`, `CGROUP_PIDS`, `BRIDGE_NETFILTER` and `NF_TABLES` can change GKI KMI and break prebuilt vendor modules.

Successful output:

```text
~/dist/equinox-production/Equinox-5.10.269-mondrian.zip
```
