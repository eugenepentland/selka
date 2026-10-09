#!/usr/bin/env python3
"""Count visible operations in current ``mylang dump-typed`` trees.

Adapted narrowly from historical frontend-fp2-20261008/tools/count_typed.py.

This is deliberately a typed-tree count, not an estimate of source spellings.
Anonymous lowering loops cannot certify an original repetition or plain list
slice. Opaque nodes hide their operands. Both limitations stay explicit.
"""
from __future__ import annotations
import argparse
from collections import Counter
from dataclasses import dataclass, field
import json
from pathlib import Path
import re

ROWS = (
    "list.in_or_not_in", "list.eq", "list.ne", "record.eq", "record.ne",
    "dict.eq", "dict.ne", "set.eq", "set.ne", "list.add",
    "sequence.mul", "list.slice_without_step", "list.slice_step", "str.slice_or_tail",
    "str.slice_step", "bytes.slice", "bytes.view", "str.add_in_loop",
    "list.contains_method", "literal.fixed_array", "literal.packed_list",
)
SCALARS = {"unit", "bool", "i8", "i16", "i32", "i64", "u8", "u16",
           "u32", "u64", "f32", "f64", "float", "filesystem_cap",
           "network_cap", "environment_cap", "clock_cap", "random_cap",
           "host_cap", "stream_cap"}

@dataclass
class Tree:
    text: str
    line: int
    children: list[Tree] = field(default_factory=list)

    @property
    def tag(self):
        return self.text.split(" ", 1)[0].rstrip(":")

    @property
    def ty(self):
        if " : " not in self.text:
            return None
        rest = self.text.split(" : ", 1)[1]
        if rest.endswith(" ..."):
            return rest[:-4]
        if self.tag == "buffer_operation":
            return rest.rsplit(" ", 2)[0]
        if self.tag in {"binary", "unary", "local", "integer", "boolean", "call", "field"}:
            return rest.rsplit(" ", 1)[0]
        for marker in (" from_end=", " tag=", " sink="):
            rest = rest.split(marker, 1)[0]
        return rest

@dataclass
class Function:
    name: str
    header: str
    locals: dict[int, tuple[str, str]]
    roots: list[Tree]
    line: int


def parse(text: str) -> list[Function]:
    functions = []
    current = None
    stack = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line:
            continue
        if line.startswith("fn "):
            header = re.fullmatch(r"fn (.+) #\d+ params=\d+ ret=.+ cabi=(true|false) host=(true|false)", line)
            if not header:
                raise ValueError(f"malformed function at line {number}: {line}")
            current = Function(header[1], line, {}, [], number)
            functions.append(current)
            stack = []
            continue
        if current is None:
            raise ValueError(f"node before function at line {number}")
        local = re.fullmatch(r"  local %(\d+) (.*): (.+?)( mut)?", line)
        if local:
            slot = int(local[1])
            if slot in current.locals:
                raise ValueError(f"duplicate local %{slot} at line {number}")
            current.locals[slot] = (local[2], local[3])
            continue
        spaces = len(line) - len(line.lstrip(" "))
        if spaces < 2 or spaces % 2:
            raise ValueError(f"malformed indentation at line {number}: {line!r}")
        depth = spaces // 2
        node = Tree(line.strip(), number)
        while stack and stack[-1][0] >= depth:
            stack.pop()
        if stack:
            if depth != stack[-1][0] + 1:
                raise ValueError(f"skipped indentation at line {number}")
            stack[-1][1].children.append(node)
        elif depth == 1:
            current.roots.append(node)
        else:
            raise ValueError(f"missing parent at line {number}")
        stack.append((depth, node))
    return functions


def nodes(roots):
    for node in roots:
        yield node
        yield from nodes(node.children)


def family(ty, records):
    if ty is None:
        return None
    for prefix, name in (("List[", "list"), ("list[", "list"), ("List<", "list"), ("list<", "list"),
                         ("Dict[", "dict"), ("dict[", "dict"), ("Dict<", "dict"), ("dict<", "dict"),
                         ("Set[", "set"), ("set[", "set"), ("Set<", "set"), ("set<", "set")):
        if ty.startswith(prefix):
            return name
    if ty in {"str", "bytes", "byte_buffer"}:
        return ty
    if ty.startswith("["):
        return "fixed_array"
    if ty in SCALARS:
        return "scalar"
    if ty.startswith(("Tuple<", "Tuple[", "tuple<", "tuple[")):
        return "tuple"
    if ty in records:
        return "record"
    return "unknown_nominal"


def count(functions: list[Function], record_types=None):
    records = set(record_types or ())
    records.update(n.ty for f in functions for n in nodes(f.roots) if n.tag == "record")
    counts = {row: [0, 0, 0] for row in ROWS}
    uncounted = Counter()
    events = []
    body_indices = {id(fn): index for index, fn in enumerate(functions)}
    def add(row, depth, fn, node):
        counts[row][min(depth, 2)] += 1
        events.append({"row": row, "loop_depth": depth, "function": fn.name,
                       "dump_line": node.line, "node": node.text, "body_index": body_indices[id(fn)]})
    def walk(node, depth, fn):
        # The role-labeled range loop keeps endpoints/setup outside the loop.
        # Its `loop:` role adds depth exactly where condition/body/step begin.
        if node.tag == "range_loop":
            roles = [child.text for child in node.children]
            if roles != ["start:", "end:", "setup:", "loop:"]:
                raise ValueError(f"range_loop role schema changed at line {node.line}: {roles}")
            plan = node.children[-1]
            if [child.text for child in plan.children] not in (
                    ["condition:", "body:"], ["condition:", "body:", "step:"]):
                raise ValueError(f"range_loop plan schema changed at line {node.line}")
        depth += node.tag == "loop"
        if node.text.endswith(" ..."):
            uncounted["opaque." + node.tag] += 1
        if node.tag == "binary":
            if len(node.children) != 2 or any(n.ty is None for n in node.children):
                raise ValueError(f"binary lacks two typed operands at line {node.line}")
            op = node.text.rsplit(" ", 1)[1]
            left, right = (family(n.ty, records) for n in node.children)
            if op in {"eq", "ne"}:
                if left in {"list", "record", "dict", "set"}:
                    add(left + "." + op, depth, fn, node)
                elif left == "unknown_nominal":
                    uncounted["equality.unknown_nominal"] += 1
            if op == "add" and left == right == "list":
                add("list.add", depth, fn, node)
            if op == "mul" and ({left, right} & {"str", "bytes", "list"}):
                add("sequence.mul", depth, fn, node)
            if op == "add" and left == right == "str" and depth:
                add("str.add_in_loop", depth, fn, node)
        if node.tag == "buffer_operation":
            match = re.search(r" ([a-z0-9_]+) owner=%(\d+)$", node.text)
            if not match:
                raise ValueError(f"malformed operation at line {node.line}")
            kind, owner = match[1], int(match[2])
            if owner not in fn.locals:
                raise ValueError(f"operation has unknown owner %{owner} at line {node.line}")
            name, ty = fn.locals[owner]
            f = family(ty, records)
            if kind == "contains" and f == "list":
                row = "list.in_or_not_in" if name == "<membership>" else "list.contains_method"
                add(row, depth, fn, node)
            if kind in {"slice", "text_tail", "slice_step"}:
                if f == "list" and kind == "slice_step":
                    add("list.slice_step", depth, fn, node)
                elif f == "str":
                    add("str.slice_step" if kind == "slice_step" else "str.slice_or_tail", depth, fn, node)
                elif f == "bytes" and kind == "slice":
                    add("bytes.slice", depth, fn, node)
                else:
                    uncounted["slice.unrecognized_receiver_or_kind"] += 1
            if kind == "view" and f == "bytes":
                add("bytes.view", depth, fn, node)
        if node.tag == "array":
            f = family(node.ty, records)
            if f == "fixed_array":
                add("literal.fixed_array", depth, fn, node)
            elif f == "list":
                add("literal.packed_list", depth, fn, node)
        for child in node.children:
            walk(child, depth, fn)
    for fn in functions:
        for root in fn.roots:
            walk(root, 0, fn)
    return {"counts": counts, "uncounted_visible_nodes": dict(sorted(uncounted.items())),
            "events": events, "functions": len(functions),
            "record_types_certified_by_constructor": sorted(records),
            "uncounted_constructs": {
                "list_plain_slice": "uncounted: anonymous copy-loop lowering has no original slice identity",
                "sequence_repetition": "uncounted: anonymous gather-loop lowering has no original multiply identity",
                "list_nonpacked_literal": "uncounted: acquire/append lowering also represents comprehensions and other constructors",
                "uninstantiated_generic_templates": "uncounted: dump contains checked specializations, not the bodies of unused generic templates",
                "record_equality_without_visible_constructor": "uncounted: dump omits aggregate schema tags; nominal equality may be enum/domain/variant/record",
                "source_loop_depth": "uncounted: reported depth is typed loop nesting, which includes generated loops",
                "hidden_operands": "uncounted: opaque nodes and print separator/terminator omit subtrees",
                "fused_slice_or_view": "uncounted: immediately consumed byte slices/views may lower to range operations without slice/view identity",
            }}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("dump", type=Path)
    p.add_argument("--module", help="keep functions whose name starts with MODULE::")
    p.add_argument("--json", type=Path)
    a = p.parse_args()
    fs = parse(a.dump.read_text())
    if a.module:
        fs = [f for f in fs if f.name.startswith(a.module + "::")]
    result = count(fs)
    text = json.dumps(result, indent=2) + "\n"
    if a.json:
        a.json.write_text(text)
    else:
        print(text, end="")

if __name__ == "__main__":
    main()
