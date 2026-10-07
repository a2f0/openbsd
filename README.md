# OpenBSD

Provision an OpenBSD **7.9/amd64** VM and apply a small security baseline with
OpenBSD's base tools: `sh`, `ssh`, `doas`, `sysctl`, `install`, and `rcctl`.
The baseline installs **no packages and no Python on the OpenBSD host**.

## Dependencies and linting

Install [uv](https://docs.astral.sh/uv/) version **0.12.23**, then run:

```sh
make deps
make lint syntax test
```

Python **3.14.8** from `.python-version` runs on the controller only, for the
installer's local HTTP server and development tools. Exact tool versions are
in `pyproject.toml`; `uv.lock` pins their transitive dependencies and hashes.
Expect linting uses `tclint==0.9.0`; shell linting uses the bundled ShellCheck
**0.11.0** binary in `shellcheck-py==0.11.0.1`. Both run from `.venv`.
CI actions are pinned to commit SHAs. OS tools come from the selected release's
repositories so security updates remain available.

`make lint` checks Expect syntax, formatting, and shell scripts; `make syntax`
checks shell parsing. `make test` checks deployment's authentication and transfer
failure handling against inherited SSH options. Run `make format` to format
Expect files. To update tools, change the exact versions, run `uv lock`, then
rerun `make deps lint syntax test`.

## QEMU

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
checks the selected ISO against that checksum before creating the fresh disk.
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

## Native security baseline

Review `baseline/sshd.conf` and `baseline/sysctl.conf` before deployment. This
host baseline requires SSH public key authentication, disables root SSH login,
password login and forwarding, limits authentication attempts and login grace
time, and logs SSH authentication verbosely. It retains OpenSSH's default
algorithms. The kernel settings disable routing, source routing, redirect-created
routes, and core dumps from processes that change user/group IDs. For a router,
edit the forwarding settings; for an SSH tunnel endpoint, review `DisableForwarding`.
This is a starting policy, not a claim of compliance with an audit standard.

Use a non-root account with a working SSH key and root privilege through `doas`.
Configure `doas` from a root console if necessary. A typical wheel-user rule is
`permit persist :wheel as root` in `/etc/doas.conf`, owned by root with mode
`0600`; validate it with `doas -C /etc/doas.conf`. Verify the SSH host key against
the console before adding it to your controller's `known_hosts`.

Leave `./boot.exp` running and use another terminal:

```sh
./deploy.sh --check -p 2222 -i /path/to/private_key a2f0@127.0.0.1
./deploy.sh -p 2222 -i /path/to/private_key a2f0@127.0.0.1
./deploy.sh --verify -p 2222 -i /path/to/private_key a2f0@127.0.0.1
```

For another host, use `user@host` and its port. `--known-hosts /path/to/file`
selects a verified host-key file. SSH configuration still supplies proxy settings.
Every connection uses strict host verification and no connection sharing or
backgrounding. The helper checks the actual public-key authentication method
before deployment and afterward; `-i` selects `IdentitiesOnly=yes` to avoid exhausting the
authentication limit with a large agent. The helper proves access before copying
files, stages a private temporary directory, invokes `doas` with a terminal for
its password prompt, checks a new SSH login afterward, and removes staging files.
Passwords are entered interactively and are not passed as command arguments.

The same script works locally after copying the `baseline` directory to a host:

```sh
doas sh baseline/baseline.sh check
doas sh baseline/baseline.sh apply
doas sh baseline/baseline.sh verify
```

`check` validates candidates and reports proposed changes without replacing
system files or writing kernel settings. `apply` changes only settings that
differ; `verify` fails on file, permission, ownership, kernel, or SSH policy drift.
The script requires OpenBSD and root, validates every sysctl name, checks the
complete candidate with `sshd -t` and `sshd -T`, and reads back each kernel write.
It keeps unrelated configuration, prepends the managed SSH block (OpenSSH uses
the first global value), and appends the managed sysctl block for boot-time use.
Files are atomically installed as root:wheel with modes `0600` and `0644`.
Changed files receive backups named `.baseline.<UTC timestamp>.<pid>`; sshd
reloads only when its file changes. A failed apply attempts to restore original
files, ownership, permissions and kernel values, then reload the original SSH
configuration. Runs use a lock in `/var/run/openbsd-baseline.lock`; after a
forced kill, remove a stale lock only after confirming the process has stopped.

The deployment helper also validates the SSH `Match` policy for the current
user and connection addresses. Its `host` context uses the client address;
review hostname-based `Match` rules and other users/addresses separately. For
manual context checks, pass `--ssh-context` with the connection specification
accepted by [sshd(8)](https://man.openbsd.org/sshd). Keep console access available
on the first application. A successful syntax or policy check cannot prove that
every user's authorized key or custom access rule will still work. If the fresh
login fails, restore the SSH backup and run `rcctl reload sshd` from the console.

## Native maintenance and migration

Service policy, PF rules, disk layout and privilege rules depend on the host and
remain separate from this baseline. Use `rcctl stop <service>` and
`rcctl disable <service>` for services you have chosen to retire. Apply base fixes
with `doas syspatch` and schedule any required reboot; use `doas pkg_add -u` for
installed packages. These maintenance commands are explicit operator actions.

For initial installation, OpenBSD also supports native custom `site79.tgz` sets
and `/install.site` hooks; see [install.site(5)](https://man.openbsd.org/OpenBSD-7.9/install.site.5).
This repository applies the baseline after installation so it can prove SSH key
access before disabling password login.

The native script replaces the old Ansible-managed SSH block when found.
Existing installations keep the Python package installed by the previous
bootstrap. Inspect `pkg_info` and its dependents before removing that package;
migration does not remove packages automatically. Fresh installs need none.
