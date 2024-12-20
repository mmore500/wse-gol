#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

python3 -m uv pip compile requirements.in | tee requirements.txt
