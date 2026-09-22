#!/usr/bin/env python3
"""Relink original non-LTO gc-o3 and count wrapped list_get requests."""
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/algorithm/counts"
CURRENT = ROOT / ".tmp/svg-arenas-20260921"
sys.path.insert(0, str(HERE.parent))
from audit import invoke, sha


def command(args):
    result = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError((list(map(str, args)), result.stderr))


def parse(stderr):
    histogram = []
    total = None
    for line in stderr.splitlines():
        fields = line.split()
        if fields[0] == "LIST_GET":
            values = {key: int(value) for key, value in (field.split("=") for field in fields[1:])}
            histogram.append(values)
        elif fields[0] == "LIST_GET_TOTAL":
            total = {key: int(value) for key, value in (field.split("=") for field in fields[1:])}
        else:
            raise AssertionError(line)
    assert total is not None
    assert total["calls"] == sum(row["calls"] for row in histogram) + total["overflow_calls"]
    assert total["requested_bytes"] == sum(row["requested_bytes"] for row in histogram) + total["overflow_requested_bytes"]
    return histogram, total


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    original = CURRENT / "gc-o3"
    manifest_path = Path(str(original) + ".qbe-manifest.json")
    receipt = json.loads(manifest_path.read_text())
    guests = [Path(function["object"]) for function in receipt["functions"]]
    extras = [path for path in guests[0].parent.glob("*.o") if path not in guests]
    assert len(extras) == 2
    candidates = [path for path in (CURRENT / "cache-gc-o3/runtime").iterdir()
                  if all((path / unit).exists() and (path / unit).read_bytes() == (ROOT / "src" / unit).read_bytes()
                         for unit in ("qbe_runtime.c", "qbe_runtime.h", "native_heap.c", "native_heap.h",
                                      "native_arena.c", "native_regions.c", "qbe_arena.c"))]
    assert len(candidates) == 1, candidates
    assets = candidates[0]
    wrapper_source = HERE / "list_get_counts.c"
    wrapper_object = WORK / "list_get_counts.o"
    provider_object = WORK / "provider.o"
    command(["zig", "cc", "-O3", "-fPIC", "-ffunction-sections", "-fdata-sections",
             "-I", assets, "-c", wrapper_source, "-o", wrapper_object])
    command(["zig", "cc", "-O3", "-fPIC", "-ffunction-sections", "-fdata-sections",
             "-I", assets, "-c", ROOT / "src/schematic/native_schematic.c", "-o", provider_object])
    binary = WORK / "gc-o3-list-get-counts"
    link = ["cc", "-no-pie", "-O3", "-fPIC", *guests, *extras, provider_object,
            receipt["runtime_object"], wrapper_object, "-lm", "-Wl,--gc-sections",
            "-Wl,--wrap=myl_native_list_get", "-o", binary]
    command(link)
    cases = {}
    for case in ("fixture", "changed-net", "changed-value"):
        _, stderr, svg = invoke(binary, case, diagnostic=True)
        histogram, total = parse(stderr)
        pin_calls = next((row["calls"] for row in histogram if row["size"] == 112), 0)
        pin_bytes = next((row["requested_bytes"] for row in histogram if row["size"] == 112), 0)
        cases[case] = {"svg_sha256": svg, "histogram": histogram, "total": total,
                       "pin_112_byte_calls": pin_calls, "pin_112_requested_bytes": pin_bytes,
                       "pin_112_percent_calls": pin_calls * 100 / total["calls"],
                       "pin_112_percent_requested_bytes": pin_bytes * 100 / total["requested_bytes"]}
    evidence = {
        "method": "Linker --wrap of myl_native_list_get around unchanged original non-LTO gc-o3 guest objects. Counts successful and failed calls reaching that external symbol and sums list->element->size as requested copied bytes. This does not capture calls inlined by LTO and must not be generalized to LTO. No runtime source currently calls list_get internally, but the wrapper boundary would include such calls if introduced.",
        "binary": str(binary.relative_to(ROOT)), "binary_sha256": sha(binary),
        "original_binary": str(original.relative_to(ROOT)), "original_binary_sha256": sha(original),
        "manifest_sha256": sha(manifest_path), "runtime_object_sha256": sha(receipt["runtime_object"]),
        "wrapper_source": str(wrapper_source.relative_to(ROOT)), "wrapper_source_sha256": sha(wrapper_source),
        "wrapper_object_sha256": sha(wrapper_object), "provider_object_sha256": sha(provider_object),
        "guest_objects_reused_unchanged": len(guests),
        "guest_object_sha256": {str(path): sha(path) for path in guests},
        "extra_object_sha256": {str(path): sha(path) for path in extras},
        "link_command": list(map(str, link)), "cases": cases,
        "exact_three_svg_qualification": True, "wall_timing_performed": False,
    }
    (HERE / "list-get-counts.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({case: {"total": values["total"], "pin_112_byte_calls": values["pin_112_byte_calls"],
                                  "pin_112_requested_bytes": values["pin_112_requested_bytes"]}
                      for case, values in cases.items()}, indent=2))


if __name__ == "__main__":
    main()
