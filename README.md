# OpenBSD

Provision an OpenBSD **8.0/amd64** VM and apply a small security baseline with
OpenBSD's base tools: `sh`, `ssh`, `doas`, `sysctl`, `install`, and `rcctl`.
The baseline installs **no packages and no Python on the OpenBSD host**.

## Dependencies and linting

On the controller, [mise](https://mise.jdx.dev/) installs the Bun and
[uv](https://docs.astral.sh/uv/) versions pinned in `.mise.toml`. CI uses the
same pins:

```sh
mise install
bun install --frozen-lockfile
make deps
make lint syntax test
```

Python **3.15.1** from `.python-version` runs on the controller only, for the
installer's local HTTP server and development tools. Exact tool versions are
in `pyproject.toml`; `uv.lock` pins their transitive dependencies and hashes.
Expect linting uses `tclint==0.9.0`; shell linting uses the bundled ShellCheck
**0.11.0** binary in `shellcheck-py==0.11.0.1`. Both run from `.venv`.
CI actions are pinned to commit SHAs. OS tools come from the selected release's
repositories so security updates remain available.

`make lint` checks Expect syntax, formatting, and shell scripts; `make syntax`
checks shell parsing. `make test` checks deployment's authentication and transfer
failure handling against inherited SSH options. Run `make format` to format
Expect files. See [dependency maintenance](docs/dependency-upgrades.md) for
tool updates and controller/host compatibility boundaries.

Coding agents follow [AGENTS.md](AGENTS.md) for controller-only agent tooling,
command capture, managed skills, and the review and shipping workflow.

## Provisioning and baseline operations

The public controller entrypoints stay at the repository root:

| Command | Purpose | Guide |
| --- | --- | --- |
| `./qemu.exp --dry-run` | Preview an OpenBSD VM installation without creating files or starting a VM | [Provisioning](docs/provisioning.md) |
| `./qemu.exp` | Install a new disposable VM after previewing its configuration | [Provisioning](docs/provisioning.md) |
| `./boot.exp` | Boot the VM; optional checks validate installation and hardening | [Provisioning](docs/provisioning.md) |
| `./deploy.sh --check …` | Preview the native baseline for an explicitly selected host | [Baseline operations](docs/baseline.md) |

Read the relevant guide before running these commands. Provisioning requires
controller tools and password environment variables; baseline deployment requires
verified SSH key access and `doas`. Each guide owns its prerequisites, preview,
execution, verification, and recovery procedure. Controller validation uses mocks;
it does not require provisioning a VM or changing a real host.

## Repository layout

`baseline/` contains the deployable OpenBSD configuration and native implementation.
`tests/` contains controller and host regression checks. The Makefile is the stable
controller validation entrypoint. These product commands and native assets retain
their established paths; shared branch, review, PR, and skill mechanics come from
the pinned agent-tool. Agent policy belongs in [AGENTS.md](AGENTS.md), with upgrade
constraints in [dependency maintenance](docs/dependency-upgrades.md).

## Validation

After dependency setup and installing [Expect](docs/provisioning.md),
`bun run check` runs the local controller checks and records their results. CI also provisions and verifies a disposable OpenBSD VM;
see [AGENTS.md](AGENTS.md) for the required integration gate.
