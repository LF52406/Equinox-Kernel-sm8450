#!/usr/bin/env python3
"""Stage actual upstream Linux 5.10.273 source changes on the Equinox branch.

Compare upstream 5.10.269 and 5.10.273 against the current Android/Qualcomm
file with a three-way merge. Files with conflicts remain untouched; the
source remains 5.10.269 until every conflict and a full build are resolved.
Never run on the production branch.
"""
from __future__ import annotations

import hashlib
import lzma
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

BRANCH = "update/equinox-linux-5.10.273-staging-20261031"
BASE_SHA = "4ba940b5b8c5361d23c21923e92116c560a3345c"
BASE_VERSION = "5.10.269"
TARGET_VERSION = "5.10.273"
ROOT = Path(__file__).resolve().parents[2]
REPORT = ROOT / "scripts/equinox/stable-5.10.273-merge-report.txt"


def run(*args: str, cwd: Path = ROOT, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check, text=True)


def fetch(url: str, destination: Path) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Equinox-kernel-stable-port/1.0"})
    h = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=180) as response, destination.open("wb") as out:
        while block := response.read(1024 * 1024):
            h.update(block)
            out.write(block)
    print(f"Downloaded {destination.name}: sha256 {h.hexdigest()}", flush=True)
    return h.hexdigest()


def data(path: Path) -> bytes | None:
    if not path.exists() or path.is_symlink() or not path.is_file():
        return None
    return path.read_bytes()


def unchanged_safe(path: Path) -> bool:
    return (not path.is_symlink()) and (not path.exists() or path.is_file())


def main() -> None:
    if run("git", "branch", "--show-current").stdout.strip() != BRANCH:
        raise RuntimeError("Refusing to change any branch other than isolated staging")
    if run("git", "status", "--porcelain").stdout.strip():
        raise RuntimeError("Working tree must be clean")
    if run("git", "merge-base", "--is-ancestor", BASE_SHA, "HEAD", check=False).returncode:
        raise RuntimeError("Staging does not descend from pinned Equinox production HEAD")
    if not re.search(r"^SUBLEVEL = 269$", (ROOT / "Makefile").read_text(), re.M):
        raise RuntimeError("Expected original 5.10.269 source")
    before = run("git", "rev-parse", "HEAD").stdout.strip()
    with tempfile.TemporaryDirectory(prefix="equinox-stable-") as work:
        work = Path(work)
        dirs = {}
        archive_hashes = {}
        for ver, label in ((BASE_VERSION, "base"), (TARGET_VERSION, "new")):
            dest = work / f"linux-{ver}.tar.xz"
            url = f"https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-{ver}.tar.xz"
            archive_hashes[ver] = fetch(url, dest)
            unpack = work / label
            unpack.mkdir()
            subprocess.run(["tar", "-xJf", str(dest), "--strip-components=1", "-C", str(unpack)],
                           check=True)
            dirs[label] = unpack
            dest.unlink()

        # The official incremental series identifies the exact touched file set.
        touched: set[str] = set()
        for level in range(270, 274):
            url = f"https://cdn.kernel.org/pub/linux/kernel/v5.x/incr/patch-5.10.{level-1}-{level}.xz"
            patch_xz = work / f"patch-{level}.xz"
            fetch(url, patch_xz)
            patch = lzma.open(patch_xz, "rb").read().decode("utf-8", errors="surrogateescape")
            touched.update(re.findall(r"^diff --git a/(.+?) b/(.+)$", patch, re.M))
            patch_xz.unlink()

        paths = sorted({a for a, b in touched if a == b})
        changes: list[str] = []
        conflicts: list[tuple[str, str]] = []
        already: list[str] = []
        identical: list[str] = []
        for rel in paths:
            if rel == "Makefile":
                # Never advertise a release before all source conflicts and
                # kernel build/ABI validation have been completed.
                continue
            old = dirs["base"] / rel
            new = dirs["new"] / rel
            ours = ROOT / rel
            if not all(unchanged_safe(p) for p in (old, new, ours)):
                conflicts.append((rel, "symlink or unsupported file type"))
                continue
            old_bytes, new_bytes, ours_bytes = data(old), data(new), data(ours)
            if old_bytes == new_bytes:
                identical.append(rel)
                continue
            if ours_bytes == new_bytes:
                already.append(rel)
                continue
            if ours_bytes is None and old_bytes is not None:
                conflicts.append((rel, "source removed from Android tree"))
                continue
            if new_bytes is None and old_bytes is not None:
                if ours_bytes == old_bytes:
                    ours.unlink()
                    changes.append(rel)
                else:
                    conflicts.append((rel, "upstream deleted a modified Android file"))
                continue
            if old_bytes is None and new_bytes is not None:
                if ours_bytes is None:
                    ours.parent.mkdir(parents=True, exist_ok=True)
                    ours.write_bytes(new_bytes)
                    shutil.copymode(new, ours)
                    changes.append(rel)
                else:
                    conflicts.append((rel, "upstream added existing Android path"))
                continue
            if new_bytes is None or old_bytes is None or ours_bytes is None:
                conflicts.append((rel, "unexpected file state"))
                continue
            if b"\x00" in old_bytes + new_bytes + ours_bytes:
                conflicts.append((rel, "binary file requiring manual review"))
                continue
            if ours_bytes == old_bytes:
                merged = new_bytes
            else:
                # git merge-file operates on real files and exits 1 for
                # conflicts, 2+ for errors. A conflicting merge is NOT written.
                merge = subprocess.run(
                    ["git", "merge-file", "-p", "--diff3", str(ours), str(old), str(new)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE
                )
                if merge.returncode != 0:
                    conflicts.append((rel, f"three-way conflict (git exit {merge.returncode})"))
                    continue
                merged = merge.stdout
            if merged != ours_bytes:
                ours.write_bytes(merged)
                changes.append(rel)
            else:
                identical.append(rel)

        output = [
            "Equinox Linux 5.10.273 STAGING ONLY - NOT RELEASE READY",
            f"Starting commit: {before}",
            f"Upstream base: {BASE_VERSION} sha256={archive_hashes[BASE_VERSION]}",
            f"Upstream target: {TARGET_VERSION} sha256={archive_hashes[TARGET_VERSION]}",
            "Official Linux release incremental patches: 270, 271, 272, 273",
            f"Touched paths (excluding Makefile): {len(paths)-1}",
            f"Source files merged/modified: {len(changes)}",
            f"Already equal to upstream: {len(already)}",
            f"Net unchanged: {len(identical)}",
            f"UNRESOLVED files: {len(conflicts)}",
            "",
            "IMPORTANT: Conflicts are not silently discarded. The Linux version",
            "remains at 5.10.269; 5.10.273 cannot be claimed until all missing",
            "changes are manually resolved and a full build, ABI/KMI check, and",
            "physical device test have succeeded. No production branch is changed.",
            "",
            "Unresolved files:",
            *[f"{p} :: {reason}" for p, reason in conflicts],
            "",
            "Successfully staged changed source files:",
            *changes,
        ]
        REPORT.write_text("\n".join(output) + "\n")
        print("\n".join(output[:16]), flush=True)
        run("git", "add", "-A")
        bad = run("git", "diff", "--cached", "--check", check=False)
        if bad.returncode != 0:
            raise RuntimeError("Merged files failed diff --check:\n" + bad.stdout + bad.stderr)
        if not changes:
            raise RuntimeError("No actual kernel source changes were produced")
        run("git", "-c", "user.name=github-actions[bot]",
            "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "commit", "-m", "stable: stage nonconflicting Linux 5.10.273 source updates (WIP)")
        after = run("git", "rev-parse", "HEAD").stdout.strip()
        print(f"Staging commit: {after}; conflicts: {len(conflicts)}", flush=True)
        run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
        if conflicts:
            print("INCOMPLETE: unresolved upstream changes require manual porting.", flush=True)


if __name__ == "__main__":
    main()
