#!/usr/bin/env python3
"""Checked loops with no branch per check (LLVM-STICKY-REDUCTION-1).

A checked `total += x` in a loop reaches LLVM as the add, a compare and a branch
to a trap block every iteration.  The branch is a loop exit whose target calls
the runtime, so LLVM's loop vectorizer refuses the loop, and a conditional
`count += 1` becomes a data-dependent branch.  This pass versions such a loop
before it is translated, on the QBE IL, so every trap keeps its exact position,
message, operands and trace:

* The loop's entry edges go to a **fast copy** of the loop.  In it, an overflow
  check of an ordinary value is **sticky**: the flag is OR-ed into one word and
  the loop goes on with the wrapped result.  An overflow check of a
  **reduction** — a frame cell the loop changes only by `+ x`/`- x` of a 64-bit
  signed value — is dropped, and the loop instead sums the magnitudes of what
  it adds.  Every other check (bounds, casts, division, iteration guards) stays
  a branch, but to the fallback below instead of to its trap.
* At every normal exit of the fast copy the pass **verifies** that no dropped
  check could have fired: the sticky word is zero, and for each reduction
  `|entry value| + sum of |added values| <= 2^63 - 1`, which bounds every
  value the cell takes and every update's result.  Then the fast copy's
  results are exactly the checked loop's results.
* Otherwise, and on every would-be trap, control reaches the **fallback**: it
  restores every frame cell the loop writes to its value at loop entry and
  jumps to the original, untouched loop, which runs from the same state with
  every check in place and traps (or not) exactly as before.

The rewrite is valid only for loops whose fast copy cannot do anything the
original would not have done before its first trap:

* no call, `blit` or phi, and every store writes this activation's own `alloc`
  storage (a *frame cell*), which the fallback can restore;
* no temporary the loop defines is read before the loop defines it, or after
  the loop (the fast copy renames its temporaries);
* a value that may have wrapped (the result of a dropped check's operation, a
  reduction cell, and anything computed from them through temporaries and
  frame cells) never reaches a branch other than a check, a load or store
  address, a shift amount, a divisor, a float-to-integer conversion or a frame
  cell whose address escapes — so the fast copy cannot loop forever, fault,
  compute poison or leak the value because of it.  A check whose wrapped value
  would is kept as a branch instead.

The module works on parsed units (`qbe_llvm.parse_unit`) and changes nothing
when no loop qualifies.  `MYLANG_QBE_LLVM_STICKY=0` turns it off for an A/B
run; `MYLANG_QBE_LLVM_STICKY_LOG=PATH` appends one line per innermost loop with
its verdict.
"""

from __future__ import annotations

import os
import sys

#: Runtime helpers a trap block may call.
FAIL_PREFIX = "myl_qbe_fail_"
#: The helper an overflow check traps through; its second argument is the
#: operation (0 add, 1 sub, 2 mul) and its last the width, which also carries
#: the unsigned-operand bit, so only a width of exactly 64 is a signed `i64`.
OVERFLOW_HELPER = "myl_qbe_fail_overflow_op"

MAX = (1 << 63) - 1
MASK64 = (1 << 64) - 1

#: Operations whose operand may fault or produce poison when it wrapped.
SHIFTS = {"shl", "sar", "shr"}
DIVISIONS = {"div", "rem", "udiv", "urem"}
FLOAT_TO_INT = {"stosi", "dtosi", "stoui", "dtoui"}


class Declined(Exception):
    """A loop the rewrite does not apply to, and why."""


def is_temp(value):
    return getattr(value, "kind", None) == "temp" and hasattr(value, "name")


def constant_value(value):
    """The 64-bit integer a literal operand denotes, or None."""
    if hasattr(value, "text") and hasattr(value, "qbe_type") and value.qbe_type != "extern":
        try:
            return int(value.text, 0) & MASK64
        except ValueError:
            return None
    return None


def signed(value):
    return value - (1 << 64) if value >= 1 << 63 else value


class Cfg:
    """Blocks, explicit successors (fall-through included) and predecessors."""

    def __init__(self, function):
        self.blocks = function.blocks
        self.by_label = {block.label: block for block in self.blocks}
        self.following = {}
        self.successors = {}
        for index, block in enumerate(self.blocks):
            nxt = self.blocks[index + 1].label if index + 1 < len(self.blocks) else None
            self.following[block.label] = nxt
            self.successors[block.label] = self._successors(block, nxt)
        self.predecessors = {block.label: [] for block in self.blocks}
        for label, successors in self.successors.items():
            for successor in successors:
                if successor in self.predecessors:
                    self.predecessors[successor].append(label)

    @staticmethod
    def _successors(block, nxt):
        terminator = block.terminator()
        if terminator is not None and terminator.opcode == "jmp":
            return [terminator.extra]
        if terminator is not None and terminator.opcode == "jnz":
            return list(dict.fromkeys(terminator.extra))
        if terminator is not None and terminator.opcode in ("ret", "hlt"):
            return []
        return [nxt] if nxt else []


def trap_call(block):
    """The fail helper call a trap block makes, or None when it is not one.

    A trap block holds only `dbgloc` lines, one `call $myl_qbe_fail_*` and
    `hlt` (QBE-NORETURN-1): control that reaches it never comes back.
    """
    body = [ins for ins in block.instructions if ins.opcode != "dbgloc"]
    if len(body) != 2 or body[1].opcode != "hlt" or body[0].opcode != "call":
        return None
    name = body[0].extra
    if not isinstance(name, str) or not name.startswith(FAIL_PREFIX):
        return None
    return body[0]


def natural_loops(cfg):
    """Innermost natural loops as (header, body labels in block order)."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from llvm_emit import Dominators
    labels = [block.label for block in cfg.blocks]
    edges = {label: [s for s in cfg.successors[label] if s in cfg.by_label] for label in labels}
    dominators = Dominators(labels[0], edges)
    loops = {}
    for label in labels:
        for successor in edges[label]:
            if dominators.dominates(successor, label):
                body, work = {successor, label}, [label]
                while work:
                    current = work.pop()
                    if current == successor:
                        continue
                    for predecessor in cfg.predecessors[current]:
                        if predecessor not in body:
                            body.add(predecessor)
                            work.append(predecessor)
                loops.setdefault(successor, set()).update(body)
    innermost = []
    for header, body in loops.items():
        if any(other != header and other in body for other in loops):
            continue
        innermost.append((header, [label for label in labels if label in body]))
    innermost.sort(key=lambda item: labels.index(item[0]))
    return innermost


class Frame:
    """This unit's frame cells: `alloc*` storage defined once in the entry block."""

    def __init__(self, function):
        self.function = function
        counts = {}
        definitions = {}
        for block in function.blocks:
            for ins in block.instructions:
                if ins.dest is not None:
                    counts[ins.dest.name] = counts.get(ins.dest.name, 0) + 1
                    definitions[ins.dest.name] = ins
        for _letter, temp in function.parameters:
            counts[temp.name] = counts.get(temp.name, 0) + 1
        self.counts = counts
        self.definitions = definitions
        self.sizes = {}
        entry = function.blocks[0]
        for ins in entry.instructions:
            if ins.dest is not None and ins.opcode.startswith("alloc") and counts[ins.dest.name] == 1:
                size = constant_value(ins.args[0])
                if size is not None:
                    self.sizes[ins.dest.name] = size
        self.escaped = self._escaped()

    def _escaped(self):
        """Frame cells whose address leaves the address position somewhere.

        An address used only to load, store or copy through (directly or by a
        `copy`/offsetting `add` that is itself such an address) cannot be read
        back by any other route; one passed to a call, stored as a value or
        otherwise computed with may be, so a loop that reads memory it cannot
        place might read such a cell."""
        escaped = set()
        for block in self.function.blocks:
            for ins in block.instructions:
                for index, argument in enumerate(ins.args):
                    for nested in getattr(argument, "args", None) or ():
                        cell = self.cell(nested)
                        if cell is not None:
                            escaped.add(cell[0])
                    cell = self.cell(argument)
                    if cell is None:
                        continue
                    if ins.opcode.startswith("load") and index == 0:
                        continue
                    if ins.opcode.startswith("store") and index == 1:
                        continue
                    if ins.opcode == "blit" and index in (0, 1):
                        continue
                    if ins.opcode in ("copy", "add") and ins.dest is not None \
                            and self.cell(ins.dest) is not None:
                        continue
                    escaped.add(cell[0])
                if ins.opcode == "phi":
                    for _label, argument in ins.extra:
                        cell = self.cell(argument)
                        if cell is not None:
                            escaped.add(cell[0])
        return escaped

    def single(self, name):
        return self.counts.get(name) == 1

    def cell(self, address):
        """(alloc, offset) when `address` is frame storage at a fixed offset."""
        offset = 0
        for _depth in range(8):
            if not is_temp(address):
                return None
            name = address.name
            if name in self.sizes:
                return (name, offset)
            if not self.single(name):
                return None
            definition = self.definitions.get(name)
            if definition is None:
                return None
            if definition.opcode == "copy":
                address = definition.args[0]
                continue
            if definition.opcode == "add" and len(definition.args) == 2:
                left, right = definition.args
                if constant_value(right) is not None:
                    offset += signed(constant_value(right))
                    address = left
                    continue
                if constant_value(left) is not None:
                    offset += signed(constant_value(left))
                    address = right
                    continue
            return None
        return None


class Check:
    """One `jnz` whose one target is a trap block."""

    def __init__(self, block, jnz, trap_label, ok_label, call):
        self.block = block
        self.jnz = jnz
        self.trap_label = trap_label
        self.ok_label = ok_label
        self.call = call
        self.trap_on_true = jnz.extra[0] == trap_label

    @property
    def overflow(self):
        return self.call.extra == OVERFLOW_HELPER


class Site:
    """A reduction update: `cell = cell +/- x`, whose check is dropped."""

    def __init__(self, check, cell, operand, constant):
        self.check = check
        self.cell = cell
        self.operand = operand      # the temp holding x (None for a literal)
        self.constant = constant    # |x| when x is a known literal, else None


class Plan:
    """Everything the rewrite of one loop needs."""

    def __init__(self, header, body):
        self.header = header
        self.body = body
        self.sticky = []            # Checks made sticky
        self.sites = []             # Sites
        self.traps = []             # Checks kept as branches to the fallback
        self.cells = set()          # frame allocs the loop stores to
        self.exits = []             # normal exit target labels
        self.defined = []           # temps the loop defines


class Analysis:
    """Decide whether one innermost loop can be versioned, and how."""

    def __init__(self, function, cfg, frame, header, body):
        self.function = function
        self.cfg = cfg
        self.frame = frame
        self.plan = Plan(header, body)
        self.body = set(body)

    def run(self):
        plan = self.plan
        cfg = self.cfg
        if plan.header == cfg.blocks[0].label:
            raise Declined("the loop header is the entry block")
        checks = {}
        for label in plan.body:
            block = cfg.by_label[label]
            for ins in block.instructions:
                self.admit(ins)
            terminator = block.terminator()
            for successor in cfg.successors[label]:
                if successor in self.body:
                    continue
                target = cfg.by_label.get(successor)
                if target is None:
                    raise Declined(f"exit to unknown block {successor}")
                call = trap_call(target)
                if call is not None:
                    if terminator is None or terminator.opcode != "jnz":
                        raise Declined(f"{label} always traps")
                    ok = [t for t in terminator.extra if t != successor]
                    if len(ok) != 1:
                        raise Declined(f"{label} branches to its trap on both edges")
                    checks[label] = Check(block, terminator, successor, ok[0], call)
                    continue
                if any(ins.opcode == "phi" for ins in target.instructions):
                    raise Declined(f"exit target {successor} starts with a phi")
                if successor not in plan.exits:
                    plan.exits.append(successor)
        if not plan.exits:
            raise Declined("no normal exit")
        self.plan_checks = list(checks.values())
        self.find_sites(checks)
        if not plan.sites and not plan.sticky:
            raise Declined("no overflow check to drop")
        self.check_liveness()
        self.check_taint()
        if not plan.sites and not plan.sticky:
            raise Declined("every overflow check decides control or an address")
        if self.function.blocks[-1].terminator() is None or \
                self.function.blocks[-1].terminator().opcode not in ("ret", "jmp", "hlt", "jnz"):
            raise Declined("the last block falls off the function")
        return plan

    def admit(self, ins):
        opcode = ins.opcode
        if opcode == "call":
            raise Declined("the loop makes a call")
        if opcode in ("blit", "phi", "vastart", "vaarg") or opcode.startswith("alloc"):
            raise Declined(f"the loop contains `{opcode}`")
        if opcode.startswith("store"):
            cell = self.frame.cell(ins.args[1])
            if cell is None:
                raise Declined("the loop stores outside its own frame")
            size = self.frame.sizes[cell[0]]
            if size % 4 or size > 256:
                raise Declined(f"frame cell %{cell[0]} of {size} bytes")
            self.plan.cells.add(cell[0])
        if ins.dest is not None:
            if ins.qbe_type is None or ins.qbe_type not in ("w", "l", "s", "d"):
                if ins.opcode not in ("extsw", "extuw", "extsh", "extuh", "extsb", "extub"):
                    raise Declined(f"temporary %{ins.dest.name} has no plain type")
            if ins.dest.name not in self.plan.defined:
                self.plan.defined.append(ins.dest.name)

    def find_sites(self, checks):
        """Sort the loop's checks into reductions, sticky checks and kept ones.

        A check of another kind (bounds, cast, division, iteration) is kept: it
        stays a branch, to the fallback.  An overflow check whose operation
        cannot be found is kept too.  Every other overflow check is sticky
        unless its operation is a reduction update (`reduction_sites`).
        """
        plan = self.plan
        facts = self.facts()
        candidates = []
        for check in checks.values():
            if not check.overflow:
                plan.traps.append(check)
                continue
            args = check.call.args
            operation = constant_value(args[1]) if len(args) == 5 else None
            width = constant_value(args[4]) if len(args) == 5 else None
            op = self.find_operation(check.block, check, operation)
            if op is None:
                plan.traps.append(check)
                continue
            check.operation = op
            check.update = operation in (0, 1) and width == 64
            candidates.append(check)
        sites = self.reduction_sites(candidates, facts)
        for check in candidates:
            mine = [site for site in sites if site.check is check]
            if mine:
                plan.sites.extend(mine)
            else:
                plan.sticky.append(check)

    def facts(self):
        """What each temporary and frame cell holds, on every path (a must-analysis).

        A fact is `("of", cell)` — the value is one the 8-byte frame cell held
        at some point of this execution —, `("result", id)` — it is the result
        of that checked operation —, or `("const", bits)`.  The loop header
        starts with no facts (whatever the cells held before the loop is not
        assumed), facts meet by intersection, and the answer is the facts of
        every operand of every instruction, keyed `(id(instruction), index)`.
        Because `("of", cell)` names *some* value the cell held, a later store
        to the cell does not retract it.
        """
        plan = self.plan
        cfg = self.cfg
        updates = set()
        for check in self.plan_checks:
            if check.overflow:
                args = check.call.args
                if len(args) == 5 and constant_value(args[1]) in (0, 1) and constant_value(args[4]) == 64:
                    op = self.find_operation(check.block, check, constant_value(args[1]))
                    if op is not None:
                        updates.add(id(op))
        state_in = {label: None for label in plan.body}
        state_in[plan.header] = {}
        operand = {}
        for _round in range(64):
            changed = False
            for label in plan.body:
                if state_in[label] is None:
                    continue
                state = dict(state_in[label])
                for ins in cfg.by_label[label].instructions:
                    self.fact_step(ins, state, updates, operand)
                for successor in cfg.successors[label]:
                    if successor not in self.body or successor == plan.header:
                        continue
                    previous = state_in[successor]
                    if previous is None:
                        merged = dict(state)
                    else:
                        merged = {key: previous[key] & state[key] for key in previous
                                  if key in state and previous[key] & state[key]}
                    if merged != previous:
                        state_in[successor] = merged
                        changed = True
            if not changed:
                return operand
        raise Declined("the value analysis did not converge")

    def fact_step(self, ins, state, updates, operand):
        """Apply one instruction to the fact state, recording its operands' facts."""
        empty = frozenset()

        def of(argument):
            if is_temp(argument):
                return state.get(("t", argument.name), empty)
            literal = constant_value(argument)
            return frozenset({("const", literal)}) if literal is not None else empty

        for index, argument in enumerate(ins.args):
            operand[(id(ins), index)] = of(argument)
        opcode = ins.opcode
        if opcode.startswith("store"):
            cell = self.frame.cell(ins.args[1])
            for key in [key for key in state if key[0] == "c" and key[1][0] == cell[0]]:
                del state[key]
            if opcode == "storel" and of(ins.args[0]):
                state[("c", cell)] = of(ins.args[0])
            return
        if ins.dest is None:
            return
        result = empty
        if opcode == "loadl":
            cell = self.frame.cell(ins.args[0])
            if cell is not None:
                result = state.get(("c", cell), empty)
                if cell[1] == 0 and self.frame.sizes.get(cell[0]) == 8:
                    result = result | {("of", cell)}
        elif opcode == "copy":
            result = of(ins.args[0])
        elif id(ins) in updates:
            result = frozenset({("result", id(ins))})
        if result:
            state[("t", ins.dest.name)] = result
        else:
            state.pop(("t", ins.dest.name), None)

    def reduction_sites(self, candidates, facts):
        """The reduction updates among the checked operations.

        An operation `a + x` (or `x + a`, or `a - x`) of a 64-bit signed value
        updates the frame cell R when `a` is a value R held and every store to
        R's allocation in the loop is a `storel` to R of such an operation's
        result.  Then R only ever changes by `+ x` or `- x` from a value it
        held, so by induction every value it takes, and every operation
        result, is at most |R at loop entry| + the sum of |x| over the updates
        run so far — the bound the fast copy verifies at its exits.
        """
        pairs = []
        for check in candidates:
            if not check.update:
                continue
            op = check.operation
            for position in ((0, 1) if op.opcode == "add" else (0,)):
                for fact in facts.get((id(op), position), ()):
                    if fact[0] == "of":
                        pairs.append((check, position, fact[1]))
        stores = {}
        for label in self.plan.body:
            for ins in self.cfg.by_label[label].instructions:
                if ins.opcode.startswith("store"):
                    stores.setdefault(self.frame.cell(ins.args[1])[0], []).append(ins)
        sites = []
        for check, position, cell in pairs:
            if any(site.check is check and site.cell == cell for site in sites):
                continue
            updating = {id(other.operation) for other, _p, other_cell in pairs if other_cell == cell}
            valid = bool(stores.get(cell[0]))
            for store in stores.get(cell[0], ()):
                results = {fact[1] for fact in facts.get((id(store), 0), ()) if fact[0] == "result"}
                if store.opcode != "storel" or self.frame.cell(store.args[1]) != cell \
                        or not results & updating:
                    valid = False
            if not valid:
                continue
            op = check.operation
            other = op.args[1 - position]
            constant = None
            for fact in facts.get((id(op), 1 - position), ()):
                if fact[0] == "const":
                    constant = abs(signed(fact[1]))
            if constant is None and not self.usable_at_check(check, other):
                continue
            site = Site(check, cell, None if constant is not None else other, constant)
            site.operation = op
            sites.append(site)
        return sites

    def usable_at_check(self, check, argument):
        """Whether `argument` still holds the operation's operand at the check."""
        if not is_temp(argument):
            return False
        instructions = check.block.instructions
        start = next(index for index, ins in enumerate(instructions) if ins is check.operation)
        return not any(ins.dest is not None and ins.dest.name == argument.name
                       for ins in instructions[start:])

    def demote(self, check):
        """Keep one check as a branch (to the fallback) instead of dropping it."""
        plan = self.plan
        dropped = [site for site in plan.sites if site.check is check]
        for site in dropped:
            plan.sites.remove(site)
        if check in plan.sticky:
            plan.sticky.remove(check)
        if check not in plan.traps:
            plan.traps.append(check)

    def find_operation(self, block, check, operation):
        """The `add`/`sub`/`mul` whose overflow the check tests."""
        names = {0: "add", 1: "sub", 2: "mul"}
        wanted = names.get(operation)
        left, right = check.call.args[2], check.call.args[3]
        for ins in reversed(block.instructions):
            if ins.opcode == wanted and ins.dest is not None and len(ins.args) == 2 and \
                    all(is_temp(a) and is_temp(b) and a.name == b.name
                        for a, b in zip(ins.args, (left, right))):
                return ins
        return None

    def check_liveness(self):
        """No temporary the loop defines may be read before the loop defines it."""
        defined = set(self.plan.defined)
        for label in self.plan.body:
            seen = set()
            for ins in self.cfg.by_label[label].instructions:
                for argument in ins.args:
                    if is_temp(argument) and argument.name in defined and argument.name not in seen:
                        if not self.defined_before(label, argument.name):
                            raise Declined(f"%{argument.name} is live into the loop")
                if ins.dest is not None:
                    seen.add(ins.dest.name)
        # A temporary the loop defines and the code after it reads keeps the
        # value of the copy that ran; the fast copy renames its temporaries,
        # so such a loop is declined.
        body = self.body
        for block in self.cfg.blocks:
            # A trap block is only ever entered from the original loop, whose
            # temporaries keep their names.
            if block.label in body or trap_call(block) is not None:
                continue
            for ins in block.instructions:
                for argument in ins.args:
                    if is_temp(argument) and argument.name in defined:
                        raise Declined(f"%{argument.name} is live out of the loop")
                if ins.opcode == "jnz" and is_temp(ins.args[0]) and ins.args[0].name in defined:
                    raise Declined(f"%{ins.args[0].name} is live out of the loop")

    def defined_before(self, label, name):
        """Whether every path from the header to `label` defines `name` first."""
        # Walk backwards within the loop, never through the header's back edges.
        header = self.plan.header
        work, seen = [label], {label}
        first = True
        while work:
            current = work.pop()
            if not first or current != label:
                block = self.cfg.by_label[current]
                if any(ins.dest is not None and ins.dest.name == name for ins in block.instructions):
                    continue
            first = False
            if current == header:
                return False
            for predecessor in self.cfg.predecessors[current]:
                if predecessor in self.body and predecessor not in seen:
                    seen.add(predecessor)
                    work.append(predecessor)
        return True

    def check_taint(self):
        """Values that may have wrapped must not reach a hazard (see the module doc).

        Taint is tracked per origin: every temporary and frame cell carries the
        set of dropped checks whose wrapped result may reach it.  A hazard
        demotes exactly the checks that reach it — they stay branches — and the
        analysis runs again, until no hazard is left.
        """
        for _round in range(256):
            items = {id(check.operation): check for check in self.plan.sticky}
            items.update({id(site.operation): site.check for site in self.plan.sites})
            if not items:
                return
            culprits = self.taint(items)
            if not culprits:
                return
            for key in culprits:
                self.demote(items[key])
        raise Declined("taint analysis did not settle")

    def taint(self, items):
        """Run the taint dataflow once; return the origins of the first hazard, or None."""
        plan = self.plan
        cfg = self.cfg
        removed = {id(check.jnz) for check in plan.sticky} | {id(site.check.jnz) for site in plan.sites}
        kept = {id(check.jnz) for check in plan.traps}
        state_in = {label: {} for label in plan.body}
        for site in plan.sites:
            key = ("cell", site.cell[0])
            state_in[plan.header][key] = state_in[plan.header].get(key, frozenset()) | {id(site.operation)}
        for _round in range(128):
            changed = False
            for label in plan.body:
                state = dict(state_in[label])
                for ins in cfg.by_label[label].instructions:
                    hazard = self.transfer(ins, state, items, removed, kept)
                    if hazard:
                        return hazard
                for successor in cfg.successors[label]:
                    if successor not in self.body:
                        continue
                    target = state_in[successor]
                    for key, origins in state.items():
                        merged = target.get(key, frozenset()) | origins
                        if merged != target.get(key):
                            target[key] = merged
                            changed = True
            if not changed:
                return None
        raise Declined("taint analysis did not converge")

    def transfer(self, ins, state, items, removed, kept):
        """Apply one instruction to the taint state; return hazard origins or None."""
        empty = frozenset()

        def of(argument):
            return state.get(("temp", argument.name), empty) if is_temp(argument) else empty

        opcode = ins.opcode
        if opcode == "jnz":
            if id(ins) not in removed and id(ins) not in kept:
                return of(ins.args[0]) or None
            return None
        if opcode in ("jmp", "hlt", "ret", "dbgloc"):
            return None
        if opcode.startswith("store"):
            # Taint is kept per allocation: a store of a tainted value taints
            # the whole cell, and only a store that overwrites all of an
            # 8-byte cell clears it.  A cell whose address escaped may be read
            # back through an address the loop cannot place, so a value that
            # may have wrapped must not be stored there at all.
            cell = self.frame.cell(ins.args[1])
            key = ("cell", cell[0])
            origins = of(ins.args[0])
            if origins and cell[0] in self.frame.escaped:
                return origins
            if origins:
                state[key] = state.get(key, empty) | origins
            elif opcode == "storel" and cell[1] == 0 and self.frame.sizes.get(cell[0]) == 8:
                state.pop(key, None)
            return None
        if ins.dest is None:
            return None
        origins = empty
        if opcode.startswith("load"):
            cell = self.frame.cell(ins.args[0])
            if cell is None:
                if of(ins.args[0]):
                    return of(ins.args[0])
            else:
                origins = state.get(("cell", cell[0]), empty)
        elif opcode in SHIFTS:
            if of(ins.args[1]):
                return of(ins.args[1])
            origins = of(ins.args[0])
        elif opcode in DIVISIONS:
            divisor = constant_value(ins.args[1])
            if of(ins.args[1]):
                return of(ins.args[1])
            if of(ins.args[0]) and (divisor is None or divisor == MASK64):
                return of(ins.args[0])
            origins = of(ins.args[0])
        elif opcode in FLOAT_TO_INT:
            if of(ins.args[0]):
                return of(ins.args[0])
        else:
            for argument in ins.args:
                origins = origins | of(argument)
        if id(ins) in items:
            origins = origins | {id(ins)}
        if origins:
            state[("temp", ins.dest.name)] = origins
        else:
            state.pop(("temp", ins.dest.name), None)
        return None


class Rewriter:
    """Build the fast copy, the verification and the fallback of one Plan."""

    def __init__(self, unit, plan, number):
        self.unit = unit
        self.function = unit.function
        self.plan = plan
        self.prefix = f"sk{number}"
        sample = next(ins for block in self.function.blocks for ins in block.instructions)
        self.module = sys.modules[type(sample).__module__]
        self.Block = type(self.function.blocks[0])
        self.fresh_count = 0
        self.rename = {name: f"{self.prefix}.{name}" for name in plan.defined}

    def fresh(self, stem):
        self.fresh_count += 1
        return f"%{self.prefix}.{stem}{self.fresh_count}"

    def parse(self, text):
        return self.module.parse_instruction(text.strip(), 0, self.function.name, text)

    def label(self, label):
        return f"@{self.prefix}.{label.lstrip('@')}"

    def clone_operand(self, argument):
        if is_temp(argument) and argument.name in self.rename:
            return type(argument)("temp", self.rename[argument.name], argument.qbe_type)
        return argument

    def clone(self, ins, targets):
        dest = ins.dest
        if dest is not None:
            dest = type(dest)("temp", self.rename.get(dest.name, dest.name), dest.qbe_type)
        args = [self.clone_operand(argument) for argument in ins.args]
        extra = ins.extra
        if ins.opcode == "jmp":
            extra = targets(extra)
        elif ins.opcode == "jnz":
            extra = (targets(extra[0]), targets(extra[1]))
        return type(ins)(ins.opcode, ins.qbe_type, dest, args, extra, ins.line, ins.text)

    def run(self):
        function = self.function
        plan = self.plan
        cfg = Cfg(function)
        entry_label = self.label("@entry")
        fallback_label = self.label("@fallback")
        exit_labels = {target: self.label(f"@exit.{target.lstrip('@')}") for target in plan.exits}
        trap_labels = {check.trap_label for check in plan.traps}
        trap_labels |= {check.trap_label for check in plan.sticky}
        trap_labels |= {site.check.trap_label for site in plan.sites}
        sticky = {id(check.jnz): check for check in plan.sticky}
        sites = {}
        for site in plan.sites:
            sites.setdefault(id(site.check.jnz), []).append(site)
        for name in list(function.object_hints):
            if name in self.rename:
                function.object_hints.add(self.rename[name])

        def targets(label):
            if label in plan.body:
                return self.label(label)
            if label in exit_labels:
                return exit_labels[label]
            if label in trap_labels or trap_call(cfg.by_label[label]) is not None:
                return fallback_label
            raise Declined(f"edge to {label}")

        sticky_word = f"%{self.prefix}.sticky"
        count = f"%{self.prefix}.count"
        cells = sorted({site.cell for site in plan.sites})
        high = {cell: f"%{self.prefix}.hi.{cell[0]}" for cell in cells}
        low = {cell: f"%{self.prefix}.lo.{cell[0]}" for cell in cells}
        snapshots = {}
        blocks = []

        # Entry: snapshot every cell the loop writes, zero the bookkeeping.
        entry = self.Block(entry_label)
        for name in sorted(plan.cells):
            size = self.function_sizes()[name]
            pieces = []
            offset = 0
            while offset < size:
                width = 8 if size - offset >= 8 else 4
                address = f"%{name}"
                if offset:
                    address = self.fresh("at")
                    entry.instructions.append(self.parse(f"{address} =l add %{name}, {offset}"))
                saved = self.fresh("save")
                load = "loadl" if width == 8 else "loaduw"
                entry.instructions.append(self.parse(f"{saved} ={'l' if width == 8 else 'w'} {load} {address}"))
                pieces.append((offset, width, saved))
                offset += width
            snapshots[name] = pieces
        if plan.sticky:
            entry.instructions.append(self.parse(f"{sticky_word} =l copy 0"))
        if plan.sites:
            entry.instructions.append(self.parse(f"{count} =l copy 0"))
            for cell in cells:
                entry.instructions.append(self.parse(f"{high[cell]} =l copy 0"))
                entry.instructions.append(self.parse(f"{low[cell]} =l copy 0"))
        entry.instructions.append(self.parse(f"jmp {self.label(plan.header)}"))
        blocks.append(entry)

        # The fast copy.
        for label in plan.body:
            block = cfg.by_label[label]
            copy = self.Block(self.label(label))
            if label == plan.header and plan.sites:
                copy.instructions.append(self.parse(f"{count} =l add {count}, 1"))
            terminator = block.terminator()
            explicit = terminator is not None and terminator.opcode in ("jmp", "jnz", "ret", "hlt")
            body = block.instructions[:-1] if explicit else block.instructions
            for ins in body:
                copy.instructions.append(self.clone(ins, targets))
            if not explicit:
                copy.instructions.append(self.parse(f"jmp {targets(cfg.following[label])}"))
            elif id(terminator) in sticky:
                check = sticky[id(terminator)]
                flag = self.clone_operand(terminator.args[0])
                word = self.flag_word(copy, flag, block)
                bit = self.fresh("bit")
                test = "cnel" if check.trap_on_true else "ceql"
                copy.instructions.append(self.parse(f"{bit} =l {test} {word}, 0"))
                copy.instructions.append(self.parse(f"{sticky_word} =l or {sticky_word}, {bit}"))
                copy.instructions.append(self.parse(f"jmp {targets(check.ok_label)}"))
            elif id(terminator) in sites:
                for site in sites[id(terminator)]:
                    if site.constant is not None:
                        continue
                    x = self.clone_operand(site.operand)
                    sign, flipped, magnitude = self.fresh("sign"), self.fresh("flip"), self.fresh("abs")
                    top, bottom = self.fresh("top"), self.fresh("bottom")
                    for text in (f"{sign} =l sar %{x.name}, 63",
                                 f"{flipped} =l xor %{x.name}, {sign}",
                                 f"{magnitude} =l sub {flipped}, {sign}",
                                 f"{top} =l shr {magnitude}, 32",
                                 f"{bottom} =l and {magnitude}, 4294967295",
                                 f"{high[site.cell]} =l add {high[site.cell]}, {top}",
                                 f"{low[site.cell]} =l add {low[site.cell]}, {bottom}"):
                        copy.instructions.append(self.parse(text))
                check = sites[id(terminator)][0].check
                copy.instructions.append(self.parse(f"jmp {targets(check.ok_label)}"))
            else:
                copy.instructions.append(self.clone(terminator, targets))
            blocks.append(copy)

        # Verification at every normal exit.
        for target, label in exit_labels.items():
            block = self.Block(label)
            ok = self.verification(block, sticky_word, count, cells, high, low, snapshots)
            block.instructions.append(self.parse(f"jnz {ok}, {target}, {fallback_label}"))
            blocks.append(block)

        # Fallback: restore and run the original loop.
        fallback = self.Block(fallback_label)
        for name in sorted(plan.cells):
            for offset, width, saved in snapshots[name]:
                address = f"%{name}"
                if offset:
                    address = self.fresh("at")
                    fallback.instructions.append(self.parse(f"{address} =l add %{name}, {offset}"))
                store = "storel" if width == 8 else "storew"
                fallback.instructions.append(self.parse(f"{store} {saved}, {address}"))
        fallback.instructions.append(self.parse(f"jmp {plan.header}"))
        blocks.append(fallback)

        # Enter the fast copy instead of the loop.
        for predecessor in cfg.predecessors[plan.header]:
            if predecessor in plan.body:
                continue
            block = cfg.by_label[predecessor]
            terminator = block.terminator()
            if terminator is not None and terminator.opcode == "jmp":
                terminator.extra = entry_label
            elif terminator is not None and terminator.opcode == "jnz":
                terminator.extra = tuple(entry_label if t == plan.header else t
                                         for t in terminator.extra)
            else:
                block.instructions.append(self.parse(f"jmp {entry_label}"))
        function.blocks.extend(blocks)

    def function_sizes(self):
        return Frame(self.function).sizes

    def flag_word(self, copy, flag, block):
        """The check's flag as an `l` value."""
        definition = None
        for ins in block.instructions:
            if ins.dest is not None and is_temp(flag) and \
                    self.rename.get(ins.dest.name, ins.dest.name) == flag.name:
                definition = ins
        if definition is not None and definition.qbe_type == "w":
            widened = self.fresh("wide")
            copy.instructions.append(self.parse(f"{widened} =l extuw %{flag.name}"))
            return widened
        if is_temp(flag):
            return f"%{flag.name}"
        return str(constant_value(flag))

    def verification(self, block, sticky_word, count, cells, high, low, snapshots):
        """Append the exit test; return the `l` temp that is 1 when the fast copy is exact."""
        plan = self.plan
        parts = []

        def emit(text):
            block.instructions.append(self.parse(text))

        if plan.sticky:
            clean = self.fresh("clean")
            emit(f"{clean} =l ceql {sticky_word}, 0")
            parts.append(clean)
        for cell in cells:
            sites = [site for site in plan.sites if site.cell == cell]
            variable = sum(1 for site in sites if site.constant is None)
            constant = sum(site.constant for site in sites if site.constant is not None)
            entry = snapshots[cell[0]][0][2]
            # |entry value| as an unsigned magnitude (2^63 for the minimum).
            sign, flipped, magnitude = self.fresh("sign"), self.fresh("flip"), self.fresh("abs")
            emit(f"{sign} =l sar {entry}, 63")
            emit(f"{flipped} =l xor {entry}, {sign}")
            emit(f"{magnitude} =l sub {flipped}, {sign}")
            total = magnitude
            if variable:
                # The low sums cannot wrap while count * sites < 2^32, and the
                # high sum's real weight fits while it stays below 2^31.
                limit = (1 << 32) // variable - 1
                fits = self.fresh("fits")
                emit(f"{fits} =l culel {count}, {limit}")
                parts.append(fits)
                small = self.fresh("small")
                emit(f"{small} =l cultl {high[cell]}, 2147483648")
                parts.append(small)
                bounded = self.fresh("bounded")
                emit(f"{bounded} =l culel {low[cell]}, {MAX}")
                parts.append(bounded)
                shifted, summed = self.fresh("shift"), self.fresh("sum")
                emit(f"{shifted} =l shl {high[cell]}, 32")
                emit(f"{summed} =l add {shifted}, {low[cell]}")
                inside = self.fresh("inside")
                emit(f"{inside} =l culel {summed}, {MAX}")
                parts.append(inside)
                grown = self.fresh("grown")
                emit(f"{grown} =l add {total}, {summed}")
                total = grown
                # total <= 2^63 + MAX < 2^64: no wrap before the last test.
            if constant:
                limit = MAX // constant
                few = self.fresh("few")
                emit(f"{few} =l culel {count}, {limit}")
                parts.append(few)
                steps = self.fresh("steps")
                emit(f"{steps} =l mul {count}, {constant}")
                if variable:
                    # Bring the running total back under 2^63 before adding.
                    under = self.fresh("under")
                    emit(f"{under} =l culel {total}, {MAX}")
                    parts.append(under)
                grown = self.fresh("grown")
                emit(f"{grown} =l add {total}, {steps}")
                total = grown
            final = self.fresh("final")
            emit(f"{final} =l culel {total}, {MAX}")
            parts.append(final)
        if not parts:
            one = self.fresh("one")
            emit(f"{one} =l copy 1")
            return one
        result = parts[0]
        for part in parts[1:]:
            both = self.fresh("both")
            emit(f"{both} =l and {result}, {part}")
            result = both
        return result


def version_loops(unit, log=None):
    """Rewrite every qualifying innermost loop of `unit` in place.

    Returns a list of (header, verdict) pairs, where the verdict is
    "versioned: ..." or the reason the loop was declined.
    """
    if os.environ.get("MYLANG_QBE_LLVM_STICKY", "1") == "0":
        return []
    function = unit.function
    if not function.blocks:
        return []
    cfg = Cfg(function)
    frame = Frame(function)
    verdicts = []
    plans = []
    for header, body in natural_loops(cfg):
        try:
            plan = Analysis(function, cfg, frame, header, body).run()
            plans.append(plan)
            verdicts.append((header, f"versioned: {len(plan.sites)} reduction(s), "
                                     f"{len(plan.sticky)} sticky, {len(plan.traps)} kept"))
        except Declined as reason:
            verdicts.append((header, f"declined: {reason}"))
    for number, plan in enumerate(plans):
        Rewriter(unit, plan, number).run()
    path = log or os.environ.get("MYLANG_QBE_LLVM_STICKY_LOG")
    if path:
        with open(path, "a") as handle:
            for header, verdict in verdicts:
                handle.write(f"{function.name} {header} {verdict}\n")
    return verdicts
