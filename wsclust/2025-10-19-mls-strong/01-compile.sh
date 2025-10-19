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
echo "setup compile ----------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
export CSLC="${CSLC:-cslc}"
echo "CSLC ${CSLC}"
export ASYNC_GA_FABRIC_DIMS="762,1172"
echo "ASYNC_GA_FABRIC_DIMS ${ASYNC_GA_FABRIC_DIMS}"

WORKDIR_MNT="$(realpath path)"
WORKDIR_MNT="${WORKDIR_MNT#/}"
WORKDIR_MNT="${WORKDIR_MNT%%/*}"
echo "WORKDIR_MNT ${WORKDIR_MNT}"
export SINGULARITY_BIND="${SINGULARITY_BIND:+${SINGULARITY_BIND},}/${WORKDIR_MNT}:/${WORKDIR_MNT},/tmp:/tmp"
echo "SINGULARITY_BIND ${SINGULARITY_BIND}"

###############################################################################
echo "config compile ---------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
cat > "${WORKDIR_STEP}/env.sh" << 'EOF'
#!/usr/bin/env bash

export ASYNC_GA_ARCH_FLAG="wse3"
export ASYNC_GA_GENOME_FLAVOR="genome_mls_2025_08_15"
export ASYNC_GA_FABRIC_DIMS="762,1172"
export ASYNC_GA_NWAV=7
export ASYNC_GA_NCOL=755
export ASYNC_GA_NCOL_SUBGRID=0
export ASYNC_GA_NONBLOCK=0
export ASYNC_GA_NROW=1170
export ASYNC_GA_NROW_SUBGRID=0
export ASYNC_GA_NTRAIT=3
export ASYNC_GA_MSEC_AT_LEAST=0
export ASYNC_GA_NCYCLE_AT_LEAST=100000
export ASYNC_GA_POPSIZE=404
export ASYNC_GA_TOURNSIZE_NUMERATOR=2
export ASYNC_GA_TOURNSIZE_DENOMINATOR=1
export ASYNC_GA_GLOBAL_SEED=1
export COMPCONFENV_CEREBRASLIB_CLOBBER_IMMIGRANT_P__f32="1.0"
export COMPCONFENV_CEREBRASLIB_NONZERO_FIT_FUDGE__f32="4.0"
export COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32="0.01"
export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string="hybrid_0_steady_1_stretched_2_algo"

echo "ASYNC_GA_ARCH_FLAG ${ASYNC_GA_ARCH_FLAG}"
echo "ASYNC_GA_GENOME_FLAVOR ${ASYNC_GA_GENOME_FLAVOR}"
echo "ASYNC_GA_FABRIC_DIMS ${ASYNC_GA_FABRIC_DIMS}"
echo "ASYNC_GA_NWAV ${ASYNC_GA_NWAV}"
echo "ASYNC_GA_NCOL ${ASYNC_GA_NCOL}"
echo "ASYNC_GA_NCOL_SUBGRID ${ASYNC_GA_NCOL_SUBGRID}"
echo "ASYNC_GA_NONBLOCK ${ASYNC_GA_NONBLOCK}"
echo "ASYNC_GA_NROW ${ASYNC_GA_NROW}"
echo "ASYNC_GA_NROW_SUBGRID ${ASYNC_GA_NROW_SUBGRID}"
echo "ASYNC_GA_NTRAIT ${ASYNC_GA_NTRAIT}"
echo "ASYNC_GA_MSEC_AT_LEAST ${ASYNC_GA_MSEC_AT_LEAST}"
echo "ASYNC_GA_NCYCLE_AT_LEAST ${ASYNC_GA_NCYCLE_AT_LEAST}"
echo "ASYNC_GA_POPSIZE ${ASYNC_GA_POPSIZE}"
echo "ASYNC_GA_TOURNSIZE_NUMERATOR ${ASYNC_GA_TOURNSIZE_NUMERATOR}"
echo "ASYNC_GA_TOURNSIZE_DENOMINATOR ${ASYNC_GA_TOURNSIZE_DENOMINATOR}"
echo "ASYNC_GA_GLOBAL_SEED ${ASYNC_GA_GLOBAL_SEED}"
echo "ASYNC_GA_ARCH_FLAG ${ASYNC_GA_ARCH_FLAG}"
echo "COMPCONFENV_CEREBRASLIB_CLOBBER_IMMIGRANT_P__f32 ${COMPCONFENV_CEREBRASLIB_CLOBBER_IMMIGRANT_P__f32}"
echo "COMPCONFENV_CEREBRASLIB_NONZERO_FIT_FUDGE__f32 ${COMPCONFENV_CEREBRASLIB_NONZERO_FIT_FUDGE__f32}"
echo "COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32 ${COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32}"
echo "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string ${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string}"
EOF

chmod +x "${WORKDIR_STEP}/env.sh"
cp "${WORKDIR_STEP}/env.sh" "${RESULTDIR_STEP}/env.sh"
source "${WORKDIR_STEP}/env.sh"

###############################################################################
echo "do compile -------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
"${WORKDIR}/src/kernel-async-ga/compile.sh" | tee "${RESULTDIR_STEP}/compile.log"

###############################################################################
echo "closeout ---------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
find "${RESULTDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${RESULTDIR_STEP}"/*

env > "${RESULTDIR_STEP}/env.txt"

###############################################################################
echo "done! ------------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
