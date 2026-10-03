#!/bin/sh
# Runs on OpenBSD using only the base system. Invoke through doas or a root console.
set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
umask 077

die() { printf '%s\n' "$*" >&2; exit 1; }
mode=${1:-}
case "$mode" in check|apply|verify) shift ;; *) die "Usage: $0 check|apply|verify [--ssh-context connection_spec]" ;; esac
context=
if [ "$#" -eq 2 ] && [ "$1" = --ssh-context ]; then
    context=$2
    shift 2
fi
[ "$#" -eq 0 ] || die "Unexpected arguments"
[ "$(uname -s)" = OpenBSD ] || die "This baseline requires OpenBSD"
[ "$(id -u)" -eq 0 ] || die "Run through doas or a root console"
source_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
[ ! -L /etc/ssh/sshd_config ] && [ -f /etc/ssh/sshd_config ] || die "sshd_config must be a regular file"
[ ! -L /etc/sysctl.conf ] || die "sysctl.conf must not be a symlink"
if [ -e /etc/sysctl.conf ]; then
    [ -f /etc/sysctl.conf ] || die "sysctl.conf must be a regular file"
fi

work=
locked=0
applying=0
committed=0
cleanup() {
    result=$?
    trap - 0 HUP INT TERM
    set +e
    if [ "$applying" -eq 1 ] && [ "$committed" -eq 0 ]; then
        printf '%s\n' "Application failed; restoring previous files and kernel settings" >&2
        # Preserve original ownership and permissions with atomic replacement.
        restore_file "$work/ssh.original" /etc/ssh/sshd_config
        if [ -f "$work/sysctl.original" ]; then
            restore_file "$work/sysctl.original" /etc/sysctl.conf
        elif [ -f /etc/sysctl.conf ]; then
            rm /etc/sysctl.conf
        fi
        while IFS='=' read -r key value; do
            current=$(read_sysctl "$key") || { printf 'Could not read %s during rollback\n' "$key" >&2; continue; }
            if [ "$current" != "$value" ]; then
                sysctl "$key=$value" >/dev/null
                [ "$(read_sysctl "$key")" = "$value" ] || printf 'Could not restore %s\n' "$key" >&2
            fi
        done < "$work/kernel.original"
        rcctl reload sshd || printf '%s\n' "Could not reload restored SSH configuration; use the console" >&2
    fi
    if [ -n "$work" ]; then rm -r "$work"; fi
    if [ "$locked" -eq 1 ]; then rmdir /var/run/openbsd-baseline.lock; fi
    exit "$result"
}
restore_file() {
    original=$1 target=$2
    install -o "$(stat -f '%u' "$original")" -g "$(stat -f '%g' "$original")" \
        -m "$(stat -f '%Lp' "$original")" "$original" "$target" ||
        printf 'Could not restore %s; use the console\n' "$target" >&2
}
read_sysctl() {
    result=$(sysctl -n "$1") || die "Unknown sysctl: $1"
    # OpenBSD's sysctl can warn and still exit zero for an unknown name.
    [ -n "$result" ] || die "Unknown sysctl: $1"
    printf '%s\n' "$result"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
mkdir /var/run/openbsd-baseline.lock || die "Another baseline run holds /var/run/openbsd-baseline.lock"
locked=1
work=$(mktemp -d /tmp/openbsd-baseline.XXXXXXXXXX)
cp "$source_dir/sshd.conf" "$work/ssh.policy"
cp "$source_dir/sysctl.conf" "$work/kernel.policy"
cp -p /etc/ssh/sshd_config "$work/ssh.original"
if [ -f /etc/sysctl.conf ]; then
    cp -p /etc/sysctl.conf "$work/sysctl.original"
fi

# Remove only complete managed blocks, including the previous Ansible baseline.
# A broken marker pair is an error, rather than a reason to discard other config.
strip_blocks() {
    awk '
        /^# BEGIN (NATIVE|ANSIBLE) OPENBSD BASELINE$/ {
            if (inside) exit 1
            inside = $3; next
        }
        /^# END (NATIVE|ANSIBLE) OPENBSD BASELINE$/ {
            if (!inside || inside != $3) exit 1
            inside = 0; next
        }
        !inside { print }
        END { if (inside) exit 1 }
    ' "$1"
}
{
    printf '%s\n' '# BEGIN NATIVE OPENBSD BASELINE'
    cat "$work/ssh.policy"
    printf '%s\n' '# END NATIVE OPENBSD BASELINE'
    strip_blocks "$work/ssh.original"
} > "$work/ssh.candidate"
{
    if [ -f "$work/sysctl.original" ]; then strip_blocks "$work/sysctl.original"; fi
    printf '%s\n' '# BEGIN NATIVE OPENBSD BASELINE'
    cat "$work/kernel.policy"
    printf '%s\n' '# END NATIVE OPENBSD BASELINE'
} > "$work/sysctl.candidate"

# Restrict the editable inputs to unambiguous key/value settings and reject duplicates.
awk '
    /^[[:space:]]*(#|$)/ { next }
    NF != 2 || seen[tolower($1)]++ { exit 1 }
    { print tolower($1), tolower($2) }
' "$work/ssh.policy" > "$work/ssh.expected" || die "Invalid SSH policy"
[ -s "$work/ssh.expected" ] || die "SSH policy is empty"
awk '
    /^[[:space:]]*(#|$)/ { next }
    !/^[a-zA-Z0-9_.]+=[0-9]+$/ { exit 1 }
    { split($0, setting, "="); if (seen[setting[1]]++) exit 1; print }
' "$work/kernel.policy" > "$work/kernel.expected" || die "Invalid sysctl policy"
[ -s "$work/kernel.expected" ] || die "Sysctl policy is empty"
: > "$work/kernel.original"
kernel_changes=0
while IFS='=' read -r key value; do
    actual=$(read_sysctl "$key")
    printf '%s=%s\n' "$key" "$actual" >> "$work/kernel.original"
    if [ "$actual" != "$value" ]; then
        printf 'sysctl: %s: %s -> %s\n' "$key" "$actual" "$value"
        kernel_changes=$((kernel_changes + 1))
    fi
done < "$work/kernel.expected"

check_ssh_policy() {
    config=$1
    sshd -t -f "$config"
    sshd -T -f "$config" > "$work/ssh.effective"
    while IFS= read -r setting; do
        grep -Fqix "$setting" "$work/ssh.effective" || die "SSH policy differs: $setting"
    done < "$work/ssh.expected"
    if [ -n "$context" ]; then
        sshd -T -f "$config" -C "$context" > "$work/ssh.effective"
        while IFS= read -r setting; do
            grep -Fqix "$setting" "$work/ssh.effective" || die "SSH Match policy differs: $setting"
        done < "$work/ssh.expected"
    fi
}
check_ssh_policy "$work/ssh.candidate"

needs_file() {
    candidate=$1 target=$2 permissions=$3
    [ -f "$target" ] && cmp -s "$candidate" "$target" &&
        [ "$(stat -f '%u:%g:%Lp' "$target")" = "0:0:$permissions" ] && return 1
    printf 'file: %s\n' "$target"
    return 0
}
ssh_changed=0 sysctl_changed=0
if needs_file "$work/ssh.candidate" /etc/ssh/sshd_config 600; then ssh_changed=1; fi
if needs_file "$work/sysctl.candidate" /etc/sysctl.conf 644; then sysctl_changed=1; fi
changes=$((ssh_changed + sysctl_changed + kernel_changes))
case "$mode" in
    check) printf 'check: changed=%s\n' "$changes"; exit 0 ;;
    verify)
        [ "$changes" -eq 0 ] || die "Baseline drift detected"
        check_ssh_policy /etc/ssh/sshd_config
        printf '%s\n' 'verify: changed=0'; exit 0 ;;
esac

applying=1
while IFS='=' read -r key value; do
    actual=$(read_sysctl "$key")
    if [ "$actual" != "$value" ]; then sysctl "$key=$value"; fi
    actual=$(read_sysctl "$key")
    [ "$actual" = "$value" ] || die "Sysctl did not take effect: $key"
done < "$work/kernel.expected"
suffix=.baseline.$(date -u +%Y%m%dT%H%M%SZ).$$
if [ "$sysctl_changed" -eq 1 ]; then
    install -b -B "$suffix" -o root -g wheel -m 644 "$work/sysctl.candidate" /etc/sysctl.conf
fi
if [ "$ssh_changed" -eq 1 ]; then
    install -b -B "$suffix" -o root -g wheel -m 600 "$work/ssh.candidate" /etc/ssh/sshd_config
    rcctl reload sshd
fi
check_ssh_policy /etc/ssh/sshd_config
committed=1
printf 'apply: changed=%s\n' "$changes"
