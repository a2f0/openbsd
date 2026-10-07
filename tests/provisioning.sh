#!/bin/sh
# Preview regression coverage: no network, disk creation, or virtual machine.
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -r "$work"' 0
trap 'exit 1' HUP INT TERM
mkdir "$work/bin" "$work/run"
PROVISION_TEST_WORK=$work
export PROVISION_TEST_WORK
cat > "$work/bin/wget" <<'WGET'
#!/bin/sh
set -eu
[ "$*" = '-q -O - https://cdn.openbsd.org/pub/OpenBSD/7.9/amd64/SHA256' ] || exit 90
cat "$PROVISION_TEST_WORK/manifest"
WGET
cat > "$work/bin/sha256sum" <<'CHECKSUM'
#!/bin/sh
echo '0000000000000000000000000000000000000000000000000000000000000000  install79.iso'
CHECKSUM
cat > "$work/bin/uv" <<'GUARD'
#!/bin/sh
echo 'Unexpected mutation command' >&2
exit 91
GUARD
cp "$work/bin/uv" "$work/bin/qemu-img"
cp "$work/bin/uv" "$work/bin/qemu-system-x86_64"
chmod +x "$work/bin/"*
PATH=$work/bin:$PATH
export PATH
USER_PASSWORD=fixture ROOT_PASSWORD=fixture
export USER_PASSWORD ROOT_PASSWORD
cd "$work/run"
checksum=0000000000000000000000000000000000000000000000000000000000000000
printf 'SHA256 (install79.iso) = %s\n' "$checksum" > "$work/manifest"
expect "$repo/qemu.exp" --dry-run > "$work/result"
grep -q 'Dry run passed: no files created, no VM started.' "$work/result"
[ -z "$(ls -A)" ]
reject() {
    expected=$1
    shift
    if expect "$repo/qemu.exp" "$@" > "$work/result" 2>&1; then
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
printf 'SHA256 (other.iso) = %s\n' "$checksum" > "$work/manifest"
reject 'Error: selected ISO has no release checksum.' --dry-run
printf 'SHA256 (install79.iso) = %s\n' "$checksum" > "$work/manifest"
printf 'SHA256 (install79.iso) = %s\n' "$checksum" >> "$work/manifest"
reject 'Error: duplicate ISO checksums in release manifest.' --dry-run
printf 'SHA256 (install79.iso) = %064d\n' 1 > "$work/manifest"
printf 'existing iso\n' > install79.iso
reject 'Error: cached ISO checksum differs from the selected release.' --dry-run
[ "$(cat install79.iso)" = 'existing iso' ]
printf 'SHA256 (install79.iso) = %s\n' "$checksum" > "$work/manifest"
expect "$repo/qemu.exp" --dry-run > "$work/result"
grep -q 'Dry run passed: no files created, no VM started.' "$work/result"
[ "$(cat install79.iso)" = 'existing iso' ]
rm install79.iso
printf '%s\n' 'Provisioning preview regressions passed'
