#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

echo "begin compile.sh --------------------------------------------------------"
echo "which python3 $(which python3)"

echo "CSLC ${CSLC}"

WSE_GOL_GLOBAL_SEED="${WSE_GOL_GLOBAL_SEED:-0}"
echo "WSE_GOL_GLOBAL_SEED ${WSE_GOL_GLOBAL_SEED}"

WSE_GOL_FABRIC_DIMS="${WSE_GOL_FABRIC_DIMS:-11,6}"
echo "WSE_GOL_FABRIC_DIMS ${WSE_GOL_FABRIC_DIMS}"

WSE_GOL_NROW="${WSE_GOL_NROW:-4}"
echo "WSE_GOL_NROW ${WSE_GOL_NROW}"

WSE_GOL_NCOL="${WSE_GOL_NCOL:-4}"
echo "WSE_GOL_NCOL ${WSE_GOL_NCOL}"

WSE_GOL_ARCH_FLAG="${WSE_GOL_ARCH_FLAG:-wse3}"
echo "WSE_GOL_ARCH_FLAG ${WSE_GOL_ARCH_FLAG}"

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

python3 -m compconf --compconf-verbose --compconf-cslc "${CSLC}" layout.csl --arch=${WSE_GOL_ARCH_FLAG} --import-path ./downstream/include --fabric-dims=${WSE_GOL_FABRIC_DIMS} --fabric-offsets=4,1 --channels=1 --memcpy --params=globalSeed:${WSE_GOL_GLOBAL_SEED},nRow:${WSE_GOL_NROW},nCol:${WSE_GOL_NCOL} -o out
