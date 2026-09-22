#!/usr/bin/env python3
"""Per-call usage for one participant run, read from the harness session log.

The envelope charges *generated tokens per model call*, so the calibration needs
the calls themselves, not a session total. This module recovers them from the
harness session log (`~/.dsh/sessions/<slug>/session-*/session.v3.jsonl.zstd`):
one `Usage` per assistant message, in the order the provider billed them.

Matching follows the rule `experiments/cascade/run.py` uses: the `cwd` recorded
in the session header must equal the run's `work_dir`, and the session must not
have started before the run's `started_utc` (5 s of slack, because the launch
timestamp and the session header are written by different processes). Every
session log that matches a working copy is included, in start order, so a run
whose harness wrote more than one log (a retry, a delegated child) is summed the
same way the runner's own aggregation sums it — never silently truncated to the
first file.

Provider mapping, verified call for call against the runner's own totals:

    inputTokens      -> input_tokens        (prompt minus cache hits, as reported)
    cacheReadTokens  -> cache_read_tokens
    outputTokens     -> output_tokens      (completion; reasoning is inside it)
    reasoningTokens  -> reasoning_tokens   (a *detail* of output_tokens)

`generated` is `output_tokens` and is never `output + reasoning`; `input_volume`
is `input + cache_read`. A partially written final line — a live session, or a
truncated frame — is skipped rather than repaired, and the skip is counted in
`malformed_lines` so a caller can tell a clean read from a short one.

    python3 experiments/diagnostic-feedback-m2/m2_usage.py --work-dir DIR --since ISO
    python3 experiments/diagnostic-feedback-m2/m2_usage.py --selftest
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from budget import Usage  # noqa: E402

SESSION_ROOT = Path.home() / ".dsh" / "sessions"
SLACK_SECONDS = 5.0
USAGE_FIELDS = ("inputTokens", "outputTokens", "reasoningTokens", "cacheReadTokens", "totalTokens")


@dataclass
class Call:
    """One assistant call, with the usage the provider reported for it."""
    index: int                      # position within its session log, from 0
    usage: Usage
    time_ms: int | None = None      # the record's own timestamp, when present
    step: int | None = None         # the harness step the call belongs to
    session: str = ""               # session directory the call came from


@dataclass
class SessionRead:
    """Everything recovered for one matching session log."""
    path: Path
    session_id: str = ""
    created_ms: int | None = None
    delegation_depth: int | None = None
    cwd: str = ""
    calls: list[Call] = field(default_factory=list)
    malformed_lines: int = 0
    decode_note: str = ""


def parse_time(value) -> float:
    """A `started_utc` string (or ms epoch) as seconds since the epoch."""
    if isinstance(value, (int, float)):
        return float(value) / 1000.0 if value > 1e11 else float(value)
    text = str(value).strip().replace("Z", "+00:00")
    moment = datetime.fromisoformat(text)
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    return moment.timestamp()


def slug_for(work_dir: Path | str) -> str:
    """The session-directory name the harness derives from a working copy."""
    return "--" + str(work_dir).replace("/", "-") + "--"


def decode_log(path: Path) -> tuple[str, str]:
    """The log's text, plus a note when it could not be decoded cleanly.

    A live or truncated zstd frame still yields its decoded prefix on stdout, so
    that prefix is used and the partial frame is noted rather than discarded.
    """
    if path.name.endswith(".zstd"):
        done = subprocess.run(["zstd", "-dc", "--", str(path)], capture_output=True)
        if done.returncode == 0:
            return done.stdout.decode(errors="replace"), ""
        if done.stdout:
            return done.stdout.decode(errors="replace"), "partial-zstd-frame"
    try:
        return path.read_text(errors="replace"), ("plain" if path.name.endswith(".zstd") else "")
    except OSError as problem:
        return "", f"unreadable: {problem}"


def read_session(path: Path, index: int = 0) -> SessionRead:
    """Parse one session log into its header facts and its per-call usage."""
    text, note = decode_log(path)
    read = SessionRead(path=path, decode_note=note)
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            # A partially written final line is the expected case here: count it,
            # keep everything already recovered, and do not fabricate a call.
            read.malformed_lines += 1
            continue
        kind = record.get("type")
        if kind == "session":
            read.session_id = record.get("id", "")
            read.cwd = record.get("cwd", "")
            created = record.get("createdAt")
            read.created_ms = int(created) if isinstance(created, (int, float)) else None
            depth = record.get("delegationDepth")
            read.delegation_depth = depth if isinstance(depth, int) else None
        elif kind == "assistant/message":
            data = record.get("data") or {}
            usage = data.get("usage") or {}
            if not any(isinstance(usage.get(key), (int, float)) for key in USAGE_FIELDS):
                continue
            def amount(key: str) -> int:
                value = usage.get(key)
                return int(value) if isinstance(value, (int, float)) else 0
            stamp = record.get("time")
            step = data.get("step")
            read.calls.append(Call(
                index=len(read.calls),
                usage=Usage(input_tokens=amount("inputTokens"),
                            cache_read_tokens=amount("cacheReadTokens"),
                            output_tokens=amount("outputTokens"),
                            reasoning_tokens=amount("reasoningTokens")),
                time_ms=int(stamp) if isinstance(stamp, (int, float)) else None,
                step=step if isinstance(step, int) else None,
                session=str(path.parent)))
    return read


LOG_PATTERNS = ("session-*/session.v3.jsonl.zstd", "session-*/session.v3.jsonl")


def candidate_paths(work_dir: Path | str, root: Path, since_s: float) -> list[Path]:
    """Session logs that could belong to a working copy, cheapest search first.

    The session directory name encodes the working copy, so the direct lookup is
    one directory read; only when that directory is absent is the whole session
    root scanned (filtered by modification time). An uncompressed
    `session.v3.jsonl` is accepted too, so a log written by a test fixture or a
    harness that stopped compressing still reads.
    """
    direct = root / slug_for(work_dir)
    if direct.is_dir():
        return sorted({path for pattern in LOG_PATTERNS for path in direct.glob(pattern)})
    found = []
    for path in sorted({path for pattern in LOG_PATTERNS for path in root.glob("*/" + pattern)}):
        try:
            if path.stat().st_mtime >= since_s - SLACK_SECONDS:
                found.append(path)
        except OSError:
            continue
    return found


def iter_calls(work_dir: Path | str, started_utc, root: Path = SESSION_ROOT,
               slack_seconds: float = SLACK_SECONDS):
    """Yield every model call of a run's sessions, in order, as `Usage`.

    Sessions are ordered by their header's creation time; calls within a session
    keep the log's own order. Logs whose header does not carry this `cwd`, or
    that started before `started_utc` (less slack), are ignored.
    """
    since_s = parse_time(started_utc)
    sessions = []
    for path in candidate_paths(work_dir, root, since_s):
        read = read_session(path)
        if read.cwd != str(work_dir):
            continue
        stamped = read.created_ms / 1000.0 if read.created_ms is not None else None
        if stamped is None:
            try:
                stamped = path.stat().st_mtime
            except OSError:
                continue
        if stamped < since_s - slack_seconds:
            continue
        sessions.append((stamped, str(path), read))
    for _, _, read in sorted(sessions, key=lambda item: (item[0], item[1])):
        for call in read.calls:
            yield call.usage


def read_calls(work_dir: Path | str, started_utc, root: Path = SESSION_ROOT,
               slack_seconds: float = SLACK_SECONDS) -> dict:
    """The full recovery record for one run: sessions, calls, and what was lost."""
    since_s = parse_time(started_utc)
    sessions = []
    for path in candidate_paths(work_dir, root, since_s):
        read = read_session(path)
        if read.cwd != str(work_dir):
            continue
        stamped = read.created_ms / 1000.0 if read.created_ms is not None else None
        if stamped is None:
            try:
                stamped = path.stat().st_mtime
            except OSError:
                continue
        if stamped < since_s - slack_seconds:
            continue
        sessions.append((stamped, str(path), read))
    sessions.sort(key=lambda item: (item[0], item[1]))
    calls = [call for _, _, read in sessions for call in read.calls]
    return {
        "work_dir": str(work_dir),
        "since_utc": str(started_utc),
        "matched": bool(sessions),
        "sessions": [{"path": str(read.path), "session_id": read.session_id,
                      "created_utc": (datetime.fromtimestamp(stamp, timezone.utc).isoformat()
                                      if read.created_ms is not None else None),
                      "delegation_depth": read.delegation_depth,
                      "calls": len(read.calls), "malformed_lines": read.malformed_lines,
                      "decode_note": read.decode_note}
                     for stamp, _, read in sessions],
        "calls": [call.usage for call in calls],
        "call_meta": [{"index": call.index, "time_ms": call.time_ms, "step": call.step,
                       "session": call.session} for call in calls],
        "malformed_lines": sum(read.malformed_lines for _, _, read in sessions),
        "generated": sum(call.usage.generated for call in calls),
        "input_volume": sum(call.usage.input_volume for call in calls),
    }


# --------------------------------------------------------------------------
# selftest


def selftest() -> tuple[int, int, list[str]]:
    """Arithmetic and ordering properties, on synthetic session logs."""
    import shutil

    checks: list[tuple[str, bool, str]] = []
    scratch = HERE / ".tmp" / "m2-usage-selftest"

    def check(name: str, condition: bool, detail: str = "") -> None:
        checks.append((name, bool(condition), detail))
        print(f"  {'ok  ' if condition else 'FAIL'} {name}{'' if condition else '  ' + detail}")

    def line(kind: str, **payload) -> str:
        return json.dumps({"type": kind, **payload})

    def call_line(uncached: int, cached: int, output: int, reasoning: int, time_ms: int, step: int) -> str:
        return line("assistant/message", time=time_ms,
                    data={"step": step, "usage": {"inputTokens": uncached, "cacheReadTokens": cached,
                                                  "outputTokens": output, "reasoningTokens": reasoning,
                                                  "totalTokens": uncached + cached + output}})

    try:
        shutil.rmtree(scratch, ignore_errors=True)
        root = scratch / "sessions"
        work = scratch / "work" / "case-1"
        work.mkdir(parents=True)
        good = root / slug_for(work) / "session-aaa"
        good.mkdir(parents=True)
        started = "2026-09-19T10:00:00+00:00"
        created = int(parse_time(started) * 1000) + 1000
        body = [
            line("session", version=3, id="session-aaa", createdAt=created, cwd=str(work), delegationDepth=0),
            call_line(100, 900, 50, 40, created + 10, 1),
            call_line(20, 1000, 200, 150, created + 20, 2),
            call_line(5, 1100, 300, 0, created + 30, 3),
        ]
        (good / "session.v3.jsonl").write_text("\n".join(body) + "\n")

        empty_work = scratch / "work" / "case-2"
        empty_work.mkdir(parents=True)
        other = root / slug_for(empty_work) / "session-bbb"
        other.mkdir(parents=True)
        (other / "session.v3.jsonl").write_text(
            "\n".join([line("session", id="session-bbb", createdAt=created, cwd=str(empty_work)),
                       call_line(1, 1, 1, 1, created, 1)]) + "\n")

        # a session that started well before the run belongs to an earlier run
        old_work = scratch / "work" / "case-3"
        old_work.mkdir(parents=True)
        stale = root / slug_for(old_work) / "session-ccc"
        stale.mkdir(parents=True)
        (stale / "session.v3.jsonl").write_text(
            "\n".join([line("session", id="session-ccc", createdAt=created - 3_600_000, cwd=str(old_work)),
                       call_line(7, 7, 7, 7, created, 1)]) + "\n")

        read = read_calls(work, started, root=root)
        calls = read["calls"]

        # (1) ordering: log order, one Usage per assistant call
        check("calls come back in log order, one per assistant call",
              [call.output_tokens for call in calls] == [50, 200, 300]
              and [meta["step"] for meta in read["call_meta"]] == [1, 2, 3],
              str([call.output_tokens for call in calls]))

        # (2) provider field mapping
        first = calls[0]
        check("provider fields map without transformation",
              first.input_tokens == 100 and first.cache_read_tokens == 900
              and first.output_tokens == 50 and first.reasoning_tokens == 40,
              str(first.as_dict()))

        # (3) arithmetic: generated is output alone, volume is uncached + cached
        check("generated counts output once and reasoning is not added again",
              [call.generated for call in calls] == [50, 200, 300]
              and read["generated"] == 550
              and read["input_volume"] == (100 + 900) + (20 + 1000) + (5 + 1100),
              f"generated={read['generated']} volume={read['input_volume']}")
        check("input_volume is the sum of its two parts for every call",
              all(call.input_volume == call.input_tokens + call.cache_read_tokens for call in calls))

        # (4) the ordering generator agrees with the collected list
        streamed = list(iter_calls(work, started, root=root))
        check("the incremental generator yields the same calls in the same order",
              [call.output_tokens for call in streamed] == [50, 200, 300],
              str([call.output_tokens for call in streamed]))

        # (5) a partially written last line is skipped, not repaired
        partial = root / slug_for(work) / "session-ddd"
        partial.mkdir(parents=True)
        (partial / "session.v3.jsonl").write_text(
            "\n".join(body[:2]) + "\n" + call_line(9, 9, 9, 9, created + 40, 4)[:40])
        read_partial = read_calls(work, started, root=root)
        check("a truncated final line is skipped and counted",
              len(read_partial["calls"]) == 4 and read_partial["malformed_lines"] == 1
              and read_partial["sessions"][-1]["malformed_lines"] == 1,
              f"calls={len(read_partial['calls'])} malformed={read_partial['malformed_lines']}")
        shutil.rmtree(partial)

        # (6) cwd mismatch and earlier sessions are excluded
        check("a log for another working copy contributes nothing",
              read_calls(empty_work, started, root=root)["generated"] == 1)
        check("a session older than the run is excluded",
              read_calls(old_work, started, root=root)["matched"] is False)

        # (7) an unrecoverable run is reported as unmatched, with no invented calls
        missing = read_calls(scratch / "work" / "never-ran", started, root=root)
        check("a run with no session log reads as unmatched, not as zero spend",
              missing["matched"] is False and missing["calls"] == [] and missing["sessions"] == [])

        # (8) a compressed log decodes through the zstd CLI
        if shutil.which("zstd"):
            packed = root / slug_for(work) / "session-eee"
            packed.mkdir(parents=True)
            plain = packed / "session.v3.jsonl"
            plain.write_text("\n".join(body) + "\n")
            target = packed / "session.v3.jsonl.zstd"
            subprocess.run(["zstd", "-q", "-f", str(plain), "-o", str(target)], check=True)
            plain.unlink()
            packed_read = read_calls(work, started, root=root)
            check("a zstd session log decodes to the same calls",
                  len(packed_read["calls"]) == 6 and packed_read["generated"] == 1100
                  and packed_read["malformed_lines"] == 0,
                  f"calls={len(packed_read['calls'])} generated={packed_read['generated']}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    failures = [name for name, ok, _ in checks if not ok]
    print(f"\n{len(checks) - len(failures)}/{len(checks)} usage-reader properties demonstrated")
    return len(checks) - len(failures), len(checks), failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--work-dir", type=Path, help="the run's working copy")
    parser.add_argument("--since", help="the run's started_utc")
    parser.add_argument("--session-root", type=Path, default=SESSION_ROOT)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        passed, total, failures = selftest()
        return 1 if failures else 0
    if not args.work_dir or not args.since:
        parser.error("--work-dir and --since are required unless --selftest is given")
    read = read_calls(args.work_dir, args.since, root=args.session_root)
    print(json.dumps({key: value for key, value in read.items() if key != "calls"}, indent=2))
    for index, call in enumerate(read["calls"]):
        print(f"{index:3d}  {json.dumps(call.as_dict())}")
    return 0 if read["matched"] else 1


if __name__ == "__main__":
    sys.exit(main())
