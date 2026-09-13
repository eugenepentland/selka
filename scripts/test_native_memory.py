#!/usr/bin/env python3
"""Build precise native heap/list regressions with C undefined-behavior checks."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    compiler = shlex.split(os.environ.get("CC", "cc"))
    flags = ["-std=c11", "-Wall", "-Wextra", "-Werror", "-fsanitize=undefined"]
    if os.environ.get("MYLANG_TEST_ASAN") == "1":
        flags.append("-fsanitize=address")
    with tempfile.TemporaryDirectory(prefix="mylang-native-memory-") as directory:
        for suite, sources in (
            ("native_heap", ["native_heap.c"]),
            ("native_collections", ["native_heap.c", "native_collections.c"]),
            ("native_text_dictionary", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c"]),
            ("native_equal", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_equal.c"]),
            ("native_bytes", ["native_heap.c", "native_collections.c", "native_text.c", "native_bytes.c"]),
        ):
            executable = Path(directory) / suite
            subprocess.run(
                compiler + flags + ["-I", str(root / "src")]
                + [str(root / "src" / source) for source in sources]
                + [str(root / "tests" / f"{suite}_test.c"), "-o", str(executable)],
                check=True,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
