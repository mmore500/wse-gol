#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

python3 -m uv pip compile pylib_cs/pyproject.toml --python-version 3.8 | tee requirements_cs.txt
