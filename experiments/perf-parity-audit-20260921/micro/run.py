#!/usr/bin/env python3
"""Build, qualify and time the matched mylang/Zig micro-kernel suite.

Every kernel exists twice, once as `<name>.my` and once as `<name>.zig`, and
prints exactly one checksum line. The harness builds every arm first, checks
that all arms of a kernel agree byte for byte on that line, measures peak RSS
once per arm, and only then times fresh processes with the arm order shuffled
inside each round. Nothing is built while anything is timed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
DEFAULT_WORK = ROOT / ".tmp/perf-audit-20260921/micro"
MYLANG = ROOT / "zig-out/bin/mylang"
REFERENCE_ARM = "zig-fast"

MYLANG_MODES = {
    "qbe": [],
    "o3": ["--backend", "llvm", "--llvm-opt", "3"],
    "o3-lto": ["--backend", "llvm", "--llvm-opt", "3", "--lto"],
}
ZIG_MODES = {
    "fast": "ReleaseFast",
    "safe": "ReleaseSafe",
}
ALL_MYLANG = ["qbe", "o3", "o3-lto"]
ALL_ZIG = ["fast", "safe"]

GLOBAL_NOTES = [
    "Every Zig kernel takes its loop bound through `common.opaqueN`, a volatile "
    "load that always yields 1, so no kernel loop can be constant-folded away. "
    "The mylang side needs no such guard: neither backend folds these loops.",
    "Each timing sample is a fresh `taskset -c <cpu> <binary>` process with "
    "stdout to /dev/null, so every number carries about 1 ms of process "
    "start-up on both sides.",
    "mylang keeps its overflow, bounds and division checks in ReleaseFast. "
    "`zig-fast` (ReleaseFast) has none of them; `zig-safe` (ReleaseSafe) has "
    "them and is the closer semantic match.",
]

# name, mylang variants, zig variants. A variant is (suffix, source, modes).
KERNELS = [
    {
        "name": "intloop",
        "match_notes": ["Matched: one `+`, one `*`, one `%` per iteration on both sides. mylang checks the add and the multiply for overflow; `zig-fast` does not, `zig-safe` does."],
        "note": "checked integer arithmetic, loop-carried dependency",
        "mylang": [("", "intloop.my", ALL_MYLANG)],
        "zig": [("", "intloop.zig", ALL_ZIG)],
    },
    {
        "name": "calls",
        "match_notes": ["Not fully isolating. The `% 1000003` in the callee costs about as much as the call on both sides, so this kernel lands within noise of `intloop` for every arm: read the *difference* against `intloop`, not the absolute ratio.", "The Zig callee is `noinline`; mylang has no inline control, so an LLVM arm may inline `step` where `zig-fast` cannot. `zig-fast-inline` is the same body without the barrier."],
        "note": "30,000,000 calls to a two-argument leaf function",
        "mylang": [("", "calls.my", ALL_MYLANG)],
        "zig": [("", "calls.zig", ALL_ZIG), ("inline", "calls_inline.zig", ["fast"])],
    },
    {
        "name": "fib",
        "match_notes": ["Matched: the same two-branch double recursion, 29,860,703 calls."],
        "note": "naive fib(36); call/frame protocol at depth",
        "mylang": [("", "fib.my", ALL_MYLANG)],
        "zig": [("", "fib.zig", ALL_ZIG)],
    },
    {
        "name": "records",
        "match_notes": ["Neither side forces `norm1` out of line, so both may inline it; this measures record construction plus by-value passing as the compiler chooses to lower them, not a guaranteed real call."],
        "note": "construct and pass a 3-field value record per iteration",
        "mylang": [("", "records.my", ALL_MYLANG)],
        "zig": [("", "records.zig", ALL_ZIG)],
    },
    {
        "name": "list_append_sum",
        "match_notes": ["Matched shape, different memory managers: mylang grows a traced `list[int]`, Zig grows `std.ArrayList(i64)` over `std.heap.smp_allocator`. The fold is a `for` over the elements on both sides and LLVM may vectorise the Zig one."],
        "note": "16,000,000 int appends, then one fold",
        "mylang": [("", "list_append_sum.my", ALL_MYLANG)],
        "zig": [("", "list_append_sum.zig", ALL_ZIG)],
    },
    {
        "name": "list_records",
        "match_notes": ["Matched: 2,000,000 four-field 32-byte records appended, then ten passes summing field `c`."],
        "note": "2,000,000 32-byte records, ten field-summing passes",
        "mylang": [("", "list_records.my", ALL_MYLANG)],
        "zig": [("", "list_records.zig", ALL_ZIG)],
    },
    {
        "name": "dict_count",
        "match_notes": ["The primary `zig-fast` arm uses `get` + `put`, two hash lookups, to mirror mylang's `counts[key] = counts.get(key, 0) + 1`. `zig-fast-getorput` is the idiomatic single-lookup form and is the fairer picture of what Zig can do.", "Keys are the same 1000 strings `key0`..`key999` on both sides, built before the timed loop.", "Root cause, read off the runtime rather than inferred: `src/native_dictionary.c` stores a dictionary as a flat entry list and its `find()` walks every entry, comparing string keys one by one. A mylang `dict` is an association list with O(n) lookup, not a hash table, so this kernel is comparing an O(K) scan against an O(1) hash and the ratio grows with the key count."],
        "note": "2,000,000 read-modify-writes over 1000 short string keys",
        "mylang": [("", "dict_count.my", ALL_MYLANG)],
        "zig": [
            ("", "dict_count.zig", ALL_ZIG),
            ("getorput", "dict_count_getorput.zig", ["fast"]),
        ],
    },
    {
        "name": "str_build",
        "match_notes": ["mylang appends through `byte_buffer.append_range(piece, 0, 8)`, Zig through `std.ArrayList(u8).appendSlice`. Same piece, same count, same final length; the sampling fold at the end is identical."],
        "note": "16,000,000 eight-byte appends into a growable byte buffer",
        "mylang": [("", "str_build.my", ALL_MYLANG)],
        "zig": [("", "str_build.zig", ALL_ZIG)],
    },
    {
        "name": "alloc_churn",
        "match_notes": ["Four different memory strategies, deliberately: `mylang-*` drops each batch on the tracing GC, `mylang-*-arena` opens `with arena():` per batch, `zig-fast` resets a `std.heap.ArenaAllocator` per batch over `page_allocator`, and `zig-fast-gpa` allocates and frees through `std.heap.smp_allocator`."],
        "note": "1,000,000 batches of build/fold/drop a 16-element list",
        "mylang": [
            ("", "alloc_churn.my", ALL_MYLANG),
            ("arena", "alloc_churn_arena.my", ALL_MYLANG),
        ],
        "zig": [
            ("", "alloc_churn.zig", ALL_ZIG),
            ("gpa", "alloc_churn_gpa.zig", ["fast"]),
        ],
    },
    {
        "name": "float_loop",
        "match_notes": ["Matched: `x = x * 0.999 + sqrt(float(i))` in strict IEEE binary64 order on both sides, printed as `int(x * 1000.0)`. All arms agree byte for byte, so no FMA contraction or reassociation happened on either side."],
        "note": "binary64 multiply-add-sqrt dependency chain",
        "mylang": [("", "float_loop.my", ALL_MYLANG)],
        "zig": [("", "float_loop.zig", ALL_ZIG)],
    },
    {
        "name": "bytes_scan",
        "match_notes": ["Same algorithm, very different codegen: LLVM auto-vectorises the Zig index loop, while mylang reads one bounds-checked octet at a time. The gap is a vectorisation gap, not an algorithmic one."],
        "note": "index an 8 MiB byte string sixteen times, counting one octet",
        "mylang": [("", "bytes_scan.my", ALL_MYLANG)],
        "zig": [("", "bytes_scan.zig", ALL_ZIG)],
    },
]


def arm_name(language: str, mode: str, suffix: str) -> str:
    base = f"{'mylang' if language == 'mylang' else 'zig'}-{mode}"
    return f"{base}-{suffix}" if suffix else base


def planned_arms(kernel: dict) -> list[dict]:
    arms = []
    for suffix, source, modes in kernel["mylang"]:
        for mode in modes:
            arms.append(
                {
                    "arm": arm_name("mylang", mode, suffix),
                    "language": "mylang",
                    "mode": mode,
                    "variant": suffix,
                    "source": source,
                }
            )
    for suffix, source, modes in kernel["zig"]:
        for mode in modes:
            arms.append(
                {
                    "arm": arm_name("zig", mode, suffix),
                    "language": "zig",
                    "mode": mode,
                    "variant": suffix,
                    "source": source,
                }
            )
    return arms


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_arm(kernel: str, arm: dict, work: Path) -> dict:
    binary = work / "bin" / f"{kernel}__{arm['arm']}"
    binary.parent.mkdir(parents=True, exist_ok=True)
    source = HERE / arm["source"]
    if arm["language"] == "mylang":
        cache = work / f"cache-{arm['mode']}"
        command = [
            str(MYLANG),
            "build",
            str(source),
            "-o",
            str(binary),
            "--mode",
            "ReleaseFast",
            *MYLANG_MODES[arm["mode"]],
            "--cache-dir",
            str(cache),
        ]
    else:
        command = [
            "zig",
            "build-exe",
            str(source),
            "-O",
            ZIG_MODES[arm["mode"]],
            f"-femit-bin={binary}",
        ]
    started = time.perf_counter()
    process = subprocess.run(
        command, cwd=str(work), capture_output=True, text=True, timeout=900
    )
    elapsed = time.perf_counter() - started
    record = {
        "arm": arm["arm"],
        "language": arm["language"],
        "mode": arm["mode"],
        "variant": arm["variant"],
        "source": arm["source"],
        "command": command,
        "status": process.returncode,
        "build_seconds": round(elapsed, 3),
        "binary": str(binary),
    }
    if process.returncode != 0 or not binary.exists():
        record["ok"] = False
        record["stderr"] = process.stderr[-8000:]
        record["stdout"] = process.stdout[-2000:]
        print(f"BUILD FAILED {kernel}/{arm['arm']}", file=sys.stderr)
        print(" ".join(command), file=sys.stderr)
        print(process.stderr[-4000:], file=sys.stderr)
        return record
    record["ok"] = True
    record["binary_sha256"] = sha256_of(binary)
    record["binary_bytes"] = binary.stat().st_size
    return record


def qualify(binary: Path, cpu: int) -> dict:
    process = subprocess.run(
        ["taskset", "-c", str(cpu), str(binary)],
        capture_output=True,
        timeout=1800,
    )
    return {
        "status": process.returncode,
        "stdout": process.stdout.decode("utf-8", "replace"),
        "stderr": process.stderr.decode("utf-8", "replace")[-2000:],
        "stdout_sha256": hashlib.sha256(process.stdout).hexdigest(),
    }


def peak_rss_kib(binary: Path, cpu: int, work: Path) -> int | None:
    report = work / "rss.txt"
    with open(report, "w"):
        pass
    with open("/dev/null", "wb") as sink:
        process = subprocess.run(
            [
                "/usr/bin/time",
                "-f",
                "%M",
                "-o",
                str(report),
                "taskset",
                "-c",
                str(cpu),
                str(binary),
            ],
            stdout=sink,
            stderr=subprocess.DEVNULL,
            timeout=1800,
        )
    if process.returncode != 0:
        return None
    text = report.read_text().strip().splitlines()
    return int(text[-1]) if text else None


def time_once(binary: Path, cpu: int, sink) -> float:
    # No `timeout=` here on purpose: subprocess's timeout path polls the child
    # with an exponential backoff capped at 50 ms, which quantises every sample
    # onto a 50 ms grid. Without it the parent blocks in waitpid.
    started = time.perf_counter_ns()
    process = subprocess.Popen(
        ["taskset", "-c", str(cpu), str(binary)],
        stdout=sink,
        stderr=subprocess.DEVNULL,
    )
    status = process.wait()
    elapsed = (time.perf_counter_ns() - started) / 1e6
    if status != 0:
        raise RuntimeError(f"{binary} exited {status}")
    return elapsed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", type=Path, default=DEFAULT_WORK)
    parser.add_argument("--rounds", type=int, default=15)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--cpu", type=int, default=6)
    parser.add_argument("--seed", type=int, default=20260921)
    parser.add_argument("--only", action="append", default=None)
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--json", type=Path, default=HERE / "results.json")
    parser.add_argument("--markdown", type=Path, default=HERE / "results.md")
    options = parser.parse_args()

    work = options.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    kernels = [k for k in KERNELS if not options.only or k["name"] in options.only]

    provenance = {
        "generated_by": "experiments/perf-parity-audit-20260921/micro/run.py",
        "mylang_binary": str(MYLANG),
        "mylang_sha256": sha256_of(MYLANG),
        "git_head": subprocess.run(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
        ).stdout.strip(),
        "zig_version": subprocess.run(
            ["zig", "version"], capture_output=True, text=True
        ).stdout.strip(),
        "zig_path": shutil.which("zig"),
        "cpu": options.cpu,
        "rounds": options.rounds,
        "warmups": options.warmups,
        "seed": options.seed,
        "reference_arm": REFERENCE_ARM,
    }

    results: dict[str, dict] = {}
    for kernel in kernels:
        name = kernel["name"]
        arms = planned_arms(kernel)
        entry = {
            "name": name,
            "note": kernel["note"],
            "match_notes": kernel.get("match_notes", []),
            "arms": {},
            "build_failures": [],
        }
        for arm in arms:
            binary = work / "bin" / f"{name}__{arm['arm']}"
            if options.skip_build and binary.exists():
                record = {
                    "arm": arm["arm"],
                    "language": arm["language"],
                    "mode": arm["mode"],
                    "variant": arm["variant"],
                    "source": arm["source"],
                    "ok": True,
                    "binary": str(binary),
                    "binary_sha256": sha256_of(binary),
                    "binary_bytes": binary.stat().st_size,
                    "command": ["(reused existing binary)"],
                }
            else:
                record = build_arm(name, arm, work)
            entry["arms"][arm["arm"]] = record
            if not record.get("ok"):
                entry["build_failures"].append(arm["arm"])
        results[name] = entry
        print(
            f"built {name}: {len(arms) - len(entry['build_failures'])}/{len(arms)} arms",
            flush=True,
        )

    # Qualification: every arm of a kernel must print the same bytes.
    for name, entry in results.items():
        checksums = {}
        for arm, record in entry["arms"].items():
            if not record.get("ok"):
                continue
            result = qualify(Path(record["binary"]), options.cpu)
            record["qualify"] = result
            checksums[arm] = result["stdout"]
        distinct = sorted(set(checksums.values()))
        entry["checksum_values"] = checksums
        entry["checksum_agrees"] = len(distinct) <= 1
        entry["checksum"] = distinct[0].strip() if distinct else None
        if not entry["checksum_agrees"]:
            print(f"CHECKSUM MISMATCH {name}: {distinct}", file=sys.stderr)
        print(f"qualified {name}: agrees={entry['checksum_agrees']}", flush=True)

    # Peak RSS, once per arm, before the timing phase.
    for name, entry in results.items():
        for arm, record in entry["arms"].items():
            if not record.get("ok"):
                continue
            record["peak_rss_kib"] = peak_rss_kib(
                Path(record["binary"]), options.cpu, work
            )
        print(f"rss {name}", flush=True)

    # Timing. Only kernels whose arms agree are timed.
    rng = random.Random(options.seed)
    timed = [
        name
        for name, entry in results.items()
        if entry["checksum_agrees"] and not entry["build_failures"]
    ]
    with open("/dev/null", "wb") as sink:
        for name in timed:
            entry = results[name]
            live = [a for a, r in entry["arms"].items() if r.get("ok")]
            samples: dict[str, list[float]] = {arm: [] for arm in live}
            order_log = []
            for _ in range(options.warmups):
                order = list(live)
                rng.shuffle(order)
                for arm in order:
                    time_once(Path(entry["arms"][arm]["binary"]), options.cpu, sink)
            for round_index in range(options.rounds):
                order = list(live)
                rng.shuffle(order)
                order_log.append(order)
                for arm in order:
                    samples[arm].append(
                        time_once(
                            Path(entry["arms"][arm]["binary"]), options.cpu, sink
                        )
                    )
            entry["round_order"] = order_log
            for arm in live:
                values = samples[arm]
                entry["arms"][arm]["samples_ms"] = [round(v, 4) for v in values]
                entry["arms"][arm]["median_ms"] = round(statistics.median(values), 3)
                entry["arms"][arm]["min_ms"] = round(min(values), 3)
                entry["arms"][arm]["max_ms"] = round(max(values), 3)
            reference = entry["arms"].get(REFERENCE_ARM, {}).get("median_ms")
            for arm in live:
                median = entry["arms"][arm]["median_ms"]
                entry["arms"][arm]["ratio_vs_zig_fast"] = (
                    round(median / reference, 3) if reference else None
                )
            print(
                f"timed {name}: "
                + ", ".join(
                    f"{arm}={entry['arms'][arm]['median_ms']}ms" for arm in live
                ),
                flush=True,
            )

    payload = {"provenance": provenance, "kernels": results}
    options.json.write_text(json.dumps(payload, indent=2) + "\n")
    write_markdown(options.markdown, payload)
    print(f"wrote {options.json} and {options.markdown}")
    return 0


TABLE_ARMS = [
    "zig-fast",
    "zig-safe",
    "mylang-qbe",
    "mylang-o3",
    "mylang-o3-lto",
]


def write_markdown(path: Path, payload: dict) -> None:
    provenance = payload["provenance"]
    kernels = payload["kernels"]
    lines = [
        "# Matched micro-kernel suite: mylang versus Zig",
        "",
        "Generated by `run.py`; every number below is a fresh process pinned to "
        f"CPU {provenance['cpu']}, stdout to `/dev/null`, "
        f"{provenance['warmups']} warmups then {provenance['rounds']} rounds with "
        "the arm order shuffled inside each round.",
        "",
        f"- mylang: `{provenance['mylang_binary']}` "
        f"sha256 `{provenance['mylang_sha256'][:16]}…`, repo HEAD "
        f"`{provenance['git_head'][:12]}`",
        f"- zig: `{provenance['zig_version']}`",
        "",
        "## Medians (ms)",
        "",
        "| kernel | " + " | ".join(TABLE_ARMS) + " | qbe/zig | o3/zig | o3-lto/zig |",
        "| --- | " + " | ".join("---" for _ in TABLE_ARMS) + " | --- | --- | --- |",
    ]
    for name, entry in kernels.items():
        cells = []
        for arm in TABLE_ARMS:
            record = entry["arms"].get(arm, {})
            cells.append(
                f"{record['median_ms']:.1f}" if record.get("median_ms") else "—"
            )
        ratios = []
        for arm in ("mylang-qbe", "mylang-o3", "mylang-o3-lto"):
            value = entry["arms"].get(arm, {}).get("ratio_vs_zig_fast")
            ratios.append(f"{value:.2f}x" if value else "—")
        lines.append(f"| {name} | " + " | ".join(cells) + " | " + " | ".join(ratios) + " |")

    extras = []
    for name, entry in kernels.items():
        for arm, record in entry["arms"].items():
            if arm not in TABLE_ARMS and record.get("median_ms"):
                extras.append(
                    f"| {name} | {arm} | {record['median_ms']:.1f} | "
                    f"{record.get('ratio_vs_zig_fast')}x |"
                )
    if extras:
        lines += [
            "",
            "## Extra arms",
            "",
            "| kernel | arm | median (ms) | vs zig-fast |",
            "| --- | --- | --- | --- |",
            *extras,
        ]

    lines += [
        "",
        "## Peak RSS (KiB, one run per arm)",
        "",
        "| kernel | " + " | ".join(TABLE_ARMS) + " |",
        "| --- | " + " | ".join("---" for _ in TABLE_ARMS) + " |",
    ]
    for name, entry in kernels.items():
        cells = []
        for arm in TABLE_ARMS:
            value = entry["arms"].get(arm, {}).get("peak_rss_kib")
            cells.append(str(value) if value else "—")
        lines.append(f"| {name} | " + " | ".join(cells) + " |")

    lines += ["", "## Checksums", "", "| kernel | stdout | all arms agree |", "| --- | --- | --- |"]
    for name, entry in kernels.items():
        lines.append(
            f"| {name} | `{entry.get('checksum')}` | {entry.get('checksum_agrees')} |"
        )

    lines += ["", "## Notes", ""]
    for note in GLOBAL_NOTES:
        lines.append(f"- {note}")
    for name, entry in kernels.items():
        for note in entry.get("match_notes", []):
            lines.append(f"- **{name}**: {note}")
    path.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    sys.exit(main())
