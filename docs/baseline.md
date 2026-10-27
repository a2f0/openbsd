# Native security baseline

Run the controller commands below from the repository root after completing
[controller setup](../README.md#quick-start).

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

For initial installation, OpenBSD also supports native custom `site80.tgz` sets
and `/install.site` hooks; see [install.site(5)](https://man.openbsd.org/OpenBSD-8.0/install.site.5).
This repository applies the baseline after installation so it can prove SSH key
access before disabling password login.

The native script replaces the old Ansible-managed SSH block when found.
Existing installations keep the Python package installed by the previous
bootstrap. Inspect `pkg_info` and its dependents before removing that package;
migration does not remove packages automatically. Fresh installs need none.

See [VM provisioning](provisioning.md) to create and verify a disposable VM, and
[repository setup](../README.md#quick-start) for controller dependencies.
