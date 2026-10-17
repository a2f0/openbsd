# Dependency maintenance

Use the managed `update-dependencies` skill and the repository's
[setup and validation guidance](../AGENTS.md#setup-and-validation).

## Toolchain boundaries

Python and development tools run on the controller. The OpenBSD baseline uses
base tools and must not gain packages or Python when controller dependencies
change. Keep the controller Python selection in `.python-version`, its supported
range in `pyproject.toml`, and CI aligned. Preserve exact development dependency
pins and refresh `uv.lock` with the pinned uv version.

To update Python tools, change their exact versions, run `uv lock`, then
`make deps lint syntax test test-provisioning`. Provisioning regression tests
require Expect and mock external effects; they do not start a VM. Check OS tool
compatibility separately when changing the OpenBSD release or controller image.
Do not provision a VM or apply the baseline to a real host merely to validate
documentation or controller tooling.

Agent-tool is controller-only too. Follow the
[managed skill update procedure](../AGENTS.md#shared-skills-and-shipping) when
changing its exact pin. CI action references remain pinned to commit SHAs.

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
