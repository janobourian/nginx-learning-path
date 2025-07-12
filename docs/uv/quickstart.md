# Quickstart

First of all you maybe want to read the docs: `https://docs.astral.sh/uv/` 

In general, you can check the next resource to view more information about every command: `https://docs.astral.sh/uv/reference/cli/#uv`

## Init the project

```sh
uv --version
uv init python-libraries
uv add ruff
uv run ruff check
uv tree
uv lock
uv sync
uv remove ruff
uv tree
uv add ruff requests
uv lock --upgrade-package requests
```

You can run scripts with an isolated environment `uv run --with rich example.py`

## Alternative commands 

The next commands are not necessary but, is still necessary to meet them.

```sh
uv add 'requests==2.31.0'
uv add git+https://github.com/psf/requests
uv add -r requirements.txt -c constraints.txt
uv build
ls dist/
```

## Docker configuration

```Dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1

ENV UV_LINK_MODE=copy

RUN --mount=type=cache,target=/root/.cache/uv --mount=type=bind,source=uv.lock,target=uv.lock --mount=type=bind,source=pyproject.toml,target=pyproject.toml uv sync --locked --no-install-project --no-dev

COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv uv sync --locked --no-dev

ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8000
CMD ["uvicorn", "apps.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```