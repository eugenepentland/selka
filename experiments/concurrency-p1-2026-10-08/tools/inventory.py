#!/usr/bin/env python3
"""Extract P1-0's declared static objects and myl_block count member accesses.

Usage: python3 experiments/concurrency-p1-2026-10-08/tools/inventory.py
The AST is scratch (about 124 MB); only the compact inventories are evidence.
String literals and Zig compile-time constants are classified in REPORT.md.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "evidence")
OUT = parser.parse_args().output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
SCRATCH = ROOT / ".tmp" / "concurrency-p1-inventory"
SCRATCH.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, TMPDIR=str(SCRATCH),
           ZIG_LOCAL_CACHE_DIR=str(ROOT / ".zig-cache"),
           ZIG_GLOBAL_CACHE_DIR=str(ROOT.parent / ".zig-global-cache"))
driver = (ROOT / "src/core/driver.zig").read_text().split("pub const runtime_source =", 1)[1].split(";", 1)[0]
files = re.findall(r'@embedFile\("([^"]+)"\)', driver)
files.insert(1, "runtime/core_count.h")
files.append("runtime/core_count.c")
source = SCRATCH / "inventory.c"
source.write_text("".join(f'#include "{ROOT / "src/core" / name}"\n' for name in files))
command = [str(ROOT / "scripts/build-slot.sh"), "build", "zig", "cc", "-std=c11"]
compiled = subprocess.run(command + ["-c", str(source), "-o", str(SCRATCH / "inventory.o")],
                          cwd=ROOT, env=env, capture_output=True, text=True)
(OUT / "inventory-compile.log").write_text(compiled.stdout + compiled.stderr)
compiled.check_returncode()
with (SCRATCH / "ast.json").open("w") as output:
    dumped = subprocess.run(command + ["-Xclang", "-ast-dump=json", "-fsyntax-only", str(source)],
                            cwd=ROOT, env=env, stdout=output, stderr=subprocess.PIPE, text=True)
(OUT / "inventory-ast.log").write_text(dumped.stderr)
# Zig's cc wrapper can look for a nonexistent object after Clang's AST-only
# action succeeds. Preserve that exit status; accept only this known wrapper
# error, and require both a real object compile above and a complete JSON AST.
if dumped.returncode and not ("error: FileNotFound" in dumped.stderr and
                              dumped.stderr.count("error:") == 1):
    dumped.check_returncode()
ast = json.loads((SCRATCH / "ast.json").read_text())
assert ast["kind"] == "TranslationUnitDecl"
state = {"file": ""}
objects, counts = [], []


def visit(node, parent="", function=""):
    loc = node.get("loc", {})
    state["file"] = loc.get("file", state["file"])
    file = state["file"]
    kind = node.get("kind", "")
    if kind == "FunctionDecl":
        function = node.get("name", "")
    if "/src/core/runtime/" in file:
        text = Path(file).read_text()
        relative = str(Path(file).relative_to(ROOT))
        if kind == "VarDecl" and (parent == "TranslationUnitDecl" or node.get("storageClass") in ("static", "extern")):
            objects.append({"file": relative, "line": text[:loc.get("offset", 0)].count("\n") + 1,
                            "name": node.get("name"), "function": function,
                            "type": node.get("type", {}).get("qualType", "").replace(str(ROOT) + "/", ""),
                            "storage": node.get("storageClass", "global")})
        if (kind == "MemberExpr" and node.get("name") == "count" and node.get("inner") and
                "myl_block" in node["inner"][0].get("type", {}).get("qualType", "")):
            line = text[:node["range"]["begin"]["offset"]].count("\n") + 1
            row = {"file": relative, "line": line, "function": function,
                   "source": text.splitlines()[line - 1].strip()}
            if row not in counts:
                counts.append(row)
    for child in node.get("inner", []):
        visit(child, kind, function)


visit(ast)
for name, rows in (("static-storage", objects), ("count-accesses", counts)):
    (OUT / (name + ".json")).write_text(json.dumps(rows, indent=2) + "\n")
summary = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
           "toolchain": subprocess.check_output(["zig", "version"], text=True).strip(),
           "object_compile_exit": compiled.returncode, "ast_wrapper_exit": dumped.returncode,
           "static_declarations": len(objects), "count_access_lines": len(counts)}
(OUT / "inventory.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary))
