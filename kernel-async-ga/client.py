print("kernel-async-ga/client.py ############################################")
print("######################################################################")
import argparse
import atexit
from collections import Counter
import itertools as it
import json
import logging
import multiprocessing
import os
import pathlib
import uuid
import shutil
import subprocess
import sys
import typing

logging.basicConfig(
    datefmt="%Y-%m-%d %H:%M:%S",
    format="%(asctime)s %(levelname)-8s %(message)s",
    level=logging.INFO,
)

def log(msg, *args, **kwargs):
    msg = str(msg)
    msg = msg.replace("\n", "\n" + " " * 29)
    logging.info(msg, *args, **kwargs)


def removeprefix(text: str, prefix: str) -> str:
    if text.startswith(prefix):
        return text[len(prefix):]
    return text


def hexify_binary_data(
    raw_binary_data: "np.ndarray",
    nWav: int,
    verbose: bool = False,
) -> typing.List[str]:
    if verbose:
        for word in range(nWav):
            log(f"---------------------------------------------- binary word {word}")
            values = (inner[word] for outer in raw_binary_data for inner in outer)
            log(str([*it.islice(values, 10)]))

    shape = raw_binary_data.shape
    binary_ints = raw_binary_data.astype(">u4").reshape(-1, shape[-1])
    assert len(binary_ints) == nRow * nCol
    if verbose:
        log("------------------------------------------------ binary u32 ints")
        for binary_int in binary_ints[:10]:
            log(f"{len(binary_ints)=} {binary_int=}")

    binary_hex = binary_ints.tobytes().hex()
    if verbose:
        log("---------------------------------------------- binary hex string")
        log(f"{len(binary_hex)=} {binary_hex[:100]=}")

    binary_bytes = bytearray(binary_hex, "ascii")
    if verbose:
        log("--------------------------------------------------- binary bytes")
        log(f"{len(binary_bytes)=} {binary_bytes[:100]=}")

    binary_chars = np.frombuffer(binary_bytes, dtype="S1").astype(str)
    if verbose:
        log("--------------------------------------------------- binary chars")
        log(f"{len(binary_chars)=} {binary_chars[:100]=}")

    chunk_size = nWav * wavSize // 4
    reshaped = binary_chars.reshape(-1, chunk_size)
    binary_strings = np.apply_along_axis("".join, 1, reshaped)
    assert len(binary_strings) == nRow * nCol
    if verbose:
        log("--------------------------------------------- binary hex strings")
        for binary_string in binary_strings[:10]:
            log(f"{binary_string=}")

    return binary_strings


def hexify_genome_data(data: "np.ndarray", verbose: bool = False) -> typing.List[str]:
    return hexify_binary_data(data, nWav=nWav, verbose=False)


log("- setting up temp dir")
# need to add polars to Cerebras python
temp_dir = f"/local/tmp/{uuid.uuid4()}"
os.makedirs(temp_dir, exist_ok=True)
atexit.register(shutil.rmtree, temp_dir, ignore_errors=True)
log(f"  - {temp_dir=}")
log("- installing polars")
for attempt in range(4):
    try:
        subprocess.check_call(
            [
                "pip",
                "install",
                f"--target={temp_dir}",
                "--no-cache-dir",
                "polars==1.6.0",
            ],
            env={
                **os.environ,
                "TMPDIR": temp_dir,
            },
        )
        log("- pip install succeeded!")
        break
    except subprocess.CalledProcessError as e:
        log(e)
        log(f"retrying {attempt=}...")
else:
    raise e
log(f"- extending sys path with temp dir {temp_dir=}")
sys.path.append(temp_dir)

log("- importing third-party dependencies")
import numpy as np
log("  - numpy")
import polars as pl
log("  - polars")
from scipy import stats as sps
log("  - scipy")
from tqdm import tqdm
log("  - tqdm")

log("- importing cerebras depencencies")
from cerebras.sdk.runtime.sdkruntimepybind import (
    MemcpyDataType,
    MemcpyOrder,
    SdkRuntime,
)  # pylint: disable=no-name-in-module

log("- defining helper functions")
def write_parquet_verbose(df: pl.DataFrame, file_name: str) -> None:
    log(f"saving df to {file_name=}")
    log(f"- {df.shape=}")

    tmp_file = "/local/tmp.pqt"
    df.write_parquet(tmp_file, compression="lz4")
    log("- write_parquet complete")

    file_size_mb = os.path.getsize(tmp_file) / (1024 * 1024)
    log(f"- saved file size: {file_size_mb:.2f} MB")

    lazy_frame = pl.scan_parquet(tmp_file)
    log("- LazyFrame describe:")
    log(lazy_frame.describe())

    original_row_count = df.shape[0]
    lazy_row_count = lazy_frame.select(pl.count()).collect().item()
    assert lazy_row_count == original_row_count, (
        f"Row count mismatch between original and lazy frames: "
        f"{original_row_count=}, {lazy_row_count=}"
    )

    shutil.copy(tmp_file, file_name)
    log(f"- copy {tmp_file} to destination {file_name} complete")

    log("- verbose save complete!")

# adapted from https://stackoverflow.com/a/31347222/17332200
def add_bool_arg(parser, name, default=False):
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--" + name, dest=name, action="store_true")
    group.add_argument("--no-" + name, dest=name, action="store_false")
    parser.set_defaults(**{name: default})

log("- reading env variables")
# number of rows, columns, and genome words
nCol = int(os.getenv("ASYNC_GA_NCOL", 3))
nRow = int(os.getenv("ASYNC_GA_NROW", 3))
nWav = int(os.getenv("ASYNC_GA_NWAV", -1))
nTrait = int(os.getenv("ASYNC_GA_NTRAIT", 1))
log(f"{nCol=}, {nRow=}, {nWav=}, {nTrait=}")

log("- setting global variables")
wavSize = 32  # number of bits in a wavelet
tscSizeWords = 3  # number of 16-bit values in 48-bit timestamp values
tscSizeWords += tscSizeWords % 2  # make even multiple of 32-bit words
tscTicksPerSecond = 850 * 10**6  # 850 MHz

log("- configuring argparse")
parser = argparse.ArgumentParser()
parser.add_argument("--name", help="the test compile output dir", default="out")
add_bool_arg(parser, "suptrace", default=True)
parser.add_argument("--cmaddr", help="IP:port for CS system")
log("- parsing arguments")
args = parser.parse_args()

log("args =======================================================")
log(args)

log("metadata ===================================================")
with open(f"{args.name}/out.json", encoding="utf-8") as json_file:
    compile_data = json.load(json_file)

globalSeed = int(compile_data["params"]["globalSeed"])
nCycleAtLeast = int(compile_data["params"]["nCycleAtLeast"])
msecAtLeast = int(compile_data["params"]["msecAtLeast"])
tscAtLeast = int(compile_data["params"]["tscAtLeast"])
nColSubgrid = int(compile_data["params"]["nColSubgrid"])
nRowSubgrid = int(compile_data["params"]["nRowSubgrid"])
nonBlock = bool(int(compile_data["params"]["nonBlock"]))
tilePopSize = int(compile_data["params"]["popSize"])
tournSize = (
    float(compile_data["params"]["tournSizeNumerator"])
    / float(compile_data["params"]["tournSizeDenominator"])
)

with open("compconf.json", encoding="utf-8") as json_file:
    compconf_data = json.load(json_file)

log(f" - {compconf_data=}")

traitLoggerNumBits = int(compconf_data["CEREBRASLIB_TRAITLOGGER_NUM_BITS:u32"])
assert bin(traitLoggerNumBits)[2:].count("1") == 1
traitLoggerDstreamAlgoName = compconf_data[
    "CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME:comptime_string"
]
log(f" - {traitLoggerNumBits=} {traitLoggerDstreamAlgoName=}")

genomeFlavor = compconf_data["ASYNC_GA_GENOME_FLAVOR:comptime_string"]
log(f" - {genomeFlavor=}")
genomePath = f"/cerebraslib/genome/{genomeFlavor}.csl"
log(f" - reading genome data from {genomePath}")
genomeDataRaw = "".join(
    removeprefix(line, "//!").strip()
    for line in pathlib.Path(genomePath).read_text().split("\n")
    if line.startswith("//!")
) or "{}"
genomeData = eval(genomeDataRaw, {"compconf_data": compconf_data, "pl": pl})
log(f" - {genomeData=}")

assert nWav in (genomeData["nWav"][0], -1)
nWav = genomeData["nWav"][0]

metadata = {
    "genomeFlavor": (genomeFlavor, pl.Categorical),
    "globalSeed": (globalSeed, pl.UInt32),
    "nCol": (nCol, pl.UInt16),
    "nRow": (nRow, pl.UInt16),
    "nWav": (nWav, pl.UInt8),
    "nTrait": (nTrait, pl.UInt8),
    "nCycle": (nCycleAtLeast, pl.UInt32),
    "nColSubgrid": (nColSubgrid, pl.UInt16),
    "nRowSubgrid": (nRowSubgrid, pl.UInt16),
    "nonBlock": (nonBlock, pl.Boolean),
    "tilePopSize": (tilePopSize, pl.UInt16),
    "tournSize": (tournSize, pl.Float32),
    "msec": (msecAtLeast, pl.Float32),
    "tsc": (tscAtLeast, pl.UInt64),
    "replicate": (str(uuid.uuid4()), pl.Categorical),
    **genomeData,
    **{
        k.split(":")[0]: {
            "bool": lambda: (json.loads(v), pl.Boolean),
            "f16": lambda: (float(v), pl.Float32),
            "f32": lambda: (float(v), pl.Float32),
            "i8": lambda: (int(v), pl.Int8),
            "i16": lambda: (int(v), pl.Int16),
            "i32": lambda: (int(v), pl.Int32),
            "i64": lambda: (int(v), pl.Int64),
            "u8": lambda: (int(v), pl.UInt8),
            "u16": lambda: (int(v), pl.UInt16),
            "u32": lambda: (int(v), pl.UInt32),
            "u64": lambda: (int(v), pl.UInt64),
            "comptime_string": lambda: (v, pl.Categorical),
        }[k.split(":")[-1]]()
        for k, v in compconf_data.items()
    },
}
log(metadata)

log("do run =====================================================")
# Path to ELF and simulation output files
runner = SdkRuntime(
    "out", cmaddr=args.cmaddr, suppress_simfab_trace=args.suptrace
)
log("- SdkRuntime created")

runner.load()
log("- runner loaded")

runner.run()
log("- runner run ran")

runner.launch("dolaunch", nonblock=False)
log("- runner launch complete")

log(f"- {nonBlock=}, if True waiting for first kernel to finish...")
fossils = []
while nonBlock:
    print("1", end="", flush=True)
    memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
    out_tensors = np.zeros((nCol, nRow, nWav), np.uint32)

    runner.memcpy_d2h(
        out_tensors.ravel(),
        runner.get_id("genome"),
        0,  # x0
        0,  # y0
        nCol,  # width
        nRow,  # height
        nWav,  # num wavelets
        streaming=False,
        data_type=memcpy_dtype,
        order=MemcpyOrder.ROW_MAJOR,
        nonblock=False,
    )
    print("2", end="", flush=True)

    genome_data = out_tensors.copy()
    fossils.append(genome_data)
    print("3", end="", flush=True)

    memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
    out_tensors = np.zeros((nCol, nRow, 1), np.uint32)
    runner.memcpy_d2h(
        out_tensors.ravel(),
        runner.get_id("cycleCounter"),
        0,  # x0
        0,  # y0
        nCol,  # width
        nRow,  # height
        1,  # num wavelets
        streaming=False,
        data_type=memcpy_dtype,
        order=MemcpyOrder.ROW_MAJOR,
        nonblock=False,
    )
    print("4", end="", flush=True)

    cycle_counts = out_tensors.ravel().copy()
    num_complete = np.sum(cycle_counts >= nCycleAtLeast)
    print("5", end="", flush=True)

    should_break = num_complete > 0
    print(f"({num_complete/cycle_counts.size * 100}%)", end="", flush=True)
    if should_break:
        print("!", flush=True)
        break
    else:
        print("|", end="", flush=True)
        continue

log(f"- {nonBlock=}, if True waiting for last kernel to finish...")
while nonBlock:
    print("1", end="", flush=True)
    memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
    out_tensors = np.zeros((nCol, nRow, 1), np.uint32)
    runner.memcpy_d2h(
        out_tensors.ravel(),
        runner.get_id("cycleCounter"),
        0,  # x0
        0,  # y0
        nCol,  # width
        nRow,  # height
        1,  # num wavelets
        streaming=False,
        data_type=memcpy_dtype,
        order=MemcpyOrder.ROW_MAJOR,
        nonblock=False,
    )
    print("2", end="", flush=True)

    cycle_counts = out_tensors.ravel().copy()
    num_complete = np.sum(cycle_counts >= nCycleAtLeast)
    print("3", end="", flush=True)
    should_break = (num_complete == cycle_counts.size)
    print(f"({num_complete/cycle_counts.size * 100}%)", end="", flush=True)
    if should_break:
        print("!", flush=True)
        break
    else:
        print("|", end="", flush=True)
        continue

log("fossils ====================================================")
log(f" - {len(fossils)=}")

max_fossil_sets = int(os.environ.get("ASYNC_GA_MAX_FOSSIL_SETS", 2**32 - 1))
log(f" - {max_fossil_sets=}")
fossils = fossils[:max_fossil_sets]

if len(fossils):
    log(f"- {fossils[0].shape=}")
    log("- example hexification")
    hexify_genome_data(fossils[0], verbose=True)

with multiprocessing.Pool() as pool:
    # Map our function over fossils in parallel, and use tqdm for a progress bar
    work = pool.imap(hexify_genome_data, fossils)
    fossils = [*tqdm(work, total=len(fossils), desc="hexing fossils")]

log(f" - {len(fossils)=}")

if fossils:
    fossils = np.array(fossils)
    layers, positions = np.indices(fossils.shape)
    df = pl.DataFrame({
        "data_hex": pl.Series(fossils.ravel(), dtype=pl.Utf8),
        "is_extant": False,
        "layer": pl.Series(layers.ravel(), dtype=pl.UInt32),
        "position": pl.Series(positions.ravel(), dtype=pl.UInt32),
    }).with_columns([
        pl.lit(value, dtype=dtype).alias(key)
        for key, (value, dtype) in metadata.items()
        if (
            key.startswith("dstream_")
            or key.startswith("downstream_")
            or key in ("genomeFlavor",)
        )
    ])

    write_parquet_verbose(
        df,
        "a=fossils"
        f"+flavor={genomeFlavor}"
        f"+seed={globalSeed}"
        f"+ncycle={nCycleAtLeast}"
        "+ext=.pqt",
    )

    del df

del fossils

log("whoami =====================================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("whoami"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
whoami_data = out_tensors.copy()
log(whoami_data[:20,:20])

log("whereami x =================================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("whereami_x"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
whereami_x_data = out_tensors.copy()
log(whereami_x_data[:20,:20])

log("whereami y =================================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("whereami_y"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
whereami_y_data = out_tensors.copy()
log(whereami_y_data[:20,:20])

log("trait data =================================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, nTrait), np.uint32)
runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("traitCounts"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    nTrait,  # num possible trait values
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
traitCounts_data = out_tensors.copy()
log(f"traitCounts_data {Counter(traitCounts_data.ravel())}")

memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, nTrait), np.uint32)
runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("traitCycles"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    nTrait,  # num possible trait values
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
traitCycles_data = out_tensors.copy()
log(f"traitCycles_data {Counter(traitCycles_data.ravel())}")

memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, nTrait), np.uint32)
runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("traitValues"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    nTrait,  # num possible trait values
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
traitValues_data = out_tensors.copy()
log(f"traitValues_data {str(Counter(traitValues_data.ravel()))[:500]}")

# save trait data values to a file
df = pl.DataFrame({
    "trait count": pl.Series(traitCounts_data.ravel(), dtype=pl.UInt16),
    "trait cycle last seen": pl.Series(traitCycles_data.ravel(), dtype=pl.UInt32),
    "trait value": pl.Series(traitValues_data.ravel(), dtype=pl.UInt8),
    "tile": pl.Series(np.repeat(whoami_data.ravel(), nTrait), dtype=pl.UInt32),
    "row": pl.Series(np.repeat(whereami_y_data.ravel(), nTrait), dtype=pl.UInt16),
    "col": pl.Series(np.repeat(whereami_x_data.ravel(), nTrait), dtype=pl.UInt16),
}).with_columns([
    pl.lit(value, dtype=dtype).alias(key)
    for key, (value, dtype) in metadata.items()
])


for trait, group in df.group_by("trait value"):
    log(f"trait {trait} total count is {group['trait count'].sum()}")

write_parquet_verbose(
    df,
    "a=traits"
    f"+flavor={genomeFlavor}"
    f"+seed={globalSeed}"
    f"+ncycle={nCycleAtLeast}"
    "+ext=.pqt",
)
del df, traitCounts_data, traitCycles_data, traitValues_data

log("wildtype traitlogs ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
traitLoggerNumWavs = traitLoggerNumBits // wavSize + 1  # +1 for dstream_T
out_tensors = np.zeros((nCol, nRow, traitLoggerNumWavs), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("wildtypeLoggerRecord"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    traitLoggerNumWavs,  # num elements
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
raw_binary_data = out_tensors.copy()
record_hex = hexify_binary_data(
    raw_binary_data.view(np.uint32), nWav=traitLoggerNumWavs, verbose=True
)

# save genome values to a file
df = pl.DataFrame({
    "data_hex": pl.Series(record_hex, dtype=pl.Utf8),
    "tile": pl.Series(whoami_data.ravel(), dtype=pl.UInt32),
    "row": pl.Series(whereami_y_data.ravel(), dtype=pl.UInt16),
    "col": pl.Series(whereami_x_data.ravel(), dtype=pl.UInt16),
}).with_columns([
    pl.lit(value, dtype=dtype).alias(key)
    for key, (value, dtype) in metadata.items()
]).with_columns(
    dstream_algo=pl.lit(
        f"dstream.{traitLoggerDstreamAlgoName}", dtype=pl.Categorical
    ),
    dstream_storage_bitoffset=pl.lit(0, dtype=pl.UInt16),
    dstream_storage_bitwidth=pl.lit(traitLoggerNumBits, dtype=pl.UInt16),
    dstream_S=pl.lit(traitLoggerNumBits, dtype=pl.UInt16),
    dstream_T_bitoffset=pl.lit(traitLoggerNumBits, dtype=pl.UInt16),
    dstream_T_bitwidth=pl.lit(32, dtype=pl.UInt16),
    trait_value=pl.lit(0, dtype=pl.UInt16),
)

write_parquet_verbose(
    df,
    "a=traitloggerRecord"
    f"+flavor={genomeFlavor}"
    f"+seed={globalSeed}"
    f"+ncycle={nCycleAtLeast}"
    "+ext=.pqt",
)
del df, raw_binary_data, record_hex

log("fitness ===================================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.float32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("fitness"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
fitness_data = out_tensors.copy()
log(fitness_data[:20,:20])

log("genome values ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, nWav), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("genome"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    nWav,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
raw_genome_data = out_tensors.copy()
genome_hex = hexify_genome_data(raw_genome_data, verbose=True)

# save genome values to a file
df = pl.DataFrame({
    "data_hex": pl.Series(genome_hex, dtype=pl.Utf8),
    "is_extant": True,
    "fitness": pl.Series(fitness_data.ravel(), dtype=pl.Float32),
    "tile": pl.Series(whoami_data.ravel(), dtype=pl.UInt32),
    "row": pl.Series(whereami_y_data.ravel(), dtype=pl.UInt16),
    "col": pl.Series(whereami_x_data.ravel(), dtype=pl.UInt16),
}).with_columns([
    pl.lit(value, dtype=dtype).alias(key)
    for key, (value, dtype) in metadata.items()
])

write_parquet_verbose(
    df,
    "a=genomes"
    f"+flavor={genomeFlavor}"
    f"+seed={globalSeed}"
    f"+ncycle={nCycleAtLeast}"
    "+ext=.pqt",
)
del df, fitness_data, genome_hex

log("cycle counter =============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("cycleCounter"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
cycle_counts = out_tensors.ravel().copy()
log(cycle_counts[:100])


log("recv counter N ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("recvCounter_N"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
recvN = out_tensors.copy()
log(recvN[:20,:20])

log("recv counter S ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("recvCounter_S"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
recvS = out_tensors.copy()
log(recvS[:20,:20])

log("recv counter E ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("recvCounter_E"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
recvE = out_tensors.copy()
log(recvE[:20,:20])

log("recv counter W ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("recvCounter_W"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
recvW = out_tensors.copy()
log(recvW[:20,:20])

log("recv counter sum ===========================================")
recvSum = [*map(sum, zip(recvN.ravel(), recvS.ravel(), recvE.ravel(), recvW.ravel()))]
log(recvSum[:100])
log(f"{np.mean(recvSum)=} {np.std(recvSum)=} {sps.sem(recvSum)=}")

log("send counter N ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("sendCounter_N"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
sendN = out_tensors.copy()
log(sendN[:20,:20])

log("send counter S ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("sendCounter_S"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
sendS = out_tensors.copy()
log(sendS[:20,:20])

log("send counter E ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("sendCounter_E"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
sendE = out_tensors.copy()
log(sendE[:20,:20])

log("send counter W ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("sendCounter_W"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    1,  # num wavelets
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
sendW = out_tensors.copy()
log(sendW[:20,:20])

log("send counter sum ===========================================")
sendSum = [*map(sum, zip(sendN.ravel(), sendS.ravel(), sendE.ravel(), sendW.ravel()))]
log(sendSum[:100])
log(f"{np.mean(sendSum)=} {np.std(sendSum)=} {sps.sem(sendSum)=}")

log("tscControl values ==========================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, tscSizeWords // 2), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("tscControlBuffer"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    tscSizeWords // 2,  # num values
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
data = out_tensors
tscControl_bytes = [
    inner.view(np.uint8).tobytes() for outer in data for inner in outer
]
tscControl_ints = [
    int.from_bytes(genome, byteorder="little") for genome in tscControl_bytes
]
log(tscControl_ints[:100])

log("tscStart values ============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, tscSizeWords // 2), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("tscStartBuffer"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    tscSizeWords // 2,  # num values
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
data = out_tensors
tscStart_bytes = [
    inner.view(np.uint8).tobytes() for outer in data for inner in outer
]
tscStart_ints = [
    int.from_bytes(genome, byteorder="little") for genome in tscStart_bytes
]
log(tscStart_ints[:100])

log("tscEnd values ==============================================")
memcpy_dtype = MemcpyDataType.MEMCPY_32BIT
out_tensors = np.zeros((nCol, nRow, tscSizeWords // 2), np.uint32)

runner.memcpy_d2h(
    out_tensors.ravel(),
    runner.get_id("tscEndBuffer"),
    0,  # x0
    0,  # y0
    nCol,  # width
    nRow,  # height
    tscSizeWords // 2,  # num values
    streaming=False,
    data_type=memcpy_dtype,
    order=MemcpyOrder.ROW_MAJOR,
    nonblock=False,
)
data = out_tensors
tscEnd_bytes = [
    inner.view(np.uint8).tobytes() for outer in data for inner in outer
]
tscEnd_ints = [
    int.from_bytes(genome, byteorder="little") for genome in tscEnd_bytes
]
log(tscEnd_ints[:100])

log("tsc diffs ==================================================")
log("--------------------------------------------------------- ticks")
tsc_ticks = [end - start for start, end in zip(tscStart_ints, tscEnd_ints)]
log(tsc_ticks[:100])
log(f"{np.mean(tsc_ticks)=} {np.std(tsc_ticks)=} {sps.sem(tsc_ticks)=}")

log("------------------------------------------------------ seconds")
tsc_sec = [diff / tscTicksPerSecond for diff in tsc_ticks]
log(tsc_sec[:100])
log(f"{np.mean(tsc_sec)=} {np.std(tsc_sec)=} {sps.sem(tsc_sec)=}")

log("-------------------------------------------- seconds per cycle")
tsc_cysec = [sec / ncy for (sec, ncy) in zip(tsc_sec, cycle_counts)]
log(tsc_cysec[:100])
log(f"{np.mean(tsc_cysec)=} {np.std(tsc_cysec)=} {sps.sem(tsc_cysec)=}")

log("-------------------------------------------------- cycle hertz")
tsc_cyhz = [1 / cysec for cysec in tsc_cysec]
log(tsc_cyhz[:100])
log(f"{np.mean(tsc_cyhz)=} {np.std(tsc_cyhz)=} {sps.sem(tsc_cyhz)=}")

log("------------------------------------------------- ns per cycle")
tsc_cyns = [cysec * 1e9 for cysec in tsc_cysec]
log(tsc_cyns[:100])
log(f"{np.mean(tsc_cyns)=} {np.std(tsc_cyns)=} {sps.sem(tsc_cyns)=}")

log("perf ======================================================")
# save performance metrics to a file
df = pl.DataFrame({
    "tsc ticks": pl.Series(tsc_ticks, dtype=pl.UInt64),
    "tsc seconds": pl.Series(tsc_sec, dtype=pl.Float32),
    "tsc seconds per cycle": pl.Series(tsc_cysec, dtype=pl.Float32),
    "tsc cycle hertz": pl.Series(tsc_cyhz, dtype=pl.Float32),
    "tsc ns per cycle": pl.Series(tsc_cyns, dtype=pl.Float32),
    "recv sum": pl.Series(recvSum, dtype=pl.UInt32),
    "send sum": pl.Series(sendSum, dtype=pl.UInt32),
    "cycle count": pl.Series(cycle_counts, dtype=pl.UInt32),
    "tsc start": pl.Series(tscStart_ints, dtype=pl.UInt64),
    "tsc end": pl.Series(tscEnd_ints, dtype=pl.UInt64),
    "send N": pl.Series(sendN.ravel(), dtype=pl.UInt32),
    "send S": pl.Series(sendS.ravel(), dtype=pl.UInt32),
    "send E": pl.Series(sendE.ravel(), dtype=pl.UInt32),
    "send W": pl.Series(sendW.ravel(), dtype=pl.UInt32),
    "recv N": pl.Series(recvN.ravel(), dtype=pl.UInt32),
    "recv S": pl.Series(recvS.ravel(), dtype=pl.UInt32),
    "recv E": pl.Series(recvE.ravel(), dtype=pl.UInt32),
    "recv W": pl.Series(recvW.ravel(), dtype=pl.UInt32),
    "tile": pl.Series(whoami_data.ravel(), dtype=pl.UInt32),
    "row": pl.Series(whereami_y_data.ravel(), dtype=pl.UInt16),
    "col": pl.Series(whereami_x_data.ravel(), dtype=pl.UInt16),
})
df.with_columns([
    pl.lit(value, dtype=dtype).alias(key)
    for key, (value, dtype) in metadata.items()
])
write_parquet_verbose(
    df,
    "a=perf"
    f"+flavor={genomeFlavor}"
    f"+seed={globalSeed}"
    f"+ncycle={nCycleAtLeast}"
    "+ext=.pqt",
)
del df, tsc_ticks, tsc_sec, tsc_cysec, tsc_cyhz, tsc_cyns, tscStart_ints, tscEnd_ints

# runner.dump("corefile.cs1")
runner.stop()

# Ensure that the result matches our expectation
log("SUCCESS!")
