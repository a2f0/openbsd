# OpenBSD

Ansible supports OpenBSD over SSH. Most modules need Python on the target;
the bootstrap playbook installs it with `raw`, which works without Python.
See [Ansible's BSD guide](https://docs.ansible.com/projects/ansible/latest/os_guide/intro_bsd.html).

## Dependencies and linting

Install [uv](https://docs.astral.sh/uv/) version **0.12.22**, then run:

```sh
make deps
make lint syntax
```

The controller uses Python **3.14.8** from `.python-version`. `uv` installs it
when necessary. Direct tools have exact versions in `pyproject.toml`, and
`uv.lock` pins their transitive dependencies and hashes. Ansible collections,
including their dependency, are pinned in `ansible/requirements.yml`; installation
disables automatic dependency resolution. CI actions are pinned to commit SHAs.

Ansible and Expect tools use `.venv` and `.venv-expect` respectively because their
linters require incompatible versions of `pathspec`. `make lint` checks all
`.exp` and `.tcl` files with `tclint`'s Expect plugin, checks formatting, and runs
`ansible-lint`. Run `make format` to format the Expect files.

To update dependencies, change the exact versions in `pyproject.toml`, run
`uv lock`, and rerun `make deps lint syntax`. Review collection versions and
their dependencies separately. OS packages come from the selected OS release's
repositories so security updates remain available.

## QEMU

The VM runs OpenBSD **7.9/amd64**. Install Expect, QEMU, wget, and GNU coreutils
on the host (Ubuntu: `sudo apt-get install expect qemu-system-x86 wget coreutils`;
macOS: `brew install qemu wget coreutils`, using the system `/usr/bin/expect`).
QEMU can emulate amd64 on other host architectures, though it will be slower.
Provisioning downloads an approximately 800 MB ISO and creates a 5 GB virtual disk.

1. Run `./qemu.exp` to provision the vm.
2. Run `./boot.exp` to use it (and `ssh -p 2222 a2f0@localhost` for ssh).

Set `USER_PASSWORD` and `ROOT_PASSWORD` before provisioning. `./qemu.exp` installs
the SSH public key in `SSH_PUBLIC_KEY` for the user, or the existing default key
when it is unset. Use your own public key to manage the VM with Ansible.
The installer response file contains passwords, is created with mode `0600`,
and is served on host loopback. The script removes `install.conf` on exit.
The booted VM's forwarded SSH port also listens on host loopback.

`./boot.exp --check` boots the vm without attaching to it, logs in on the console
with `USER_PASSWORD`, logs in over ssh on port 2222 (with the private key in
`SSH_IDENTITY_FILE`, or ssh's defaults), and powers the vm off. CI runs it after
the install with a throwaway key pair. It obtains the SSH host key from the VM
console and verifies SSH against that key.

`./boot.exp --check-hardened` additionally bootstraps Python, applies the baseline,
applies it again to verify idempotence, and checks SSH access after hardening.
It requires `ROOT_PASSWORD` and `SSH_IDENTITY_FILE` as well as `USER_PASSWORD`.
This smoke test uses `su` for root access so it can run on a fresh installation.
CI runs this test after linting; it does not enable optional patching.

## Security baseline

Start the VM with `./boot.exp` and leave it running while executing Ansible in
another terminal. `ansible/inventory.yml` targets `a2f0@127.0.0.1:2222`; use
`-i /path/to/inventory.yml` for other hosts in the `openbsd` group.
The target Python defaults to `/usr/local/bin/python3.13`, installed with
`python%3` for OpenBSD 7.9's `lang/python/3` port branch. Override
`ansible_python_interpreter` and, when necessary,
`openbsd_python_package` when targeting a release with a different Python branch.

Use a non-root account with a working SSH key and root privilege escalation.
Before changing authentication, the role verifies a separate key-only SSH login
without reusing an existing connection, while retaining host verification and proxy options.
Verify the host key against the fingerprint shown on the VM console before
accepting it in your normal `known_hosts`. Host key checking stays enabled.

For ordinary hosts, configure `doas` from a root console. A typical rule for
the installer-created wheel user is `permit persist :wheel as root` in
`/etc/doas.conf`, owned by root with mode `0600`. Validate the file with
`doas -C /etc/doas.conf`. Ansible uses `community.general.doas`; `-K` prompts
for the user's privilege escalation password.

```sh
uv run --locked ansible-playbook ansible/bootstrap.yml -K
uv run --locked ansible-playbook ansible/harden.yml -K --check --diff
uv run --locked ansible-playbook ansible/harden.yml -K --diff
```

Add `--private-key /path/to/key` if SSH cannot discover your key. For a fresh VM
without a doas rule, add `-e ansible_become_method=ansible.builtin.su` to each
command and provide the **root** password at the `-K` prompt. Bootstrap Python
before the hardening dry run; bootstrap in check mode does not install packages.

The baseline:

- Requires SSH public key authentication, disables root SSH login and password
  authentication, limits authentication attempts and login grace time, and logs
  SSH authentication verbosely.
- Disables SSH forwarding by default. Set
  `openbsd_baseline_ssh_disable_forwarding: false` if the host needs tunnels or
  agent forwarding. OpenSSH's default cipher and algorithm choices remain in use.
- Disables IPv4/IPv6 routing, source routing, ICMP redirects, and core dumps from
  processes that change user/group IDs, with OpenBSD-native sysctls.
- Can stop and disable services listed in `openbsd_baseline_disabled_services`.
- Can apply base system patches and update installed packages when
  `openbsd_baseline_apply_syspatches` and `openbsd_baseline_update_packages` are
  enabled. It reports required reboots for the operator to schedule.

Review the defaults in `ansible/roles/openbsd_baseline/defaults/main.yml` and
override them in your inventory or an extra-vars file. For a router, replace
`openbsd_baseline_sysctls` with the settings appropriate for its routing duties.
The role checks that each sysctl exists and verifies its live value after applying it.
The default service list is empty; PF rules, disk layout, and privilege rules
need a host-specific policy and are outside this initial baseline. This is a
starting configuration, not a claim of compliance with an audit standard.

SSH settings go in a managed block at the beginning of `/etc/ssh/sshd_config`.
The complete candidate is checked with `sshd -t` before replacement, a backup
is saved, and sshd reloads only when the file changes. The playbook then opens
a fresh SSH connection to check access. Review existing `Match` blocks and
included configurations on customized hosts, since they can override global
settings. Keep console access available when first applying the baseline;
restore the timestamped SSH configuration backup and run `rcctl reload sshd`
from the console if needed.
