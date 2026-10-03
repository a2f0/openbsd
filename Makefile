.PHONY: deps lint format syntax test

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

test:
	sh tests/controller.sh
