#!//bin/bash

set -euo pipefail

echo "date $(date '+%Y-%m-%d %H:%M:%S')"
echo "hostname $(hostname)"
echo "SECONDS ${SECONDS}"

source "${HOME}/.env" || true

cd "$(dirname "$0")"
echo "PWD ${PWD}"
cd "$(git rev-parse --show-toplevel)"
echo "PWD ${PWD}"

echo "git rev-parse HEAD $(git rev-parse HEAD)"

###############################################################################
echo "setup work environment -------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################

WORKDIR="${TMPDIR:-/tmp}/$(basename "$0" .sh)"
echo "WORKDIR ${WORKDIR}"
if [ -d "${WORKDIR}" ]; then
    echo "Clearing WORKDIR ${WORKDIR}"
    rm -rf "${WORKDIR}"
fi
mkdir -p "${WORKDIR}"

SCRATCHDIR="${HOME}/scratch/wse-async-ga/$(basename "$0" .sh)"
echo "SCRATCHDIR ${SCRATCHDIR}"
if [ -d "${SCRATCHDIR}" ]; then
    echo "Clearing SCRATCHDIR ${SCRATCHDIR}"
    rm -rf "${SCRATCHDIR}"
fi
mkdir -p "${SCRATCHDIR}"

echo "creating venv"
VENVDIR="${WORKDIR}/venv"
echo "VENVDIR ${VENVDIR}"
python3.8 -m venv "${VENVDIR}"
source "${VENVDIR}/bin/activate"
which python3

echo "setting up venv"
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade uv
python3 -m uv pip install -r "requirements_cs.txt"
python3 -m uv pip install ./pylib_cs
python3 -m uv pip freeze | tee "${WORKDIR}/pip-freeze.txt"
python3 -m pylib_cs.cslc_wsclust_shim  # test install

rsync -a "${PWD}/" "${WORKDIR}/source/"

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
cat > "${WORKDIR}/compile.env" << 'EOF'
export ASYNC_GA_ARCH_FLAG="wse3"
export ASYNC_GA_GENOME_FLAVOR="genome_mls_2025_08_15"
export ASYNC_GA_FABRIC_DIMS="762,1172"
export ASYNC_GA_NWAV=7
export ASYNC_GA_NCOL=755
export ASYNC_GA_NCOL_SUBGRID=0
export ASYNC_GA_NONBLOCK=1
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

source "${WORKDIR}/compile.env"

###############################################################################
echo "do compile -------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
"${WORKDIR}/source/kernel-async-ga/compile.sh" | tee "${WORKDIR}/compile.log"

###############################################################################
echo "setup run --------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
mkdir -p "${WORKDIR}/out"
mkdir -p "${WORKDIR}/run"
cd "${WORKDIR}/run"
echo "PWD ${PWD}"

cp -rL "${WORKDIR}/source/kernel-async-ga/cerebraslib" .
cp -rL "${WORKDIR}/source/kernel-async-ga/out" .
cp -L "${WORKDIR}/source/kernel-async-ga/client.py" .
cp -L "${WORKDIR}/source/kernel-async-ga/compconf.json" .
ls

cd "${WORKDIR}"
echo "PWD ${PWD}"
find "./run" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"

###############################################################################
echo "do run -----------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
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
    command = f"{env_prefix} cs_python client.py --cmaddr %CMADDR% | tee run.log"
    logging.info(f"command={command}")
    logging.info("running command...")
    response = launcher.run(command)
    logging.info("... done!")
    logging.info(response + "\n")

    logging.info("finding output files...")
    response = launcher.run(
        "find . -maxdepth 1 -type f "
        r'\( -name "*.log" -o -name "*.pqt" -o -name "*.json" \)',
    )
    logging.info("... done!")
    logging.info(response + "\n")

    for filename in response.splitlines():
        target = f"${WORKDIR}/out/{filename}"
        logging.info(f"retrieving file {filename} to {target}...")
        file_contents = launcher.download_artifact(filename, target)
        logging.info("... done!")

    logging.info("exiting SdkLauncher")

logging.info("exited SdkLauncher")
EOF

###############################################################################
echo "handle output ----------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
find "${WORKDIR}/out" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${WORKDIR}"/out/*

cp "${WORKDIR}/compile.log" "${SCRATCHDIR}/compile.log"
cp "${WORKDIR}"/out/* "${SCRATCHDIR}"

find "${SCRATCHDIR}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${SCRATCHDIR}"/*

###############################################################################
echo "build phylogeny --------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
cd "${SCRATCHDIR}"
find . -type f \( -name 'a=genomes*.pqt' -o -name 'a=fossils*.pqt' \) \
    | singularity exec docker://ghcr.io/mmore500/hstrat:v1.20.13 \
    python3 -m hstrat.dataframe.surface_build_tree \
        "a=phylogeny+ext=.pqt" \
        --filter '~pl.col("data_hex").str.contains(r"^0+$")' \
        --with-column 'pl.lit(filepath).cast(pl.Categorical).alias("file")' \
        --with-column 'pl.sum_horizontal(
            ((pl.col("data_hex").str.slice(2*b, 2).str.to_integer(base=16)
            ^ pl.col(f"flag_nand_mask_byte{b}"))
            & pl.col(f"flag_is_focal_mask_byte{b}")).bitwise_count_ones()
            for b in range(8)
        ).alias("focal_trait_count")' \
        --with-column 'pl.sum_horizontal(
            ((pl.col("data_hex").str.slice(2*b, 2).str.to_integer(base=16)
            ^ pl.col(f"flag_nand_mask_byte{b}"))
            & (~pl.col(f"flag_is_focal_mask_byte{b}"))).bitwise_count_ones()
            for b in range(8)
        ).alias("nonfocal_trait_count")' \
        --with-column '(
            ((pl.col("data_hex").str.slice(0, 2).str.to_integer(base=16)
            ^ pl.col("flag_nand_mask_byte0"))
            & pl.lit(1))
            * ((pl.col("flag_is_focal_mask_byte0") & pl.lit(1)) + pl.lit(1))
        ).alias("byte0_bit0_trait")' \
        --with-column '(
            ((pl.col("data_hex").str.slice(0, 2).str.to_integer(base=16)
            ^ pl.col("flag_nand_mask_byte0"))
            & pl.lit(2))
            * ((pl.col("flag_is_focal_mask_byte0") & pl.lit(2)) + pl.lit(2))
            // 4
        ).alias("byte0_bit1_trait")' \
        --with-column '(
            ((pl.col("data_hex").str.slice(2, 2).str.to_integer(base=16)
            ^ pl.col("flag_nand_mask_byte1"))
            & pl.lit(1))
            * ((pl.col("flag_is_focal_mask_byte1") & pl.lit(1)) + pl.lit(1))
        ).alias("byte1_bit0_trait")' \
        --with-column '(
            ((pl.col("data_hex").str.slice(2, 2).str.to_integer(base=16)
            ^ pl.col("flag_nand_mask_byte1"))
            & pl.lit(2))
            * ((pl.col("flag_is_focal_mask_byte1") & pl.lit(2)) + pl.lit(2))
            // 4
        ).alias("byte1_bit1_trait")'

###############################################################################
echo "done! ------------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
