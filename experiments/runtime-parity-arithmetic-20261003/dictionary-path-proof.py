"""Untimed P5 code-path evidence, run through scripts/build-slot.sh build."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TEMP = Path(os.environ["TMPDIR"])
BEFORE = "2af5d62a"
SOURCES = [
    "native_heap.c", "native_arena.c", "native_collections.c", "native_text.c",
    "native_dictionary.c", "native_equal.c", "native_bytes.c", "native_search.c",
    "native_trim.c", "native_repr.c", "native_rc.c", "native_rc_stats.c",
    "native_rc_shapes.c", "native_rc_walk.c", "native_rc_scope.c",
    "native_rc_transfer.c", "native_rc_alloc.c", "native_rc_values.c",
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def arm(label, dictionary):
    executable = TEMP / f"dictionary-path-{label}"
    sources = [dictionary if name == "native_dictionary.c" else ROOT / "src" / name
               for name in SOURCES]
    commands, objects = [], []
    for index, source in enumerate([*sources, HERE / "dictionary-path-proof.c"]):
        obj = TEMP / f"dictionary-path-{label}-{index}.o"
        command = ["zig", "cc", "-O3", "-std=c11", "-UNDEBUG", "-ffunction-sections",
                   "-fdata-sections", "-I", str(ROOT / "src"), "-c", str(source), "-o", str(obj)]
        subprocess.run(command, cwd=ROOT, check=True)
        commands.append(command)
        objects.append(str(obj))
    # Zig's integrated linker does not support --wrap; use the host linker on
    # the unchanged Zig-generated objects to count this public runtime call.
    command = ["cc", *objects, "-Wl,--gc-sections", "-Wl,--wrap=myl_rc_value_retain_many",
               "-Wl,--wrap=myl_rc_native_retain_replace",
               "-o", str(executable)]
    subprocess.run(command, cwd=ROOT, check=True)
    commands.append(command)
    result = json.loads(subprocess.check_output([str(executable)], text=True))
    assembly = subprocess.check_output(["objdump", "-dr", "--disassemble=rc_insert_result",
                                        str(executable)], text=True)
    (HERE / f"dictionary-{label}.asm").write_text(assembly)
    return {"source_sha256": digest(dictionary), "executable_sha256": digest(executable),
            "commands": commands, "observed": result,
            "assembly_sha256": digest(HERE / f"dictionary-{label}.asm")}


old = TEMP / "dictionary-before.c"
old.write_bytes(subprocess.check_output(["git", "show", f"{BEFORE}:src/native_dictionary.c"], cwd=ROOT))
receipt = {"kind": "untimed-code-path-diagnostic", "baseline_commit": BEFORE,
           "proof_sha256": digest(HERE / "dictionary-path-proof.c"),
           "compiler": subprocess.check_output(["zig", "version"], text=True).strip(),
           "before": arm("before", old), "after": arm("after", ROOT / "src/native_dictionary.c")}
for field in ("checksum", "allocations", "bytes"):
    assert receipt["before"]["observed"][field] == receipt["after"]["observed"][field]
assert receipt["after"]["observed"]["scalar_insert_transactions"] == 0
assert receipt["after"]["observed"]["set_insert_transactions"] == 0
assert receipt["after"]["observed"]["set_duplicate_transactions"] == 0
assert receipt["after"]["observed"]["set_duplicate_replacements"] == 0
(HERE / "p5-dictionary-paths.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps({label: receipt[label]["observed"] for label in ("before", "after")}, indent=2))
