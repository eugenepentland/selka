#!/usr/bin/env python3
"""Wall-time scaling of the programs in bench/parity/parallel (PARALLEL.md): Selka, Zig and Rust at 1, 2, 4 and 8 threads.

Builds every port, checks each run's stdout against the program's `.expected` line, and times the timed runs after the
warm-up runs. Run it inside `scripts/build-slot.sh timing`. Usage:

  time_parallel.py --selka SELKA --zig ZIG --rustc RUSTC --work DIR [--runs 5] [--warmups 1]
                   [--threads 1,2,4,8] [--json OUT]

Prints one table per program, the Selka/Zig and Selka/Rust ratios at each thread count, each language's speedup at 8
threads, and the mark PROFILE where Selka at 8 threads is more than 1.25 times Zig.
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PROGRAMS = ["map_work", "group_tasks", "shared_model"]
LANGUAGES = ["selka", "zig", "rust"]
PROFILE_RATIO = 1.25


def build(arguments, cwd):
    """Run one build command; on failure, stop with its output."""
    built = subprocess.run(arguments, cwd=cwd, capture_output=True, text=True, timeout=1800)
    if built.returncode != 0:
        sys.stderr.write(built.stdout + built.stderr)
        raise SystemExit(f"time_parallel: build failed: {' '.join(arguments)}")


def build_all(options):
    """Build each program in each language into the work directory; return {(program, language): binary}."""
    binaries = {}
    os.makedirs(os.path.join(options.work, "bin"), exist_ok=True)
    for program in PROGRAMS:
        source = os.path.join(HERE, program)
        out = os.path.join(options.work, "bin")
        selka = os.path.join(out, f"{program}.selka")
        build([options.selka, "build", source + ".selka", "-o", selka, "--release"], ROOT)
        zig = os.path.join(out, f"{program}.zig-bin")
        build([options.zig, "build-exe", "-OReleaseFast", source + ".zig", f"-femit-bin={zig}"], HERE)
        rust = os.path.join(out, f"{program}.rust-bin")
        build([options.rustc, "-C", "opt-level=3", "-C", "codegen-units=1", "-C", "target-cpu=native", "-C", "panic=abort",
               source + ".rs", "-o", rust], HERE)
        binaries[(program, "selka")] = selka
        binaries[(program, "zig")] = zig
        binaries[(program, "rust")] = rust
    return binaries


def timed_run(binary, threads):
    """Run `binary` with SELKA_THREADS=threads; return (seconds, stdout, exit status)."""
    environment = dict(os.environ, SELKA_THREADS=str(threads))
    start = time.perf_counter()
    finished = subprocess.run([binary], env=environment, capture_output=True, text=True, timeout=900)
    return time.perf_counter() - start, finished.stdout, finished.returncode


def expected(program):
    """The one output line a program prints, from its `.expected` file."""
    with open(os.path.join(HERE, program + ".expected"), encoding="utf-8") as handle:
        return handle.read()


def measure(options, binaries):
    """Time every program, language and thread count; return the nested results and the failures."""
    results, failures = {}, []
    for program in PROGRAMS:
        results[program] = {}
        for language in LANGUAGES:
            results[program][language] = {}
            for threads in options.threads:
                times = []
                for index in range(options.warmups + options.runs):
                    seconds, output, status = timed_run(binaries[(program, language)], threads)
                    if status != 0 or output != expected(program):
                        failures.append(f"{program} {language} at {threads} threads: exit {status}, output {output!r}")
                    if index >= options.warmups:
                        times.append(seconds)
                results[program][language][threads] = {"median": statistics.median(times), "min": min(times), "max": max(times), "runs": times}
    return results, failures


def report(results, options):
    """Print the tables and the ratios; return the lines so the JSON can carry them too."""
    lines = []
    for program in PROGRAMS:
        lines.append(f"\n{program}: median wall seconds (min-max over {options.runs} runs)")
        lines.append("threads  " + "  ".join(f"{language:>22}" for language in LANGUAGES) + "   selka/zig  selka/rust")
        for threads in options.threads:
            cells = []
            for language in LANGUAGES:
                row = results[program][language][threads]
                cells.append(f"{row['median']:8.3f} ({row['min']:.3f}-{row['max']:.3f})")
            selka, zig, rust = (results[program][language][threads]["median"] for language in LANGUAGES)
            mark = ""
            if threads == max(options.threads) and selka > PROFILE_RATIO * zig:
                mark = "  PROFILE"
            lines.append(f"{threads:7d}  " + "  ".join(f"{cell:>22}" for cell in cells) + f"   {selka / zig:9.2f}  {selka / rust:10.2f}{mark}")
        lines.append("speedup at %d threads (1-thread median / %d-thread median):" % (max(options.threads), max(options.threads)))
        for language in LANGUAGES:
            one = results[program][language][min(options.threads)]["median"]
            top = results[program][language][max(options.threads)]["median"]
            lines.append(f"  {language:6s} {one / top:6.2f}x")
    return lines


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--selka", required=True)
    parser.add_argument("--zig", required=True)
    parser.add_argument("--rustc", required=True)
    parser.add_argument("--work", required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--threads", default="1,2,4,8")
    parser.add_argument("--json")
    options = parser.parse_args(argv)
    options.threads = [int(text) for text in options.threads.split(",")]
    for name in ("selka", "zig", "rustc", "work"):
        setattr(options, name, os.path.abspath(getattr(options, name)))
    if options.runs < 5:
        parser.error("the median needs at least five timed runs")
    binaries = build_all(options)
    results, failures = measure(options, binaries)
    lines = report(results, options)
    print("\n".join(lines))
    if options.json:
        document = {"programs": PROGRAMS, "languages": LANGUAGES, "threads": options.threads, "runs": options.runs,
                    "warmups": options.warmups, "cpus": os.cpu_count(), "results": results, "failures": failures}
        with open(options.json, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=1)
    for line in failures:
        print("time_parallel: FAIL " + line)
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
