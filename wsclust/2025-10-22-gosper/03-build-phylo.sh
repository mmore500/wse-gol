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

    LOGDIR="${HOME}/log/wse-gol/"
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
echo "build phylogeny --------------------------------------------------------"
echo ">>>>> ${FLOWNAME} :: ${STEPNAME} || ${SECONDS}"
###############################################################################
cd "${WORKDIR}/02-run/out"
export APPTAINERENV_POLARS_MAX_THREADS=32
export APPTAINERENV_NUMBA_NUM_THREADS=32
echo "APPTAINERENV_POLARS_MAX_THREADS=${APPTAINERENV_POLARS_MAX_THREADS}"
echo "APPTAINERENV_NUMBA_NUM_THREADS=${APPTAINERENV_NUMBA_NUM_THREADS}"

export SINGULARITYENV_POLARS_MAX_THREADS="${APPTAINERENV_POLARS_MAX_THREADS}"
export SINGULARITYENV_NUMBA_NUM_THREADS="${APPTAINERENV_NUMBA_NUM_THREADS}"
echo "SINGULARITYENV_POLARS_MAX_THREADS=${SINGULARITYENV_POLARS_MAX_THREADS}"
echo "SINGULARITYENV_NUMBA_NUM_THREADS=${SINGULARITYENV_NUMBA_NUM_THREADS}"

for i in 0 1 2; do
    f="a=surfaces+i=${i}+ext=.pqt"
    echo "processing set ${i}, filename ${f}..."
    ls -1 "${f}" \
    | singularity exec docker://ghcr.io/mmore500/hstrat:v1.20.14 \
    python3 -m hstrat.dataframe.surface_build_tree \
        "${WORKDIR_STEP}/a=phylogeny+i=${i}+ext=.pqt" \
        --trie-postprocessor \
            'hstrat.AssignOriginTimeNodeRankTriePostprocessor()' \
        --exploded-slice-size 100000 \
        --filter '~pl.col("data_hex").str.contains(r"^0+$")' \
        --eager-read --eager-write --string-cache \
        --with-column 'pl.lit(filepath).cast(pl.Categorical).alias("file")' \
        --with-column 'pl.when(pl.col("dstream_algo").str.starts_with("dstream.")).then(pl.col("dstream_algo")).otherwise(pl.concat_str(pl.lit("dstream."), pl.col("dstream_algo"))).alias("dstream_algo")' \
        | tee "${RESULTDIR_STEP}/surface_build_tree${i}.log"
done

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
