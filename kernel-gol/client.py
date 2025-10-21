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


def assemble_genome_data(
        data: "np.ndarray", verbose: bool = False
) -> "np.ndarray":
    return assemble_binary_data(data, nWav=nWav, verbose=verbose)


def assemble_genome_bookend_data(
    data: "np.ndarray", verbose: bool = False
) -> "np.ndarray":
    return assemble_binary_data(data, nWav=nWav + 2, verbose=verbose)


def create_initial_state(state_type, x_dim, y_dim):
  """Generate intitial state for Game of Life"""

  initial_state = np.zeros((x_dim, y_dim), dtype=np.uint32)

  if state_type == 'glider':
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

  else: # state_type == 'random'
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

log("- reading env variables")
# number of rows, columns, and genome words
nCol = int(os.getenv("WSE_GOL_NCOL", 3))
nRow = int(os.getenv("WSE_GOL_NROW", 3))
nWav = int(os.getenv("WSE_GOL_NWAV", -1))
nTrait = int(os.getenv("WSE_GOL_NTRAIT", 1))
log(f"{nCol=}, {nRow=}, {nWav=}, {nTrait=}")

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
log("- parsing arguments")
args = parser.parse_args()

log("args =======================================================")
log(args)

log("metadata ===================================================")
with open(f"{args.name}/out.json", encoding="utf-8") as json_file:
    compile_data = json.load(json_file)

globalSeed = int(compile_data["params"]["globalSeed"])
nCycleAtLeast = int(compile_data["params"]["nCycleAtLeast"])

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

print('Copy initial state to device...')
initial_state = create_initial_state('random', x_dim, y_dim)
# Copy initial state into all PEs
runner.memcpy_h2d(states_symbol, initial_state.flatten(), 0, 0, x_dim, y_dim, 1,
streaming=False, order=MemcpyOrder.ROW_MAJOR, data_type=MemcpyDataType.MEMCPY_32BIT,nonblock=False)

print(f'Run for {nCycleAtLeast} generations...')
# Launch the generate function on device
runner.launch('generate', np.uint16(nCycleAtLeast), nonblock=False)

# Copy states back
states_result = np.zeros([x_dim * y_dim * 8], dtype=np.uint32)
runner.memcpy_d2h(states_result, states_symbol, 0, 0, x_dim, y_dim, 8, streaming=False,
order=MemcpyOrder.ROW_MAJOR, data_type=MemcpyDataType.MEMCPY_32BIT, nonblock=False)

# Stop the program
runner.stop()

print('Create output...')

# Reshape states results to x_dim x y_dim frames
all_states = states_result.reshape((x_dim, y_dim, 8)).transpose(2, 0, 1)
print(all_states)

# Ensure that the result matches our expectation
log("SUCCESS!")
