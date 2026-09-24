#!/usr/bin/env python3
"""LLVM IR emission for the emitted QBE subset.

The QBE the compiler emits is not SSA: a temporary is a mutable cell, and the
emitter reuses names for anchors, copies and results.  Reconstructing SSA from it
is possible but every dominance subtlety becomes a correctness risk, so this
module takes the strategy the experiment plan prescribes instead: every temporary
gets one private slot at the top of the LLVM entry block, each definition stores
to its slot and each use loads from it.  LLVM's own `mem2reg`/SROA promotion then
turns those slots back into SSA values, so the optimization the comparison is
about still happens — inside the backend being measured, on a form that is
correct by construction rather than by a hand-written dominance proof.

Two properties matter for correctness:

* An aggregate value in this IL is the *address* of its storage, so `:tN` is an
  `i64` here like any other pointer-width integer, and only the instruction that
  touches memory converts it with `inttoptr`.
* No `nsw`/`nuw`/`exact`/fast-math flags and no `inbounds`: the frontend emits its
  own checks, and a flag this translator cannot prove would introduce undefined
  behaviour ahead of them.  Scoped alias metadata is the one exception, because
  it states a fact about *where* memory lives rather than about a value a check
  is about to test: `MemoryClasses` below places an access in this activation's
  own stack storage or outside it, and an access it cannot place carries no
  metadata at all.
"""

from __future__ import annotations

import hashlib
import heapq
import os
import re
import sys

from qbe_llvm import (AGGREGATE_NAME, BASE_TYPES, COMPARISONS, CONVERSIONS,
                      EXT_WIDTH, INTEGER_OPS, LOADS, STORES, infer_types,
                      letter_for)
from amd64_sysv import aggregate_abi
from runtime_signatures import signature as runtime_signature, ATTRIBUTES as runtime_attributes

# ---------------------------------------------------------------------------
# Structural operand recognition
# ---------------------------------------------------------------------------
# The tool runs as a script, so `qbe_llvm` is also loaded as `__main__` and a
# `from qbe_llvm import Temp` here would bind a second, distinct class.  Operands
# are therefore recognised by shape, never by `isinstance`.


def is_temporary(value):
    """True for a parsed `%temporary` or `$global`."""
    return getattr(value, "kind", None) in ("temp", "global") and hasattr(value, "name")


def target_attribute(name):
    """Read one driver-resolved target attribute, rejecting malformed input."""
    value = os.environ.get(name, "")
    if value and not re.fullmatch(r"[A-Za-z0-9+._,-]+", value):
        raise ParseError(f"invalid {name} value")
    return value


def is_constant(value):
    """True for a parsed literal operand."""
    return hasattr(value, "text") and hasattr(value, "qbe_type")


def is_call(value):
    """True for a nested call used as an operand."""
    return (hasattr(value, "args") and hasattr(value, "name")
            and not is_temporary(value) and not is_constant(value))


def is_indirect(value):
    """True for a call target computed at run time (`call %temp(...)`)."""
    return getattr(value, "kind", None) == "indirect"


class CalleeTemp:
    """A parsed `%temporary` rebuilt here for a call target the parser computed.

    The parser owns the real `Temp` class, and this module is loaded both beside
    it and as `__main__`, so a temporary is reconstructed by shape rather than
    imported: `kind`, `name` and `qbe_type` are the whole contract.
    """

    __slots__ = ("kind", "name", "qbe_type")

    def __init__(self, name, qbe_type="l"):
        self.kind = "temp"
        self.name = name
        self.qbe_type = qbe_type

    def __repr__(self):
        return f"%{self.name}"


#: The same opcode covers integer, single and double arithmetic; the destination's
#: own type selects the LLVM instruction.
FLOAT_OPS = {"add": "fadd", "sub": "fsub", "mul": "fmul", "div": "fdiv"}

#: A temporary with no inferred type still gets a pointer-width slot.
DEFAULT_SLOT = ("int", 64)

#: The frontend names every guest function `myl_f_<hash>` and every runtime
#: function `myl_<family>_*`; only the first kind is defined inside the build.
GUEST_SYMBOL = re.compile(r"^myl_f_[0-9a-f]{16,}$")

# C/library entry points whose source signature cannot be inferred from QBE's
# pointer-width `l`.  LLVM intrinsics are used where they express the operation
# more precisely than a C declaration.  Unknown runtime helpers keep the typed
# QBE call shape; adding a C helper requires adding and testing it here.
C_HELPERS = {
    "memset": ("intrinsic-memset", ("ptr", "i8", "i64"), "void"),
}


def llvm_scalar(kind, width):
    """The LLVM type of a value of one inferred kind and width."""
    if kind == "aggregate":
        return "i64"
    if kind == "float":
        return "double" if width == 64 else "float"
    return f"i{width}"


def letter_type(letter):
    """The LLVM type of a QBE type letter or aggregate name.

    `l` and every `:tN` are integers of pointer width: this IL passes aggregates
    as addresses and does arithmetic on the same values.
    """
    if letter in (None, "l") or AGGREGATE_NAME.match(letter):
        return "i64"
    if letter in ("s", "d"):
        return "double" if letter == "d" else "float"
    return f"i{BASE_TYPES[letter]}"


def kind_is_integer(width):
    """Whether a QBE width names an integer type rather than a float."""
    return width in (8, 16, 32, 64)


def bit_width(llvm):
    """The bit width of an LLVM integer type, or None for floats."""
    if llvm.startswith("i") and llvm[1:].isdigit():
        return int(llvm[1:])
    return None


class ParseError(Exception):
    """A translation diagnostic the tool reports instead of guessing."""


class Slot:
    """One temporary's private storage and the LLVM type it holds."""

    __slots__ = ("name", "pointer", "llvm", "size")

    def __init__(self, name, pointer, llvm, size):
        self.name = name
        self.pointer = pointer
        self.llvm = llvm
        self.size = size


def aggregate_bytes(letter, sizes):
    """The byte size of an aggregate type name, from the unit's own definitions."""
    if not AGGREGATE_NAME.match(letter or ""):
        return None
    return sizes.get(letter)


# ---------------------------------------------------------------------------
# Memory classes
# ---------------------------------------------------------------------------
# Two classes carry the whole model.  `frame` is storage this activation itself
# obtained: every `alloc4/8/16` of the unit — the local slots, the operand
# scratch, the aggregate scratch, the root records and the frame record — the
# private copy an aggregate parameter arrives in, and, for a unit whose frame is
# too large for the stack, the block `myl_qbe_frame_allocate` freshly allocated
# for it on entry and releases on exit.  `foreign` is storage some other
# allocation owns: a value the caller computed (a scalar parameter such as
# `%ctx`), a global's address, the context's embedded heap record, and every
# address the frontend marked `# myl-obj` — a managed container's header or the
# element storage that header points at, both of which came from
# `myl_native_heap_alloc`.
#
# The two are disjoint because everything in `frame` is an allocation this
# activation made after it was entered: no value that existed before the call can
# point into it, no managed object is allocated inside it, and it is released
# before the activation returns.  So an access of one class never aliases an
# access of the other.  Anything the analysis cannot place stays untagged and
# keeps aliasing both, which is what makes the classification safe to be
# incomplete.

FRAME = "frame"
FOREIGN = "foreign"

#: Runtime helpers whose C definition fixes the class of the address they answer.
#: `myl_qbe_frame_allocate` returns a fresh `calloc` block that holds only this
#: activation's slots and that `myl_qbe_frame_release` frees on the way out;
#: `myl_qbe_heap` computes the address of the context's embedded heap record,
#: which is the caller's storage and never one of this unit's allocations.
HELPER_CLASSES = {"myl_qbe_frame_allocate": FRAME, "myl_qbe_heap": FOREIGN}

#: Metadata identifiers of the two scopes and of the one-element scope lists a
#: tagged access names.  The domain and both scopes are `distinct`, so the IR
#: linker cannot unify one unit's classes with another's during LTO.
ALIAS_METADATA = """
!0 = distinct !{!0, !"mylang memory classes"}
!1 = distinct !{!1, !0, !"frame"}
!2 = distinct !{!2, !0, !"foreign"}
!3 = !{!1}
!4 = !{!2}
"""

#: LLVM-ELEMENT-CLASS-1: a foreign access is placed more finely when the
#: frontend said what it touches.  An access through an *object* (a container
#: header, an allocation's payload: `# myl-obj`) and one through a container's
#: *element storage* (`# myl-elem %v KIND`) never meet: every storage block is
#: an allocation of its own, apart from every object.  Storage blocks of
#: different element kinds never meet either, because a block only ever holds
#: elements of its one kind (a block of GC references is never read as plain
#: values or the reverse, and no two element sizes share a block).  A plain
#: foreign access (a parameter, a global, the context) names none of these
#: scopes in its `!noalias` and so still aliases all of them, and the frame
#: scope list is unchanged: an object or element access names the frame scope
#: in its own `!noalias`.  All scopes are `distinct` members of the unit's one
#: domain, so the IR linker never unifies two units' classes.
OBJECT = "object"
ELEMENT = "element"
OBJECT_SCOPE = 5
#: Element kind number j uses !(ELEMENT_BASE + 3j) as its scope, the next
#: number as its scope list and the one after as its `!noalias` list.
ELEMENT_BASE = 11
#: Kinds beyond this many stay plainly foreign: the numbers stop short of the
#: frame-map debug nodes (`FRAME_MAP_METADATA_BASE`).
MAX_ELEMENT_KINDS = 29
#: Scope lists a copy between two classes names are numbered from here, clear
#: of every number the frame-map debug nodes can reach.
SCOPE_LIST_BASE = 10000000

#: What one class names as its own scope list and as the list it cannot alias.
ALIAS_SUFFIX = {FRAME: ", !alias.scope !3, !noalias !4",
                FOREIGN: ", !alias.scope !4, !noalias !3",
                OBJECT: ", !alias.scope !6, !noalias !7"}


class Dominators:
    """The dominance relation of one control-flow graph, by block label.

    `edges` maps every label to its successor labels and `entry` is where
    control starts.  The immediate dominators come from the iterative
    algorithm of Cooper, Harvey and Kennedy over reverse postorder; one walk of
    the dominator tree then numbers every block on entry and exit, so a query
    is two comparisons.  A block dominates itself; a block control cannot
    reach neither dominates nor is dominated.
    """

    def __init__(self, entry, edges):
        postorder, seen, stack = [], {entry}, [(entry, iter(edges.get(entry, ())))]
        while stack:
            label, successors = stack[-1]
            advanced = False
            for successor in successors:
                if successor not in seen:
                    seen.add(successor)
                    stack.append((successor, iter(edges.get(successor, ()))))
                    advanced = True
                    break
            if not advanced:
                postorder.append(label)
                stack.pop()
        rank = {label: index for index, label in enumerate(postorder)}
        predecessors = {label: [] for label in postorder}
        for label in postorder:
            for successor in edges.get(label, ()):
                predecessors[successor].append(label)
        idom = {entry: entry}
        reverse = list(reversed(postorder))
        changed = True
        while changed:
            changed = False
            for label in reverse[1:]:
                chosen = None
                for predecessor in predecessors[label]:
                    if predecessor not in idom:
                        continue
                    chosen = predecessor if chosen is None else self._meet(idom, rank, predecessor, chosen)
                if chosen is not None and idom.get(label) != chosen:
                    idom[label] = chosen
                    changed = True
        children = {label: [] for label in idom}
        for label, parent in idom.items():
            if label != entry:
                children[parent].append(label)
        self.enter, self.leave, clock, walk = {}, {}, 0, [(entry, False)]
        while walk:
            label, done = walk.pop()
            if done:
                self.leave[label] = clock
            else:
                self.enter[label] = clock
                walk.append((label, True))
                walk.extend((child, False) for child in children[label])
            clock += 1

    @staticmethod
    def _meet(idom, rank, left, right):
        """The nearest common dominator of two processed blocks."""
        while left != right:
            while rank[left] < rank[right]:
                left = idom[left]
            while rank[right] < rank[left]:
                right = idom[right]
        return left

    def dominates(self, dominator, block):
        """Whether every path from the entry to `block` passes `dominator`."""
        if dominator not in self.enter or block not in self.enter:
            return False
        return self.enter[dominator] <= self.enter[block] and self.leave[block] <= self.leave[dominator]


class MemoryClasses:
    """Which memory class each temporary of one unit addresses.

    The result is deliberately partial: `of(name)` answers `None` for every
    temporary the unit does not place beyond doubt, and an unplaced address is
    emitted without metadata.  A contradiction anywhere — one temporary reached
    as both classes — discards the whole unit's classification rather than
    emitting a fact the analysis just disproved.
    """

    def __init__(self, function, sizes):
        self.function = function
        self.sizes = sizes
        self.classes = {}
        self.conflict = False
        self.counts = self._definition_counts()
        self.slots = self._simple_slots()
        self._classify()
        if self.conflict:
            self.classes = {}
        self.refined = self._refine()

    def of(self, name):
        """The class of one temporary, or None when the unit does not place it."""
        return self.classes.get(name)

    def access_class(self, argument):
        """The class one access through `argument` is tagged with.

        A foreign address the frontend placed in a container's element storage
        or in an object is `ELEMENT` or `OBJECT` (LLVM-ELEMENT-CLASS-1);
        everything else answers its plain class.
        """
        klass = self.operand_class(argument)
        if klass == FOREIGN and is_temporary(argument) and argument.kind == "temp":
            return self.refined.get(argument.name, klass)
        return klass

    def _refine(self):
        """Split the foreign addresses into objects and element storage.

        Seeds: a temporary the frontend marked `# myl-elem %v KIND` is the
        start of an element storage block holding elements of that kind, and
        every other `# myl-obj` temporary is an object — a container header or
        an allocation's payload.  A class then travels through `copy` and
        offsetting `add` exactly as `_derive` carries the coarse class.  An
        `add` that combines two different refined classes is a contradiction,
        and a contradiction drops the whole refinement, leaving every foreign
        access plainly foreign, as it was before this refinement existed.
        """
        elements = dict(getattr(self.function, "element_hints", {}) or {})
        refined = {}
        for name in set(self.function.object_hints) | set(elements):
            if self.counts.get(name) != 1 or self.classes.get(name) != FOREIGN:
                continue
            refined[name] = (ELEMENT, elements[name]) if name in elements else OBJECT
        for _round in range(8):
            changed = False
            for block in self.function.blocks:
                for instruction in block.instructions:
                    if instruction.dest is None or instruction.opcode not in ("copy", "add"):
                        continue
                    name = instruction.dest.name
                    if self.counts.get(name) != 1 or self.classes.get(name) != FOREIGN:
                        continue
                    seen = {refined.get(argument.name) for argument in instruction.args
                            if is_temporary(argument) and argument.kind == "temp"}
                    seen.discard(None)
                    if len(seen) > 1:
                        return {}
                    if len(seen) == 1:
                        result = self._refine_one(refined, name, seen.pop())
                        if result is None:
                            return {}
                        changed = changed or result
            through = self._refine_through_slots(refined)
            if through is None:
                return {}
            if not changed and not through:
                break
        return refined

    @staticmethod
    def _refine_one(refined, name, klass):
        """Refine one temporary; None on a contradiction, else whether it is new."""
        previous = refined.get(name)
        if previous is not None and previous != klass:
            return None
        refined[name] = klass
        return previous is None

    def _refine_through_slots(self, refined):
        """Carry a refined class through a simple slot by the same must-analysis
        that carries the coarse one (`_slot_flow`).  None on a contradiction,
        else whether anything new was refined."""
        def value_class(value):
            if is_temporary(value) and value.kind == "temp":
                return refined.get(value.name)
            return None

        changed = False
        for name, klass in self._slot_flow(value_class).items():
            if self.counts.get(name) != 1 or self.classes.get(name) != FOREIGN:
                continue
            result = self._refine_one(refined, name, klass)
            if result is None:
                return None
            changed = changed or result
        return changed

    def _definition_counts(self):
        """How many times each temporary of this unit is defined."""
        counts = {temp.name: 1 for _letter, temp in self.function.parameters}
        for block in self.function.blocks:
            for instruction in block.instructions:
                if instruction.dest is not None:
                    counts[instruction.dest.name] = counts.get(instruction.dest.name, 0) + 1
        return counts

    def _note(self, name, klass):
        """Place one singly-defined temporary, reporting whether that is new."""
        if klass is None or self.counts.get(name) != 1:
            return False
        previous = self.classes.get(name)
        if previous is None:
            self.classes[name] = klass
            return True
        if previous != klass:
            self.conflict = True
        return False

    def _simple_slots(self):
        """Stack slots whose address the unit never lets out of its own hands.

        A slot qualifies when it is one `alloc*` whose every appearance is as the
        address of a `loadl` or a `storel`: nothing else can read or write it, so
        the value a load answers is one the unit itself stored.
        """
        allocated = {instruction.dest.name
                     for block in self.function.blocks
                     for instruction in block.instructions
                     if instruction.dest is not None and instruction.opcode.startswith("alloc")}
        escaped = set()
        for block in self.function.blocks:
            for instruction in block.instructions:
                for index, argument in enumerate(instruction.args):
                    if not is_temporary(argument) or argument.kind != "temp":
                        continue
                    if argument.name not in allocated:
                        continue
                    if instruction.opcode == "loadl" and index == 0:
                        continue
                    if instruction.opcode == "storel" and index == 1:
                        continue
                    escaped.add(argument.name)
                if instruction.opcode == "phi":
                    for _predecessor, argument in instruction.extra:
                        if is_temporary(argument) and argument.name in allocated:
                            escaped.add(argument.name)
        return {name for name in allocated
                if name not in escaped and self.counts.get(name) == 1}

    def _classify(self):
        """Seed the two classes and run the derivation to a fixed point."""
        for letter, temp in self.function.parameters:
            self._note(temp.name,
                       FRAME if aggregate_bytes(letter, self.sizes) is not None else FOREIGN)
        for block in self.function.blocks:
            for instruction in block.instructions:
                if instruction.dest is None:
                    continue
                if instruction.opcode.startswith("alloc"):
                    self._note(instruction.dest.name, FRAME)
                elif instruction.opcode == "call" and isinstance(instruction.extra, str):
                    self._note(instruction.dest.name, HELPER_CLASSES.get(instruction.extra))
        for name in self.function.object_hints:
            self._note(name, FOREIGN)
        for _round in range(8):
            changed = self._derive()
            changed = self._through_slots() or changed
            if not changed or self.conflict:
                break

    def operand_class(self, argument):
        """The class of one operand, or None when it is not an address this unit places."""
        if is_temporary(argument):
            if argument.kind == "global":
                return FOREIGN
            return self.classes.get(argument.name)
        return None

    def _derive(self):
        """Carry a class through `copy` and through offsetting `add`."""
        changed = False
        for block in self.function.blocks:
            for instruction in block.instructions:
                if instruction.dest is None or instruction.opcode not in ("copy", "add"):
                    continue
                if instruction.dest.name in self.classes:
                    continue
                seen = {self.operand_class(argument) for argument in instruction.args}
                seen.discard(None)
                if len(seen) == 1:
                    changed = self._note(instruction.dest.name, seen.pop()) or changed
        return changed

    def _through_slots(self):
        """Carry a class through a simple slot (`_slot_flow`).

        This is what carries a class across the push and pop the frontend's
        operand stack writes around every value, within a block and across
        the branches a checked operation or a guard opens between them.
        """
        changed = False
        for name, klass in self._slot_flow(self.operand_class).items():
            changed = self._note(name, klass) or changed
        return changed

    def _slot_flow(self, value_class):
        """The class of every load of a simple slot into a singly-defined temporary.

        A forward must-analysis: at each point a simple slot holds the class of
        the value the last store put there, on every path that reaches the
        point, or nothing when two paths disagree, a path stored an unplaced
        value, or a path reaches it before any store (the slot then holds
        whatever the frame held).  A simple slot is written and read only by
        `storel`/`loadl` through its own `alloc` temporary, so no other
        instruction — not a call, not a store through another address — can
        change it.  `value_class` answers the class of one stored operand.
        Returns {load destination: class}.
        """
        blocks = self.function.blocks
        index = {block.label: position for position, block in enumerate(blocks)}
        successors = {}
        for position, block in enumerate(blocks):
            following = blocks[position + 1].label if position + 1 < len(blocks) else None
            successors[block.label] = [label for label in self._successors(block, following)
                                       if label in index]
        state_in = {blocks[0].label: {}}
        pending = [(0, blocks[0].label)]
        queued = {blocks[0].label}
        loads = {}
        while pending:
            _position, label = heapq.heappop(pending)
            queued.discard(label)
            state = dict(state_in[label])
            for instruction in blocks[index[label]].instructions:
                target = self._slot_store_target(instruction)
                if target is not None:
                    klass = value_class(instruction.args[0])
                    if klass is None:
                        state.pop(target, None)
                    else:
                        state[target] = klass
                    continue
                source = self._slot_load_source(instruction)
                if source is not None:
                    loads[instruction.dest.name] = state.get(source)
            for successor in successors[label]:
                previous = state_in.get(successor)
                if previous is None:
                    merged = state
                else:
                    merged = {slot: klass for slot, klass in previous.items()
                              if state.get(slot) == klass}
                if previous is None or merged != previous:
                    state_in[successor] = dict(merged)
                    if successor not in queued:
                        queued.add(successor)
                        heapq.heappush(pending, (index[successor], successor))
        return {name: klass for name, klass in loads.items() if klass is not None}

    def _successors(self, block, following):
        """The labels control can reach from one block, fall-through included."""
        terminator = block.terminator()
        if terminator is None:
            return [following] if following else []
        if terminator.opcode == "jmp":
            return [terminator.extra]
        if terminator.opcode == "jnz":
            return list(terminator.extra)
        if terminator.opcode in ("ret", "hlt"):
            return []
        return [following] if following else []

    def _slot_store_target(self, instruction):
        """The simple slot one `storel` writes, or None."""
        if instruction.opcode != "storel" or len(instruction.args) != 2:
            return None
        target = instruction.args[1]
        if is_temporary(target) and target.kind == "temp" and target.name in self.slots:
            return target.name
        return None

    def _slot_load_source(self, instruction):
        """The simple slot one `loadl` reads into a singly-defined temporary, or None."""
        if instruction.opcode != "loadl" or instruction.dest is None or not instruction.args:
            return None
        source = instruction.args[0]
        if is_temporary(source) and source.kind == "temp" and source.name in self.slots:
            return source.name
        return None


# ---------------------------------------------------------------------------
# Checked arithmetic (LLVM-OVERFLOW-INTRINSIC-1)
# ---------------------------------------------------------------------------
# The frontend checks a 64-bit `+ - *` with plain integer code: it computes the
# wrapped result and then an overflow flag from it (`src/qbe_scalar.zig`,
# `checkedAddSub`/`checkedMul`).  LLVM does not recognise those idioms — a
# signed add reaches the machine as `add; mov; xor; mov; xor; test; js`, and the
# 64-bit multiply as a four-limb high product — so this pass finds each flag
# whose value is *exactly* one of the frontend's formulas over one `add`, `sub`
# or `mul` of the same block, and lowers that instruction to
# `llvm.{s,u}{add,sub,mul}.with.overflow.i64`: its first result replaces the
# wrapped value and its second replaces the flag.  Nothing else changes — the
# old flag computation is still emitted (LLVM deletes it once nothing reads it),
# the branch, the cold block and its `myl_qbe_fail_overflow_op` call with the
# same operands and position are untouched.
#
# The match is by value, not by text.  Every temporary of one block is
# evaluated symbolically in order: a pure `l` operation becomes a tuple of its
# opcode and its operands' values, a literal becomes its 64-bit pattern, and
# anything else (a load, a call, a phi, a value from another block) becomes a
# leaf that only equals itself.  Tuples compare structurally, so two operands
# are "the same" exactly when they are the same computation over the same
# leaves, whatever the temporaries were called and however often a name was
# reassigned in between.  A flag is rewritten only when its value tuple equals
# the formula below, built over the operands of an arithmetic instruction that
# precedes it in the block.  Each formula is an identity for every pair of
# 64-bit inputs (`test_adapter.OverflowFormulaTests` checks them exhaustively on
# the boundaries and on random operands), so the rewrite needs no fact about the
# operands' ranges and no fact about the check.  A narrower width's range check
# (`r < min or r > max` over the exact 64-bit result) is not an overflow
# intrinsic without assuming the operands already lie in that width, which the
# IL cannot show, so it is left as it is; so is the one-compare test the
# frontend emits against a literal operand, which is already a single compare.

#: Pure 64-bit opcodes the symbolic evaluation models (everything the formulas
#: below use).  Any other definition is a leaf.
OVERFLOW_PURE = {"add", "sub", "mul", "and", "xor", "shr", "sar", "neg",
                 "csltl", "cultl", "cnel"}

_MASK64 = (1 << 64) - 1


def _k(value):
    """The symbolic value of a 64-bit literal."""
    return ("const", value & _MASK64)


def _unsigned_high(a, b):
    """`qbe_scalar.unsignedHigh`: the high 64 bits of `a * b`, four 32-bit limbs."""
    def low(v):
        return ("and", v, _k(0xFFFFFFFF))

    def high(v):
        return ("shr", v, _k(32))
    base = ("mul", low(a), low(b))
    middle = ("add", ("mul", high(a), low(b)), high(base))
    total = ("add", ("mul", low(a), high(b)), low(middle))
    return ("add", ("add", ("mul", high(a), high(b)), high(middle)), high(total))


def overflow_formulas(result):
    """(intrinsic stem, flag value) pairs the frontend derives from `result`.

    `result` is the symbolic value of one `add`, `sub` or `mul`; each pair names
    the `llvm.<stem>.with.overflow.i64` whose overflow bit equals the flag.
    """
    opcode, a, b = result
    zero = _k(0)
    if opcode == "add":
        return (("sadd", ("csltl", ("and", ("xor", a, result), ("xor", b, result)), zero)),
                ("uadd", ("cultl", result, a)))
    if opcode == "sub":
        return (("ssub", ("csltl", ("and", ("xor", a, b), ("xor", a, result)), zero)),
                ("usub", ("cultl", a, b)))
    high = _unsigned_high(a, b)
    signed_high = ("sub", ("sub", high, ("and", b, ("neg", ("csltl", a, zero)))),
                   ("and", a, ("neg", ("csltl", b, zero))))
    return (("umul", ("cnel", high, zero)),
            ("smul", ("cnel", signed_high, ("sar", result, _k(63)))))


class OverflowChecks:
    """The checked 64-bit operations of one unit, found by value.

    `producers` maps an arithmetic instruction (by `id`) to the intrinsic stems
    it must also compute; `flags` maps a flag definition to the arithmetic
    instruction and stem whose overflow bit it is.  `excluded` names the
    temporaries that hold object addresses: an `add` of one is lowered as a
    `getelementptr` (`Emitter.on_arithmetic`), so it is left alone.
    """

    @staticmethod
    def _address(instruction, excluded):
        return instruction.opcode == "add" and any(
            is_temporary(argument) and (argument.kind == "global" or argument.name in excluded)
            for argument in instruction.args)

    def __init__(self, function, excluded=frozenset()):
        self.producers = {}
        self.flags = {}
        for block in function.blocks:
            self._scan(block, excluded)

    def _scan(self, block, excluded):
        values, expected = {}, {}

        def value(argument):
            if is_temporary(argument):
                if argument.kind == "global":
                    return ("global", argument.name)
                return values.get(argument.name, ("entry", argument.name))
            if is_constant(argument) and argument.qbe_type != "extern":
                try:
                    return _k(int(argument.text, 0))
                except ValueError:
                    pass
            return ("leaf", id(argument))

        for instruction in block.instructions:
            if instruction.dest is None:
                continue
            opcode, args = instruction.opcode, instruction.args
            arity = 1 if opcode == "neg" else 2
            if (opcode in OVERFLOW_PURE and instruction.qbe_type == "l"
                    and len(args) == arity):
                node = (opcode, *(value(argument) for argument in args))
            else:
                node = ("leaf", id(instruction))
            match = expected.get(node)
            if match is not None:
                producer, stem = match
                self.flags[id(instruction)] = (id(producer), stem)
                stems = self.producers.setdefault(id(producer), [])
                if stem not in stems:
                    stems.append(stem)
            values[instruction.dest.name] = node
            if opcode in ("add", "sub", "mul") and node[0] == opcode \
                    and not self._address(instruction, excluded):
                for stem, flag in overflow_formulas(node):
                    expected[flag] = (instruction, stem)


#: The runtime's failure helpers: each records a trap and calls `fail`.
FAIL_HELPER_PREFIX = "myl_qbe_fail_"

#: First metadata number the frame-map debug nodes use, clear of the alias
#: scopes (`ALIAS_METADATA`, !0-!4).
FRAME_MAP_METADATA_BASE = 100

#: A call line in the emitted LLVM, direct or through a pointer.
LLVM_CALL = re.compile(r"^\s*(?:%[\w.]+ = )?call ")


class FrameMapDebug:
    """Call-site positions for a frame-map unit (QBE-FRAMEMAP-1).

    The frontend links no frame record in a fast executable.  It positions
    every call with `dbgloc PC+1` instead, and the build maps each call's
    return address to its frames from the assembly LLVM prints
    (`src/qbe_frame_map.zig`).  Each call gets a debug location whose line is
    the position and whose discriminator is a pseudo-probe call index equal to
    it.  LLVM then prints `.pseudoprobe GUID INDEX ...` immediately before the
    call, and when the call was inlined through other guest functions it
    appends `@ GUID:INDEX` for every caller — so LLVM may inline guest code
    freely and the trace still names each logical frame at its own call site.
    `llvm.pseudo_probe_desc` is what turns the probe inserter on and names each
    GUID's function for the build.

    * A runtime helper LLVM inlines carries no debug information, so every
      instruction of its body takes the location — and the probe — of the call
      it replaced: a trap inside it reports the helper's call site, as the
      record's position did.
    * Every call is `nomerge`: merging two call sites would merge their
      positions, and `"disable-tail-calls"` keeps a call from replacing its
      caller's frame.  `uwtable` gives every such function asynchronous unwind
      tables: the runtime walks an LLVM program's stack by its CFI (the linked
      libunwind's `_Unwind_Backtrace`), so no guest function spends a register
      or a push on a frame pointer.
    * A probe index is 16 bits.  A call at a position past that carries its
      location without a probe and is `noinline`, and so is its function, so
      nothing is ever inlined through a position the probe cannot name; the
      build reads such a call's position from its `.loc` line instead.
    * The entry guard's frame-failure call (column 1) gets probe index 0,
      which the build records as a frame to skip.
    * A unit that makes no call carries no debug information: no trap can
      start in it and no frame can be above it, so inlining it changes no
      trace, and its inlined body takes its call site's location.

    The compile unit is `DebugDirectivesOnly`, so LLVM prints `.file`/`.loc`
    and no DWARF; the build removes those and the probe directives after
    reading them.
    """

    #: The largest pseudo-probe index LLVM can encode in a discriminator.
    MAX_PROBE = 0xFFFF

    def __init__(self, unit):
        self.file = getattr(unit, "debug_file", None)
        positions = [instruction.extra
                     for block in unit.function.blocks for instruction in block.instructions
                     if instruction.opcode == "dbgloc"]
        self.active = self.file is not None and bool(positions)
        self.unprobed = any(self.probe(line, column) is None and line != 0
                            for line, column in positions)
        self.location = (0, 0)
        self.locations = {}

    @staticmethod
    def probe(line, column):
        """The probe index one `dbgloc` position gets, or None."""
        if column == 1:
            return 0
        if 1 <= line <= FrameMapDebug.MAX_PROBE:
            return line
        return None

    @staticmethod
    def discriminator(index):
        """LLVM's pseudo-probe discriminator for a direct-call probe `index`:
        `PseudoProbeDwarfDiscriminator::packProbeData(index, DirectCall, 0,
        FullDistributionFactor)`."""
        return (index << 3) | (100 << 19) | (2 << 26) | 0x7

    def guid(self):
        """The GUID LLVM derives from the subprogram's linkage name: the low
        eight bytes of its MD5, little-endian."""
        return int.from_bytes(hashlib.md5(self.file.encode()).digest()[:8], "little")

    def attributes(self):
        """The function attributes a frame-map unit's definition carries."""
        if not self.active:
            return []
        extra = ["noinline"] if self.unprobed else []
        return ["uwtable", '"disable-tail-calls"="true"', *extra]

    def reference(self, location):
        """The metadata number of one `(line, column)` debug location."""
        number = self.locations.get(location)
        if number is None:
            number = FRAME_MAP_METADATA_BASE + 10 + 2 * len(self.locations)
            self.locations[location] = number
        return number

    def position_calls(self, lines):
        """Mark every call line `nomerge` and give it the current location."""
        if not self.active:
            return lines
        reference = self.reference(self.location)
        unprobed = self.probe(*self.location) is None
        out = []
        for line in lines:
            if LLVM_CALL.match(line):
                if "@llvm." not in line and line.rstrip().endswith(")"):
                    line += " nomerge noinline" if unprobed else " nomerge"
                line += f", !dbg !{reference}"
            out.append(line)
        return out

    def subprogram(self):
        """The `!dbg` suffix of the function definition, or ''."""
        return f" !dbg !{FRAME_MAP_METADATA_BASE + 1}" if self.active else ""

    def metadata(self):
        """Named and numbered debug metadata for the module."""
        if not self.active:
            return []
        base = FRAME_MAP_METADATA_BASE
        name = self.file.replace("\\", "\\\\").replace('"', '\\"')
        out = [
            f"!llvm.dbg.cu = !{{!{base}}}",
            f"!llvm.module.flags = !{{!{base + 2}, !{base + 3}}}",
            f"!llvm.pseudo_probe_desc = !{{!{base + 7}}}",
            f'!{base} = distinct !DICompileUnit(language: DW_LANG_C99, file: !{base + 4}, '
            'producer: "mylang", isOptimized: true, runtimeVersion: 0, '
            "emissionKind: DebugDirectivesOnly)",
            f'!{base + 4} = !DIFile(filename: "{name}", directory: "")',
            f'!{base + 1} = distinct !DISubprogram(name: "{name}", linkageName: "{name}", '
            f"scope: !{base + 4}, file: !{base + 4}, line: 1, type: !{base + 5}, "
            f"spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !{base})",
            f"!{base + 5} = !DISubroutineType(types: !{base + 6})",
            f"!{base + 6} = !{{}}",
            f'!{base + 2} = !{{i32 7, !"Dwarf Version", i32 4}}',
            f'!{base + 3} = !{{i32 2, !"Debug Info Version", i32 3}}',
            f'!{base + 7} = !{{i64 {self.guid()}, i64 0, !"{name}"}}',
        ]
        for (line, column), number in sorted(self.locations.items(), key=lambda item: item[1]):
            index = self.probe(line, column)
            scope = f"!{base + 1}"
            if index is not None:
                out.append(f"!{number + 1} = !DILexicalBlockFile(scope: !{base + 1}, "
                           f"file: !{base + 4}, discriminator: {self.discriminator(index)})")
                scope = f"!{number + 1}"
            out.append(f"!{number} = !DILocation(line: {line}, column: {column}, scope: {scope})")
        return out


class Emitter:
    """Translates one parsed QBE unit into a self-contained LLVM module."""

    def __init__(self, unit, signatures=None):
        self.unit = unit
        self.function = unit.function
        self.types = infer_types(unit)
        self.signatures = dict(signatures or {})
        self.counter = 0
        self.slots = {}
        self.globals = {}          # $symbol -> LLVM type
        self.declarations = {}     # symbol -> (parameter types, result type)
        self.attributes = set()
        self.slot_lines = []
        self.sizes = dict(unit.aggregates)
        self.alignments = dict(unit.aggregate_alignments)
        self.aggregate_slots = {}
        self.call_result_buffers = {}
        self.pointer_values = self.find_pointer_values()
        self.stack_guard_compare = self.find_stack_guard_compare()
        self.overflow = OverflowChecks(self.function, self.pointer_values)
        #: (id(arithmetic instruction), stem) -> the LLVM `i1` overflow bit.
        self.overflow_bits = {}
        self.assign_slots()
        self.phi_stores = self.collect_phi_stores()
        self.memory = (MemoryClasses(self.function, self.sizes)
                       if os.environ.get("MYLANG_QBE_LLVM_ALIAS", "1") != "0" else None)
        self.alias_metadata = False
        #: LLVM-ELEMENT-CLASS-1: element kinds in first-use order.
        self.element_kinds = []
        #: Scope lists a copy between two classes names, by members.
        self.scope_lists = {}
        self.frame_map = FrameMapDebug(unit)
        #: LLVM-ELEMENT-GEP-1: singly-defined temporaries, and the position of
        #: each one defined so far in the block being emitted.
        self.single = {name for name, count in self.definition_counts().items() if count == 1}
        self.element_gep = os.environ.get("MYLANG_QBE_LLVM_ELEMENT_GEP", "1") != "0"
        self.block_positions, self.block_definitions = {}, {}
        self.position = 0

    def alias_of(self, argument):
        """The alias metadata one access through this address operand carries.

        An address the unit does not place beyond doubt carries none, which
        leaves it aliasing every class, the way every access behaved before any
        of this metadata existed.
        """
        if self.memory is None:
            return ""
        suffix = self.class_suffix(self.memory.access_class(argument))
        if suffix:
            self.alias_metadata = True
        return suffix

    def class_suffix(self, klass):
        """The `!alias.scope`/`!noalias` suffix of one memory class."""
        if isinstance(klass, tuple):
            kind = klass[1]
            if kind not in self.element_kinds:
                if len(self.element_kinds) >= MAX_ELEMENT_KINDS:
                    return ALIAS_SUFFIX[FOREIGN]
                self.element_kinds.append(kind)
            scope = ELEMENT_BASE + 3 * self.element_kinds.index(kind)
            return f", !alias.scope !{scope + 1}, !noalias !{scope + 2}"
        return ALIAS_SUFFIX.get(klass, "")

    def element_metadata(self):
        """The object and element scopes (LLVM-ELEMENT-CLASS-1), always emitted
        with the frame/foreign ones because the object suffix names them, and
        the scope lists a copy between two classes names."""
        scopes = [ELEMENT_BASE + 3 * index for index in range(len(self.element_kinds))]
        base = OBJECT_SCOPE
        out = [f'!{base} = distinct !{{!{base}, !0, !"object"}}',
               f"!{base + 1} = !{{!{base}}}",
               "!{} = !{{{}}}".format(base + 2, ", ".join(["!1"] + [f"!{scope}" for scope in scopes]))]
        for kind, scope in zip(self.element_kinds, scopes):
            others = [f"!{other}" for other in scopes if other != scope]
            out.append(f'!{scope} = distinct !{{!{scope}, !0, !"element {kind}"}}')
            out.append(f"!{scope + 1} = !{{!{scope}}}")
            out.append("!{} = !{{{}}}".format(scope + 2, ", ".join(["!1", f"!{base}"] + others)))
        for members, number in sorted(self.scope_lists.items(), key=lambda item: item[1]):
            out.append("!{} = !{{{}}}".format(number, ", ".join(f"!{member}" for member in members)))
        return out

    def class_scopes(self, klass):
        """(own scopes, scopes it cannot alias) of one memory class, as numbers.

        An element or object class's second set names only the element kinds
        this unit has used so far; a set that later grows only ever gains
        facts, so an answer taken early is a subset of the final one."""
        if klass == FRAME:
            return {1}, {2}
        if klass == FOREIGN:
            return {2}, {1}
        kinds = [ELEMENT_BASE + 3 * index for index in range(len(self.element_kinds))]
        if klass == OBJECT:
            return {OBJECT_SCOPE}, {1, *kinds}
        self.class_suffix(klass)
        if klass[1] not in self.element_kinds:
            return {2}, {1}
        own = ELEMENT_BASE + 3 * self.element_kinds.index(klass[1])
        return {own}, {1, OBJECT_SCOPE, *(scope for scope in kinds if scope != own)}

    def scope_list(self, members):
        """The metadata number of one scope list a copy names."""
        key = tuple(sorted(members))
        number = self.scope_lists.get(key)
        if number is None:
            number = SCOPE_LIST_BASE + len(self.scope_lists)
            self.scope_lists[key] = number
        return number

    def alias_of_both(self, first, second):
        """The metadata a two-address copy carries.

        The copy reads one end and writes the other, and LLVM applies one pair
        of lists to both, so its scopes are both ends' scopes and the scopes it
        cannot alias are the ones neither end can alias (LLVM-ELEMENT-CLASS-1).
        A copy with an end the unit does not place carries none."""
        if self.memory is None:
            return ""
        left = self.memory.access_class(first)
        right = self.memory.access_class(second)
        if left is None or right is None:
            return ""
        if left == right:
            suffix = self.class_suffix(left)
            if suffix:
                self.alias_metadata = True
            return suffix
        own_left, apart_left = self.class_scopes(left)
        own_right, apart_right = self.class_scopes(right)
        self.alias_metadata = True
        suffix = f", !alias.scope !{self.scope_list(own_left | own_right)}"
        apart = apart_left & apart_right
        if apart:
            suffix += f", !noalias !{self.scope_list(apart)}"
        return suffix

    def aggregate_abi(self, letter, force_memory=False):
        size = aggregate_bytes(letter, self.sizes)
        if size is None:
            return None
        return aggregate_abi(size, self.alignments[letter], force_memory)

    def parameter_abis(self, letters, result_letter=None):
        """Classify the whole signature, including SysV register rollback."""
        result = self.aggregate_abi(result_letter)
        gp_used = 1 if result is not None and result.indirect else 0
        out = []
        for letter in letters:
            aggregate = self.aggregate_abi(letter)
            if aggregate is not None:
                words = (aggregate.size + 7) // 8
                force_memory = aggregate.indirect or gp_used + words > 6
                aggregate = self.aggregate_abi(letter, force_memory)
                if not aggregate.indirect:
                    gp_used += words
                out.append(aggregate)
            else:
                llvm = letter_type(letter)
                if llvm not in ("float", "double"):
                    gp_used += 1
                out.append(llvm)
        return out

    def find_stack_guard_compare(self):
        """Identify the frontend's physical stack-floor comparison.

        The proof uses control-flow shape, not temporary names: an unsigned-less
        comparison feeds a branch with one floor-failure and one stack-admission
        successor.  Its address operand is replaced with the backend's actual
        stack pointer after the complete static frame has been allocated.
        """
        for block in self.function.blocks:
            for branch_index, branch in enumerate(block.instructions):
                if branch.opcode != "jnz":
                    continue
                targets = tuple(label.lower() for label in branch.extra)
                looks_like_guard = (any("floorfail" in label for label in targets) and
                                    any("stackadmit" in label for label in targets))
                if not looks_like_guard:
                    continue
                # QBE temporaries are mutable.  Use only the last definition that
                # reaches this branch in its straight-line prologue; a later
                # textual redefinition in stackadmit must not validate a decoy.
                definitions = {}
                for index, preceding in enumerate(block.instructions[:branch_index]):
                    if preceding.dest is not None:
                        definitions.setdefault(preceding.dest.name, []).append((index, preceding))
                def reaching(name, before):
                    candidates = definitions.get(name, ())
                    return next(((index, ins) for index, ins in reversed(candidates)
                                 if index < before), (None, None))
                condition = branch.args[0]
                seen = set()
                use_index = branch_index
                while is_temporary(condition) and condition.name not in seen:
                    seen.add(condition.name)
                    producer_index, producer = reaching(condition.name, use_index)
                    if producer is None:
                        break
                    if producer.opcode == "copy":
                        condition = producer.args[0]
                        use_index = producer_index
                        continue
                    if producer.opcode == "cultl":
                        left = producer.args[0]
                        _, left_def = (reaching(left.name, producer_index)
                                       if is_temporary(left) else (None, None))
                        right = producer.args[1]
                        right_index, right_def = (reaching(right.name, producer_index)
                                                  if is_temporary(right) else (None, None))
                        floor_address = None
                        if right_def is not None and right_def.opcode == "loadl":
                            address = right_def.args[0]
                            _, floor_address = (reaching(address.name, right_index)
                                                if is_temporary(address) else (None, None))
                        floor_offset = False
                        if floor_address is not None and floor_address.opcode == "add":
                            floor_offset = any(is_constant(arg) and arg.text == "64"
                                               for arg in floor_address.args)
                        if (left_def is not None and left_def.opcode.startswith("alloc") and
                                right_def is not None and right_def.opcode == "loadl" and
                                floor_offset):
                            return producer
                    break
                raise ParseError(f"{self.unit.name}: stack-floor branch does not match "
                                 "the checked allocation/load/compare shape")
        return None

    def definition_counts(self):
        """How many times each temporary of this unit is defined."""
        counts = {temp.name: 1 for _letter, temp in self.function.parameters}
        for block in self.function.blocks:
            for ins in block.instructions:
                if ins.dest is not None:
                    counts[ins.dest.name] = counts.get(ins.dest.name, 0) + 1
        return counts

    # -- element addresses (LLVM-ELEMENT-GEP-1) ----------------------------
    #
    # The frontend computes an element's address as integer arithmetic on the
    # storage word it loaded from a container header (`# myl-obj %storage`,
    # then `add %storage, %offset`), and every access turns that integer into a
    # pointer with `inttoptr`.  Scalar evolution does not look through
    # `inttoptr`, so to LLVM's loop analyses `data[i]` in a loop is an unknown
    # pointer per iteration: the vectorizer gathers it byte by byte instead of
    # loading a vector, and cannot compute a dependence distance at all.
    #
    # So a load or store whose address is such a sum, computed earlier in the
    # same block, is given the address as `getelementptr i8` from the marked
    # object: the same bits, with the variable part visible as an offset.  The
    # integer `add` is still emitted for every other reader.  Only a sum with a
    # non-constant term is rewritten, which is an element access; a header
    # field keeps its integer form, and so does every `blit`, so the two forms
    # never meet on a copy LLVM needs to see as a self-copy.  A plain (not
    # `inbounds`) `getelementptr` is wrapping address arithmetic: it states
    # nothing the integer sum did not.

    def element_chain(self, argument):
        """(base, offsets) when a load/store address is an element sum, else None.

        The address must be a singly-defined `add` emitted earlier in this
        block, its operands followed through further such `add`s down to a
        singly-defined temporary the frontend marked as a managed address.
        Every temporary on the way is singly defined and none is defined in
        this block after the sum that reads it, so reloading them at the access
        reproduces exactly the operands the sum used.
        """
        if not self.element_gep or not is_temporary(argument) or argument.kind != "temp":
            return None
        offsets = []
        name = argument.name
        use_position = self.position
        for _depth in range(8):
            if name in self.function.object_hints and name in self.single:
                variable = any(is_temporary(offset) for offset in offsets)
                return (name, list(reversed(offsets))) if variable else None
            position = self.block_positions.get(name)
            if name not in self.single or position is None or position >= use_position:
                return None
            definition = self.block_definitions[name]
            if definition.opcode != "add" or definition.qbe_type != "l" or len(definition.args) != 2:
                return None
            for operand in definition.args:
                if not is_temporary(operand):
                    continue
                if operand.kind != "temp" or operand.name not in self.single:
                    return None
                later = self.block_positions.get(operand.name)
                if later is not None and later >= position:
                    return None
            left, right = definition.args
            follow = None
            for rank in (0, 1):
                for candidate, other in ((left, right), (right, left)):
                    if follow is None and is_temporary(candidate) and (
                            candidate.name in self.function.object_hints if rank == 0 else
                            getattr(self.block_definitions.get(candidate.name), "opcode", None) == "add"):
                        follow, offset = candidate, other
            if follow is None:
                return None
            offsets.append(offset)
            name = follow.name
            use_position = position
        return None

    def access_pointer(self, lines, argument):
        """The pointer a load or store uses for one address operand."""
        chain = self.element_chain(argument)
        if chain is None:
            return self.address(lines, self.render(lines, argument, "int", 64, "i64"))
        base, offsets = chain
        pointer = self.address(lines, self.load_slot(lines, base))
        for offset in offsets:
            value = self.render(lines, offset, "int", 64, "i64")
            gep = self.fresh("egep")
            lines.append(f"  %{gep} = getelementptr i8, ptr {pointer}, i64 {value}")
            pointer = f"%{gep}"
        return pointer

    def find_pointer_values(self):
        """Find values whose bits retain an actual object-address origin.

        This is derived from parsed operations, rather than rewriting optimized
        IR that merely happens to resemble address arithmetic.  Only allocations,
        aggregate parameters, globals, and copies/additions derived from them are
        admitted.
        """
        definition_count = {temp.name: 1 for _letter, temp in self.function.parameters}
        for block in self.function.blocks:
            for ins in block.instructions:
                if ins.dest is not None:
                    definition_count[ins.dest.name] = definition_count.get(ins.dest.name, 0) + 1

        def unique(name):
            return definition_count.get(name) == 1

        pointers = {temp.name for letter, temp in self.function.parameters
                    if aggregate_bytes(letter, self.sizes) is not None and unique(temp.name)}
        # Only explicit origins establish provenance.  A later memory use does
        # not prove that integer arithmetic constructing its address was
        # object-relative.
        for block in self.function.blocks:
            for ins in block.instructions:
                if ins.dest is None or not unique(ins.dest.name):
                    continue
                if ins.opcode.startswith("alloc"):
                    pointers.add(ins.dest.name)
                elif ins.opcode == "call":
                    # A computed callee has no symbol to look a C signature up
                    # by; only an aggregate destination proves an address here.
                    exact = None if is_indirect(ins.extra) else runtime_signature(ins.extra)
                    if ((exact is not None and exact[1] == "ptr") or
                            aggregate_bytes(ins.qbe_type, self.sizes) is not None):
                        pointers.add(ins.dest.name)
        changed = True
        while changed:
            changed = False
            for block in self.function.blocks:
                for ins in block.instructions:
                    if ins.dest is None or not unique(ins.dest.name):
                        continue
                    derived = ins.dest.name in pointers
                    if ins.opcode in ("copy", "add"):
                        derived |= any((is_temporary(arg) and
                                        (arg.kind == "global" or arg.name in pointers))
                                       for arg in ins.args)
                    if derived and ins.dest.name not in pointers:
                        pointers.add(ins.dest.name)
                        changed = True
        return pointers

    # -- names -------------------------------------------------------------

    def fresh(self, stem="t"):
        """A fresh LLVM local name."""
        self.counter += 1
        return f"{stem}{self.counter}"

    def label(self, block_label):
        """The LLVM label of a QBE block label."""
        return "bb_" + block_label.lstrip("@").replace(".", "_")

    def type_of(self, name):
        """(kind, width) of a temporary, defaulting to a pointer-width integer."""
        if self.types.has(name):
            return self.types.of(name)
        return DEFAULT_SLOT

    def llvm_of(self, name):
        """The LLVM type of a temporary."""
        kind, width = self.type_of(name)
        return llvm_scalar(kind, width)

    # -- slots -------------------------------------------------------------

    def assign_slots(self):
        """Give every temporary one slot in the entry block.

        A definition the unit never reads still gets a slot: the frontend keeps
        dead stores on purpose (scratch anchors and root pushes), and dropping
        them is LLVM's decision to make, not this translator's.
        """
        for qbe_type, temp in self.function.parameters:
            size = aggregate_bytes(qbe_type, self.sizes)
            if size is None:
                self.slot(temp.name)
            else:
                self.aggregate_slots[temp.name] = size
        for block in self.function.blocks:
            for instruction in block.instructions:
                if instruction.dest is not None:
                    self.slot(instruction.dest.name)
                    abi = self.aggregate_abi(instruction.qbe_type)
                    if instruction.opcode == "call" and abi is not None:
                        pointer = self.fresh("callresult")
                        self.call_result_buffers[id(instruction)] = (pointer, abi)
                        self.slot_lines.append(
                            f"  %{pointer} = alloca {abi.storage}, align {abi.alignment}")

    def slot(self, name):
        """The slot of one temporary, created on first use.

        A temporary that an aggregate parameter arrived in keeps a pointer-width
        slot holding the address of the copy; every other temporary's slot holds
        the value itself.
        """
        existing = self.slots.get(name)
        if existing is not None:
            return existing
        kind, width = self.type_of(name)
        llvm = llvm_scalar(kind, width)
        size = 8 if kind != "float" else (8 if width == 64 else 4)
        pointer = self.fresh("slot")
        created = Slot(name, pointer, llvm, size)
        self.slots[name] = created
        self.slot_lines.append(f"  %{pointer} = alloca {llvm}, "
                               f"align {min(size, 8)}")
        return created

    def reserve_aggregate(self, name, size):
        """Reserve a pointer-width slot for an aggregate parameter's address."""
        created = self.slot(name)
        return created

    def load_slot(self, lines, name):
        """Load a temporary's current value."""
        held = self.slot(name)
        value = self.fresh("v")
        lines.append(f"  %{value} = load {held.llvm}, ptr %{held.pointer}, "
                     f"align {min(held.size, 8)}")
        return f"%{value}"

    def store_slot(self, lines, name, value):
        """Store a value into a temporary's slot."""
        held = self.slot(name)
        lines.append(f"  store {held.llvm} {value}, ptr %{held.pointer}, "
                     f"align {min(held.size, 8)}")

    def address(self, lines, value):
        """Append an `inttoptr` of an integer address and return the pointer."""
        pointer = self.fresh("p")
        lines.append(f"  %{pointer} = inttoptr i64 {value} to ptr")
        return f"%{pointer}"

    # -- operands ----------------------------------------------------------

    def render(self, lines, argument, kind, width, llvm):
        """Render an operand as an LLVM value of type `llvm`.

        `lines` collects any instruction the widening or a nested call needs.
        """
        if is_temporary(argument):
            if argument.kind == "global":
                return self.global_address(argument.name)
            value = self.load_slot(lines, argument.name)
            return self.widen(lines, value, self.llvm_of(argument.name), llvm)
        if is_call(argument):
            value = self.render_call(lines, argument.name, argument.args, llvm)
            return self.widen(lines, value, llvm, llvm)
        if is_constant(argument):
            return self.constant(argument, llvm)
        raise ParseError(f"{self.unit.name}: unsupported operand {argument!r}")

    def constant(self, constant, llvm):
        """Render a literal as an LLVM constant of type `llvm`."""
        if constant.qbe_type == "extern":
            # `extern $sym` names storage the generated C metadata defines; this
            # unit only declares it.
            self.globals.setdefault(constant.text, "i8")
            return f"ptrtoint (ptr @{constant.text} to i64)"
        if llvm in ("double", "float"):
            literal = float(constant.text)
            if literal != literal or literal in (float("inf"), float("-inf")):
                bits = (0x7FF8000000000000 if literal != literal
                        else 0x7FF0000000000000 if literal > 0
                        else 0xFFF0000000000000)
                if llvm == "double":
                    return f"bitcast (i64 {bits} to double)"
                return f"bitcast (i32 {bits >> 32} to float)"
            return repr(literal)
        try:
            bits = int(constant.text, 0)
        except ValueError:
            try:
                bits = int(float(constant.text))
            except ValueError:
                raise ParseError(f"{self.unit.name}: cannot parse the constant "
                                 f"`{constant.text}`")
        width = bit_width(llvm)
        return str(bits & ((1 << width) - 1)) if width else str(bits)

    def global_address(self, name):
        """Register a `$symbol` global and return its address as an integer."""
        self.globals.setdefault(name, "i8")
        return f"ptrtoint (ptr @{name} to i64)"

    def widen(self, lines, value, source, target):
        """Convert between two scalar types, appending an instruction if needed.

        The IL reinterprets the same 64 bits as an integer or a double freely
        (`cast`, `loadl` of a float field, `storel` of a float), so a conversion
        between two equally wide types is a `bitcast`: the bits are the value.
        """
        if source == target:
            return value
        source_bits, target_bits = bit_width(source), bit_width(target)
        name = self.fresh("cv")
        if source == "double" and target == "i64" or source == "i64" and target == "double":
            lines.append(f"  %{name} = bitcast {source} {value} to {target}")
            return f"%{name}"
        if source_bits and target_bits:
            operation = "trunc" if source_bits > target_bits else "zext"
            lines.append(f"  %{name} = {operation} {source} {value} to {target}")
            return f"%{name}"
        if source_bits and target in ("float", "double"):
            lines.append(f"  %{name} = uitofp {source} {value} to {target}")
            return f"%{name}"
        if source in ("float", "double") and target_bits:
            lines.append(f"  %{name} = fptoui {source} {value} to {target}")
            return f"%{name}"
        if source == "float" and target == "double":
            lines.append(f"  %{name} = fpext float {value} to double")
            return f"%{name}"
        if source == "double" and target == "float":
            lines.append(f"  %{name} = fptrunc double {value} to float")
            return f"%{name}"
        raise ParseError(f"{self.unit.name}: cannot convert {source} to {target}")

    # -- calls -------------------------------------------------------------

    def render_call(self, lines, name, arguments, wanted, annotated=None):
        """Render a call, returning the LLVM value of its result."""
        value, _aggregate = self.render_call_value(lines, name, arguments, wanted,
                                                   annotated)
        return value

    def declared_result(self, name, declared):
        """The LLVM return type of a call to a function in this closure."""
        if declared is None:
            return None
        letter = declared[1]
        if not letter:
            return "void"
        size = aggregate_bytes(letter, self.sizes)
        return self.aggregate_abi(letter) if size is not None else letter_type(letter)

    def render_call_value(self, lines, name, arguments, wanted, annotated=None,
                          result_pointer=None):
        """Render a call, returning its value and the aggregate type it holds."""
        if is_indirect(name):
            return self.render_indirect_call(lines, name, arguments, wanted,
                                             annotated, result_pointer)
        if name in C_HELPERS:
            helper, parameters, result = C_HELPERS[name]
            if helper == "intrinsic-memset":
                if len(arguments) != 3:
                    raise ParseError(f"{self.unit.name}: memset takes three arguments")
                self.declare_intrinsic("llvm.memset.p0.i64",
                                       ["ptr", "i8", "i64", "i1"], "void")
                address = self.render(lines, arguments[0], "int", 64, "i64")
                pointer = self.address(lines, address)
                fill = self.render(lines, arguments[1], "int", 8, "i8")
                length = self.render(lines, arguments[2], "int", 64, "i64")
                lines.append(f"  call void @llvm.memset.p0.i64(ptr {pointer}, "
                             f"i8 {fill}, i64 {length}, i1 false)"
                             f"{self.alias_of(arguments[0])}")
                return "0", None
        if name == self.function.name:
            self.declare_undefined(name)
        declared = self.signatures.get(name)
        exact_runtime = runtime_signature(name)
        if exact_runtime is not None:
            parameters, result = exact_runtime
            self.declarations.setdefault(name, (tuple(parameters), result, "external"))
        elif declared is not None:
            parameters = self.parameter_abis(declared[0], declared[1])
            result = self.declared_result(name, declared)
            # A sidecar entry describes a unit of this same build, so this module
            # still needs its own declaration for the symbol: the type comes from
            # the sidecar, and the definition comes from the link.
            self.declarations.setdefault(name, (tuple(parameters), result, "external"))
        else:
            # A symbol the closure did not describe is declared here: it is either
            # a C runtime function or a guest unit this build compiled before its
            # signature reached the sidecar.  Either way the emitter's own
            # convention (`i64` for every pointer-width value) is what both sides
            # of this program were built with, and no `declare` is emitted for a
            # symbol the linker will find as a definition.
            parameters, result = self.infer_external(name, arguments, wanted,
                                                      annotated)
        aggregate = result if hasattr(result, "storage") else None
        if len(parameters) != len(arguments):
            raise ParseError(f"{self.unit.name}: call to ${name} passes "
                             f"{len(arguments)} arguments but ${name} takes "
                             f"{len(parameters)}")
        rendered = self.render_arguments(lines, arguments, parameters)
        if hasattr(result, "storage") and result.indirect:
            destination = result_pointer or self.fresh("aggret")
            if result_pointer is None:
                lines.append(f"  %{destination} = alloca {result.storage}, align {result.alignment}")
            rendered.insert(0, f"ptr sret({result.storage}) align {result.alignment} %{destination}")
            lines.append(f"  call void @{name}({', '.join(rendered)})")
            return f"%{destination}", result
        if result == "void":
            lines.append(f"  call void @{name}({', '.join(rendered)})")
            return "0", None
        value = self.fresh("call")
        result_type = result.value if hasattr(result, "storage") else result
        lines.append(f"  %{value} = call {result_type} @{name}({', '.join(rendered)})")
        if result_type == "ptr":
            address = self.fresh("calladdr")
            lines.append(f"  %{address} = ptrtoint ptr %{value} to i64")
            return f"%{address}", aggregate
        return f"%{value}", aggregate

    def render_indirect_call(self, lines, target, arguments, wanted, annotated=None,
                             result_pointer=None):
        """A call through a function value computed at run time.

        The callee is a pointer-width integer holding the function's address, and
        the call site spells its arguments exactly as a direct call does: `%ctx`
        first, every value pointer-width, and an aggregate result named on the
        destination.  The shapes therefore come from the same call-site evidence
        an unknown direct symbol uses, and the callee's own unit compiled the
        definition from that same convention.  ABI classification still runs
        through `parameter_abis`, because an aggregate argument or result changes
        the register assignment of everything around it.
        """
        callee = self.render(lines, CalleeTemp(target.name), "int", 64, "i64")
        pointer = self.address(lines, callee)
        parameters, result = self.call_site_signature(arguments, wanted, annotated)
        if len(parameters) != len(arguments):
            raise ParseError(f"{self.unit.name}: indirect call passes "
                             f"{len(arguments)} arguments but its site declares "
                             f"{len(parameters)}")
        rendered = self.render_arguments(lines, arguments, parameters)
        aggregate = result if hasattr(result, "storage") else None
        if hasattr(result, "storage") and result.indirect:
            destination = result_pointer or self.fresh("aggret")
            if result_pointer is None:
                lines.append(f"  %{destination} = alloca {result.storage}, align {result.alignment}")
            rendered.insert(0, f"ptr sret({result.storage}) align {result.alignment} %{destination}")
            lines.append(f"  call void {pointer}({', '.join(rendered)})")
            return f"%{destination}", result
        if result == "void":
            lines.append(f"  call void {pointer}({', '.join(rendered)})")
            return "0", None
        value = self.fresh("call")
        result_type = result.value if hasattr(result, "storage") else result
        lines.append(f"  %{value} = call {result_type} {pointer}({', '.join(rendered)})")
        if result_type == "ptr":
            address = self.fresh("calladdr")
            lines.append(f"  %{address} = ptrtoint ptr %{value} to i64")
            return f"%{address}", aggregate
        return f"%{value}", aggregate

    def render_arguments(self, lines, arguments, parameters):
        """Render every argument of a call in the shape its ABI classified."""
        rendered = []
        for argument, parameter in zip(arguments, parameters):
            if hasattr(parameter, "storage"):
                address = self.render(lines, argument, "int", 64, "i64")
                pointer = self.address(lines, address)
                if parameter.indirect:
                    rendered.append(f"ptr byval({parameter.storage}) align {parameter.alignment} {pointer}")
                else:
                    loaded = self.fresh("arg")
                    lines.append(f"  %{loaded} = load {parameter.value}, ptr {pointer}, align {parameter.alignment}")
                    rendered.append(f"{parameter.value} %{loaded}")
                continue
            if parameter == "ptr":
                integer = self.render(lines, argument, "int", 64, "i64")
                rendered.append(f"ptr {self.address(lines, integer)}")
                continue
            kind = "float" if parameter in ("float", "double") else "int"
            width = bit_width(parameter) or (64 if parameter == "double" else 32)
            value = self.render(lines, argument, kind, width, parameter)
            rendered.append(f"{parameter} {value}")
        return rendered

    def call_site_signature(self, arguments, wanted, annotated=None):
        """The signature a call site's own operand spellings imply.

        Every argument carries its own type prefix in the IL, and the destination
        carries the result's aggregate name, so a callee with no sidecar entry --
        an unknown C symbol, or a function value whose target is only known at run
        time -- is classified from exactly the evidence the frontend wrote.
        """
        letters = []
        for argument in arguments:
            if is_temporary(argument) and argument.kind == "temp":
                letter = getattr(argument, "qbe_type", None)
                if letter is None:
                    kind, width = self.type_of(argument.name)
                    letter = letter_for(kind, width) if kind != "aggregate" else width
                letters.append(letter)
            elif is_constant(argument):
                letters.append(argument.qbe_type if argument.qbe_type in BASE_TYPES else "l")
            elif is_call(argument):
                letters.append(argument.qbe_type or "l")
            else:
                letters.append("l")
        parameters = self.parameter_abis(letters, annotated)
        size = aggregate_bytes(annotated, self.sizes)
        result = self.aggregate_abi(annotated) if size is not None else (wanted or "void")
        return parameters, result

    def infer_external(self, name, arguments, wanted, annotated=None):
        """The signature of a symbol this unit has no sidecar entry for.

        The call site itself carries what is needed: every argument has its own
        type prefix, and the destination is annotated with the result's type name,
        which is how an aggregate result is recognised as one.
        """
        parameters, result = self.call_site_signature(arguments, wanted, annotated)
        if ((name.startswith("myl_native_") or name.startswith("myl_qbe_")) and
                runtime_signature(name) is None):
            raise ParseError(f"{self.unit.name}: runtime helper ${name} has no checked C signature")
        signature = (tuple(parameters), result, "external")
        previous = self.declarations.get(name)
        if previous is not None and previous[:2] != signature[:2]:
            raise ParseError(f"{self.unit.name}: external ${name} is called with "
                             f"conflicting signatures {previous[:2]} and {signature[:2]}")
        self.declarations[name] = signature
        return parameters, result

    def declare_undefined(self, name):
        """Remember a function this unit defines, so no `declare` is emitted.

        A unit may call a helper it defines itself (a local `function`, or the
        module entry calling `main`).  LLVM rejects a declaration that a later
        definition contradicts, so the call site reaches the definition without
        one.
        """
        self.declarations.setdefault(name, (None, None, "undefined"))

    def declare_intrinsic(self, name, parameters, result):
        """Declare an LLVM intrinsic once."""
        self.declarations.setdefault(name, (tuple(parameters), result, "intrinsic"))

    # -- instructions ------------------------------------------------------

    #: Opcodes that end a block.
    TERMINATORS = ("ret", "jmp", "jnz", "hlt")

    def collect_phi_stores(self):
        """Every phi input, keyed by the predecessor block that supplies it.

        A QBE phi names one input per predecessor, and this IL is not SSA, so the
        phi is lowered where its value is produced: on the edge out of each
        predecessor.  The input is often not a temporary the predecessor already
        stored — the frontend's float normalisation passes the canonical NaN bit
        pattern as a literal on its `nan` edge — so the phi cannot be dropped the
        way an SSA form would let this emitter drop it, and it cannot be resolved
        with a `select` either: a select placed in the merge block has no way to
        ask which edge was taken, while the edge store is unconditional and known.
        """
        stores = {}
        known = {block.label for block in self.function.blocks}
        for block in self.function.blocks:
            for instruction in block.instructions:
                if instruction.opcode != "phi":
                    continue
                for predecessor, operand in instruction.extra:
                    if predecessor not in known:
                        raise ParseError(
                            f"{self.unit.name}:{instruction.line}: phi in "
                            f"{block.label} names `{predecessor}`, which is not a "
                            f"block of ${self.function.name}")
                    stores.setdefault(predecessor, []).append((instruction,
                                                               operand))
        return stores

    def emit_phi_stores(self, block):
        """Store the phi inputs this block hands to its successors."""
        pending = self.phi_stores.get(block.label)
        if not pending:
            return []
        lines = []
        for instruction, operand in pending:
            name = instruction.dest.name
            kind, width = self.type_of(name)
            llvm = self.llvm_of(name)
            value = self.render(lines, operand, kind, width, llvm)
            self.store_slot(lines, name, value)
        return lines

    def emit_block(self, block, following=None):
        """Render one QBE block, including an implicit fall-through.

        QBE does not require a block to end with a branch: a block that runs off
        its end continues at the next one, which the emitted IL does rely on.  The
        fall-through is therefore made explicit here, because LLVM does require
        every block to end with a terminator.
        """
        lines = []
        terminator = block.terminator()
        explicit = (terminator is not None
                    and terminator.opcode in self.TERMINATORS)
        body = block.instructions[:-1] if explicit else block.instructions
        self.block_positions, self.block_definitions = {}, {}
        for position, instruction in enumerate(body):
            self.position = position
            lines.extend(self.emit_instruction(instruction, block))
            if instruction.dest is not None:
                self.block_positions[instruction.dest.name] = position
                self.block_definitions[instruction.dest.name] = instruction
        self.position = len(body)
        # A phi input belongs on the edge out of the block that supplies it, so
        # the stores go after the block's own instructions and before its branch.
        lines.extend(self.emit_phi_stores(block))
        if explicit:
            lines.extend(self.emit_instruction(terminator, block))
        elif following is None:
            lines.append("  unreachable")
        else:
            lines.append(f"  br label %{self.label(following)}")
        return lines

    def emit_instruction(self, instruction, block=None):
        """Render one instruction as zero or more LLVM lines."""
        handler = getattr(self, "on_" + instruction.opcode, None)
        if handler is not None:
            if instruction.opcode == "phi":
                return handler(instruction, block)
            if instruction.opcode == "call":
                return self.frame_map.position_calls(handler(instruction))
            return handler(instruction)
        opcode = instruction.opcode
        if opcode in COMPARISONS:
            return self.on_compare(instruction)
        if opcode in CONVERSIONS:
            return self.on_conversion(instruction)
        if opcode in LOADS:
            return self.on_load(instruction)
        if opcode in STORES:
            return self.on_store(instruction)
        if opcode in INTEGER_OPS:
            return self.on_arithmetic(instruction)
        raise ParseError(f"{self.unit.name}:{instruction.line}: unsupported opcode "
                         f"`{opcode}`")

    def define(self, instruction, lines, value):
        """Store one instruction's result into its destination slot."""
        self.store_slot(lines, instruction.dest.name, value)
        return lines

    # -- memory ------------------------------------------------------------

    def on_alloc4(self, instruction):
        """`%t =l alloc4 size` — a 4-byte-aligned stack allocation."""
        return self.on_alloc(instruction, 4)

    def on_alloc8(self, instruction):
        """`%t =l alloc8 size` — an 8-byte-aligned stack allocation."""
        return self.on_alloc(instruction, 8)

    def on_alloc16(self, instruction):
        """`%t =l alloc16 size` — a 16-byte-aligned stack allocation."""
        return self.on_alloc(instruction, 16)

    def on_alloc(self, instruction, alignment):
        """One stack allocation, kept where the source put it."""
        lines = []
        size = self.render(lines, instruction.args[0], "int", 64, "i64")
        raw = self.fresh("mem")
        address = self.fresh("ptr")
        lines.append(f"  %{raw} = alloca i8, i64 {size}, align {alignment}")
        lines.append(f"  %{address} = ptrtoint ptr %{raw} to i64")
        return self.define(instruction, lines, f"%{address}")

    def on_blit(self, instruction):
        """`blit src, dst, size` — a byte copy of possibly overlapping ranges."""
        self.declare_intrinsic("llvm.memmove.p0.p0.i64", ["ptr", "ptr", "i64", "i1"],
                               "void")
        lines = []
        source = self.render(lines, instruction.args[0], "int", 64, "i64")
        destination = self.render(lines, instruction.args[1], "int", 64, "i64")
        size = self.render(lines, instruction.args[2], "int", 64, "i64")
        source_pointer = self.address(lines, source)
        destination_pointer = self.address(lines, destination)
        lines.append(f"  call void @llvm.memmove.p0.p0.i64(ptr {destination_pointer}, "
                     f"ptr {source_pointer}, i64 {size}, i1 false)"
                     f"{self.alias_of_both(instruction.args[0], instruction.args[1])}")
        return lines

    def on_load(self, instruction):
        """One load, signed or unsigned, widened to the destination's width."""
        bits, signed = LOADS[instruction.opcode]
        llvm = self.llvm_of(instruction.dest.name)
        lines = []
        pointer = self.access_pointer(lines, instruction.args[0])
        loaded = self.fresh("ld")
        loaded_type = ("double" if instruction.opcode == "loadd"
                       else "float" if instruction.opcode == "loads" else f"i{bits}")
        lines.append(f"  %{loaded} = load {loaded_type}, ptr {pointer}, "
                     f"align {max(1, bits // 8)}{self.alias_of(instruction.args[0])}")
        value = f"%{loaded}"
        if loaded_type in ("float", "double"):
            pass
        elif bit_width(llvm) and bits < bit_width(llvm):
            widened = self.fresh("ext")
            operation = "sext" if signed else "zext"
            lines.append(f"  %{widened} = {operation} {loaded_type} %{loaded} to {llvm}")
            value = f"%{widened}"
        return self.define(instruction, lines, value)

    def on_store(self, instruction):
        """One store of the low `bits` of a value.

        The opcode names the width and not the interpretation: the frontend stores
        a float field with `storel`, so the value is rendered at that width and a
        same-width reinterpretation is a `bitcast` (`widen`).
        """
        bits = STORES[instruction.opcode]
        stored_type = ("double" if instruction.opcode == "stored"
                       else "float" if instruction.opcode == "stores" else f"i{bits}")
        kind = "float" if stored_type in ("float", "double") else "int"
        lines = []
        source = instruction.args[0]
        source_llvm = self.llvm_of(source.name) if is_temporary(source) and \
            source.kind == "temp" else stored_type
        value = self.render(lines, source, kind if stored_type in ("float", "double")
                            else "int", bits, source_llvm)
        if source_llvm != stored_type:
            value = self.widen(lines, value, source_llvm, stored_type)
        pointer = self.access_pointer(lines, instruction.args[1])
        lines.append(f"  store {stored_type} {value}, ptr {pointer}, "
                     f"align {max(1, bits // 8)}{self.alias_of(instruction.args[1])}")
        return lines

    # -- values ------------------------------------------------------------

    def on_copy(self, instruction):
        """`%t =T copy %v` — a value move, including an aggregate address."""
        llvm = self.llvm_of(instruction.dest.name)
        kind = self.type_of(instruction.dest.name)[0]
        width = bit_width(llvm) or (64 if llvm == "double" else 32)
        lines = []
        value = self.render(lines, instruction.args[0], kind, width, llvm)
        return self.define(instruction, lines, value)

    def on_arithmetic(self, instruction):
        """Integer or floating arithmetic, whichever the destination carries."""
        name = instruction.dest.name
        kind, width = self.type_of(name)
        llvm = self.llvm_of(name)
        lines = []
        if kind == "float":
            operation = FLOAT_OPS.get(instruction.opcode)
            if operation is None:
                raise ParseError(f"{self.unit.name}:{instruction.line}: "
                                 f"`{instruction.opcode}` is not defined on floats")
            left = self.render(lines, instruction.args[0], "float", width, llvm)
            right = self.render(lines, instruction.args[1], "float", width, llvm)
        else:
            left = self.render(lines, instruction.args[0], "int", width, llvm)
            right = self.render(lines, instruction.args[1], "int", width, llvm)
            operation = INTEGER_OPS[instruction.opcode]
        result = self.fresh("op")
        pointer_index = None
        if instruction.opcode == "add" and llvm == "i64":
            for index, argument in enumerate(instruction.args):
                if ((is_temporary(argument) and
                     (argument.kind == "global" or argument.name in self.pointer_values))):
                    pointer_index = index
                    break
        stems = self.overflow.producers.get(id(instruction))
        if pointer_index is not None:
            base, offset = (left, right) if pointer_index == 0 else (right, left)
            base_pointer = self.address(lines, base)
            gep = self.fresh("gep")
            lines.append(f"  %{gep} = getelementptr i8, ptr {base_pointer}, i64 {offset}")
            lines.append(f"  %{result} = ptrtoint ptr %{gep} to i64")
        elif stems and kind == "int" and llvm == "i64":
            self.checked_arithmetic(instruction, stems, lines, (left, right, result))
        else:
            lines.append(f"  %{result} = {operation} {llvm} {left}, {right}")
        return self.define(instruction, lines, f"%{result}")

    def checked_arithmetic(self, instruction, stems, lines, values):
        """Compute a checked `add`/`sub`/`mul` with its overflow intrinsics.

        LLVM-OVERFLOW-INTRINSIC-1: the first intrinsic's wrapped value is the
        instruction's result — the plain operation's value, bit for bit — and
        each stem's overflow bit waits for the flag `OverflowChecks` matched it
        to, which `on_compare` stores in place of the frontend's formula.
        """
        left, right, result = values
        for stem in stems:
            intrinsic = f"llvm.{stem}.with.overflow.i64"
            self.declare_intrinsic(intrinsic, ["i64", "i64"], "{ i64, i1 }")
            pair = self.fresh("ovpair")
            bit = self.fresh("ov")
            lines.append(f"  %{pair} = call {{ i64, i1 }} @{intrinsic}(i64 {left}, i64 {right})")
            if stem == stems[0]:
                lines.append(f"  %{result} = extractvalue {{ i64, i1 }} %{pair}, 0")
            lines.append(f"  %{bit} = extractvalue {{ i64, i1 }} %{pair}, 1")
            self.overflow_bits[(id(instruction), stem)] = f"%{bit}"

    def on_compare(self, instruction):
        """One comparison, whose result is an integer holding 0 or 1."""
        predicate, kind, operand_llvm = COMPARISONS[instruction.opcode]
        llvm = self.llvm_of(instruction.dest.name)
        width = bit_width(operand_llvm) or (64 if operand_llvm == "double" else 32)
        lines = []
        matched = self.overflow.flags.get(id(instruction))
        if matched is not None and (matched in self.overflow_bits):
            # LLVM-OVERFLOW-INTRINSIC-1: this flag is exactly the overflow bit
            # of an intrinsic its arithmetic instruction already computed.
            return self.define(instruction, lines,
                               self.widen(lines, self.overflow_bits[matched], "i1", llvm))
        if instruction is self.stack_guard_compare:
            self.declare_intrinsic("llvm.stacksave", [], "ptr")
            stack = self.fresh("stack")
            left_name = self.fresh("stackaddr")
            lines.append(f"  %{stack} = call ptr @llvm.stacksave()")
            lines.append(f"  %{left_name} = ptrtoint ptr %{stack} to i64")
            left = f"%{left_name}"
        else:
            left = self.render(lines, instruction.args[0], kind, width, operand_llvm)
        right = self.render(lines, instruction.args[1], kind, width, operand_llvm)
        operation = "fcmp" if kind == "float" else "icmp"
        compared = self.fresh("cmp")
        lines.append(f"  %{compared} = {operation} {predicate} {operand_llvm} "
                     f"{left}, {right}")
        # QBE comparisons produce an integer of the requested width, never an i1.
        return self.define(instruction, lines,
                           self.widen(lines, f"%{compared}", "i1", llvm))

    def on_neg(self, instruction):
        """`neg` on an integer or a float."""
        name = instruction.dest.name
        kind, width = self.type_of(name)
        llvm = self.llvm_of(name)
        lines = []
        value = self.render(lines, instruction.args[0], kind, width, llvm)
        result = self.fresh("neg")
        if kind == "float":
            lines.append(f"  %{result} = fneg {llvm} {value}")
        else:
            lines.append(f"  %{result} = sub {llvm} 0, {value}")
        return self.define(instruction, lines, f"%{result}")

    def on_not(self, instruction):
        """`not` on an integer."""
        llvm = self.llvm_of(instruction.dest.name)
        lines = []
        value = self.render(lines, instruction.args[0], "int", bit_width(llvm), llvm)
        result = self.fresh("not")
        lines.append(f"  %{result} = xor {llvm} {value}, -1")
        return self.define(instruction, lines, f"%{result}")

    def on_conversion(self, instruction):
        """One conversion between widths or bit patterns."""
        opcode = instruction.opcode
        kind, source_letter, _target = CONVERSIONS[opcode]
        llvm = self.llvm_of(instruction.dest.name)
        lines = []
        if kind == "ext":
            source_width = EXT_WIDTH[opcode]
            source_llvm = f"i{source_width}"
            value = self.render(lines, instruction.args[0], "int", source_width,
                                source_llvm)
            result = self.fresh("ext")
            operation = "sext" if opcode in ("extsw", "extsh", "extsb") else "zext"
            lines.append(f"  %{result} = {operation} {source_llvm} {value} to {llvm}")
            return self.define(instruction, lines, f"%{result}")
        if kind == "bitcast":
            # `cast` reinterprets the same 64 bits as the destination's type: the
            # IL's "integer" doubles are a bit pattern, so the store into the slot
            # has to be the destination type, not the source's.
            target_llvm = llvm_scalar(*self.types.of(instruction.dest.name))
            source_llvm = self.llvm_of(instruction.args[0].name)
            source_width = bit_width(source_llvm) or 64
            value = self.render(lines, instruction.args[0], "int", source_width,
                                source_llvm)
            result = self.fresh("cast")
            lines.append(f"  %{result} = bitcast {source_llvm} {value} to {target_llvm}")
            slot = self.slot(instruction.dest.name)
            lines.append(f"  store {target_llvm} %{result}, ptr %{slot.pointer}, "
                         f"align {min(slot.size, 8)}")
            return lines
        # The remaining conversions are the float/float and float/integer pairs,
        # which `widen` already knows how to express.
        source_kind = "float" if source_letter in ("s", "d") else "int"
        source_llvm = letter_type(source_letter)
        source_width = bit_width(source_llvm) or (64 if source_llvm == "double" else 32)
        value = self.render(lines, instruction.args[0], source_kind, source_width,
                            source_llvm)
        converted = self.widen(lines, value, source_llvm, llvm)
        return self.define(instruction, lines, converted)

    # -- control -----------------------------------------------------------

    def on_ret(self, instruction):
        """`ret` with the function's own result type."""
        result = self.function.result
        if result is None:
            return ["  ret void"]
        if self.aggregate_slots.get("__result__") is None:
            size = aggregate_bytes(result, self.sizes)
            if size is not None:
                return self.ret_aggregate(instruction, size)
        llvm = letter_type(result)
        if not instruction.args:
            return [f"  ret {llvm} 0"]
        lines = []
        kind = "float" if llvm in ("float", "double") else "int"
        width = bit_width(llvm) or (64 if llvm == "double" else 32)
        value = self.render(lines, instruction.args[0], kind, width, llvm)
        lines.append(f"  ret {llvm} {value}")
        return lines

    def ret_aggregate(self, instruction, size):
        """Return an aggregate by value, loaded from the address the IL names."""
        abi = self.aggregate_abi(self.function.result)
        llvm = abi.storage
        if abi.indirect:
            if instruction.args:
                lines = []
                address = self.render(lines, instruction.args[0], "int", 64, "i64")
                pointer = self.address(lines, address)
                self.declare_intrinsic("llvm.memmove.p0.p0.i64",
                                       ["ptr", "ptr", "i64", "i1"], "void")
                lines.append(f"  call void @llvm.memmove.p0.p0.i64(ptr %p_sret, "
                             f"ptr {pointer}, i64 {size}, i1 false)")
                lines.append("  ret void")
                return lines
            lines = []
            self.declare_intrinsic("llvm.memset.p0.i64", ["ptr", "i8", "i64", "i1"], "void")
            lines.append(f"  call void @llvm.memset.p0.i64(ptr %p_sret, i8 0, i64 {size}, i1 false)")
            lines.append("  ret void")
            return lines
        if not instruction.args:
            return [f"  ret {abi.value} zeroinitializer"]
        lines = []
        address = self.render(lines, instruction.args[0], "int", 64, "i64")
        pointer = self.address(lines, address)
        value = self.fresh("ret")
        lines.append(f"  %{value} = load {abi.value}, ptr {pointer}, align {abi.alignment}")
        lines.append(f"  ret {abi.value} %{value}")
        return lines

    def on_jmp(self, instruction):
        """An unconditional branch."""
        return [f"  br label %{self.label(instruction.extra)}"]

    def on_jnz(self, instruction):
        """A conditional branch on a non-zero integer."""
        lines = []
        condition = self.render(lines, instruction.args[0], "int", 64, "i64")
        tested = self.fresh("cond")
        lines.append(f"  %{tested} = icmp ne i64 {condition}, 0")
        lines.append(f"  br i1 %{tested}, label %{self.label(instruction.extra[0])}, "
                     f"label %{self.label(instruction.extra[1])}")
        return lines

    def on_call(self, instruction):
        """A call whose result is the instruction's destination."""
        lines = []
        wanted = (self.llvm_of(instruction.dest.name) if instruction.dest else None)
        # The destination's own annotation is the authority on an aggregate
        # result: `%v =:t43894... call $f(...)` says the callee returns that
        # aggregate even when this unit has no signature for `$f` yet.  Without
        # it a call would be declared `i64` while the callee returns a struct by
        # value, and the callee's hidden result pointer would shift every
        # argument one register — the crash this guards against.
        reserved = self.call_result_buffers.get(id(instruction))
        result_pointer = reserved[0] if reserved is not None else None
        value, aggregate = self.render_call_value(lines, instruction.extra,
                                                 instruction.args, wanted,
                                                 instruction.qbe_type,
                                                 result_pointer)
        if instruction.dest is None:
            return lines
        if aggregate is not None:
            # An aggregate result arrives as a value whose address is the returned
            # storage; the IL keeps that address as the temporary's value.
            if aggregate.indirect:
                slot = value.lstrip("%")
            else:
                slot = result_pointer or self.fresh("aggret")
                if result_pointer is None:
                    lines.append(f"  %{slot} = alloca {aggregate.storage}, align {aggregate.alignment}")
                lines.append(f"  store {aggregate.value} {value}, ptr %{slot}, align {aggregate.alignment}")
            address = self.fresh("addr")
            lines.append(f"  %{address} = ptrtoint ptr %{slot} to i64")
            return self.define(instruction, lines, f"%{address}")
        llvm = self.llvm_of(instruction.dest.name)
        if wanted != llvm:
            value = self.widen(lines, value, wanted, llvm)
        return self.define(instruction, lines, value)

    def on_phi(self, instruction, block=None):
        """A QBE phi, whose value its predecessors stored on the way out.

        `collect_phi_stores` lowers every phi input at the end of the block that
        supplies it, so by the time control reaches the merge block the
        destination's slot already holds the input of the edge that was taken and
        the phi itself has nothing left to do.
        """
        return []

    def declaration_attributes(self, name):
        """The function attributes one runtime declaration carries.

        A `myl_qbe_fail_*` helper runs only on a path that has already failed,
        so it is `cold` wherever it is called.  It is also `noreturn` in this
        module when every call to it is immediately followed by `hlt`
        (QBE-NORETURN-1): the frontend emits that only for a build whose entry
        armed the runtime's non-local exit, where the helper leaves through it.
        A unit that keeps the sticky `jmp @failure` after any call says the
        helper may return there, and its declaration says nothing more.
        """
        attributes = runtime_attributes.get(name, "")
        if not name.startswith(FAIL_HELPER_PREFIX):
            return attributes
        extra = "noreturn cold" if name in self.halting_helpers() else "cold"
        return f"{attributes} {extra}" if attributes else extra

    def halting_helpers(self):
        """Fail helpers whose every call in this unit is followed by `hlt`."""
        halting, returning = set(), set()
        for block in self.function.blocks:
            for index, instruction in enumerate(block.instructions):
                if instruction.opcode != "call" or not isinstance(instruction.extra, str):
                    continue
                if not instruction.extra.startswith(FAIL_HELPER_PREFIX):
                    continue
                following = block.instructions[index + 1:index + 2]
                if following and following[0].opcode == "hlt":
                    halting.add(instruction.extra)
                else:
                    returning.add(instruction.extra)
        return halting - returning

    def on_hlt(self, instruction):
        """`hlt`: the end of a failure path whose fail helper never returns."""
        return ["  unreachable"]

    def on_dbgloc(self, instruction):
        """`dbgloc LINE[, COLUMN]`: the position the following calls report."""
        self.frame_map.location = instruction.extra
        return []

    # -- module ------------------------------------------------------------

    def emit(self):
        """Render the whole module."""
        out = ['target triple = "x86_64-unknown-linux-gnu"', ""]
        out.extend(self.emit_function())
        if self.globals:
            out.append("")
            for name in sorted(self.globals):
                if name in self.declarations:
                    # `extern $f` takes a function's address and `call $f` names
                    # the same symbol: LLVM allows one kind of name per symbol, and
                    # the declaration is the one that carries the call.  A second
                    # `@f = external global` would be a redefinition.
                    continue
                declared = self.signatures.get(name)
                exact_runtime = runtime_signature(name)
                if declared is not None or exact_runtime is not None:
                    # A callable whose address is taken but which this unit never
                    # calls is still a function, not storage: a lambda passed as a
                    # callback is defined by its own unit, and an `external global`
                    # here would leave the LTO link with an undefined symbol.
                    if exact_runtime is not None:
                        parameters, result = exact_runtime
                    else:
                        parameters = self.parameter_abis(declared[0], declared[1])
                        result = self.declared_result(name, declared)
                    self.declarations.setdefault(name, (tuple(parameters), result, "external"))
                    continue
                out.append(f"@{name} = external global {self.globals[name]}, align 8")
        declarations = [(name, entry) for name, entry in sorted(self.declarations.items())
                        if entry[2] != "undefined"]
        if declarations:
            out.append("")
            for name, (parameters, result, _origin) in declarations:
                rendered = []
                for parameter in parameters:
                    if hasattr(parameter, "storage"):
                        rendered.append((f"ptr byval({parameter.storage}) align {parameter.alignment}"
                                         if parameter.indirect else parameter.value))
                    else:
                        rendered.append(parameter)
                if hasattr(result, "storage") and result.indirect:
                    rendered.insert(0, f"ptr sret({result.storage}) align {result.alignment}")
                    result_type = "void"
                else:
                    result_type = result.value if hasattr(result, "storage") else result
                attributes = self.declaration_attributes(name)
                suffix = " " + attributes if attributes else ""
                out.append(f"declare {result_type} @{name}({', '.join(rendered)}){suffix}")
        if self.attributes:
            out.append("")
            out.append("attributes #0 = { " + " ".join(sorted(self.attributes)) + " }")
        if self.alias_metadata:
            out.append(ALIAS_METADATA.rstrip("\n"))
            out.extend(self.element_metadata())
        out.extend(self.frame_map.metadata())
        return "\n".join(out) + "\n"

    def parameter_shapes(self):
        """The LLVM parameter list.

        Scalar values retain their QBE machine type.  Aggregates follow AMD64
        SysV: one or two INTEGER eightbytes are coerced to register values, while
        larger arguments use a `byval` pointer whose pointee is callee-owned.
        """
        out = []
        result_size = aggregate_bytes(self.function.result, self.sizes)
        result_abi = self.aggregate_abi(self.function.result)
        if result_abi is not None and result_abi.indirect:
            out.append(f"ptr sret({result_abi.storage}) align {result_abi.alignment} %p_sret")
        classified = self.parameter_abis(
            [letter for letter, _ in self.function.parameters], self.function.result)
        for (letter, temp), shape in zip(self.function.parameters, classified):
            size = aggregate_bytes(letter, self.sizes)
            if size is None:
                out.append(f"{letter_type(letter)} %p_{temp.name}")
            else:
                abi = shape
                out.append((f"ptr byval({abi.storage}) align {abi.alignment} %p_{temp.name}"
                            if abi.indirect else f"{abi.value} %p_{temp.name}"))
        return out

    def return_type(self):
        """The LLVM return type.

        An aggregate result is returned by value: the IL names the address of the
        returned storage, and LLVM's own ABI already produces one — in registers
        for a two-word aggregate, and through the caller's buffer above that.
        Returning a bare `i64` instead would hand the guest whatever the callee
        happened to leave in `%rax`, which is not an address at all.
        """
        result = self.function.result
        if result is None:
            return "void"
        size = aggregate_bytes(result, self.sizes)
        if size is None:
            return letter_type(result)
        abi = self.aggregate_abi(result)
        return "void" if abi.indirect else abi.value

    def emit_function(self):
        """Render the function: parameters, slots, then the blocks in order."""
        named = list(self.function.parameters)
        rendered = self.parameter_shapes()
        result = self.return_type()
        # QBE gives every emitted unit a global symbol whether or not its own IL
        # says `export`: another unit or the generated C entry point calls it by
        # name.  `dllexport` reproduces that, and `noinline` keeps a local helper
        # from inlining the symbol out of existence.
        target_cpu = target_attribute("MYLANG_QBE_LLVM_TARGET_CPU")
        target_features = target_attribute("MYLANG_QBE_LLVM_TARGET_FEATURES")
        if target_cpu:
            self.attributes.add(f'"target-cpu"="{target_cpu}"')
        if target_features:
            self.attributes.add(f'"target-features"="{target_features}"')
        self.attributes.update(self.frame_map.attributes())
        attributes = " #0" if self.attributes or not self.function.export else ""
        if not self.function.export:
            self.attributes.add("noinline")
        first = self.function.blocks[0].label
        out = [f"define dllexport {result} @{self.function.name}"
               f"({', '.join(rendered)}){attributes}{self.frame_map.subprogram()} {{",
               f"{self.label(first)}:"]
        # The slots live in the entry block, so they dominate every use, and the
        # source's own allocations keep their place in the code below.  They come
        # before the parameter prologue because that prologue writes into them.
        # Every slot must exist before the entry block is written, so the layout is
        # completed here rather than lazily while the prologue is being rendered.
        for _letter, temp in named:
            self.slot(temp.name)
        for block in self.function.blocks:
            for instruction in block.instructions:
                if instruction.dest is not None:
                    self.slot(instruction.dest.name)
        out.extend(self.slot_lines)
        # A parameter arrives as a value (an aggregate arrives as its address) and
        # the IL body reads and writes it as a temporary, so each one is stored
        # into its slot before the first block runs.
        classified = self.parameter_abis([letter for letter, _ in named],
                                         self.function.result)
        for (letter, temp), shape in zip(named, classified):
            slot = self.slot(temp.name)
            size = aggregate_bytes(letter, self.sizes)
            if size is None:
                value = f"%p_{temp.name}"
            else:
                abi = shape
                if abi.indirect:
                    local = f"p_{temp.name}"
                else:
                    local = self.fresh("param")
                    out.append(f"  %{local} = alloca {abi.storage}, align {abi.alignment}")
                    out.append(f"  store {abi.value} %p_{temp.name}, ptr %{local}, align {abi.alignment}")
                address = self.fresh("addr")
                out.append(f"  %{address} = ptrtoint ptr %{local} to i64")
                value = f"%{address}"
            out.append(f"  store {slot.llvm} {value}, ptr %{slot.pointer}, "
                       f"align {min(slot.size, 8)}")
        blocks = self.function.blocks
        for index, block in enumerate(blocks):
            if block.label != first:
                out.append(f"{self.label(block.label)}:")
            following = blocks[index + 1].label if index + 1 < len(blocks) else None
            out.extend(self.emit_block(block, following))
        out.append("}")
        return out


def translate(unit, signatures=None):
    """Translate one parsed QBE unit into LLVM IR text.

    LLVM-STICKY-REDUCTION-1: qualifying loops are versioned first
    (`sticky_loops`), so the Emitter sees ordinary IL either way.
    """
    import sticky_loops
    sticky_loops.version_loops(unit)
    return Emitter(unit, signatures).emit()


if __name__ == "__main__":  # pragma: no cover - the tool is qbe_llvm.py
    sys.exit(0)
