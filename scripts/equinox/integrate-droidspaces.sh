#!/usr/bin/env bash
set -euo pipefail

KROOT="${1:-$PWD}"
SCHED="$KROOT/include/linux/sched.h"
SCHED_USER="$KROOT/include/linux/sched/user.h"
KSUN_KCONFIG="$KROOT/drivers/kernelsu/Kconfig"

[ -f "$SCHED" ] || { echo "[!] missing $SCHED"; exit 1; }
[ -f "$SCHED_USER" ] || { echo "[!] missing $SCHED_USER"; exit 1; }

echo "[*] DroidSpaces: preserve Android KMI for SYSVIPC and POSIX_MQUEUE"

# DroidSpaces upstream requires the GKI below-6.12 SYSVIPC KABI fix before
# CONFIG_SYSVIPC is enabled. Keep task_struct layout and genksyms view stable by
# consuming Android KABI reserves 6, 7 and 8 instead of adding fields in place.
python3 - "$SCHED" <<'PY'
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

if "ANDROID_KABI_USE(6, struct sysv_sem sysvsem)" in s:
    print("[=] DroidSpaces SYSVIPC KMI relocation already present")
    raise SystemExit(0)

old_fields = (
    "#ifdef CONFIG_SYSVIPC\n"
    "\tstruct sysv_sem\t\t\tsysvsem;\n"
    "\tstruct sysv_shm\t\t\tsysvshm;\n"
    "#endif\n"
)

new_fields = (
    "#ifdef CONFIG_SYSVIPC\n"
    "\t/* DroidSpaces: fields are stored in Android KABI reserves below. */\n"
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

# Linux 5.10 GKI also needs DroidSpaces' POSIX_MQUEUE KABI fix. Enabling
# CONFIG_POSIX_MQUEUE normally inserts mq_bytes into struct user_struct and
# changes CRCs for a very large part of the exported KMI. Store mq_bytes in
# Android KABI reserve 1 instead, matching the upstream DroidSpaces GKI patch.
python3 - "$SCHED_USER" <<'PY'
import re
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()

if "ANDROID_KABI_USE(1, unsigned long mq_bytes)" in s:
    print("[=] DroidSpaces POSIX_MQUEUE KMI relocation already present")
    raise SystemExit(0)

field_re = re.compile(
    r'(^#ifdef CONFIG_POSIX_MQUEUE\n'
    r'(?P<body>(?:[^\n]*\n)*?)'
    r'^[ \t]*unsigned long mq_bytes;[^\n]*\n'
    r'(?P<tail>(?:[^\n]*\n)*?)'
    r'^#endif\n)',
    re.M,
)
match = field_re.search(s)
if not match:
    raise SystemExit("[!] user_struct POSIX_MQUEUE mq_bytes anchor changed; refusing an unsafe edit")

block = match.group(0)
block = re.sub(
    r'^[ \t]*unsigned long mq_bytes;[^\n]*$',
    '\t/* mq_bytes is stored in Android KABI reserve 1 below. */',
    block,
    count=1,
    flags=re.M,
)
s = s[:match.start()] + block + s[match.end():]

reserve_re = re.compile(
    r'(?P<indent>[ \t]*)ANDROID_OEM_DATA_ARRAY\(1, 2\);\n'
    r'(?P=indent)ANDROID_KABI_RESERVE\(1\);'
)
reserve_match = reserve_re.search(s)
if not reserve_match:
    raise SystemExit("[!] user_struct KABI reserve 1 anchor changed; refusing an unsafe edit")
indent = reserve_match.group('indent')
replacement = (
    f"{indent}ANDROID_OEM_DATA_ARRAY(1, 2);\n"
    "#ifdef CONFIG_POSIX_MQUEUE\n"
    f"{indent}ANDROID_KABI_USE(1, unsigned long mq_bytes);\n"
    "#else\n"
    f"{indent}ANDROID_KABI_RESERVE(1);\n"
    "#endif"
)
s = s[:reserve_match.start()] + replacement + s[reserve_match.end():]

open(path, "w", encoding="utf-8").write(s)
print("[+] POSIX_MQUEUE relocated: mq_bytes -> user_struct reserve 1")
PY

# SUSFS 2.3.0 currently contains one help line whose indentation is
# "tab + spaces + tab". Kconfig rejects that as "space before tab in indent".
# The KernelSU checkout is linked under drivers/kernelsu, so normalize only
# leading whitespace there after the SUSFS menu has been integrated.
if [ -f "$KSUN_KCONFIG" ]; then
    python3 - "$KSUN_KCONFIG" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
lines = text.splitlines(keepends=True)
changed = 0
out = []

for line in lines:
    m = re.match(r"^[ \t]+", line)
    if m:
        prefix = m.group(0)
        normalized = prefix
        while " \t" in normalized:
            normalized = normalized.replace(" \t", "  ")
        if normalized != prefix:
            line = normalized + line[len(prefix):]
            changed += 1
    out.append(line)

open(path, "w", encoding="utf-8").writelines(out)

bad = []
for no, line in enumerate(out, 1):
    m = re.match(r"^[ \t]+", line)
    if m and " \t" in m.group(0):
        bad.append(no)

if bad:
    raise SystemExit(f"[!] invalid space-before-tab indentation remains in KernelSU Kconfig: {bad}")

print(f"[+] KernelSU/SUSFS Kconfig indentation normalized ({changed} line(s))")
PY
fi

# Validate that the two mandatory DroidSpaces GKI KABI relocations exist and
# that the original ABI-sensitive storage locations are not active anymore.
grep -q 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)' "$SCHED" || {
    echo '[!] SYSVIPC reserve 6 relocation missing'
    exit 1
}
grep -q '_ANDROID_KABI_REPLACE(ANDROID_KABI_RESERVE(7); ANDROID_KABI_RESERVE(8),' "$SCHED" || {
    echo '[!] SYSVIPC reserves 7+8 relocation missing'
    exit 1
}
grep -q 'ANDROID_KABI_USE(1, unsigned long mq_bytes)' "$SCHED_USER" || {
    echo '[!] POSIX_MQUEUE reserve 1 relocation missing'
    exit 1
}

# Never use a global CRC/module-version bypass. A standalone Image must pass the
# real Module.symvers KMI comparison against the known-good Equinox baseline.
if git -C "$KROOT" diff -- include/linux/sched.h include/linux/sched/user.h | \
        grep -qE 'check_version|CONFIG_MODVERSIONS|abi_gki_protected'; then
    echo "[!] unexpected ABI-bypass change detected"
    exit 1
fi

echo "[+] DroidSpaces GKI KMI relocations prepared: SYSVIPC + POSIX_MQUEUE"
