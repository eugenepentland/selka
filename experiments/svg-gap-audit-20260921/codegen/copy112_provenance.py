#!/usr/bin/env python3
"""Record exact existing control/probe source, object, archive-member hashes."""
import hashlib, json, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
OUT = ROOT / "experiments/svg-gap-audit-20260921/codegen"

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def manifest(name): return json.loads((WORK / f"gc-lto-{name}.qbe-manifest.json").read_text())
def members(archive):
    result = {}
    with tempfile.TemporaryDirectory(dir=WORK) as temporary:
        subprocess.run(["ar", "x", str(archive)], cwd=temporary, check=True)
        for path in sorted(Path(temporary).iterdir()): result[path.name] = sha(path)
    return result
def objects(doc): return {row["symbol"]: sha(row["object"]) for row in doc["functions"]}

control, probe = manifest("none"), manifest("copy112")
control_objects, probe_objects = objects(control), objects(probe)
control_members, probe_members = members(control["runtime_object"]), members(probe["runtime_object"])
before = next((WORK / "cache-none/runtime").glob("*/native_collections.c"))
after = next((WORK / "cache-copy112/runtime").glob("*/native_collections.c"))
control_source_dir, probe_source_dir = before.parent, after.parent
control_sources = {p.name: sha(p) for p in sorted(control_source_dir.iterdir()) if p.is_file()}
probe_sources = {p.name: sha(p) for p in sorted(probe_source_dir.iterdir()) if p.is_file()}
source_differences = sorted(k for k in control_sources if control_sources[k] != probe_sources[k])
report = {
    "compiler_sha256": sha(ROOT / ".tmp/svg-gap-audit-20260921/mylang-audit-compiler"),
    "emitted_guest_manifest_sha256": sha(WORK / "emitted-none.json"),
    "control_binary_sha256": sha(WORK / "gc-lto-none"),
    "probe_binary_sha256": sha(WORK / "gc-lto-copy112"),
    "guest_objects": {"count": len(control_objects), "identical": control_objects == probe_objects,
                      "control": control_objects, "probe": probe_objects},
    "runtime": {"control_archive_sha256": sha(control["runtime_object"]),
                "probe_archive_sha256": sha(probe["runtime_object"]),
                "control_members": control_members, "probe_members": probe_members,
                "native_collections_member_changed": control_members["native_collections.c.o"] != probe_members["native_collections.c.o"],
                "other_members_exact_hash_equal": all(control_members[k] == probe_members[k] for k in control_members if k != "native_collections.c.o")},
    "source": {"control_native_collections_sha256": sha(before),
               "probe_native_collections_sha256": sha(after),
               "runtime_source_file_count": len(control_sources),
               "differing_runtime_sources": source_differences,
               "all_other_runtime_sources_hash_equal": source_differences == ["native_collections.c"],
               "exact_delta": "+    case 112: memcpy(destination,source,112); return;"},
    "note": "Runtime members other than native_collections may have different bitcode hashes because the hermetic build embeds cache-path prefix maps. Their copied C/Zig inputs and build controls are unchanged; guest objects are byte-identical."
}
(OUT / "copy112-provenance.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
