#!/usr/bin/env python3
"""Build precise native heap/list regressions with C undefined-behavior checks."""
import concurrent.futures
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
        # Each suite is compiled and run on its own; they share nothing but the
        # sources, so they run concurrently and a failure is reported in order.
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs()) as pool:
            outcomes = [pool.submit(run_suite, root, compiler + flags, Path(directory), suite, list(sources))
                        for suite, sources in SUITES]
            for outcome in outcomes:
                outcome.result()


def run_suite(root, command, directory, suite, sources):
    """Compile one C suite against the runtime sources it needs and run it."""
    executable = directory / suite
    if "native_heap.c" in sources:
        required = ("native_arena.c", "native_collections.c", "native_text.c",
                    "native_dictionary.c", "native_equal.c")
        at = sources.index("native_heap.c") + 1
        for source in required:
            if source not in sources:
                sources.insert(at, source)
                at += 1
    subprocess.run(
        command + ["-I", str(root / "src")]
        + [str(root / "src" / source) for source in sources]
        + [str(root / "tests" / f"{suite}_test.c"), "-o", str(executable)],
        check=True,
    )
    subprocess.run([str(executable)], check=True)


def jobs():
    """Suites built at once: `MYLANG_JOBS` when set, else every core."""
    try:
        return max(1, int(os.environ["MYLANG_JOBS"]))
    except (KeyError, ValueError):
        return max(1, os.cpu_count() or 1)


# Each C suite and the runtime sources it links.
SUITES = (
    ("native_heap", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_equal.c", "native_bytes.c"]),
    ("native_collections", ["native_heap.c", "native_collections.c"]),
    ("native_text_dictionary", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c"]),
    ("native_equal", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_equal.c"]),
    ("native_bytes", ["native_heap.c", "native_collections.c", "native_text.c", "native_bytes.c"]),
    ("native_regions", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_equal.c", "native_regions.c"]),
    ("native_arena_chunks", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_equal.c", "native_bytes.c", "native_regions.c"]),
    ("native_print", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_print.c"]),
    ("native_text_methods", ["native_heap.c", "native_collections.c", "native_text.c", "native_text_methods.c"]),
    ("native_text_views", ["native_heap.c", "native_collections.c", "native_text.c", "native_text_methods.c", "native_dictionary.c", "native_equal.c", "native_regions.c"]),
    ("native_scoped", ["native_scoped.c"]),
    ("native_cow", ["native_heap.c", "native_collections.c", "native_text.c", "native_dictionary.c", "native_equal.c", "native_bytes.c", "native_regions.c", "native_cow.c"]),
)


if __name__ == "__main__":
    main()
