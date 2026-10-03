#!/bin/sh
# Integration regressions: run as root only in the disposable smoke-test VM.
set -eu
PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH
umask 077
[ "$(uname -s)" = OpenBSD ] || exit 1
[ "$(id -u)" -eq 0 ] || exit 1
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
baseline=$repo/baseline/baseline.sh
context=user=a2f0,host=10.0.2.2,addr=10.0.2.2,laddr=10.0.2.15,lport=22
# No package installation is needed, including a Python interpreter.
set -- /usr/local/bin/python*
[ ! -e "$1" ] || { echo "Unexpected target Python" >&2; exit 1; }
work=$(mktemp -d /tmp/native-smoke.XXXXXXXXXX)
trap 'rm -r "$work"' 0
trap 'exit 1' HUP INT TERM
pkg_info -q > "$work/packages.before"
snapshot() {
    for config in /etc/ssh/sshd_config /etc/sysctl.conf; do
        if [ -f "$config" ]; then
            stat -f '%N:%u:%g:%Lp' "$config"
            sha256 "$config"
        else
            printf 'absent: %s\n' "$config"
        fi
    done
    while IFS='=' read -r key _value; do
        case "$key" in '#'*|'') continue ;; esac
        sysctl "$key"
    done < "$repo/baseline/sysctl.conf"
}
snapshot > "$work/before"
sh "$baseline" check --ssh-context "$context"
snapshot > "$work/after"
cmp "$work/before" "$work/after"

# A syntax error and an unknown sysctl must fail before changing the host.
mkdir "$work/bad"
cp "$repo"/baseline/* "$work/bad/"
printf '%s\n' 'InvalidSSHDirective yes' >> "$work/bad/sshd.conf"
if sh "$work/bad/baseline.sh" apply; then echo "Invalid SSH policy accepted" >&2; exit 1; fi
snapshot > "$work/after"
cmp "$work/before" "$work/after"
cp "$repo/baseline/sshd.conf" "$work/bad/sshd.conf"
printf '%s\n' 'net.inet.ip.nonexistent_baseline_key=0' >> "$work/bad/sysctl.conf"
if sh "$work/bad/baseline.sh" apply; then echo "Unknown sysctl accepted" >&2; exit 1; fi
snapshot > "$work/after"
cmp "$work/before" "$work/after"

# A rejected write must restore any settings already applied in this transaction.
awk '
    /^net.inet.ip.forwarding=/ { print "net.inet.ip.forwarding=1"; next }
    /^net.inet6.ip6.maxdynroutes=/ { print "net.inet6.ip6.maxdynroutes=999999999999999999999999"; next }
    { print }
' "$repo/baseline/sysctl.conf" > "$work/bad/sysctl.conf"
if sh "$work/bad/baseline.sh" apply; then echo "Invalid sysctl value accepted" >&2; exit 1; fi
snapshot > "$work/after"
cmp "$work/before" "$work/after"

sh "$baseline" apply --ssh-context "$context"
sh "$baseline" verify --ssh-context "$context"
sh "$baseline" apply --ssh-context "$context" > "$work/repeat"
cat "$work/repeat"
grep -qx 'apply: changed=0' "$work/repeat"
pkg_info -q > "$work/packages.after"
cmp "$work/packages.before" "$work/packages.after"
printf '%s\n' 'Native baseline regressions passed; no packages installed'
