import json
import logging
import sys

from cerebras.sdk.client import SdkCompiler


from ._clsc_wsclust_shim import cslc_wsclust_shim_parse_args

if __name__ == "__main__":

    logging.basicConfig(
        datefmt="%Y-%m-%d %H:%M:%S",
        format="%(asctime)s %(levelname)-8s %(message)s",
        level=logging.INFO,
    )

    command, *args = sys.argv
    logging.info(f"command: {args}")
    logging.info(f"raw args: {args}")

    target, flags = cslc_wsclust_shim_parse_args(args)

    # adapted from https://sdk.cerebras.net/appliance-mode#compiling
    # Instantiate copmiler using a context manager
    with SdkCompiler() as compiler:

        # Launch compile job
        logging.info("compiling...")
        artifact_path = compiler.compile(".", target, flags, ".")
        logging.info(f"...done! artifact_path: {artifact_path}")

        # Write the artifact_path to a JSON file
        with open("artifact_path.json", "w", encoding="utf8") as f:
            json.dump({"artifact_path": artifact_path}, f)
        logging.info("saved artifact_path to artifact_path.json")
