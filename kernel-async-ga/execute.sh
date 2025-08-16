#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

echo "begin execute.sh --------------------------------------------------------"
echo "CS_PYTHON ${CS_PYTHON}"
echo "which ${CS_PYTHON} $(which "${CS_PYTHON}")"
echo "ASYNC_GA_EXECUTE_FLAGS ${ASYNC_GA_EXECUTE_FLAGS:-}"

echo "setup LOCAL -------------------------------------------------------------"
echo "LOCAL ${LOCAL:-}"
export MYLOCAL="${LOCAL:-local}/bio240020p/$(uuidgen)"
echo "MYLOCAL ${MYLOCAL}"
mkdir -p "${MYLOCAL}"
touch "${MYLOCAL}/.touch"
cp -r "../cerebraslib" "${MYLOCAL}/cerebraslib"

echo "configure container ENV -------------------------------------------------"
export APPTAINERENV_ASYNC_GA_NCOL="${ASYNC_GA_NCOL:-3}"
echo "APPTAINERENV_ASYNC_GA_NCOL ${APPTAINERENV_ASYNC_GA_NCOL}"
export APPTAINERENV_ASYNC_GA_NROW="${ASYNC_GA_NROW:-3}"
echo "APPTAINERENV_ASYNC_GA_NROW ${APPTAINERENV_ASYNC_GA_NROW}"
export APPTAINERENV_ASYNC_GA_NTRAIT="${ASYNC_GA_NTRAIT:-1}"
echo "APPTAINERENV_ASYNC_GA_NTRAIT ${APPTAINERENV_ASYNC_GA_NTRAIT}"
export APPTAINER_BINDPATH="${MYLOCAL}:/local:rw,../cerebraslib:/cerebraslib:rw"
echo "APPTAINER_BINDPATH ${APPTAINER_BINDPATH}"

export SINGULARITYENV_ASYNC_GA_NCOL="${APPTAINERENV_ASYNC_GA_NCOL}"
echo "SINGULARITYENV_ASYNC_GA_NCOL ${SINGULARITYENV_ASYNC_GA_NCOL}"
export SINGULARITYENV_ASYNC_GA_NROW="${APPTAINERENV_ASYNC_GA_NROW}"
echo "SINGULARITYENV_ASYNC_GA_NROW ${SINGULARITYENV_ASYNC_GA_NROW}"
export SINGULARITYENV_ASYNC_GA_NTRAIT="${APPTAINERENV_ASYNC_GA_NTRAIT}"
echo "SINGULARITYENV_ASYNC_GA_NTRAIT ${SINGULARITYENV_ASYNC_GA_NTRAIT}"
export SINGULARITY_BINDPATH="${APPTAINER_BINDPATH}"
echo "SINGULARITY_BINDPATH ${SINGULARITY_BINDPATH}"

echo "run client.py -----------------------------------------------------------"
"${CS_PYTHON}" client.py ${ASYNC_GA_EXECUTE_FLAGS:-}
