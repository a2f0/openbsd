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

## Python distribution metadata

Python 3.15.1 was published after uv 0.13.4's embedded download catalog. The
`python-downloads-json-url` setting in `pyproject.toml` uses uv's
[documented catalog override](https://docs.astral.sh/uv/reference/settings/#python-downloads-json-url)
with the official metadata from [uv PR #22802](https://github.com/astral-sh/uv/pull/22802),
pinned to its immutable merge commit. It provides
checksummed [Astral standalone builds](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021)
for the same interpreter on developer platforms and Linux CI, without a custom
installer or global tool changes.

After upgrading uv, check its built-in catalog with
`uv --no-config python list 3.15.1 --only-downloads --all-platforms --all-arches --all-versions`.
Remove the override once the catalog includes macOS arm64 and Linux amd64, then
repeat locked setup, controller validation, and QEMU CI. Until then, keep the
metadata commit immutable and verify any replacement's download hashes against
the corresponding official release.

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
