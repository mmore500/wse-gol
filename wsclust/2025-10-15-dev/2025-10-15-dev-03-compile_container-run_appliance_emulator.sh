#!//bin/bash

set -euo pipefail

echo "date $(date '+%Y-%m-%d %H:%M:%S')"
echo "hostname $(hostname)"
echo "SECONDS ${SECONDS}"

source "${HOME}/.env" || true

cd "$(dirname "$0")"
echo "PWD ${PWD}"
cd "$(git rev-parse --show-toplevel)"
echo "PWD ${PWD}"

echo "git rev-parse HEAD $(git rev-parse HEAD)"

###############################################################################
echo "setup work environment -------------------------------------------------"
echo "SECONDS ${SECONDS}"
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

rsync -a "${PWD}/" "${WORKDIR}/source/"

###############################################################################
echo "setup compile ----------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
export CSLC="${CSLC:-cslc}"
echo "CSLC ${CSLC}"

export ASYNC_GA_ARCH_FLAG="wse3"
echo "ASYNC_GA_ARCH_FLAG ${ASYNC_GA_ARCH_FLAG}"

WORKDIR_MNT="$(realpath path)"
WORKDIR_MNT="${WORKDIR_MNT#/}"
WORKDIR_MNT="${WORKDIR_MNT%%/*}"
echo "WORKDIR_MNT ${WORKDIR_MNT}"
export SINGULARITY_BIND="${SINGULARITY_BIND:+${SINGULARITY_BIND},}/${WORKDIR_MNT}:/${WORKDIR_MNT},/tmp:/tmp"
echo "SINGULARITY_BIND ${SINGULARITY_BIND}"

# export ASYNC_GA_FABRIC_DIMS="757,996"  # TODO these are PSC WSE2 fabric dims
# echo "ASYNC_GA_FABRIC_DIMS ${ASYNC_GA_FABRIC_DIMS}"

###############################################################################
echo "do compile -------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
"${WORKDIR}/source/kernel-async-ga/compile.sh" | tee "${WORKDIR}/compile.log"

###############################################################################
echo "setup run -------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
mkdir -p "${WORKDIR}/out"
mkdir -p "${WORKDIR}/run"
cd "${WORKDIR}/run"
echo "PWD ${PWD}"

cp -rL "${WORKDIR}/source/kernel-async-ga/cerebraslib" .
cp -rL "${WORKDIR}/source/kernel-async-ga/out" .
cp -L "${WORKDIR}/source/kernel-async-ga/client.py" .
cp -L "${WORKDIR}/source/kernel-async-ga/compconf.json" .
ls

cd "${WORKDIR}"
echo "PWD ${PWD}"
find "./run" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"

python3 - << EOF
import logging
import os

from cerebras.appliance import logger
from cerebras.sdk.client import SdkLauncher


logging.basicConfig(
    datefmt="%Y-%m-%d %H:%M:%S",
    format="%(asctime)s %(levelname)-8s %(message)s",
    level=logging.INFO,
)

logging.info("entering SdkLauncher")
with SdkLauncher(
    "./run", disable_version_check=True, simulator=True
) as launcher:

    logging.info("querying context info...")
    response = launcher.run(
        "env",
        "pwd",
        "ls",
        r'find . | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"',
    )
    logging.info("... done!")
    logging.info(response + "\n")

    env_prefix = " ".join(
        f"{key}='{value}'"
        for key, value in os.environ.items()
        if key.startswith("ASYNC_GA_") or key.startswith("COMPCONFENV_")
    )
    command = f"{env_prefix} cs_python client.py | tee run.log"
    logging.info(f"command={command}")
    logging.info("running command...")
    response = launcher.run(command)
    logging.info("... done!")
    logging.info(response + "\n")

    logging.info("finding output files...")
    response = launcher.run(
        "find . -maxdepth 1 -type f "
        r'\( -name "*.log" -o -name "*.pqt" -o -name "*.json" \)',
    )
    logging.info("... done!")
    logging.info(response + "\n")

    for filename in response.splitlines():
        target = f"${WORKDIR}/out/{filename}"
        logging.info(f"retrieving file {filename} to {target}...")
        file_contents = launcher.download_artifact(filename, target)
        logging.info("... done!")

    logging.info("exiting SdkLauncher")

logging.info("exited SdkLauncher")
EOF

find "${WORKDIR}/out" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${WORKDIR}"/out/*

###############################################################################
echo "done! ------------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
