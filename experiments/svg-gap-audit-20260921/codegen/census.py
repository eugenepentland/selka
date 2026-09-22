#!/usr/bin/env python3
"""Static census for the qualified accounting matrix; performs no executions."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "experiments/svg-gap-audit-20260921/codegen"
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
NAMES = ("none", "step", "frame", "both")

def sha_bytes(data): return hashlib.sha256(data).hexdigest()
def sha(path): return sha_bytes(Path(path).read_bytes())

def count_ir(manifest):
    doc = json.loads(manifest.read_text())
    text = "\n".join(row["il"] for row in doc["functions"])
    blits = [int(x) for x in re.findall(r"\bblit [^\n]+, (\d+)\s*$", text, re.M)]
    calls = re.findall(r"\bcall \$([^ (]+)", text)
    collection = [x for x in calls if any(word in x for word in ("list", "array", "collection", "dictionary"))]
    return {
        "functions": len(doc["functions"]),
        "qbe_lines": text.count("\n") + 1,
        "qbe_instruction_lines": len(re.findall(r"^ ", text, re.M)),
        "position_stores": len(re.findall(r"^ storel \d+, %position$", text, re.M)),
        "step_success_labels": len(re.findall(r"^@step\d+$", text, re.M)),
        "step_limit_calls": calls.count("myl_qbe_fail_step"),
        "frame_limit_calls": calls.count("myl_qbe_fail_frame"),
        "require_step_calls": calls.count("myl_qbe_require_step_accounting"),
        "require_frame_calls": calls.count("myl_qbe_require_frame_accounting"),
        "frame_counter_loads": len(re.findall(r"=l add %ctx, 8$", text, re.M)),
        "active_frame_accesses": len(re.findall(r"=l add %ctx, 48$", text, re.M)),
        "frame_limit_accesses": len(re.findall(r"=l add %ctx, 56$", text, re.M)),
        "frame_floor_accesses": len(re.findall(r"=l add %ctx, 64$", text, re.M)),
        "root_slots": len(re.findall(r"=l alloc8 32$", text, re.M)),
        "root_mark_calls": calls.count("myl_qbe_root_mark"),
        "blit_count": len(blits),
        "blit_bytes": sum(blits),
        "calls": len(calls),
        "collection_calls": len(collection),
        "collection_call_symbols": {x: collection.count(x) for x in sorted(set(collection))},
    }

def main():
    report = {"variants": {}}
    for name in NAMES:
        binary = WORK / f"gc-lto-{name}"
        emitted = WORK / f"emitted-{name}.json"
        linked = Path(str(binary) + ".qbe-manifest.json")
        disassembly = subprocess.run(["objdump", "-d", "--no-show-raw-insn", str(binary)], check=True, capture_output=True).stdout
        instructions = re.findall(rb"^\s+[0-9a-f]+:\s+([a-z][a-z0-9.]*)", disassembly, re.M)
        linked_doc = json.loads(linked.read_text())
        object_hashes = sorted(sha(row["object"]) for row in linked_doc["functions"])
        report["variants"][name] = {
            "binary": str(binary.relative_to(ROOT)), "binary_sha256": sha(binary),
            "binary_bytes": binary.stat().st_size,
            "emitted_manifest_sha256": sha(emitted),
            "linked_manifest_sha256": sha(linked),
            "runtime_object_sha256": sha(linked_doc["runtime_object"]),
            "function_object_count": len(object_hashes),
            "function_objects_digest": sha_bytes(("\n".join(object_hashes) + "\n").encode()),
            "ir": count_ir(emitted),
            "disassembly_sha256": sha_bytes(disassembly),
            "machine_instruction_count": len(instructions),
            "machine_call_count": sum(x.startswith(b"call") for x in instructions),
            "machine_conditional_branch_count": sum(x.startswith(b"j") and x not in (b"jmp", b"jmpq") for x in instructions),
            "machine_load_store_count": sum(x.startswith((b"mov", b"stos")) for x in instructions),
        }
    (OUT / "accounting-census.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

if __name__ == "__main__": main()
