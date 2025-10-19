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
WORKDIR="${FLOWDIR}/workdir"
RESULTDIR="${FLOWDIR}/resultdir"

echo "STEPNAME ${STEPNAME}"
echo "FLOWDIR ${FLOWDIR}"
echo "FLOWNAME ${FLOWNAME}"
echo "WORKDIR ${WORKDIR}"
echo "RESULTDIR ${RESULTDIR}"

###############################################################################
echo "make and link flow work dir --------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
WORKDIR_PATH="${TMPDIR:-/tmp}/wse-async-ga/${FLOWNAME}"
echo "WORKDIR_PATH ${WORKDIR_PATH}"
if [ -d "${WORKDIR_PATH}" ]; then
    echo "Clearing WORKDIR_PATH ${WORKDIR_PATH}"
    rm -rf "${WORKDIR_PATH}"
fi
mkdir -p "${WORKDIR_PATH}"
ln -sf "${WORKDIR_PATH}" "${WORKDIR}"

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
echo "make and link result dir -----------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
RESULTDIR_PATH="${HOME}/scratch/wse-async-ga/${FLOWNAME}"
echo "RESULTDIR_PATH ${RESULTDIR_PATH}"
if [ -d "${RESULTDIR_PATH}" ]; then
    echo "Clearing RESULTDIR_PATH ${RESULTDIR_PATH}"
    rm -rf "${RESULTDIR_PATH}"
fi
mkdir -p "${RESULTDIR_PATH}"
ln -sf "${RESULTDIR_PATH}" "${RESULTDIR}"

mkdir -p "${RESULTDIR}/${FLOWNAME}  "

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
echo "log and setup source ---------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
git -C "${FLOWDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/git-revision.txt"
git -C "$(git -C "${FLOWDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/git-status.txt"
git -C "${FLOWDIR}" --no-pager diff > "${RESULTDIR_STEP}/git-status.diff"
git -C "${FLOWDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${FLOWDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/git-status.diff"

SRCDIR="${WORKDIR}/src"
echo "SRCDIR ${SRCDIR}"
rm -rf "${SRCDIR}"
rsync -a "$(git rev-parse --show-toplevel)" "${SRCDIR}"

git -C "${SRCDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/src-revision.txt"
git -C "$(git -C "${SRCDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/src-status.txt"
git -C "${SRCDIR}" --no-pager diff > "${RESULTDIR_STEP}/src-status.diff"
git -C "${SRCDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${SRCDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/src-status.diff"

###############################################################################
echo "setup venv  ------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
VENVDIR="${WORKDIR}/venv"
echo "VENVDIR ${VENVDIR}"

echo "creating venv"
rm -rf "${VENVDIR}"
python3.8 -m venv "${VENVDIR}"
source "${VENVDIR}/bin/activate"
which python3

echo "setting up venv"
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade uv
python3 -m uv pip install -r "${SRCDIR}/requirements_cs.txt"
python3 -m uv pip install ./pylib_cs
python3 -m uv pip freeze | tee "${RESULTDIR_STEP}/pip-freeze.txt"
python3 -m pylib_cs.cslc_wsclust_shim  # test install

###############################################################################
echo "done! ------------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
