#!/usr/bin/env python3
"""FU-PORT: does the integration's timing carry over to the new syntax? Emit release LLVM
(`mylang build --release --emit-llvm`) for the 45 parity programs, the 46 rows, the Lox port and
EDA with four ReleaseFast compilers:
  A  main ab85c16c2 (~/.cache/mylang/main-ab85c16c)     on claude/fu-x's old-syntax sources
  X  claude/fu-x    (~/.cache/mylang/fu-final-x)       on the same old-syntax sources
  M  main e23651f6a (.mylang-cache/compilers/main-*)   on the new-syntax sources
  P  the port       (.mylang-cache/compilers/port-*)   on the same new-syntax sources
and compare normalized text: every build runs in its source root with a relative path; the
root's absolute path, `source_filename`, debug-info metadata (`!DI*` nodes and `!dbg`
attachments), the line and column of each trap site record (`@myl.site.N`), and the spelling
of function names (quoted symbols renamed in order of first appearance; the name strings
`@myl.fn.N` and source path strings `@myl.path.N` that trap reports print: a headered module
reported its file's basename, a headerless one its path from the project root) are normalized away; `compare` also reports which programs
are identical without the name normalization. Everything else, including non-debug metadata, is compared exactly.
  (a) P == X: the port's code for the new source is fu-x's code for the old source.
  (b) M == A as well means the redesign changed nothing in that program's code, and P differs
      from M exactly as X differs from A.
usage: llvm_identity.py emit [FILTER]   |   llvm_identity.py compare OUT.json"""
import concurrent.futures, json, os, re, subprocess, sys
from pathlib import Path

WT = Path(__file__).resolve().parents[3]
WORK = WT / ".mylang-cache/fuport/llvm"
SLOT = WT / "scripts/build-slot.sh"
COMPILERS = {
    "A": Path.home() / ".cache/mylang/main-ab85c16c/bin/mylang",
    "X": Path.home() / ".cache/mylang/fu-final-x/bin/mylang",
    "M": WT / ".mylang-cache/compilers/main-e23651f6/bin/mylang",
    "P": WT / ".mylang-cache/compilers/port-a4636591/bin/mylang",
}
OLD = {"tree": WT / ".tmp/fux-src", "lox": WT / ".tmp/lox-mylang-orig", "eda": WT / ".tmp/eda-src-orig"}
NEW = {"tree": WT, "lox": WT / ".mylang-cache/lox/ports/mylang", "eda": WT / ".mylang-cache/eda-src"}
S0 = ("binary_search", "int_math", "float_math", "call_direct", "branch_mixed", "branch_predictable")
CLOCK = "benchmarks/runtime/ports/native_clock.c"


def jobs():
    out = []
    for group in ("suite", "micro", "lib"):
        for source in sorted((WT / "bench/parity" / group).glob("*.my")):
            out.append((f"parity-{group}-{source.stem}", "tree", f"bench/parity/{group}/{source.name}", []))
    rows = sorted(p.stem for p in (WT / "test/core").glob("row_*.my")) + list(S0)
    for stem in rows:
        out.append((f"row-{stem.removeprefix('row_')}", "tree", f"test/core/{stem}.my", [CLOCK]))
    out.append(("lox", "lox", "main.my", []))
    out.append(("eda", "eda", "src/main.my", []))
    return out


def emit(tag, job):
    label, root_key, rel, links = job
    root = (OLD if tag in "AX" else NEW)[root_key]
    directory = WORK / tag
    directory.mkdir(parents=True, exist_ok=True)
    llvm = directory / f"{label}.ll"
    env = dict(os.environ, TMPDIR=str(WT / ".tmp"), MYLANG_CORE_RUNTIME_CACHE=str(WT / ".mylang-cache/core-runtime"))
    argv = [str(SLOT), "build", str(COMPILERS[tag]), "build", rel, "-o", str(directory / f"{label}.bin"), "--release",
            "--emit-llvm", str(llvm), "--cache-dir", str(WORK / "cache" / tag)]
    for link in links:
        argv += ["--link", link]
    done = subprocess.run(argv, cwd=root, env=env, capture_output=True)
    return label, done.returncode


SITE = re.compile(r"^(@myl\.site\.\d+ = private constant %myl\.site \{ i32 -?\d+, )i32 -?\d+, i32 -?\d+, ")


QUOTED = re.compile(r'@"[^"]*"')
FN_NAME = re.compile(r'^(@myl\.(?:fn|path)\.\d+ = private constant )\[\d+ x i8\] c"[^"]*"')


def rename(text):
    """Quoted symbols (`@"my.module::name"`, `@"my.lambda@OFFSET"`) renamed in order of first
    appearance: the redesign's headerless entry modules drop the `module::` prefix, and a lambda's
    name carries its byte offset, which moves with any edit above it."""
    names = {}
    return QUOTED.sub(lambda m: names.setdefault(m.group(0), f'@"S{len(names)}"'), text)


def normalize(text, root, symbols=True):
    if symbols:
        text = rename(text)
    lines = []
    for line in text.replace(str(root), "<ROOT>").split("\n"):
        # Debug metadata: `!DI*` nodes, and every node in the emitter's debug numbering range
        # (from !1000000: the module flags that name the debug-info versions).
        if (line.startswith(("source_filename", "!llvm.dbg.cu", "!llvm.module.flags")) or re.match(r"^!\d+ = (distinct )?!DI", line)
                or re.match(r"^!1\d{6,} = ", line)):
            continue
        line = re.sub(r",? !dbg !\d+", "", line)
        line = SITE.sub(r"\1i32 L, i32 C, ", line)
        if symbols:
            line = FN_NAME.sub(r'\1[N x i8] c"FUNCTION"', line)
        lines.append(line)
    return "\n".join(lines)


def load(tag, job, symbols=True):
    path = WORK / tag / f"{job[0]}.ll"
    if not path.exists():
        return None
    return normalize(path.read_text(), (OLD if tag in "AX" else NEW)[job[1]], symbols)


def main():
    if sys.argv[1] == "emit":
        selected = [j for j in jobs() if len(sys.argv) < 3 or sys.argv[2] in j[0]]
        tasks = [(tag, job) for job in selected for tag in "AXMP"]
        with concurrent.futures.ThreadPoolExecutor(3) as pool:
            results = list(pool.map(lambda t: (t[0], *emit(*t)), tasks))
        failed = [r for r in results if r[2] != 0]
        print(f"emitted {len(results) - len(failed)} of {len(results)}; failed: {failed}")
        return
    report = {"compilers": {k: str(v) for k, v in COMPILERS.items()}, "programs": {}}
    for job in jobs():
        texts = {tag: load(tag, job) for tag in "AXMP"}
        if any(t is None for t in texts.values()):
            report["programs"][job[0]] = {"missing": [t for t, v in texts.items() if v is None]}
            continue
        exact = {tag: load(tag, job, False) for tag in "PX"}
        report["programs"][job[0]] = {"P==X": texts["P"] == texts["X"], "M==A": texts["M"] == texts["A"],
                                      "X==A": texts["X"] == texts["A"], "P==M": texts["P"] == texts["M"],
                                      "P==X with names": exact["P"] == exact["X"]}
    Path(sys.argv[2]).write_text(json.dumps(report, indent=1) + "\n")
    rows = report["programs"]
    for key in ("P==X", "M==A", "X==A", "P==M", "P==X with names"):
        differ = sorted(k for k, v in rows.items() if not v.get(key, False))
        print(f"{key}: {len(rows) - len(differ)} of {len(rows)} identical; not: {differ}")


if __name__ == "__main__":
    main()
