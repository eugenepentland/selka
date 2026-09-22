#!/usr/bin/env python3
"""Capture syntax/performance audit evidence from an existing compiler, without rebuilding it."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
COMPILER = ROOT / "zig-out/bin/mylang"
CASES = {
    "format": 'def format_value(x: int, y: int) -> str:\n    return f"x={x}; y={y}!"\n',
    "comprehension": 'def transform(xs: list[int]) -> list[int]:\n    return [x + 1 for x in xs]\n',
    "range_comprehension": 'def transform(n: int) -> list[int]:\n    return [x + 1 for x in range(n)]\n',
    "bytes_slice": 'def parse(b: bytes, start: int, end: int) -> Option[int]:\n    return b[start:end].parse_int()\n',
    "bytes_view": 'def parse(b: bytes, start: int, end: int) -> Option[int]:\n    return b.view(start, end).parse_int()\n',
    "bytes_range": 'def parse(b: bytes, start: int, end: int) -> Option[int]:\n    return b.parse_int_range(start, end)\n',
    "bytes_slice_noalloc": 'def parse(b: bytes, start: int, end: int) -> Option[int] noalloc:\n    return b[start:end].parse_int()\n',
    "bytes_view_noalloc": 'def parse(b: bytes, start: int, end: int) -> Option[int] noalloc:\n    return b.view(start, end).parse_int()\n',
    "bytes_range_noalloc": 'def parse(b: bytes, start: int, end: int) -> Option[int] noalloc:\n    return b.parse_int_range(start, end)\n',
    "minimum_text_noalloc": 'def minimum(xs: list[str]) -> str noalloc:\n    return min(xs)\n',
    "minimum_text": 'def minimum(xs: list[str]) -> str:\n    return min(xs)\n',
    "minimum_int_noalloc": 'def minimum(xs: list[int]) -> int noalloc:\n    return min(xs)\n',
    "sort_in_place": 'def order(xs: list[int]):\n    xs.sort()\n',
    "sort_copy": 'def order(xs: list[int]) -> list[int]:\n    return sorted(xs)\n',
    "sort_text": 'def order(xs: list[str]) -> list[str]:\n    return sorted(xs)\n',
    "dict_items_direct": 'def total(d: dict[str, int]) -> int noalloc:\n    result = 0\n    for key, value in d.items():\n        result += value\n    return result\n',
    "dict_values_direct": 'def total(d: dict[str, int]) -> int noalloc:\n    result = 0\n    for value in d.values():\n        result += value\n    return result\n',
    "record_projection": 'record Point:\n    a: int\n    b: int\n    c: int\n    d: int\n\ndef project(p: Point) -> int:\n    return p.a\n',
    "prelude_float_noalloc": 'def parse(s: str) -> Option[float] noalloc:\n    return float(s)\n',
    "library_float": 'import strings\n\ndef parse(s: str) -> Option[float]:\n    return strings.to_float(s)\n',
    "library_int_noalloc": 'import strings\n\ndef parse(s: str) -> Option[int] noalloc:\n    return strings.to_int(s)\n',
    "removed_float_intrinsic": 'def root(x: float) -> float:\n    return f64_sqrt(x)\n',
}
RUNTIME = '''import strings

def main(out: Stream) -> int:
    out.print(float(" 1.5 "))
    out.print(strings.to_float(" 1.5 "))
    out.print(float("1_000.5"))
    out.print(strings.to_float("1_000.5"))
    out.print(float("inf"))
    out.print(strings.to_float("inf"))
    d = {"a": 10, "b": 20}
    out.print(d.items())
    for key, value in d.items():
        out.print(key)
        out.print(value)
    return 0
'''


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(args):
    result = subprocess.run([str(COMPILER), *args], cwd=ROOT, text=True,
                            capture_output=True, timeout=120)
    return {"command": ["zig-out/bin/mylang", *args], "exit_code": result.returncode,
            "stdout": result.stdout, "stderr": result.stderr}


def main():
    sources = HERE / "sources"
    ir = HERE / "ir"
    sources.mkdir(exist_ok=True)
    ir.mkdir(exist_ok=True)
    evidence = {"compiler_sha256_before": digest(COMPILER), "cases": {}}
    for name, source in CASES.items():
        path = sources / (name + ".my")
        path.write_text(source + '\ndef main() -> int:\n    return 0\n')
        relative = str(path.relative_to(ROOT))
        check = invoke(["check", relative])
        row = {"source_sha256": digest(path), "check": check}
        if check["exit_code"] == 0:
            command = "emit-project-qbe" if source.startswith("import ") else "emit-qbe"
            emitted = invoke([command, relative])
            output = emitted.pop("stdout")
            if emitted["exit_code"] != 0:
                raise RuntimeError(f"{name}: emission failed: {emitted['stderr']}")
            bundle = json.loads(output)
            selected = [function for function in bundle["functions"]
                        if any(location["path"] in (relative, path.name)
                               for location in function["locations"])]
            if not selected:
                raise RuntimeError(f"{name}: emitted no source functions")
            text = "\n".join("# " + function["name"] + "\n" + function["il"]
                             for function in selected)
            target = ir / (name + ".ssa")
            target.write_text(text)
            emitted["ir_path"] = str(target.relative_to(ROOT))
            emitted["functions"] = [function["name"] for function in selected]
            emitted["runtime_calls"] = sorted(set(re.findall(r'call \$(myl_native_[A-Za-z0-9_]+)', text)))
            emitted["text_concat_sites"] = len(re.findall(r'call \$myl_native_text_concat\(', text))
            emitted["aggregate_blit_sites"] = len(re.findall(r'\bblit ', text))
            row["emit"] = emitted
        evidence["cases"][name] = row
        print(name, check["exit_code"], flush=True)
    runtime = sources / "behavior.my"
    runtime.write_text(RUNTIME)
    evidence["behavior"] = invoke(["run", str(runtime.relative_to(ROOT))])
    evidence["compiler_sha256_after"] = digest(COMPILER)
    files = ["src/sema.zig", "src/prelude_builtins.zig", "src/native_collections.c",
             "src/native_text.c", "src/native_bytes.c", "src/stdlib/strings.my",
             "src/stdlib/sort.my", "src/removed_names.zig"]
    evidence["source_sha256_after"] = {path: digest(ROOT / path) for path in files}
    (HERE / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("behavior", evidence["behavior"]["exit_code"], evidence["behavior"]["stdout"],
          evidence["behavior"]["stderr"], flush=True)


if __name__ == "__main__":
    main()
