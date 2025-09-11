#!/bin/bash
#SBATCH --ntasks=1
#SBATCH --mem=64G
#SBATCH --time=4:00:00
#SBATCH --cpus-per-task=28
#SBATCH --output="/jet/home/%u/joblog/id=%j+ext=.txt"
#SBATCH --mail-user=mawni4ah2o@pomail.net
#SBATCH --mail-type=FAIL,TIME_LIMIT

set -e

cd "$(dirname "$0")"

echo "SLURM_ARRAY_TASK_ID ${SLURM_ARRAY_TASK_ID}"

WSE_ASYNC_GA_REVISION="a33f6e9f028df71d734706378f14d634f51251ee"
echo "WSE_ASYNC_GA_REVISION ${WSE_ASYNC_GA_REVISION}"

WORKDIR="${HOME}/scratch/2025-08-15/async-ga-mls-strong"
echo "WORKDIR ${WORKDIR}"

export CSLC="${CSLC:-cslc}"
echo "CSLC ${CSLC}"

echo "initialization telemetry ==============================================="
echo "which cslc $(which cslc)"
echo "SDK_INSTALL_LOCATION ${SDK_INSTALL_LOCATION:-}"
echo "SDK_INSTALL_PATH ${SDK_INSTALL_PATH:-}"
echo "hostname $(hostname)"

echo "setup TMPDIR ==========================================================="
export TMPDIR="${HOME}/scratch/tmp"
echo "TMPDIR ${TMPDIR}"
mkdir -p "${TMPDIR}"

export TMPDIR="$(readlink -f "${TMPDIR}")"
echo "TMPDIR ${TMPDIR}"

echo "setup WORKDIR =========================================================="
mkdir -p "${WORKDIR}"

echo "setup SOURCEDIR ========================================================"
SOURCEDIR="${TMPDIR}/${WSE_ASYNC_GA_REVISION}-${SLURM_JOB_ID}"
echo "SOURCEDIR ${SOURCEDIR}"
rm -rf "${SOURCEDIR}"
git clone https://github.com/mmore500/wse-async-ga.git "${SOURCEDIR}" --single-branch
cd "${SOURCEDIR}"
git checkout "${WSE_ASYNC_GA_REVISION}"
cd -

echo "setup virtual env ======================================================"
venv="$(mktemp -d)"
echo "venv ${venv}"
python3 -m venv "${venv}"
source "${venv}/bin/activate"
python3 -m pip install --upgrade pip wheel
python3 -m pip install "compconf==0.5.0"
python3 -m pip freeze

echo "begin work loop ========================================================"
seed=0
export ASYNC_GA_NCOL=750
echo "ASYNC_GA_NCOL ${ASYNC_GA_NCOL}"

export ASYNC_GA_NROW=994
echo "ASYNC_GA_NROW ${ASYNC_GA_NROW}"

for POPULATION_EXTINCTION_PROBABILITY in 0.01; do
for config in \
    "export ASYNC_GA_NCOL_SUBGRID=0 ASYNC_GA_NROW_SUBGRID=0 NREP=1" \
; do
eval "${config}"
echo "NUM_AVAIL_BEN_MUTS ${NUM_AVAIL_BEN_MUTS}"

echo "ASYNC_GA_NCOL ${ASYNC_GA_NCOL}"
echo "ASYNC_GA_NROW ${ASYNC_GA_NROW}"
echo "ASYNC_GA_NCOL_SUBGRID ${ASYNC_GA_NCOL_SUBGRID}"
echo "ASYNC_GA_NROW_SUBGRID ${ASYNC_GA_NROW_SUBGRID}"

echo "NREP ${NREP}"
for rep in $(seq 1 ${NREP}); do
echo "rep ${rep}"
seed=$((seed+1))
echo "seed ${seed}"

SLUG="wse-async-ga+subgrid=${ASYNC_GA_NCOL_SUBGRID}+pop-extinct-prob=${POPULATION_EXTINCTION_PROBABILITY}+seed=${seed}"
echo "SLUG ${SLUG}"

echo "configure kernel compile ==============================================="
rm -rf "${WORKDIR:?}/${SLUG:?}"
cp -r "${SOURCEDIR}" "${WORKDIR}/${SLUG}"
cd "${WORKDIR}/${SLUG}"
git status

export ASYNC_GA_FABRIC_DIMS="757,996"
echo "ASYNC_GA_FABRIC_DIMS ${ASYNC_GA_FABRIC_DIMS}"

export ASYNC_GA_ARCH_FLAG="--arch=wse2"
echo "ASYNC_GA_ARCH_FLAG ${ASYNC_GA_ARCH_FLAG}"

export ASYNC_GA_GENOME_FLAVOR="genome_mls_2025_08_15"
echo "ASYNC_GA_GENOME_FLAVOR ${ASYNC_GA_GENOME_FLAVOR}"
export ASYNC_GA_NWAV="${ASYNC_GA_NWAV:-7}"
echo "ASYNC_GA_NWAV ${ASYNC_GA_NWAV}"
export ASYNC_GA_NTRAIT="${ASYNC_GA_NTRAIT:-3}"
echo "ASYNC_GA_NTRAIT ${ASYNC_GA_NTRAIT}"

export ASYNC_GA_MSEC_AT_LEAST=0
echo "ASYNC_GA_MSEC_AT_LEAST ${ASYNC_GA_MSEC_AT_LEAST}"

export ASYNC_GA_NCYCLE_AT_LEAST=100000
echo "ASYNC_GA_NCYCLE_AT_LEAST ${ASYNC_GA_NCYCLE_AT_LEAST}"

export ASYNC_GA_GLOBAL_SEED="${seed}"
echo "ASYNC_GA_GLOBAL_SEED ${ASYNC_GA_GLOBAL_SEED}"

export ASYNC_GA_POPSIZE=404
echo "ASYNC_GA_POPSIZE ${ASYNC_GA_POPSIZE}"

export ASYNC_GA_TOURNSIZE_NUMERATOR=2
echo "ASYNC_GA_TOURNSIZE_NUMERATOR ${ASYNC_GA_TOURNSIZE_NUMERATOR}"

export ASYNC_GA_TOURNSIZE_DENOMINATOR=1
echo "ASYNC_GA_TOURNSIZE_DENOMINATOR ${ASYNC_GA_TOURNSIZE_DENOMINATOR}"

export COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string="hybrid_0_steady_1_stretched_2_algo"
echo "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string ${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string}"

export COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32="${POPULATION_EXTINCTION_PROBABILITY}"
echo "COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32 ${COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32}"

echo "create sbatch file ====================================================="

SBATCH_FILE="$(mktemp)"
echo "SBATCH_FILE ${SBATCH_FILE}"

###############################################################################
# ----------------------------------------------------------------------------#
###############################################################################
cat > "${SBATCH_FILE}" << EOF
#!/bin/bash
#SBATCH --gres=cs:cerebras:1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G
#SBATCH --time=0:15:00
#SBATCH --output="/jet/home/%u/joblog/id=%j+ext=.txt"
#SBATCH --mail-user=mawni4ah2o@pomail.net
#SBATCH --mail-type=FAIL,TIME_LIMIT
#SBATCH --exclude=sdf-2

set -e
# newgrp GRANT_ID

echo "cc SLURM script --------------------------------------------------------"
JOBSCRIPT="\${HOME}/jobscript/id=\${SLURM_JOB_ID}+ext=.sbatch"
echo "JOBSCRIPT \${JOBSCRIPT}"
cp "\${0}" "\${JOBSCRIPT}"
chmod +x "\${JOBSCRIPT}"

echo "job telemetry ----------------------------------------------------------"
echo "source SLURM_JOB_ID ${SLURM_JOB_ID}"
echo "current SLURM_JOB_ID \${SLURM_JOB_ID}"
echo "hostname \$(hostname)"

echo "initialization telemetry -----------------------------------------------"
echo "WSE_ASYNC_GA_REVISION ${WSE_ASYNC_GA_REVISION}"
echo "HEAD_REVISION $(git rev-parse HEAD)"
echo "WORKDIR ${WORKDIR}"
echo "SLUG ${SLUG}"
echo "date \$(date)"
echo "SDK_INSTALL_LOCATION \${SDK_INSTALL_LOCATION:-}"
echo "SDK_INSTALL_PATH \${SDK_INSTALL_PATH:-}"
echo "which cs_python \$(which cs_python)"
echo "CS_IP_ADDR \${CS_IP_ADDR}"

echo "ASYNC_GA_NCOL_SUBGRID ${ASYNC_GA_NCOL_SUBGRID}"
echo "ASYNC_GA_NROW_SUBGRID ${ASYNC_GA_NROW_SUBGRID}"
echo "ASYNC_GA_MSEC_AT_LEAST ${ASYNC_GA_MSEC_AT_LEAST}"
echo "ASYNC_GA_NCYCLE_AT_LEAST ${ASYNC_GA_NCYCLE_AT_LEAST}"
echo "ASYNC_GA_GLOBAL_SEED ${ASYNC_GA_GLOBAL_SEED}"
echo "NREP ${NREP}"
echo "WSE_ASYNC_GA_REVISION ${WSE_ASYNC_GA_REVISION}"

export CS_PYTHON="${CS_PYTHON:-cs_python}"
echo "CS_PYTHON \${CS_PYTHON}"
export ASYNC_GA_GENOME_FLAVOR="${ASYNC_GA_GENOME_FLAVOR}"
echo "ASYNC_GA_GENOME_FLAVOR \${ASYNC_GA_GENOME_FLAVOR}"
export ASYNC_GA_NCOL="${ASYNC_GA_NCOL}"
echo "ASYNC_GA_NCOL \${ASYNC_GA_NCOL}"
export ASYNC_GA_NROW="${ASYNC_GA_NROW}"
echo "ASYNC_GA_NROW \${ASYNC_GA_NROW}"
export ASYNC_GA_NWAV="${ASYNC_GA_NWAV}"
echo "ASYNC_GA_NWAV \${ASYNC_GA_NWAV}"
export ASYNC_GA_NTRAIT="${ASYNC_GA_NTRAIT}"
echo "ASYNC_GA_NTRAIT \${ASYNC_GA_NTRAIT}"
export ASYNC_GA_EXECUTE_FLAGS="--cmaddr \${CS_IP_ADDR}:9000 --no-suptrace"
echo "ASYNC_GA_EXECUTE_FLAGS \${ASYNC_GA_EXECUTE_FLAGS}"
export "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string=${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string}"
echo "COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string \${COMPCONFENV_CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME__comptime_string}"
export "CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY=${CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY}"
echo "COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32 \${COMPCONFENV_CEREBRASLIB_POPULATION_EXTINCTION_PROBABILITY__f32}"

echo "setup WORKDIR ----------------------------------------------------------"
cd "${WORKDIR}"
echo "PWD \${PWD}"

echo "execute kernel program -------------------------------------------------"
./${SLUG}/kernel-async-ga/execute.sh
# clean up and save space
find "${SLUG}" -name "*.elf" -type f -exec rm {} +
find "${SLUG}" -name "*.conf" -type f -exec rm {} +

echo "finalization telemetry -------------------------------------------------"
echo "SECONDS \${SECONDS}"
echo ">>>fin<<<"

EOF
###############################################################################
# ----------------------------------------------------------------------------#
###############################################################################


echo "do kernel compile and submit sbatch file ==============================="
./kernel-async-ga/compile.sh
sbatch "${SBATCH_FILE}"

echo "end work loop =========================================================="
done
done
done

echo "wait ==================================================================="
wait

echo "finalization telemetry ================================================="
echo "SECONDS ${SECONDS}"
echo ">>>fin<<<"
