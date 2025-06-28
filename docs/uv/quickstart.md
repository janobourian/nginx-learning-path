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

Sometis the next commands are not necessary but, is still necessary to meet them.

```sh
uv add 'requests==2.31.0'
uv add git+https://github.com/psf/requests
uv add -r requirements.txt -c constraints.txt
uv build
ls dist/
```