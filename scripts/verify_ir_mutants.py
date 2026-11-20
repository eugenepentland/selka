#!/usr/bin/env python3
"""Single-rule mutants of `core-ir-v1` texts, for the IR verifier differential (`scripts/verify_ir_proof.py`).

Each mutation class edits one function of a module that both verifiers accept so that it breaks one rule of
`src/core/verify_ir.zig` (or, for the `strict-*` classes, one rule only the Lean copy has), and names the rule both
checkers must report. The choice of sites is deterministic: classes visit the files in path order, the functions in
module order and the sites in instruction order, and take at most one site per function and `--per-class` per class.

    python3 scripts/verify_ir_mutants.py SOURCE_DIR OUT_DIR [--per-class N]

writes `OUT_DIR/<class>-<n>.core-ir` and prints a manifest line `<file> <class> <rule> <function>` per mutant.
The classes `type-table`, `operand-type`, `copy-none`, `copy-cycle` and `last-ref` are malformed tables the Zig verifier
crashed or looped on before the differential's findings; `strict-unused` is accepted by both (only `irverify --strict`
refuses it).
"""
from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path

FIRST = 16
VOID, BOOL, I8, I16, I32, I64, U8, U16, U32, U64, F64, CAP, STR, BYTES, STR_VIEW, F32 = range(16)
PLACE_COPY = 1 << 60
TERMINATORS = {"jump", "branch", "ret", "unreachable"}
CONSTANTS = {"param", "iconst", "fconst", "undef", "str_const", "text_sentinel", "func_ref"}
EXTRA_OPS = {"phi", "call", "call_indirect", "print", "record_make", "list_set", "list_set_field", "buffer_append",
             "dict_set_value", "dict_insert", "str_append_char", "str_slice", "str_view_of", "str_slice_view",
             "str_slice_bytes_view", "float_fma", "vector_select", "array_set", "list_slice_view", "buffer_set"}
EXTRA_ONLY = {"phi", "call", "print", "record_make"}
INTEGERS = {I8, I16, I32, I64, U8, U16, U32, U64}


class Fn:
    """One function of a text, kept as words so that it renders back exactly."""

    def __init__(self, head, sig, insts, extra, blocks):
        self.head, self.sig, self.insts, self.extra, self.blocks = head, sig, insts, extra, blocks

    @property
    def name(self):
        return self.head[0]

    @property
    def internal(self):
        return self.sig[0] == "internal"

    def params(self):
        return [int(t) for t in self.sig[3:3 + int(self.sig[2])]]

    def ret(self):
        return int(self.sig[1])


class Module:
    def __init__(self, types, fns):
        self.types, self.fns = types, fns

    def render(self):
        out = ["core-ir-v1", f"types {len(self.types)}"]
        out += ["t " + " ".join(t) for t in self.types]
        out.append(f"functions {len(self.fns)}")
        for f in self.fns:
            out.append("function " + " ".join(f.head))
            out.append("sig " + " ".join(f.sig))
            out.append(f"insts {len(f.insts)}")
            out += [" ".join(i) for i in f.insts]
            out.append(" ".join(["extra", str(len(f.extra))] + f.extra))
            out.append(f"blocks {len(f.blocks)}")
            for refs, preds in f.blocks:
                out.append(" ".join(["block", str(len(refs))] + refs + [str(len(preds))] + preds))
            out.append("end")
        return "\n".join(out) + "\n"

    def kind(self, t):
        t = int(t)
        if t >= FIRST and t < 0xFFFFFFF0 and t - FIRST < len(self.types):
            return self.types[t - FIRST][0]
        return None


def parse(text):
    lines = text.split("\n")
    i = 1
    nt = int(lines[i].split()[1]); i += 1
    types = [lines[i + k].split()[1:] for k in range(nt)]; i += nt
    nf = int(lines[i].split()[1]); i += 1
    fns = []
    for _ in range(nf):
        head = lines[i].split()[1:]
        sig = lines[i + 1].split()[1:]
        n = int(lines[i + 2].split()[1])
        insts = [lines[i + 3 + k].split() for k in range(n)]
        extra = lines[i + 3 + n].split()[2:]
        nb = int(lines[i + 4 + n].split()[1])
        blocks = []
        for k in range(nb):
            w = lines[i + 5 + n + k].split()
            c = int(w[1])
            refs = w[2:2 + c]
            preds = w[3 + c:3 + c + int(w[2 + c])]
            blocks.append((refs, preds))
        i += 6 + n + nb
        fns.append(Fn(head, sig, insts, extra, blocks))
    return Module(types, fns)


# ---- what a function's control flow and values are --------------------------------------------------------------------

def extra_slice(data):
    data = int(data)
    return data & 0xFFFFFFFF, (data >> 32) & 0x7FFFFFFF


def successors(f, b):
    refs = f.blocks[b][0]
    if not refs or refs[-1] == "-" or int(refs[-1]) >= len(f.insts):
        return []
    last = f.insts[int(refs[-1])]
    data = int(last[4])
    if last[0] == "jump":
        return [data & 0xFFFFFFFF]
    if last[0] == "branch":
        return [data & 0xFFFFFFFF, data >> 32]
    return []


def reachable(f):
    seen, stack = {0}, [0]
    while stack:
        b = stack.pop()
        for s in successors(f, b):
            if s < len(f.blocks) and s not in seen:
                seen.add(s)
                stack.append(s)
    return seen


def dominators(f, reach):
    order = sorted(reach)
    dom = {b: set(reach) for b in order}
    dom[0] = {0}
    preds = {b: [int(p) for p in f.blocks[b][1] if int(p) in reach] for b in order}
    changed = True
    while changed:
        changed = False
        for b in order:
            if b == 0:
                continue
            new = set(reach)
            for p in preds[b]:
                new &= dom[p]
            new |= {b}
            if new != dom[b]:
                dom[b] = new
                changed = True
    return dom


def positions(f, reach):
    pos = {}
    for b in sorted(reach):
        for k, r in enumerate(f.blocks[b][0]):
            pos[int(r)] = (b, k)
    return pos


def resolve(f, r):
    seen = set()
    while r is not None and r not in seen and r < len(f.insts) and f.insts[r][0] == "copy":
        seen.add(r)
        r = None if f.insts[r][2] == "-" else int(f.insts[r][2])
    return r


def type_of(f, r):
    r = resolve(f, r)
    return int(f.insts[r][1]) if r is not None and r < len(f.insts) else None


def value_operands(f, inst):
    """(field, index) of each value operand: ('a', None), ('b', None) or ('x', position in the extra list)."""
    if inst[0] == "jump":
        return []
    out = []
    if inst[0] not in EXTRA_ONLY:
        out += [(field, None) for field, w in (("a", inst[2]), ("b", inst[3])) if w != "-"]
    if inst[0] in EXTRA_OPS:
        start, length = extra_slice(inst[4])
        out += [("x", start + k) for k in range(length)]
    return out


def operand(f, inst, where):
    field, index = where
    w = inst[2] if field == "a" else inst[3] if field == "b" else f.extra[index]
    return None if w == "-" else int(w)


def set_operand(f, r, where, value):
    field, index = where
    if field == "a":
        f.insts[r][2] = str(value)
    elif field == "b":
        f.insts[r][3] = str(value)
    else:
        f.extra[index] = str(value)


def listed(f, reach):
    """(block, position, ref) of each listed instruction of a reachable block, in block order."""
    for b in sorted(reach):
        for k, r in enumerate(f.blocks[b][0]):
            yield b, k, int(r)


def fresh(f, op, ty, data=0):
    """Append a constant to the table; its reference."""
    f.insts.append([op, str(ty), "-", "-", str(data), "none"])
    return len(f.insts) - 1


def other_type(t):
    return I64 if t == BOOL else BOOL


# ---- the classes: each yields mutated copies of one function ---------------------------------------------------------
#
# A class is `(name, rule, sites)`: `sites(m, f)` yields functions that mutate a fresh copy of `f` in place (and may
# append to the module's types) and return True when they applied.


def c_no_blocks(m, f):
    def edit(g):
        g.blocks = []
        return True
    yield edit


def c_target(m, f):
    for b in sorted(reachable(f)):
        last = f.insts[int(f.blocks[b][0][-1])]
        if last[0] == "jump":
            def edit(g, b=b):
                g.insts[int(g.blocks[b][0][-1])][4] = str(len(g.blocks) + 3)
                return True
            yield edit


def c_empty_block(m, f):
    # A block whose successors all come after it: no earlier block's predecessor check meets the emptied block first.
    for b in sorted(reachable(f), reverse=True):
        if b != 0 and all(s > b for s in successors(f, b)):
            def edit(g, b=b):
                g.blocks[b] = ([], g.blocks[b][1])
                return True
            yield edit


def c_listed_range(m, f):
    for b in sorted(reachable(f)):
        if len(f.blocks[b][0]) >= 2:
            def edit(g, b=b):
                g.blocks[b][0][0] = str(len(g.insts) + 3)
                return True
            yield edit


def c_listed_twice(m, f):
    for b in sorted(reachable(f)):
        refs = f.blocks[b][0]
        for k, r in enumerate(refs[:-1]):
            if f.insts[int(r)][0] not in ("phi", "copy"):
                def edit(g, b=b, k=k):
                    refs = g.blocks[b][0]
                    refs.insert(k + 1, refs[k])
                    return True
                yield edit
                break


def c_terminator(m, f):
    for b in sorted(reachable(f)):
        refs = f.blocks[b][0]
        if len(refs) >= 2 and f.insts[int(refs[-2])][0] not in {"phi", "copy"} | TERMINATORS:
            def edit(g, b=b):
                refs = g.blocks[b][0]
                refs[-1], refs[-2] = refs[-2], refs[-1]
                return True
            yield edit


def c_phi_order(m, f):
    for b in sorted(reachable(f)):
        refs = f.blocks[b][0]
        ops = [f.insts[int(r)][0] for r in refs]
        if "phi" in ops:
            last_phi = max(k for k, o in enumerate(ops) if o == "phi")
            later = [k for k, o in enumerate(ops) if k > last_phi and o not in TERMINATORS and o != "copy"]
            if later:
                def edit(g, b=b, p=last_phi, k=later[0]):
                    refs = g.blocks[b][0]
                    refs.insert(k, refs.pop(p))
                    return True
                yield edit


def c_phi_arity(m, f):
    for b, _, r in listed(f, reachable(f)):
        if f.insts[r][0] == "phi" and extra_slice(f.insts[r][4])[1] >= 1:
            def edit(g, r=r):
                g.insts[r][4] = str(int(g.insts[r][4]) - (1 << 32))
                return True
            yield edit


def has_phi(f, b):
    return any(f.insts[int(r)][0] == "phi" for r in f.blocks[b][0])


def c_edge_preds(m, f):
    for s in sorted(reachable(f)):
        if s != 0 and f.blocks[s][1] and not has_phi(f, s):
            def edit(g, s=s):
                g.blocks[s][1].append(g.blocks[s][1][0])
                return True
            yield edit


def c_pred_edge(m, f):
    reach = reachable(f)
    for s in sorted(reach):
        # Not the entry: a predecessor there is `entry-preds`.
        if s == 0 or has_phi(f, s):
            continue
        for q in sorted(reach):
            if s not in successors(f, q):
                def edit(g, s=s, q=q):
                    g.blocks[s][1].append(str(q))
                    return True
                yield edit
                break


def c_type_valid(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] not in TERMINATORS | {"copy", "phi"}:
            def edit(g, r=r):
                g.insts[r][1] = str(FIRST + len(m.types) + 5)
                return True
            yield edit


def c_extra_range(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] in EXTRA_OPS and f.insts[r][0] != "phi":
            def edit(g, r=r):
                g.insts[r][4] = str(((int(g.insts[r][4]) >> 32) << 32) | (len(g.extra) + 1))
                return True
            yield edit


def c_operand_range(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] in ("add", "sub", "mul", "cmp") and f.insts[r][3] != "-":
            def edit(g, r=r):
                g.insts[r][3] = str(len(g.insts) + 3)
                return True
            yield edit


def c_retype_result(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] in ("add", "sub", "mul") and int(f.insts[r][1]) in (I64, I32):
            def edit(g, r=r):
                g.insts[r][1] = str(I32 if int(g.insts[r][1]) == I64 else I64)
                return True
            yield edit


def retype_operand(ops, which=lambda inst, k: True):
    """A class: replace a value operand of an instruction with an operation in `ops` by a fresh constant of another type."""
    def sites(m, f):
        for _, _, r in listed(f, reachable(f)):
            inst = f.insts[r]
            if inst[0] not in ops:
                continue
            for k, where in enumerate(value_operands(f, inst)):
                current = operand(f, inst, where)
                if current is None or not which(inst, k):
                    continue
                t = type_of(f, current)
                if t is None or m.kind(t) is not None and m.kind(t) in ("list_view",):
                    continue
                def edit(g, r=r, where=where, t=t):
                    set_operand(g, r, where, fresh(g, "iconst", other_type(t)))
                    return True
                yield edit
                break
    return sites


def c_func_ref_sig(m, f):
    internal = [k for k, g in enumerate(m.fns) if g.internal]
    for r, inst in enumerate(f.insts):
        if inst[0] != "func_ref":
            continue
        target = int(inst[4])
        for k in internal:
            if m.fns[k].sig != m.fns[target].sig:
                def edit(g, r=r, k=k):
                    g.insts[r][4] = str(k)
                    return True
                yield edit
                break


def c_view_def(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] in ("add", "sub", "mul"):
            def edit(g, r=r):
                g.insts[r][1] = str(STR_VIEW)
                return True
            yield edit


def c_view_use(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] in ("add", "sub", "mul", "cmp") and f.insts[r][3] != "-":
            def edit(g, r=r):
                g.insts[r][3] = str(fresh(g, "undef", STR_VIEW))
                return True
            yield edit


def c_insert_probe(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] == "dict_insert":
            def edit(g, r=r):
                g.insts[r][3] = str(fresh(g, "iconst", I64))
                return True
            yield edit


def c_shallow_copy(m, f):
    for _, _, r in listed(f, reachable(f)):
        inst = f.insts[r]
        if inst[0] == "list_copy" and int(inst[4]) == PLACE_COPY:
            def edit(g, r=r):
                g.insts[r][4] = "0"
                return True
            yield edit


def c_dom_order(m, f):
    reach = reachable(f)
    pos = positions(f, reach)
    for b, k, r in listed(f, reach):
        inst = f.insts[r]
        if inst[0] in TERMINATORS | {"phi", "copy"}:
            continue
        for where in value_operands(f, inst):
            y = resolve(f, operand(f, inst, where))
            if y is None or f.insts[y][0] in CONSTANTS | {"phi"} or y not in pos:
                continue
            yb, yk = pos[y]
            if yb == b and yk < k:
                def edit(g, b=b, k=k, yk=yk):
                    refs = g.blocks[b][0]
                    refs.insert(yk, refs.pop(k))
                    return True
                yield edit
                break


def c_dom_block(m, f):
    reach = reachable(f)
    dom = dominators(f, reach)
    pos = positions(f, reach)
    defs = {}
    for b, k, r in listed(f, reach):
        inst = f.insts[r]
        # A constant listed in a block is still materialized at each use, so it dominates every use.
        if inst[0] not in TERMINATORS | {"phi", "copy"} | CONSTANTS and int(inst[1]) != VOID:
            defs.setdefault(int(inst[1]), []).append((b, r))
    for b, k, r in listed(f, reach):
        inst = f.insts[r]
        if inst[0] in ("phi", "copy"):
            continue
        for where in value_operands(f, inst):
            cur = operand(f, inst, where)
            t = type_of(f, cur)
            for db, dr in defs.get(t, []):
                if db not in dom[b] and dr != r:
                    def edit(g, r=r, where=where, dr=dr):
                        set_operand(g, r, where, dr)
                        return True
                    yield edit
                    break
            else:
                continue
            break


def c_dom_undefined(m, f):
    reach = reachable(f)
    for b, k, r in listed(f, reach):
        inst = f.insts[r]
        if inst[0] in TERMINATORS | {"phi", "copy"} | CONSTANTS:
            continue
        users = [u for _, _, u in listed(f, reach)
                 if any(resolve(f, operand(f, f.insts[u], w)) == r for w in value_operands(f, f.insts[u]))]
        if users:
            def edit(g, b=b, k=k):
                g.blocks[b][0].pop(k)
                return True
            yield edit


def c_param_type(m, f):
    if f.params():
        def edit(g):
            g.sig[3] = str(FIRST + len(m.types) + 9)
            return True
        yield edit


def c_result_type(m, f):
    def edit(g):
        g.sig[3 + int(g.sig[2])] = str(1 << int(g.sig[2])) if int(g.sig[2]) < 64 else g.sig[3 + int(g.sig[2])]
        return int(g.sig[2]) < 64
    yield edit


def c_borrow_contract(m, f):
    if f.sig[-1] == "0" and f.sig[-2] == "0":
        def edit(g):
            g.sig[-1] = "1"
            g.sig.append(f"a{int(g.sig[2]) + 1}")
            return True
        yield edit


def c_view_storage(m, f):
    def edit(g):
        m.types.append(["list", str(STR_VIEW)])
        return True
    yield edit


def c_view_storage_box(m, f):
    """A box of a text span that no task thunk takes: not a task environment (FR58), so it stores a view."""
    def edit(g):
        m.types.append(["box", str(STR_VIEW)])
        return True
    yield edit


def c_view_storage_task_field(m, f):
    """A task thunk's environment record gains a field that holds a borrow and is no view (an overlay of `str`): the
    environment exception (FR58) covers views only."""
    params = f.params()
    if not f.name.startswith("<task.thunk.") or len(params) != 1 or m.kind(params[0]) != "box":
        return
    record = int(m.types[params[0] - FIRST][1])
    if m.kind(record) != "record":
        return
    def edit(g):
        m.types.append(["borrowed", str(STR)])
        fields = m.types[record - FIRST][2:] + [str(FIRST + len(m.types) - 1)]
        m.types[record - FIRST] = ["record", str(len(fields))] + fields
        return True
    yield edit


def c_record_field(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] == "record_get":
            def edit(g, r=r):
                g.insts[r][4] = str(1000)
                return True
            yield edit


def c_union_tag(m, f):
    for _, _, r in listed(f, reachable(f)):
        if f.insts[r][0] == "union_make":
            def edit(g, r=r):
                g.insts[r][4] = str(1000)
                return True
            yield edit


# Lean-only rules (`irverify --strict`), and the Zig verifier once it has them.

def c_strict_param(m, f):
    def edit(g):
        fresh(g, "param", I64, data=len(g.params()) + 3)
        return True
    yield edit


def c_strict_const(m, f):
    def edit(g):
        fresh(g, "str_const", I64)
        return True
    yield edit


def c_strict_entry(m, f):
    """Turn the entry's `else` edge into a back edge to the entry, when the `else` block has no phi and one predecessor."""
    if has_phi(f, 0) or not f.blocks[0][0]:
        return
    last = f.insts[int(f.blocks[0][0][-1])]
    if last[0] != "branch":
        return
    then, other = int(last[4]) & 0xFFFFFFFF, int(last[4]) >> 32
    if then == other or then == 0 or other == 0 or has_phi(f, other) or f.blocks[other][1] != ["0"]:
        return
    def edit(g):
        r = int(g.blocks[0][0][-1])
        g.insts[r][4] = str(then)  # else (the high half) is now block 0
        g.blocks[other][1].clear()
        g.blocks[0][1].append("0")
        return True
    yield edit


# ---- the union-tag rule (F-VL-10): a payload read is justified only by a test of its own value's tag ------------------

READS = {"union_payload", "union_take"}


def canonical(f, r):
    """Follow copies and overlays (`copy`, `borrow`) to the value they stand for, as the union-tag rule does."""
    seen = set()
    while r is not None and r not in seen and r < len(f.insts) and f.insts[r][0] in ("copy", "borrow"):
        seen.add(r)
        r = None if f.insts[r][2] == "-" else int(f.insts[r][2])
    return r


def tag_tests(f, reach):
    """(block, branch ref, cmp ref, tag refs) of each branch on `cmp eq|ne` of union tags: one tag and a constant, or two
    tags."""
    for b in sorted(reach):
        refs = f.blocks[b][0]
        if not refs or refs[-1] == "-":
            continue
        last = int(refs[-1])
        if f.insts[last][0] != "branch" or f.insts[last][2] == "-":
            continue
        then, other = int(f.insts[last][4]) & 0xFFFFFFFF, int(f.insts[last][4]) >> 32
        cond = canonical(f, int(f.insts[last][2]))
        if then == other or cond is None or f.insts[cond][0] != "cmp" or int(f.insts[cond][4]) > 1:
            continue
        sides = [canonical(f, None if w == "-" else int(w)) for w in f.insts[cond][2:4]]
        if None in sides:
            continue
        tags = [r for r in sides if f.insts[r][0] == "union_tag"]
        constants = [r for r in sides if f.insts[r][0] == "iconst"]
        made = [canonical(f, None if f.insts[t][2] == "-" else int(f.insts[t][2])) for t in tags]
        if any(v is not None and f.insts[v][0] == "union_make" for v in made):
            continue  # a `union_make` is its own case whatever the test says: no mutant of the test can refuse its reads
        if len(tags) == 2 or (len(tags) == 1 and len(constants) == 1):
            yield b, last, cond, tags


def reads_union(f, reach):
    return any(f.insts[r][0] in READS for _, _, r in listed(f, reach))


def c_tag_false_edge(equality):
    """The read on the false edge: the branch on a tag test swaps its targets."""
    def sites(m, f):
        reach = reachable(f)
        if not reads_union(f, reach):
            return
        for _, last, _, tags in tag_tests(f, reach):
            if (len(tags) == 2) == equality:
                def edit(g, last=last):
                    data = int(g.insts[last][4])
                    g.insts[last][4] = str(((data & 0xFFFFFFFF) << 32) | (data >> 32))
                    return True
                yield edit
    return sites


def c_tag_other_value(equality):
    """The guard on another value: a tag test's `union_tag` reads an `undef` of the same union instead."""
    def sites(m, f):
        reach = reachable(f)
        if not reads_union(f, reach):
            return
        for _, _, _, tags in tag_tests(f, reach):
            if (len(tags) == 2) == equality:
                tag = tags[0]
                value = canonical(f, None if f.insts[tag][2] == "-" else int(f.insts[tag][2]))
                if value is None:
                    continue
                def edit(g, tag=tag, ty=int(f.insts[value][1])):
                    g.insts[tag][2] = str(fresh(g, "undef", ty))
                    return True
                yield edit
    return sites


def read_values(f, reach):
    """(read ref, canonical value) of each payload read of a reachable block whose value no `union_tag` reads (its tag is
    known only through the place shapes R, S and P)."""
    tested = {canonical(f, int(i[2])) for i in f.insts if i[0] == "union_tag" and i[2] != "-"}
    for _, _, r in listed(f, reach):
        if f.insts[r][0] in READS and f.insts[r][2] != "-":
            v = canonical(f, int(f.insts[r][2]))
            if v is not None and v not in tested:
                yield r, v


def c_tag_field(store):
    """Shapes R and S: the `record_get` a payload read reads reads an `undef` record of the same type instead (with `store`,
    a `record_get` of a `record_set` of the same field; else one with a twin, another `record_get` of its record and field)."""
    def sites(m, f):
        for _, v in read_values(f, reachable(f)):
            inst = f.insts[v]
            if inst[0] != "record_get" or inst[2] == "-":
                continue
            base = canonical(f, int(inst[2]))
            if base is None:
                continue
            is_store = f.insts[base][0] == "record_set" and f.insts[base][4] == inst[4]
            twin = any(k != v and i[0] == "record_get" and i[4] == inst[4] and i[2] != "-" and canonical(f, int(i[2])) == base
                       for k, i in enumerate(f.insts))
            if (is_store if store else (twin and not is_store)):
                def edit(g, v=v, ty=int(f.insts[base][1])):
                    g.insts[v][2] = str(fresh(g, "undef", ty))
                    return True
                yield edit
    return sites


def c_tag_phi_operand(m, f):
    """Shape P: the first operand of a `phi` a payload read reads becomes an `undef` of the `phi`'s type."""
    for _, v in read_values(f, reachable(f)):
        if f.insts[v][0] != "phi":
            continue
        start, length = extra_slice(f.insts[v][4])
        if length == 0:
            continue
        def edit(g, v=v, start=start):
            g.extra[start] = str(fresh(g, "undef", int(g.insts[v][1])))
            return True
        yield edit


def c_tag_read_moved(m, f):
    """A payload read moved out of its guarded block: into the block whose tag test guards it, before the branch."""
    reach = reachable(f)
    pos = positions(f, reach)
    for b, k, r in listed(f, reach):
        inst = f.insts[r]
        if inst[0] not in READS or inst[2] == "-" or len(f.blocks[b][1]) != 1:
            continue
        p = int(f.blocks[b][1][0])
        value = canonical(f, int(inst[2]))
        if p == b or p not in reach or value is None or pos.get(value, (None,))[0] == b or f.insts[value][0] == "union_make":
            continue
        if not any(t == p for t, _, _, _ in tag_tests(f, reach)):
            continue
        def edit(g, b=b, k=k, r=r, p=p):
            del g.blocks[b][0][k]
            g.blocks[p][0].insert(len(g.blocks[p][0]) - 1, str(r))
            return True
        yield edit


CLASSES = [
    ("no-blocks", "no-blocks", c_no_blocks),
    ("target", "target", c_target),
    ("empty-block", "empty-block", c_empty_block),
    ("listed-range", "listed-range", c_listed_range),
    ("listed-twice", "listed-twice", c_listed_twice),
    ("terminator", "terminator", c_terminator),
    ("phi-order", "phi-order", c_phi_order),
    ("phi-arity", "phi-arity", c_phi_arity),
    ("edge-preds", "edge-preds", c_edge_preds),
    ("pred-edge", "pred-edge", c_pred_edge),
    ("type-valid", "type-valid", c_type_valid),
    ("extra-range", "extra-range", c_extra_range),
    ("operand-range", "operand-range", c_operand_range),
    ("retype-result", "signature", c_retype_result),
    ("call-argument", "signature", retype_operand({"call"})),
    ("ret-value", "signature", retype_operand({"ret"})),
    ("branch-condition", "signature", retype_operand({"branch"})),
    ("phi-operand", "signature", retype_operand({"phi"})),
    ("record-make-field", "signature", retype_operand({"record_make"})),
    ("list-push-element", "signature", retype_operand({"list_push"}, lambda inst, k: k == 1)),
    ("drop-unmanaged", "signature", retype_operand({"drop"})),
    ("record-field", "signature", c_record_field),
    ("union-tag", "signature", c_union_tag),
    ("func-ref-signature", "signature", c_func_ref_sig),
    ("call-indirect-argument", "signature", retype_operand({"call_indirect"}, lambda inst, k: k >= 1)),
    ("call-indirect-callee", "signature", retype_operand({"call_indirect"}, lambda inst, k: k == 0)),
    ("view-def", "view-def", c_view_def),
    ("view-use", "view-use", c_view_use),
    ("insert-probe", "insert-probe", c_insert_probe),
    ("shallow-copy", "shallow-copy", c_shallow_copy),
    ("dom-order", "dom-order", c_dom_order),
    ("dom-block", "dom-block", c_dom_block),
    ("dom-undefined", "dom-undefined", c_dom_undefined),
    ("param-type", "param-type", c_param_type),
    ("result-type", "result-type", c_result_type),
    ("borrow-contract", "borrow-contract", c_borrow_contract),
    ("view-storage", "view-storage", c_view_storage),
    ("view-storage-box", "view-storage", c_view_storage_box),
    ("view-storage-task-field", "view-storage", c_view_storage_task_field),
    ("param-signature", "signature", c_strict_param),
    ("constant-type", "signature", c_strict_const),
    ("entry-preds", "entry-preds", c_strict_entry),
    ("type-table", "type-table", lambda m, f: [lambda g: _type_table(m)]),
    ("operand-type", "operand-type", lambda m, f: [lambda g: _operand_type(m, g)]),
    ("copy-none", "dom-forward", lambda m, f: [lambda g: _copy_none(g)]),
    ("copy-cycle", "dom-forward", lambda m, f: [lambda g: _copy_cycle(g)]),
    ("last-ref", "listed-range", lambda m, f: [lambda g: _last_ref(g)]),
    ("listed-constant", "dom-order", lambda m, f: c_listed_constant(m, f)),
    ("span-admission", "param-type", lambda m, f: c_span_admission(m, f)),
    ("span-argument", "signature", lambda m, f: c_span_argument(m, f)),
    ("unused-operand", "unused-operand", lambda m, f: c_unused_operand(m, f)),
    ("tag-read-moved", "union-tag", c_tag_read_moved),
    ("tag-false-edge", "union-tag", c_tag_false_edge(False)),
    ("tag-other-value", "union-tag", c_tag_other_value(False)),
    ("tag-equal-false-edge", "union-tag", c_tag_false_edge(True)),
    ("tag-third-value", "union-tag", c_tag_other_value(True)),
    ("tag-field-twin", "union-tag", c_tag_field(False)),
    ("tag-field-store", "union-tag", c_tag_field(True)),
    ("tag-phi-operand", "union-tag", c_tag_phi_operand),
    # Lean only (`irverify --strict`): the Zig verifier accepts these.
    ("strict-unused", "accept", lambda m, f: [lambda g: _jump_operand(g)]),
]


def c_listed_constant(m, f):
    """List a constant an instruction reads right after that instruction: the use now precedes the definition."""
    for b, k, r in listed(f, reachable(f)):
        inst = f.insts[r]
        if inst[0] in TERMINATORS | {"phi", "copy"}:
            continue
        for where in value_operands(f, inst):
            y = operand(f, inst, where)
            if y is not None and f.insts[y][0] == "iconst" and str(y) not in [x for refs, _ in f.blocks for x in refs]:
                def edit(g, b=b, k=k, y=y):
                    g.blocks[b][0].insert(k + 1, str(y))
                    return True
                yield edit
                break


def c_span_admission(m, f):
    """An external function's span convention on a parameter that is no text, bytes or list view."""
    n = int(f.sig[2])
    views = int(f.sig[3 + n + 2])
    for k in range(min(n, 64)):
        if views >> k & 1:
            def edit(g, k=k):
                g.sig[3 + k] = str(I64)
                return True
            yield edit
            break


def c_span_argument(m, f):
    """A call passing a text span for a parameter of a list-view type: the callee's parameter becomes a list view."""
    for _, _, r in listed(f, reachable(f)):
        inst = f.insts[r]
        if inst[0] != "call":
            continue
        callee = m.fns[int(inst[2])]
        if not callee.internal:
            continue
        for k, where in enumerate(value_operands(f, inst)):
            if type_of(f, operand(f, inst, where)) == STR_VIEW and int(callee.sig[3 + k]) == STR_VIEW:
                view = next((FIRST + j for j, t in enumerate(m.types) if t[0] == "list_view"), None)
                if view is None:
                    continue
                def edit(g, view=view, index=int(inst[2]), k=k):
                    callee = copy.deepcopy(m.fns[index])
                    callee.sig[3 + k] = str(view)
                    m.fns[index] = callee
                    return True
                yield edit
                break


def c_unused_operand(m, f):
    for _, _, r in listed(f, reachable(f)):
        inst = f.insts[r]
        if inst[0] in ("print", "record_make") and inst[2] == "-":
            def edit(g, r=r):
                g.insts[r][2] = str(fresh(g, "iconst", I64))
                return True
            yield edit


def _type_table(m):
    m.types.append(["list", str(FIRST + len(m.types) + 40)])
    return True


def _operand_type(m, g):
    u = _first_value_user(g)
    if u is None:
        return False
    g.insts.append(["add", str(FIRST + len(m.types) + 40), "-", "-", "0", "none"])
    g.insts[u][2] = str(len(g.insts) - 1)
    return True


def _last_ref(g):
    for refs, _ in g.blocks:
        if refs:
            refs[-1] = str(len(g.insts) + 7)
            return True
    return False


def _first_value_user(g):
    for b in sorted(reachable(g)):
        for r in g.blocks[b][0]:
            inst = g.insts[int(r)]
            if inst[0] in ("add", "sub", "mul", "cmp", "ret", "branch") and inst[2] != "-":
                return int(r)
    return None


def _copy_none(g):
    u = _first_value_user(g)
    if u is None:
        return False
    g.insts.append(["copy", g.insts[u][1], "-", "-", "0", "none"])
    g.insts[u][2] = str(len(g.insts) - 1)
    return True


def _copy_cycle(g):
    u = _first_value_user(g)
    if u is None:
        return False
    n = len(g.insts)
    g.insts.append(["copy", "0", str(n + 1), "-", "0", "none"])
    g.insts.append(["copy", "0", str(n), "-", "0", "none"])
    g.insts[u][2] = str(n)
    return True


def _jump_operand(g):
    for b in sorted(reachable(g)):
        r = int(g.blocks[b][0][-1])
        if g.insts[r][0] == "jump":
            g.insts[r][2] = str(len(g.insts) + 11)
            return True
    return False


def mutants(sources, per_class, classes=CLASSES):
    """(class, rule, function name, module) for each mutant, deterministically. The sites are found on the original
    function; the chosen site is applied to a copy (the copy's own sites are enumerated again and the same one taken),
    so an edit that appends a type appends it to the copy's table."""
    modules = [(p, parse(p.read_text())) for p in sources]
    for name, rule, sites in classes:
        made = 0
        for _, m in modules:
            if made >= per_class:
                break
            for index, f in enumerate(m.fns):
                if made >= per_class:
                    break
                if (not f.internal or not f.blocks) and name != "span-admission":
                    continue
                for k, _ in enumerate(sites(m, f)):
                    work = Module([list(t) for t in m.types], list(m.fns))
                    g = copy.deepcopy(f)
                    edit = next(e for j, e in enumerate(sites(work, g)) if j == k)
                    if not edit(g):
                        continue
                    work.fns[index] = g
                    yield name, rule, f.name, work
                    made += 1
                    break


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("out")
    parser.add_argument("--per-class", type=int, default=6)
    args = parser.parse_args()
    sources = sorted(Path(args.source).rglob("*.core-ir"))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    n = 0
    for name, rule, function, module in mutants(sources, args.per_class):
        path = out / f"{name}-{n:04d}.core-ir"
        path.write_text(module.render())
        print(f"{path.name} {name} {rule} {function}")
        n += 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
