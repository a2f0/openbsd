# VM provisioning and verification

Run the commands below from the repository root after completing
[controller setup](../README.md#dependencies-and-linting).

Install Expect, QEMU, wget, and GNU coreutils on the controller (Ubuntu:
`sudo apt-get install expect qemu-system-x86 wget coreutils`; macOS:
`brew install qemu wget coreutils`, using the system `/usr/bin/expect`). QEMU can
emulate amd64 on another architecture, though it will be slower. Provisioning
needs an approximately 800 MB ISO and creates a 5 GB virtual disk.

Set `USER_PASSWORD` and `ROOT_PASSWORD`, then run:

```sh
./qemu.exp --dry-run
./qemu.exp
./boot.exp
```

Set `SSH_PUBLIC_KEY` before installation to authorize your own key for `a2f0`;
otherwise the existing default public key is used. SSH is forwarded at
`a2f0@127.0.0.1:2222`. The password-bearing `install.conf` has mode `0600`, is
served on controller loopback, and is removed on exit. The forwarded SSH listener
also binds to loopback.

The installer always previews its selected release, ISO checksum, disk, and QEMU
commands before creating anything. `--dry-run` performs that preflight without
creating files or starting a VM; it reads the release checksum over HTTPS and
rejects an existing disk or `install.conf`, including symlinks. Installation
disables wget's user configuration and HSTS cache for these requests so preview
cannot create a cache file or inherit download side effects. It
checks the selected ISO against that checksum before creating the fresh disk.
An interrupted download or mismatched cached ISO fails the preview and remains
untouched; inspect it and move it aside before retrying the download.
This checks integrity from the HTTPS release source; independent signature
verification requires [signify](https://www.openbsd.org/faq/faq4.html#Download).
Explicit QEMU drive formats and network devices preserve the IDE disk and
e1000 adapter without relying on legacy option defaults.
After installing Expect, `make test-provisioning` checks the preview's refusal
to overwrite existing artifacts or accept missing/mismatched ISO checksums,
using mocked controller commands without starting a VM.

`./boot.exp --check` tests console and SSH logins, then powers off the VM.
It requires `USER_PASSWORD`; `SSH_IDENTITY_FILE` selects a private key. The SSH
host key comes from the VM console and is strictly verified.

`./boot.exp --check-hardened` transfers the native baseline, tests a preview,
rejects invalid configurations, tests rollback after a failed kernel write,
applies and verifies the baseline, repeats it with `changed=0`, and checks a
fresh SSH key login. It also checks that no packages or target Python were
installed. This disposable-VM test uses `su` on the root console, and requires
`ROOT_PASSWORD` and `SSH_IDENTITY_FILE` too. `./boot.exp --verify-hardened`
boots again and verifies that the settings survived reboot. CI runs both.

See [native baseline operations](baseline.md) for the settings applied by the
hardening checks and the manual deployment workflow.
