# OpenBSD

Provision an OpenBSD **8.0/amd64** VM and apply a small security baseline with
OpenBSD's base tools: `sh`, `ssh`, `doas`, `sysctl`, `install`, and `rcctl`.
The baseline installs **no packages and no Python on the OpenBSD host**.

## Quick start

Install [mise](https://mise.jdx.dev/) for the Bun and [uv](https://docs.astral.sh/uv/)
pins in `.mise.toml`, and Expect, QEMU, wget, and GNU coreutils for the VM preview
([provisioning](docs/provisioning.md)).

```sh
mise install
bun install --frozen-lockfile  # pinned agent-tool for `bun run check`
make deps                      # locked controller Python tools in .venv
make lint syntax test          # controller checks; no VM needed
# With USER_PASSWORD and ROOT_PASSWORD set, preview a VM installation; this
# creates no files and starts no VM.
./qemu.exp --dry-run
```

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

## Validation

| Command | Purpose |
| --- | --- |
| `make lint` | Expect syntax and formatting, and shell scripts |
| `make syntax` | Shell parsing |
| `make test` | Deployment's authentication and transfer failure handling against inherited SSH options |
| `make test-provisioning` | The installer preview's refusal to overwrite artifacts or accept missing or mismatched ISO checksums; requires [Expect](docs/provisioning.md) |
| `make format` | Formats Expect files in place |
| `bun run check` | Runs `make lint syntax test test-provisioning` and `bun run agents:check`, recording each result; requires Expect |

CI also provisions a disposable OpenBSD VM, applies the baseline, and verifies it
after a reboot. See [dependency maintenance](docs/dependency-upgrades.md) for tool
updates and controller/host compatibility boundaries.

## Repository layout

`baseline/` contains the deployable OpenBSD configuration and native implementation.
`tests/` contains controller and host regression checks. The Makefile is the stable
controller validation entrypoint, and `docs/` holds the provisioning, baseline
operations, and dependency maintenance guides.
