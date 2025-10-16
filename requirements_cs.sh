#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

python3 -m uv pip compile requirements_cs.in --python-version 3.8 | tee requirements_cs.txt
