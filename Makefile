.PHONY: deps lint format syntax

EXPECT_RUN = UV_PROJECT_ENVIRONMENT=.venv-expect uv run --locked --no-default-groups --group expect

deps:
	uv sync --locked
	UV_PROJECT_ENVIRONMENT=.venv-expect uv sync --locked --no-default-groups --group expect
	uv run --locked ansible-galaxy collection install --no-deps -r ansible/requirements.yml -p .ansible/collections

lint:
	$(EXPECT_RUN) tclint .
	$(EXPECT_RUN) tclfmt --check .
	uv run --locked ansible-lint

format:
	$(EXPECT_RUN) tclfmt --in-place .

syntax:
	uv run --locked ansible-playbook ansible/bootstrap.yml --syntax-check
	uv run --locked ansible-playbook ansible/harden.yml --syntax-check
