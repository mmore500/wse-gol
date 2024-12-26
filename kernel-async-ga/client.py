print("kernel-async-ga/client.py ############################################")
print("######################################################################")
import argparse
import atexit
from collections import Counter
import itertools as it
import json
import os
import pathlib
import uuid
import shutil
import subprocess
import sys
import textwrap
import typing


def print_(*args, **kwargs) -> None:
    return print(*args, **kwargs, flush=True)


def removeprefix(text: str, prefix: str) -> str:
    if text.startswith(prefix):
        return text[len(prefix):]
    return text


def hexify_genome_data(
    raw_genome_data: "np.ndarray",
    verbose: bool = False,
) -> typing.List[str]:
    if verbose:
        for word in range(nWav):
            print_(f"---------------------------------------------- genome word {word}")
            values = (
                inner[word] for outer in raw_genome_data for inner in outer
            )
            print_([*it.islice(values, 10)])

    shape = raw_genome_data.shape
    genome_ints = raw_genome_data.astype(">u4").reshape(-1, shape[-1])
    assert len(genome_ints) == nRow * nCol
    if verbose:
        print_("------------------------------------------------ genome u32 ints")
        for genome_int in genome_ints[:10]:
            print_(f"{genome_int=}")

    genome_hex = genome_ints.tobytes().hex()
    if verbose:
        print_("--------------------------------------------------- genome hex string")
        print_(f"{genome_hex[:100]=}", len(genome_hex))

    genome_hexes = textwrap.wrap(genome_hex, nWav * wavSize // 4)
    assert len(genome_hexes) == nRow * nCol
    if verbose:
        print_("------------------------------------------------ genome hex strings")
        for genome_hex_ in genome_hexes[:10]:
            print_(f"{genome_hex_=}")

    return genome_hexes


print_("- setting up temp dir")
# need to add polars to Cerebras python
temp_dir = f"/local/tmp/{uuid.uuid4()}"
os.makedirs(temp_dir, exist_ok=True)
atexit.register(shutil.rmtree, temp_dir, ignore_errors=True)
print_(f"  - {temp_dir=}")
print_("- installing polars")
for attempt in range(4):
    try:
        subprocess.check_call(
            [
                "pip",
                "install",
                f"--target={temp_dir}",
                f"--no-cache-dir",
                "polars==1.6.0",
            ],
            env={
                **os.environ,
                "TMPDIR": temp_dir,
            },
        )
        print_("- pip install succeeded!")
        break
    except subprocess.CalledProcessError as e:
        print_(e)
        print_(f"retrying {attempt=}...")
else:
    raise e
print_(f"- extending sys path with temp dir {temp_dir=}")
sys.path.append(temp_dir)

print_("- importing third-party dependencies")
import numpy as np
print_("  - numpy")
import polars as pl
print_("  - polars")
from scipy import stats as sps
print_("  - scipy")
from tqdm import tqdm
print_("  - tqdm")

print_("- importing cerebras depencencies")
from cerebras.sdk.runtime.sdkruntimepybind import (
    MemcpyDataType,
    MemcpyOrder,
    SdkRuntime,
)  # pylint: disable=no-name-in-module

print_("- defining helper functions")
def write_parquet_verbose(df: pl.DataFrame, file_name: str) -> None:
    print_(f"saving df to {file_name=}")
    print_(f"- {df.shape=}")

    tmp_file = "/local/tmp.pqt"
    df.write_parquet(tmp_file, compression="lz4")
    print_("- write_parquet complete")

    file_size_mb = os.path.getsize(tmp_file) / (1024 * 1024)
    print_(f"- saved file size: {file_size_mb:.2f} MB")

    lazy_frame = pl.scan_parquet(tmp_file)
    print_("- LazyFrame describe:")
    print_(lazy_frame.describe())

    original_row_count = df.shape[0]
    lazy_row_count = lazy_frame.select(pl.count()).collect().item()
    assert lazy_row_count == original_row_count, (
        f"Row count mismatch between original and lazy frames: "
        f"{original_row_count=}, {lazy_row_count=}"
    )

    shutil.copy(tmp_file, file_name)
    print_(f"- copy {tmp_file} to destination {file_name} complete")

    print_("- verbose save complete!")

# adapted from https://stackoverflow.com/a/31347222/17332200
def add_bool_arg(parser, name, default=False):
    group = parser.add_mutually_exclusive_group(required=False)
    group.add_argument("--" + name, dest=name, action="store_true")
    group.add_argument("--no-" + name, dest=name, action="store_false")
    parser.set_defaults(**{name: default})

print_("- reading env variables")
# number of rows, columns, and genome words
nCol = int(os.getenv("ASYNC_GA_NCOL", 3))
nRow = int(os.getenv("ASYNC_GA_NROW", 3))
nWav = int(os.getenv("ASYNC_GA_NWAV", -1))
nTrait = int(os.getenv("ASYNC_GA_NTRAIT", 1))
print_(f"{nCol=}, {nRow=}, {nWav=}, {nTrait=}")

print_("- setting global variables")
wavSize = 32  # number of bits in a wavelet
tscSizeWords = 3  # number of 16-bit values in 48-bit timestamp values
tscSizeWords += tscSizeWords % 2  # make even multiple of 32-bit words
tscTicksPerSecond = 850 * 10**6  # 850 MHz

print_("- configuring argparse")
parser = argparse.ArgumentParser()
parser.add_argument("--name", help="the test compile output dir", default="out")
add_bool_arg(parser, "suptrace", default=True)
parser.add_argument("--cmaddr", help="IP:port for CS system")
print_("- parsing arguments")
args = parser.parse_args()

print_("args =================================================================")
print_(args)

print_("metadata =============================================================")
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

with open(f"compconf.json", encoding="utf-8") as json_file:
    compconf_data = json.load(json_file)

print_(f" - {compconf_data=}")

genomeFlavor = compconf_data["ASYNC_GA_GENOME_FLAVOR:comptime_string"]
print_(f" - {genomeFlavor=}")
genomePath = f"/cerebraslib/genome/{genomeFlavor}.csl"
print (" - reading genome data from", genomePath)
genomeDataRaw = "".join(
    removeprefix(line, "//!").strip()
    for line in pathlib.Path(genomePath).read_text().split("\n")
    if line.startswith("//!")
) or "{}"
genomeData = eval(genomeDataRaw, {"compconf_data": compconf_data, "pl": pl})
print (f" - {genomeData=}")

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
}
print_(metadata)

print_("do run ===============================================================")
# Path to ELF and simulation output files
runner = SdkRuntime(
    "out", cmaddr=args.cmaddr, suppress_simfab_trace=args.suptrace
)
print_("- SdkRuntime created")

runner.load()
print_("- runner loaded")

runner.run()
print_("- runner run ran")

runner.launch("dolaunch", nonblock=False)
print_("- runner launch complete")

print_(f"- {nonBlock=}, if True waiting for first kernel to finish...")
fossils = []
while nonBlock:
    print_("1", end="")
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
    print_("2", end="")

    genome_data = out_tensors.copy()
    fossils.append(genome_data)
    print_("3", end="")

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
    print_("4", end="")

    cycle_counts = out_tensors.ravel().copy()
    num_complete = np.sum(cycle_counts >= nCycleAtLeast)
    print_("5", end="")

    should_break = num_complete > 0
    print_(f"({num_complete/cycle_counts.size * 100}%)", end="")
    if should_break:
        print_("!")
        break
    else:
        print_("|", end="")
        continue

print_(f"- {nonBlock=}, if True waiting for last kernel to finish...")
while nonBlock:
    print_("1", end="")
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
    print_("2", end="")

    cycle_counts = out_tensors.ravel().copy()
    num_complete = np.sum(cycle_counts >= nCycleAtLeast)
    print_("3", end="")
    should_break = (num_complete == cycle_counts.size)
    print_(f"({num_complete/cycle_counts.size * 100}%)", end="")
    print_(f"{should_break=}")
    if should_break:
        print_("!")
        break
    else:
        print_("|", end="")
        continue

print_("fossils ==============================================================")
print_(f" - {len(fossils)=}")

if len(fossils):
    print_(f"- {fossils[0].shape=}")
    print_("- example hexification")
    hexify_genome_data(fossils[0], verbose=True)

fossils = [
    hexify_genome_data(genome_data, verbose=False)
    for genome_data in tqdm(fossils)
]

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

print_("whoami ===============================================================")
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
print_(whoami_data[:20,:20])

print_("whereami x ===========================================================")
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
print_(whereami_x_data[:20,:20])

print_("whereami y ===========================================================")
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
print_(whereami_y_data[:20,:20])

print_("trait data ===========================================================")
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
print_("traitCounts_data", Counter(traitCounts_data.ravel()))

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
print_("traitCycles_data", Counter(traitCycles_data.ravel()))

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
print_("traitValues_data", str(Counter(traitValues_data.ravel()))[:500])

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
    print_(
        f"trait {trait} total count is",
        group["trait count"].sum()
    )

write_parquet_verbose(
    df,
    "a=traits"
    f"+flavor={genomeFlavor}"
    f"+seed={globalSeed}"
    f"+ncycle={nCycleAtLeast}"
    "+ext=.pqt",
)
del df, traitCounts_data, traitCycles_data, traitValues_data

print_("fitness =============================================================")
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
print_(fitness_data[:20,:20])

print_("genome values ========================================================")
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

print_("cycle counter =======================================================")
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
print_(cycle_counts[:100])


print_("recv counter N ========================================================")
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
print_(recvN[:20,:20])

print_("recv counter S ========================================================")
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
print_(recvS[:20,:20])

print_("recv counter E ========================================================")
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
print_(recvE[:20,:20])

print_("recv counter W ========================================================")
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
print_(recvW[:20,:20])

print_("recv counter sum =====================================================")
recvSum = [*map(sum, zip(recvN.ravel(), recvS.ravel(), recvE.ravel(), recvW.ravel()))]
print_(recvSum[:100])
print_(f"{np.mean(recvSum)=} {np.std(recvSum)=} {sps.sem(recvSum)=}")

print_("send counter N ========================================================")
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
print_(sendN[:20,:20])

print_("send counter S ========================================================")
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
print_(sendS[:20,:20])

print_("send counter E ========================================================")
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
print_(sendE[:20,:20])

print_("send counter W ========================================================")
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
print_(sendW[:20,:20])

print_("send counter sum =====================================================")
sendSum = [*map(sum, zip(sendN.ravel(), sendS.ravel(), sendE.ravel(), sendW.ravel()))]
print_(sendSum[:100])
print_(f"{np.mean(sendSum)=} {np.std(sendSum)=} {sps.sem(sendSum)=}")

print_("tscControl values ====================================================")
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
print_(tscControl_ints[:100])

print_("tscStart values ======================================================")
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
print_(tscStart_ints[:100])

print_("tscEnd values ========================================================")
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
print_(tscEnd_ints[:100])

print_("tsc diffs ============================================================")
print_("--------------------------------------------------------------- ticks")
tsc_ticks = [end - start for start, end in zip(tscStart_ints, tscEnd_ints)]
print_(tsc_ticks[:100])
print_(f"{np.mean(tsc_ticks)=} {np.std(tsc_ticks)=} {sps.sem(tsc_ticks)=}")

print_("-------------------------------------------------------------- seconds")
tsc_sec = [diff / tscTicksPerSecond for diff in tsc_ticks]
print_(tsc_sec[:100])
print_(f"{np.mean(tsc_sec)=} {np.std(tsc_sec)=} {sps.sem(tsc_sec)=}")

print_("---------------------------------------------------- seconds per cycle")
tsc_cysec = [sec / ncy for (sec, ncy) in zip(tsc_sec, cycle_counts)]
print_(tsc_cysec[:100])
print_(f"{np.mean(tsc_cysec)=} {np.std(tsc_cysec)=} {sps.sem(tsc_cysec)=}")

print_("---------------------------------------------------------- cycle hertz")
tsc_cyhz = [1 / cysec for cysec in tsc_cysec]
print_(tsc_cyhz[:100])
print_(f"{np.mean(tsc_cyhz)=} {np.std(tsc_cyhz)=} {sps.sem(tsc_cyhz)=}")

print_("--------------------------------------------------------- ns per cycle")
tsc_cyns = [cysec * 1e9 for cysec in tsc_cysec]
print_(tsc_cyns[:100])
print_(f"{np.mean(tsc_cyns)=} {np.std(tsc_cyns)=} {sps.sem(tsc_cyns)=}")

print_("perf ================================================================")
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
print_("SUCCESS!")
