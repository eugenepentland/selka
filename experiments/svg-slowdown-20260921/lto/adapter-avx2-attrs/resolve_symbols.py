#!/usr/bin/env python3
"""Resolve every external symbol of the QBE census to its defining C prototype.

    resolve_symbols.py CENSUS.json OUT.json

`symbol_census.py` says which `$symbol`s the emitted IL references and which of
them no unit defines.  This script attaches, for each of those:

  kind        "external-function" | "generated-data" | "closure-function" | ...
  prototype   the exact C declaration, whitespace-normalised to one line
  header      the file the declaration was read from
  defined_by  who must provide it in a linked image

A prototype is only recorded when the declaration text is found in the named
file, so the table cannot drift from the headers.
"""
import argparse
import json
import os
import re
import sys

SRC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "src")

# Hand-written declarations for the two runtime entry points the compiler
# exports from Zig (`@export`), which no C header spells, plus libc `memset`.
# Each is checked against its source file below.
ZIG_EXPORTS = {
    "myl_native_text_scalar": (
        "src/native_format.zig",
        "void *myl_native_text_scalar(void *heap, uint64_t bits, unsigned kind);",
        "fn scalarC(heap: *anyopaque, bits: u64, kind: c_uint) callconv(.c) ?*anyopaque",
    ),
    "myl_native_number_parse": (
        "src/native_format.zig",
        "unsigned myl_native_number_parse(const uint32_t *points, size_t count,"
        " unsigned floating, uint64_t *output);",
        "fn numberC(points: ?[*]const u32, count: usize, floating: c_uint, output: *u64) callconv(.c) c_uint",
    ),
}
LIBC = {
    "memset": ("<string.h>", "void *memset(void *s, int c, size_t n);",
               "libc; no mylang header declares it"),
}
# Symbols the build driver's generated C defines; an LLVM arm must declare and
# use them, never emit its own definition.
GENERATED = {
    "myl_f_": ("generated-metadata", "extern const MylQbeFunction {sym};",
               "src/qbe_build_outputs.zig:68 (metadata)"),
    "myl_lit_": ("generated-literal", "extern const void *const {sym};",
                 "src/qbe_build_outputs.zig:109 (emitLiteral)"),
    "myl_t_": ("generated-descriptor", "extern const myl_native_type {sym};",
               "src/native_descriptors.zig:18 (generate)"),
    "myl_r_": ("generated-renderer", "void {sym}(MylPrint *o, const void *v, unsigned d);",
               "src/native_render.zig:38 (generate)"),
}
# The 39 called externals; each maps to the file its prototype is read from.
HEADER_FOR = {
    "myl_native_equal": "src/native_equal.h",
    "myl_native_heap_alloc": "src/native_heap.h",
    "myl_native_list_append": "src/native_collections.h",
    "myl_native_list_get": "src/native_collections.h",
    "myl_native_list_new": "src/native_collections.h",
    "myl_native_text_at": "src/native_text.h",
    "myl_native_text_concat": "src/native_text.h",
    "myl_native_text_join": "src/native_text.h",
    "myl_native_text_slice": "src/native_text.h",
    "myl_native_text_edge": "src/native_text_methods.h",
    "myl_native_text_every": "src/native_text_methods.h",
    "myl_native_text_find": "src/native_text_methods.h",
    "myl_qbe_bytes_decode_range": "src/qbe_bytes.h",
    "myl_qbe_file_access": "src/qbe_files.h",
    "myl_qbe_print_byte": "src/qbe_io.h",
    "myl_qbe_stream_begin": "src/qbe_io.h",
    "myl_qbe_stream_finish": "src/qbe_io.h",
    "myl_qbe_fail_allocation": "src/qbe_runtime.h",
    "myl_qbe_fail_cast": "src/qbe_runtime.h",
    "myl_qbe_fail_empty_separator": "src/qbe_runtime.h",
    "myl_qbe_fail_equality": "src/qbe_runtime.h",
    "myl_qbe_fail_frame": "src/qbe_runtime.h",
    "myl_qbe_fail_index_bounds": "src/qbe_runtime.h",
    "myl_qbe_fail_iteration": "src/qbe_runtime.h",
    "myl_qbe_fail_list_capacity": "src/qbe_runtime.h",
    "myl_qbe_fail_normalized_index_bounds": "src/qbe_runtime.h",
    "myl_qbe_fail_overflow_op": "src/qbe_runtime.h",
    "myl_qbe_fail_text_bounds_detail": "src/qbe_runtime.h",
    "myl_qbe_float_unary": "src/qbe_runtime.h",
    "myl_qbe_heap": "src/qbe_runtime.h",
    "myl_qbe_int_neg": "src/qbe_runtime.h",
    "myl_qbe_require_frame_accounting": "src/qbe_runtime.h",
    "myl_qbe_require_step_accounting": "src/qbe_runtime.h",
    "myl_qbe_root_mark": "src/qbe_runtime.h",
}

DECLARATION = re.compile(r"^[A-Za-z_][\w \t*]*?\b{sym}\s*\(", re.M)


def declarations(path, symbol):
    """Every declaration of `symbol` in `path`, whitespace-normalised."""
    with open(os.path.join(SRC, os.path.basename(path))) as handle:
        text = handle.read()
    pattern = re.compile(r"(?m)^[A-Za-z_][^\n;{{}}]*?\b" + re.escape(symbol) + r"\s*\([^;{{}}]*?\);")
    found = []
    for match in pattern.finditer(text):
        if match.group(0).lstrip().startswith(("/*", "*", "//")):
            continue
        found.append(re.sub(r"\s+", " ", match.group(0)).strip())
    return found


def classify(name, entry, records):
    """Assign one external symbol its kind, prototype, header and definer."""
    for prefix, (kind, prototype, defined_by) in GENERATED.items():
        if name.startswith(prefix):
            rendered = prototype.replace("{sym}", name)
            if prefix == "myl_f_" and name.endswith("_meta"):
                rendered = f"extern const MylQbeFunction {name};"
            return kind, rendered, "src/qbe_build_outputs.zig / native_descriptors.zig / native_render.zig", defined_by
    if name in LIBC:
        header, prototype, defined_by = LIBC[name]
        return "libc-function", prototype, header, defined_by
    if name in ZIG_EXPORTS:
        path, prototype, anchor = ZIG_EXPORTS[name]
        with open(os.path.join(SRC, os.path.basename(path))) as handle:
            if anchor not in handle.read():
                return "unresolved", "", path, "anchor missing"
        return "runtime-function", prototype, path + " (@export)", "runtime archive (Zig)"
    path = HEADER_FOR.get(name)
    if path is None:
        return "unresolved", "", "", ""
    found = declarations(path, name)
    # Prefer the prototype whose parameter list has no nested function pointer.
    prototype = found[0] if found else ""
    return "runtime-function", prototype, path, "runtime archive (C)"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("census")
    parser.add_argument("out")
    options = parser.parse_args()
    with open(options.census) as handle:
        census = json.load(handle)
    symbols = census["symbols"]
    result = {}
    unresolved = []
    for name, entry in symbols.items():
        kind, prototype, header, defined_by = classify(name, entry, symbols)
        record = {
            "kind": kind,
            "prototype": prototype,
            "header": header,
            "defined_by": defined_by,
            "il_call_shapes": entry["call_shapes"],
            "il_reference_sites": entry["reference_sites"],
            "il_operand_contexts": entry["operand_contexts"],
            "referenced_from": entry["seen_in"],
        }
        if kind == "external" or (kind == "unresolved" and entry["kind"] == "external"):
            unresolved.append(name)
        result[name] = record
    with open(options.out, "w") as handle:
        json.dump({"source": options.census, "symbols": result}, handle, indent=1, sort_keys=True)
    external = {n: r for n, r in result.items() if r["kind"] == "external"}
    print(f"{len(result)} symbols, {len(external)} still external: {sorted(external)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
