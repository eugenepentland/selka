#!/usr/bin/env python3
"""Translate one QBE unit into LLVM IR and compile it with the pinned toolchain.

The mylang native driver invokes a QBE-compatible tool as

    TOOL -t amd64_sysv -o OUTPUT.s INPUT.ssa

once per emitted unit, then assembles OUTPUT.s with `zig cc`.  This script is a
drop-in replacement for that tool: it parses the QBE IL, emits LLVM IR with the
same memory and calling behaviour, and runs `zig cc` to produce the assembly the
driver expects.

Design rules, in the order they constrain the code:

* Correctness first.  No `nsw`/`nuw`/`exact`/fast-math flags, no `inbounds`, no
  `noalias`, no TBAA: the frontend already emits every overflow, bounds, cast and
  allocation check as explicit code, and this translator must not introduce
  undefined behaviour ahead of a guard.
* QBE temporaries are mutable cells. Each gets a private entry-block slot;
  LLVM's promotion and SROA passes recover SSA where possible. Address arithmetic
  uses GEP only when conservative provenance checks establish an object origin.
* Source allocations stay where the source put them: the emitter deliberately
  hoists some aggregate scratch to the entry block and not others.
* An unsupported opcode, type or calling shape raises `ParseError` naming the
  unit, the line and the text.  Nothing falls back to QBE and nothing is
  silently replaced by zero.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import shlex
import subprocess
import sys

# ---------------------------------------------------------------------------
# QBE vocabulary
# ---------------------------------------------------------------------------

#: QBE base type letter -> bit width.
BASE_TYPES = {"w": 32, "l": 64, "s": 32, "d": 64}

#: Load opcode -> (bit width, sign-extend the loaded value).  QBE spells the
#: sized integer loads `loadsb`/`loadub`, `loadsh`/`loaduh` and `loadsw`/`loaduw`
#: (see `vendor/qbe/ops.h`); `loadb`/`loadh`/`loadw` are not opcodes at all, and a
#: row that can never match is invisible until a unit happens to contain the real
#: spelling, so every row here is checked against the vendored opcode table.
LOADS = {
    "loadsb": (8, True), "loadub": (8, False),
    "loadsh": (16, True), "loaduh": (16, False),
    "loadsw": (32, True), "loaduw": (32, False),
    "loadl": (64, True), "loads": (32, True), "loadd": (64, True),
}

#: Store opcode -> bit width.
STORES = {"storeb": 8, "storeh": 16, "storew": 32, "storel": 64,
          "stores": 32, "stored": 64}

#: Integer arithmetic opcode -> LLVM instruction.
INTEGER_OPS = {
    "add": "add", "sub": "sub", "mul": "mul", "and": "and", "or": "or",
    "xor": "xor", "shl": "shl", "sar": "ashr", "shr": "lshr",
    "div": "sdiv", "rem": "srem", "udiv": "udiv", "urem": "urem",
}

#: Comparison opcode -> (LLVM predicate, operand kind).  `c<stem><w>` is signed
#: or float, `cu<stem><w>` is unsigned or unordered, `co<w>` is ordered.  The
#: `eq`/`ne` stems exist only as `ceq`/`cne`; the unsigned forms are `cult` and
#: friends.  Verified against `vendor/qbe/ops.h`.
COMPARISONS = {}
for _width in ("w", "l"):
    _llvm_width = "i32" if _width == "w" else "i64"
    # QBE spells equality as `ceq`/`cne` plus the width, and the ordering forms
    # as `cs`/`cu` plus `lt`/`le`/`gt`/`ge` plus the width.
    COMPARISONS["ceq" + _width] = ("eq", "int", _llvm_width)
    COMPARISONS["cne" + _width] = ("ne", "int", _llvm_width)
    for _stem, _signed, _unsigned in (("lt", "slt", "ult"), ("le", "sle", "ule"),
                                      ("gt", "sgt", "ugt"), ("ge", "sge", "uge")):
        COMPARISONS["cs" + _stem + _width] = (_signed, "int", _llvm_width)
        COMPARISONS["cu" + _stem + _width] = (_unsigned, "int", _llvm_width)
for _width in ("s", "d"):
    _llvm_width = "float" if _width == "s" else "double"
    for _stem, _predicate in (("eq", "oeq"), ("ne", "une"), ("lt", "olt"),
                              ("le", "ole"), ("gt", "ogt"), ("ge", "oge")):
        COMPARISONS["c" + _stem + _width] = (_predicate, "float", _llvm_width)
    COMPARISONS["co" + _width] = ("ord", "float", _llvm_width)
    COMPARISONS["cuo" + _width] = ("uno", "float", _llvm_width)

#: QBE conversion opcode -> (kind, source type letter, destination letter).
#: Verified against `vendor/qbe/ops.h`: `exts`/`truncd` widen and narrow floats,
#: `extsb`…`extuw` widen integers, and the `*tof`/`*toi` pair name the width of
#: the *other* side (`swtof` is "signed word to float").
CONVERSIONS = {
    "extsw": ("ext", "w", "l"), "extuw": ("ext", "w", "l"),
    "extsh": ("ext", "h", "l"), "extuh": ("ext", "h", "l"),
    "extsb": ("ext", "b", "l"), "extub": ("ext", "b", "l"),
    "exts": ("fext", "s", "d"), "truncd": ("ftrunc", "d", "s"),
    "stosi": ("fptosi", "s", "w"), "dtosi": ("fptosi", "d", "w"),
    "stoui": ("fptoui", "s", "w"), "dtoui": ("fptoui", "d", "w"),
    "swtof": ("sitofp", "w", "s"), "uwtof": ("uitofp", "w", "s"),
    "sltof": ("sitofp", "l", "d"), "ultof": ("uitofp", "l", "d"),
    "cast": ("bitcast", None, None),
}

#: Widening conversion opcode -> source bit width.
EXT_WIDTH = {"extsw": 32, "extuw": 32, "extsh": 16, "extuh": 16,
             "extsb": 8, "extub": 8}

#: Conversion opcode -> the QBE type letter of its result.
CONVERSION_RESULT = {"stosi": "w", "dtosi": "w", "stoui": "w", "dtoui": "w",
                     "swtof": "s", "uwtof": "s", "sltof": "d", "ultof": "d",
                     "exts": "d", "truncd": "s"}

TERMINATORS = {"ret", "jmp", "jnz", "hlt"}

OPERATORS = (set(INTEGER_OPS) | {"neg", "not", "copy"} | set(LOADS) | set(STORES)
             | set(CONVERSIONS) | set(COMPARISONS)
             | {"call", "ret", "jmp", "jnz", "blit", "alloc4", "alloc8",
                "alloc16", "phi", "hlt"})

AGGREGATE_NAME = re.compile(r"^:[\w.$]+$")


class ParseError(Exception):
    """A QBE construct this translator refuses to guess about."""

    def __init__(self, message, unit="", line=0, text=""):
        detail = f"qbe_llvm: {unit}:{line}: {message}" if unit else f"qbe_llvm: {message}"
        if text:
            detail += f"\n    {text}"
        super().__init__(detail)
        self.unit = unit
        self.line = line
        self.text = text


# ---------------------------------------------------------------------------
# Operands
# ---------------------------------------------------------------------------

class Temp:
    """A QBE temporary (`%name`) or a global (`$name`)."""

    __slots__ = ("kind", "name", "qbe_type")

    def __init__(self, kind, name, qbe_type=None):
        self.kind = kind      # "temp" | "global"
        self.name = name
        self.qbe_type = qbe_type  # call-site annotation, when present

    def __repr__(self):
        return f"{'%' if self.kind == 'temp' else '$'}{self.name}"

    def key(self):
        return (self.kind, self.name)


class Constant:
    """A literal operand: an integer, a float, or an external symbol address."""

    __slots__ = ("text", "qbe_type")

    def __init__(self, text, qbe_type):
        self.text = text
        self.qbe_type = qbe_type

    def __repr__(self):
        return self.text


class IndirectTarget:
    """The callee of a call through a computed function value.

    `%result =l call %callee(l %ctx, ...)` invokes whatever function address the
    temporary holds.  The target is recognised by shape (`kind == "indirect"`)
    rather than by `isinstance`, because the tool is loaded both as a module and
    as `__main__`, so a class imported across that boundary is a different class.
    """

    __slots__ = ("kind", "name")

    def __init__(self, name):
        self.kind = "indirect"
        self.name = name

    def __repr__(self):
        return f"call %{self.name}(...)"


class CallOperand:
    """A nested call used as an operand, e.g. `add %a, call $f(...)`."""

    __slots__ = ("name", "args", "qbe_type")

    def __init__(self, name, args, qbe_type):
        self.name = name
        self.args = args
        self.qbe_type = qbe_type

    def __repr__(self):
        return f"call {self.name}(...)"


class Instruction:
    """One parsed QBE instruction."""

    __slots__ = ("opcode", "qbe_type", "dest", "args", "extra", "line", "text",
                 "ssa_dest")

    def __init__(self, opcode, qbe_type, dest, args, extra, line, text):
        self.opcode = opcode      # "add", "storel", "jnz", ...
        self.qbe_type = qbe_type  # the letter after `=`, or None
        self.dest = dest          # Temp or None
        self.args = args          # list of Temp/Constant/CallOperand
        self.extra = extra        # opcode-specific payload (labels, call name)
        self.line = line
        self.text = text
        self.ssa_dest = None      # filled in by the SSA pass

    def __repr__(self):
        return f"<{self.opcode} {self.args}>"


class Block:
    """A basic block: a label and the instructions that follow it."""

    __slots__ = ("label", "instructions")

    def __init__(self, label):
        self.label = label
        self.instructions = []

    def terminator(self):
        return self.instructions[-1] if self.instructions else None


class Function:
    """One parsed QBE unit."""

    def __init__(self, name, result, parameters, blocks, export, line):
        self.name = name                # symbol without the leading `$`
        self.result = result            # type letter, :aggregate, or None
        self.parameters = parameters    # list of (type, Temp)
        self.blocks = blocks            # list of Block, in source order
        self.export = export
        self.line = line


class Unit:
    """A parsed QBE unit: the aggregate definitions plus one function."""

    def __init__(self, function, aggregates, aggregate_alignments=None):
        self.function = function
        self.aggregates = aggregates    # :name -> byte size
        self.aggregate_alignments = aggregate_alignments or {
            name: 8 for name in aggregates}

    @property
    def name(self):
        """The emitted symbol of this unit's function, for diagnostics."""
        return self.function.name


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def aggregate_size(definition):
    """Byte size of an emitted aggregate definition, or None when it is not one."""
    match = re.fullmatch(r"(?:align\s+\d+\s+)?\{\s*b\s+(\d+)\s*\}", definition)
    if match:
        return int(match.group(1))
    if re.fullmatch(r"\{\s*l\s*,\s*l\s*\}", definition):
        return 16
    return None


def aggregate_alignment(definition):
    """Declared aggregate alignment (QBE defaults to its largest member)."""
    match = re.match(r"align\s+(\d+)\s+", definition)
    if match:
        return int(match.group(1))
    if re.fullmatch(r"\{\s*l\s*,\s*l\s*\}", definition):
        return 8
    return 1


def split_operands(text):
    """Split a comma-separated operand list, respecting call parentheses."""
    parts, depth, current = [], 0, ""
    for char in text:
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def strip_comment(line):
    """Remove a trailing `# ...` comment outside string literals."""
    out, in_string = [], False
    for char in line:
        if char == '"':
            in_string = not in_string
        if char == "#" and not in_string:
            break
        out.append(char)
    return "".join(out).strip()


def parse_unit(text, unit="unit"):
    """Parse one emitted QBE unit into a Unit."""
    aggregates, alignments = {}, {}
    for match in re.finditer(r"^type\s+(:\S+)\s*=\s*(.+?)\s*$", text, re.M):
        size = aggregate_size(match.group(2))
        if size is None:
            raise ParseError(f"unsupported aggregate definition "
                             f"`{match.group(1)} = {match.group(2)}`", unit)
        aggregates[match.group(1)] = size
        alignments[match.group(1)] = aggregate_alignment(match.group(2))
    body = re.sub(r"^type\s+:\S+\s*=.*$", "", text, flags=re.M)
    lines = body.split("\n")
    index = 0
    while index < len(lines) and not lines[index].strip():
        index += 1
    if index >= len(lines):
        raise ParseError("unit contains no function", unit)
    header = lines[index].strip()
    function, index = parse_header(header, lines, index, unit)
    function.blocks = parse_blocks(lines, index, unit)
    if not function.blocks:
        raise ParseError("function contains no blocks", unit, function.line, header)
    return Unit(function, aggregates, alignments)


def parse_header(header, lines, index, unit):
    """Parse a function header, returning the Function and the next line index."""
    line_number = index + 1
    export = False
    rest = header
    if rest.startswith("export "):
        export = True
        rest = rest[len("export "):]
    if not rest.startswith("function "):
        raise ParseError("expected a function header", unit, line_number, header)
    rest = rest[len("function "):]
    match = re.match(r"^\s*(?:(?P<result>[lwsbd]|:[\w.$]+)\s+)?\$(?P<name>[\w.$]+)\s*"
                     r"\((?P<params>.*?)\)\s*\{?\s*$", rest, re.S)
    if not match:
        raise ParseError("cannot parse the function signature", unit, line_number, header)
    parameters = []
    if match.group("params").strip():
        for item in split_operands(match.group("params")):
            parts = item.split()
            if len(parts) != 2 or not parts[1].startswith("%"):
                raise ParseError(f"cannot parse parameter `{item}`", unit, line_number, header)
            parameters.append((parts[0], Temp("temp", parts[1][1:])))
    index += 1
    if "{" not in header:
        while index < len(lines) and "{" not in lines[index]:
            index += 1
        index += 1
    return Function(match.group("name"), match.group("result"), parameters, [], export,
                    line_number), index


def parse_blocks(lines, index, unit):
    """Parse the block list of one function body."""
    blocks, current = [], None
    while index < len(lines):
        raw = lines[index]
        index += 1
        line = strip_comment(raw)
        if not line:
            continue
        if line == "}":
            break
        if line.startswith("@"):
            if " " in line:
                raise ParseError(f"unexpected text after a label: `{line}`", unit, index, raw)
            current = Block(line)
            blocks.append(current)
            continue
        if current is None:
            raise ParseError("instruction outside any block", unit, index, raw)
        current.instructions.append(parse_instruction(line, index, unit, raw))
    return blocks


ASSIGNMENT = re.compile(r"^%(?P<dest>[\w.$]+)\s*=\s*(?:(?P<type>[lwsbd]|:[\w.$]+)\s+)?(?P<rest>.*)$")


def parse_instruction(line, number, unit, raw):
    """Parse one instruction line."""
    dest = qbe_type = None
    match = ASSIGNMENT.match(line)
    if match:
        dest = Temp("temp", match.group("dest"))
        qbe_type = match.group("type")
        tail = match.group("rest").strip()
    else:
        tail = line
    tokens = tail.split(None, 1)
    opcode = tokens[0] if tokens else ""
    operands = tokens[1] if len(tokens) > 1 else ""
    return build_instruction(opcode, qbe_type, dest, operands, number, unit, raw)


def build_instruction(opcode, qbe_type, dest, operands, number, unit, raw):
    """Turn one opcode and its operand text into an Instruction."""
    def fail(message):
        raise ParseError(message, unit, number, raw)

    def one(text, expected=None):
        return operand(text, expected, unit, number)

    args, extra = [], None
    if opcode == "ret":
        if operands.strip():
            args = [one(operands)]
    elif opcode == "jmp":
        if not operands.strip().startswith("@"):
            fail("jmp target is not a label")
        extra = operands.strip()
    elif opcode == "jnz":
        parts = split_operands(operands)
        if len(parts) != 3:
            fail("jnz expects a value and two labels")
        args = [one(parts[0])]
        extra = (parts[1].strip(), parts[2].strip())
    elif opcode == "call":
        match = re.match(r"^(?P<target>[%$]?[\w.$]+)\s*\((?P<args>.*)\)\s*$", operands, re.S)
        if not match:
            fail("cannot parse a call")
        extra = call_target(match.group("target"))
        inner = split_operands(match.group("args")) if match.group("args").strip() else []
        args = [one(item, inner_parameter_type(item)) for item in inner]
    elif opcode == "phi":
        extra = []
        for item in split_operands(operands):
            parts = item.split()
            if len(parts) != 2:
                fail(f"cannot parse a phi input `{item}`")
            extra.append((parts[0], one(parts[1])))
    elif opcode in ("alloc4", "alloc8", "alloc16"):
        args = [one(operands, "l")]
    elif opcode == "blit":
        parts = split_operands(operands)
        if len(parts) != 3:
            fail("blit expects source, destination and size")
        args = [one(parts[0], "l"), one(parts[1], "l"), one(parts[2], "l")]
    elif opcode in STORES:
        parts = split_operands(operands)
        if len(parts) != 2:
            fail(f"{opcode} expects a value and an address")
        args = [one(parts[0]), one(parts[1], "l")]
    elif opcode in LOADS:
        args = [one(operands, "l")]
    elif opcode in ("copy", "neg", "not"):
        args = [one(operands)]
    elif opcode in INTEGER_OPS or opcode in COMPARISONS or opcode in CONVERSIONS:
        args = [one(item) for item in split_operands(operands)]
    elif opcode in ("hlt", "vastart", "vaarg"):
        fail(f"unsupported opcode `{opcode}`")
    else:
        fail(f"unknown opcode `{opcode}`")
    return Instruction(opcode, qbe_type, dest, args, extra, number, raw)


def call_target(token):
    """The callee of one call: a symbol name, or an `IndirectTarget` for `%temp`.

    A direct call names its callee (`$f`), an indirect call computes it
    (`%v`), and the two are the same call shape otherwise, so only the target
    differs between them.
    """
    if token.startswith("%"):
        return IndirectTarget(token[1:])
    return token.lstrip("$")


def inner_parameter_type(text):
    """The declared type text of one call argument, when it has one."""
    parts = text.split(None, 1)
    if parts and (parts[0] in BASE_TYPES or AGGREGATE_NAME.match(parts[0])):
        return parts[0]
    return None


def operand(text, qbe_type, unit, number):
    """Parse one operand into a Temp, Constant or CallOperand."""
    text = text.strip()
    if not text:
        raise ParseError("empty operand", unit, number, text)
    if text.startswith("%"):
        return Temp("temp", text[1:], qbe_type)
    if text.startswith("$"):
        return Temp("global", text[1:], qbe_type)
    if text.startswith("extern "):
        return Constant(text[len("extern "):].lstrip("$"), "extern")
    parts = text.split(None, 1)
    if len(parts) == 2 and (parts[0] in BASE_TYPES or AGGREGATE_NAME.match(parts[0])):
        # A typed operand: `l %v`, `:t... %v`, `w 0`.
        return operand(parts[1], parts[0], unit, number)
    if text.startswith("call "):
        match = re.match(r"^call\s+(?P<target>[%$]?[\w.$]+)\s*\((?P<args>.*)\)$", text, re.S)
        if not match:
            raise ParseError(f"cannot parse a nested call `{text}`", unit, number, text)
        inner = split_operands(match.group("args")) if match.group("args").strip() else []
        return CallOperand(call_target(match.group("target")),
                           [operand(item, inner_parameter_type(item), unit, number)
                            for item in inner], qbe_type)
    return Constant(text, qbe_type)


# ---------------------------------------------------------------------------
# Type inference
# ---------------------------------------------------------------------------

def llvm_scalar(letter):
    """The LLVM type of a QBE base type letter."""
    return {32: "i32", 64: "i64"}[BASE_TYPES[letter]]


def compare_operands(opcode):
    """(LLVM predicate, operand kind, operand LLVM type) for a comparison."""
    return COMPARISONS[opcode]


class Types:
    """What the translator knows about each temporary of one unit.

    ``kind[name]`` is ``"int"``, ``"float"`` or ``"aggregate"``; ``width[name]``
    is a bit width for the first two and an aggregate name for the third.  A
    temporary the emitter never gave a type appears in no map at all.
    """

    def __init__(self):
        self.kind = {}
        self.width = {}
        self.aggregates = {}    # aggregate name -> byte size

    def has(self, name):
        return name in self.kind

    def of(self, name):
        return self.kind[name], self.width[name]

    def record(self, name, kind, width, unit, line=0, text=""):
        """Record one temporary's type, rejecting a contradiction."""
        if name in self.kind:
            if (self.kind[name], self.width[name]) != (kind, width):
                raise ParseError(f"temporary %{name} has conflicting types "
                                 f"`{self.kind[name]}:{self.width[name]}` and "
                                 f"`{kind}:{width}`", unit, line, text)
            return False
        self.kind[name] = kind
        self.width[name] = width
        return True

    def record_letter(self, name, qbe_type, unit, line=0, text=""):
        """Record a type named by a QBE type letter or an aggregate name."""
        if AGGREGATE_NAME.match(qbe_type):
            if qbe_type not in self.aggregates:
                raise ParseError(f"undefined aggregate type `{qbe_type}`", unit, line, text)
            return self.record(name, "aggregate", qbe_type, unit, line, text)
        if qbe_type not in BASE_TYPES:
            raise ParseError(f"unsupported value type `{qbe_type}`", unit, line, text)
        kind = "float" if qbe_type in ("s", "d") else "int"
        return self.record(name, kind, BASE_TYPES[qbe_type], unit, line, text)


def letter_for(kind, width):
    """The QBE type letter of an integer or float type."""
    if kind == "float":
        return {32: "s", 64: "d"}[width]
    return {32: "w", 64: "l"}[width]


def infer_types(unit):
    """Resolve the QBE type of every temporary this unit defines.

    The result is a `Types`.  Emitted definitions nearly always name their type
    or use an opcode whose result type is fixed, so a short fixpoint over the
    definition sites (which also follows `copy`) resolves the rest.
    """
    types = Types()
    types.aggregates = dict(unit.aggregates)
    function = unit.function
    for qbe_type, temp in function.parameters:
        types.record_letter(temp.name, qbe_type, "unit", function.line)
    for _pass in range(4):
        changed = False
        for block in function.blocks:
            for instruction in block.instructions:
                changed |= record_definition(types, instruction)
        if not changed:
            break
    return types


def record_definition(types, instruction):
    """Record the destination type of one instruction.  Returns whether it is new."""
    dest = instruction.dest
    if dest is None or types.has(dest.name):
        return False
    opcode = instruction.opcode
    line, text = instruction.line, instruction.text
    if instruction.qbe_type is not None:
        return types.record_letter(dest.name, instruction.qbe_type, "unit", line, text)
    if opcode in EXT_WIDTH:
        return types.record(dest.name, "int", 64, "unit", line, text)
    if opcode in CONVERSIONS:
        kind, _source, _target = CONVERSIONS[opcode]
        if kind == "bitcast":
            source = instruction.args[0]
            if isinstance(source, Temp) and types.has(source.name):
                return types.record(dest.name, *types.of(source.name), "unit", line, text)
            return False
        return types.record_letter(dest.name, CONVERSION_RESULT[opcode], "unit", line, text)
    if opcode in COMPARISONS:
        _predicate, operand_kind_name, llvm_type = COMPARISONS[opcode]
        if operand_kind_name == "float":
            return types.record(dest.name, "float", 64 if llvm_type == "double" else 32,
                                "unit", line, text)
        return types.record(dest.name, "int", 64 if llvm_type == "i64" else 32,
                            "unit", line, text)
    if opcode in INTEGER_OPS or opcode in ("neg", "not"):
        width = operand_width(types, instruction.args[0], "unit")
        if width is None:
            return False
        return types.record(dest.name, "int", width, "unit", line, text)
    if opcode == "copy":
        source = instruction.args[0]
        if isinstance(source, Temp) and types.has(source.name):
            return types.record(dest.name, *types.of(source.name), "unit", line, text)
    return False


def operand_width(types, arg, unit):
    """The integer width of an operand, or None when it is not known yet."""
    if isinstance(arg, Temp):
        if arg.kind == "global":
            return 64
        if types.kind.get(arg.name) == "int":
            return types.width[arg.name]
        return None
    if isinstance(arg, Constant):
        if arg.qbe_type in BASE_TYPES:
            return BASE_TYPES[arg.qbe_type]
        return 64
    return None


# Operand recognition is structural throughout.  The tool runs as a script, so
# `qbe_llvm` is also loaded as `__main__` and `llvm_emit`'s `from qbe_llvm import`
# binds a second, distinct copy of every class: `isinstance` against the classes
# defined here would reject the objects this module itself parsed.
def is_temporary(arg):
    """True for a parsed `%temporary` or `$global` operand."""
    return getattr(arg, "kind", None) in ("temp", "global") and hasattr(arg, "name")


def is_constant(arg):
    """True for a parsed literal operand."""
    return hasattr(arg, "text") and hasattr(arg, "qbe_type")


def is_call(arg):
    """True for a nested call used as an operand."""
    return (hasattr(arg, "args") and hasattr(arg, "name")
            and not is_temporary(arg) and not is_constant(arg))


def is_remapped(arg):
    """True for an operand the SSA pass replaced with one of its renamed values."""
    return (hasattr(arg, "value") and hasattr(arg, "name")
            and not is_temporary(arg) and not is_call(arg) and not is_constant(arg))


def operand_kind(types, arg, unit):
    """(kind, width-or-aggregate-name) of an operand, raising when it is unknown."""
    if is_remapped(arg):
        if arg.name in types.kind:
            return types.of(arg.name)
        raise ParseError(f"temporary %{arg.name} is used before any definition",
                         unit, 0, repr(arg))
    if is_constant(arg):
        if arg.qbe_type == "extern":
            return ("int", 64)
        if arg.qbe_type in BASE_TYPES:
            kind = "float" if arg.qbe_type in ("s", "d") else "int"
            return (kind, BASE_TYPES[arg.qbe_type])
        return ("int", 64)
    if is_call(arg):
        if arg.qbe_type is None:
            return ("int", 64)
        if AGGREGATE_NAME.match(arg.qbe_type):
            return ("aggregate", arg.qbe_type)
        kind = "float" if arg.qbe_type in ("s", "d") else "int"
        return (kind, BASE_TYPES[arg.qbe_type])
    if is_temporary(arg):
        if arg.kind == "global":
            return ("int", 64)
        if types.has(arg.name):
            return types.of(arg.name)
    else:
        raise ParseError(f"unsupported operand {arg!r}", unit)
    raise ParseError(f"temporary %{arg.name} is used before any definition",
                     unit, 0, repr(arg))


# ---------------------------------------------------------------------------
# The QBE-compatible tool interface
# ---------------------------------------------------------------------------

VERSION = "1"


def signature_map(unit):
    """The unit's own signature, as a caller elsewhere would see it."""
    parameters = tuple(letter for letter, _temp in unit.function.parameters)
    result = unit.function.result
    return (parameters, result)


def translate_text(text, unit_name, signatures=None):
    """Translate one unit's QBE IL text into LLVM IR text."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import llvm_emit

    unit = parse_unit(text, unit_name)
    table = dict(signatures or {})
    table.setdefault(unit.function.name, signature_map(unit))
    return llvm_emit.translate(unit, table)


#: Where a build's closure signatures are collected when the caller does not name
#: a path.  Every unit published its own signature while the closure is compiled,
#: so a unit that runs after its callees sees their real declarations instead of
#: guessing from its own call site.
SIGNATURE_DIRECTORY = "/tmp/mylang-llvm-signatures"
SIGNATURE_FILE = SIGNATURE_DIRECTORY + "/signatures.json"


def signature_path(environment=None, output=None):
    """The sidecar for one build.

    Scoped to the build, because the signatures of one program say nothing about
    another: an unscoped file would let a stale entry from an unrelated build
    drive a declaration's type.  The environment variable wins when it is set,
    which is how a measurement harness gives one batch a private sidecar; the
    fallback is a fixed ancestor chain of the output path, which is stable for
    every unit of one build and different between builds.
    """
    source = os.environ if environment is None else environment
    declared = (source or {}).get("MYLANG_QBE_LLVM_SIGNATURES")
    if declared:
        return declared
    if output:
        # `<cache>/<generation>/<temporary>/unit.s`: two levels up is the build's
        # working directory, whose own parent is the generation.
        scope = os.path.dirname(os.path.dirname(os.path.abspath(output)))
        digest = hashlib.sha256(scope.encode()).hexdigest()[:16]
        return os.path.join(SIGNATURE_DIRECTORY, f"{digest}.json")
    return SIGNATURE_FILE


def load_signatures(path):
    """Read the closure signatures collected from the units of this build.

    A unit's own IL knows how *it* is declared but not how its callees are, and
    an aggregate result has to be recognised as one at the call site.  Every
    invocation therefore publishes its own signature into a sidecar beside the
    units it is compiled with, and reads whatever is already there, so a
    translation that runs after its callees sees their real declarations.
    """
    if not path or not os.path.exists(path):
        return {}
    import json
    try:
        with open(path) as handle:
            raw = json.load(handle)
    except (OSError, ValueError):
        return {}
    return {name: (tuple(entry["parameters"]), entry["result"])
            for name, entry in raw.items()}


def publish_signatures(path, name, signature):
    """Add one unit's signature to the sidecar, atomically enough for one build."""
    if not path:
        return
    import json
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        table = {}
        if os.path.exists(path):
            with open(path) as handle:
                table = json.load(handle)
        table[name] = {"parameters": list(signature[0]), "result": signature[1]}
        temporary = path + f".{os.getpid()}"
        with open(temporary, "w") as handle:
            json.dump(table, handle, indent=1, sort_keys=True)
        os.replace(temporary, path)
    except (OSError, ValueError):
        # A missing sidecar only costs precision on aggregate call boundaries, so
        # a concurrent build losing this race must not fail the compilation.
        pass


def compile_ir(ir_text, output):
    """Assemble LLVM IR into the assembly the driver links."""
    optimization = os.environ.get("MYLANG_QBE_LLVM_OPT", "-O2")
    keep_ir = os.environ.get("MYLANG_QBE_LLVM_KEEP_IR")
    if keep_ir:
        with open(keep_ir, "w") as handle:
            handle.write(ir_text)
    ir_path = output + ".ll"
    with open(ir_path, "w") as handle:
        handle.write(ir_text)
    zig = os.environ.get("MYLANG_QBE_LLVM_ZIG", "zig")
    if os.environ.get("MYLANG_QBE_LLVM_EMIT_LTO_OBJECT"):
        command = [zig, "cc", "-c", "-flto", "-march=native", optimization, "-fPIC", "-g0", ir_path, "-o", output]
    else:
        command = [zig, "cc", "-S", optimization, "-fPIC", "-g0", ir_path, "-o", output]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise ParseError(f"LLVM rejected the translated unit:\n{completed.stderr}\n"
                         f"IR kept at {ir_path}")
    if not keep_ir:
        os.unlink(ir_path)
    return output


def main(argv=None):
    """The `qbe`-compatible command line: `TOOL -t TARGET -o OUT.s IN.ssa`."""
    # The driver invokes this file once per unit.  Writing bytecode would leave a
    # cache that can outlive an edit to these modules, so it is never written.
    sys.dont_write_bytecode = True
    parser = argparse.ArgumentParser(prog="qbe_llvm.py", add_help=True)
    parser.add_argument("-t", "--target", default="amd64_sysv")
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("inputs", nargs="+")
    options = parser.parse_args(argv)
    if options.target != "amd64_sysv":
        sys.stderr.write(f"qbe_llvm: unsupported target `{options.target}`\n")
        return 1
    sidecar = signature_path(os.environ, options.output)
    signatures = load_signatures(sidecar)
    source = options.inputs[0]
    with open(source) as handle:
        text = handle.read()
    unit_name = os.environ.get("MYLANG_QBE_LLVM_UNIT", os.path.basename(source))
    try:
        unit = parse_unit(text, unit_name)
        publish_signatures(sidecar, unit.function.name, signature_map(unit))
        ir_text = translate_text(text, unit_name, signatures)
    except ParseError as error:
        sys.stderr.write(f"{error}\n")
        return 1
    try:
        compile_ir(ir_text, options.output)
    except ParseError as error:
        sys.stderr.write(f"{error}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
