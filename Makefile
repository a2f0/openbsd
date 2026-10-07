.PHONY: deps lint format syntax test test-provisioning

deps:
	uv sync --locked

lint:
	uv run --locked tclint .
	uv run --locked tclfmt --check .
	uv run --locked shellcheck baseline/*.sh deploy.sh tests/*.sh

format:
	uv run --locked tclfmt --in-place .

syntax:
	sh -n baseline/baseline.sh
	sh -n deploy.sh
	sh -n tests/on-host.sh
	sh -n tests/controller.sh
	sh -n tests/provisioning.sh

test:
	sh tests/controller.sh

# Requires the controller's Expect executable; all external effects are mocked.
test-provisioning:
	sh tests/provisioning.sh
