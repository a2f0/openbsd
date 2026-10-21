# Dependency maintenance

Use the managed `update-dependencies` skill and the repository's
[setup and validation guidance](../AGENTS.md#setup-and-validation).

## Toolchain boundaries

Python and development tools run on the controller. The OpenBSD baseline uses
base tools and must not gain packages or Python when controller dependencies
change. Keep the controller Python selection in `.python-version`, its supported
range in `pyproject.toml`, and CI aligned. Preserve exact development dependency
pins and refresh `uv.lock` with the pinned uv version.

Keep Bun and uv pinned in `.mise.toml`; CI installs those versions with mise.
Keep `package.json`'s `packageManager` aligned with the Bun pin. Python packages
remain managed by uv, and `.python-version` remains its interpreter selection.

To update Python tools, change their exact versions, run `uv lock`, then
`make deps lint syntax test test-provisioning`. Provisioning regression tests
require Expect and mock external effects; they do not start a VM. Check OS tool
compatibility separately when changing the OpenBSD release or controller image.
Do not provision a VM or apply the baseline to a real host merely to validate
documentation or controller tooling.

Agent-tool is controller-only too. Follow the
[managed skill update procedure](../AGENTS.md#shared-skills-and-shipping) when
changing its exact pin. CI action references remain pinned to commit SHAs.

## Python distribution availability

The controller interpreter must be available through the pinned uv release on
both macOS arm64 and Linux amd64. Python 3.15.1 is published upstream, but
[uv 0.13.4](https://github.com/astral-sh/uv/releases/tag/0.13.4) only provides
3.15.0 in its managed download catalog. Keep `.python-version` at 3.15.0 until
`uv python list 3.15.1 --all-platforms --all-arches --all-versions` includes both
platforms, then update the pin and README and repeat controller and QEMU CI.
Do not substitute a local-only interpreter while CI still uses uv's catalog.

Use uv 0.13.4 or later to address its
[emSign CA advisory](https://github.com/astral-sh/uv/security/advisories/GHSA-hq85-5cpj-mr62).
The repository installs with uv and does not invoke Python's bundled pip; any
separate use of pip must follow the
[Python security release guidance](https://www.python.org/downloads/release/python-3151/).

## Tcl tooling constraints

[tclint's published metadata](https://pypi.org/pypi/tclint/0.9.0/json)
pins its parser and language-server dependencies exactly. Keep importlib-metadata,
pathspec, pygls, and voluptuous within those pins even when newer releases exist;
pygls also constrains lsprotocol. Revisit them with a supported tclint release,
regenerate the lockfile, and run the full controller validation above instead of
overriding the linter's internal dependencies. Check each resolved package's
Python requirements when changing the controller interpreter.

## Keeping the record current

Record each upgrade's selected versions, audits, validation, warnings, previews,
and held groups in its PR. Keep only reusable procedure and unresolved constraints
here, with evidence links and conditions for revisiting them. Update or remove
entries as constraints change; do not append a dated upgrade journal. Historical
results do not establish current compatibility or a fresh audit.
