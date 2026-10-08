#!/usr/bin/env python3
"""Compare imported loop-body diagnostics and object ownership with old/whole builds."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from trace_units import command, FLAGS, ROOT

CASES = {
    "cold_cfg": (
        "module app\nimport leaf\ndef main(args: list[str]) -> int:\n    x = 9223372036854775807\n"
        "    if len(args) > 0:\n        x = 0\n    return leaf.origin(x)\n",
        "module leaf\npublic def origin(x: int) -> int:\n"
        + "".join(f"    if x == {i + 1}:\n        return {i + 1}\n" for i in range(16))
        + "    total = 0\n    for i in range(2):\n        total += x\n    return total\n",
    ),
    "cold_loop": (
        "module app\nimport leaf\ndef main() -> int:\n    return leaf.origin(9223372036854775807)\n",
        "module leaf\npublic def origin(x: int) -> int:\n    total = 0\n    for i in range(2):\n        total += x\n    return total\n",
    ),
    "overflow": (
        "module app\nimport leaf\ndef main() -> int:\n    total = 0\n    for i in range(2):\n"
        "        total += leaf.origin(9223372036854775807)\n    return total\n",
        "module leaf\npublic def origin(x: int) -> int:\n    if x < 0:\n        return 0\n    return x + 1\n",
    ),
    "assert": (
        "module app\nimport leaf\ndef main() -> int:\n    total = 0\n    for i in range(2):\n"
        "        total += leaf.origin(i + 1)\n    return total\n",
        "module leaf\npublic def origin(x: int) -> int:\n    assert x == 0, \"loop check\"\n    return x\n",
    ),
    "result": (
        "module app\nimport leaf\ndef main() -> Result[int, str]:\n    for i in range(2):\n"
        "        value = leaf.origin(i)?\n        assert value >= 0\n    return Ok(0)\n",
        "module leaf\npublic def origin(x: int) -> Result[int, str]:\n    return Err(\"loop failure\")\n",
    ),
    "integer": (
        "module app\nimport leaf\ndef main() -> Result[int, str]:\n    for i in range(2):\n"
        "        value = leaf.origin[int](i)?\n        assert value >= 0\n    return Ok(0)\n",
        "module leaf\npublic def origin[T](x: T) -> Result[T, str]:\n    return Err(\"generic failure\")\n",
    ),
    "string": (
        "module app\nimport leaf\ndef main() -> Result[int, str]:\n    for i in range(2):\n"
        "        value = leaf.origin[str](\"x\")?\n        assert len(value) >= 0\n    return Ok(0)\n",
        "module leaf\npublic def origin[T](x: T) -> Result[T, str]:\n    return Err(\"generic failure\")\n",
    ),
}
DEFINITION = re.compile(r'^define (?P<linkage>[^@\n]*)@"(?P<name>[^"\n]+)"\(', re.MULTILINE)


def identity(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def inspect_objects(area, native, mode):
    report = []
    owners = {}
    imports = set()
    for number, llvm in enumerate(sorted(native.glob("program-*/*.ll"))):
        text = llvm.read_text()
        definitions = list(DEFINITION.finditer(text))
        for definition in definitions:
            name = definition["name"]
            if "available_externally" in definition["linkage"]:
                imports.add(name)
            else:
                owners[name] = owners.get(name, 0) + 1
        obj = area / f"unit-{number}.o"
        command(["zig", "cc", "-c", "-O0" if mode == "debug" else "-O3", *FLAGS,
                 "-Wno-override-module", "-o", obj, llvm], area / f"compile-object-{number}.json")
        symbols = command(["nm", "--defined-only", obj], area / f"symbols-{number}.json")
        names = {line.split(maxsplit=2)[-1] for line in symbols["stdout"].splitlines() if line.strip()}
        for definition in definitions:
            if "available_externally" in definition["linkage"] and definition["name"] in names:
                raise ValueError(f"imported body emitted an object definition: {llvm}/{definition['name']}")
        report.append({**identity(llvm), "object": identity(obj), "imports": [d["name"] for d in definitions
                       if "available_externally" in d["linkage"]]})
    if mode != "debug" and not imports:
        raise ValueError("release loop fixture emitted no imported body")
    for name in imports:
        if owners.get(name) != 1:
            raise ValueError(f"imported function has {owners.get(name)} real definitions: {name}")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--cases", nargs="+", choices=CASES, default=CASES)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(ROOT / "experiments")
    area.mkdir(parents=True, exist_ok=False)
    report = {"qualified": False, "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"],
              cwd=ROOT, text=True).strip(), "compilers": {"old": identity(args.old), "new": identity(args.new)},
              "comparisons": []}
    cache = ROOT / ".mylang-cache/s4-emission" / area.name
    cache.mkdir(parents=True, exist_ok=False)
    try:
        for case in args.cases:
            sources = CASES[case]
            source = area / case
            source.mkdir()
            for name, text in zip(("app.my", "leaf.my"), sources):
                (source / name).write_text(text)
            for mode in ("debug", "release", "verify"):
                run_area = area / f"{case}-{mode}"
                run_area.mkdir()
                native = cache / f"{case}-{mode}"
                whole_llvm = run_area / "whole.ll"
                split = native / "split"
                old = native / "old"
                whole = native / "whole"
                build_new = [args.new.resolve(), "build", source / "app.my", "-o", split,
                             "--cache-dir", native / "new", "--emit-llvm", whole_llvm]
                build_old = [args.old.resolve(), "build", source / "app.my", "-o", old, "--cache-dir", native / "old-cache"]
                if mode != "debug":
                    build_new.append("--release")
                    build_old.append("--release")
                if mode == "verify":
                    build_new.append("--verify-facts")
                command(build_new, run_area / "build-new.json")
                command(build_old, run_area / "build-old.json")
                runtimes = list((native / "new").glob("core_rt-*.o"))
                if len(runtimes) != 1:
                    raise ValueError(f"ambiguous runtime: {runtimes}")
                command(["zig", "cc", "-O0" if mode == "debug" else "-O3", *FLAGS,
                         "-Wno-override-module", "-o", whole, whole_llvm, runtimes[0]], run_area / "build-whole.json")
                outputs = {label: command([path], run_area / f"run-{label}.json", 1)
                           for label, path in (("old", old), ("split", split), ("whole", whole))}
                expected = (outputs["old"]["stdout"], outputs["old"]["stderr"])
                for label, result in outputs.items():
                    if (result["stdout"], result["stderr"]) != expected:
                        raise ValueError(f"diagnostic bytes differ: {case}/{mode}/{label}")
                    if "leak:" in result["stderr"]:
                        raise ValueError(f"native leak: {case}/{mode}/{label}")
                units = inspect_objects(run_area, native / "new", mode)
                report["comparisons"].append({"case": case, "mode": mode, "identical": True,
                                              "stderr": expected[1], "units": units})
                print(f"{case}/{mode}: exact old/split/whole diagnostics; unique real definitions", flush=True)
        for label, path in (("old", args.old), ("new", args.new)):
            if identity(path) != report["compilers"][label]:
                raise ValueError(f"compiler changed: {label}")
        report["qualified"] = True
    finally:
        (area / "summary.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
