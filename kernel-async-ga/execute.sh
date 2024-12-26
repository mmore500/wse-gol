#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

echo "CS_PYTHON ${CS_PYTHON}"
echo "ASYNC_GA_EXECUTE_FLAGS ${ASYNC_GA_EXECUTE_FLAGS:-}"

echo "setup LOCAL -------------------------------------------------------------"
echo "LOCAL ${LOCAL:-}"
export LOCAL="${LOCAL:-local}/bio240020p/$(uuidgen)"
echo "LOCAL ${LOCAL}"
mkdir -p "${LOCAL}"
touch "${LOCAL}/.touch"
cp -r "../cerebraslib" "${LOCAL}/cerebraslib"

export APPTAINERENV_ASYNC_GA_NCOL="${ASYNC_GA_NCOL:-3}"
export APPTAINERENV_ASYNC_GA_NROW="${ASYNC_GA_NROW:-3}"
export APPTAINERENV_ASYNC_GA_NTRAIT="${ASYNC_GA_NTRAIT:-1}"
export APPTAINER_BINDPATH="${LOCAL}:/local:rw,../cerebraslib:/cerebraslib:rw"
export SINGULARITY_BINDPATH="${LOCAL}:/local:rw,../cerebraslib:/cerebraslib:rw"

"${CS_PYTHON}" client.py ${ASYNC_GA_EXECUTE_FLAGS:-}
