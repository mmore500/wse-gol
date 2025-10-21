#!/bin/bash

set -euo pipefail

shopt -s globstar

cd "$(dirname "$0")"

echo "CSLC ${CSLC}"

git submodule update --init --recursive

# symlinks don't work and --import-path doesn't work, so this is a workaround
trap "git checkout ./cerebraslib ./downstream" EXIT
rsync -rI "$(readlink -f cerebraslib)" .
rsync -rI "$(readlink -f downstream)" .

# remove any old output
rm -rf out*

# target a 1x1 region of interest
# Every program using memcpy must use a fabric offset of 4,1, and if compiling
# for a simulated fabric, must use a fabric dimension of at least
# width+7,height+1, where width and height are the dimensions of the program.
# These additional PEs are used by memcpy to route data on and off the wafer.
# see https://sdk.cerebras.net/csl/tutorials/gemv-01-complete-program/
# 9x4 because compiler says
# RuntimeError: Fabric dimension must be at least 9-by-4
if [ "$#" -ge 1 ]; then  # use user argument if provided
    test_module_paths="$@"
else
    test_module_paths="$(ls test_cerebraslib/**/test_*.csl)"
fi
num_tests="$(echo "${test_module_paths}" | wc -l)"
echo "${num_tests} tests detected"

echo "Compiling ${num_tests} tests"

export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_NUM_BITS__u32="256"
export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string="steady_algo"

WSE_GOL_ARCH_FLAG="${WSE_GOL_ARCH_FLAG:-wse2}"
echo "WSE_GOL_ARCH_FLAG ${WSE_GOL_ARCH_FLAG}"

for test_module_path in ${test_module_paths}; do
    cp "${test_module_path}" "cerebraslib/current_compilation_target.csl"
    test_basename="$(basename -- "${test_module_path}")"
    test_name="${test_basename%.csl}"
    python3 -m compconf --compconf-cslc "${CSLC}" layout.csl --import-path ./downstream/include --arch=${WSE_GOL_ARCH_FLAG} --fabric-dims=9,4 --fabric-offsets=4,1 --channels=1 --memcpy -o "out_${test_name}" --verbose >/dev/null 2>&1
    echo "${test_module_path}"
done | python3 -m tqdm --total "${num_tests}" --unit test --unit_scale --desc "Compiling"
