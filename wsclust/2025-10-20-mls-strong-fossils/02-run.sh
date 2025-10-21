#!/usr/bin/env bash

set -euo pipefail

LOG_ALL="$(mktemp)"
LOG_ERR="$(mktemp)"
LOG_OUT="$(mktemp)"

# adapted from https://unix.stackexchange.com/a/61936/605206
exec > >(tee >(tee "${LOG_ALL}" >>"${LOG_OUT}")) \
     2> >(tee >(tee -a "${LOG_ALL}" >>"${LOG_ERR}") >&2)
on_exit() {
    echo
    echo "exit trap ----------------------------------------------------------"
    echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"

    LOGDIR="${HOME}/log/wse-async-ga/"
    echo "copying script and logs to LOGDIR ${LOGDIR}"
    mkdir -p "${LOGDIR}"

    cp "${FLOWDIR}/$(basename "$0")" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=script+ext=.sh" || :
    cp "${LOG_ALL}" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=stdall+ext=.log" || :
    cp "${LOG_ERR}" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=stderr+ext=.log" || :
    cp "${LOG_OUT}" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=stdout+ext=.log" || :

    echo "copying script and logs to RESULTDIR_STEP ${RESULTDIR_STEP}"
    cp "${FLOWDIR}/$(basename "$0")" "${RESULTDIR_STEP}/" || :
    cp "${LOG_ALL}" "${RESULTDIR_STEP}/stdall.log" || :
    cp "${LOG_ERR}" "${RESULTDIR_STEP}/stderr.log" || :
    cp "${LOG_OUT}" "${RESULTDIR_STEP}/stdout.log" || :
}
trap on_exit EXIT

FLOWDIR="$(realpath "$(dirname "$0")")"
FLOWNAME="$(basename "${FLOWDIR}")"
STEPNAME="$(basename "$0" .sh)"
WORKDIR="${FLOWDIR}/workdir"
RESULTDIR="${FLOWDIR}/resultdir"

###############################################################################
echo
echo
echo "============================================= ${FLOWNAME} :: ${STEPNAME}"
###############################################################################
source "${HOME}/.env" || true

###############################################################################
echo
echo "log context ------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
echo "date $(date '+%Y-%m-%d %H:%M:%S')"
echo "hostname $(hostname)"
echo "SECONDS ${SECONDS}"

echo "STEPNAME ${STEPNAME}"
echo "FLOWDIR ${FLOWDIR}"
echo "FLOWNAME ${FLOWNAME}"
echo "WORKDIR ${WORKDIR}"
echo "RESULTDIR ${RESULTDIR}"

echo "LOG_ERR ${LOG_ERR}"
echo "LOG_OUT ${LOG_OUT}"
echo "LOG_ALL ${LOG_ALL}"

###############################################################################
echo
echo "make step work dir -----------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
WORKDIR_STEP="${WORKDIR}/${STEPNAME}"
echo "WORKDIR_STEP ${WORKDIR_STEP}"
if [ -d "${WORKDIR_STEP}" ]; then
    echo "Clearing WORKDIR_STEP ${WORKDIR_STEP}"
    rm -rf "${WORKDIR_STEP}"
fi
mkdir -p "${WORKDIR_STEP}"

###############################################################################
echo
echo "make step result dir ---------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
RESULTDIR_STEP="${RESULTDIR}/${STEPNAME}"
echo "RESULTDIR_STEP ${RESULTDIR_STEP}"
if [ -d "${RESULTDIR_STEP}" ]; then
    echo "Clearing RESULTDIR_STEP ${RESULTDIR_STEP}"
    rm -rf "${RESULTDIR_STEP}"
fi
mkdir -p "${RESULTDIR_STEP}"

###############################################################################
echo
echo "setup venv  ------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
VENVDIR="${WORKDIR}/venv"
echo "VENVDIR ${VENVDIR}"

echo "creating venv"
source "${VENVDIR}/bin/activate"
python3 -m uv pip freeze | tee "${RESULTDIR_STEP}/pip-freeze.txt"
python3 -m pylib_cs.cslc_wsclust_shim  # test install

###############################################################################
echo
echo "log source -------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
echo "log revision"
git -C "${FLOWDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/git-revision.txt"
echo "log remote"
git -C "${FLOWDIR}" remote -v > "${RESULTDIR_STEP}/git-remote.txt"
echo "log status"
git -C "$(git -C "${FLOWDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/git-status.txt"
echo "log diff"
git -C "${FLOWDIR}" --no-pager diff > "${RESULTDIR_STEP}/git-status.diff" || :
git -C "${FLOWDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${FLOWDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/git-status.diff" || :

SRCDIR="${WORKDIR}/src"
echo "SRCDIR ${SRCDIR}"
echo "log revision"
git -C "${SRCDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/src-revision.txt"
echo "log remote"
git -C "${SRCDIR}" remote -v > "${RESULTDIR_STEP}/src-remote.txt"
echo "log status"
git -C "$(git -C "${SRCDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/src-status.txt"
echo "log diff"
git -C "${SRCDIR}" --no-pager diff > "${RESULTDIR_STEP}/src-status.diff" || :
git -C "${SRCDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${SRCDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/src-status.diff" || :

###############################################################################
echo
echo "setup run --------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
source "${WORKDIR}/01-compile/env.sh"

export ASYNC_GA_MAX_FOSSIL_SETS_SPREAD=16
echo "ASYNC_GA_MAX_FOSSIL_SETS_SPREAD=${ASYNC_GA_MAX_FOSSIL_SETS_SPREAD}"

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
echo
echo "do run -----------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
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
    command = f"{env_prefix} cs_python client.py --cmaddr %CMADDR% 2>&1 | tee run.log"
    logging.info(f"command={command}")
    logging.info("running command...")
    response = launcher.run(command)
    logging.info("... done!")
    logging.info(response + "\n")

    logging.info("finding output files...")
    response = launcher.run(
        "find . -maxdepth 1 -type f "
        r'\( -name "*.log" -o -name "*.pqt" -o -name "*.json" -o -name "*.npy" \)',
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
echo
echo "closeout ---------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
find "${WORKDIR_STEP}/out" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${WORKDIR_STEP}"/out/*

cp "${WORKDIR_STEP}"/out/* "${RESULTDIR_STEP}"

find "${RESULTDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${RESULTDIR_STEP}"/*

env > "${RESULTDIR_STEP}/env.txt"

###############################################################################
echo "done! ------------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
