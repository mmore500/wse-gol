#!//bin/bash

set -euo pipefail

echo "date $(date '+%Y-%m-%d %H:%M:%S')"
echo "hostname $(hostname)"
echo "SECONDS ${SECONDS}"

source "${HOME}/.env" || true

cd "$(dirname "$0")"
echo "PWD ${PWD}"

echo "git rev-parse HEAD $(git rev-parse HEAD)"

FLOWDIR="$(realpath "$(dirname "$0")")"
FLOWNAME="$(basename "${FLOWDIR}")"
STEPNAME="$(basename "$0" .sh)"
WORKDIR="${FLOWPATH}/workdir"
RESULTDIR="${FLOWPATH}/resultdir"

echo "STEPNAME ${STEPNAME}"
echo "FLOWDIR ${FLOWDIR}"
echo "FLOWNAME ${FLOWNAME}"
echo "WORKDIR ${WORKDIR}"
echo "RESULTDIR ${RESULTDIR}"

###############################################################################
echo "make step work dir -----------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
WORKDIR_STEP="${WORKDIR}/${STEPNAME}"
echo "WORKDIR_STEP ${WORKDIR_STEP}"
if [ -d "${WORKDIR_STEP}" ]; then
    echo "Clearing WORKDIR_STEP ${WORKDIR_STEP}"
    rm -rf "${WORKDIR_STEP}"
fi
mkdir -p "${WORKDIR_STEP}"

###############################################################################
echo "make step result dir ---------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
RESULTDIR_STEP="${RESULTDIR}/${STEPNAME}"
echo "RESULTDIR_STEP ${RESULTDIR_STEP}"
if [ -d "${RESULTDIR_STEP}" ]; then
    echo "Clearing RESULTDIR_STEP ${RESULTDIR_STEP}"
    rm -rf "${RESULTDIR_STEP}"
fi
mkdir -p "${RESULTDIR_STEP}"

###############################################################################
echo "setup venv  ------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
VENVDIR="${WORKDIR}/venv"
echo "VENVDIR ${VENVDIR}"

echo "creating venv"
source "${VENVDIR}/bin/activate"
python3 -m uv pip freeze | tee "${RESULTDIR_STEP}/pip-freeze.txt"
python3 -m pylib_cs.cslc_wsclust_shim  # test install

###############################################################################
echo "log source -------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
git -C "${FLOWDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/git-revision.txt"
git -C "$(git -C "${FLOWDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/git-status.txt"
git -C "${FLOWDIR}" --no-pager diff > "${RESULTDIR_STEP}/git-status.diff"
git -C "${FLOWDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${FLOWDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/git-status.diff"

SRCDIR="${WORKDIR}/src"
echo "SRCDIR ${SRCDIR}"
git -C "${SRCDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/src-revision.txt"
git -C "$(git -C "${SRCDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/src-status.txt"
git -C "${SRCDIR}" --no-pager diff > "${RESULTDIR_STEP}/src-status.diff"
git -C "${SRCDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${SRCDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/src-status.diff"

###############################################################################
echo "setup run --------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
source "${WORKDIR}/01-compile/env.sh"

mkdir -p "${WORKDIR_STEP}/out"
mkdir -p "${WORKDIR_STEP}/run"

cd "${WORKDIR_STEP}/run"
echo "PWD ${PWD}"
cp -rL "${WORKDIR}/src/kernel-async-ga/cerebraslib" .
cp -rL "${WORKDIR}/src/kernel-async-ga/out" .
cp -L "${WORKDIR}/src/kernel-async-ga/client.py" .
cp -L "${WORKDIR}/src/kernel-async-ga/compconf.json" .
ls

cd "${WORKDIR_STEP}"
echo "PWD ${PWD}"
find "./run" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"

###############################################################################
echo "do run -----------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
cd "${WORKDIR_STEP}"
echo "PWD ${PWD}"

which python3
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
with SdkLauncher("./run", disable_version_check=True) as launcher:

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
    command = f"{env_prefix} cs_python client.py --cmaddr %CMADDR% | tee run.log"
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
        target = f"${WORKDIR_STEP}/out/{filename}"
        logging.info(f"retrieving file {filename} to {target}...")
        file_contents = launcher.download_artifact(filename, target)
        logging.info("... done!")

    logging.info("exiting SdkLauncher")

logging.info("exited SdkLauncher")
EOF

###############################################################################
echo "handle output ----------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
find "${WORKDIR_STEP}/out" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${WORKDIR_STEP}"/out/*

cp "${WORKDIR_STEP}"/out/* "${RESULTDIR_STEP}"

find "${RESULTDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${RESULTDIR_STEP}"/*

###############################################################################
echo "done! ------------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
