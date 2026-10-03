#!/usr/bin/env bash
set -euo pipefail

KSUN_DIR="${1:?KernelSU-Next checkout required}"
SUSFS_DIR="${2:?susfs4ksu checkout required}"
KROOT="${3:-$PWD}"

P10="$SUSFS_DIR/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
P50="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android13-5.10.patch"

for f in "$P10" "$P50" "$KSUN_DIR/kernel/Kconfig" "$KROOT/drivers/Kconfig" "$KROOT/drivers/Makefile"; do
    [ -f "$f" ] || { echo "[!] missing $f"; exit 1; }
done

echo "[*] KernelSU-Next + SUSFS: wiring driver"

# Wire the pinned KernelSU-Next driver into this build worktree.
ln -sfn "$(realpath --relative-to="$KROOT/drivers" "$KSUN_DIR/kernel")" "$KROOT/drivers/kernelsu"
grep -q 'source "drivers/kernelsu/Kconfig"' "$KROOT/drivers/Kconfig" || \
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$KROOT/drivers/Kconfig"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$KROOT/drivers/Makefile" || \
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$KROOT/drivers/Makefile"

# Import only the SUSFS Kconfig menu. The complete generic KernelSU patch is not
# applied because it contains hook code for a different KernelSU integration.
python3 - "$P10" "$KSUN_DIR/kernel/Kconfig" <<'PY'
import re
import sys

patch, dst = sys.argv[1:]
src = open(patch, encoding='utf-8', errors='replace').read()
code = open(dst, encoding='utf-8').read()

if 'config KSU_SUSFS' in code:
    print('[=] KernelSU SUSFS Kconfig already present')
    raise SystemExit(0)

m = re.search(r'diff --git a/kernel/Kconfig.*?(?=\ndiff --git |\Z)', src, re.S)
if not m:
    raise SystemExit('[!] cannot find KernelSU Kconfig hunk in SUSFS patch')

added = [
    line[1:]
    for line in m.group(0).splitlines()
    if line.startswith('+') and not line.startswith('+++')
]
menu = '\n'.join(added).strip()
if 'config KSU_SUSFS' not in menu or 'config KSU_SUSFS_SUS_MAP' not in menu:
    raise SystemExit('[!] extracted SUSFS Kconfig menu is incomplete')

# SUSFS 2.3.0's patch contains help-text bullet lines in a few stanzas without
# an explicit `help` token. Kconfig treats the first '-' as syntax. Repair this
# deterministically while keeping the actual menu text unchanged.
fixed = []
in_config = False
seen_help = False
for line in menu.splitlines():
    stripped = line.strip()
    if stripped.startswith('config '):
        in_config = True
        seen_help = False
    elif stripped.startswith('menu') or stripped == 'endmenu':
        in_config = False
        seen_help = False
    elif stripped == 'help':
        seen_help = True
    elif in_config and stripped.startswith('- ') and not seen_help:
        fixed.append('\thelp')
        seen_help = True
    fixed.append(line)
menu = '\n'.join(fixed)

open(dst, 'a', encoding='utf-8').write('\n\n' + menu + '\n')
print('[+] appended validated SUSFS Kconfig menu')
PY

# Add the SID helper surface expected by SUSFS while preserving KernelSU-Next's
# own SELinux implementation.
python3 - "$KSUN_DIR/kernel/selinux/selinux.c" "$KSUN_DIR/kernel/selinux/selinux.h" "$KSUN_DIR/kernel/selinux/rules.c" <<'PY'
import sys
cfile, hfile, rfile = sys.argv[1:]
c = open(cfile, encoding='utf-8').read()
h = open(hfile, encoding='utf-8').read()
r = open(rfile, encoding='utf-8').read()

if 'susfs_set_batch_sid(void)' not in c:
    glue = r'''
#ifdef CONFIG_KSU_SUSFS
#define SUSFS_INIT_DOMAIN "u:r:init:s0"
#define SUSFS_ZYGOTE_DOMAIN "u:r:zygote:s0"
#define SUSFS_ZYGOTE_NEXT_DOMAIN "u:r:zygote_next:s0"
#define SUSFS_PRIV_APP_DOMAIN "u:r:priv_app:s0:c512,c768"

u32 susfs_ksu_sid __read_mostly;
u32 susfs_init_sid __read_mostly;
u32 susfs_zygote_sid __read_mostly;
u32 susfs_zygote_next_sid __read_mostly;
u32 susfs_priv_app_sid __read_mostly;

static void susfs_set_sid(const char *ctx, u32 *sid)
{
    u32 resolved = 0;

    if (!security_secctx_to_secid(ctx, strlen(ctx), &resolved) && resolved > 1)
        *sid = resolved;
}

bool susfs_is_sid_equal(const struct cred *cred, u32 sid2)
{
    u32 sid = 0;
    security_cred_getsecid(cred, &sid);
    return sid == sid2;
}

u32 susfs_get_sid_from_name(const char *ctx)
{
    u32 sid = 0;
    security_secctx_to_secid(ctx, strlen(ctx), &sid);
    return sid;
}

u32 susfs_get_current_sid(void)
{
    return current_sid();
}

bool susfs_is_current_zygote_domain(void)
{
    return unlikely(current_sid() == susfs_zygote_sid);
}

bool susfs_is_current_zygote_next_domain(void)
{
    return unlikely(current_sid() == susfs_zygote_next_sid);
}

bool susfs_is_current_ksu_domain(void)
{
    return is_ksu_domain();
}

bool susfs_is_current_init_domain(void)
{
    return unlikely(current_sid() == susfs_init_sid);
}

void susfs_set_batch_sid(void)
{
    susfs_set_sid(SUSFS_ZYGOTE_DOMAIN, &susfs_zygote_sid);
    susfs_set_sid(SUSFS_ZYGOTE_NEXT_DOMAIN, &susfs_zygote_next_sid);
    susfs_set_sid(KERNEL_SU_CONTEXT, &susfs_ksu_sid);
    susfs_set_sid(SUSFS_INIT_DOMAIN, &susfs_init_sid);
    susfs_set_sid(SUSFS_PRIV_APP_DOMAIN, &susfs_priv_app_sid);
}
#endif
'''
    c = c.rstrip() + '\n' + glue

if 'void susfs_set_batch_sid(void);' not in h:
    pos = h.rfind('#endif')
    if pos < 0:
        raise SystemExit('[!] selinux.h end guard not found')
    proto = r'''
#ifdef CONFIG_KSU_SUSFS
extern u32 susfs_ksu_sid;
extern u32 susfs_init_sid;
extern u32 susfs_zygote_sid;
extern u32 susfs_zygote_next_sid;
extern u32 susfs_priv_app_sid;
bool susfs_is_sid_equal(const struct cred *cred, u32 sid2);
u32 susfs_get_sid_from_name(const char *secctx_name);
u32 susfs_get_current_sid(void);
void susfs_set_batch_sid(void);
bool susfs_is_current_zygote_domain(void);
bool susfs_is_current_zygote_next_domain(void);
bool susfs_is_current_ksu_domain(void);
bool susfs_is_current_init_domain(void);
#endif

'''
    h = h[:pos] + proto + h[pos:]

if 'susfs_set_batch_sid();' not in r:
    anchor = '    reset_avc_cache();'
    if anchor not in r:
        raise SystemExit('[!] KernelSU rules.c reset_avc_cache anchor changed')
    r = r.replace(anchor, anchor + '\n#ifdef CONFIG_KSU_SUSFS\n    susfs_set_batch_sid();\n#endif', 1)

open(cfile, 'w', encoding='utf-8').write(c)
open(hfile, 'w', encoding='utf-8').write(h)
open(rfile, 'w', encoding='utf-8').write(r)
print('[+] SUSFS SELinux SID helpers integrated')
PY

# Graft SUSFS command dispatch into the reboot supercall path already owned by
# KernelSU-Next. Do not add a second reboot hook.
python3 - "$P10" "$KSUN_DIR/kernel/supercall/supercall.c" <<'PY'
import re
import sys
patch, path = sys.argv[1:]
p = open(patch, encoding='utf-8', errors='replace').read()
s = open(path, encoding='utf-8').read()
if 'CMD_SUSFS_ADD_SUS_PATH' in s:
    print('[=] SUSFS supercall dispatch already present')
    raise SystemExit(0)

m = re.search(r'diff --git a/kernel/supercall/dispatch\.c.*?(?=\ndiff --git |\Z)', p, re.S)
if not m:
    raise SystemExit('[!] SUSFS dispatch hunk not found')
added = '\n'.join(
    line[1:] for line in m.group(0).splitlines()
    if line.startswith('+') and not line.startswith('+++')
)
sm = re.search(r'switch\(cmd\)\s*\{\s*(.*?)\n\s*\}\s*\n\s*\}', added, re.S)
if not sm:
    raise SystemExit('[!] cannot extract SUSFS command switch')
switch_body = sm.group(1)
if 'CMD_SUSFS_ADD_SUS_PATH' not in switch_body or 'CMD_SUSFS_SHOW_VERSION' not in switch_body:
    raise SystemExit('[!] SUSFS command switch failed validation')
switch_body = re.sub(
    r'default:\s*\n\s*return -EINVAL;',
    'default:\n                return 0;',
    switch_body,
)

include_anchor = '#include <linux/utsname.h> // utsname() and uts_sem\n'
if include_anchor not in s:
    raise SystemExit('[!] KernelSU supercall include anchor changed')
s = s.replace(
    include_anchor,
    include_anchor +
    '#ifdef CONFIG_KSU_SUSFS\n'
    '#include <linux/cred.h>\n'
    '#include <linux/sched.h>\n'
    '#include <linux/susfs.h>\n'
    '#endif\n',
    1,
)

arg_anchor = '    unsigned long reply = (unsigned long)arg4;\n'
if arg_anchor not in s:
    raise SystemExit('[!] KernelSU reboot handler anchor changed')
dispatch = '''
#ifdef CONFIG_KSU_SUSFS
    if (magic2 == SUSFS_MAGIC && current_uid().val == 0) {
        void __user *susfs_uptr = (void __user *)arg4;
        void __user **arg = &susfs_uptr;
        switch(cmd) {
%s
        }
    }
#endif
''' % switch_body
s = s.replace(arg_anchor, arg_anchor + dispatch, 1)
open(path, 'w', encoding='utf-8').write(s)
print('[+] SUSFS command dispatch integrated into KSUN reboot supercall')
PY

# Initialize SUSFS before KernelSU begins accepting supercalls.
python3 - "$KSUN_DIR/kernel/core/init.c" <<'PY'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()
if 'susfs_init();' in s:
    print('[=] SUSFS init already present')
    raise SystemExit(0)
anchor = '\tksu_supercalls_init();'
if anchor not in s:
    raise SystemExit('[!] KernelSU init anchor changed')
s = s.replace(
    anchor,
    '#ifdef CONFIG_KSU_SUSFS\n\t{ extern void susfs_init(void); susfs_init(); }\n#endif\n' + anchor,
    1,
)
open(path, 'w', encoding='utf-8').write(s)
print('[+] SUSFS init wired into kernelsu_init')
PY

# Keep KernelSU-Next v3.3.0's manager/setuid logic and only add the SUSFS
# process state around the existing kernel-umount transition.
python3 - "$KSUN_DIR/kernel/hook/setuid_hook.c" <<'PY'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()
if 'Equinox SUSFS process state' in s:
    print('[=] SUSFS setuid integration already present')
    raise SystemExit(0)

inc = '#include "feature/kernel_umount.h"\n'
if inc not in s:
    raise SystemExit('[!] KernelSU setuid include anchor changed')
s = s.replace(
    inc,
    inc +
    '#ifdef CONFIG_KSU_SUSFS\n'
    '#include <linux/susfs_def.h>\n'
    '#include "selinux/selinux.h"\n'
    'extern struct work_struct susfs_extra_works;\n'
    '#endif\n',
    1,
)

old = '    // Handle kernel umount\n    ksu_handle_umount(old_uid, new_uid);\n\n    return 0;\n'
if old not in s:
    raise SystemExit('[!] KernelSU kernel-umount anchor changed')
new = r'''#ifdef CONFIG_KSU_SUSFS
    /* Equinox SUSFS process state. Keep KernelSU-Next v3.3.0's manager and
     * allowlist logic above intact; only specialize the zygote transition. */
    if (susfs_is_current_zygote_domain()) {
        if (is_isolated_process(new_uid) ||
            (is_appuid(new_uid) && ksu_uid_should_umount(new_uid))) {
            susfs_set_current_proc_no_su();
            susfs_set_current_proc_umounted();
            ksu_handle_umount(old_uid, new_uid);
            if (!work_pending(&susfs_extra_works))
                schedule_work(&susfs_extra_works);
            return 0;
        }
    } else if (susfs_is_current_zygote_next_domain()) {
        if (is_isolated_process(new_uid) ||
            (is_appuid(new_uid) && ksu_uid_should_umount(new_uid))) {
            susfs_set_current_proc_no_su();
            susfs_set_current_proc_umounted();
            susfs_set_current_proc_umounted_for_zygote_next();
            if (!work_pending(&susfs_extra_works))
                schedule_work(&susfs_extra_works);
            return 0;
        }
    }
#endif

    // Handle kernel umount
    ksu_handle_umount(old_uid, new_uid);

    return 0;
'''
s = s.replace(old, new, 1)
open(path, 'w', encoding='utf-8').write(s)
print('[+] SUSFS zygote process state integrated without replacing KSUN setuid hook')
PY

echo "[*] KernelSU-Next + SUSFS: applying Linux 5.10 VFS side"

cp "$SUSFS_DIR"/kernel_patches/fs/*.c "$KROOT/fs/"
cp "$SUSFS_DIR"/kernel_patches/include/linux/*.h "$KROOT/include/linux/"

# The generic Linux 5.10 SUSFS patch contains old manual KernelSU hook code.
# Drop those pieces while keeping the real SUSFS VFS hooks. Some upstream hunks
# mix legacy declarations with SUSFS declarations, so required SUSFS declarations
# are restored explicitly after patching below.
python3 - "$P50" "$KROOT/.equinox-susfs50.patch" <<'PY'
import re
import sys
src = open(sys.argv[1], encoding='utf-8', errors='replace').read()

DROP_FILES = {
    'drivers/input/input.c',
    'fs/exec.c',
    'fs/read_write.c',
    'kernel/reboot.c',
    'security/selinux/hooks.c',
    'security/selinux/selinuxfs.c',
}
DROP_HUNK_MARKERS = {
    'fs/open.c': (
        'ksu_handle_faccessat',
        'ksu_su_compat_enabled',
        'struct filename *fname = NULL',
    ),
    'fs/stat.c': (
        'ksu_handle_stat',
        'ksu_handle_vfs_fstat',
        'ksu_is_init_rc_hook_enabled',
        'ksu_su_compat_enabled',
        'struct filename *fname = NULL',
    ),
    'kernel/sys.c': ('ksu_handle_setresuid',),
}

out = []
for chunk in re.split(r'(?=^diff --git )', src, flags=re.M):
    if not chunk.startswith('diff --git '):
        out.append(chunk)
        continue
    m = re.match(r'diff --git a/(\S+) b/(\S+)', chunk)
    if not m:
        raise SystemExit('[!] malformed SUSFS patch chunk')
    path = m.group(1)
    if path in DROP_FILES:
        print('[i] drop legacy KSU-only file patch:', path)
        continue
    markers = DROP_HUNK_MARKERS.get(path)
    if markers:
        parts = re.split(r'(?=^@@ )', chunk, flags=re.M)
        head, hunks = parts[0], parts[1:]
        kept = []
        for hunk in hunks:
            if any(marker in hunk for marker in markers):
                print('[i] drop legacy/mixed KSU hunk:', path)
                continue
            kept.append(hunk)
        if not kept:
            continue
        chunk = head + ''.join(kept)
    out.append(chunk)

final = ''.join(out)
for forbidden in (
    'ksu_handle_setresuid',
    'ksu_handle_faccessat',
    'ksu_handle_execveat_sucompat',
    'ksu_selinux_hide_running',
    'ksu_is_init_rc_hook_enabled',
):
    if forbidden in final:
        raise SystemExit('[!] legacy KernelSU hook survived patch sanitizer: ' + forbidden)

for required in (
    'susfs_spoof_uname',
    'susfs_is_inode_sus_kstat',
    'susfs_is_current_proc_umounted',
    'susfs_get_non_sus_mnt_id_from_mnt',
    'susfs_show_mountinfo',
):
    if required not in final:
        raise SystemExit('[!] required SUSFS 2.3.0 VFS hook missing after sanitizer: ' + required)

open(sys.argv[2], 'w', encoding='utf-8').write(final)
PY

cd "$KROOT"
if ! patch --batch --forward --fuzz=0 -p1 < .equinox-susfs50.patch; then
    echo "[!] SUSFS 5.10 patch did not apply cleanly. No fuzzy fallback is allowed."
    git ls-files --others --exclude-standard -- '*.rej' | while read -r rej; do
        [ -n "$rej" ] || continue
        echo "== $rej =="
        cat "$rej"
    done
    exit 1
fi
rm -f .equinox-susfs50.patch

# The base tree already contains a tracked historical .rej unrelated to this
# integration. Only a reject newly created by this run is a failure.
rejects="$(git ls-files --others --exclude-standard -- '*.rej')"
[ -z "$rejects" ] || {
    echo "[!] new SUSFS patch rejects remain"
    echo "$rejects"
    exit 1
}

# Repair declarations that live in the same upstream stat.c hunks as legacy KSU
# hooks. The sanitizer intentionally drops those mixed hunks, then restores only
# the declarations required by SUSFS itself. Also remove the orphan `fname`
# declaration left by old manual-hook hunks if it is present.
python3 - "$KROOT/fs/open.c" "$KROOT/fs/stat.c" <<'PY'
import sys
open_path, stat_path = sys.argv[1:]

orphan = '#ifdef CONFIG_KSU_SUSFS\n\tstruct filename *fname = NULL;\n#endif\n'

open_code = open(open_path, encoding='utf-8').read()
open_code = open_code.replace(orphan, '', 1)
open(open_path, 'w', encoding='utf-8').write(open_code)

stat = open(stat_path, encoding='utf-8').read()
stat = stat.replace(orphan, '', 1)

if '#include <linux/susfs_def.h>' not in stat:
    anchor = '#include <linux/compat.h>\n'
    if anchor not in stat:
        raise SystemExit('[!] fs/stat.c include anchor changed')
    stat = stat.replace(
        anchor,
        anchor + '#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif\n',
        1,
    )

need_decl = (
    'susfs_is_inode_sus_kstat(' in stat or
    'susfs_sus_kstat_spoof_generic_fillattr(' in stat
)
if need_decl and 'extern bool susfs_is_inode_sus_kstat' not in stat:
    anchor = '#include "mount.h"\n'
    if anchor not in stat:
        raise SystemExit('[!] fs/stat.c declaration anchor changed')
    decl = '''
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
extern bool susfs_is_inode_sus_kstat(struct inode *inode, bool *out_is_fuse);
extern void susfs_sus_kstat_spoof_generic_fillattr(struct inode *inode,
                                                    struct kstat *stat,
                                                    u32 result_mask);
#endif
'''
    stat = stat.replace(anchor, anchor + decl, 1)

open(stat_path, 'w', encoding='utf-8').write(stat)
print('[+] validated fs/open.c and restored SUSFS-only fs/stat.c declarations')
PY

# Never bypass Android module version/KMI checks.
if git diff | grep -E 'check_version\(.*return true|abi_gki_protected_exports.*^\+?$' >/dev/null; then
    echo "[!] forbidden module ABI bypass detected"
    exit 1
fi

# Structural validation before Kconfig/build.
grep -q 'obj-$(CONFIG_KSU_SUSFS) += susfs.o' fs/Makefile || { echo '[!] fs/susfs.o build wiring missing'; exit 1; }
grep -q '#define SUSFS_VERSION "v2.3.0"' include/linux/susfs.h || { echo '[!] SUSFS is not v2.3.0'; exit 1; }
grep -q 'CMD_SUSFS_ADD_SUS_PATH' "$KSUN_DIR/kernel/supercall/supercall.c" || { echo '[!] SUSFS supercall missing'; exit 1; }
grep -q 'extern bool susfs_is_inode_sus_kstat' fs/stat.c || { echo '[!] SUSFS stat declarations missing'; exit 1; }
grep -q 'susfs_sus_kstat_spoof_generic_fillattr' fs/stat.c || { echo '[!] SUSFS stat spoof hook missing'; exit 1; }

# The exact integration that previously compiled successfully must not leave the
# two known orphan declarations behind.
if grep -q 'struct filename \*fname = NULL' fs/open.c fs/stat.c; then
    echo '[!] legacy fname declaration survived SUSFS sanitization'
    exit 1
fi

git diff --check

echo "[+] KernelSU-Next v3.3.0 + SUSFS v2.3.0 source integration prepared"
