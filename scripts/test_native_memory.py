#!/usr/bin/env python3
"""Build precise native heap/list regressions with C undefined-behavior checks."""
import concurrent.futures
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parents[1]
    compiler = shlex.split(os.environ.get("CC", "cc"))
    flags = ["-std=c11", "-Wall", "-Wextra", "-Werror", "-fsanitize=undefined", "-ffunction-sections", "-fdata-sections", "-Wl,--gc-sections"]
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
    if suite in ("native_rc_stats", "native_rc_execution"):
        command = command + ["-DMYL_NATIVE_RC_COUNTING=1"]
    if suite == "native_rc_execution":
        command = command + ["-DMYL_NATIVE_RC=1"]
    if "native_heap.c" in sources:
        required = ("native_arena.c", "native_collections.c", "native_text.c",
                    "native_dictionary.c", "native_equal.c", "native_bytes.c",
                    "native_rc.c", "native_rc_stats.c", "native_rc_shapes.c", "native_rc_walk.c",
                    "native_rc_scope.c", "native_rc_transfer.c", "native_rc_alloc.c", "native_rc_values.c")
        at = sources.index("native_heap.c") + 1
        for source in required:
            if source not in sources:
                sources.insert(at, source)
                at += 1
    if "qbe_runtime.c" in sources and "native_cow.c" not in sources:
        sources.append("native_cow.c")
    subprocess.run(
        command + ["-I", str(root / "src")]
        + [str(root / "src" / source) for source in sources]
        + [str(root / "tests" / f"{suite}_test.c")]
        + (["-lm"] if "qbe_runtime.c" in sources else [])
        + ["-o", str(executable)],
        check=True,
    )
    if suite == "native_rc_execution":
        verify_execution(executable)
    else:
        subprocess.run([str(executable)], check=True)


def verify_execution(executable):
    """Real execution reports complete ownership traffic once after all cleanup."""
    expected = None
    for mode in ("success", "trap", "fast"):
        environment = dict(os.environ)
        if mode == "fast":
            # Process-exit allocator reservations are deliberately unswept.
            environment["ASAN_OPTIONS"] = environment.get("ASAN_OPTIONS", "") + ":detect_leaks=0"
        run = subprocess.run([str(executable), mode], check=True, capture_output=True,
                             text=True, env=environment)
        records = [json.loads(line.removeprefix("MYLANG_RC_COUNTS "))
                   for line in run.stderr.splitlines() if line.startswith("MYLANG_RC_COUNTS ")]
        assert len(records) == 1 and not run.stdout, (mode, run.stdout, run.stderr)
        counts = records[0]
        assert counts["version"] == 1 and counts["runtime"] == "rc-v1-counting"
        assert not counts["saturated"]
        assert counts["heap_allocate"] == counts["retire"] == 2
        assert counts["arena_allocate"] == 2
        assert counts["hold_acquire"] == counts["hold_release"] == 1
        assert counts["owner_acquire"] == 1 and counts["owner_release"] == 3
        assert expected is None or counts == expected, (mode, counts, expected)
        expected = counts


def jobs():
    """Suites built at once: `MYLANG_JOBS` when set, else every core."""
    try:
        return max(1, int(os.environ["MYLANG_JOBS"]))
    except (KeyError, ValueError):
        return max(1, os.cpu_count() or 1)


# Each C suite and the runtime sources it links.
SUITES = (
    ("native_file_cleanup", ["native_heap.c", "qbe_runtime.c", "qbe_files.c", "qbe_resources.c", "qbe_stand_ins.c"]),
    ("native_rc_execution", ["native_heap.c", "qbe_runtime.c", "qbe_runtime_rc.c", "qbe_stack.c"]),
    ("native_rc_arena", ["native_heap.c", "native_regions.c"]),
    ("native_rc_stats", ["native_heap.c"]),
    ("native_rc_contract", ["native_rc.c", "native_rc_stats.c", "native_rc_shapes.c", "native_rc_walk.c", "native_rc_scope.c", "native_rc_transfer.c"]),
    ("native_rc_collections", ["native_heap.c", "native_text_methods.c", "native_print.c"]),
    ("native_rc_codecs", ["native_heap.c", "qbe_runtime.c"]),
    ("native_rc_host", ["native_heap.c", "qbe_runtime.c"]),
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
