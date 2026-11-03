# Dependency maintenance

Use the managed `update-dependencies` skill and the repository's
[setup and validation guidance](../AGENTS.md#setup-and-validation).

## Toolchain boundaries

Python and development tools run on the controller. The controller Python that
`.python-version` selects serves `qemu.exp`'s local installer HTTP server and
runs the development tools from `.venv`: tclint (`tclint` and `tclfmt`) for
Expect files, and the ShellCheck binary bundled in `shellcheck-py`, whose version
is the bundled ShellCheck release plus a packaging suffix. The OpenBSD baseline
uses base tools and must not gain packages or Python when controller dependencies
change. Keep the controller Python selection in `.python-version`, its supported
range in `pyproject.toml`, and CI aligned. `pyproject.toml` pins the development
tools exactly, and `uv.lock` pins their transitive dependencies and hashes;
preserve those exact pins and refresh `uv.lock` with the pinned uv version.

Keep Bun and uv pinned in `.mise.toml`; CI installs those versions with mise.
Keep `package.json`'s `packageManager` aligned with the Bun pin. Python packages
remain managed by uv, and `.python-version` remains its interpreter selection.

To update Python tools, change their exact versions, run `uv lock`, then
`make deps lint syntax test test-provisioning`. Provisioning regression tests
require Expect and mock external effects; they do not start a VM. Controller OS
tools (Expect, QEMU, wget, and GNU coreutils) are not pinned: they come from the
controller OS's packages, which CI installs from its Ubuntu release's
repositories, so security updates remain available. Check OS tool compatibility
separately when changing the OpenBSD release or controller image.
Do not provision a VM or apply the baseline to a real host merely to validate
documentation or controller tooling.

Agent-tool is controller-only too. Follow the
[managed skill update procedure](../AGENTS.md#shared-skills-and-shipping) when
changing its exact pin. CI action references remain pinned to commit SHAs.

## Python distribution metadata

Use uv's built-in checksummed Python catalog. Before changing `.python-version`,
check the selected uv with
`uv --no-config python list <version> --only-downloads --all-platforms --all-arches --all-versions`.
Verify macOS arm64 developer and Linux amd64 CI builds, preserving the supported
Python range. Repeat locked setup, full controller validation, and disposable-VM
CI with that interpreter.

If a future security release needs uv's
[documented catalog override](https://docs.astral.sh/uv/reference/settings/#python-downloads-json-url),
pin official metadata to an immutable commit and verify its release checksums.
Remove it only after the built-in catalog covers every target it supplied.
Keep agent-run `UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR`, and `UV_TOOL_DIR` in this
checkout's task runtime, and `UV_PROJECT_ENVIRONMENT` in this checkout. Inspect
inherited values before setup; another session's exported paths are not safe
installation destinations. Verify the selected interpreter's `sys.base_prefix`
too: a foreign interpreter on `PATH` can satisfy the version pin. When needed,
install with `uv python install --no-bin <version>` into the scoped directory
and select that interpreter explicitly during `uv sync --locked --python <path>`.
Never change global tools or trust to run an upgrade.

## Tcl tooling constraints

[tclint's published metadata](https://pypi.org/pypi/tclint/0.9.0/json)
pins its parser and language-server dependencies exactly. Keep importlib-metadata,
pathspec, pygls, and voluptuous within those pins even when newer releases exist;
pygls also constrains lsprotocol. Revisit them with a supported tclint release,
regenerate the lockfile, and run the full controller validation above instead of
overriding the linter's internal dependencies. Check each resolved package's
Python requirements when changing the controller interpreter.

## Release media and host updates

The installer uses official OpenBSD release media, not an automatically patched
image. Check the release's [errata](https://www.openbsd.org/errata80.html) separately
from controller dependency audits; update that link together with
`qemu.exp`'s `OPENBSD_VERSION`. The baseline does not apply `syspatch` or
update host certificate/timezone databases; those remain explicit operator
[maintenance actions](baseline.md#native-maintenance-and-migration). Do not treat
controller validation or disposable-VM hardening as proof that release media
contains subsequent base-system security fixes. Changing that host-maintenance
contract requires its own safe preview and disposable-VM verification.

## Advisory coverage

Using the pinned tools, run `bun audit` on the resolved agent-tool graph and
`uv audit --locked` on the controller's resolved Python graph, including development dependencies and the
Linux CI target. Keep uv's preview/schema warnings visible in the run evidence.
These audits do not inspect the native ShellCheck binary bundled by shellcheck-py,
controller OS packages, or the OpenBSD base system. Check their official releases
and advisories separately; a clean npm/Python result is not a whole-system audit.

## Keeping the record current

Record each upgrade's selected versions, audits, validation, warnings, previews,
and held groups in its PR. Keep only reusable procedure and unresolved constraints
here, with evidence links and conditions for revisiting them. Update or remove
entries as constraints change; do not append a dated upgrade journal. Historical
results do not establish current compatibility or a fresh audit.
