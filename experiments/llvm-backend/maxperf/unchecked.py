"""Opt-in valid-input-only lowering transforms for the LLVM maxperf arm.

This module never edits textual LLVM IR.  It parses QBE, proves a small set of
frontend control-flow/data-flow shapes, mutates those parsed instructions, and
then delegates to the normal LLVM emitter.  Invalid input has deliberately
undefined behaviour in ``unchecked`` mode.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import sys

BACKEND = Path(__file__).resolve().parents[1]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

from qbe_llvm import Constant, Instruction, Temp, parse_unit  # noqa: E402
import llvm_emit  # noqa: E402


@dataclass(frozen=True)
class Options:
    mode: str = "baseline"
    arena_proven: bool = False


@dataclass
class Inventory:
    removed: dict[str, int] = field(default_factory=dict)
    retained: dict[str, int] = field(default_factory=dict)

    def add(self, table, category, count=1):
        target = self.removed if table == "removed" else self.retained
        target[category] = target.get(category, 0) + count


@dataclass
class Translation:
    ir: str
    inventory: Inventory


FAILURE_CATEGORY = {
    "myl_qbe_fail_frame": "frame_floor",
    "myl_qbe_fail_overflow_op": "overflow",
    "myl_qbe_fail_division": "overflow",
    "myl_qbe_fail_cast": "cast",
    "myl_qbe_fail_index_bounds": "bounds",
    "myl_qbe_fail_normalized_index_bounds": "bounds",
    "myl_qbe_fail_text_bounds_detail": "bounds",
    "myl_qbe_fail_array_bounds": "bounds",
    "myl_qbe_fail_list_capacity": "capacity",
    "myl_qbe_fail_iteration": "iteration",
    "myl_qbe_fail_allocation": "allocation",
    "myl_qbe_fail_equality": "allocation",
}


def _temp(value):
    return getattr(value, "kind", None) == "temp"


def _definitions_before(block, stop):
    result = {}
    for index, instruction in enumerate(block.instructions[:stop]):
        if instruction.dest is not None:
            result[instruction.dest.name] = (index, instruction)
    return result


def _failure_category(block):
    found = {FAILURE_CATEGORY[ins.extra] for ins in block.instructions
             if ins.opcode == "call" and ins.extra in FAILURE_CATEGORY}
    return next(iter(found)) if len(found) == 1 else None


def _has_removable_failure(block):
    return any(ins.opcode == "call" and ins.extra in FAILURE_CATEGORY
               for ins in block.instructions)


def _sticky_trap(block, branch_index, failure, safe, trap_addresses):
    if not (failure.label == "@failure" and safe.label.startswith("@ok")):
        return False
    definitions = _definitions_before(block, branch_index)
    condition = block.instructions[branch_index].args[0]
    producer = definitions.get(condition.name, (None, None))[1] if _temp(condition) else None
    if producer is None or producer.opcode != "loadl":
        return False
    address = producer.args[0]
    if _temp(address) and address.name in trap_addresses:
        return True
    address_def = definitions.get(address.name, (None, None))[1] if _temp(address) else None
    return (address_def is not None and address_def.opcode == "add" and
            any(isinstance(arg, Constant) and arg.text == "32"
                for arg in address_def.args))


def _jmp(instruction, target):
    return Instruction("jmp", None, None, [], target, instruction.line,
                       f"jmp {target}")


def _trap_addresses(unit):
    counts, definitions = {}, {}
    for block in unit.function.blocks:
        for ins in block.instructions:
            if ins.dest is not None:
                counts[ins.dest.name] = counts.get(ins.dest.name, 0) + 1
                definitions[ins.dest.name] = ins
    context = (unit.function.parameters[0][1].name
               if unit.function.parameters else None)
    return {name for name, ins in definitions.items()
            if counts[name] == 1 and ins.opcode == "add" and
            any(_temp(arg) and arg.name == context for arg in ins.args) and
            any(isinstance(arg, Constant) and arg.text == "32" for arg in ins.args)}


def _strip_guards(unit, inventory):
    blocks = {block.label: block for block in unit.function.blocks}
    trap_addresses = _trap_addresses(unit)
    for block in unit.function.blocks:
        for index, instruction in enumerate(list(block.instructions)):
            if instruction.opcode != "jnz":
                continue
            left = blocks.get(instruction.extra[0])
            right = blocks.get(instruction.extra[1])
            if left is None or right is None:
                inventory.add("retained", "unresolved_branch")
                continue
            left_category, right_category = _failure_category(left), _failure_category(right)
            category = None
            safe = None
            if left_category and not right_category:
                category, safe = left_category, right
            elif right_category and not left_category:
                category, safe = right_category, left
            elif _sticky_trap(block, index, left, right, trap_addresses):
                category, safe = "sticky_trap", right
            elif _sticky_trap(block, index, right, left, trap_addresses):
                category, safe = "sticky_trap", left
            if category is None:
                if (_has_removable_failure(left) or
                        _has_removable_failure(right)):
                    inventory.add("retained", "ambiguous_failure_branch")
                continue
            block.instructions[index] = _jmp(instruction, safe.label)
            # A QBE terminator ends its block; anything after it is malformed for
            # this transform and must not be silently discarded.
            if index != len(block.instructions) - 1:
                raise ValueError(f"{unit.name}: guard branch is not a block terminator")
            inventory.add("removed", category)


def _strip_arena_roots(unit, inventory):
    """Remove only the heap root-head protocol proven by the +16 ABI field."""
    definitions = {}
    for block in unit.function.blocks:
        for ins in block.instructions:
            if ins.dest is not None:
                definitions[ins.dest.name] = definitions.get(ins.dest.name, 0) + 1
    heap_values = {ins.dest.name for block in unit.function.blocks
                   for ins in block.instructions
                   if ins.opcode == "call" and ins.extra == "myl_qbe_heap" and
                   ins.dest is not None and definitions[ins.dest.name] == 1}
    root_heads = set()
    for block in unit.function.blocks:
        for ins in block.instructions:
            if (ins.opcode != "add" or ins.dest is None or
                    definitions[ins.dest.name] != 1):
                continue
            has_heap = any(_temp(arg) and arg.name in heap_values for arg in ins.args)
            has_offset = any(isinstance(arg, Constant) and arg.text == "16"
                             for arg in ins.args)
            if has_heap and has_offset:
                root_heads.add(ins.dest.name)
    for block in unit.function.blocks:
        rewritten = []
        for ins in block.instructions:
            if ins.opcode == "call" and ins.extra == "myl_qbe_root_mark":
                rewritten.append(Instruction("copy", "l", ins.dest,
                                             [Constant("0", "l")], None,
                                             ins.line, "%root_mark =l copy 0"))
                inventory.add("removed", "arena_root_mark")
                continue
            if (ins.opcode.startswith("store") and len(ins.args) == 2 and
                    _temp(ins.args[1]) and ins.args[1].name in root_heads):
                inventory.add("removed", "arena_root_head_store")
                continue
            rewritten.append(ins)
        block.instructions = rewritten


def _strip_trace_frame(unit, inventory):
    """Remove the proven ctx+48 diagnostic frame chain and line slot writes."""
    if not unit.function.parameters:
        return
    context = unit.function.parameters[0][1].name
    counts, definitions = {}, {}
    for block in unit.function.blocks:
        for ins in block.instructions:
            if ins.dest is not None:
                counts[ins.dest.name] = counts.get(ins.dest.name, 0) + 1
                definitions[ins.dest.name] = ins
    frame_heads = {name for name, ins in definitions.items()
                   if counts[name] == 1 and ins.opcode == "add" and
                   any(_temp(arg) and arg.name == context for arg in ins.args) and
                   any(isinstance(arg, Constant) and arg.text == "48" for arg in ins.args)}
    records = set()
    for block in unit.function.blocks:
        for ins in block.instructions:
            if not ins.opcode.startswith("store") or len(ins.args) != 2:
                continue
            source, destination = ins.args
            if (_temp(source) and _temp(destination) and
                    destination.name in frame_heads):
                producer = definitions.get(source.name)
                if (producer is not None and producer.opcode == "alloc8" and
                        producer.args and isinstance(producer.args[0], Constant) and
                        producer.args[0].text == "32" and counts[source.name] == 1):
                    records.add(source.name)
    record_addresses = set(records)
    changed = True
    while changed:
        changed = False
        for name, ins in definitions.items():
            if counts[name] != 1 or ins.opcode != "add":
                continue
            if any(_temp(arg) and arg.name in record_addresses for arg in ins.args):
                if name not in record_addresses:
                    record_addresses.add(name)
                    changed = True
    if not records:
        return
    for block in unit.function.blocks:
        rewritten = []
        for ins in block.instructions:
            if (ins.opcode.startswith("store") and len(ins.args) == 2 and
                    _temp(ins.args[1]) and
                    ins.args[1].name in frame_heads | record_addresses):
                inventory.add("removed", "trace_frame_store")
                continue
            if (ins.opcode.startswith("load") and ins.dest is not None and
                    ins.args and _temp(ins.args[0]) and
                    ins.args[0].name in frame_heads | record_addresses):
                rewritten.append(Instruction("copy", ins.qbe_type or "l", ins.dest,
                                             [Constant("0", ins.qbe_type or "l")], None,
                                             ins.line, f"%{ins.dest.name} copy 0"))
                inventory.add("removed", "trace_frame_load")
                continue
            rewritten.append(ins)
        block.instructions = rewritten


def translate_unit(unit_il, options=None, signatures=None, unit_name="unit"):
    options = options or Options()
    if options.mode not in ("baseline", "arena", "unchecked"):
        raise ValueError(f"unknown maxperf mode {options.mode!r}")
    unit = parse_unit(unit_il, unit_name)
    inventory = Inventory()
    if options.mode in ("arena", "unchecked"):
        if not options.arena_proven:
            raise ValueError("arena root elision requires arena_proven=True")
        _strip_arena_roots(unit, inventory)
    if options.mode == "unchecked":
        _strip_guards(unit, inventory)
        _strip_trace_frame(unit, inventory)
    return Translation(llvm_emit.translate(unit, signatures), inventory)


def translate_ir(unit_il, **kwargs):
    """Convenience API for build scripts that need only LLVM IR text."""
    return translate_unit(unit_il, **kwargs).ir
