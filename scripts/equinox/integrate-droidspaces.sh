#!/usr/bin/env bash
set -euo pipefail

KROOT="${1:-$PWD}"
SCHED="$KROOT/include/linux/sched.h"

[ -f "$SCHED" ] || { echo "[!] missing $SCHED"; exit 1; }

echo "[*] DroidSpaces: preserve task_struct KMI while enabling SYSVIPC"

python3 - "$SCHED" <<'PY'
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

if "ANDROID_KABI_USE(6, struct sysv_sem sysvsem)" in s:
    print("[=] DroidSpaces task_struct relocation already present")
    raise SystemExit(0)

old_fields = (
    "#ifdef CONFIG_SYSVIPC\n"
    "\tstruct sysv_sem\t\t\tsysvsem;\n"
    "\tstruct sysv_shm\t\t\tsysvshm;\n"
    "#endif\n"
)

new_fields = (
    "#ifdef CONFIG_SYSVIPC\n"
    "\t/* Equinox/DroidSpaces: fields are stored in Android KABI reserves below. */\n"
    "\t/* struct sysv_sem\t\t\tsysvsem; */\n"
    "\t/* struct sysv_shm\t\t\tsysvshm; */\n"
    "#endif\n"
)

if old_fields not in s:
    raise SystemExit("[!] task_struct SYSVIPC anchor changed; refusing an unsafe edit")

old_reserves = (
    "\tANDROID_KABI_RESERVE(6);\n"
    "\tANDROID_KABI_RESERVE(7);\n"
    "\tANDROID_KABI_RESERVE(8);\n"
)

new_reserves = (
    "#ifdef CONFIG_SYSVIPC\n"
    "\tANDROID_KABI_USE(6, struct sysv_sem sysvsem);\n"
    "\t_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(7); ANDROID_KABI_RESERVE(8),\n"
    "\t\t\t      struct sysv_shm sysvshm);\n"
    "#else\n"
    "\tANDROID_KABI_RESERVE(6);\n"
    "\tANDROID_KABI_RESERVE(7);\n"
    "\tANDROID_KABI_RESERVE(8);\n"
    "#endif\n"
)

if s.count(old_reserves) != 1:
    raise SystemExit("[!] KABI reserves 6..8 are missing or ambiguous; refusing an unsafe edit")

s = s.replace(old_fields, new_fields, 1)
s = s.replace(old_reserves, new_reserves, 1)
open(path, "w", encoding="utf-8").write(s)
print("[+] SYSVIPC relocated: sysvsem -> reserve 6, sysvshm -> reserves 7+8")
PY

# Never use the upstream global CRC/module-version bypass here.
if git -C "$KROOT" diff -- include/linux/sched.h | grep -qE 'check_version|CONFIG_MODVERSIONS|abi_gki_protected'; then
    echo "[!] unexpected ABI-bypass change detected"
    exit 1
fi

echo "[+] DroidSpaces KMI relocation prepared"
