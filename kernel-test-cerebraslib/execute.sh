#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

echo "CS_PYTHON ${CS_PYTHON}"

# Find directories that match the pattern 'out*'
dir_list=$(find . -maxdepth 1 -type d -name 'out*')

# Check if the directory list is empty
if [ -z "$dir_list" ]; then
    echo "No tests found, did you run ./compile.sh?"
    exit 0
fi

# Count the number of directories to process
num_dirs=$(echo "$dir_list" | wc -l)
echo "${num_dirs} directories detected"

echo "Running ${num_dirs} tests with up to ${MAX_PROCESSES} parallel processes"

# set if not set to 0
export APPTAINERENV_CSL_SUPPRESS_SIMFAB_TRACE=${APPTAINERENV_CSL_SUPPRESS_SIMFAB_TRACE:-1}
echo "APPTAINERENV_CSL_SUPPRESS_SIMFAB_TRACE ${APPTAINERENV_CSL_SUPPRESS_SIMFAB_TRACE}"

for dir in $dir_list; do
    # Run the client.py script in the background for the current directory
    "${CS_PYTHON}" client.py --name "${dir}"

    # Print the directory name to stdout for tqdm to track progress
    echo "${dir}"
done | python3 -m tqdm --total "${num_dirs}" --unit test --unit_scale --desc "running tests"

echo "All tests processed."
