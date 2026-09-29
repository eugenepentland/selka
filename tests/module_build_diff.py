#!/usr/bin/env python3
"""MODULE-COMPILE-1 build differential: an incremental per-module build after
seeded edits must build what a clean whole-program build builds.

usage: module_build_diff.py MYLANG [--project DIR] [--steps N] [--seed S]
                            [--arg-sets FILE] [--keep DIR]

The project (default `tests/fixtures/module_compile`) is copied to a work
directory and built once per module, in import order, with `compile-module`
and `link-modules`. Each step then restores the pristine sources, applies one
or two seeded edits (literals, operators, byte strings, record field order, an
added function, a no-op statement, a comment), and rebuilds two ways:

- clean and whole-program: `emit-project-qbe` with a fresh cache, then `build`;
- incremental and per-module: a module is compiled again only when its own
  source changed, the program's arena switch changed, or an interface it read
  last time (by its interface, emission and positions hashes) is not the one
  there now; every other module keeps its interface, units and objects from
  the steps before. Then `link-modules`.

Both must reject the same edited programs; for a program that builds, every
unit (text and metadata digests) and the executable itself must be the same,
and running it (with no arguments, and with each argument list in
`--arg-sets`, a JSON list of lists) must give the same stdout, stderr and exit
status. The summary counts steps, rejections, modules compiled and reused, and
mismatches; the exit status is 1 on any mismatch.
"""
import argparse
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run(cmd, cwd=None, timeout=900):
    try:
        return subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def mutations(rng, text):
    out = []
    for m in re.finditer(r"(?<![\w.\[])(\d+)(?![\w.])", text):
        out.append(("int literal", text[:m.start()] + str(int(m.group(1)) + rng.choice([1, 2, 7])) + text[m.end():]))
    for pat, rep in [(" < ", " <= "), (" > ", " >= "), (" + 1", " + 2"), (" - 1", " - 2"), (" == ", " != "), (" * 2", " * 3")]:
        idx = [m.start() for m in re.finditer(re.escape(pat), text)]
        if idx:
            i = rng.choice(idx)
            out.append((f"op {pat.strip()}->{rep.strip()}", text[:i] + rep + text[i + len(pat):]))
    for m in re.finditer(r'"([^"\\]{2,})"', text):
        out.append(("text literal", text[:m.start()] + '"' + m.group(1)[::-1] + '"' + text[m.end():]))
    lines = text.split("\n")
    for i in range(len(lines) - 1):
        a, b = lines[i], lines[i + 1]
        if re.match(r"^    \w+: [\w\[\]., ]+$", a) and re.match(r"^    \w+: [\w\[\]., ]+$", b):
            out.append(("swap fields", "\n".join(lines[:i] + [b, a] + lines[i + 2:])))
    out.append(("add function", text + "\n\npublic def zz_added_fn(n: int) -> int:\n    return n + 1\n"))
    out.append(("comment", text.replace("\n\n\n", "\n\n\n# an edit that moves lines\n", 1)))
    for m in re.finditer(r"^(public )?def \w+\(.*\)( -> [^:]+)?( effects\([^)]*\))?:\n", text, re.M):
        out.append(("body no-op", text[:m.end()] + "    zz_ok: int = 1\n    _ = zz_ok\n" + text[m.end():]))
    return out


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest() if Path(path).exists() else None


class Differential:
    def __init__(self, args, work):
        self.mylang = str(Path(args.mylang).resolve())
        self.work = work
        self.tree = work / "tree"
        self.modules_dir = work / "modules"
        self.arg_sets = [[]] + (json.loads(Path(args.arg_sets).read_text()) if args.arg_sets else [])
        # module -> {"source": sha, "inputs": [...], "hashes": {...}, "arenas": str}
        self.state = {}
        self.stats = {"steps": 0, "built": 0, "rejected": 0, "compiled": 0, "reused": 0, "mismatches": 0, "runs": 0}

    def entry(self):
        return self.tree / "main.my"

    def whole(self):
        """The clean whole-program build: manifest, report and executable, or None."""
        out = self.work / "whole"
        shutil.rmtree(out, ignore_errors=True)
        out.mkdir()
        proc = run([self.mylang, "emit-project-qbe", str(self.entry()), "--lean-manifest=executable", f"--cache-dir={out / 'cache'}",
                    f"--emission-report={out / 'report.json'}"])
        if proc is None or proc.returncode != 0:
            return None
        (out / "manifest.json").write_bytes(proc.stdout)
        proc = run([self.mylang, "build", str(self.entry()), "--project", f"--manifest-file={out / 'manifest.json'}", "-o", str(out / "program"),
                    f"--cache-dir={out / 'cache'}"])
        if proc is None or proc.returncode != 0:
            raise SystemExit(f"harness error: the whole-program link failed: {proc and proc.stderr[-800:]}")
        return {"manifest": json.loads((out / "manifest.json").read_text()), "report": json.loads((out / "report.json").read_text()),
                "program": out / "program"}

    def current_hashes(self, module):
        return self.state.get(module, {}).get("hashes")

    def stale(self, module, arenas):
        known = self.state.get(module)
        if known is None or known["arenas"] != arenas:
            return True
        if known["source"] != digest(self.tree / f"{module.replace('.', '/')}.my"):
            return True
        for item in known["inputs"]:
            now = self.current_hashes(item["module"])
            if now is None:
                continue  # a standard module is read from the compiler
            if (now["interface"], now["emission"], now["positions"]) != (item["interface"], item["emission"], item["positions"]):
                return True
        return False

    def incremental(self, order, arenas):
        """Compile what is stale in import order; returns (status, compiled)."""
        compiled = 0
        for module in order:
            if not self.stale(module, arenas):
                self.stats["reused"] += 1
                continue
            proc = run([self.mylang, "compile-module", str(self.entry()), f"--module={module}", f"--interfaces={self.modules_dir / 'if'}",
                        f"--out={self.modules_dir / 'out'}", f"--cache-dir={self.modules_dir / 'cache'}", arenas, "--objects"])
            if proc is None or proc.returncode != 0:
                return "rejected", compiled
            summary = json.loads(proc.stdout)
            compiled += 1
            self.state[module] = {"source": digest(self.tree / f"{module.replace('.', '/')}.my"), "inputs": summary["hashes"]["inputs"],
                                  "hashes": summary["hashes"], "arenas": arenas}
        self.stats["compiled"] += compiled
        proc = run([self.mylang, "link-modules", str(self.entry()), f"--units={self.modules_dir / 'out'}", "-o", str(self.modules_dir / "program"),
                    f"--cache-dir={self.modules_dir / 'cache'}"])
        if proc is None or proc.returncode != 0:
            raise SystemExit(f"harness error: link-modules failed: {proc and proc.stderr[-800:]}")
        return "built", compiled

    def behaviour(self, program):
        results = []
        for args in self.arg_sets:
            proc = run([str(program)] + [str(a) for a in args], cwd=self.tree, timeout=20)
            results.append("timeout" if proc is None else (proc.returncode, proc.stdout, proc.stderr))
        return results

    def compare(self, reference, what):
        problems = []
        linked = json.loads((self.modules_dir / "out" / "program.json").read_text())
        want = {u["symbol"]: (u["il_digest"], u["meta_digest"]) for u in reference["manifest"]["functions"]}
        got = {u["symbol"]: (u["il_digest"], u["meta_digest"]) for u in linked["functions"]}
        if want != got:
            differing = sorted(s for s in set(want) | set(got) if want.get(s) != got.get(s))
            problems.append(f"{len(differing)} units differ")
        for key in ("runtime_data", "host", "text_format", "entry"):
            if linked.get(key) != reference["manifest"].get(key):
                problems.append(f"linked {key} differs")
        if reference["program"].read_bytes() != (self.modules_dir / "program").read_bytes():
            problems.append("executables differ")
        runs = self.behaviour(self.modules_dir / "program")
        self.stats["runs"] += len(runs)
        if runs != self.behaviour(reference["program"]):
            problems.append("runs differ")
        if problems:
            self.stats["mismatches"] += 1
            print(f"MISMATCH ({what}): {problems}", flush=True)
            shutil.copytree(self.tree, self.work / f"mismatch-{self.stats['steps']}", dirs_exist_ok=True)
        return not problems

    def step(self, what):
        reference = self.whole()
        if reference is None:
            order = sorted(p.stem for p in self.tree.glob("*.my"))
            status, compiled = self.incremental(self.topological_fallback(order), "--arenas=off")
            if status != "rejected":
                self.stats["mismatches"] += 1
                print(f"MISMATCH ({what}): the whole program rejects it and the per-module build does not", flush=True)
            self.stats["rejected"] += 1
            return
        order = topological(reference["report"]["modules"])
        arenas = "--arenas=on" if reference["report"]["arenas"] else "--arenas=off"
        status, compiled = self.incremental(order, arenas)
        if status == "rejected":
            self.stats["mismatches"] += 1
            print(f"MISMATCH ({what}): the per-module build rejects what the whole program builds", flush=True)
            return
        self.stats["built"] += 1
        if self.compare(reference, what):
            print(f"ok ({what}): {compiled} module(s) compiled", flush=True)

    def topological_fallback(self, names):
        """Import order from the sources, for a program the whole build rejected."""
        modules = []
        for name in names:
            text = (self.tree / f"{name}.my").read_text()
            modules.append({"name": name, "imports": [m for m in re.findall(r"^import (\w+)", text, re.M) if (self.tree / f"{m}.my").exists()]})
        return topological(modules)


def topological(modules):
    imports = {m["name"]: m["imports"] for m in modules}
    order, state = [], {}

    def visit(name):
        if state.get(name):
            return
        state[name] = 1
        for dependency in sorted(imports.get(name, [])):
            visit(dependency)
        order.append(name)

    for name in sorted(imports):
        visit(name)
    return order


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("--project", default="tests/fixtures/module_compile")
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--arg-sets")
    parser.add_argument("--keep")
    args = parser.parse_args()
    work = Path(args.keep or tempfile.mkdtemp(prefix="module-build-diff-"))
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    diff = Differential(args, work)
    shutil.copytree(args.project, diff.tree, ignore=shutil.ignore_patterns(".mylang-cache"))
    # Test modules are not part of the program the entry builds.
    pristine = {p.name: p.read_text() for p in diff.tree.glob("*.my") if not re.search(r"_tests?\.my$", p.name)}
    rng = random.Random(args.seed)
    diff.step("pristine")
    for number in range(1, args.steps + 1):
        diff.stats["steps"] = number
        for name, text in pristine.items():
            (diff.tree / name).write_text(text)
        edits = []
        for _ in range(1 if rng.random() < 0.7 else 2):
            name = rng.choice(sorted(pristine))
            path = diff.tree / name
            label, text = rng.choice(mutations(rng, path.read_text()))
            path.write_text(text)
            edits.append(f"{name}: {label}")
        diff.step(f"step {number}: " + "; ".join(edits))
    print(json.dumps(diff.stats))
    if not args.keep and diff.stats["mismatches"] == 0:
        shutil.rmtree(work, ignore_errors=True)
    return 1 if diff.stats["mismatches"] else 0


if __name__ == "__main__":
    sys.exit(main())
