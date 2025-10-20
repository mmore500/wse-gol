#!//bin/bash

set -euo pipefail

cd "$(dirname "$0")"
echo "PWD ${PWD}"
cd "$(git rev-parse --show-toplevel)"
echo "PWD ${PWD}"

echo "git rev-parse HEAD $(git rev-parse HEAD)"

###############################################################################
echo "setup work environment -------------------------------------------------"
###############################################################################

WORKDIR="${TMPDIR:-/tmp}/$(basename "$0" .sh)"
echo "WORKDIR ${WORKDIR}"
if [ -d "${WORKDIR}" ]; then
    echo "Clearing WORKDIR ${WORKDIR}"
    rm -rf "${WORKDIR}"
fi
mkdir "${WORKDIR}"

echo "creating venv"
VENVDIR="${WORKDIR}/venv"
echo "VENVDIR ${VENVDIR}"
python3.8 -m venv "${VENVDIR}"
source "${VENVDIR}/bin/activate"
which python3

echo "setting up venv"
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade uv
python3 -m uv pip install -r "requirements_cs.txt"
python3 -m uv pip install ./pylib_cs
python3 -m uv pip freeze | tee "${WORKDIR}/pip-freeze.txt"
python3 -m pylib_cs.cslc_wsclust_shim  # test install
