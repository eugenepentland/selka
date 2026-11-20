#!/usr/bin/env python3
"""Throughput of the Selka lexer against the Zig lexer on the same files held in memory.

    python3 bench/selfhost/lexer_throughput.py [--compiler PATH] [--rounds 15] [--sessions 3]
                                               [--out DIR] [--list FILE] [--repeat N] [--variant LABEL=BINARY]...

Both programs read every file of the list first and then time, per round, over all of them:

* tokenize: `lexer.tokenize` (Selka) against `lexer.lexRange` over the whole file (Zig);
* layout:   `lexer.lower` (Selka) against `lex - lexRange` (Zig; its layout pass is private to
            src/python_layout.zig and `lex` runs it, so the Zig figure is a difference of two
            medians taken on the same rounds);
* lex:      `lexer.lex` against `lexer.lex`, the two passes together.

The Selka program is built with `selka build --release` (one optimized unit) and the Zig twin with
`zig build-exe -OReleaseFast`. Sessions interleave the two arms (zig, selka, zig, selka, ...) so a change
in machine load reaches both. This is NOT a timing window: it runs under ordinary admission on a shared
machine, takes medians of `sessions x rounds` samples per phase and reports the spread (p10 to p90) so the
reader can judge the noise. A row whose ratio exceeds 1.10 is a `perf` item for the language (stage-1 S11).
`--variant LABEL=BINARY` adds another program that speaks the Selka program's protocol (for example the same
LLVM unit with one change, to attribute a ratio to it); it is timed in every session beside the other two and
gets its own column. Round 0 of every run warms up and is discarded. The list defaults to every file of the in-tree syntax
corpus that lexes.
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "selfhost" / "tests"))
import syntax_parity as sp  # noqa: E402

THRESHOLD = 1.10
PHASES = ("tokenize", "layout", "lex")


def corpus_list(compiler: Path, repeat: int, destination: Path) -> tuple[int, int]:
    """Write the paths of every in-tree corpus file that lexes, `repeat` times over; return (files, bytes)."""
    entries, _ = sp.load_corpus(sp.CORPUS, in_tree=True)
    paths = []
    for entry in entries:
        if subprocess.run([str(compiler), "dump-tokens", entry.argument], cwd=ROOT, capture_output=True).returncode == 0:
            paths.append(entry.argument)
    total = sum((ROOT / p).stat().st_size for p in paths) * repeat
    destination.write_text("\n".join(paths * repeat) + "\n")
    return len(paths) * repeat, total


def build(compiler: Path, scratch: Path, zig: str) -> tuple[Path, Path]:
    twin, program = scratch / "lexer_twin", scratch / "lexer_bench"
    subprocess.run([
        zig, "build-exe", "-OReleaseFast", "--dep", "lexer", f"-Mroot={ROOT / 'bench/selfhost/lexer_twin.zig'}",
        f"-Mlexer={ROOT / 'src/lexer.zig'}", f"-femit-bin={twin}", "--cache-dir", str(scratch / "zcache"),
    ], cwd=ROOT, check=True)
    subprocess.run([str(compiler), "build", str(ROOT / "selfhost/frontend/lexer_bench.selka"), "-o", str(program), "--release",
                    "--cache-dir", str(scratch / "cache")], cwd=ROOT, check=True)
    return twin, program


def samples(binary: Path, listing: Path, rounds: int) -> list[dict]:
    done = subprocess.run([str(binary), str(listing), str(rounds)], cwd=ROOT, capture_output=True, text=True, check=True)
    rows = [json.loads(line) for line in done.stdout.splitlines()]
    return [row for row in rows if row["round"] > 0]


def quantile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(q * len(ordered)))]


def phases(rows: list[dict], layout_from_lex: bool) -> dict[str, list[float]]:
    """Per-phase sample lists; the Zig twin's layout is `lex - tokenize`, the Selka programs report it."""
    return {
        "tokenize": [r["tokenize_ns"] for r in rows],
        "layout": [r["lex_ns"] - r["tokenize_ns"] if layout_from_lex else r["lower_ns"] for r in rows],
        "lex": [r["lex_ns"] for r in rows],
    }


def summarize(zig: list[dict], arms: dict[str, list[dict]]) -> list[dict]:
    """One row per phase and Selka-protocol arm: medians, p10-p90 and the ratio to the Zig twin."""
    rows = []
    base = phases(zig, True)
    for label, samples_ in arms.items():
        got = phases(samples_, False)
        for phase in PHASES:
            z, s = statistics.median(base[phase]), statistics.median(got[phase])
            rows.append({
                "arm": label, "phase": phase, "zig_ms": z / 1e6, "arm_ms": s / 1e6, "ratio": s / z,
                "zig_p10_p90_ms": [quantile(base[phase], .1) / 1e6, quantile(base[phase], .9) / 1e6],
                "arm_p10_p90_ms": [quantile(got[phase], .1) / 1e6, quantile(got[phase], .9) / 1e6],
                "samples": [len(base[phase]), len(got[phase])],
            })
    return rows


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", type=Path, default=ROOT / "zig-out" / "bin" / "selka")
    parser.add_argument("--zig", default=os.environ.get("SELKA_ZIG") or os.environ.get("ZIG") or "zig")
    parser.add_argument("--rounds", type=int, default=15)
    parser.add_argument("--sessions", type=int, default=3)
    parser.add_argument("--repeat", type=int, default=1, help="read every file this many times over (more bytes per round)")
    parser.add_argument("--list", type=Path, help="a list of source files that lex, instead of the corpus")
    parser.add_argument("--out", type=Path, help="write the full record to OUT/lexer-throughput.json")
    parser.add_argument("--variant", action="append", default=[], metavar="LABEL=BINARY", help="another program with the Selka protocol")
    args = parser.parse_args(argv)
    compiler = args.compiler.resolve()
    variants = {}
    for spec in args.variant:
        label, _, binary = spec.partition("=")
        variants[label] = Path(binary).resolve()
    with tempfile.TemporaryDirectory() as scratch_name:
        scratch = Path(scratch_name)
        listing = scratch / "list.txt"
        if args.list:
            listing.write_text(args.list.read_text())
            names = [n for n in listing.read_text().splitlines() if n]
            count, size = len(names), sum((ROOT / n).stat().st_size for n in names)
        else:
            count, size = corpus_list(compiler, args.repeat, listing)
        twin, program = build(compiler, scratch, args.zig)
        binaries = {"selka": program, **variants}
        zig_rows: list[dict] = []
        arm_rows: dict[str, list[dict]] = {label: [] for label in binaries}
        for _ in range(args.sessions):
            zig_rows += samples(twin, listing, args.rounds)
            for label, binary in binaries.items():
                arm_rows[label] += samples(binary, listing, args.rounds)
    table = summarize(zig_rows, arm_rows)
    print(f"{count} files, {size} bytes in memory; {args.sessions} sessions x {args.rounds} rounds, interleaved, ordinary admission (no timing window)")
    print(f"{'arm':10} {'phase':9} {'zig ms':>8} {'arm ms':>8} {'ratio':>6}  {'zig p10-p90':>15} {'arm p10-p90':>15}")
    for row in table:
        flag = "  > 1.10" if row["ratio"] > THRESHOLD else ""
        print(f"{row['arm']:10} {row['phase']:9} {row['zig_ms']:8.2f} {row['arm_ms']:8.2f} {row['ratio']:6.2f}  "
              f"{row['zig_p10_p90_ms'][0]:6.2f}-{row['zig_p10_p90_ms'][1]:<7.2f} {row['arm_p10_p90_ms'][0]:6.2f}-{row['arm_p10_p90_ms'][1]:<7.2f}{flag}")
    for row in (r for r in table if r["phase"] == "lex"):
        print(f"throughput over the lex phase: zig {size / row['zig_ms'] / 1e3:.0f} MB/s, {row['arm']} {size / row['arm_ms'] / 1e3:.0f} MB/s")
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        (args.out / "lexer-throughput.json").write_text(json.dumps({
            "files": count, "bytes": size, "tokens_after_layout": zig_rows[0]["tokens"],
            "sessions": args.sessions, "rounds": args.rounds, "rows": table, "zig": zig_rows, "arms": arm_rows}, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
