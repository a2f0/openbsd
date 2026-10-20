# Repository guidance

Read README.md before changing the controller or native baseline. Resolve GitHub
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

Capture noisy finite commands with `bun run agent:run --label <check> --
<command> [args...]`, for example
`bun run agent:run --label checks -- make lint syntax test test-provisioning`.
The harness preserves exit status and complete private logs, with one compact
receipt and a bounded failure excerpt. Inspect more with
`bun run agent-tool logs <log-path>` or a targeted search. A zero exit does not
prove the absence of warnings: inspect required warnings, timings, and artifacts
before accepting a check. Keep review verdicts, audit reports, and structured
decision output visible. Run interactive commands and persistent servers directly.

## Shared skills and shipping

`@a2f0/agent-tool` is pinned exactly in package.json and bun.lock. After updating
it, run `bun run agents:sync` and commit the lockfile, `.agent-tool-skills.json`,
and generated skills under `.agents/skills` and `.claude/skills` together. Do not
edit managed skills. Keep repository guidance here; do not add CLAUDE.md.
The existing CI `lint` job runs `bun run agents:check` to detect skill drift.

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
