# Equinox production build

Target: POCO F5 Pro / Redmi K60 (`mondrian`), Linux 5.10.x.

Production builds must use:

```bash
bash scripts/equinox/build-production.sh
```

The production flow is intentionally strict:

- base source is pinned to the known-good Equinox commit;
- Neutron Clang, KernelSU-Next, SUSFS and AnyKernel3 are pinned;
- the KernelSU-Next release and commit are defined only by `KSUN_TAG` and `KSUN_PIN` in `scripts/equinox/pins.env`;
- build and package metadata derive the displayed KernelSU-Next version from `KSUN_TAG` instead of duplicating a hardcoded version;
- a clean baseline `Module.symvers` is built first with the same compiler/config stack;
- DroidSpaces uses the GKI KMI-safe profile;
- SYSVIPC fields are relocated into Android KABI reserve slots;
- any changed CRC or removed existing export fails the build before packaging;
- the flashable ZIP is created only after the required KMI gate passes.

The `full` DroidSpaces config is kept only for ABI research. It is blocked from the normal Image-only production flow because options such as `CGROUP_DEVICE`, `CGROUP_PIDS`, `BRIDGE_NETFILTER` and `NF_TABLES` can change GKI KMI and break prebuilt vendor modules.

Successful output for the current kernel base:

```text
~/dist/equinox-production/Equinox-5.10.269-mondrian.zip
```

## Publishing a GitHub Release

Official releases are published from the already-built and tested production ZIP. GitHub does not rebuild the kernel.

The release script validates the ZIP, checks the embedded device/kernel metadata, calculates SHA256, generates a `.sha256` file and uploads both files to GitHub Releases.

For the current test build:

```bash
bash scripts/equinox/publish-release.sh 5.10.269-test1
```

Supported tag formats:

```text
5.10.269-test1   test build / prerelease
5.10.269-r2      revision on the same Linux base
5.10.270         stable release for a new Linux base
```

Release notes are stored in:

```text
scripts/equinox/release-notes/<tag>.md
```

`gh auth login` must be completed once on the build server before publishing.
