#!/bin/sh
# Preview, ISO download, and installation failure regression coverage: no
# network, real disk, or virtual machine.
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
EXPECT=$(command -v expect)
work=$(mktemp -d)
trap 'rm -r "$work"' 0
trap 'exit 1' HUP INT TERM
mkdir "$work/bin" "$work/run"
PROVISION_TEST_WORK=$work
export PROVISION_TEST_WORK
cat > "$work/bin/wget" <<'WGET'
#!/bin/sh
set -eu
iso=https://cdn.openbsd.org/pub/OpenBSD/8.0/amd64/install80.iso
if [ "$#" -eq 6 ] && [ "$6" = "$iso" ]; then
    [ "$1 $2 $3 $4" = '--no-config --no-hsts -q -O' ] || exit 90
    printf 'downloaded iso\n' > "$5"
    if [ "${PROVISION_TEST_DOWNLOAD_RACE:-0}" -eq 1 ]; then mkdir install80.iso; fi
    if [ "${PROVISION_TEST_DOWNLOAD_BLOCK:-0}" -eq 1 ]; then
        echo "$$" > "$PROVISION_TEST_WORK/wget.pid"
        exec sleep 60
    fi
    exit "${PROVISION_TEST_DOWNLOAD_STATUS:-0}"
fi
[ "$*" = '--no-config --no-hsts -q -O - https://cdn.openbsd.org/pub/OpenBSD/8.0/amd64/SHA256' ] || exit 90
if [ "${PROVISION_TEST_FETCH_FAILURE:-0}" -eq 1 ]; then exit 98; fi
cat "$PROVISION_TEST_WORK/manifest"
WGET
cat > "$work/bin/sha256sum" <<'CHECKSUM'
#!/bin/sh
# Fail like sha256sum on a missing file, so verifying the wrong path is caught.
[ "$#" -eq 1 ] && [ -f "$1" ] || exit 1
echo '0000000000000000000000000000000000000000000000000000000000000000  install80.iso'
CHECKSUM
cat > "$work/bin/qemu-img" <<'GUARD'
#!/bin/sh
echo 'Unexpected mutation command' >&2
exit 91
GUARD
cp "$work/bin/qemu-img" "$work/bin/qemu-system-x86_64"
# Installation runs only far enough to download, verify, and reach qemu-img.
cat > "$work/bin/uv" <<'UV'
#!/bin/sh
if [ "${PROVISION_TEST_INSTALL:-0}" -eq 1 ] &&
    [ "$*" = 'run --locked python -c import sys; print(sys.executable)' ]; then
    echo "$PROVISION_TEST_WORK/server"
    exit 0
fi
echo 'Unexpected mutation command' >&2
exit 91
UV
cat > "$work/server" <<'SERVER'
#!/bin/sh
echo 'Serving HTTP on 127.0.0.1 port 8686'
exec sleep 60
SERVER
chmod +x "$work/server"
chmod +x "$work/bin/"*
PATH=$work/bin:$PATH
export PATH
USER_PASSWORD=fixture ROOT_PASSWORD=fixture
export USER_PASSWORD ROOT_PASSWORD
cd "$work/run"
checksum=0000000000000000000000000000000000000000000000000000000000000000
printf 'SHA256 (install80.iso) = %s\n' "$checksum" > "$work/manifest"
"$EXPECT" "$repo/qemu.exp" --dry-run > "$work/result"
grep -q 'Dry run passed: no files created, no VM started.' "$work/result"
[ -z "$(ls -A)" ]
reject() {
    expected=$1
    shift
    if "$EXPECT" "$repo/qemu.exp" "$@" > "$work/result" 2>&1; then
        echo 'Unsafe provisioning preview was accepted' >&2; exit 1
    fi
    grep -Fxq "$expected" "$work/result" || { cat "$work/result"; exit 1; }
}
printf 'keep\n' > openbsd-vm.qcow2
reject "Error: 'openbsd-vm.qcow2' already exists." --dry-run
reject "Error: 'openbsd-vm.qcow2' already exists."
[ "$(cat openbsd-vm.qcow2)" = keep ]
rm openbsd-vm.qcow2
ln -s absent openbsd-vm.qcow2
reject "Error: 'openbsd-vm.qcow2' already exists." --dry-run
rm openbsd-vm.qcow2
printf 'private\n' > install.conf
reject "Error: 'install.conf' already exists." --dry-run
[ "$(cat install.conf)" = private ]
rm install.conf
ln -s absent install.conf
reject "Error: 'install.conf' already exists." --dry-run
rm install.conf
PROVISION_TEST_FETCH_FAILURE=1 reject 'Error: could not read the release checksum manifest: child process exited abnormally' --dry-run
unset PROVISION_TEST_FETCH_FAILURE
mv "$work/bin/qemu-img" "$work/bin/qemu-img.saved"
if PATH=$work/bin "$EXPECT" "$repo/qemu.exp" --dry-run > "$work/result" 2>&1; then
    echo 'Missing controller tool was accepted' >&2; exit 1
fi
grep -Fxq "Error: required controller tool 'qemu-img' is missing." "$work/result"
mv "$work/bin/qemu-img.saved" "$work/bin/qemu-img"
SSH_PUBLIC_KEY='invalid
key' reject 'Error: SSH_PUBLIC_KEY must not contain newlines.' --dry-run
unset SSH_PUBLIC_KEY
printf 'SHA256 (other.iso) = %s\n' "$checksum" > "$work/manifest"
reject 'Error: selected ISO has no release checksum.' --dry-run
printf 'SHA256 (install80.iso) = %s\n' "$checksum" > "$work/manifest"
printf 'SHA256 (install80.iso) = %s\n' "$checksum" >> "$work/manifest"
reject 'Error: duplicate ISO checksums in release manifest.' --dry-run
printf 'SHA256 (install80.iso) = %064d\n' 1 > "$work/manifest"
printf 'existing iso\n' > install80.iso
reject "Error: cached ISO checksum differs from the selected release; move 'install80.iso' aside to download it again." --dry-run
[ "$(cat install80.iso)" = 'existing iso' ]
printf 'SHA256 (install80.iso) = %s\n' "$checksum" > "$work/manifest"
"$EXPECT" "$repo/qemu.exp" --dry-run > "$work/result"
grep -q 'Dry run passed: no files created, no VM started.' "$work/result"
[ "$(cat install80.iso)" = 'existing iso' ]
rm install80.iso
ln -s absent install80.iso
reject "Error: 'install80.iso' must be a regular file." --dry-run
rm install80.iso
mkdir install80.iso
reject "Error: 'install80.iso' must be a regular file." --dry-run
rmdir install80.iso
PROVISION_TEST_INSTALL=1
export PROVISION_TEST_INSTALL
# A failed or mismatched download must leave no ISO behind to fail preflight.
PROVISION_TEST_DOWNLOAD_STATUS=4 reject 'Failed to download ISO file.'
unset PROVISION_TEST_DOWNLOAD_STATUS
[ -z "$(ls -A)" ] || { ls -A; exit 1; }
printf 'SHA256 (install80.iso) = %064d\n' 1 > "$work/manifest"
reject "Error: SHA256 verification failed: $checksum  install80.iso"
[ -z "$(ls -A)" ] || { ls -A; exit 1; }
printf 'SHA256 (install80.iso) = %s\n' "$checksum" > "$work/manifest"
reject 'Unexpected mutation command'
[ "$(ls -A)" = install80.iso ] || { ls -A; exit 1; }
[ "$(cat install80.iso)" = 'downloaded iso' ]
rm install80.iso
PROVISION_TEST_DOWNLOAD_RACE=1 reject "Error: 'install80.iso' appeared during the download."
unset PROVISION_TEST_DOWNLOAD_RACE
[ "$(ls -A)" = install80.iso ] && [ -z "$(ls -A install80.iso)" ] || { ls -AR; exit 1; }
rmdir install80.iso
# A hung-up download exits through cleanup (Expect already exits cleanly on
# INT and TERM). Expect handles the signal once
# the blocking wget returns, so stop wget as a terminal interrupt would.
PROVISION_TEST_DOWNLOAD_BLOCK=1 "$EXPECT" "$repo/qemu.exp" > "$work/result" 2>&1 &
installer=$!
tries=0
until [ -s "$work/wget.pid" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 100 ] || { cat "$work/result"; exit 1; }
    sleep 0.1
done
kill -HUP "$installer"
sleep 0.2
kill "$(cat "$work/wget.pid")"
if wait "$installer"; then
    echo 'Interrupted installation exited successfully' >&2; exit 1
fi
# The signal, not wget's failure, must end the run.
if grep -q 'wget failed' "$work/result"; then cat "$work/result"; exit 1; fi
[ -z "$(ls -A)" ] || { ls -A; exit 1; }

# A failed or interrupted installation must not leave a half-installed disk at
# the path boot.exp trusts; only a clean power-down publishes it. The fake
# qemu-img creates the disk it is given, and the fake installer VM answers the
# console dialogue, marks its disk installed, and exits with the chosen status.
mkdir "$work/disk"
cat > "$work/disk/qemu-img" <<'IMG'
#!/bin/sh
set -eu
[ "$#" -eq 5 ] && [ "$1 $2 $3 $5" = 'create -f qcow2 5G' ] && [ ! -e "$4" ] || exit 90
case "$4" in /*) exit 90 ;; esac
printf 'blank\n' > "$4"
IMG
cat > "$work/disk/qemu-system-x86_64" <<'VM'
#!/bin/sh
set -eu
disk=
for argument do
    case "$argument" in file=*,format=qcow2,*) disk=${argument#file=}; disk=${disk%%,*} ;; esac
done
[ -n "$disk" ] && [ "$(cat "$disk")" = blank ] || exit 90
[ -f install.conf ] || exit 90
echo "$$" > "$PROVISION_TEST_WORK/installer.pid"
[ "${PROVISION_TEST_VM_FAIL:-0}" -eq 0 ] || exit 1
printf 'boot> '; read -r line
printf 'boot> '; read -r line
printf '(I)nstall, (U)pgrade, (A)utoinstall or (S)hell? '; read -r line
printf 'Response file location? '; read -r line
[ "$line" = http://10.0.2.2:8686/install.conf ] || exit 90
printf 'installed\n' > "$disk"
if [ "${PROVISION_TEST_VM_BLOCK:-0}" -eq 1 ]; then exec sleep 60; fi
printf 'login: '
stty -icanon -echo min 1 time 0
input=
while byte=$(dd bs=1 count=1 2> /dev/null | od -An -tx1 | tr -d ' \n') && [ -n "$byte" ]; do
    input="$input$byte"
    case "$input" in
        *0163) printf '(qemu) '; input= ;;
        *73797374656d5f706f776572646f776e0d | *73797374656d5f706f776572646f776e0a)
            if [ "${PROVISION_TEST_VM_KILLED:-0}" -eq 1 ]; then kill -TERM "$$"; fi
            exit "${PROVISION_TEST_VM_STATUS:-0}" ;;
    esac
done
exit 1
VM
chmod +x "$work/disk/"*
printf 'cached iso\n' > install80.iso
install() {
    PATH=$work/disk:$PATH "$EXPECT" "$repo/qemu.exp" > "$work/result" 2>&1
}
install_rejected() {
    if install; then cat "$work/result"; echo 'Failed installation succeeded' >&2; exit 1; fi
    grep -Fq "$1" "$work/result" || { cat "$work/result"; exit 1; }
    [ "$(ls -A)" = install80.iso ] || { cat "$work/result"; ls -A; exit 1; }
}
PROVISION_TEST_VM_FAIL=1 install_rejected 'Error: QEMU exited unexpectedly'
unset PROVISION_TEST_VM_FAIL
PROVISION_TEST_VM_STATUS=3 install_rejected 'Error: QEMU did not exit cleanly after the installation'
unset PROVISION_TEST_VM_STATUS
PROVISION_TEST_VM_KILLED=1 install_rejected 'Error: QEMU did not exit cleanly after the installation'
unset PROVISION_TEST_VM_KILLED
# Hanging up mid-installation must discard the disk as well.
rm -f "$work/installer.pid"
# Background Expect itself, not a subshell, so the signal reaches it.
PROVISION_TEST_VM_BLOCK=1 PATH=$work/disk:$PATH "$EXPECT" "$repo/qemu.exp" > "$work/result" 2>&1 &
installer=$!
tries=0
until [ -s "$work/installer.pid" ] && grep -q 'Response file location' "$work/result"; do
    tries=$((tries + 1))
    [ "$tries" -le 100 ] || { cat "$work/result"; exit 1; }
    sleep 0.1
done
sleep 0.2
kill -HUP "$installer"
if wait "$installer"; then echo 'Hung-up installation exited successfully' >&2; exit 1; fi
kill "$(cat "$work/installer.pid")" 2> /dev/null || :
[ "$(ls -A)" = install80.iso ] || { cat "$work/result"; ls -A; exit 1; }
install || { cat "$work/result"; exit 1; }
[ "$(cat openbsd-vm.qcow2)" = installed ] || { cat "$work/result"; ls -A; exit 1; }
[ "$(ls -A)" = 'install80.iso
openbsd-vm.qcow2' ] || { ls -A; exit 1; }
rm install80.iso openbsd-vm.qcow2

# A hung-up boot must still power the VM down through the QEMU monitor, so the
# guest flushes its disk. The fake VM reads raw console bytes as hex.
mkdir "$work/vm"
cat > "$work/vm/qemu-system-x86_64" <<'VM'
#!/bin/sh
stty -icanon -echo min 1 time 0
echo "$$" > "$PROVISION_TEST_WORK/vm.pid"
printf 'Booting\r\n'
input=
while byte=$(dd bs=1 count=1 2> /dev/null | od -An -tx1 | tr -d ' \n') && [ -n "$byte" ]; do
    input="$input$byte"
    case "$input" in
        # Control-A, c opens the monitor.
        *0163) printf '(qemu) '; input= ;;
        # system_powerdown followed by a carriage return or newline.
        *73797374656d5f706f776572646f776e0d | *73797374656d5f706f776572646f776e0a)
            echo powerdown > "$PROVISION_TEST_WORK/vm.log"
            exit 0 ;;
    esac
done
exit 1
VM
chmod +x "$work/vm/qemu-system-x86_64"
printf 'disk\n' > openbsd-vm.qcow2
PATH=$work/vm:$PATH "$EXPECT" "$repo/boot.exp" > "$work/result" 2>&1 &
booter=$!
tries=0
until [ -s "$work/vm.pid" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 100 ] || { cat "$work/result"; exit 1; }
    sleep 0.1
done
sleep 0.2
kill -HUP "$booter"
if wait "$booter"; then
    echo 'Hung-up boot exited successfully' >&2; exit 1
fi
if [ "$(cat "$work/vm.log" 2> /dev/null)" != powerdown ]; then
    cat "$work/result"
    kill "$(cat "$work/vm.pid")" 2> /dev/null || :
    echo 'Hung-up boot did not power down the VM' >&2; exit 1
fi
rm openbsd-vm.qcow2
printf '%s\n' 'Provisioning preview regressions passed'
