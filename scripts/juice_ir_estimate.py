#!/usr/bin/env python3
"""Experimental compile-only costs for scalar, structured Core IR.

Consumes `mylang dump-ir FILE --facts`, never executes the guest. Counts canonical
loops algebraically; deliberately refuses data-dependent control flow/memory.
The cycle score is a heuristic, NOT a time guarantee or a worst-case bound.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, field
import hashlib
import json
from pathlib import Path
import re
import subprocess


class Unknown(ValueError):
    pass


@dataclass(frozen=True)
class Expr:
    text: str
    value: int | float | None

    def combine(self, other, op):
        other = scalar(other) if isinstance(other, (int, float)) else other
        if op == "+":
            if self.value == 0:
                return other
            if other.value == 0:
                return self
        if op == "*":
            if self.value == 0 or other.value == 0:
                return scalar(0)
            if self.value == 1:
                return other
            if other.value == 1:
                return self
        value = None
        if self.value is not None and other.value is not None:
            value = self.value + other.value if op == "+" else self.value * other.value
        return Expr(f"({self.text} {op} {other.text})", value)

    def __add__(self, other):
        return self.combine(other, "+")

    def __mul__(self, other):
        return self.combine(other, "*")

    def json(self):
        return {"formula": self.text, "value": self.value}


def scalar(value):
    return Expr(str(value), value)


@dataclass
class Inst:
    ref: str | None
    op: str
    ty: str
    args: list[str]
    block: int

    @property
    def base(self):
        return self.op.split(".")[0]


@dataclass
class Block:
    preds: list[int]
    insts: list[Inst] = field(default_factory=list)

    def successors(self):
        term = self.insts[-1]
        if term.op == "jump":
            return [int(term.args[0][1:])]
        if term.op == "branch":
            return [int(x[1:]) for x in term.args[1:]]
        if term.op == "ret":
            return []
        raise Unknown(f"unsupported terminator {term.op}")


def parse(text, function):
    """Parse just the selected function; ignore separately printed fact tables."""
    blocks, params, current = {}, None, None
    active = False
    for line in text.splitlines():
        if line.startswith("fn "):
            if active:
                break
            match = re.fullmatch(r"fn (\S+)\((.*)\) -> (\S+)", line)
            active = bool(match and match[1] == function)
            if active:
                params = match[2].split(", ") if match[2] else []
            continue
        if not active or line.startswith(("facts ", "list ", "field ")):
            continue
        if match := re.fullmatch(r"b(\d+):(?: ; preds(.*))?", line):
            current = int(match[1])
            blocks[current] = Block([int(x[1:]) for x in (match[2] or "").split()])
        elif line.startswith("  "):
            match = re.fullmatch(r"  (?:(%\d+) = )?(\S+)(?: (.*))?", line)
            if not match or current is None:
                raise Unknown(f"unrecognized IR: {line}")
            ref, op, rest = match.groups()
            ty = "void"
            if ref:
                ty, _, rest = (rest or "").partition(" ")
            blocks[current].insts.append(Inst(ref, op, ty, (rest or "").split(", ") if rest else [], current))
    if params is None or not blocks:
        raise Unknown(f"function {function!r} has no supported definition")
    return params, blocks


def int_range(ty):
    match = re.fullmatch(r"([iu])(8|16|32|64)", ty)
    if not match:
        raise Unknown(f"unsupported integer type {ty}")
    width = int(match[2])
    return (0, 2**width - 1) if match[1] == "u" else (-2**(width-1), 2**(width-1)-1)


def trip_count(start, bound, step, predicate, ty):
    """Pre-test affine recurrence, including the final executed increment."""
    if step == 0 or (step > 0 and predicate not in ("lt", "le")) or (step < 0 and predicate not in ("gt", "ge")):
        raise Unknown("non-monotone or unsupported loop condition")
    low, high = int_range(ty)
    distance = f"({bound.text} - {start.text})" if step > 0 else f"({start.text} - {bound.text})"
    inclusive = int(predicate in ("le", "ge"))
    formula = f"max(0, ceil_div({distance} + {inclusive}, {abs(step)}))"
    count = None
    if start.value is not None and bound.value is not None:
        a, b = int(start.value), int(bound.value)
        if not (low <= a <= high and low <= b <= high):
            raise Unknown("loop endpoint outside induction type")
        distance_value = b - a if step > 0 else a - b
        count = max(0, (distance_value + inclusive + abs(step) - 1) // abs(step))
        if not low <= a + count * step <= high:
            raise Unknown("loop induction can overflow on its final increment")
    return Expr(formula, count)


class Analyzer:
    # Frozen heuristic: a four-operation issue budget, one-cycle scalar bitwise
    # operations, three-cycle integer multiply. No cache/port/backend model.
    LATENCY = {"add": 1, "sub": 1, "mul": 3, "bit_xor": 1, "bit_and": 1,
               "bit_or": 1, "shift_left": 1, "shift_right": 1, "cmp": 1,
               "convert": 1, "branch": 1, "ret": 1,
               "jump": 0, "phi": 0, "iconst": 0}
    ISSUE_WIDTH = 4

    def __init__(self, text, function, bindings):
        self.params, self.blocks = parse(text, function)
        self.bindings = bindings
        for index, value in bindings.items():
            if index < 0 or index >= len(self.params):
                raise Unknown(f"no parameter {index}")
            lo, hi = int_range(self.params[index])
            if not lo <= value <= hi:
                raise Unknown(f"parameter {index} outside {self.params[index]}")
        self.insts = {i.ref: i for b in self.blocks.values() for i in b.insts if i.ref}
        self.succ = {}
        self.reachable = set()
        pending = [0]
        while pending:
            b = pending.pop()
            if b not in self.reachable:
                if b not in self.blocks or not self.blocks[b].insts:
                    raise Unknown(f"reachable empty/missing block b{b}")
                # Optimized dumps retain empty, unreachable blocks. They have
                # no execution cost and must not be parsed as live terminators.
                self.succ[b] = self.blocks[b].successors()
                self.reachable.add(b)
                pending.extend(self.succ[b])
        self.preds = {b: [p for p in self.reachable if b in self.succ[p]] for b in self.reachable}
        dom = {b: ({0} if b == 0 else set(self.reachable)) for b in self.reachable}
        changed = True
        while changed:
            changed = False
            for b in sorted(self.reachable - {0}):
                new = {b} | set.intersection(*(dom[p] for p in self.preds[b]))
                if new != dom[b]:
                    dom[b], changed = new, True
        self.loops = {}
        for latch in sorted(self.reachable):
            for header in self.succ[latch]:
                if header not in dom[latch]:
                    continue
                if header in self.loops:
                    raise Unknown("multiple latches for one loop")
                nodes = {header, latch}
                pending = [latch] if latch != header else []
                while pending:
                    b = pending.pop()
                    for p in self.preds[b]:
                        if p not in nodes:
                            nodes.add(p)
                            pending.append(p)
                if len([p for p in self.preds[header] if p not in nodes]) != 1:
                    raise Unknown("loop needs a single entry")
                self.loops[header] = dict(header=header, latch=latch, nodes=nodes)
        self.counts = {}
        self.loop_reports = []

    def invariant(self, operand, forbidden, seen=frozenset()):
        if re.fullmatch(r"-?\d+:[iu]\d+", operand):
            value, ty = operand.split(":")
            value = int(value)
            # Core prints u64 constants through a signed i64 representation.
            if ty.startswith("u") and value < 0:
                value += 2**int(ty[1:])
            return scalar(value)
        if operand.startswith("param"):
            index = int(operand[5:])
            int_range(self.params[index])
            return Expr(operand, self.bindings.get(index))
        if operand in seen or operand not in self.insts:
            raise Unknown(f"unresolved bound {operand}")
        inst = self.insts[operand]
        if inst.block in forbidden:
            raise Unknown(f"bound {operand} depends on a loop body")
        args = [self.invariant(a, forbidden, seen | {operand}) for a in inst.args]
        if inst.base in ("add", "sub", "mul") and len(args) == 2:
            a, b = args
            if inst.base == "add":
                result = a + b
            elif inst.base == "mul":
                result = a * b
            else:
                result = a + b * -1
        elif inst.base == "convert" and len(args) == 1:
            result = args[0]
        else:
            raise Unknown(f"unsupported bound expression {inst.op}")
        lo, hi = int_range(inst.ty)
        if result.value is not None and not lo <= result.value <= hi:
            raise Unknown("bound expression can overflow")
        return result

    def describe_loop(self, loop):
        header, latch, nodes = loop["header"], loop["latch"], loop["nodes"]
        term = self.blocks[header].insts[-1]
        if term.op != "branch" or term.args[0] not in self.insts:
            raise Unknown(f"b{header}: loop has no canonical pre-test")
        cmp = self.insts[term.args[0]]
        if cmp.base != "cmp" or len(cmp.args) != 2:
            raise Unknown(f"b{header}: loop test is not an integer comparison")
        predicate = cmp.op.split(".")[1]
        inside, outside = self.succ[header]
        if inside not in nodes and outside in nodes:
            inside, outside = outside, inside
            predicate = {"lt": "ge", "le": "gt", "gt": "le", "ge": "lt"}.get(predicate)
        if inside not in nodes or outside in nodes:
            raise Unknown("loop needs one exit at its header")
        for b in nodes - {header}:
            if any(s not in nodes for s in self.succ[b]):
                raise Unknown(f"b{header}: data-dependent/early loop exit")
        induction = self.insts.get(cmp.args[0])
        bound_operand = cmp.args[1]
        if not induction or induction.base != "phi" or induction.block != header:
            induction = self.insts.get(cmp.args[1])
            bound_operand = cmp.args[0]
            predicate = {"lt": "gt", "le": "ge", "gt": "lt", "ge": "le"}.get(predicate)
        if not induction or induction.base != "phi" or induction.block != header:
            raise Unknown("condition does not compare an induction phi")
        preds = self.blocks[header].preds
        if len(preds) != 2 or len(induction.args) != 2:
            raise Unknown("induction needs one initial and one carried value")
        back = induction.args[preds.index(latch)]
        init = induction.args[1 - preds.index(latch)]
        update = self.insts.get(back)
        if not update or update.base not in ("add", "sub") or len(update.args) != 2:
            raise Unknown("induction has no constant add/sub recurrence")
        if update.args[0] == induction.ref:
            step_operand = update.args[1]
        elif update.base == "add" and update.args[1] == induction.ref:
            step_operand = update.args[0]
        else:
            raise Unknown("induction update does not use its phi")
        step = self.invariant(step_operand, nodes)
        if step.value is None or not re.fullmatch(r"-?\d+", step.text):
            raise Unknown("induction step is not a compile-time constant")
        # Refuse triangular/ragged nests: no pretending an outer induction is invariant.
        ancestors = set().union(*(x["nodes"] for x in self.loops.values() if nodes < x["nodes"]))
        start = self.invariant(init, nodes | ancestors)
        bound = self.invariant(bound_operand, nodes | ancestors)
        count = trip_count(start, bound, int(step.value) * (-1 if update.base == "sub" else 1), predicate, induction.ty)
        return inside, outside, count

    def latency(self, inst):
        if inst.base not in self.LATENCY or (inst.ty not in ("bool", "void") and not re.fullmatch(r"[iu](8|16|32|64)", inst.ty)):
            raise Unknown(f"b{inst.block}: unsupported operation {inst.op} {inst.ty}")
        if ".exact" in inst.op:
            raise Unknown(f"b{inst.block}: unproven arithmetic check {inst.op}")
        return self.LATENCY[inst.base]

    def block_work(self, block):
        return sum(self.latency(i) for i in self.blocks[block].insts)

    def recurrence(self, loop, direct):
        """Longest same-iteration path back to a header phi, not operation count."""
        cache = {}
        def depth(ref, active=frozenset()):
            if ref in cache:
                return cache[ref]
            i = self.insts.get(ref)
            if i is None or i.block not in direct or (i.base == "phi" and i.block == loop["header"]):
                return 0
            if ref in active or i.base == "phi":
                raise Unknown("unsupported intra-iteration dependency cycle/merge")
            result = max((depth(a, active | {ref}) for a in i.args), default=0) + self.latency(i)
            cache[ref] = result
            return result
        block = self.blocks[loop["header"]]
        index = block.preds.index(loop["latch"])
        return max((depth(i.args[index]) for i in block.insts if i.base == "phi"), default=0)

    def walk(self, start, stop, multiplier, owner=None):
        b, visited, direct = start, set(), set()
        work, cycles, nested_cycles = scalar(0), scalar(0), scalar(0)
        while b != stop:
            if b in visited:
                raise Unknown("unsupported cycle outside canonical loops")
            visited.add(b)
            if b in self.loops and b != owner:
                w, c, exit_block = self.analyze_loop(self.loops[b], multiplier)
                work, nested_cycles = work + w, nested_cycles + c
                b = exit_block
                continue
            direct.add(b)
            self.counts[b] = multiplier
            block_work = self.block_work(b)
            work, cycles = work + block_work, cycles + block_work
            term = self.blocks[b].insts[-1]
            if term.op == "ret":
                if stop is not None:
                    raise Unknown("return inside a loop")
                break
            if term.op != "jump":
                raise Unknown(f"b{b}: data-dependent branch (no path probabilities)")
            b = self.succ[b][0]
        return work, cycles + nested_cycles, direct, nested_cycles

    def analyze_loop(self, loop, multiplier):
        header = loop["header"]
        inside, outside, count = self.describe_loop(loop)
        self.counts[header] = multiplier * (count + 1)
        header_work = self.block_work(header)
        body_work, _, direct, nested_cycles = self.walk(inside, header, multiplier * count, header)
        recurrence = self.recurrence(loop, direct | {header})
        direct_work = header_work + sum(self.block_work(b) for b in direct)
        per_iteration = max(1, recurrence, direct_work / self.ISSUE_WIDTH)
        # Child loops are serial regions. This deliberately coarse composition
        # does not claim to model cross-nest scheduling or LLVM transformations.
        cycles = (nested_cycles + per_iteration) * count + header_work
        work = (body_work + header_work) * count + header_work
        self.loop_reports.append({"header": header, "latch": loop["latch"],
                                  "iterations_per_entry": count.json(),
                                  "entries": multiplier.json(),
                                  "recurrence_cycles": recurrence,
                                  "direct_work_per_iteration": direct_work,
                                  "modeled_cycles": cycles.json()})
        return work, cycles, outside

    def run(self):
        work, cycles, _, _ = self.walk(0, None, scalar(1))
        if set(self.counts) != self.reachable:
            raise Unknown("unmodeled reachable blocks")
        operations = {}
        for b, count in self.counts.items():
            for op, sites in Counter(i.base for i in self.blocks[b].insts).items():
                operations[op] = operations.get(op, scalar(0)) + count * sites
        return {"status": "estimated" if cycles.value is not None else "symbolic",
                "weighted_work": work.json(), "cycle_score": cycles.json(),
                "loops": sorted(self.loop_reports, key=lambda x: x["header"]),
                "block_executions": {str(b): c.json() for b, c in sorted(self.counts.items())},
                "operation_executions": {op: n.json() for op, n in sorted(operations.items())}}


def estimate(text, function, bindings=None):
    result = {"schema": "juice-ir-estimate-v1", "function": function,
              "ir_sha256": hashlib.sha256(text.encode()).hexdigest(),
              "parameters": {str(k): v for k, v in sorted((bindings or {}).items())},
              "model": {"name": "scalar-recurrence-v1", "issue_width": Analyzer.ISSUE_WIDTH,
                        "latencies": Analyzer.LATENCY},
              "limitations": ["Heuristic score, not guaranteed cycles or wall time.",
                              "Counts assume declared parameters and normal completion without traps.",
                              "Symbolic counts require non-overflowing bound arithmetic and induction.",
                              "No LLVM folding/vectorization, instruction selection, cache, frequency or OS model."]}
    try:
        result.update(Analyzer(text, function, bindings or {}).run())
    except Unknown as error:
        result.update(status="unknown", reason=str(error))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--ir", type=Path, help="existing optimized Core IR dump")
    source.add_argument("--source", type=Path, help="compile to Core IR; do not link/run")
    parser.add_argument("--compiler", default="zig-out/bin/mylang")
    parser.add_argument("--function", required=True)
    parser.add_argument("--param", action="append", default=[], metavar="INDEX=INTEGER")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    bindings = {}
    for binding in args.param:
        index, value = binding.split("=", 1)
        bindings[int(index)] = int(value)
    if args.ir:
        text = args.ir.read_text()
    else:
        text = subprocess.run([args.compiler, "dump-ir", str(args.source), "--facts"],
                              check=True, capture_output=True, text=True, timeout=120).stdout
    result = estimate(text, args.function, bindings)
    if args.source:
        result["source_sha256"] = hashlib.sha256(args.source.read_bytes()).hexdigest()
        result["compiler_sha256"] = hashlib.sha256(Path(args.compiler).read_bytes()).hexdigest()
    rendered = json.dumps(result, indent=2, allow_nan=False) + "\n"
    if args.output:
        args.output.write_text(rendered)
    else:
        print(rendered, end="")
    return 1 if result["status"] == "unknown" else 0


if __name__ == "__main__":
    raise SystemExit(main())
