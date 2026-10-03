#!/bin/sh
# Controller helper; the remote host needs only OpenBSD's base system.
set -eu
umask 077
mode=apply
port=22
identity=
known_hosts=
usage() { echo "Usage: $0 [--check|--verify] [-p port] [-i identity] [--known-hosts file] user@host" >&2; exit 1; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --check) mode=check; shift ;;
        --verify) mode=verify; shift ;;
        -p|-i|--known-hosts)
            [ "$#" -ge 2 ] || usage
            case "$1" in -p) port=$2 ;; -i) identity=$2 ;; --known-hosts) known_hosts=$2 ;; esac
            shift 2 ;;
        -*) usage ;;
        *) break ;;
    esac
done
[ "$#" -eq 1 ] || usage
target=$1
case "$target" in root@*|*[!a-zA-Z0-9_.@:-]*|'') usage ;; *@*) ;; *) usage ;; esac
case "${target#*@}" in ''|*@*) usage ;; esac
case "$port" in ''|*[!0-9]*) usage ;; esac
source_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# Options precede ssh_config values. Never satisfy a probe through an old master,
# and use only public key authentication, even before hardening the server.
set -- -o BatchMode=yes -o PreferredAuthentications=publickey \
    -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no \
    -o StrictHostKeyChecking=yes -o ControlMaster=no -o ControlPersist=no \
    -o ControlPath=none -o ConnectTimeout=10 -o ForkAfterAuthentication=no \
    -o StdinNull=no -o RequestTTY=no -S none -p "$port"
if [ -n "$identity" ]; then set -- "$@" -i "$identity" -o IdentitiesOnly=yes; fi
if [ -n "$known_hosts" ]; then set -- "$@" -o "UserKnownHostsFile=$known_hosts"; fi
remote=
archive=
auth_log=
cleanup() {
    result=$?
    trap - 0 HUP INT TERM
    # The directory is created remotely and checked against a strict character list.
    # shellcheck disable=SC2029
    if [ -n "$remote" ]; then ssh "$@" "$target" "rm -r '$remote'" || :; fi
    if [ -n "$archive" ]; then rm "$archive"; fi
    if [ -n "$auth_log" ]; then rm "$auth_log"; fi
    exit "$result"
}
# Save the SSH arguments in the trap call without evaluating shell text.
trap 'cleanup "$@"' 0
trap 'exit 1' HUP INT TERM
prove_key() {
    : > "$auth_log"
    system=$(ssh "$@" -v -E "$auth_log" "$target" uname -s)
    [ "$system" = OpenBSD ] || { echo "Target must be OpenBSD" >&2; exit 1; }
    # OpenSSH probes authentication method "none" even with publickey preferred.
    # A successful command on a passwordless account is not proof of a key login.
    # OpenSSH logs may use CRLF even when -E writes to a regular file.
    tr -d '\r' < "$auth_log" | grep -Eq '^Authenticated to .* using "publickey"\.$' || {
        echo "SSH did not authenticate with a public key" >&2
        exit 1
    }
}
auth_log=$(mktemp)
prove_key "$@"
remote_uid=$(ssh "$@" "$target" id -u)
case "$remote_uid" in ''|0|*[!0-9]*) echo "Use a non-root SSH account" >&2; exit 1 ;; esac
context=$(ssh "$@" "$target" 'set -- $SSH_CONNECTION; printf "user=%s,host=%s,addr=%s,laddr=%s,lport=%s" "$(id -un)" "$1" "$1" "$3" "$4"')
case "$context" in ''|*[!a-zA-Z0-9_=.,:%-]*) echo "Invalid SSH connection context" >&2; exit 1 ;; esac
remote=$(ssh "$@" "$target" 'umask 077; mktemp -d /tmp/openbsd-deploy.XXXXXXXXXX')
case "$remote" in /tmp/openbsd-deploy.*) ;; *) echo "Invalid staging directory" >&2; remote=; exit 1 ;; esac
case "$remote" in *[!a-zA-Z0-9_./-]*) echo "Invalid staging directory" >&2; remote=; exit 1 ;; esac
archive=$(mktemp)
tar -C "$source_dir" -cf "$archive" baseline
# Interpolate only the validated staging directory.
# shellcheck disable=SC2029
ssh "$@" "$target" "tar -xpf - -C '$remote'" < "$archive"
# A TTY lets doas prompt for the user's password. SSH itself remains key-only.
ssh "$@" -tt "$target" "doas /bin/sh '$remote/baseline/baseline.sh' $mode --ssh-context '$context'"
prove_key "$@"
printf '%s\n' 'Fresh SSH key login passed'
