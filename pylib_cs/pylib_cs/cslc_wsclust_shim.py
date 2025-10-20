import json
import logging
import sys

from cerebras.sdk.client import SdkCompiler
from cerebras.sdk.client import _version as sdk_version

from ._cslc_wsclust_shim_parse_args import cslc_wsclust_shim_parse_args
from ._print_tree import print_tree


if __name__ == "__main__":

    logging.basicConfig(
        datefmt="%Y-%m-%d %H:%M:%S",
        format="%(asctime)s %(levelname)-8s %(message)s",
        level=logging.INFO,
    )

    command, *args = sys.argv
    logging.info(f"command: {args}")
    logging.info(f"raw args: {args}")

    if len(args) == 0:
        print("Wrapper to run cslc CLI on Cerebras Wafer-Scale Cluster.")
        print("Usage: cslc_wsclust_shim.py [cslc args]")
        sys.exit(0)

    target, flags = cslc_wsclust_shim_parse_args(args)

    # adapted from https://sdk.cerebras.net/appliance-mode#compiling
    # Instantiate copmiler using a context manager
    with SdkCompiler(disable_version_check=True) as compiler:
        app_path: str = "."
        csl_main: str = target
        options: str = flags
        out_path: str = "."

        # Launch compile job
        logging.info("compiling...")
        logging.info(f"    sdk version: {sdk_version.__version__}")
        logging.info(f"    {app_path=}")
        logging.info(f"    {csl_main=}")
        logging.info(f"    {options=}")
        logging.info(f"    {out_path=}")
        print_tree(app_path, ".csl")

        artifact_path = compiler.compile(app_path, csl_main, options, out_path)
        logging.info(f"...done! artifact_path: {artifact_path}")

        # Write the artifact_path to a JSON file
        with open("artifact_path.json", "w", encoding="utf8") as f:
            json.dump({"artifact_path": artifact_path}, f)
        logging.info("saved artifact_path to artifact_path.json")
