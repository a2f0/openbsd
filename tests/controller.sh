#!/bin/sh
# Exercise fail-closed deployment using real SSH option parsing and fake remote replies.
set -eu
umask 077
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -r "$work"' 0
trap 'exit 1' HUP INT TERM
REAL_SSH=$(command -v ssh)
TEST_WORK=$work
export REAL_SSH TEST_WORK
mkdir "$work/bin"
cat > "$work/config" <<'CONFIG'
Host *
    ForkAfterAuthentication yes
    StdinNull yes
    RequestTTY force
    ControlMaster auto
    ControlPersist yes
    ControlPath /tmp/existing-password-master
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
    StrictHostKeyChecking no
CONFIG
cat > "$work/bin/ssh" <<'SSH'
#!/bin/sh
set -eu
# Verify the actual client precedence against unsafe inherited options.
effective=$("$REAL_SSH" -G -F "$TEST_WORK/config" "$@" 2>/dev/null)
for required in 'forkafterauthentication no' 'stdinnull no' \
    'passwordauthentication no' 'kbdinteractiveauthentication no' \
    'stricthostkeychecking true' 'batchmode yes'; do
    printf '%s\n' "$effective" | grep -qx "$required" || exit 90
done
if printf '%s\n' "$effective" | grep '^controlpath ' | grep -qvx 'controlpath none'; then exit 90; fi
log=
previous=
for argument do
    if [ "$previous" = -E ]; then log=$argument; fi
    previous=$argument
done
command=$previous
printf '%s\n' "$command" >> "$TEST_WORK/commands"
case "$command" in
    -s)
        printf 'Authenticated to fixture using "%s".\n' "$TEST_METHOD" >> "$log"
        echo OpenBSD ;;
    -u) echo 1000 ;;
    *SSH_CONNECTION*) echo 'user=admin,host=192.0.2.1,addr=192.0.2.1,laddr=192.0.2.2,lport=22' ;;
    *mktemp*) echo /tmp/openbsd-deploy.fixture ;;
    'tar -xpf -'*)
        printf '%s\n' "$effective" | grep -qx 'requesttty false' || exit 91
        cat > /dev/null
        exit 42 ;;
    'rm -r '*) exit 0 ;;
    *) echo "Unexpected remote command: $command" >&2; exit 92 ;;
esac
SSH
chmod +x "$work/bin/ssh"
PATH=$work/bin:$PATH
export PATH

# A successful none-authenticated command must never reach file transfer or doas.
TEST_METHOD=none
export TEST_METHOD
if sh "$repo/deploy.sh" admin@fixture > "$work/result" 2>&1; then
    echo "Accepted SSH none authentication" >&2; exit 1
fi
grep -qx 'SSH did not authenticate with a public key' "$work/result" || { cat "$work/result"; exit 1; }
[ "$(wc -l < "$work/commands" | tr -d ' ')" -eq 1 ]

# A failed transfer must stop deployment and preserve the remote failure status,
# despite config that would normally background SSH and discard its stdin.
TEST_METHOD=publickey
export TEST_METHOD
: > "$work/commands"
status=0
sh "$repo/deploy.sh" admin@fixture > "$work/result" 2>&1 || status=$?
[ "$status" -eq 42 ] || { cat "$work/result"; echo "Expected transfer failure, got $status" >&2; exit 1; }
if grep -q 'doas' "$work/commands"; then echo "Escalated after failed transfer" >&2; exit 1; fi
grep -q '^rm -r ' "$work/commands"
printf '%s\n' 'Controller deployment regressions passed'
