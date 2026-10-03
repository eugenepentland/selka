#!/usr/bin/env python3
"""Read-only source binding and lexical model; no compiler or guest execution."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess

W = Path(__file__).resolve().parents[2]
E = Path(__file__).resolve().parent
B = W.parent
BASE = "3b33df52044a10cb84b908f8b1641af439e8c729"
ROOT = B / "codex-lox-parity-20261003"
PORT = ROOT / ".tmp-lox-round3/ast"
NATIVE = B / "codex-lox-native-case-glue-20261003"
BORROW = B / "codex-lox-borrow-assert-20261003/.tmp-lox-borrow-assert-20261003"
FILES = [
    "build_qbe_assets.zig", "src/qbe_build.zig", "src/qbe_build_options.zig",
    "src/qbe_build_backend.zig", "src/qbe_build_cache.zig", "src/qbe_build_batch.zig",
    "src/qbe_build_units.zig", "src/qbe_build_outputs.zig", "src/qbe_build_sites.zig",
    "src/qbe_build_llvm.zig", "src/qbe_build_llvm_il.zig", "src/qbe_build_llvm_compile.zig",
    "src/qbe_build_llvm_lower.zig", "src/qbe_fragments.zig", "src/qbe_rc_cache.zig",
    "src/qbe.zig", "src/qbe_rc_glue.zig", "src/qbe_rc_slots.zig",
    "src/qbe_rc_values.zig", "src/qbe_rc_frame.zig", "src/qbe_zero.zig",
    "src/rc_shape.zig", "src/native_types.zig", "src/native_descriptors.zig",
    "src/rc_glue.zig", "src/native_interface.zig", "src/main.zig",
    "src/compiler.zig", "src/project_compile.zig", "src/module_build.zig",
    "src/module_compile.zig", "src/module_compile_command.zig", "src/module_interface.zig",
    "src/native_test_options.zig", "src/native_test_session.zig",
    "src/native_test_command.zig", "src/native_test_directory.zig",
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return path.read_bytes()


def strip_comment(line):
    # Exact lexical loop in selected qbe_build_llvm_il.stripComment. This is
    # a Python model, not an actual LLVM translation or an ownership proof.
    quoted = False
    for index, byte in enumerate(line):
        if byte == '"':
            quoted = not quoted
        if byte == "#" and not quoted:
            return line[:index].strip()
    return line.strip()


def symbols(text):
    # Selected referencedSymbols scans raw text, including comments.
    return sorted(set(re.findall(r"\$+([A-Za-z0-9_.$]+)", text)))


def lexical(text):
    return [line for raw in text.splitlines() if (line := strip_comment(raw))]


def main():
    for name in ("analysis.json", "raw.json.gz"):
        assert not (E / name).exists(), f"refuse overwrite: {name}"
    raw = {}
    core = {}
    for name in FILES:
        data = subprocess.check_output(["git", "show", f"{BASE}:{name}"], cwd=W)
        assert read(W / name) == data, f"selected source differs: {name}"
        raw["selected/" + name] = data.decode()
        core[name] = sha(data)
    frozen = json.loads(read(W / ".tmp-lox-variant-number-tag-20261003/frozen-source.json"))
    source37 = frozen["source37"]
    assert len(source37) == 37
    for name, expected in source37.items():
        assert sha(read(PORT / name)) == expected, name
    descriptor_path = NATIVE / ".tmp-lox-native-case-20261003/proof-v2.json"
    descriptor = read(descriptor_path)
    assert sha(descriptor) == "33dc940cb303d78bc5556009e63f932b041458107234e1248fc04d64f952632a"
    native = json.loads(descriptor)
    assert native["base"] == BASE and len(native["files"]) == 12
    for name, expected in native["files"].items():
        data = read(NATIVE / ".tmp-lox-native-case-20261003/proof-v2" / name)
        assert sha(data) == expected, name
        raw["native-v2/" + name] = data.decode()
    raw["native-v2/proof-v2.json"] = descriptor.decode()
    controls = {
        str(BORROW / "fixed-qbe-ast"): "246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25",
        str(BORROW / "fixed-llvm-ast"): "180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361",
        str(B / "codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang"):
            "d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040",
        str(B / "codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/qbe"):
            "99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63",
    }
    for path, expected in controls.items():
        assert sha(read(Path(path))) == expected, path
    models = []
    for name in ("vm-load_frame.ssa", "vm-run.ssa"):
        data = read(W / ".tmp-lox-load-frame-diagnostic-20261003" / name)
        text = data.decode()
        # Illustrative inert marker only; no claimed native plan or API grammar.
        comment = " # myl-native-v2-plan diagnostic-only type=00 size=16 align=8 tags=0,1 src=%v1 dst=%v2 region=%v3 private=0\n"
        lines = text.splitlines(keepends=True)
        changed = "".join(comment + line if "_rcg_take(" in line or "_rcg_drop(" in line or "_rcg_unloan(" in line else line for line in lines)
        assert lexical(text) == lexical(changed)
        assert symbols(text) == symbols(changed)
        poisoned = changed + " # diagnostic-only $not_an_original_symbol\n"
        assert symbols(poisoned) != symbols(text)
        raw["selected-il/" + name] = text
        models.append({
            "file": name, "sha256": sha(data), "illustrative_comment_sites": changed.count(comment),
            "noncomment_lines_equal": True, "raw_symbol_set_equal": True,
            "dollar_comment_changes_raw_symbol_set": True,
            "actual_translation_or_codegen_executed": False,
        })
    document = {
        "scope": "read-only feasibility; no implementation, compile, test, guest execution, performance or speed claim",
        "selected_core_commit": BASE, "selected_core_files": core,
        "selected_source_path": str(PORT), "selected_source37": source37,
        "native_v2_commit": "9ab993c1b9e2088c471ea1b57c98361b8554d0ae",
        "native_v2_descriptor": {"path": str(descriptor_path), "sha256": sha(descriptor), "files": native["files"]},
        "selected_artifacts": controls, "lexical_models": models,
        "recommendation": "explicit frontend native-case emission policy, original by default, enabled only for resolved QBE; partition all policy-dependent emission and replay/module keys",
        "byte_equivalence": "feasible by early default refusal before temp/layout/shape queries, but actual whole-program LLVM IL/IR/ELF equivalence remains unexecuted",
    }
    # Recheck source and tool identities before publishing the diagnostic.
    for name, expected in source37.items():
        assert sha(read(PORT / name)) == expected
    for path, expected in controls.items():
        assert sha(read(Path(path))) == expected
    for name, expected in core.items():
        assert sha(read(W / name)) == expected
    payload = json.dumps(raw, sort_keys=True, separators=(",", ":")).encode()
    (E / "raw.json.gz").write_bytes(gzip.compress(payload, mtime=0))
    document["raw_archive_sha256"] = sha(read(E / "raw.json.gz"))
    document["verified_before_after"] = True
    (E / "analysis.json").write_text(json.dumps(document, sort_keys=True, indent=2) + "\n")
    print(json.dumps({"core_files": len(core), "source_files": 37, "native_v2_files": 12,
                      "lexical_models": models, "raw_sha256": document["raw_archive_sha256"]}))


if __name__ == "__main__":
    main()
