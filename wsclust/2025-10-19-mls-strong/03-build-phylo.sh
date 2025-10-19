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
WORKDIR="${FLOWPATH}/workdir"
RESULTDIR="${FLOWPATH}/resultdir"

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
echo "build phylogeny --------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
cd "${WORKDIR}/02-run/out"
find . -type f \( -name 'a=genomes*.pqt' -o -name 'a=fossils*.pqt' \) \
    | singularity exec docker://ghcr.io/mmore500/hstrat:v1.20.13 \
    python3 -m hstrat.dataframe.surface_build_tree \
        "${WORKDIR_STEP}/a=phylogeny+ext=.pqt" \
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
        ).alias("byte1_bit1_trait")' \
        | tee "${RESULTDIR_STEP}/surface_build_tree.log"

###############################################################################
echo "handle output ----------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################
find "${WORKDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${WORKDIR_STEP}"/*

cp "${WORKDIR_STEP}"/* "${RESULTDIR_STEP}"

find "${RESULTDIR_STEP}" | sed -e "s/[^-][^\/]*\// |/g" -e "s/|\([^ ]\)/|-\1/"
du -ah "${RESULTDIR_STEP}"/*

###############################################################################
echo "done! ------------------------------------------------------------------"
echo "SECONDS ${SECONDS}"
###############################################################################

echo ">>>fin<<<"
