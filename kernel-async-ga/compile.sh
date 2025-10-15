#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

echo "begin compile.sh --------------------------------------------------------"

echo "CSLC ${CSLC}"

ASYNC_GA_GENOME_FLAVOR="${ASYNC_GA_GENOME_FLAVOR:-genome_bitdrift}"
echo "ASYNC_GA_GENOME_FLAVOR ${ASYNC_GA_GENOME_FLAVOR}"

ASYNC_GA_GLOBAL_SEED="${ASYNC_GA_GLOBAL_SEED:-0}"
echo "ASYNC_GA_GLOBAL_SEED ${ASYNC_GA_GLOBAL_SEED}"

ASYNC_GA_NCYCLE_AT_LEAST="${ASYNC_GA_NCYCLE_AT_LEAST:-40}"
echo "ASYNC_GA_NCYCLE_AT_LEAST ${ASYNC_GA_NCYCLE_AT_LEAST}"

ASYNC_GA_MSEC_AT_LEAST="${ASYNC_GA_MSEC_AT_LEAST:-0}"
echo "ASYNC_GA_MSEC_AT_LEAST ${ASYNC_GA_MSEC_AT_LEAST}"

ASYNC_GA_TSC_AT_LEAST="${ASYNC_GA_TSC_AT_LEAST:-0}"
echo "ASYNC_GA_TSC_AT_LEAST ${ASYNC_GA_TSC_AT_LEAST}"

ASYNC_GA_FABRIC_DIMS="${ASYNC_GA_FABRIC_DIMS:-10,5}"
echo "ASYNC_GA_FABRIC_DIMS ${ASYNC_GA_FABRIC_DIMS}"

ASYNC_GA_NROW="${ASYNC_GA_NROW:-3}"
echo "ASYNC_GA_NROW ${ASYNC_GA_NROW}"

ASYNC_GA_NCOL="${ASYNC_GA_NCOL:-3}"
echo "ASYNC_GA_NCOL ${ASYNC_GA_NCOL}"

ASYNC_GA_NROW_SUBGRID="${ASYNC_GA_NROW_SUBGRID:-0}"
echo "ASYNC_GA_NROW_SUBGRID ${ASYNC_GA_NROW_SUBGRID}"

ASYNC_GA_NCOL_SUBGRID="${ASYNC_GA_NCOL_SUBGRID:-0}"
echo "ASYNC_GA_NCOL_SUBGRID ${ASYNC_GA_NCOL_SUBGRID}"

ASYNC_GA_NONBLOCK="${ASYNC_GA_NONBLOCK:-0}"
echo "ASYNC_GA_NONBLOCK ${ASYNC_GA_NONBLOCK}"

ASYNC_GA_POPSIZE="${ASYNC_GA_POPSIZE:-32}"
echo "ASYNC_GA_POPSIZE ${ASYNC_GA_POPSIZE}"

ASYNC_GA_TOURNSIZE_NUMERATOR="${ASYNC_GA_TOURNSIZE_NUMERATOR:-5}"
echo "ASYNC_GA_TOURNSIZE_NUMERATOR ${ASYNC_GA_TOURNSIZE_NUMERATOR}"

ASYNC_GA_TOURNSIZE_DENOMINATOR="${ASYNC_GA_TOURNSIZE_DENOMINATOR:-1}"
echo "ASYNC_GA_TOURNSIZE_DENOMINATOR ${ASYNC_GA_TOURNSIZE_DENOMINATOR}"

ASYNC_GA_ARCH_FLAG="${ASYNC_GA_ARCH_FLAG:-wse2}"
echo "ASYNC_GA_ARCH_FLAG ${ASYNC_GA_ARCH_FLAG}"

export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_NUM_BITS__u32="${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_NUM_BITS__u32:-256}"
echo "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_NUM_BITS__u32 ${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_NUM_BITS__u32}"

export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DILATION__u32="${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DILATION__u32:-8}"
echo "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DILATION__u32 ${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DILATION__u32}"

export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string="${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string:-steady_algo}"
echo "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string ${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string}"


pushd ..
git submodule update --init --recursive || :
popd

# symlinks don't work and --import-path doesn't work, so this is a workaround
trap "git checkout ./cerebraslib" EXIT
rsync -rI "$(readlink -f cerebraslib)" .

# target a 2x2 region of interest
# Every program using memcpy must use a fabric offset of 4,1, and if compiling
# for a simulated fabric, must use a fabric dimension of at least
# width+7,height+1, where width and height are the dimensions of the program.
# These additional PEs are used by memcpy to route data on and off the wafer.
# see https://sdk.cerebras.net/csl/tutorials/gemv-01-complete-program/
# 9x4 because compiler says
# RuntimeError: Fabric dimension must be at least 9-by-4

python3 -m compconf --compconf-jq ". += {\"ASYNC_GA_GENOME_FLAVOR:comptime_string\": \"${ASYNC_GA_GENOME_FLAVOR}\"}" --compconf-verbose --compconf-cslc "${CSLC}" layout.csl --arch=${ASYNC_GA_ARCH_FLAG} --import-path ./downstream/include --fabric-dims=${ASYNC_GA_FABRIC_DIMS} --fabric-offsets=4,1 --channels=1 --memcpy --params=globalSeed:${ASYNC_GA_GLOBAL_SEED},nCycleAtLeast:${ASYNC_GA_NCYCLE_AT_LEAST},msecAtLeast:${ASYNC_GA_MSEC_AT_LEAST},tscAtLeast:${ASYNC_GA_TSC_AT_LEAST},nRow:${ASYNC_GA_NROW},nCol:${ASYNC_GA_NCOL},nRowSubgrid:${ASYNC_GA_NROW_SUBGRID},nColSubgrid:${ASYNC_GA_NCOL_SUBGRID},nonBlock:${ASYNC_GA_NONBLOCK},popSize:${ASYNC_GA_POPSIZE},tournSizeNumerator:${ASYNC_GA_TOURNSIZE_NUMERATOR},tournSizeDenominator:${ASYNC_GA_TOURNSIZE_DENOMINATOR} -o out
