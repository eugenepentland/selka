#!/usr/bin/env python3
"""Inspect emitted descriptors and model stable descending-alignment reordering.

This reads an emit-qbe / emit-project-qbe JSON manifest; it does not change or
execute the compiler. Baseline reconstruction must agree with every emitted
descriptor before the projection is reported. Usage: inspect_layouts.py FILE
"""
import functools
import hashlib
import json
import re
import sys
from pathlib import Path


def inspect(path):
    raw = Path(path).read_bytes()
    manifest = json.loads(raw)
    text = manifest["runtime_data"]
    descriptors = {}
    for name, body in re.findall(r"const myl_native_type (myl_t_\w+) = \{([^;]+)\};", text):
        descriptors[name] = dict(re.findall(r"\.(\w+)=([^,}]+)", body))
    fields = {}
    for name, body in re.findall(r"static const myl_native_field (\w+)\[\] = \{(.*?)\};", text, re.S):
        fields[name] = [
            (int(offset), child, int(tag))
            for offset, child, tag in re.findall(r"\.offset=(\d+),\.type=&(\w+),\.tag=(\d+)", body)
        ]

    def align(size, alignment):
        return (size + alignment - 1) // alignment * alignment

    @functools.cache
    def calculate(name, reorder):
        descriptor = descriptors[name]
        kind = descriptor["kind"]
        members = fields.get(descriptor["fields"], [])
        emitted = int(descriptor["size"]), int(descriptor["alignment"])
        if kind == "MYL_NATIVE_RECORD":
            children = [(i, calculate(child, reorder)) for i, (_, child, _) in enumerate(members)]
            if reorder:
                children.sort(key=lambda item: -item[1][1])
            size, alignment = 0, 1
            offsets = [0] * len(children)
            for i, (child_size, child_alignment) in children:
                offsets[i] = align(size, child_alignment)
                size = offsets[i] + child_size
                alignment = max(alignment, child_alignment)
            result = align(size, alignment), alignment
            if not reorder:
                assert offsets == [offset for offset, _, _ in members], (name, offsets, members)
        elif kind == "MYL_NATIVE_VARIANT":
            children = [calculate(child, reorder) for _, child, _ in members]
            payload_alignment = max([1] + [child[1] for child in children])
            alignment = max(4, payload_alignment)
            offset = align(4, payload_alignment)
            result = align(offset + max([0] + [child[0] for child in children]), alignment), alignment
            if not reorder:
                assert all(member[0] == offset for member in members), name
        elif kind == "MYL_NATIVE_ARRAY":
            child_size, alignment = calculate(members[0][1], reorder)
            stride = align(child_size, alignment)
            result = stride * int(descriptor["count"]), alignment
            if not reorder:
                assert stride == int(descriptor["stride"]), name
        else:
            result = emitted
        if not reorder:
            assert result == emitted, (name, result, emitted)
        return result

    for name in descriptors:
        calculate(name, False)
        calculate(name, True)

    names = {}
    schema = json.loads(manifest["schema"]) if manifest.get("schema") else {"types": []}
    for item in schema["types"]:
        symbol = "myl_t_" + hashlib.sha256(item["name"].encode()).hexdigest()
        names[symbol] = item["name"]
        names[symbol + "_body"] = item["name"] + " (heap body)"
    # Single-file emit-qbe omits the schema. Name only the probe's known types.
    for name in ("Example", "ReorderedExample", "Pair", "Counter"):
        symbol = "myl_t_" + hashlib.sha256(name.encode()).hexdigest()
        names[symbol] = name
        names[symbol + "_body"] = name + " (heap body)"

    rows = []
    for symbol, descriptor in descriptors.items():
        if descriptor["kind"] not in ("MYL_NATIVE_RECORD", "MYL_NATIVE_VARIANT", "MYL_NATIVE_ARRAY"):
            continue
        before, alignment = calculate(symbol, False)
        after, _ = calculate(symbol, True)
        rows.append({"name": names.get(symbol, symbol), "kind": descriptor["kind"],
                     "size": before, "alignment": alignment, "projected_size": after,
                     "saved": before - after})
    return {"manifest_sha256": hashlib.sha256(raw).hexdigest(),
            "verified_descriptors": len(descriptors),
            "changed_descriptors": sum(calculate(n, False) != calculate(n, True) for n in descriptors),
            "types": sorted(rows, key=lambda row: row["name"])}


if __name__ == "__main__":
    print(json.dumps(inspect(sys.argv[1]), indent=2))
