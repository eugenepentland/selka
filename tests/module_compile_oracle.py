#!/usr/bin/env python3
"""MODULE-COMPILE-1 equivalence harness: compile every module of a program on
its own, from its imports' interfaces, and compare with the whole-program build.

usage: module_compile_oracle.py MYLANG ENTRY_OR_DIR... [--jobs N] [--json OUT]
                                [--release] [--no-run] [--work DIR] [--keep]

For every program (a directory contributes each `*.my` under it; an entry
without `main` is built through a generated driver module that imports it):

1. the whole-program reference: `emit-project-qbe --lean-manifest=executable
   --emission-report` (the build frontend `mylang build` runs), then
   `build --manifest-file` to link it, and `interfaces emit` for the
   check-level interfaces;
2. the per-module build: `compile-module` for every module of the program, in
   import order, each reading only its imports' interfaces (which the earlier
   compiles wrote), into a separate cache; then `link-modules`.

It asserts, function by function: the same unit set; equal fragment unit keys,
IL digests (hence object unit keys) and metadata digests; equal emission facts
(may-allocate, parameter writes); each module's interface hash and positions
hash equal to `interfaces emit`'s; the linked manifest's runtime data, host
bridges and text switch equal to the whole program's; and, unless --no-run,
the same stdout, stderr and exit status from both executables (trap traces are
on stderr). Exit status 1 when anything differs or fails to run.
"""
import argparse
import concurrent.futures
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

RELEASE = ["--drop-debug", "--drop-step-checks", "--drop-frame-checks"]
MAIN = re.compile(r"^(public\s+)?def\s+main\s*\(", re.M)


def entries(paths):
    out = []
    for path in paths:
        p = Path(path)
        if p.is_dir():
            out += sorted(q for q in p.rglob("*.my") if ".mylang-cache" not in q.parts)
        else:
            out.append(p)
    return out


def run(cmd, cwd=None, timeout=600, env=None):
    started = time.perf_counter()
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return None, time.perf_counter() - started
    return proc, time.perf_counter() - started


def text(data):
    return data.decode("utf-8", "replace")


class Program:
    """One program to compare: its entry, and where its work goes."""

    def __init__(self, mylang, entry, work, release, runtime):
        self.mylang = str(Path(mylang).resolve())
        self.entry = Path(entry).resolve()
        self.work = work
        self.release = release
        self.runtime = runtime
        self.runtime_flags = ["--gc-runtime"] if runtime == "gc" else ["--rc-runtime" + ("=" + runtime if runtime != "rc" else "")]
        self.env = dict(os.environ, TMPDIR=os.environ.get("TMPDIR", str(work)))

    def invoke(self, args, **kwargs):
        return run([self.mylang, args[0], *self.runtime_flags, *args[1:]], **kwargs)

    def prepare(self):
        """The entry the build runs: the file itself when it declares `main`,
        else a driver module beside a copy of its directory that imports it."""
        source = self.entry.read_text()
        named = bool(re.search(r"^module\s", source, re.M))
        if MAIN.search(source) and named:
            return self.entry
        mirror = self.work / "src"
        shutil.copytree(self.entry.parent, mirror, ignore=shutil.ignore_patterns(".mylang-cache"))
        name = self.entry.stem
        # Standalone corpus entries have no header. Give the module-path
        # comparison one deterministic projection, retaining line numbers.
        projected = mirror / self.entry.name
        if not named:
            projected.write_text(f"module {name}; " + source)
        if MAIN.search(source):
            return projected
        driver = mirror / f"mcdrv_{name}.my"
        driver.write_text(f"module mcdrv_{name}\nimport {name}\n\n\ndef main() -> int:\n    return 0\n")
        return driver

    def result(self):
        out = {"entry": str(self.entry), "status": "equal", "problems": []}
        try:
            self.compare(out)
        except Failure as failure:
            out["status"] = failure.status
            out["problems"].append(failure.detail)
        if out["problems"] and out["status"] == "equal":
            out["status"] = "different"
        return out

    def compare(self, out):
        entry = self.prepare()
        whole = self.work / "whole"
        whole.mkdir(parents=True)
        flags = RELEASE if self.release else []
        report_path = whole / "report.json"
        proc, wall = self.invoke(["emit-project-qbe", str(entry), "--lean-manifest=executable", f"--cache-dir={whole / 'cache'}",
                          f"--emission-report={report_path}"] + flags, env=self.env)
        if proc is None or proc.returncode != 0:
            raise Failure("reference-failed", "emit-project-qbe: " + ("timeout" if proc is None else text(proc.stderr)[-1500:]))
        (whole / "manifest.json").write_bytes(proc.stdout)
        manifest = json.loads(proc.stdout)
        report = json.loads(report_path.read_text())
        out["whole_emit_seconds"] = round(wall, 3)
        iface_dir = whole / "interfaces"
        proc, _ = self.invoke(["interfaces", "emit", str(entry), f"--out={iface_dir}"], env=self.env)
        if proc is None or proc.returncode != 0:
            raise Failure("reference-failed", "interfaces emit: " + ("timeout" if proc is None else text(proc.stderr)[-1500:]))
        index = {row["module"]: row for row in json.loads(proc.stdout)["modules"]}
        order = topological(report["modules"])
        modules = self.work / "modules"
        arenas = "--arenas=on" if report["arenas"] else "--arenas=off"
        compiled = {}
        seconds = 0.0
        # A ReleaseFast comparison stops at the units; a Debug one builds each
        # module's objects too, which the link must then only reuse.
        objects = [] if self.release else ["--objects"]
        for module in order:
            proc, wall = self.invoke(["compile-module", str(entry), f"--module={module}", f"--interfaces={modules / 'if'}",
                              f"--out={modules / 'out'}", f"--cache-dir={modules / 'cache'}", arenas] + objects + flags, env=self.env)
            seconds += wall
            if proc is None or proc.returncode != 0:
                raise Failure("compile-failed", f"compile-module {module}: " + ("timeout" if proc is None else text(proc.stderr)[-1500:]))
            compiled[module] = json.loads(proc.stdout)
        out["modules"] = len(order)
        out["compile_seconds"] = round(seconds, 3)
        self.compareInterfaces(out, compiled, index)
        units = {}
        for module in order:
            data = json.loads((modules / "out" / f"{module}.units.json").read_text())
            for row in data["units"]:
                units.setdefault(row["name"], []).append((module, row))
        self.compareUnits(out, manifest, report, units)
        all_units = {}
        for module in order:
            data = json.loads((modules / "out" / f"{module}.units.json").read_text())
            for row in data["manifest"]["functions"]:
                previous = all_units.setdefault(row["symbol"], row)
                for key in ("il_digest", "meta_digest", "il", "locations", "messages", "inlines"):
                    if previous.get(key) != row.get(key):
                        out["problems"].append(f"{module}: conflicting shared unit {row['symbol']}: {key}")
        whole_symbols = {row["symbol"]: row for row in manifest["functions"]}
        if set(all_units) != set(whole_symbols):
            out["problems"].append("complete canonical/alternate entry symbol sets differ")
        for symbol in set(all_units) & set(whole_symbols):
            for key in ("il_digest", "meta_digest", "il", "locations", "messages", "inlines"):
                if all_units[symbol].get(key) != whole_symbols[symbol].get(key):
                    out["problems"].append(f"{symbol}: {key} differs")
        out["physical_entries_compared"] = len(set(all_units) & set(whole_symbols))
        out["physical_contracts"] = {
            "borrowed": sum(symbol.endswith("_rc_borrow") for symbol in whole_symbols),
            "immortal": sum(symbol.endswith("_rc_immortal") for symbol in whole_symbols),
            "stable_parameters": sum(sum(row["marks"]["physical"]["stable"]) for row in report["functions"]),
            "stood_in": sum(row["counts"]["stood_in"] for row in compiled.values()),
        }
        if self.entry.parent.name == "module_rc" and self.runtime != "gc":
            if not all(out["physical_contracts"].values()):
                out["problems"].append("RC fixture omitted a required borrowed/immortal/pin/import contract")
        if self.release:
            return
        self.link(out, entry, whole, modules, flags)

    def compareInterfaces(self, out, compiled, index):
        compared = 0
        for module, summary in compiled.items():
            reference = index.get(module)
            if reference is None:
                continue
            compared += 1
            for key, name in (("interface", "interface_hash"), ("positions", "positions_hash"), ("implementation", "implementation_hash")):
                if summary["hashes"][key] != reference[name]:
                    out["problems"].append(f"{module}: {key} hash differs from `interfaces emit`")
        out["interfaces_compared"] = compared

    def compareUnits(self, out, manifest, report, units):
        whole_units = {f["name"]: f for f in manifest["functions"] if "il_digest" in f}
        facts = {f["name"]: f for f in report["functions"]}
        missing = sorted(set(whole_units) - set(units))
        extra = sorted(set(units) - set(whole_units))
        if missing:
            out["problems"].append(f"units the whole program emits and no module does: {missing[:8]}")
        if extra:
            out["problems"].append(f"units a module emits and the whole program does not: {extra[:8]}")
        compared = shared = 0
        for name, emitted in units.items():
            if name not in whole_units:
                continue
            reference = facts[name]
            shared += len(emitted) > 1
            for module, row in emitted:
                compared += 1
                wanted = {"unit_key": reference["keys"]["unit"], "il": reference["keys"]["il"], "meta": reference["keys"]["meta"],
                          "allocates": reference["allocates"], "writes": reference["writes"]}
                for key, value in wanted.items():
                    if row[key] != value:
                        out["problems"].append(f"{module}: {name}: {key} differs")
        out["units_compared"] = compared
        out["units_whole"] = len(whole_units)
        out["specializations_shared"] = shared

    def link(self, out, entry, whole, modules, flags):
        whole_exe = whole / "program"
        proc, _ = self.invoke(["build", str(entry), "--project", f"--manifest-file={whole / 'manifest.json'}", "-o", str(whole_exe),
                       f"--cache-dir={whole / 'cache'}"], env=self.env)
        if proc is None or proc.returncode != 0:
            raise Failure("reference-failed", "build: " + ("timeout" if proc is None else text(proc.stderr)[-1500:]))
        module_exe = modules / "program"
        proc, wall = self.invoke(["link-modules", str(entry), f"--units={modules / 'out'}", "-o", str(module_exe),
                          f"--cache-dir={modules / 'cache'}", "--report"], env=self.env)
        out["link_seconds"] = round(wall, 3)
        if proc is None or proc.returncode != 0:
            raise Failure("link-failed", "link-modules: " + ("timeout" if proc is None else text(proc.stderr)[-1500:]))
        build = next((json.loads(line) for line in text(proc.stdout).splitlines() if line.startswith('{"version":"qbe-build-v1"')), {})
        # Every guest object comes from a module compile; the link compiles
        # only the program-wide metadata and entry units.
        out["link_compiled_function_objects"] = build.get("compiled_function_objects")
        if build.get("compiled_function_objects") != 0:
            out["problems"].append(f"the link compiled {build.get('compiled_function_objects')} guest objects no module compile had built")
        linked = json.loads((modules / "out" / "program.json").read_text())
        reference = json.loads((whole / "manifest.json").read_text())
        for key in ("runtime_data", "host", "text_format", "entry", "entry_parameters", "entry_argv_element"):
            if linked.get(key) != reference.get(key):
                out["problems"].append(f"linked manifest: {key} differs from the whole program's")
        out["executables_identical"] = whole_exe.read_bytes() == module_exe.read_bytes()
        if not out["executables_identical"]:
            out["problems"].append("the whole-program and module executables differ in bytes")
        if not self.execute:
            return
        results = []
        for exe in (whole_exe, module_exe):
            proc, _ = run([str(exe)], cwd=self.work, timeout=120, env=self.env)
            results.append(None if proc is None else (proc.returncode, proc.stdout, proc.stderr))
        if any(result is None for result in results):
            out["problems"].append("an executable timed out")
        elif results[0] != results[1]:
            out["problems"].append("the executables' stdout, stderr or exit status differ")
        out["exit_status"] = None if results[0] is None else results[0][0]


class Failure(Exception):
    def __init__(self, status, detail):
        super().__init__(detail)
        self.status = status
        self.detail = detail


def topological(modules):
    """Modules in an order where each comes after everything it imports."""
    imports = {m["name"]: m["imports"] for m in modules}
    order, state = [], {}

    def visit(name):
        if state.get(name) == 2:
            return
        state[name] = 1
        for dependency in sorted(imports.get(name, [])):
            if state.get(dependency) != 1:
                visit(dependency)
        state[name] = 2
        order.append(name)

    for name in sorted(imports):
        visit(name)
    return order


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mylang")
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1))
    parser.add_argument("--json")
    parser.add_argument("--runtime", choices=("rc", "stats", "sites", "gc"), default="rc")
    parser.add_argument("--release", action="store_true", help="compare ReleaseFast emission (keys and facts only)")
    parser.add_argument("--no-run", action="store_true", help="link but do not run the executables")
    parser.add_argument("--work", help="work directory (default: a temporary one)")
    parser.add_argument("--keep", action="store_true")
    args = parser.parse_args()
    root = Path(args.work or tempfile.mkdtemp(prefix="module-compile-")).resolve()
    root.mkdir(parents=True, exist_ok=True)
    todo = entries(args.paths)
    if not todo:
        parser.error("the accepted corpus must contain at least one entry")

    def one(numbered):
        number, entry = numbered
        work = root / f"{number:04d}-{entry.stem}"
        shutil.rmtree(work, ignore_errors=True)
        work.mkdir(parents=True)
        program = Program(args.mylang, entry, work, args.release, args.runtime)
        program.execute = not args.no_run
        result = program.result()
        if not args.keep and result["status"] == "equal":
            shutil.rmtree(work, ignore_errors=True)
        return result

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(one, enumerate(todo)))
    totals = {"programs": len(results), "equal": 0, "reference_failed": 0, "modules": 0, "units_compared": 0, "units_whole": 0,
              "specializations_shared": 0, "interfaces_compared": 0, "executables_identical": 0, "different": []}
    for result in results:
        if result["status"] == "reference-failed":
            totals["reference_failed"] += 1
            continue
        for key in ("modules", "units_compared", "units_whole", "specializations_shared", "interfaces_compared"):
            totals[key] += result.get(key, 0)
        totals["executables_identical"] += bool(result.get("executables_identical"))
        if result["status"] == "equal":
            totals["equal"] += 1
        else:
            totals["different"].append({"entry": result["entry"], "status": result["status"], "problems": result["problems"][:6]})
    if args.json:
        Path(args.json).write_text(json.dumps({"totals": totals, "results": results}, indent=1))
    print(json.dumps(totals, indent=1))
    if not args.keep and not totals["different"]:
        shutil.rmtree(root, ignore_errors=True)
    return 0 if not totals["different"] and not totals["reference_failed"] and totals["equal"] == totals["programs"] else 1


if __name__ == "__main__":
    sys.exit(main())
