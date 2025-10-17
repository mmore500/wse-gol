import logging
import typing

from ._pairwise import pairwise


def cslc_wsclust_shim_parse_args(
    args: typing.List[str],
) -> typing.Tuple[str, str]:
    args = [*args, "---dropme"]
    for i, (first, second) in enumerate(pairwise(args)):
        if first == "-h":
            args[i] = "--help"
        if second == "-h":
            args[i + 1] = "--help"
        if first == "-o":
            args[i] = f"---o={second}"
            args[i + 1] = "---dropme"
        if first == "--import-path":
            args[i] = f"---import-path={second}"
            args[i + 1] = "---dropme"

    logging.info(f"fix args: {args}")

    targets = [arg for arg in args if not arg.startswith("--")]
    logging.info(f"targets: {targets}")
    if len(targets) == 0:
        target = None
    elif len(targets) > 1:
        raise ValueError("Expected one target .csl file")
    elif not targets[0].endswith(".csl"):
        raise ValueError("Expected target to be a .csl file")
    else:
        (target,) = targets

    logging.info(f"target: {target}")

    flags = " ".join(filter(lambda arg: arg.startswith("--"), args))
    flags = (
        flags.replace("---o=", "-o ")
        .replace("---import-path=", "--import-path ")
        .replace("---dropme", "")
        .strip()
    )
    logging.info(f"flags: {flags}")

    return target, flags
