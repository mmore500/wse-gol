import os
import pathlib

from rich.tree import Tree as rich_Tree
from rich.console import Console as rich_Console


def print_tree(path: str, ext: str) -> None:
    # 1. Get all matching files
    matching_files = [
        os.path.normpath(os.path.join(root, f))
        for root, _, files in os.walk(
            os.path.abspath(path), topdown=False, followlinks=True
        )
        for f in files
        if f.endswith(ext)
    ]
    if not matching_files:
        return

    # 2. Create set of all required directories (comprehension)
    required_dirs = {
        os.path.normpath(parent)
        for file_path in matching_files
        for parent in pathlib.Path(file_path).parents
    }

    # 3. Build and print filtered tree
    tree = rich_Tree(path)

    def add_nodes(tree: rich_Tree, directory: str) -> None:
        for entry in sorted(os.listdir(directory)):
            full_path = os.path.join(directory, entry)
            if os.path.isdir(full_path) and full_path in required_dirs:
                branch = tree.add(entry + "/")
                add_nodes(branch, full_path)
            elif full_path in matching_files:
                tree.add(entry)

    add_nodes(tree, os.path.abspath(path))
    rich_Console().print(tree)
