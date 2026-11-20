#!/usr/bin/env python3
"""Developer audit of what the compiler's caches read, and of whether they can serve stale results.

Packages K0 and K1 of docs/audits/provable-cache-plan-2026-10-26.md.  Python is allowed here
(a developer script); nothing in src/ or the install graph runs it.

Eight subcommands:

    corpus   Write the projects the cases mutate under <work>/corpus.
    trace    Run cold commands under `strace -f` and compare every path read and every
             program executed with what the build's replay record lists (its `inputs`:
             files, absent files, existence probes, directory listings, variables),
             grouping the reads by where they live (project, toolchain, compiler, stores,
             system).  A project read, probe or listing the record does not list is
             printed as READ / LOOKED FOR / LISTED BUT NOT RECORDED; the comparison runs
             only for commands that write a replay record (build, run).
    env      Scan src/ for environment lookups and classify each name with
             src/environment_identity.zon, the way the keys do.
    mutate   Build warm, mutate one input, build warm again and compare with a clean
             build (`--no-cache`) of the mutated state.  Each case records a verdict:
             correct reuse, correct miss or STALE.
    fuzz     Chains of small edits to a real project; after each, a warm command must equal a clean one.
    table    Merge result files into a markdown table.
    racy     Alternate two same-size sources with no pause and require every build to
             run the current one (the stat fast path's racy-write window).
    toolchain  Run cold builds under `strace -f` with a fresh Zig global cache and list every
             file `zig` opened below its library that src/core/tool_files.zig does not
             track (K1): the tracked set must cover what the toolchain reads.

Everything the script writes goes under --work (default
~/.cache/selka/cache-audit); nothing is written under the repository.  Start with `corpus`.
The 2026-10-26 run's results, traces and case tables are in the evidence archive
(~/ai/canopy/mylang-evidence-archive/experiments/cache-read-audit-20261026).
"""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Optional

ROOT = Path(__file__).resolve().parents[1]
HOME = Path(os.environ.get("HOME", "/"))
DEFAULT_WORK = HOME / ".cache" / "selka" / "cache-audit"
SYSTEM_PREFIXES = ("/usr", "/lib", "/lib64", "/lib32", "/bin", "/sbin", "/etc", "/proc", "/sys", "/dev", "/var", "/run", "/opt", "/snap")
STRACE_CALLS = "openat,open,newfstatat,statx,stat,lstat,readlink,readlinkat,access,faccessat,faccessat2,execve,getdents64,chdir"

# The small purpose-built projects the cases mutate (`audit_cache_reads.py corpus` writes them).  Each maps a
# relative path to its text.  The two real projects come from `git archive`, and `policy` and `api` are copies
# of tests/fixtures/module_projects and examples/interface-files.
SMALL_CORPORA: dict[str, dict[str, str]] = {
    "hello": {
        'main.selka': 'func main(out: Stream) -> int:\n    print(out, "hello", 1 + 2)\n    return 0\n',
    },
    "proj": {
        'label.txt': 'LABEL-ONE',
        'main.selka': 'import util\nimport types\n\nfunc main(out: Stream) -> int:\n    const p = types.Point(x=3, y=4)\n    print(out, "dist2", util.dist2(p), util.label())\n    return 0\n',
        'mathlib.selka': 'public func add(a: int, b: int) -> int:\n    return a + b\n\npublic func sub(a: int, b: int) -> int:\n    return a - b\n\npublic func unreached(a: int) -> int:\n    return a * 2\n\npublic func test_add() -> bool:\n    return add(1, 2) == 3\n\npublic func test_sub() -> bool:\n    return sub(5, 2) == 3\n',
        'selka.json': '{"version": 2}\n',
        'tests/test_math.selka': 'import mathlib\n\npublic func test_both() -> bool:\n    return mathlib.add(2, 2) == mathlib.sub(6, 2)\n',
        'types.selka': 'public record Point:\n    x: int\n    y: int\n',
        'util.selka': 'import types\n\npublic func dist2(p: types.Point) -> int:\n    return p.x * p.x + p.y * p.y\n\npublic func label() -> str:\n    return embed_str("label.txt")\n\n\npublic func test_label() -> bool:\n    return label() == "LABEL-ONE"\n',
    },
    "linkc": {
        'foo.c': '#include "foo.h"\n#include <stdint.h>\nint32_t triple(int32_t v) { return v * FACTOR; }\n',
        'foo.h': '#define FACTOR 3\n',
        'main.selka': 'extern func triple(host: Host, v: i32) -> i32\n\nfunc main(out: Stream, host: Host) -> int:\n    print(out, "triple", triple(host, 7))\n    return 0\n',
    },
    "linkw": {
        'foo.c': '#include "foo.h"\n#include <stdint.h>\n#warning "careful with factor"\nint32_t triple(int32_t v) { return v * FACTOR; }\n',
        'foo.h': '#define FACTOR 3\n',
        'main.selka': 'extern func triple(host: Host, v: i32) -> i32\n\nfunc main(out: Stream, host: Host) -> int:\n    print(out, "triple", triple(host, 7))\n    return 0\n',
    },
    "linkneg": {
        'foo.c': '#include <stdint.h>\n#if __has_include("opt.h")\n#define FACTOR 5\n#else\n#define FACTOR 3\n#endif\n#include "stdbool.h"\nint32_t triple(int32_t v) { return v * FACTOR * (true ? 1 : 0); }\n',
        'main.selka': 'extern func triple(host: Host, v: i32) -> i32\n\nfunc main(out: Stream, host: Host) -> int:\n    print(out, "triple", triple(host, 7))\n    return 0\n',
    },
    "trap": {
        'main.selka': 'func main(out: Stream) -> int:\n    const xs: int[] = [1, 2, 3]\n    mut i = 5\n    print(out, "before")\n    return xs[i]\n',
    },
    "trap2": {
        'lib2.selka': 'public func pick(i: int) -> int:\n    const xs: int[] = [1, 2, 3]\n    return xs[i]\n\npublic func other(i: int) -> int:\n    return i + 1\n',
        'main.selka': 'import lib2\n\nfunc main(out: Stream) -> int:\n    print(out, "before", lib2.other(1))\n    mut i = 7\n    return lib2.pick(i)\n',
    },
    "warn": {
        'main.selka': 'import math\n\nfunc helper() -> int:\n    const unused = 5\n    return 1\n\nfunc main(out: Stream) -> int:\n    print(out, "w", helper())\n    return 0\n',
    },
    "sweep": {
        'lib.selka': 'import types\n\n\npublic func area(side: int) -> int:\n    return side * side\n\n\npublic func norm(p: types.Point) -> int:\n    return p.x + p.y\n\n\npublic func note(msg: str) -> int:\n    return len(msg)\n\n\npublic func total(xs: int[]) -> int:\n    mut t = 0\n    for x in xs:\n        t += x\n    return t\n\n\npublic func scale(v: int) -> int:\n    return v * types.SCALE\n',
        'main.selka': 'import lib\nimport types\n\n\nfunc uses_area(n: int) -> int:\n    return lib.area(n) + 1\n\n\nfunc uses_norm(a: int) -> int:\n    const p = types.Point(x=a, y=2)\n    return lib.norm(p)\n\n\nfunc uses_note() -> int:\n    return lib.note("abc")\n\n\nfunc uses_total() -> int:\n    const xs: int[] = [1, 2, 3]\n    return lib.total(xs)\n\n\nfunc uses_scale(v: int) -> int:\n    return lib.scale(v) + types.SCALE\n\n\nfunc uses_shape(s: types.Shape) -> int:\n    match s:\n        case dot:\n            return 0\n        case box(side):\n            return side\n\n\nfunc main(out: Stream) -> int:\n    print(out, uses_area(2), uses_norm(1), uses_note(), uses_total(), uses_scale(2), uses_shape(types.Shape.dot))\n    return 0\n',
        'types.selka': 'public record Point:\n    x: int\n    y: int\n\n\npublic enum Shape:\n    dot\n    box(side: int)\n\n\npublic const SCALE: int = 3\n',
    },
    "libsweep": {
        'lib.selka': 'import types\n\n\npublic func area(side: int) -> int:\n    return side * side\n\n\npublic func norm(p: types.Point) -> int:\n    return p.x + p.y\n\n\npublic func note(msg: str) -> int:\n    return len(msg)\n\n\npublic func total(xs: int[]) -> int:\n    mut t = 0\n    for x in xs:\n        t += x\n    return t\n\n\npublic func scale(v: int) -> int:\n    return v * types.SCALE\n',
        'types.selka': 'public record Point:\n    x: int\n    y: int\n\n\npublic enum Shape:\n    dot\n    box(side: int)\n\n\npublic const SCALE: int = 3\n',
        'user.selka': 'import lib\nimport types\n\n\nfunc uses_area(n: int) -> int:\n    return lib.area(n) + 1\n\n\nfunc uses_norm(a: int) -> int:\n    const p = types.Point(x=a, y=2)\n    return lib.norm(p)\n\n\nfunc uses_note() -> int:\n    return lib.note("abc")\n\n\nfunc uses_total() -> int:\n    const xs: int[] = [1, 2, 3]\n    return lib.total(xs)\n\n\nfunc uses_scale(v: int) -> int:\n    return lib.scale(v) + types.SCALE\n\n\nfunc uses_shape(s: types.Shape) -> int:\n    match s:\n        case dot:\n            return 0\n        case box(side):\n            return side\n',
    },
    "twoentry": {
        'helper.selka': 'import lib\n\npublic func uses_area(n: int) -> int:\n    return lib.area(n) + 1\n',
        'lib.selka': '@deprecated("use area2")\npublic func area(side: int) -> int:\n    return side * side\n',
        'main.selka': 'import helper\n\nfunc main(out: Stream) -> int:\n    print(out, "main", helper.uses_area(2))\n    return 0\n',
        'other.selka': 'import helper\n\nfunc main(out: Stream) -> int:\n    print(out, "other", helper.uses_area(3))\n    return 0\n',
    },
    "genericdep": {
        'helper.selka': 'import lib\n\npublic func apply[T](value: T, n: int) -> T:\n    const used = lib.area(n)\n    if used > 0:\n        return value\n    return value\n',
        'lib.selka': '@deprecated("use area2")\npublic func area(side: int) -> int:\n    return side * side\n',
        'main.selka': 'import helper\n\nfunc main(out: Stream) -> int:\n    print(out, "main", helper.apply[int](5, 2))\n    return 0\n',
        'other.selka': 'import helper\n\nfunc main(out: Stream) -> int:\n    print(out, "other", helper.apply[int](6, 3))\n    return 0\n',
    },
    "fstr": {
        'm.selka': 'import util as u\n\nrecord Row:\n    name: int\n    reserved: bool\n\nfunc require_unique(table: Row[]):\n    for i in range(0, len(table)):\n        for j in range(i + 1, len(table)):\n            if table[i].name == table[j].name:\n                assert False, f"duplicate row \'{u.twice(table[i].name)}\'"\n\nfunc require_parents(table: Row[]):\n    for row in table:\n        if not row.reserved:\n            assert False, f"direct row \'{u.twice(row.name)}\' is always reserved"\n\npublic func guarded(n: int) -> int:\n    const table: Row[] = [Row(name=1, reserved=True), Row(name=2, reserved=True)]\n    require_unique(table)\n    require_parents(table)\n    return n\n',
        'main.selka': 'import m\nimport other\n\nfunc main(out: Stream) -> int:\n    print(out, "v", m.guarded(3), other.unrelated())\n    return 0\n',
        'other.selka': '# shifted\npublic func unrelated() -> int:\n    return 1\n',
        'util.selka': 'public func twice(n: int) -> int:\n    return n * 2\n',
    },
    "facts": {
        'lib3.selka': 'public func limit() -> int:\n    return 2\n\npublic func small() -> u8:\n    return 10u8\n',
        'main.selka': 'import lib3\n\nfunc pick(xs: int[]) -> int:\n    return xs[lib3.limit()]\n\nfunc widen() -> u8:\n    return lib3.small() + 200u8\n\nfunc main(out: Stream) -> int:\n    const xs: int[] = [10, 20, 30]\n    print(out, "v", pick(xs), widen())\n    return 0\n\n\npublic func test_pick() -> bool:\n    const xs: int[] = [10, 20, 30]\n    return pick(xs) == 30\n',
    },
}


# --------------------------------------------------------------------------- helpers


def real(path: str | Path) -> str:
    """The physical spelling of `path` (the longest existing prefix resolved)."""
    p = Path(path)
    tail: list[str] = []
    while not p.exists() and p != p.parent:
        tail.append(p.name)
        p = p.parent
    resolved = Path(os.path.realpath(p))
    for name in reversed(tail):
        resolved = resolved / name
    return str(resolved)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(argv: list[str], env: dict[str, str] | None = None, cwd: Path | None = None, timeout: int = 1800) -> tuple[int, str, str]:
    """Run a command; return (status, stdout, stderr) with undecodable bytes replaced."""
    proc = subprocess.run(argv, env=env, cwd=cwd, capture_output=True, timeout=timeout)
    return proc.returncode, proc.stdout.decode("utf-8", "replace"), proc.stderr.decode("utf-8", "replace")


def base_env(extra: dict[str, str] | None = None, drop: tuple[str, ...] = ()) -> dict[str, str]:
    env = dict(os.environ)
    for name in drop:
        env.pop(name, None)
    env.update(extra or {})
    return env


# --------------------------------------------------------------------------- environment identity


class EnvironmentIdentity:
    """src/environment_identity.zon: exact names and `*` prefixes in four classes."""

    def __init__(self, path: Path) -> None:
        text = re.sub(r"//[^\n]*", "", path.read_text())
        self.classes: dict[str, list[str]] = {}
        for name in ("keyed", "host", "placement", "dropped"):
            block = re.search(r"\.%s\s*=\s*\.\{(.*?)\}" % name, text, re.S)
            self.classes[name] = re.findall(r'"([^"]+)"', block.group(1)) if block else []

    def classify(self, name: str) -> str:
        """An exact name beats every prefix; among prefixes the longest wins."""
        best: tuple[int, str] | None = None
        for klass, entries in self.classes.items():
            for entry in entries:
                if entry == name:
                    return klass
                if entry.endswith("*") and name.startswith(entry[:-1]) and (best is None or len(entry) > best[0]):
                    best = (len(entry), klass)
        return best[1] if best else "dropped (no entry)"


ENV_READ = re.compile(r'(?:environ_map|environment|environ|env|environment_map|variables)\s*\.\s*(?:get|put|getPtr|contains|fetchPut)\(\s*"([A-Za-z_][A-Za-z0-9_]*)"')
ENV_GETENV = re.compile(r'(?:getenv|getEnvVarOwned|getenvZ|environ\.get)\w*\(\s*"([A-Za-z_][A-Za-z0-9_]*)"')
ENV_CONST = re.compile(r'const\s+\w*(?:variable|_env|_var|ENV)\w*\s*=\s*"([A-Z][A-Z0-9_]+)"')
ENV_LITERAL = re.compile(r'"((?:MYL_|SELKA_|ZIG_|XDG_|LD_|CC|CPATH|C_INCLUDE|CPLUS|LIBRARY|SOURCE_DATE|NO_COLOR|CLICOLOR|FORCE_COLOR|TERM|HOME|TMPDIR|PATH|USER|LANG|LC_)[A-Z0-9_]*)"')


def scan_environment(src: Path, identity: EnvironmentIdentity) -> list[dict]:
    """Every environment name a non-test Zig source looks up, with its class and its files."""
    found: dict[str, set[str]] = {}
    literal: dict[str, set[str]] = {}
    for path in sorted(src.rglob("*.zig")):
        rel = str(path.relative_to(src))
        if path.name.endswith("_test.zig") or "/test" in rel:
            continue
        text = path.read_text(errors="replace")
        for regex in (ENV_READ, ENV_GETENV, ENV_CONST):
            for match in regex.finditer(text):
                found.setdefault(match.group(1), set()).add(rel)
        for match in ENV_LITERAL.finditer(text):
            literal.setdefault(match.group(1), set()).add(rel)
    rows = []
    for name in sorted(set(found) | set(literal)):
        rows.append({
            "name": name,
            "class": identity.classify(name),
            "lookup": name in found,
            "files": sorted(found.get(name, literal.get(name, set())))[:6],
        })
    return rows


# --------------------------------------------------------------------------- strace parsing


@dataclasses.dataclass
class Access:
    call: str
    path: str
    ok: bool
    errno: str
    flags: str = ""
    pid: int = 0


LINE = re.compile(r"^(\d+)\s+(?:(\w+)\((.*)\)\s+=\s+(-?\d+|\?)(?:\s+(\w+))?|<\.\.\. (\w+) resumed>(.*)\)\s+=\s+(-?\d+)(?:\s+(\w+))?|(\w+)\((.*) <unfinished \.\.\.>)")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')


def unescape(text: str) -> str:
    return text.encode("latin-1", "backslashreplace").decode("unicode_escape", "replace") if "\\" in text else text


def parse_trace(path: Path, start: str) -> tuple[list[Access], list[list[str]]]:
    """Accesses (opens, stats, readlinks, accesses, directory listings) and execve argvs.

    Relative paths are resolved against `start`, the directory the traced command ran in,
    or against the last `chdir` of the same process.
    """
    accesses: list[Access] = []
    execs: list[list[str]] = []
    pending: dict[int, tuple[str, str]] = {}
    cwd_of: dict[int, str] = {}
    with open(path, errors="replace") as handle:
        for raw in handle:
            raw = raw.rstrip("\n")
            m = re.match(r"^(\d+)\s+(.*)$", raw)
            if not m:
                continue
            pid, rest = int(m.group(1)), m.group(2)
            if rest.startswith("+++") or rest.startswith("---"):
                continue
            if rest.endswith("<unfinished ...>"):
                name, args = rest.split("(", 1)
                pending[pid] = (name, args.replace(" <unfinished ...>", ""))
                continue
            resumed = re.match(r"^<\.\.\. (\w+) resumed>(.*)$", rest)
            if resumed:
                name, tail = resumed.group(1), resumed.group(2)
                first = pending.pop(pid, (name, ""))
                rest = f"{name}({first[1]}{tail}"
            call_match = re.match(r"^(\w+)\((.*)\)\s+=\s+(-?\d+|\?)(?:\s+([A-Z0-9_]+))?", rest)
            if not call_match:
                continue
            call, args, result, errno = call_match.groups()
            ok = not result.startswith("-")
            if call == "execve":
                argv = [unescape(s) for s in STRING.findall(args)]
                if ok and argv:
                    execs.append([str(pid)] + argv)
                continue
            strings = [unescape(s) for s in STRING.findall(args)]
            if call == "chdir" and ok and strings:
                cwd_of[pid] = strings[0]
                continue
            if call == "getdents64":
                fd_path = re.match(r"^\d+<([^>]*)>", args)
                if fd_path:
                    accesses.append(Access(call, fd_path.group(1), ok, errno or "", pid=pid))
                continue
            if not strings:
                continue
            target = strings[0]
            if call in ("readlink", "readlinkat") and target.startswith("/proc/self/"):
                continue
            if not target.startswith("/"):
                base = cwd_of.get(pid, start)
                if call in ("openat", "newfstatat", "statx", "readlinkat", "faccessat", "faccessat2"):
                    # strace -y prints a directory descriptor as `7</path/to/dir>`; AT_FDCWD is the cwd.
                    dirfd = re.match(r"^\d+<([^>]*)>", args)
                    if dirfd:
                        base = dirfd.group(1)
                target = os.path.normpath(os.path.join(base, target))
            flags = "|".join(re.findall(r"\bO_[A-Z0-9_]+", args)) if call in ("openat", "open") else ""
            accesses.append(Access(call, target, ok, errno or "", flags=flags, pid=pid))
    return accesses, execs


# --------------------------------------------------------------------------- classification


class Places:
    """Where a path lives: project, toolchain, compiler installation, stores, work, tmp, system."""

    def __init__(self, project: str, compiler: Path, zig: Path, work_dir: str, tmp: str) -> None:
        self.rules: list[tuple[str, str]] = []

        def add(label: str, *paths: str) -> None:
            for p in paths:
                if p:
                    self.rules.append((label, os.path.normpath(p)))
                    self.rules.append((label, real(p)))

        add("work-dir", work_dir)
        add("project", project)
        add("toolchain", str(zig.parent), str(Path(os.path.realpath(zig)).parent))
        add("compiler", str(compiler.parent), str(Path(os.path.realpath(compiler)).parent), str(ROOT / "zig-out"))
        add("per-user-store", str(HOME / ".cache" / "selka"))
        add("zig-global-cache", str(HOME / ".cache" / "zig"), os.environ.get("ZIG_GLOBAL_CACHE_DIR", ""))
        add("tmp", tmp)
        self.rules.sort(key=lambda rule: -len(rule[1]))

    def of(self, path: str) -> str:
        if not path.startswith("/"):
            return "relative"
        for label, prefix in self.rules:
            if path == prefix or path.startswith(prefix.rstrip("/") + "/"):
                return label
        if path.startswith(SYSTEM_PREFIXES):
            return "system"
        return "other"


def replay_inputs(cache_dir: Path) -> tuple[dict[str, set[str]], list[dict]]:
    """What the replay records in CACHE_DIR say their builds read, by kind, and the records themselves.

    A record holds `inputs` since format `core-build-replay-v8` (ffb27c4f5), the wire form of `src/core/inputs.zig`: a list of
    {kind, name, ...}.  The kinds, with the sets they fill:

        file      bytes read, by digest; no digest means the path was looked for and absent   -> "file" / "absent"
        exists    only whether a path is there                                                  -> "exists"
        listing   a directory's entry names, by digest and filter                               -> "listing"
        variable  an environment variable's value, or its absence                               -> "variable" (names)

    Before that format the record held `dependencies`; this reader no longer looks at it, so an old record yields no inputs.
    """
    recorded: dict[str, set[str]] = {kind: set() for kind in ("file", "absent", "exists", "listing", "variable")}
    records: list[dict] = []
    folder = cache_dir / "replay-v1"
    if not folder.is_dir():
        return recorded, records
    for record in folder.iterdir():
        if record.name.endswith(".partial"):
            continue
        try:
            payload = json.loads(json.loads(record.read_text())["payload"])
        except Exception:
            continue
        records.append(payload)
        for item in payload.get("inputs", []):
            kind, name = item.get("kind"), item.get("name")
            if not isinstance(name, str):
                continue
            if kind == "file":
                recorded["file" if item.get("digest") else "absent"].add(name)
            elif kind in ("exists", "listing", "variable"):
                recorded[kind].add(name)
    return recorded, records


def unrecorded(project_reads: set[str], missing: set[str], listed: set[str], recorded: dict[str, set[str]], configuration: set[str]) -> dict[str, list[str]]:
    """The project accesses of a traced build that no replay input covers (paths compared by real path).

    A file opened for reading must be a `file` input (or one of the configuration files, keyed by their bytes); a path looked
    for and not found must be an `absent` file or an `exists` input; a directory listed must be a `listing` input.
    """
    files = {real(p) for p in recorded["file"]} | {real(p) for p in configuration}
    looked_for = {real(p) for p in recorded["absent"]} | {real(p) for p in recorded["exists"]} | files
    listings = {real(p) for p in recorded["listing"]}
    return {
        "reads": sorted(p for p in project_reads if real(p) not in files),
        "probes": sorted(p for p in missing if real(p) not in looked_for),
        "listings": sorted(p for p in listed if real(p) not in listings),
    }


def configuration_files(project: Path) -> set[str]:
    """The nearest selka.json above `project` and the import policy it names: both keyed by bytes."""
    found: set[str] = set()
    for folder in [project, *project.parents]:
        config = folder / "selka.json"
        if config.is_file():
            found.add(str(config))
            try:
                policy = json.loads(config.read_text()).get("import_policy")
            except Exception:
                policy = None
            if policy:
                found.add(str(folder / policy))
            break
    return found


# --------------------------------------------------------------------------- trace subcommand


@dataclasses.dataclass
class Scenario:
    name: str
    command: list[str]            # arguments after the compiler, `{out}`/`{cache}` expand
    project: str                  # directory the command runs in and treats as the project
    note: str = ""
    env: dict[str, str] = dataclasses.field(default_factory=dict)
    cold_store: bool = False      # a private per-user object store and Zig cache: the toolchain's reads too


def scenarios(corpus: Path, repo: Path) -> list[Scenario]:
    out = [
        Scenario("hello-build", ["build", "main.selka", "-o", "{out}/prog"], str(corpus / "hello")),
        Scenario("hello-run", ["run", "main.selka"], str(corpus / "hello")),
        Scenario("hello-check", ["check", "main.selka"], str(corpus / "hello")),
        Scenario("hello-build-cold-store", ["build", "main.selka", "-o", "{out}/prog"], str(corpus / "hello"), cold_store=True,
                 note="private object store and Zig cache: every toolchain read shows"),
        Scenario("proj-build", ["build", "main.selka", "-o", "{out}/prog"], str(corpus / "proj"), note="selka.json, imports, embed_str"),
        Scenario("proj-check", ["check", "main.selka"], str(corpus / "proj")),
        Scenario("proj-test", ["test", "tests/test_math.selka"], str(corpus / "proj")),
        Scenario("linkc-build", ["build", "main.selka", "-o", "{out}/prog", "--link", "foo.c"], str(corpus / "linkc"), note="--link C source and a header"),
        Scenario("linkc-release", ["build", "main.selka", "-o", "{out}/prog", "--link", "foo.c", "--release"], str(corpus / "linkc")),
        Scenario("eda-check", ["check", "main.selka"], str(corpus / "eda" / "stage2" / "selka" / "src"), note="EDA stage 2, 178 modules"),
        Scenario("eda-build", ["build", "main.selka", "-o", "{out}/prog"], str(corpus / "eda" / "stage2" / "selka" / "src")),
        Scenario("selka-build", ["build", "md2html.selka", "-o", "{out}/prog"], str(corpus / "selka" / "markdown"), note="selka markdown, 42 modules"),
        Scenario("selka-check-site", ["check", "site.selka"], str(corpus / "selka" / "markdown")),
        Scenario("lang-slice-test", ["test", "tests/lang/standard_strings.selka"], str(repo), note="a slice of tests/lang"),
    ]
    return out


def trace_one(scenario: Scenario, args: argparse.Namespace, work: Path, evidence: Path) -> dict:
    name = scenario.name
    folder = work / "trace" / name
    shutil.rmtree(folder, ignore_errors=True)
    (folder / "out").mkdir(parents=True)
    cache = folder / "cache"
    argv = [a.replace("{out}", str(folder / "out")).replace("{cache}", str(cache)) for a in scenario.command]
    env = base_env(scenario.env)
    env.pop("SELKA_CORE_RUNTIME_CACHE", None)
    if scenario.cold_store:
        env["SELKA_CORE_RUNTIME_CACHE"] = str(folder / "store")
        env["ZIG_GLOBAL_CACHE_DIR"] = str(folder / "zig-global")
    env["TMPDIR"] = str(folder / "tmp")
    (folder / "tmp").mkdir()
    trace = evidence / f"{name}.strace"
    evidence.mkdir(parents=True, exist_ok=True)
    started = time.time()
    status, stdout, stderr = run(
        ["strace", "-f", "-y", "-s", "400", "-o", str(trace), "-e", f"trace={STRACE_CALLS}", str(args.compiler), *argv, "--cache-dir", str(cache)],
        env=env, cwd=Path(scenario.project), timeout=3600)
    elapsed = time.time() - started
    accesses, execs = parse_trace(trace, real(scenario.project))
    places = Places(real(scenario.project), args.compiler, args.zig, str(cache), str(folder / "tmp"))
    recorded, records = replay_inputs(cache)
    receipts = sorted(str(p) for p in (cache / "tests").rglob("*") if p.is_file()) if (cache / "tests").is_dir() else []
    by_place: dict[str, dict[str, set[str]]] = {}
    for access in accesses:
        place = places.of(access.path)
        bucket = by_place.setdefault(place, {"read": set(), "stat": set(), "missing": set(), "listed": set()})
        if access.call == "getdents64":
            bucket["listed"].add(access.path)
        elif not access.ok:
            bucket["missing"].add(access.path)
        elif access.call in ("openat", "open") and "O_DIRECTORY" not in access.flags and "O_PATH" not in access.flags and "O_RDONLY" in access.flags:
            bucket["read"].add(access.path)
        else:
            bucket["stat"].add(access.path)
    project_reads = by_place.get("project", {}).get("read", set())
    configuration = configuration_files(Path(real(scenario.project)))
    # Only a command that writes a replay record (build, run) can be compared with one: `check` and `test` record their
    # reads in other keys (the verdict key, the test manifest), so a comparison there would call every read unrecorded.
    gaps = unrecorded(project_reads, by_place.get("project", {}).get("missing", set()), by_place.get("project", {}).get("listed", set()),
                      recorded, configuration) if records else {"reads": [], "probes": [], "listings": []}
    result = {
        "scenario": name,
        "note": scenario.note,
        "status": status,
        "seconds": round(elapsed, 1),
        "trace": str(trace),
        "syscalls": len(accesses),
        "places": {place: {kind: len(paths) for kind, paths in bucket.items()} for place, bucket in sorted(by_place.items())},
        "replay_records": len(records),
        "replay_inputs": {kind: len(names) for kind, names in recorded.items()},
        "replay_variables": sorted(recorded["variable"]),
        "configuration_files": sorted(configuration),
        "project_reads": sorted(project_reads),
        "project_read_not_in_replay": gaps["reads"],
        "project_probe_not_in_replay": gaps["probes"],
        "project_listing_not_in_replay": gaps["listings"],
        "project_missing_probes": sorted(by_place.get("project", {}).get("missing", set()))[:40],
        "project_directories_listed": sorted(by_place.get("project", {}).get("listed", set())),
        "other_reads": sorted(by_place.get("other", {}).get("read", set()))[:60],
        "relative_reads": sorted(by_place.get("relative", {}).get("read", set()))[:20],
        "compiler_reads": sorted(by_place.get("compiler", {}).get("read", set()))[:20],
        "store_reads": sorted(by_place.get("per-user-store", {}).get("read", set()))[:5],
        "system_reads": sorted(by_place.get("system", {}).get("read", set())),
        "toolchain_reads": len(by_place.get("toolchain", {}).get("read", set())),
        "executed": sorted({" ".join(a[1:4]) if a[1].endswith("zig") else a[1] for a in execs}),
        "toolchain_files_children_read_not_inventoried": inventory_gap(accesses, execs, places),
        "test_receipt_files": receipts[:20],
        "stderr_tail": stderr[-300:],
    }
    return result


def inventory_gap(accesses: list[Access], execs: list[list[str]], places: Places) -> list[str]:
    """Toolchain files a child process (zig) opened that the compiler process itself never looked at.

    The compiler binds a build to its toolchain by an inventory of library files it inspects
    (tool_identity.zig) plus the zig executable's content.  A file only a child reads is not
    in the identity unless the whole tree is covered another way (the one-time review of the
    library root against the approved distribution).
    """
    if not execs:
        return []
    root = int(execs[0][0])
    seen_by_root = {a.path for a in accesses if a.pid == root and places.of(a.path) == "toolchain"}
    child = {a.path for a in accesses if a.pid != root and places.of(a.path) == "toolchain" and a.ok and a.call in ("openat", "open") and "O_DIRECTORY" not in a.flags and "O_PATH" not in a.flags}
    return sorted(child - seen_by_root)[:50]


def command_trace(args: argparse.Namespace) -> int:
    if shutil.which("strace") is None:
        print("strace is required", file=sys.stderr)
        return 2
    work = Path(args.work)
    evidence = Path(args.evidence)
    results = []
    chosen = [s for s in scenarios(work / "corpus", ROOT) if not args.scenario or s.name in args.scenario]
    for scenario in chosen:
        print(f"trace {scenario.name} ...", file=sys.stderr, flush=True)
        results.append(trace_one(scenario, args, work, evidence))
    for r in results:
        (evidence / f"trace-{r['scenario']}.json").write_text(json.dumps(r, indent=1))
    target = evidence / "trace-summary.json"
    merged = {p.stem[len("trace-"):]: json.loads(p.read_text()) for p in sorted(evidence.glob("trace-*.json")) if p.name != "trace-summary.json"}
    target.write_text(json.dumps(list(merged.values()), indent=1))
    for r in results:
        print(f"\n== {r['scenario']} (exit {r['status']}, {r['seconds']}s, {r['syscalls']} accesses)")
        for place, kinds in r["places"].items():
            print(f"   {place:18s} " + " ".join(f"{k}={v}" for k, v in kinds.items()))
        kinds = " ".join(f"{kind}={count}" for kind, count in r["replay_inputs"].items())
        print(f"   replay records {r['replay_records']}, inputs {kinds}" + ("" if r["replay_records"] else " (no replay record: nothing to compare)"))
        for p in r["project_read_not_in_replay"]:
            print(f"   READ BUT NOT RECORDED: {p}")
        for p in r["project_probe_not_in_replay"]:
            print(f"   LOOKED FOR BUT NOT RECORDED: {p}")
        for p in r["project_listing_not_in_replay"]:
            print(f"   LISTED BUT NOT RECORDED: {p}")
        for p in r["project_directories_listed"]:
            print(f"   DIRECTORY LISTED: {p}")
        for p in r["other_reads"][:12]:
            print(f"   other read: {p}")
        gap = r["toolchain_files_children_read_not_inventoried"]
        if gap:
            print(f"   toolchain files only children read: {len(gap)} (first: {gap[0]})")
        print(f"   executed: {r['executed']}")
    print(f"\nsummary: {target}")
    return 0


# --------------------------------------------------------------------------- env subcommand


def command_env(args: argparse.Namespace) -> int:
    identity = EnvironmentIdentity(ROOT / "src" / "environment_identity.zon")
    rows = scan_environment(ROOT / "src", identity)
    print(f"{'NAME':36s} {'CLASS':22s} LOOKUP  FILES")
    for row in rows:
        print(f"{row['name']:36s} {row['class']:22s} {'yes' if row['lookup'] else 'lit':6s}  {', '.join(row['files'][:3])}")
    if args.json:
        Path(args.json).write_text(json.dumps(rows, indent=1))
    return 0


# --------------------------------------------------------------------------- toolchain subcommand


LIST = ROOT / "src" / "core" / "tool_files.list"


def listed_toolchain_files() -> list[str]:
    """The files src/core/tool_files.list names, one path below the library root per line."""
    return [line for line in LIST.read_text().splitlines() if line and not line.startswith("#")]


def zig_strings(name: str) -> list[str]:
    """The string array `name` of src/core/tool_files.zig."""
    text = (ROOT / "src" / "core" / "tool_files.zig").read_text()
    match = re.search(r"pub const " + name + r" = \[_\]\[\]const u8\{(.*?)\};", text, re.S)
    return re.findall(r'"([^"]+)"', match.group(1)) if match else []


def tracked_toolchain_files(lib: Path, thread: bool) -> set[str]:
    """The files below `lib` that the tracked set covers: the single files, the listed headers and
    stub sources, every file of the subtrees and, for a thread-sanitizer build, of the thread
    subtrees (a symbolic link is followed)."""
    tracked = {name for name in listed_toolchain_files() + zig_strings("files") if (lib / name).is_file()}
    for subtree in zig_strings("subtrees") + (zig_strings("thread_subtrees") if thread else []):
        for directory, _, names in os.walk(lib / subtree, followlinks=True):
            for name in names:
                tracked.add(str((Path(directory) / name).relative_to(lib)))
    return tracked


OPENED = re.compile(r"^\d+\s+(?:openat|open)\(.*\)\s+=\s+\d+<([^>]+)>")


def command_toolchain(args: argparse.Namespace) -> int:
    if shutil.which("strace") is None:
        print("strace is required", file=sys.stderr)
        return 2
    work = Path(args.work)
    lib = Path(real(Path(args.zig).resolve().parent / "lib"))
    commands = [
        ("hello-debug", "hello", ["build", "main.selka", "-o", "{out}"], {}),
        ("hello-release", "hello", ["build", "main.selka", "-o", "{out}", "--release"], {}),
        ("hello-thread", "hello", ["build", "main.selka", "-o", "{out}"], {"SELKA_CORE_SANITIZE": "thread"}),
        ("hello-address", "hello", ["build", "main.selka", "-o", "{out}"], {"SELKA_CORE_SANITIZE": "address"}),
        ("linkc-debug", "linkc", ["build", "main.selka", "-o", "{out}", "--link", "foo.c"], {}),
        ("linkc-release", "linkc", ["build", "main.selka", "-o", "{out}", "--link", "foo.c", "--release"], {}),
        ("layout-counting", "hello", ["build", "main.selka", "-o", "{out}", "--counters"], {"SELKA_CORE_LAYOUT": "5"}),
    ]
    opened: dict[str, set[str]] = {}
    for label, template, command, extra in commands:
        scratch = Path(real(work / "toolchain" / label))
        shutil.rmtree(scratch, ignore_errors=True)
        scratch.mkdir(parents=True)
        shutil.copytree(work / "corpus" / template, scratch / "p")
        # A cold Zig global cache (so the stubs and compiler-rt are built and read) beside the toolchain
        # memos of the real cache home (so the approval review, which reads every file once, does not run).
        memos = HOME / ".cache" / "selka" / "core-tools-v1"
        if memos.is_dir():
            shutil.copytree(memos, scratch / "xdg" / "selka" / "core-tools-v1")
        env = base_env({"SELKA_CORE_RUNTIME_CACHE": str(scratch / "store"), "ZIG_GLOBAL_CACHE_DIR": str(scratch / "zig-global"),
                        "XDG_CACHE_HOME": str(scratch / "xdg"), "SELKA_COMPILER_SHARED_CACHE": "", "SELKA_TEST_SHARED_CACHE": "", **extra})
        trace = scratch / "trace.txt"
        argv = ["strace", "-f", "-y", "-qq", "-e", "trace=openat,open", "-o", str(trace), "--", str(args.compiler)] + \
               [a.replace("{out}", str(scratch / "out")) for a in command] + ["--cache-dir", str(scratch / "cache")]
        status, _, error = run(argv, env=env, cwd=scratch / "p")
        files = set()
        for line in trace.read_text(errors="replace").splitlines():
            match = OPENED.match(line)
            if match and match.group(1).startswith(str(lib) + "/") and Path(match.group(1)).is_file():
                files.add(str(Path(match.group(1)).relative_to(lib)))
        opened[label] = files
        print(f"{label}: exit {status}, {len(files)} toolchain files opened" + ("" if status == 0 else f" ({error.strip().splitlines()[-1][:90] if error.strip() else ''})"))
    if args.write_list:
        whole = tuple(f"{name}/" for name in zig_strings("subtrees")) + tuple(zig_strings("files"))
        union = sorted(name for name in set().union(*(files for label, files in opened.items() if "thread" not in label))
                       if not name.startswith(whole) and name not in zig_strings("files"))
        LIST.write_text("# The toolchain files `zig` opens for the commands the core runs (scripts/audit_cache_reads.py toolchain\n"
                        "# --write-list), one path below the library root per line. src/core/tool_files.zig tracks them.\n" + "\n".join(union) + "\n")
        print(f"wrote {LIST} ({len(union)} files)")
    untracked: dict[str, list[str]] = {}
    for label, files in opened.items():
        missing = sorted(files - tracked_toolchain_files(lib, "thread" in label))
        if missing:
            untracked[label] = missing
        for name in missing[:20]:
            print(f"UNTRACKED READ ({label}): {name}")
    total = sorted(set().union(*opened.values()))
    print(f"the list names {len(listed_toolchain_files())} files; the commands opened {len(total)} in all; untracked reads: {sum(len(v) for v in untracked.values())}")
    if args.json:
        Path(args.json).write_text(json.dumps({"listed": len(listed_toolchain_files()), "opened": {k: sorted(v) for k, v in opened.items()}, "untracked": untracked}, indent=1))
    return 1 if untracked else 0


# --------------------------------------------------------------------------- mutate subcommand


@dataclasses.dataclass
class Observation:
    status: int
    stdout: str
    stderr: str
    program: Optional[str]      # sha256 of the produced executable, when the command makes one
    reuse: str                  # replayed / program-reused / linked / verdict-hit / check-miss / cached:N / unknown
    detail: str = ""


@dataclasses.dataclass
class Move:
    """What differs after the mutation: another working directory, command or environment."""
    project: Optional[Path] = None
    command: Optional[list[str]] = None
    env: dict[str, str] = dataclasses.field(default_factory=dict)
    unset: tuple[str, ...] = ()
    fresh_cache: bool = False       # warm run in an empty private cache directory (only shared stores can help it)


class CaseContext:
    def __init__(self, project: Path, case_dir: Path) -> None:
        self.project = project
        self.case_dir = case_dir

    def write(self, name: str, text: str) -> None:
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def read(self, name: str) -> str:
        return (self.project / name).read_text()

    def replace(self, name: str, old: str, new: str) -> None:
        text = self.read(name)
        if old not in text:
            raise RuntimeError(f"{name} does not contain {old!r}")
        self.write(name, text.replace(old, new, 1))

    def path(self, name: str) -> Path:
        return self.project / name


Mutation = Callable[[CaseContext], Optional[Move]]


@dataclasses.dataclass
class Case:
    name: str
    template: str                                   # corpus directory copied into the case's project
    command: list[str]                              # arguments after the compiler; {out}, {p} (the project) and {case} expand
    mutate: Mutation = lambda c: None
    env: dict[str, str] = dataclasses.field(default_factory=dict)
    setup: Mutation = lambda c: None                # applied to the fresh project before the first command
    expect: str = "any"                             # reuse: a correct cache reuses here; miss: it must not; any: either
    note: str = ""
    cold_store: bool = False                        # also compare with a build through a private object store
    group: str = ""
    must_change: bool = False                       # the mutation is meant to change the clean output (else it is a no-op case)
    other_compiler: bool = False                    # the warm and clean runs use --other-compiler (a rebuilt compiler on the same caches)
    repeat: int = 1                                 # times the first command runs before the mutation (library summaries start on the third check)
    subdir: str = ""                                # run inside this directory of the project (real corpora keep their project below the archive root)


def parse_reuse(kind: str, stdout: str, stderr: str) -> tuple[str, str]:
    if kind in ("build", "run"):
        match = re.search(r"selka-core: cache: (.*)", stderr)
        if match:
            line = match.group(1)
            if "replayed" in line:
                return "replayed", line
            if "program reused" in line:
                return "program-reused", line
            return "linked", line
    if kind == "check":
        report = re.search(r'"verdict_hits":(\d+)', stderr)
        bodies = re.search(r'"checked_bodies":\{"status":"(\w+)","performed":(\d+),"reused":(\d+)\}', stderr)
        detail = f"bodies performed={bodies.group(2)} reused={bodies.group(3)}" if bodies else ""
        if report and int(report.group(1)):
            return "verdict-hit", detail
        if bodies and int(bodies.group(3)):
            return "stand-ins", detail
        if bodies and bodies.group(1) == "hit":
            return "bodies-hit", detail
        return "check-miss", detail
    if kind == "test":
        cached = len(re.findall(r"^cached ", stdout + stderr, re.M))
        return (f"cached:{cached}" if cached else "ran"), ""
    return "unknown", ""


DEBUG_ECHO = re.compile(r"(?:CCC_OVERRIDE_OPTIONS|x-O0|[#: ])*")
NOISE = re.compile(r"^(selka-core: cache: .*|work: .*|\{\"version\":\"(?:frontend-cache-v1|work-report-v1|cache-report-v1|invalidation-report-v1)\".*)$")
TIME = re.compile(r"\b\d+(?:\.\d+)?\s?(?:ms|µs|us|ns|s)\b")
CACHED_MODULES = re.compile(r"(check: ok \(\d+ modules?), \d+ cached\)")
TEST_SUMMARY = re.compile(r"^(\d+) passed, (\d+) cached, (\d+) failed, (\d+) skipped(.*)$")


JSON_VOLATILE = {"cache", "nanoseconds", "work", "exec_receipts", "storage", "seconds", "duration_ms", "summary_cache"}


def normalise_json_report(text: str) -> Optional[str]:
    """A `--json` test report without what a warm run reports differently by design (cache details, timings)."""
    try:
        document = json.loads(text)
    except ValueError:
        return None
    if not isinstance(document, dict) or "tests" not in document:
        return None

    def strip(value):
        if isinstance(value, dict):
            return {k: strip(v) for k, v in value.items() if k not in JSON_VOLATILE and not k.endswith("_ns") and k not in ("steps", "peak_bytes")}
        if isinstance(value, list):
            return [strip(v) for v in value]
        return value
    counts = {k: document.get(k, 0) for k in ("passed", "cached") if isinstance(document.get(k), int)}
    stripped = strip(document)
    if counts:
        stripped["passed"] = sum(counts.values())
        stripped.pop("cached", None)
    for test in stripped.get("tests", []):
        if test.get("status") == "cached":
            test["status"] = "passed"
    for holder in (stripped, stripped.get("summary")):
        if isinstance(holder, dict) and "cached" in holder:
            holder["passed"] = holder.get("passed", 0) + holder.pop("cached", 0)
    return json.dumps(stripped, sort_keys=True)


def normalise(kind: str, text: str) -> str:
    if kind == "test" and text.lstrip().startswith("{"):
        report = normalise_json_report(text)
        if report is not None:
            return report
    lines = []
    for line in text.splitlines():
        if NOISE.match(line) or DEBUG_ECHO.fullmatch(line):
            continue  # clang's CCC_OVERRIDE_OPTIONS echo: one line per process, and concurrent ones interleave
        line = CACHED_MODULES.sub(r"\1)", line)
        line = TIME.sub("<time>", line)  # --stats and test lines carry wall times
        line = re.sub(r"==\d+==", "==<pid>==", line)  # a sanitizer's report names its process
        if kind == "test":
            line = re.sub(r"^cached ", "passed ", line)
            summary = TEST_SUMMARY.match(line)
            if summary:
                line = f"{int(summary.group(1)) + int(summary.group(2))} passed, {summary.group(3)} failed, {summary.group(4)} skipped"
        lines.append(line)
    if kind == "test":
        lines.sort()
    return "\n".join(lines)


class Runner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.compiler = Path(args.compiler)
        self.zig = Path(args.zig)
        self.work = Path(args.work)
        self.corpus = self.work / "corpus"
        self.other = Path(args.other_compiler) if getattr(args, "other_compiler", None) else None
        self.timeout = 1800

    def expand(self, command: list[str], project: Path, case_dir: Path, out: Path) -> list[str]:
        return [a.replace("{out}", str(out)).replace("{p}", str(project)).replace("{case}", str(case_dir)) for a in command]

    def observe(self, case: Case, case_dir: Path, project: Path, command: list[str], env: dict[str, str], cache: Path, label: str, extra: list[str], compiler: Optional[Path] = None) -> Observation:
        out = case_dir / f"out-{label}"
        expanded = self.expand(command, project, case_dir, out)
        kind = expanded[0]
        argv = [str(compiler or self.compiler)] + expanded + extra
        if kind in ("build", "run", "test", "check") and not any(a.startswith("--cache-dir") for a in expanded):
            argv += ["--cache-dir", str(cache)]
        if kind in ("build", "run") and "--no-cache" not in extra:
            argv += ["--cache-report"]
        if kind == "check":
            argv += ["--report"]
        try:
            status, stdout, stderr = run(argv, env=env, cwd=project, timeout=self.timeout)
        except subprocess.TimeoutExpired:
            return Observation(-9, "", "timed out", None, "unknown")
        program = sha(out) if out.is_file() else None
        reuse, detail = parse_reuse(kind, stdout, stderr)
        return Observation(status, normalise(kind, stdout), normalise(kind, stderr), program, reuse, detail)

    def case_env(self, case: Case, extra: dict[str, str], unset: tuple[str, ...], case_dir: Path, store: Optional[Path] = None) -> dict[str, str]:
        path_without_zig = os.pathsep.join(p for p in os.environ.get("PATH", "").split(os.pathsep) if not (Path(p) / "zig").exists()) or "/usr/bin:/bin"
        env = base_env({}, drop=unset)
        for source in (case.env, extra):
            for name, value in source.items():
                env[name] = value.replace("{zig}", str(self.zig)).replace("{case}", str(case_dir)).replace("{path_without_zig}", path_without_zig)
        if "TMPDIR" not in case.env and "TMPDIR" not in extra:
            env["TMPDIR"] = str(case_dir / "tmp")
        if store is not None:
            env["SELKA_CORE_RUNTIME_CACHE"] = str(store)
        Path(env["TMPDIR"]).mkdir(parents=True, exist_ok=True)  # a test run needs its scratch directory to exist
        return env

    def run_case(self, case: Case) -> dict:
        case_dir = self.work / "cases" / case.name
        shutil.rmtree(case_dir, ignore_errors=True)
        project = case_dir / "p"
        shutil.copytree(self.corpus / case.template, project, symlinks=True)
        (case_dir / "tmp").mkdir(parents=True, exist_ok=True)
        cache = case_dir / "cache"
        context = CaseContext(project, case_dir)
        case.setup(context)
        for _ in range(case.repeat):
            first = self.observe(case, case_dir, project / case.subdir, case.command, self.case_env(case, {}, (), case_dir), cache, "first", [])
        move = case.mutate(context) or Move()
        where = move.project or (project / case.subdir)
        command = move.command or case.command
        env = self.case_env(case, move.env, move.unset, case_dir)
        second = self.other if case.other_compiler else None
        warm = self.observe(case, case_dir, where, command, env, case_dir / "cache-fresh" if move.fresh_cache else cache, "warm", [], second)
        clean = self.observe(case, case_dir, where, command, env, case_dir / "cache-clean", "clean", ["--no-cache"], second)
        references = [("clean", clean)]
        if case.cold_store:
            cold_env = self.case_env(case, move.env, move.unset, case_dir, store=case_dir / "cold-store")
            references.append(("cold-store", self.observe(case, case_dir, where, command, cold_env, case_dir / "cache-cold", "cold", ["--no-cache"])))
        verdict, why = self.judge(case, first, warm, references)
        return {
            "case": case.name, "group": case.group, "verdict": verdict, "why": why, "note": case.note,
            "changed_output": (first.stdout, first.stderr, first.status, first.program) != (clean.stdout, clean.stderr, clean.status, clean.program),
            "first": dataclasses.asdict(first), "warm": dataclasses.asdict(warm), "clean": dataclasses.asdict(clean),
        }

    @staticmethod
    def judge(case: Case, first: Observation, warm: Observation, references: list[tuple[str, Observation]]) -> tuple[str, str]:
        for label, clean in references:
            differences = []
            if warm.status != clean.status:
                differences.append(f"exit {warm.status} vs {clean.status}")
            if warm.stdout != clean.stdout:
                differences.append("stdout")
            if warm.stderr != clean.stderr:
                differences.append("stderr")
            if warm.program != clean.program:
                differences.append("program bytes")
            if differences:
                return "STALE", f"warm ({warm.reuse}) differs from the {label} build in " + ", ".join(differences)
        reused = warm.reuse in ("replayed", "program-reused", "verdict-hit", "stand-ins", "bodies-hit") or warm.reuse.startswith("cached:")
        if case.expect == "reuse" and not reused:
            return "correct miss (reuse expected)", warm.reuse
        if case.expect == "miss" and reused:
            return "reused though a miss was expected (output equals clean)", warm.reuse
        return ("correct reuse" if reused else "correct miss"), f"{warm.reuse} {warm.detail}".strip()


# --- mutations ---------------------------------------------------------------


def edit(name: str, old: str, new: str) -> Mutation:
    def apply(c: CaseContext) -> None:
        c.replace(name, old, new)
    return apply


def write(name: str, text: str) -> Mutation:
    def apply(c: CaseContext) -> None:
        c.write(name, text)
    return apply


def then(*steps: Mutation) -> Mutation:
    def apply(c: CaseContext) -> Optional[Move]:
        move = None
        for step in steps:
            move = step(c) or move
        return move
    return apply


def append(name: str, text: str) -> Mutation:
    def apply(c: CaseContext) -> None:
        c.write(name, c.read(name) + text)
    return apply


def remove(name: str) -> Mutation:
    def apply(c: CaseContext) -> None:
        (c.project / name).unlink()
    return apply


def with_env(**values: str) -> Mutation:
    return lambda c: Move(env=dict(values))


def without_env(*names: str) -> Mutation:
    return lambda c: Move(unset=tuple(names))


def with_command(*command: str) -> Mutation:
    return lambda c: Move(command=list(command))


def noop(_: CaseContext) -> None:
    return None


BUILD = ["build", "main.selka", "-o", "{out}"]
RUN = ["run", "main.selka"]
CHECK = ["check", "main.selka"]


def core_cases() -> list[Case]:
    g = "replay"
    def symlink_file(c: CaseContext) -> None:
        (c.project / "util_other.selka").write_text(
            "import types\n\npublic func dist2(p: types.Point) -> int:\n    return p.x + p.y\n\npublic func label() -> str:\n    return embed_str(\"label.txt\")\n")
        (c.project / "util.selka").unlink()
        os.symlink("util_other.selka", c.project / "util.selka")

    def preserve_mtime_edit(c: CaseContext) -> None:
        path = c.path("util.selka")
        before = path.stat()
        c.replace("util.selka", "+ p.y * p.y", "- p.y * p.y")
        os.utime(path, ns=(before.st_atime_ns, before.st_mtime_ns))

    def move_project(c: CaseContext) -> Move:
        target = c.case_dir / "moved"
        shutil.copytree(c.project, target, symlinks=True)
        return Move(project=target)

    def via_symlink(c: CaseContext) -> Move:
        alias = c.case_dir / "alias"
        os.symlink(c.project, alias)
        return Move(project=alias)

    def parent_config(c: CaseContext) -> None:
        (c.case_dir / "selka.json").write_text('{"version": 2, "budgets": {"max_modules": 1}}')

    def stdlib_shadow(c: CaseContext) -> None:
        (c.project / "strings.selka").write_text("public func shadow() -> int:\n    return 1\n")

    def delete_module(c: CaseContext) -> None:
        (c.project / "types.selka").unlink()

    def add_api(c: CaseContext) -> None:
        c.write("selka.json", '{"version": 2, "interface_files": true}')

    cases = [
        Case("noop-rebuild", "proj", BUILD, noop, expect="reuse", group=g, note="nothing changed; a warm build must equal a clean one"),
        Case("module-edit", "proj", BUILD, edit("util.selka", "p.x * p.x + p.y * p.y", "p.x * p.x + p.y * p.y + 1"), group=g, note="an imported module's body"),
        Case("entry-edit", "proj", BUILD, edit("main.selka", '"dist2"', '"dist3"'), group=g, note="the entry source"),
        Case("signature-edit-error", "proj", BUILD, edit("types.selka", "y: int", "y: int\n    z: int"), group=g, note="record gains a field; the constructor call now fails"),
        Case("embed-edit", "proj", BUILD, write("label.txt", "LABEL-TWO"), group=g, note="an embedded file"),
        Case("embed-edit-same-size", "proj", BUILD, write("label.txt", "LABEL-TWO"[:9].replace("TWO", "ONF")), group=g, note="an embedded file, same size"),
        Case("touch-only", "proj", BUILD, lambda c: os.utime(c.path("util.selka"), None), expect="reuse", group=g, note="touch without change"),
        Case("same-size-immediate-edit", "proj", BUILD, edit("util.selka", "+ p.y * p.y", "- p.y * p.y"), group=g, note="same size, immediately after the first build"),
        Case("same-size-preserved-mtime", "proj", BUILD, preserve_mtime_edit, group=g, note="same size and the old mtime put back (ctime still moves)"),
        Case("symlink-replaces-file", "proj", BUILD, symlink_file, group=g, note="util.selka becomes a symlink to a file with other content"),
        Case("delete-module", "proj", BUILD, delete_module, group=g, note="an imported module disappears"),
        Case("add-stdlib-shadow", "proj", BUILD, stdlib_shadow, group=g, note="a local file named like a standard module appears (warning)"),
        Case("config-budget", "proj", BUILD, write("selka.json", '{"version": 2, "budgets": {"max_modules": 1}}'), group=g, note="selka.json budgets refuse the project"),
        Case("config-parent-appears", "proj", BUILD, then(remove("selka.json"), parent_config), group=g, note="the project's selka.json is replaced by one in the parent"),
        Case("config-interface-files", "proj", BUILD, add_api, group=g, note="interface_files turned on without .api files"),
        Case("move-project", "proj", BUILD, move_project, group=g, note="the same project in another directory"),
        Case("symlinked-directory", "proj", BUILD, via_symlink, group=g, note="the project reached through a symlinked directory"),
        Case("stdlib-shadow-present", "proj", BUILD, noop, setup=stdlib_shadow, expect="reuse", group=g, note="the shadowing warning is already there on both builds"),
        Case("stdlib-shadow-removed", "proj", BUILD, lambda c: (c.project / "strings.selka").unlink(), setup=stdlib_shadow, group=g, note="the shadowing file is removed after a build that warned"),
        Case("stdlib-shadow-unrelated-file", "proj", BUILD, write("unrelated.selka", "public func unrelated() -> int:\n    return 2\n"), setup=stdlib_shadow, expect="reuse", group=g, note="a file no standard module is named like appears beside a warned build (K1: the filtered listing is unchanged)"),
        Case("stdlib-shadow-second", "proj", BUILD, write("math.selka", "public func shadow2() -> int:\n    return 3\n"), setup=stdlib_shadow, group=g, must_change=True, note="a second shadowing file appears (K1: the listing moves)"),
        Case("release-flag", "proj", BUILD, with_command(*BUILD, "--release"), group=g, note="--release added"),
        Case("unoptimized-flag", "proj", BUILD, with_command(*BUILD, "--unoptimized"), group=g, note="--unoptimized added"),
        Case("entry-spelling-absolute", "trap", BUILD, with_command("build", "{p}/main.selka", "-o", "{out}"), group=g, note="relative build, then the absolute spelling of the entry", must_change=True),
        Case("entry-spelling-dot-slash", "trap", BUILD, with_command("build", "./main.selka", "-o", "{out}"), group=g, note="relative build, then ./main.selka"),
        Case("entry-spelling-dotdot", "trap", BUILD, with_command("build", "../p/main.selka", "-o", "{out}"), group=g, note="relative build, then ../p/main.selka"),
    ]
    return cases


def warning_cases() -> list[Case]:
    g = "warnings"
    wbuild = ["build", "main.selka", "-o", "{out}"]
    wcheck = ["check", "main.selka"]
    wtest = ["test", "main.selka"]
    abs_build = ["build", "{p}/main.selka", "-o", "{out}"]
    abs_check = ["check", "{p}/main.selka"]
    link = ["build", "main.selka", "-o", "{out}", "--link", "foo.c"]
    return [
        Case("warn-build-noop", "warn", wbuild, noop, expect="reuse", group=g, note="a build that prints warnings, replayed"),
        Case("warn-build-edit-text", "warn", wbuild, edit("main.selka", '"w"', '"v"'), group=g, note="a build that prints warnings, then an edit"),
        Case("warn-build-spelling", "warn", wbuild, with_command(*abs_build), group=g, note="warnings name the path as spelled"),
        Case("warn-build-fix-warning", "warn", wbuild, edit("main.selka", "const unused = 5\n    return 1", "return 1"), group=g, note="a warning's cause is removed"),
        Case("warn-check-noop", "warn", wcheck, noop, expect="reuse", group=g, note="check twice: the verdict hit replays the warnings"),
        Case("warn-check-spelling", "warn", wcheck, with_command(*abs_check), group=g, note="check with the absolute spelling after a relative check"),
        Case("warn-check-edit-text", "warn", wcheck, edit("main.selka", '"w"', '"v"'), group=g),
        Case("warn-check-fix-warning", "warn", wcheck, edit("main.selka", "const unused = 5\n    return 1", "return 1"), group=g),
        Case("warn-test-noop", "warn", wtest, noop, group=g, note="tests of a file that warns"),
        Case("warn-test-spelling", "warn", wtest, with_command("test", "{p}/main.selka"), group=g),
        Case("dep-second-entry", "twoentry", BUILD, with_command("build", "other.selka", "-o", "{out}"), group=g, note="a deprecated call in a module shared by two entries of one cache directory", must_change=False),
        Case("dep-second-entry-check", "twoentry", ["check", "main.selka"], with_command("check", "other.selka"), group=g),
        Case("dep-generic-edit-entry", "genericdep", BUILD, edit("main.selka", '"main"', '"main2"'), group=g, note="a generic helper calls a deprecated function; the entry is edited"),
        Case("dep-generic-second-entry", "genericdep", BUILD, with_command("build", "other.selka", "-o", "{out}"), group=g),
        Case("dep-generic-check-edit", "genericdep", ["check", "main.selka"], edit("main.selka", '"main"', '"main2"'), group=g),
        Case("linkw-noop", "linkw", link, noop, expect="reuse", group=g, note="a C source that warns, replayed"),
        Case("linkw-module-edit", "linkw", link, edit("main.selka", '"triple"', '"thrice"'), group=g, note="the C object is served; the compiler's warning came from its compile"),
        Case("linkw-release", "linkw", link, with_command(*link, "--release"), group=g),
    ]


def configuration_cases() -> list[Case]:
    g = "configuration"
    deny_main = '{"version": 1, "default_action": "allow", "rules": [{"from": "main", "to": "core.*", "action": "deny", "reason": "no"}]}'
    return [
        Case("policy-build-noop", "policy", BUILD, noop, expect="reuse", group=g),
        Case("policy-edit-denies", "policy", BUILD, write("policy.json", deny_main), group=g, note="the import policy now denies an import the program makes", must_change=True),
        Case("policy-check-edit-denies", "policy", CHECK, write("policy.json", deny_main), group=g, must_change=True),
        Case("policy-removed-from-config", "policy", BUILD, write("selka.json", '{"version": 2}'), group=g),
        Case("policy-file-deleted", "policy", BUILD, lambda c: (c.project / "policy.json").unlink(), group=g, note="selka.json names a policy file that is gone"),
        Case("config-lint-edit", "policy", CHECK, write("selka.json", '{"version": 2, "import_policy": "policy.json", "lint": {"warnings": "deny"}}'), group=g),
        Case("config-budget-check", "policy", CHECK, write("selka.json", '{"version": 2, "budgets": {"max_modules": 1}}'), group=g, must_change=True),
        Case("api-build-noop", "api", BUILD, noop, expect="reuse", group=g, note="interface_files project"),
        Case("api-file-stale", "api", BUILD, then(append("shop/billing.api", "\n# edited\n")), group=g),
        Case("api-file-removed", "api", BUILD, then(remove("shop/billing.api")), group=g),
        Case("api-source-edit", "api", BUILD, edit("shop/billing.selka", "unit_cents", "unit_cents"), group=g, note="no-op replace"),
        Case("api-check-file-stale", "api", CHECK, write("shop/billing.api", "junk"), group=g),
        Case("check-diagnostics-json", "warn", CHECK, with_command(*CHECK, "--diagnostics=json"), group=g, note="warnings replayed from a verdict hit in another format"),
        Case("build-diagnostics-json", "warn", BUILD, with_command(*BUILD, "--diagnostics=json"), group=g),
        Case("test-cases-file-appears", "proj", TEST, write("mathlib.cases.json", '{"mathlib::test_add": {"skip": "not now"}}'), group=g, note="a per-entry cases file appears", must_change=True),
        Case("test-cases-file-edit", "proj", TEST, write("mathlib.cases.json", '{"mathlib::test_sub": {"skip": "later"}}'), group=g, note="a cases file that existed from the start changes",
             setup=write("mathlib.cases.json", '{"mathlib::test_add": {"skip": "not now"}}'), must_change=True),
        Case("test-nearer-config-appears", "proj", ["test", "tests/test_math.selka"], write("tests/selka.json", '{"version": 2, "limits": {"test": {"max_steps": 1}}}'), group=g, must_change=True, note="a selka.json appears beside the entry, nearer than the project's"),
        Case("check-nearer-config-appears", "proj", ["check", "tests/test_math.selka"], write("tests/selka.json", '{"version": 2, "budgets": {"max_modules": 1}}'), group=g, must_change=True),
        Case("test-entry-absolute", "proj", TEST, with_command("test", "{p}/mathlib.selka"), group=g),
        Case("test-entry-dotslash", "proj", TEST, with_command("test", "./mathlib.selka"), group=g),
    ]


def toolchain_cases(zig: Path) -> list[Case]:
    """Mutations of a private copy of the guest toolchain (410 MB each)."""
    g = "toolchain"
    source = Path(os.path.realpath(zig)).parent
    command = ["build", "main.selka", "-o", "{out}", "--zig", "{case}/zigtool/zig"]

    def copy_toolchain(c: CaseContext) -> None:
        shutil.copytree(source, c.case_dir / "zigtool", symlinks=True)

    def edit_header(preserve: bool) -> Mutation:
        def apply(c: CaseContext) -> None:
            header = c.case_dir / "zigtool" / "lib" / "include" / "stdbool.h"
            before = header.stat()
            header.write_text(header.read_text().replace("#define true 1", "#define true 0", 1))
            if preserve:
                os.utime(header, ns=(before.st_atime_ns, before.st_mtime_ns))
        return apply

    def edit_library_source(c: CaseContext) -> None:
        # A comment appended to a Zig source the link builds (compiler-rt): the program is the same,
        # but the toolchain is no longer the one that was reviewed.
        source = c.case_dir / "zigtool" / "lib" / "compiler_rt.zig"
        source.write_text(source.read_text() + "\n// edited in place\n")

    def edit_untracked_file(c: CaseContext) -> None:
        target = sorted((c.case_dir / "zigtool" / "lib" / "docs").glob("*"))[0]
        target.write_text(target.read_text() + "edited\n")

    def add_shadowing_header(c: CaseContext) -> None:
        # A header that appears earlier on the include path than the one the runtime uses.
        directory = c.case_dir / "zigtool" / "lib" / "libc" / "include" / "x86-linux-any"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "stdbool.h").write_text("#define bool _Bool\n#define true 1\n#define false 0\n#define __bool_true_false_are_defined 1\n")

    def append_binary(c: CaseContext) -> None:
        binary = c.case_dir / "zigtool" / "zig"
        replacement = c.case_dir / "zigtool" / "zig.new"
        shutil.copy2(binary, replacement)
        with open(replacement, "ab") as handle:
            handle.write(b"\0")
        os.replace(replacement, binary)

    def edited_lib_dir_env(c: CaseContext) -> Move:
        edit_header(False)(c)
        return Move(env={"ZIG_LIB_DIR": str(c.case_dir / "zigtool" / "lib")})

    plain = ["build", "main.selka", "-o", "{out}"]
    return [
        Case("toolchain-zig-lib-dir-env", "trap", plain, edited_lib_dir_env, setup=copy_toolchain, group=g, cold_store=True,
             note="ZIG_LIB_DIR names a library tree whose libc header differs; the zig executable is the same"),
        Case("toolchain-copy-noop", "trap", command, noop, setup=copy_toolchain, expect="reuse", group=g, note="a copy of the toolchain at another path, unchanged"),
        Case("toolchain-header-edit", "trap", command, edit_header(False), setup=copy_toolchain, group=g, cold_store=True, note="a libc header the runtime includes changes (same size)"),
        Case("toolchain-header-edit-keep-mtime", "trap", command, edit_header(True), setup=copy_toolchain, group=g, cold_store=True, note="the same, with the old mtime put back"),
        Case("toolchain-binary-append", "trap", command, append_binary, setup=copy_toolchain, group=g, note="the zig executable changes"),
        Case("toolchain-source-edit", "trap", command, edit_library_source, setup=copy_toolchain, group=g, cold_store=True, note="a Zig source the link builds is edited in place"),
        Case("toolchain-header-appears", "trap", command, add_shadowing_header, setup=copy_toolchain, expect="miss", group=g, cold_store=True, note="a header appears in a directory earlier on the include path"),
        Case("toolchain-unrelated-file", "trap", command, edit_untracked_file, setup=copy_toolchain, expect="reuse", group=g, note="a documentation file edited in place: no build reads it, so it is not tracked and the replay stands"),
    ]


def location_cases() -> list[Case]:
    """Edits that move code without changing it: the positions in traps and debug information must follow."""
    g = "locations"
    prepend = lambda name, text: (lambda c: c.write(name, text + c.read(name)))
    return [
        Case("line-shift-lib-run", "trap2", RUN, prepend("lib2.selka", "# one\n# two\n"), group=g, must_change=True, note="a callee module gains two comment lines at the top"),
        Case("line-shift-main-run", "trap2", RUN, prepend("main.selka", "# one\n"), group=g, must_change=True),
        Case("line-shift-lib-build", "trap2", BUILD, prepend("lib2.selka", "# one\n# two\n"), group=g, must_change=True),
        Case("line-shift-lib-sibling-edit", "trap2", RUN, edit("lib2.selka", "return i + 1", "return i + 2"), group=g, note="a sibling function in the trapping module changes"),
        Case("column-shift-lib-run", "trap2", RUN, edit("lib2.selka", "    return xs[i]", "    return  xs[i]"), group=g, must_change=True, note="one extra space before the trapping expression"),
        Case("line-shift-test", "proj", TEST, prepend("mathlib.selka", "# one\n"), group=g, note="tests of a module whose lines moved"),
    ]


def bump_constant(directory: str, pattern: str = r"^((?:public )?const [A-Za-z_]+: int = )(\d+)$") -> Mutation:
    """Raise the first module-level integer constant found under `directory`: a small edit that still checks."""
    def apply(c: CaseContext) -> None:
        for path in sorted((c.project / directory).glob("*.selka")):
            if path.name.endswith("_test.selka"):
                continue
            text = path.read_text()
            match = re.search(pattern, text, re.M)
            if match:
                path.write_text(text[:match.start(2)] + str(int(match.group(2)) + int(os.environ.get("AUDIT_BUMP", "1"))) + text[match.end(2):])
                return
        raise RuntimeError("no module-level integer constant to bump")
    return apply


def real_cases() -> list[Case]:
    g = "real"
    eda = "stage2/selka/src"
    selka = "markdown"
    prepend = lambda name, text: (lambda c: c.write(name, text + c.read(name)))
    return [
        Case("eda-build-noop", "eda", BUILD, noop, subdir=eda, expect="reuse", group=g),
        Case("eda-check-noop", "eda", CHECK, noop, subdir=eda, expect="reuse", group=g),
        Case("eda-build-bump-constant", "eda", BUILD, bump_constant(eda), subdir=eda, group=g, must_change=True),
        Case("eda-check-bump-constant", "eda", CHECK, bump_constant(eda), subdir=eda, group=g, must_change=True),
        Case("eda-build-line-shift", "eda", BUILD, prepend(eda + "/design_model.selka", "# shifted\n# lines\n"), subdir=eda, group=g, note="two comment lines at the top of a mid-level module"),
        Case("eda-check-line-shift", "eda", CHECK, prepend(eda + "/design_model.selka", "# shifted\n# lines\n"), subdir=eda, group=g),
        Case("eda-build-release", "eda", BUILD, with_command(*BUILD, "--release"), subdir=eda, group=g),
        Case("eda-test-slice", "eda", ["test", "board_layers_test.selka"], bump_constant(eda), subdir=eda, group=g, note="a test file whose module constants change"),
        Case("selka-check-md2html", "selka", ["check", "md2html.selka"], noop, subdir=selka, expect="reuse", group=g),
        Case("selka-build-md2html", "selka", ["build", "md2html.selka", "-o", "{out}"], noop, subdir=selka, expect="reuse", group=g),
        Case("selka-build-bump-constant", "selka", ["build", "md2html.selka", "-o", "{out}"], bump_constant(selka + "/inline"), subdir=selka, group=g, must_change=True),
        Case("selka-check-site", "selka", ["check", "site.selka"], bump_constant(selka + "/container"), subdir=selka, group=g),
        Case("selka-build-line-shift", "selka", ["build", "md2html.selka", "-o", "{out}"], prepend(selka + "/links/scan.selka", "# a\n# b\n"), subdir=selka, group=g),
    ]


def import_use_cases() -> list[Case]:
    """An import whose only use is inside an f-string hole, and edits that move the module's lines."""
    g = "import-use"
    prepend = lambda name, text: (lambda c: c.write(name, text + c.read(name)))
    return [
        Case("fstring-import-noop", "fstr", BUILD, noop, expect="reuse", group=g),
        Case("fstring-import-line-shift", "fstr", BUILD, prepend("m.selka", "# moved\n"), group=g, note="the module whose only use of `util` is in an assert message moves down a line"),
        Case("fstring-import-line-shift-release", "fstr", BUILD + ["--release"], prepend("m.selka", "# moved\n"), group=g),
        Case("fstring-import-line-shift-check", "fstr", CHECK, prepend("m.selka", "# moved\n"), group=g),
        Case("fstring-import-other-module-edit", "fstr", BUILD, prepend("other.selka", "# moved\n"), group=g),
    ]


def facts_cases() -> list[Case]:
    """A callee edit that breaks a fact the optimizer used in its caller (a removed bounds or overflow check)."""
    g = "facts"
    cases = []
    for mode, flags in (("default", []), ("release", ["--release"]), ("unoptimized", ["--unoptimized"])):
        run = ["run", "main.selka", *flags]
        cases.append(Case(f"facts-index-{mode}", "facts", run, edit("lib3.selka", "return 2\n", "return 5\n"), group=g, must_change=True, note=f"run {' '.join(flags)}: the callee's result leaves the indexed range"))
        cases.append(Case(f"facts-overflow-{mode}", "facts", run, edit("lib3.selka", "return 10u8", "return 100u8"), group=g, must_change=True, note=f"run {' '.join(flags)}: a u8 sum overflows"))
        cases.append(Case(f"facts-both-then-fix-{mode}", "facts", run, noop, group=g, setup=lambda c: c.replace("lib3.selka", "return 2\n", "return 1\n"), note="control: nothing changes"))
    cases.append(Case("facts-build-release", "facts", ["build", "main.selka", "-o", "{out}", "--release"], edit("lib3.selka", "return 2\n", "return 5\n"), group=g, must_change=True))
    cases.append(Case("facts-test-release", "facts", ["test", "main.selka", "--release"], edit("lib3.selka", "return 2\n", "return 5\n"), group=g))
    return cases


def compiler_cases(runner_has_other: bool) -> list[Case]:
    """The cache written by one compiler, read by another build of the compiler with a real source change."""
    if not runner_has_other:
        return []
    g = "compiler"
    return [
        Case("compiler-rebuilt-build", "trap2", BUILD, noop, other_compiler=True, group=g, note="the same project built by two compilers on one cache"),
        Case("compiler-rebuilt-warn-build", "warn", BUILD, noop, other_compiler=True, group=g),
        Case("compiler-rebuilt-check", "warn", CHECK, noop, other_compiler=True, group=g),
        Case("compiler-rebuilt-test", "proj", TEST, noop, other_compiler=True, group=g),
        Case("compiler-rebuilt-dep", "twoentry", BUILD, with_command("build", "other.selka", "-o", "{out}"), other_compiler=True, group=g),
        Case("compiler-rebuilt-sweep", "sweep", BUILD, edit("lib.selka", "return side * side", "return side * side + 1"), other_compiler=True, group=g),
    ]


FLAG_SETS: list[tuple[str, list[str]]] = [
    ("generic-vectors", ["--generic-vectors"]),
    ("counters", ["--counters"]),
    ("no-facts", ["--no-facts"]),
    ("verify-facts", ["--verify-facts"]),
    ("local-stdlib", ["--local-stdlib"]),
    ("stats", ["--stats"]),
    ("diagnostics-json", ["--diagnostics=json"]),
    ("diagnostics-text", ["--diagnostics=text"]),
    ("optimize-debug", ["--optimize-debug"]),
    ("verify-written-copies", ["--verify-written-copies"]),
]


def flag_cases() -> list[Case]:
    cases = []
    for name, flags in FLAG_SETS:
        cases.append(Case(f"flag-{name}", "trap", BUILD, with_command(*BUILD, *flags), group="flags", note=f"build, then the same build with {' '.join(flags)}"))
    run_flags = [("max-steps", ["--max-steps", "5"]), ("max-frames", ["--max-frames", "3"]), ("max-memory", ["--max-memory", "64M"]),
                 ("threads", ["--threads", "1"]), ("print-result", ["--print-result"]), ("restrict", ["--restrict"]),
                 ("timeout", ["--timeout", "9"]), ("allow-clock", ["--restrict", "--allow-clock"])]
    for name, flags in run_flags:
        cases.append(Case(f"run-{name}", "proj", RUN, with_command(*RUN, *flags), group="flags", note=f"run, then run with {' '.join(flags)}"))
    cases.append(Case("build-run-max-steps", "proj", ["build", "main.selka", "--run"], with_command("build", "main.selka", "--run", "--max-steps", "5"), group="flags"))
    return cases


def env_cases() -> list[Case]:
    g = "environment"
    cases = []
    build_vars: list[tuple[str, str]] = [
        ("SELKA_CORE_LEAKCHECK", "1"), ("SELKA_CORE_LAYOUT", "5"), ("SELKA_CORE_SANITIZE", "thread"), ("SELKA_OPTIONS", "--print-result"),
        ("SELKA_THREADS", "1"), ("SELKA_MEMORY_LIMIT", "64M"), ("SELKA_JOBS", "1"), ("SELKA_UNIT_JOBS", "1"),
        ("SELKA_STAGE_CACHE_COMPRESSION", "none"), ("SELKA_CACHE_PLAN_MODE", "reference"), ("SELKA_TEST_KEYS", "per-test"),
        ("SELKA_SEMANTIC_BUDGET", "1048576"), ("SELKA_VERIFY_WRITTEN_COPIES", "1"), ("SOURCE_DATE_EPOCH", "1"), ("ZERO_AR_DATE", "1"),
        ("SELKA_ZIG", "{zig}"), ("ZIG", "{zig}"),
        ("CC", "/bin/false"), ("CPATH", "{case}/inc"), ("C_INCLUDE_PATH", "{case}/inc"), ("LIBRARY_PATH", "{case}/inc"), ("CCC_OVERRIDE_OPTIONS", "x-O0"),
        ("ZIG_LIBC", "/nonexistent"), ("LD_LIBRARY_PATH", "{case}/inc"),
        ("PATH", "{path_without_zig}"), ("HOME", "{case}/home"), ("TMPDIR", "{case}/other-tmp"), ("XDG_CACHE_HOME", "{case}/xdg"),
        ("ZIG_GLOBAL_CACHE_DIR", "{case}/zig-global"), ("ZIG_LOCAL_CACHE_DIR", "{case}/zig-local"), ("SELKA_CORE_RUNTIME_CACHE", "{case}/runtime-store"),
        ("LANG", "C.UTF-8"), ("TZ", "Asia/Tokyo"), ("TERM", "dumb"), ("NO_COLOR", "1"), ("CLICOLOR_FORCE", "1"), ("COLUMNS", "40"), ("USER", "someone-else"),
        ("PWD", "/somewhere/else"), ("SELKA_COMPILER_SHARED_CACHE", "{case}/shared"), ("SELKA_FRONTEND_CACHE", "{case}/fe"),
        ("SELKA_FRICTION_LOG", "{case}/friction.log"), ("SELKA_PROFILE_DIR", "{case}/profile"),
    ]
    for name, value in build_vars:
        cases.append(Case(f"env-build-{name.lower()}", "trap", BUILD, lambda c, n=name, v=value: Move(env={n: v}), group=g, note=f"build, then {name}={value}"))
    # The same variables against the other cached commands: a project check (warnings replay from a verdict hit) and tests.
    for name, value in build_vars:
        cases.append(Case(f"env-check-{name.lower()}", "warn", CHECK, lambda c, n=name, v=value: Move(env={n: v}), group="environment-check", note=f"check, then {name}={value}"))
        cases.append(Case(f"env-test-{name.lower()}", "proj", TEST, lambda c, n=name, v=value: Move(env={n: v}), group="environment-test", note=f"test, then {name}={value}"))
    return cases


# --- the stand-in sweep -------------------------------------------------------

# (name, file, old, new): each keeps main.selka's helper bodies byte-identical and changes what they mean.
SWEEP: list[tuple[str, str, str, str]] = [
    ("param-type", "lib.selka", "public func area(side: int) -> int:", "public func area(side: str) -> int:"),
    ("param-count", "lib.selka", "public func area(side: int) -> int:\n    return side * side", "public func area(side: int, extra: int) -> int:\n    return side * extra"),
    ("return-type", "lib.selka", "public func area(side: int) -> int:\n    return side * side", "public func area(side: int) -> str:\n    return \"x\""),
    ("not-public", "lib.selka", "public func note(msg: str) -> int:", "func note(msg: str) -> int:"),
    ("removed-function", "lib.selka", "public func note(msg: str) -> int:\n    return len(msg)\n", ""),
    ("renamed-function", "lib.selka", "public func note(msg: str) -> int:", "public func note2(msg: str) -> int:"),
    ("fails-added", "lib.selka", "public func area(side: int) -> int:\n    return side * side", "public func area(side: int) -> int fails str:\n    return side * side"),
    ("own-parameter", "lib.selka", "public func total(xs: int[]) -> int:", "public func total(own xs: int[]) -> int:"),
    ("mut-parameter", "lib.selka", "public func total(xs: int[]) -> int:", "public func total(mut xs: int[]) -> int:"),
    ("record-field-added", "types.selka", "    y: int\n", "    y: int\n    z: int\n"),
    ("record-field-removed", "types.selka", "    y: int\n", ""),
    ("record-field-renamed", "types.selka", "    y: int\n", "    w: int\n"),
    ("record-field-type", "types.selka", "    y: int\n", "    y: str\n"),
    ("record-private", "types.selka", "public record Point:", "record Point:"),
    ("const-type", "types.selka", "public const SCALE: int = 3", "public const SCALE: str = \"3\""),
    ("const-removed", "types.selka", "public const SCALE: int = 3\n", ""),
    ("const-value", "types.selka", "public const SCALE: int = 3", "public const SCALE: int = 4"),
    ("enum-variant-added", "types.selka", "    box(side: int)\n", "    box(side: int)\n    ring(radius: int)\n"),
    ("enum-variant-removed", "types.selka", "    box(side: int)\n", ""),
    ("enum-payload-type", "types.selka", "    box(side: int)\n", "    box(side: str)\n"),
    ("deprecated-added", "lib.selka", "public func area(side: int) -> int:", "@deprecated(\"use area2\")\npublic func area(side: int) -> int:"),
    ("callee-needs-stream", "lib.selka", "public func note(msg: str) -> int:\n    return len(msg)", "public func note(out: Stream, msg: str) -> int:\n    return len(msg)"),
    ("import-removed", "lib.selka", "import types\n", ""),
    ("transitive-type", "types.selka", "public record Point:\n    x: int\n    y: int", "public record Point:\n    x: int\n    y: int\n    tag: Tag\n\n\nrecord Tag:\n    id: int"),
    ("array-param", "lib.selka", "public func total(xs: int[]) -> int:", "public func total(xs: str[]) -> int:"),
    ("body-only-callee", "lib.selka", "return side * side", "return side * side + 1"),
]


def sweep_cases() -> list[Case]:
    cases = []
    for name, file, old, new in SWEEP:
        def mutate(c: CaseContext, file=file, old=old, new=new) -> None:
            c.replace(file, old, new)
        cases.append(Case(f"standin-library-{name}", "libsweep", ["check", "user.selka"], mutate, group="stand-ins", repeat=3, note=f"library check, third check then {file} {name}"))
    for kind, command in (("check", CHECK), ("build", BUILD)):
        for name, file, old, new in SWEEP:
            def mutate(c: CaseContext, file=file, old=old, new=new) -> None:
                # the second check (or build) of the unmodified project is what writes the stand-in summaries
                c.replace(file, old, new)
            cases.append(Case(f"standin-{kind}-{name}", "sweep", command, mutate, group="stand-ins", note=f"{kind}: {file} {name}"))
    return cases


# --- tests -------------------------------------------------------------------

TEST = ["test", "mathlib.selka"]
TEST_DIR = ["test", "."]


def test_cases() -> list[Case]:
    g = "tests"
    def new_test_file(c: CaseContext) -> None:
        c.write("tests/test_extra.selka", "import mathlib\n\npublic func test_extra() -> bool:\n    return mathlib.add(1, 1) == 3\n")
    def edit_reached(c: CaseContext) -> None:
        c.replace("mathlib.selka", "return a + b", "return a + b + 1")
    return [
        Case("test-noop", "proj", TEST, noop, expect="reuse", group=g),
        Case("test-edit-reached", "proj", TEST, edit_reached, group=g, note="a function the tests reach changes (test_add now fails)", must_change=True),
        Case("test-edit-unreached", "proj", TEST, edit("mathlib.selka", "return a * 2", "return a * 3"), expect="reuse", group=g, note="a function no test reaches"),
        Case("test-edit-test-body", "proj", TEST, edit("mathlib.selka", "return add(1, 2) == 3", "return add(1, 2) == 4"), group=g, must_change=True),
        Case("test-embed-edit", "proj", ["test", "util.selka"], write("label.txt", "LABEL-TWO"), group=g, note="a test module that embeds a file; the file changes"),
        Case("test-dir-new-file", "proj", TEST_DIR, new_test_file, group=g, note="a directory run, then a new test file appears", must_change=True),
        Case("test-dir-delete-file", "proj", TEST_DIR, lambda c: (c.project / "tests" / "test_math.selka").unlink(), group=g, note="a directory run, then a test file disappears"),
        Case("test-config-limits", "proj", TEST, write("selka.json", '{"version": 2, "limits": {"test": {"max_steps": 1}}}'), group=g, note="selka.json test step limit", must_change=True),
        Case("test-filter-change", "proj", TEST, with_command(*TEST, "--filter", "test_add"), group=g, note="a filter after an unfiltered run"),
        Case("test-json-after-text", "proj", TEST, with_command(*TEST, "--json"), group=g, note="--json after a text run replays the report"),
        Case("test-text-after-json", "proj", TEST + ["--json"], with_command(*TEST), group=g),
        Case("test-force-flag", "proj", TEST, with_command(*TEST, "--force"), group=g),
        Case("test-unoptimized-flag", "proj", TEST, with_command(*TEST, "--unoptimized"), group=g),
        Case("test-release-flag", "proj", TEST, with_command(*TEST, "--release"), group=g),
        Case("test-max-steps", "proj", TEST, with_command(*TEST, "--max-steps", "2"), group=g, note="a step ceiling the tests exceed", must_change=True),
        Case("test-seed", "proj", TEST, with_command(*TEST, "--seed", "7"), group=g),
        Case("test-leakcheck-env", "proj", TEST, with_env(SELKA_CORE_LEAKCHECK="1"), group=g),
        Case("test-move-project", "proj", TEST, lambda c: Move(project=_copy(c)), group=g, note="the project in another directory"),
        Case("test-same-size-edit", "proj", TEST, edit("mathlib.selka", "add(1, 2) == 3", "add(1, 2) == 4"), group=g, must_change=True),
        Case("test-symlink-dir", "proj", TEST, lambda c: Move(project=_alias(c)), group=g),
        Case("test-env-path", "proj", TEST, with_env(PATH="/usr/bin:/bin"), group=g, note="PATH changes (the toolchain is found by content)"),
        Case("test-env-home", "proj", TEST, lambda c: Move(env={"HOME": str(c.case_dir / "home")}), group=g),
    ]


def _fresh(move: Move) -> Move:
    move.fresh_cache = True
    return move


def _copy(c: CaseContext) -> Path:
    target = c.case_dir / "moved"
    shutil.copytree(c.project, target, symlinks=True)
    return target


def _alias(c: CaseContext) -> Path:
    alias = c.case_dir / "alias"
    os.symlink(c.project, alias)
    return alias


# --- --link ------------------------------------------------------------------

LINK = ["build", "main.selka", "-o", "{out}", "--link", "foo.c"]


def link_cases() -> list[Case]:
    g = "link"
    return [
        Case("link-noop", "linkc", LINK, noop, expect="reuse", group=g),
        Case("link-source-edit", "linkc", LINK, edit("foo.c", "v * FACTOR", "v * FACTOR + 1"), group=g, note="the C source"),
        Case("link-source-edit-same-size", "linkc", LINK, edit("foo.c", "v * FACTOR", "v + FACTOR"), group=g),
        Case("link-header-edit", "linkc", LINK, write("foo.h", "#define FACTOR 4\n"), group=g, note="the header the C source includes (same size)"),
        Case("link-header-edit-size", "linkc", LINK, write("foo.h", "#define FACTOR 10\n"), group=g),
        Case("link-header-appears-earlier", "linkc", LINK, then(write("sub/foo.h", "#define FACTOR 9\n"), edit("foo.c", '#include "foo.h"', '#include "sub/foo.h"')), group=g),
        Case("link-header-delete", "linkc", LINK, lambda c: (c.project / "foo.h").unlink(), group=g, note="the header disappears (compile error)"),
        Case("link-new-header-shadows", "linkc", LINK, then(write("foo.h", "#define FACTOR 3\n"), noop), expect="reuse", group=g),
        Case("link-release", "linkc", LINK, with_command(*LINK, "--release"), group=g),
        Case("link-source-moved", "linkc", LINK, lambda c: Move(project=_copy(c)), group=g, note="the project in another directory"),
        Case("link-system-header", "linkc", LINK, then(edit("foo.c", "#include <stdint.h>", "#include <stdint.h>\n#include <limits.h>"),), group=g),
        Case("link-env-cpath", "linkc", LINK, lambda c: Move(env={"CPATH": str(c.case_dir / "inc")}), group=g, note="CPATH set after a build without it (unproved toolchain env)"),
        Case("link-env-c-include", "linkc", LINK, lambda c: Move(env={"C_INCLUDE_PATH": str(c.case_dir / "inc")}), group=g),
        Case("link-spelling-dot-slash", "linkc", LINK, with_command("build", "main.selka", "-o", "{out}", "--link", "./foo.c"), group=g, note="the --link source spelled ./foo.c"),
        Case("link-spelling-absolute", "linkc", LINK, with_command("build", "main.selka", "-o", "{out}", "--link", "{p}/foo.c"), group=g, note="the --link source spelled as an absolute path"),
        Case("link-has-include-appears", "linkneg", LINK, write("opt.h", "#define OPT 1\n"), group=g, must_change=True, note="a file `__has_include` tests for appears beside the source"),
        Case("link-shadow-system-header-appears", "linkneg", LINK, write("stdbool.h", "#define true 0\n"), group=g, must_change=True, note="a local stdbool.h now shadows the system one for a quoted include"),
        Case("link-has-include-disappears", "linkneg", LINK, remove("opt.h"), setup=write("opt.h", "#define OPT 1\n"), group=g, must_change=True),
        Case("link-header-appears-unlisted", "linkc", LINK, write("unused.h", "#define UNUSED 1\n"), expect="reuse", group=g, note="a header nothing includes appears beside the source"),
        Case("link-two-sources", "linkc", LINK, then(write("bar.c", "int bar(void) { return 1; }\n")), group=g, note="a second --link source added", ),
    ]


def shared_cases() -> list[Case]:
    g = "shared"
    store = {"SELKA_COMPILER_SHARED_CACHE": "{case}/shared-compiler"}
    tests_store = ["--shared-cache-dir", "{case}/shared-tests"]
    def copy_to_other_root(c: CaseContext) -> Move:
        return _fresh(Move(project=_copy(c)))
    return [
        Case("shared-compiler-noop", "proj", BUILD, noop, env=store, group=g),
        Case("shared-compiler-moved", "proj", BUILD, copy_to_other_root, env=store, group=g, note="the same project at another path, through the shared compiler store"),
        Case("shared-compiler-moved-trap-relative", "trap", BUILD, copy_to_other_root, env=store, group=g, note="single-file entry built by a relative path from another root"),
        Case("shared-compiler-trap-absolute", "trap", BUILD, with_command("build", "{p}/main.selka", "-o", "{out}"), env=store, group=g, note="absolute spelling after a relative build, shared store on"),
        Case("shared-compiler-edit", "proj", BUILD, edit("util.selka", "p.x * p.x + p.y * p.y", "p.x * p.x + p.y * p.y + 2"), env=store, group=g),
        Case("shared-compiler-check-moved", "proj", CHECK, copy_to_other_root, env=store, group=g, note="check from another root with the shared store on"),
        Case("shared-compiler-sweep-edit", "sweep", BUILD, edit("lib.selka", "return side * side", "return side * side + 1"), env=store, group=g),
        Case("shared-tests-noop", "proj", TEST + tests_store, noop, group=g),
        Case("shared-tests-moved", "proj", TEST + tests_store, copy_to_other_root, group=g, note="the project at another root hits the shared receipts"),
        Case("shared-tests-edit-reached", "proj", TEST + tests_store, edit("mathlib.selka", "return a + b", "return a + b + 1"), group=g, must_change=True),
        Case("shared-tests-embed", "proj", ["test", "util.selka"] + tests_store, write("label.txt", "LABEL-TWO"), group=g),
        Case("shared-tests-config", "proj", TEST + tests_store, write("selka.json", '{"version": 2, "limits": {"test": {"max_steps": 1}}}'), group=g, must_change=True),
        Case("shared-tests-other-root-edit", "proj", TEST + tests_store, lambda c: _fresh(_edit_copy(c, "mathlib.selka", "return a + b", "return a + b + 1")), group=g, must_change=True, note="another root whose reached function differs"),
    ]


def _edit_copy(c: CaseContext, name: str, old: str, new: str) -> Move:
    target = _copy(c)
    path = target / name
    path.write_text(path.read_text().replace(old, new, 1))
    return Move(project=target)


def all_cases(zig: Path, other: bool) -> list[Case]:
    return core_cases() + warning_cases() + configuration_cases() + flag_cases() + env_cases() + sweep_cases() + test_cases() + link_cases() + shared_cases() + toolchain_cases(zig) + location_cases() + import_use_cases() + facts_cases() + real_cases() + compiler_cases(other)


def command_mutate(args: argparse.Namespace) -> int:
    runner = Runner(args)
    cases = all_cases(Path(args.zig), bool(args.other_compiler))
    if args.case:
        cases = [c for c in cases if any(sel in c.name or sel == c.group for sel in args.case)]
    out_path = Path(args.evidence) / (args.output or "mutation-results.jsonl")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    results = []
    with open(out_path, "w") as sink:
        for case in cases:
            print(f"case {case.name} ...", file=sys.stderr, flush=True)
            try:
                result = runner.run_case(case)
            except Exception as error:  # a broken case is reported, never hidden
                result = {"case": case.name, "group": case.group, "verdict": "HARNESS ERROR", "why": f"{type(error).__name__}: {error}", "note": case.note}
            results.append(result)
            sink.write(json.dumps(result) + "\n")
            sink.flush()
            print(f"  {case.name:36s} {result['verdict']:34s} {result['why']}", flush=True)
    stale = [r for r in results if r["verdict"].startswith("STALE")]
    broken = [r for r in results if r["verdict"] == "HARNESS ERROR"]
    print(f"\n{len(results)} cases, {len(stale)} stale, {len(broken)} harness errors; results in {out_path}")
    return 1 if stale else 0


# --------------------------------------------------------------------------- racy subcommand


def command_racy(args: argparse.Namespace) -> int:
    """Alternate two same-size sources with no pause and require every build to run the current one.

    The replay record trusts an unchanged (size, inode, mtime, ctime) tuple.  A write that
    lands in the same timestamp tick as the recorded one and keeps the size would be
    served the previous build.  A modern kernel's multigrain timestamps close that
    window on most file systems; this loop measures it on the one it runs on.
    """
    folder = Path(args.work) / "racy"
    shutil.rmtree(folder, ignore_errors=True)
    (folder / "p").mkdir(parents=True)
    (folder / "tmp").mkdir()
    env = base_env({"TMPDIR": str(folder / "tmp")})
    source = 'func main(out: Stream) -> int:\n    print(out, "{}")\n    return 0\n'
    wrong = 0
    runs = args.runs
    for i in range(runs):
        word = "AAAA" if i % 2 == 0 else "BBBB"
        (folder / "p" / "main.selka").write_text(source.format(word))
        status, _, _ = run([str(args.compiler), "build", "main.selka", "-o", str(folder / "prog"), "--cache-dir", str(folder / "cache")], env=env, cwd=folder / "p")
        status2, out, _ = run([str(folder / "prog")], env=env, cwd=folder / "p")
        if status != 0 or status2 != 0 or out.strip() != word:
            wrong += 1
            print(f"iteration {i}: wrote {word}, the program printed {out.strip()!r}")
    fs = subprocess.run(["stat", "-f", "-c", "%T", str(folder)], capture_output=True, text=True).stdout.strip()
    print(f"{runs} alternating same-size builds on {fs}: {wrong} served a stale program")
    return 1 if wrong else 0


# --------------------------------------------------------------------------- corpus subcommand


def command_corpus(args: argparse.Namespace) -> int:
    """Write the corpora under <work>/corpus: the small projects, two repository copies and the real projects."""
    corpus = Path(args.work) / "corpus"
    for name, files in SMALL_CORPORA.items():
        for rel, text in files.items():
            path = corpus / name / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    for name, source in (("policy", ROOT / "tests" / "fixtures" / "module_projects"), ("api", ROOT / "examples" / "interface-files")):
        shutil.rmtree(corpus / name, ignore_errors=True)
        shutil.copytree(source, corpus / name)
    for name, repository, path in (("eda", args.eda, "stage2/selka"), ("selka", args.selka, "markdown")):
        if not Path(repository).is_dir():
            print(f"skipping {name}: {repository} is not a repository", file=sys.stderr)
            continue
        destination = corpus / name
        shutil.rmtree(destination, ignore_errors=True)
        destination.mkdir(parents=True)
        archive = subprocess.run(["git", "-C", repository, "archive", "main", path], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", str(destination)], input=archive, check=True)
    print(f"corpora written under {corpus}")
    return 0


# --------------------------------------------------------------------------- table subcommand


def load_results(args: argparse.Namespace, names: list[str]) -> dict[str, dict]:
    merged: dict[str, dict] = {}
    for name in names:
        path = Path(name) if os.path.isabs(name) else Path(args.evidence) / name
        for line in path.read_text().splitlines():
            if line.strip():
                row = json.loads(line)
                merged[row["case"]] = row
    return merged


def command_table(args: argparse.Namespace) -> int:
    """Merge result files (later files win per case) into a markdown table, STALE rows first.

    With --baseline, a column shows the verdict the same case had on the baseline files."""
    final = load_results(args, args.files)
    base = load_results(args, args.baseline) if args.baseline else {}
    order = {"STALE": 0, "STALE?": 1, "HARNESS ERROR": 2}
    rows = sorted(final.values(), key=lambda r: (order.get(r["verdict"], 3), r.get("group", ""), r["case"]))
    header = "| case | group | verdict | output changed | what the case does |"
    rule = "| --- | --- | --- | --- | --- |"
    if base:
        header = "| case | group | before the fixes | after | output changed | what the case does |"
        rule = "| --- | --- | --- | --- | --- | --- |"
    print(header)
    print(rule)
    for r in rows:
        changed = "yes" if r.get("changed_output") else "no"
        if base:
            before = base.get(r["case"], {}).get("verdict", "not run")
            print(f"| `{r['case']}` | {r.get('group', '')} | {before} | {r['verdict']} | {changed} | {r.get('note', '')} |")
        else:
            print(f"| `{r['case']}` | {r.get('group', '')} | {r['verdict']} | {changed} | {r.get('note', '')} |")
    counts: dict[str, int] = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print()
    print(", ".join(f"{k}: {v}" for k, v in sorted(counts.items())) + f"; {len(rows)} cases")
    return 0


# --------------------------------------------------------------------------- fuzz subcommand


def command_fuzz(args: argparse.Namespace) -> int:
    """Apply a chain of small edits to a real project; after each, a warm command must equal a clean one.

    Edits mostly keep the program valid: a comment line before or after a module or inside a
    body, a blank line before a top-level declaration, two neighbouring functions exchanged,
    a string literal lengthened, a raised integer constant, or putting a module back to an
    earlier text (so the caches meet a state they have seen).  An edit that breaks the build
    breaks it for the clean command too; the two must still agree.  The warm command keeps
    one cache directory across the whole chain.  Mismatches are listed with the edit.
    """
    import random
    corpus = {"selka": ("selka", "markdown", ["build", "md2html.selka", "-o", "{out}"]),
              "selka-check": ("selka", "markdown", ["check", "site.selka"]),
              "eda": ("eda", "stage2/selka/src", ["build", "main.selka", "-o", "{out}"]),
              "eda-check": ("eda", "stage2/selka/src", ["check", "main.selka"]),
              "selka-test": ("selka", "markdown", ["test", "."])}[args.target]
    template, subdir, command = corpus
    rng = random.Random(args.seed)
    work = Path(args.work) / "fuzz" / args.target
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    project = work / "p"
    shutil.copytree(Path(args.work) / "corpus" / template, project, symlinks=True)
    (work / "tmp").mkdir()
    env = base_env({"TMPDIR": str(work / "tmp")})
    runner = Runner(args)
    case = Case("fuzz", template, command)
    root = project / subdir
    modules = sorted(p for p in root.rglob("*.selka") if "oracle" not in p.parts and not p.name.endswith("_test.selka"))
    history: dict[Path, list[str]] = {}
    mismatches = 0
    log = []

    def edit_once() -> str:
        path = rng.choice(modules)
        text = path.read_text()
        history.setdefault(path, []).append(text)
        kind = rng.choice(["prepend", "append", "blank", "bump", "undo", "swap", "inner", "string", "literal"])
        rel = str(path.relative_to(root))
        if kind == "prepend":
            path.write_text("# fuzz\n" + text)
        elif kind == "append":
            path.write_text(text + "\n# fuzz\n")
        elif kind == "blank":
            lines = text.split("\n")
            spots = [i for i, line in enumerate(lines) if re.match(r"^(public )?func ", line) and i > 0]
            if not spots:
                return f"{rel}: no declaration to space"
            lines.insert(rng.choice(spots), "")
            path.write_text("\n".join(lines))
        elif kind == "bump":
            match = re.search(r"^((?:public )?const [A-Za-z_]+: int = )(\d+)$", text, re.M)
            if not match:
                return f"{rel}: no constant to bump"
            path.write_text(text[:match.start(2)] + str(int(match.group(2)) + 1) + text[match.end(2):])
        elif kind == "swap":
            # exchange two neighbouring top-level declarations (blocks separated by blank lines that start at column 0)
            blocks = re.split(r"\n\n+(?=\S)", text)
            spots = [i for i in range(len(blocks) - 1) if re.match(r"(?:public )?func ", blocks[i]) and re.match(r"(?:public )?func ", blocks[i + 1])]
            if not spots:
                return f"{rel}: no pair of functions to swap"
            i = rng.choice(spots)
            blocks[i], blocks[i + 1] = blocks[i + 1], blocks[i]
            path.write_text("\n\n".join(blocks))
        elif kind == "inner":
            lines = text.split("\n")
            spots = [i for i, line in enumerate(lines) if line.startswith("    ") and not line.strip().startswith(("#", "\"", "elif", "else", "case", "except")) and i > 0 and not lines[i - 1].rstrip().endswith("\\")]
            if not spots:
                return f"{rel}: no body line"
            at = rng.choice(spots)
            indent = len(lines[at]) - len(lines[at].lstrip())
            lines.insert(at, " " * indent + "# fuzz inner")
            path.write_text("\n".join(lines))
        elif kind == "literal":
            # a behavioural edit: raise one integer literal that sits in code (not in a comment or a string)
            lines = text.split("\n")
            candidates = [(i, m) for i, line in enumerate(lines) if not line.lstrip().startswith("#") and '"' not in line
                          for m in re.finditer(r"(?<![\w.])(\d{1,3})(?![\w.])", line)]
            if not candidates:
                return f"{rel}: no integer literal"
            i, m = rng.choice(candidates)
            lines[i] = lines[i][:m.start(1)] + str(int(m.group(1)) + 1) + lines[i][m.end(1):]
            path.write_text("\n".join(lines))
        elif kind == "string":
            matches = list(re.finditer(r'"([A-Za-z ]{4,20})"', text))
            if not matches:
                return f"{rel}: no string literal"
            m = rng.choice(matches)
            path.write_text(text[:m.start(1)] + m.group(1) + "x" + text[m.end(1):])
        else:
            earlier = history[path]
            if len(earlier) > 1:
                path.write_text(earlier[rng.randrange(len(earlier) - 1)])
        return f"{rel}: {kind}"

    cache = work / "cache"
    base = runner.observe(case, work, root, command, env, cache, "base", [])
    print(f"baseline: {base.reuse}", flush=True)
    for step in range(args.steps):
        what = edit_once()
        warm = runner.observe(case, work, root, command, env, cache, "warm", [])
        clean = runner.observe(case, work, root, command, env, work / "cache-clean", "clean", ["--no-cache"])
        differences = [name for name, a, b in (("exit", warm.status, clean.status), ("stdout", warm.stdout, clean.stdout), ("stderr", warm.stderr, clean.stderr), ("program", warm.program, clean.program)) if a != b]
        note = f"step {step:3d} {what:60s} {warm.reuse:15s}"
        if differences:
            mismatches += 1
            note += "  MISMATCH: " + ", ".join(differences)
            if "program" in differences:
                # keep both executables of a mismatch for a byte-level comparison, then ask the clean command twice more
                for label in ("warm", "clean"):
                    source_file = work / f"out-{label}"
                    if source_file.is_file():
                        shutil.copy2(source_file, work / f"mismatch-{step}-{label}")
                again = [runner.observe(case, work, root, command, env, work / "cache-clean", f"reclean{n}", ["--no-cache"]).program for n in (1, 2)]
                note += "  reclean: " + ", ".join((h or "-")[:8] for h in again) + f" (warm {(warm.program or '-')[:8]}, clean {(clean.program or '-')[:8]})"
                # and the LLVM text each side produces now: equal text means the objects or the link differ, unequal text means emission does
                if command[0] == "build":
                    texts = {}
                    for label, cache_dir, extra in (("warm", cache, []), ("clean", work / "cache-clean", ["--no-cache"])):
                        target = work / f"mismatch-{step}-{label}.ll"
                        runner.observe(case, work, root, command, env, cache_dir, f"llvm-{label}", ["--emit-llvm", str(target), *extra])
                        texts[label] = target
                    if texts["warm"].is_file() and texts["clean"].is_file():
                        a_bytes, b_bytes = texts["warm"].read_bytes(), texts["clean"].read_bytes()
                        if a_bytes == b_bytes:
                            note += "  LLVM text equal"
                        else:
                            first = next((i for i, (x, y) in enumerate(zip(a_bytes.split(b"\n"), b_bytes.split(b"\n"))) if x != y), -1)
                            note += f"  LLVM text DIFFERS (first differing line {first + 1})"
        print(note, flush=True)
        log.append({"step": step, "edit": what, "warm": dataclasses.asdict(warm), "clean": dataclasses.asdict(clean), "differences": differences})
    out = Path(args.evidence) / f"fuzz-{args.target}-{args.seed}.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(log, indent=1))
    print(f"{args.steps} edits, {mismatches} mismatched; details in {out}")
    return 1 if mismatches else 0


# --------------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", default=str(ROOT / "zig-out" / "bin" / "selka"))
    parser.add_argument("--zig", default=os.environ.get("ZIG", "zig"))
    parser.add_argument("--work", default=str(DEFAULT_WORK))
    parser.add_argument("--evidence", default=str(HOME / "ai" / "canopy" / "mylang-evidence-archive" / "experiments" / "cache-read-audit-20261026"))
    sub = parser.add_subparsers(dest="command", required=True)
    c = sub.add_parser("corpus", help="write the corpora the cases mutate under <work>/corpus")
    c.add_argument("--eda", default=str(HOME / "ai" / "canopy" / "eda-bench"), help="repository holding EDA stage 2 on main (stage2/selka)")
    c.add_argument("--selka", default=str(HOME / "ai" / "canopy" / "selka-projects"), help="repository holding selka markdown on main")
    t = sub.add_parser("trace")
    t.add_argument("scenario", nargs="*")
    e = sub.add_parser("env")
    e.add_argument("--json")
    m = sub.add_parser("mutate")
    m.add_argument("case", nargs="*", help="case names (substrings) or group names: replay flags environment stand-ins tests link")
    m.add_argument("--output", help="results file name under --evidence (default mutation-results.jsonl)")
    m.add_argument("--other-compiler", help="a second compiler (a rebuilt one) for the `compiler` cases: warm on the first, then the second on the same caches")
    fz = sub.add_parser("fuzz", help="chains of small edits to a real project, each checked against a clean build")
    fz.add_argument("target", choices=["selka", "selka-check", "eda", "eda-check", "selka-test"])
    fz.add_argument("--steps", type=int, default=40)
    fz.add_argument("--seed", type=int, default=1)
    tb = sub.add_parser("table", help="merge result files into a markdown table")
    tb.add_argument("files", nargs="+")
    tb.add_argument("--baseline", nargs="*", default=[], help="result files of the same cases on the compiler before the fixes")
    tc = sub.add_parser("toolchain", help="compare the toolchain files `zig` opens with the set tool_files.zig tracks")
    tc.add_argument("--json")
    tc.add_argument("--write-list", action="store_true", help="rewrite src/core/tool_files.list from the files the non-thread commands opened")
    r = sub.add_parser("racy", help="alternate two same-size sources immediately and check every build")
    r.add_argument("--runs", type=int, default=300)
    args = parser.parse_args()
    args.compiler = Path(args.compiler)
    args.zig = Path(args.zig)
    return {"trace": command_trace, "env": command_env, "mutate": command_mutate, "racy": command_racy, "toolchain": command_toolchain, "table": command_table, "fuzz": command_fuzz, "corpus": command_corpus}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
