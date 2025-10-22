# Major elements of this work are adapted from
# https://sdk.cerebras.net/csl/code-examples/benchmark-game-of-life.html
# which is distributed by Cerebras Systems under Apache 2.0 License
# https://github.com/Cerebras/csl-examples/blob/v1.4.0/LICENSE

print("kernel-gol/client.py #################################################")
print("######################################################################")
import argparse
import atexit
import itertools as it
import json
import logging
import os
import random
import uuid
import shutil
import subprocess
import sys

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


def assemble_binary_data(
    raw_binary_data: "np.ndarray",
    nWav: int,
    verbose: bool = False,
) -> "np.ndarray":
    if verbose:
        log(f"- begin assemble_binary_data...")
        log(f"  - raw_binary_data.dtype={raw_binary_data.dtype}")
        log(f"  - raw_binary_data.shape={raw_binary_data.shape}")
        log(f"  - raw_binary_data.flat[:nWav]={raw_binary_data.flat[:nWav]}")
        log(f"  - nWav={nWav} verbose={verbose}")

        for word in range(nWav):
            log(f"---------------------------------------- binary word {word}")
            values = (inner[word] for outer in raw_binary_data for inner in outer)
            log(str([*it.islice(values, 10)]))

    binary_ints = np.ascontiguousarray(raw_binary_data.astype(">u4").ravel())
    assert binary_ints.shape == (nRow * nCol * nWav,)
    if verbose:
        log("------------------------------------------------ binary u32 ints")
        for binary_int in binary_ints[:10]:
            log(f"{len(binary_ints)=} {binary_int=}")

    binary_strings = binary_ints.view(f'V{nWav * 4}')
    assert binary_strings.shape == (nRow * nCol, )
    if verbose:
        log("------------------------------------------------- binary strings")
        log(f"  - target dtype: V{nWav * 4}")
        for binary_string in binary_strings[:10]:
            log(f"{binary_string=}")

    return binary_strings


def assemble_state_data(
        data: "np.ndarray", verbose: bool = False
) -> "np.ndarray":
    return assemble_binary_data(data, nWav=nWav, verbose=verbose)


def create_initial_state(state_type, x_dim, y_dim):
  """Generate intitial state for Game of Life"""

  initial_state = np.zeros((x_dim, y_dim), dtype=np.uint32)

  if state_type == 'glider':
    log("creating glider initial state...")
    assert x_dim >= 4 and y_dim >=4, \
           'For glider initial state, x_dim and y_dim must be at least 4'

    glider = np.array([[0, 0, 1],
                       [1, 0, 1],
                       [0, 1, 1]])

    for i in range(x_dim//4):
      for j in range(y_dim//4):
        if i%2 == 0 and j%2 == 0:
          initial_state[4*i:4*i+3, 4*j:4*j+3] = glider
        elif i%2 == 0 and j%2 == 1:
          initial_state[4*i:4*i+3, 4*j:4*j+3] = glider[:,::-1]
        elif i%2 == 1 and j%2 == 0:
          initial_state[4*i:4*i+3, 4*j:4*j+3] = glider[::-1,:]
        elif i%2 == 1 and j%2 == 1:
          initial_state[4*i:4*i+3, 4*j:4*j+3] = glider[::-1,:]

  elif state_type == 'gosper':
    log("creating gosper glider gun initial state...")
    # assert x_dim >= 56 and y_dim >=29, \
    #        'For gosper initial state, x_dim and y_dim must be at least 56, 29'

    # https://conwaylife.com/patterns/gosperglidergun.cells
    pattern = [
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
        "..................................O",
        "................................O.O",
        "......................OO......OO............OO..........",
        ".....................O...O....OO............OO",
        "..........OO........O.....O...OO",
        "..........OO........O...O.OO....O.O",
        "....................O.....O.......O",
        ".....................O...O",
        "......................OO",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
       ".",
    ]

    assert max(len(row) for row in pattern) == 56 and len(pattern) == 29
    padded = [row.ljust(56, '.') for row in pattern]
    gosper = np.array([[1 if c == 'O' else 0 for c in row] for row in padded])

    initial_state[:29, :56] = gosper
    assert initial_state.ravel().sum() == sum(row.count('O') for row in pattern)

  else: # state_type == 'random'
    log("creating random initial state...")
    np.random.seed(seed=7)
    initial_state = np.random.binomial(1, 0.5, (x_dim, y_dim)).astype(np.uint32)

  return initial_state


log("- printenv")
for k, v in sorted(os.environ.items()):
    log(f"  - {k}={v}")

log("- setting up temp dir")
# need to add polars to Cerebras python
temp_dir = f"{os.getenv('WSE_GOL_LOCAL_PATH', 'local')}/tmp/{uuid.uuid4()}"
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

    tmp_file = f"{os.getenv('WSE_GOL_LOCAL_PATH', 'local')}/tmp.pqt"
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

def render_ascii_braille(
    grid: "np.ndarray",
    total_rows: int,
    total_cols: int,
    max_render_rows: int = None,
    max_render_cols: int = None,
) -> str:
    """
    Renders the grid as ASCII Braille art.
    Expects grid with shape (total_cols, total_rows).
    """

    # Determine render dimensions
    render_rows = total_rows
    if max_render_rows is not None:
        render_rows = min(total_rows, max_render_rows)

    render_cols = total_cols
    if max_render_cols is not None:
        render_cols = min(total_cols, max_render_cols)

    # Helper to safely get a cell value (handles out-of-bounds)
    def get_cell(r: int, c: int) -> int:
        # Check against *total* dims
        if r < total_rows and c < total_cols:
            return grid[c][r] # Access as [col][row]
        return 0  # Treat out-of-bounds as 'off'

    output = []
    # Iterate in 4-row, 2-column steps
    for r in range(0, render_rows, 4):
        line = ""
        for c in range(0, render_cols, 2):
            val = 0

            # Braille dot mapping (base Unicode 0x2800)
            # Left column dots (1, 2, 3, 7)
            if get_cell(r, c):     val |= 0x01 # dot 1
            if get_cell(r + 1, c): val |= 0x02 # dot 2
            if get_cell(r + 2, c): val |= 0x04 # dot 3
            if get_cell(r + 3, c): val |= 0x40 # dot 7

            # Right column dots (4, 5, 6, 8)
            if get_cell(r, c + 1):     val |= 0x08 # dot 4
            if get_cell(r + 1, c + 1): val |= 0x10 # dot 5
            if get_cell(r + 2, c + 1): val |= 0x20 # dot 6
            if get_cell(r + 3, c + 1): val |= 0x80 # dot 8

            # 0x2800 is the Unicode offset for the blank Braille pattern
            line += chr(0x2800 + val)

        output.append(line)

    return "\n".join(output)


log("- reading env variables")
# number of rows, columns, and genome words
nCol = int(os.getenv("WSE_GOL_NCOL", 3))
nRow = int(os.getenv("WSE_GOL_NROW", 3))
nWav = int(os.getenv("WSE_GOL_NWAV", 8))
nTrait = int(os.getenv("WSE_GOL_NTRAIT", 1))
log(f"{nCol=}, {nRow=}, {nWav=}, {nTrait=}")

surfWavs = 2
nSurf = 3
assert nWav == 8 and surfWavs == 2 and nSurf == 3  # currently hardcoded
assert nWav == surfWavs * nSurf + 2  # currently hardcoded

dstream_algo = "hybrid_0_steady_1_tilted_2_algo"
assert dstream_algo == "hybrid_0_steady_1_tilted_2_algo"  # hardcoded

# PE grid dimensions
x_dim = nCol
y_dim = nRow

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
parser.add_argument('--initial-state', choices=['glider', 'random', 'gosper'], default='glider')
parser.add_argument("--ncycle", default=40, type=int, help="run duration")
log("- parsing arguments")
args = parser.parse_args()

log("args =======================================================")
log(args)

log("metadata ===================================================")
with open(f"{args.name}/out.json", encoding="utf-8") as json_file:
    compile_data = json.load(json_file)

globalSeed = int(compile_data["params"]["globalSeed"])
nCycleAtLeast = args.ncycle

with open("compconf.json", encoding="utf-8") as json_file:
    compconf_data = json.load(json_file)

log(f" - applying globalSeed={globalSeed}")
random.seed(globalSeed)
np.random.seed(globalSeed)

log(f" - {compconf_data=}")

# traitLoggerNumBits = int(compconf_data["CEREBRASLIB_TRAITLOGGER_NUM_BITS:u32"])
# assert bin(traitLoggerNumBits)[2:].count("1") == 1
# traitLoggerDstreamAlgoName = compconf_data[
#     "CEREBRASLIB_TRAITLOGGER_DSTREAM_ALGO_NAME:comptime_string"
# ]
# log(f" - {traitLoggerNumBits=} {traitLoggerDstreamAlgoName=}")

metadata = {
    "globalSeed": (globalSeed, pl.UInt32),
    "nCol": (nCol, pl.UInt16),
    "nRow": (nRow, pl.UInt16),
    "nWav": (nWav, pl.UInt8),
    "nTrait": (nTrait, pl.UInt8),
    "nCycle": (nCycleAtLeast, pl.UInt32),
    "replicate": (str(uuid.uuid4()), pl.Categorical),
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

states_symbol = runner.get_id('states')

log('Copy initial state to device...')
initial_state = create_initial_state(args.initial_state, x_dim, y_dim)
log(f"initial_state sum: {initial_state.ravel().sum()}")
log(f"initial_state shape: {initial_state.shape}")
log(f"initial_state dtype: {initial_state.dtype}")

log("\npartial initial ascii rendering")
partial_initial_render = render_ascii_braille(
    initial_state, nRow, nCol, max_render_rows=100, max_render_cols=100
)
log(partial_initial_render)

log("\nfull initial ascii rendering")
full_initial_render = render_ascii_braille(initial_state, nRow, nCol)
log(full_initial_render)


# Copy initial state into all PEs
runner.memcpy_h2d(states_symbol, initial_state.flatten(), 0, 0, x_dim, y_dim, 1,
streaming=False, order=MemcpyOrder.ROW_MAJOR, data_type=MemcpyDataType.MEMCPY_32BIT,nonblock=False)

log(f'Run for {nCycleAtLeast} generations...')
if nCycleAtLeast != 0:
    # Launch the generate function on device
    runner.launch('generate', np.uint16(nCycleAtLeast), nonblock=False)

# Copy states back
states_result = np.zeros([x_dim * y_dim * nWav], dtype=np.uint32)
runner.memcpy_d2h(states_result, states_symbol, 0, 0, x_dim, y_dim, nWav, streaming=False,
order=MemcpyOrder.ROW_MAJOR, data_type=MemcpyDataType.MEMCPY_32BIT, nonblock=False)

# Stop the program
runner.stop()

log('Log output...')
# Reshape states results to x_dim x y_dim frames
all_states = states_result.reshape((x_dim, y_dim, nWav)).transpose(2, 0, 1)

grid = all_states[0]
log(f"num cells set 0: {all_states[0].ravel().sum()}")
log(f"num cells set 1: {all_states[0].size - all_states[0].ravel().sum()}")
log(f"grid shape: {grid.shape}")
log(f"grid dtype: {grid.dtype}")
log(f"grid max: {grid.max()}")
log(f"grid min: {grid.min()}")
assert set(map(int, grid.ravel())).issubset({0, 1})

log("\npartial output ascii rendering")
partial_output_render = render_ascii_braille(
    grid, nRow, nCol, max_render_rows=100, max_render_cols=100
)
log(partial_output_render)

log("\nfull output ascii rendering")
full_output_render = render_ascii_braille(grid, nRow, nCol)
log(full_output_render)


log("\nstate layers")
log(all_states[:, :10, :10])  # log first 5x5 of each wave

log("Build state dataframe...")
# states_z = states_result.reshape((x_dim * y_dim, nWav))
# log(states_z[:5, :])  # log first 5 rows
# log(f" - states_z.dtype={states_z.dtype}")
# log(f" - states_z.shape={states_z.shape}")

log("- verbose assemble_state_data")
assembled_state_data = assemble_state_data(
   states_result.reshape((x_dim, y_dim, nWav)),
   verbose=True,
)
log(f"  - assembled_state_data.dtype={assembled_state_data.dtype}")
log(f"  - assembled_state_data.shape={assembled_state_data.shape}")

log(f" - casting assembled_state_data to object")
assembled_state_data = assembled_state_data.astype(object)
log(f"  - assembled_state_data.dtype={assembled_state_data.dtype}")
log(f"  - assembled_state_data.shape={assembled_state_data.shape}")

log(f" - reshaping assembled_state_data")
assembled_state_data = assembled_state_data.reshape((x_dim, y_dim))
log(f"  - assembled_state_data.dtype={assembled_state_data.dtype}")
log(f"  - assembled_state_data.shape={assembled_state_data.shape}")

log(" - creating indices")
positions = np.arange(x_dim * y_dim, dtype=np.uint32).reshape((x_dim, y_dim))
rows, cols = np.indices(assembled_state_data.shape)
log(" - creating DataFrame")
df = pl.DataFrame({
    "data_raw": pl.Series(assembled_state_data.ravel(), dtype=pl.Binary),
    "is_extant": False,
    "position": pl.Series(positions.ravel(), dtype=pl.UInt32),
    "row": pl.Series(rows.ravel(), dtype=pl.UInt16),
    "col": pl.Series(cols.ravel(), dtype=pl.UInt16),
}).with_columns([
    pl.lit(value, dtype=dtype).alias(key)
    for key, (value, dtype) in metadata.items()
])
log(f" - data_raw: {df['data_raw'].head(3)}")
assert (df["data_raw"].bin.size(unit="b") == nWav * 4).all()

log(f" - encoding {len(df)} binary fossil rows to hex...")
df = df.with_columns(
    data_hex=pl.col("data_raw").bin.encode("hex"),
).drop("data_raw")
log(f" - ... done!")

log(f" - data_hex: {df['data_hex'].head(3)}")
assert (df["data_hex"].str.len_chars() == nWav * 8).all()
assert (df["data_hex"].str.len_bytes() == nWav * 8).all()
assert (df["data_hex"].str.contains("^[0-9a-fA-F]+$")).all()

for i in range(nSurf):
    log(f"saving surface {i}")
    data_slice = pl.concat_str(
       pl.col("data_hex").str.head(16),  # GOL state and counter
       pl.col("data_hex").str.slice(16 + 8 * i * surfWavs, surfWavs * 8),
    )
    df_surf = df.with_columns(
        dstream_algo=pl.lit(dstream_algo, dtype=pl.Categorical),
        dstream_storage_bitoffset=pl.lit(64, dtype=pl.UInt16),
        dstream_storage_bitwidth=pl.lit(surfWavs * 32, dtype=pl.UInt16),
        dstream_S=pl.lit(surfWavs * 32, dtype=pl.UInt16),
        dstream_T_bitoffset=pl.lit(32, dtype=pl.UInt16),
        dstream_T_bitwidth=pl.lit(32, dtype=pl.UInt16),
        gol_state=pl.col("data_hex").str.slice(0, 8).str.to_integer(base=16),
        data_hex=data_slice,
    )
    write_parquet_verbose(
        df_surf,
        f"a=surfaces+i={i}+ext=.pqt",
    )

del df, df_surf

log("SUCCESS!")
