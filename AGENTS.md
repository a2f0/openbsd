# Repository guidance

Read README.md and the relevant [provisioning](docs/provisioning.md) or
[baseline operations](docs/baseline.md) guide before changing the controller or
native baseline. Resolve GitHub
identity with `gh repo view --json nameWithOwner`. Work on a feature branch,
preserve unrelated edits, and use Conventional Commits.

## Setup and validation

Controller Bun and uv are pinned in `.mise.toml`; uv selects Python from
`.python-version`. In agent shells, put the matching directories under
`~/.local/share/mise/installs` first on `PATH` rather than running `mise trust`.
Install agent tooling with `bun install --frozen-lockfile`,
then run `make deps`. These are controller-only dependencies; the OpenBSD host
uses base tools and must not gain packages or Python from this workflow.

Run `make lint syntax test`, `make test-provisioning` (requires Expect), and
`bun run agents:check`. The provisioning regression test mocks external effects.
Full QEMU installation and hardening run in CI; do not provision a VM or apply
the baseline to a real host merely to validate documentation or tooling changes.
No repository Git hooks are installed.

Use `bun run check` for the local lint, syntax, test, provisioning-guard, and
managed-skill and permission sequence. This local command does not replace CI's `check` job,
which installs and verifies a disposable OpenBSD VM. CI validates the actual
branch with `bun run lint:branch-name <name>`. Feature branches use the configured
Conventional Commit type followed by `/topic`; main is exempt and there is no
branch-length cap. Use the managed shipping and reset skills for shared PR and
confirmed-merge cleanup mechanics.

## Output capture

Run finite, noisy commands, such as installs, builds, tests, linters, package
scripts, and Git commands that run hooks, through
`bun run agent:run --label <name> -- <command> [args...]`. It keeps complete
output in a private log, preserves the exit status, and prints a compact
receipt, with a bounded excerpt of the log on failure. Read more with
`bun run agent:logs <log-path>`, raising `--tail-lines` or `--max-bytes` as
needed, or with a targeted search of the log. A zero exit does not rule out
warnings: inspect required warnings, timings, and artifacts before accepting a
check. Run reviews, version preparation, audits, infrastructure previews, and
run-group checks directly so their results stay visible, and run interactive
tools and servers directly too. Never narrow a suite or silence warnings to
reduce output.

For example, capture the controller checks with
`bun run agent:run --label checks -- make lint syntax test test-provisioning`.
`bun run check` is already an `agent-tool run-group` that records each step, so
run it directly rather than through `agent:run`. Keep audit reports and other
structured decision output visible.

## Shared skills and shipping

`@a2f0/agent-tool` is pinned exactly in package.json and bun.lock. After updating
it or the `permissions` section of `agent-tool.json`, run `bun run agents:sync`,
which installs the managed skills and then the generated harness permission
rules, and commit the lockfile, `.agent-tool-skills.json`, the generated skills
under `.agents/skills` and `.claude/skills`, `.agent-tool-permissions.json`,
`.claude/settings.json`, and `.codex/rules/agent-tool.rules` together. Do not
edit managed skills or generated rules. Keep repository guidance here; do not
add CLAUDE.md. The existing CI `lint` job runs `bun run agents:check` to detect
skill and permission drift. `agent-tool.json` classifies no executables:
agent-tool is the only installed package executable, and the controller linters
run through `make` from uv's `.venv`.

Use the installed `ship-pr` skill for authorized shipping, including independent
review of the committed HEAD. `agent-tool.json` requires both `lint` and `check`
from workflow `main`; wait for every push and pull-request check to finish.
There is no package release or deployment workflow. Do not change repository
protection settings as part of routine shipping.

## Dependency documentation

Read [dependency maintenance](docs/dependency-upgrades.md) before upgrades.
Keep reusable procedures and active constraints there, updating entries in place
and removing resolved ones. Keep run-specific versions, audits, validation,
previews, and skipped-group evidence in the upgrade PR. The top-level README
needs only setup, normal usage, and a short maintenance link; do not append
upgrade reports or duplicate agent instructions there.

## Script and documentation layout

Keep the public controller commands at the repository root and the deployable
native implementation in `baseline/`. Retain Makefile targets and `tests/` as the
validation interface. Put future internal maintenance helpers under purpose-based
`scripts/` directories, without moving product entrypoints merely for uniformity.
README owns setup and normal command discovery; the linked operational guides own
procedures and recovery details. Update those guides and their callers together.
