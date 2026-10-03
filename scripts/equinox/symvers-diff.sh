#!/usr/bin/env bash
set -euo pipefail

BASELINE="${1:?baseline Module.symvers required}"
CANDIDATE="${2:?candidate Module.symvers required}"
REPORT="${3:?report path required}"

[ -s "$BASELINE" ] || { echo "[!] missing baseline Module.symvers: $BASELINE"; exit 1; }
[ -s "$CANDIDATE" ] || { echo "[!] missing candidate Module.symvers: $CANDIDATE"; exit 1; }

python3 - "$BASELINE" "$CANDIDATE" "$REPORT" <<'PY'
import sys
baseline_path, candidate_path, report_path = sys.argv[1:]

def load(path):
    out = {}
    with open(path, encoding='utf-8', errors='replace') as f:
        for line in f:
            cols = line.split()
            if len(cols) >= 2:
                out[cols[1]] = cols[0]
    return out

baseline = load(baseline_path)
candidate = load(candidate_path)

changed = sorted(
    (name, baseline[name], candidate[name])
    for name in baseline.keys() & candidate.keys()
    if baseline[name] != candidate[name]
)
removed = sorted(baseline.keys() - candidate.keys())
added = sorted(candidate.keys() - baseline.keys())

with open(report_path, 'w', encoding='utf-8') as out:
    out.write(f'changed_crc={len(changed)}\n')
    out.write(f'removed={len(removed)}\n')
    out.write(f'added={len(added)}\n\n')
    for name, old, new in changed:
        out.write(f'CHANGED {name} {old} -> {new}\n')
    for name in removed:
        out.write(f'REMOVED {name}\n')
    for name in added:
        out.write(f'ADDED {name}\n')

print(f'[KMI] changed CRC: {len(changed)}')
print(f'[KMI] removed:     {len(removed)}')
print(f'[KMI] added:       {len(added)}')

if changed or removed:
    print('[!] KMI gate FAILED: existing exported symbols changed or disappeared')
    raise SystemExit(1)

print('[+] KMI gate PASSED: no existing exported symbol CRC changed or disappeared')
PY
