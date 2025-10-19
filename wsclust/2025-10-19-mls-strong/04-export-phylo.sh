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

    cp "$0" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=script+ext=.sh" || :
    cp "${LOG_ALL}" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=stdall+ext=.log" || :
    cp "${LOG_ERR}" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=stderr+ext=.log" || :
    cp "${LOG_OUT}" \
        "${LOGDIR}/flow=${FLOWNAME}+step=${STEPNAME}+what=stdout+ext=.log" || :

    echo "copying script and logs to RESULTDIR_STEP ${RESULTDIR_STEP}"
    cp "$0" "${RESULTDIR_STEP}/" || :
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
git -C "${FLOWDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/git-revision.txt"
git -C "${FLOWDIR}" remote -v > "${RESULTDIR_STEP}/git-remote.txt"
git -C "$(git -C "${FLOWDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/git-status.txt"
git -C "${FLOWDIR}" --no-pager diff > "${RESULTDIR_STEP}/git-status.diff"
git -C "${FLOWDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${FLOWDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/git-status.diff"

SRCDIR="${WORKDIR}/src"
echo "SRCDIR ${SRCDIR}"
git -C "${SRCDIR}" rev-parse HEAD > "${RESULTDIR_STEP}/src-revision.txt"
git -C "${SRCDIR}" remote -v > "${RESULTDIR_STEP}/git-remote.txt"
git -C "$(git -C "${SRCDIR}" rev-parse --show-toplevel)" status \
    > "${RESULTDIR_STEP}/src-status.txt"
git -C "${SRCDIR}" --no-pager diff > "${RESULTDIR_STEP}/src-status.diff"
git -C "${SRCDIR}" ls-files -z --others --exclude-standard | xargs -0 -I {} git -C "${SRCDIR}" --no-pager diff --no-index /dev/null {} >> "${RESULTDIR_STEP}/src-status.diff"

###############################################################################
echo
echo "export phylogeny -------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
singularity exec docker://ghcr.io/mmore500/hstrat:v1.20.13 \
    python3 -m hstrat._auxiliary_lib._alifestd_as_newick_asexual \
        -i "${WORKDIR}/03-build-phylo/a=phylogeny+ext=.pqt" \
        -o "${WORKDIR_STEP}/a=phylotree+ext=.nwk" \
        -l "id" \
        | tee "${RESULTDIR_STEP}/_alifestd_as_newick_asexual.log"

ls -1 "${WORKDIR}/03-build-phylo/a=phylogeny+ext=.pqt" \
    | singularity run docker://ghcr.io/mmore500/joinem:v0.11.0 \
        "${WORKDIR_STEP}/a=phylometa+ext=.csv" \
        --select "id" \
        --select "origin_time" \
        --select "focal_trait_count" \
        --select "nonfocal_trait_count" \
        --select "^byte\d+_bit\d+.*_trait$" \
        | tee "${RESULTDIR_STEP}/joinem.log"

gzip -k "${WORKDIR_STEP}/a=phylotree+ext=.nwk"
gzip -k "${WORKDIR_STEP}/a=phylometa+ext=.csv"

###############################################################################
echo
echo "downsample phylogeny ---------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
dsamp=4096
echo "dsamp ${dsamp}"

ls -1 ${WORKDIR}/03-build-phylo/a=phylogeny+ext=.pqt \
    | singularity exec docker://ghcr.io/mmore500/hstrat:v1.20.13 \
    python3 -m hstrat._auxiliary_lib._alifestd_downsample_tips_asexual \
        -n "${dsamp}" \
        "${WORKDIR_STEP}/a=phylotree+dsamp=${dsamp}+ext=.nwk" \
        | tee "${RESULTDIR_STEP}/_alifestd_downsample_tips_asexual${dsamp}.log"

singularity exec docker://ghcr.io/mmore500/hstrat:v1.20.13 \
    python3 -m hstrat._auxiliary_lib._alifestd_as_newick_asexual \
        -i "${WORKDIR_STEP}/a=phylogeny+dsamp=${dsamp}+ext=.pqt" \
        -o "${WORKDIR_STEP}/a=phylotree+dsamp=${dsamp}+ext=.nwk" \
        -l "id" \
        | tee "${RESULTDIR_STEP}/_alifestd_as_newick_asexual_dsamp${dsamp}.log"

ls -1 "${WORKDIR_STEP}/a=phylogeny+dsamp=${dsamp}+ext=.pqt" \
    | singularity run docker://ghcr.io/mmore500/joinem:v0.11.0 \
        "${WORKDIR_STEP}/a=phylometa+dsamp=${dsamp}+ext=.csv" \
        --select "id" \
        --select "origin_time" \
        --select "focal_trait_count" \
        --select "nonfocal_trait_count" \
        --select "^byte\d+_bit\d+.*_trait$" \
        | tee "${RESULTDIR_STEP}/joinem_dsamp${dsamp}.log"

gzip -k "${WORKDIR_STEP}/a=phylotree+dsamp=${dsamp}+ext=.nwk"
gzip -k "${WORKDIR_STEP}/a=phylometa+dsamp=${dsamp}+ext=.csv"

###############################################################################
echo
echo "closeout ---------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
find "${WORKDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${WORKDIR_STEP}"/*

cp "${WORKDIR_STEP}"/* "${RESULTDIR_STEP}"

find "${RESULTDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${RESULTDIR_STEP}"/*

env > "${RESULTDIR_STEP}/env.txt"

###############################################################################
echo
echo "done! ------------------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
