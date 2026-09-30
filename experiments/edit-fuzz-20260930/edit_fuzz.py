#!/usr/bin/env python3
"""Randomized edit-sequence differential tester for module-by-module builds.

Applies a seeded sequence of small source-level edits to a copy of a mylang
project. After every edit it builds the program twice and compares:

  1. incremental:  mylang build main.my --project      (persistent cache, early cutoff)
  2. whole:        mylang build main.my --project --whole-program   (fresh cache)

Both must succeed with byte-identical executables, or both must fail. Anything
else is a finding: a missed invalidation links stale objects. An edit that
breaks the build is reverted after the check (and the reverted state is checked
against the last good executable), so the sequence keeps moving.

    edit_fuzz.py --compiler PATH --work DIR --seed N --steps K [--source DIR]
                 [--project-kind lox|synthetic] [--gc-runtime] [--json OUT]
                 [--keep-going]
    edit_fuzz.py --compiler PATH --replay REPRO_DIR --work DIR   # re-run a reproducer
    edit_fuzz.py --compiler PATH --minimize REPRO_DIR --work DIR # shrink its edit list

Deterministic for a given (seed, project, compiler). Exit status 0 when every
step matched, 1 on any mismatch or crash. See README.md.
"""
import argparse
import copy
import difflib
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Callable, Optional

LOX_DEFAULT = ("/home/epentland/ai/canopy/mylang-worktrees/claude-rc-perf/.tmp-rc-quick/"
               "lox/benchmarks/lox/ports/mylang")

# Relative weight of each edit kind. A kind whose precondition fails (returns
# None) is re-drawn, so a weight is a preference, not a guarantee.
WEIGHTS = {
    "int-literal": 12,        # change an integer literal in a body
    "float-literal": 3,       # change a float literal in a body
    "insert-statement": 7,    # harmless statement (`_ = K`, or a local that is then used)
    "wrap-return": 7,         # `return E` -> `tmp = E` + `return tmp`
    "add-private-fn": 6,      # new private function at a random top-level position
    "add-public-fn": 6,       # new public function at a random top-level position
    "remove-added": 4,        # remove a symbol this tool added (and its use statements)
    "rename-added": 4,        # rename a symbol this tool added (and its uses)
    "add-default-param": 5,   # defaulted trailing parameter on a function
    "change-default": 3,      # change a defaulted parameter's default value
    "helper-call": 5,         # small public function now calls a new private helper
    "const-value": 6,         # change a const's value (same type)
    "add-const": 3,           # add a public/private const
    "record-field-add": 4,    # defaulted field appended to a record
    "record-field-remove": 2, # remove a field this tool added
    "change-field-default": 2,  # change a record field's default value
    "start-alloc": 4,         # a function starts allocating (build and discard a list/str)
    "stop-alloc": 3,          # a function stops allocating (undo of the above)
    "use-added": 8,           # a function starts using a tool-added symbol (adds an import if needed)
    "toggle-visibility": 3,   # public <-> private for a tool-added symbol
    "comment": 2,             # pure comment line
    "whitespace": 2,          # extra blank line / trailing spaces
    "move-function": 3,       # move a function within its file
    "noop": 1,                # no edit: the rebuild must reuse everything
    # interface edits that break dependents unless nothing uses the symbol: they exercise the
    # error path across modules (a caller nobody edited must still report the error)
    "add-required-param": 3,  # required trailing parameter on a public function
    "remove-public-fn": 3,    # delete an existing public function
    "rename-public-def": 2,   # rename an existing public function's definition only
    "change-return-type": 2,  # `-> int` becomes `-> float` (and so on)
    "drop-record-field": 2,   # remove an existing field of a record
    "break-type": 2,          # `return E` becomes a return of the wrong scalar type
}

# Chance that a function pick prefers small public functions (inline candidates).
SMALL_PUBLIC_BIAS = 0.4
BUILD_TIMEOUT = 900
SCALAR_TYPES = {"int", "float", "bool", "str", "bytes", "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64"}


# --------------------------------------------------------------------------
# source model
# --------------------------------------------------------------------------

def mask(line):
    """Blank out string-literal contents and comments, keeping every column."""
    out = []
    quote = None
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if quote:
            if c == "\\" and i + 1 < n:
                out.append("  ")
                i += 2
                continue
            out.append(c if c == quote else " ")
            if c == quote:
                quote = None
            i += 1
            continue
        if c == "#":
            out.append(" " * (n - i))
            break
        if c in "\"'":
            quote = c
        out.append(c)
        i += 1
    return "".join(out)


def bracket_delta(masked):
    return sum(masked.count(c) for c in "([{") - sum(masked.count(c) for c in ")]}")


DECL_RE = re.compile(r"^(public\s+)?(def|record|union|enum|type|const|class|interface)\s+(\w+)")
FN_RE = re.compile(r"^(public\s+)?def\s+(\w+)\s*\(")
IMPORT_RE = re.compile(r"^import\s+(\w+)\s*(?:as\s+(\w+))?\s*$")
ODD_RE = re.compile(r"\s(effects\(|noio\b|noalloc\b|nothrow\b|pure\b)")


@dataclass
class Item:
    kind: str
    name: str
    public: bool
    lead: int     # first line, comments and decorators above the declaration included
    line: int     # the declaration line
    end: int      # exclusive


@dataclass
class Fn:
    name: str
    public: bool
    lead: int
    line: int
    end: int
    open_col: int
    close_col: int
    ret: Optional[str]    # simple return type text, or None (no return type, or an effect clause)
    odd: bool             # has an effect clause after the parameters


def block_end(lines, i):
    """Exclusive end of the indented block that starts after line `i`."""
    n = len(lines)
    j = i + 1
    last = i + 1
    while j < n:
        text = lines[j]
        if text.strip() == "":
            j += 1
        elif text[0] in " \t":
            j += 1
            last = j
        elif text.startswith("#"):
            k = j
            while k < n and (lines[k].strip() == "" or lines[k].startswith("#")):
                k += 1
            if k < n and lines[k][0] in " \t":
                j = k
            else:
                break
        else:
            break
    return last


def items_of(lines):
    found = []
    i = 0
    while i < len(lines):
        text = lines[i]
        m = DECL_RE.match(text) if text and text[0] not in " \t#" else None
        if not m:
            i += 1
            continue
        lead = i
        while lead > 0 and lines[lead - 1][:1] in ("#", "@"):
            lead -= 1
        end = block_end(lines, i)
        found.append(Item(m.group(2), m.group(3), bool(m.group(1)), lead, i, end))
        i = max(end, i + 1)
    return found


def parse_fn(lines, item):
    text = lines[item.line]
    m = FN_RE.match(text)
    if not m:
        return None
    masked = mask(text)
    open_col = m.end() - 1
    depth = 0
    close = None
    for k in range(open_col, len(masked)):
        if masked[k] in "([{":
            depth += 1
        elif masked[k] in ")]}":
            depth -= 1
            if depth == 0:
                close = k
                break
    if close is None:
        return None
    rest = text[close + 1:].rstrip()
    if not rest.endswith(":"):
        return None
    odd = bool(ODD_RE.search(rest))
    ret = None
    if not odd:
        rm = re.fullmatch(r"\s*->\s*(.+?)\s*:", rest)
        if rm:
            ret = rm.group(1)
        elif rest != ":":
            odd = True
    return Fn(item.name, item.public, item.lead, item.line, item.end, open_col, close, ret, odd)


def split_top(text):
    """Split at depth-0 commas."""
    parts, depth, cur = [], 0, []
    for c in text:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(c)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return parts


class Project:
    """The mutable source of a project plus what this tool has added to it."""

    def __init__(self, files, added=None, counter=0, imports_added=None):
        self.files = files            # file name -> list of lines
        self.added = added or {}      # symbol name -> {"kind","file","public",...}
        self.counter = counter
        self.imports_added = imports_added or {}   # file -> modules this tool imported there

    def clone(self):
        return Project({k: list(v) for k, v in self.files.items()}, copy.deepcopy(self.added), self.counter,
                       copy.deepcopy(self.imports_added))

    def fresh(self, prefix):
        self.counter += 1
        return f"{prefix}{self.counter}"

    def imports(self, fname):
        found = []
        for line in self.files[fname]:
            m = IMPORT_RE.match(line)
            if m and f"{m.group(1)}.my" in self.files:
                found.append(m.group(1))
        return found

    def reachable(self):
        """File names reachable from main.my through project imports, sorted."""
        seen = set()
        todo = ["main.my"]
        while todo:
            f = todo.pop()
            if f in seen or f not in self.files:
                continue
            seen.add(f)
            todo.extend(f"{m}.my" for m in self.imports(f))
        return sorted(seen)

    def transitive(self, fname):
        seen = set()
        todo = [fname]
        while todo:
            f = todo.pop()
            if f in seen:
                continue
            seen.add(f)
            todo.extend(f"{m}.my" for m in self.imports(f))
        return seen

    def fns(self, fname):
        lines = self.files[fname]
        out = []
        for it in items_of(lines):
            if it.kind == "def":
                fn = parse_fn(lines, it)
                if fn:
                    out.append(fn)
        return out

    def all_fns(self):
        return [(f, fn) for f in self.reachable() for fn in self.fns(f)]


def to_text(lines):
    return "\n".join(lines) + "\n"


def from_text(text):
    return text.split("\n")[:-1] if text.endswith("\n") else text.split("\n")


def load_project(directory):
    files = {}
    for name in sorted(os.listdir(directory)):
        if name.endswith(".my"):
            with open(os.path.join(directory, name)) as handle:
                files[name] = from_text(handle.read())
    return Project(files)


def write_files(directory, files, names):
    for name in names:
        with open(os.path.join(directory, name), "w") as handle:
            handle.write(to_text(files[name]))


def module_of(fname):
    return fname[:-3]


# --------------------------------------------------------------------------
# shared editing helpers
# --------------------------------------------------------------------------

def body_indent(lines, fn):
    for k in range(fn.line + 1, fn.end):
        text = lines[k]
        if text.strip() and not text.lstrip().startswith("#"):
            return text[: len(text) - len(text.lstrip())]
    return "    "


STMT_SKIP_RE = re.compile(r"^\s*(else|elif|case|except|finally)\b")


def stmt_positions(lines, fn):
    """(line index, indent) where a whole statement can be inserted inside `fn`."""
    found = []
    depth = 0
    continues = False
    for k in range(fn.line + 1, fn.end):
        text = lines[k]
        masked = mask(text)
        stripped = text.strip()
        if (depth == 0 and not continues and stripped and not stripped.startswith("#")
                and stripped[0] not in ")]}" and not STMT_SKIP_RE.match(text)):
            found.append((k, text[: len(text) - len(text.lstrip())]))
        depth += bracket_delta(masked)
        continues = masked.rstrip().endswith("\\")
    return found


def boundaries(lines):
    """Line indexes where a whole top-level declaration can be inserted."""
    marks = [it.lead for it in items_of(lines)]
    marks.append(len(lines))
    return marks


def insert_block(lines, at, block):
    if at >= len(lines):
        while lines and lines[-1].strip() == "":
            lines.pop()
        lines.extend(["", ""] + block)
    else:
        lines[at:at] = block + ["", ""]


def add_import(p, fname, module):
    """Make `fname` import `module`; False when that would create a cycle."""
    if module in p.imports(fname):
        return True
    if fname in p.transitive(f"{module}.my") or fname == f"{module}.my":
        return False
    lines = p.files[fname]
    last = None
    for k, text in enumerate(lines):
        if IMPORT_RE.match(text) or text.startswith("module "):
            last = k
    lines.insert((last if last is not None else -1) + 1, f"import {module}")
    p.imports_added.setdefault(fname, []).append(module)
    return True


def drop_unused_added_imports(p, fname):
    """Remove `import M` lines this tool added to `fname` that nothing references now (an unused import warns)."""
    for module in sorted(p.imports_added.get(fname, [])):
        word = re.compile(rf"\b{re.escape(module)}\.")
        if not any(word.search(mask(text)) for text in p.files[fname]):
            p.files[fname] = [t for t in p.files[fname] if t.strip() != f"import {module}"]
            p.imports_added[fname].remove(module)


def uses_of(p, name):
    """(file, line index) of every reference to `name` outside its own declaration."""
    decl = p.added.get(name)
    skip = None
    if decl and decl["kind"] in ("fn", "const"):
        lines = p.files[decl["file"]]
        for it in items_of(lines):
            if it.name == name:
                skip = (decl["file"], it.lead, it.end)
    word = re.compile(rf"\b{re.escape(name)}\b")
    found = []
    for f in p.reachable():
        for k, text in enumerate(p.files[f]):
            if skip and f == skip[0] and skip[1] <= k < skip[2]:
                continue
            if word.search(mask(text)):
                found.append((f, k))
    return found


def use_statement_only(p, name):
    """Use lines of `name` when every use is a bare `_ = ...` statement, else None."""
    uses = uses_of(p, name)
    for f, k in uses:
        if not re.match(r"^\s*_ = ", p.files[f][k]):
            return None
    return uses


def pick(rng, seq):
    return seq[rng.randrange(len(seq))] if seq else None


def pick_fn(rng, p, pred, prefer_added=False):
    cands = [(f, fn) for f, fn in p.all_fns() if pred(f, fn)]
    if not cands:
        return None
    if prefer_added and rng.random() < 0.5:
        added = [(f, fn) for f, fn in cands if fn.name in p.added]
        if added:
            return pick(rng, added)
    if rng.random() < SMALL_PUBLIC_BIAS:
        small = [(f, fn) for f, fn in cands if fn.public and fn.end - fn.line <= 8]
        if small:
            return pick(rng, small)
    return pick(rng, cands)


def simple_return(lines, fn):
    """(index, indent, expr) for each `return EXPR` that fits on one line (no trailing comment)."""
    found = []
    for k in range(fn.line + 1, fn.end):
        text = lines[k]
        masked = mask(text)
        m = re.match(r"^(\s+)return\s+(.+?)\s*$", text)
        if m and bracket_delta(masked) == 0 and len(masked.rstrip()) == len(text.rstrip()):
            found.append((k, m.group(1), m.group(2)))
    return found


NO_INFER_RE = re.compile(r"^(None\b|Some\(|Ok\(|Err\(|\[\s*\]|\{\s*\})")


def new_int(rng, old, prefix_char):
    choices = [old + 1, old * 2 + 1, max(0, old - 1), rng.randint(0, 99)]
    value = rng.choice(choices)
    if value == old:
        value = old + 3
    if value == 0 and prefix_char in "/%":
        value = 1
    return value


# --------------------------------------------------------------------------
# edit kinds: each mutates the cloned project and returns (file, description),
# or returns None (touching nothing) when it does not apply
# --------------------------------------------------------------------------

INT_RE = re.compile(r"(?<![\w.])(\d+)(?![\w.])")
FLOAT_RE = re.compile(r"(?<![\w.])(\d+\.\d+)(?![\w.])")


def literal_edit(rng, p, regex, make_new):
    cands = [(f, fn) for f, fn in p.all_fns()]
    rng.shuffle(cands)
    for f, fn in cands:
        lines = p.files[f]
        sites = []
        for k in range(fn.line + 1, fn.end):
            if "fz_" in lines[k]:
                continue
            masked = mask(lines[k])
            for m in regex.finditer(masked):
                sites.append((k, m.start(1), m.end(1)))
        if not sites:
            continue
        k, a, b = pick(rng, sites)
        text = lines[k]
        prefix = mask(text)[:a].rstrip()[-1:]
        old, new = text[a:b], make_new(rng, text[a:b], prefix)
        lines[k] = text[:a] + new + text[b:]
        return f, f"{fn.name}: {old} -> {new}"
    return None


def k_int_literal(rng, p):
    return literal_edit(rng, p, INT_RE, lambda r, old, pre: str(new_int(r, int(old), pre)))


def k_float_literal(rng, p):
    return literal_edit(rng, p, FLOAT_RE, lambda r, old, pre: f"{r.randint(0, 9)}.{r.randint(1, 9)}")


def k_insert_statement(rng, p):
    got = pick_fn(rng, p, lambda f, fn: fn.end > fn.line + 1)
    if not got:
        return None
    f, fn = got
    lines = p.files[f]
    spots = stmt_positions(lines, fn)
    if not spots:
        return None
    k, indent = pick(rng, spots)
    if rng.random() < 0.5:
        block = [f"{indent}_ = {rng.randint(0, 99)}"]
    else:
        name = p.fresh("fz_v")
        block = [f"{indent}{name} = {rng.randint(0, 99)}", f"{indent}_ = {name} + 1"]
    lines[k:k] = block
    return f, f"{fn.name}: insert {len(block)} statement(s)"


def k_wrap_return(rng, p):
    cands = []
    for f, fn in p.all_fns():
        if fn.ret is None or fn.ret.startswith(("Option[", "Result[")):
            continue
        for k, indent, expr in simple_return(p.files[f], fn):
            if not NO_INFER_RE.match(expr):
                cands.append((f, fn, k, indent, expr))
    if not cands:
        return None
    f, fn, k, indent, expr = pick(rng, cands)
    name = p.fresh("fz_r")
    p.files[f][k:k + 1] = [f"{indent}{name} = {expr}", f"{indent}return {name}"]
    return f, f"{fn.name}: wrap return"


def add_fn_lines(rng, p, f, public):
    """A new `(n: int) -> int` function; may call an earlier tool-added function."""
    name = p.fresh("fz_fn_")
    k = rng.randint(1, 30)
    callee = None
    chain = [(s, d) for s, d in sorted(p.added.items())
             if d["kind"] == "fn" and s != name and (d["file"] == f or d["public"])]
    if chain and rng.random() < 0.3:
        callee = pick(rng, chain)
    if callee:
        sym, d = callee
        if d["file"] != f:
            if not add_import(p, f, module_of(d["file"])):
                callee = None
    if callee:
        qual = sym if d["file"] == f else f"{module_of(d['file'])}.{sym}"
        body = [f"    return {qual}(n) + {k}"]
    else:
        body = pick(rng, [
            [f"    return n + {k}"],
            [f"    if n > {k}:", f"        return n - {k}", "    return n"],
            ["    acc = 0", f"    for v in [n, {k}]:", "        acc += v", "    return acc"],
            [f"    return n * {k} + 1"],
        ])
    vis = "public " if public else ""
    block = [f"{vis}def {name}(n: int) -> int:"] + body
    insert_block(p.files[f], pick(rng, boundaries(p.files[f])), block)
    p.added[name] = {"kind": "fn", "file": f, "public": public}
    return name


def k_add_private_fn(rng, p):
    f = pick(rng, p.reachable())
    name = add_fn_lines(rng, p, f, False)
    return f, f"add private {name}"


def k_add_public_fn(rng, p):
    f = pick(rng, p.reachable())
    name = add_fn_lines(rng, p, f, True)
    return f, f"add public {name}"


def k_remove_added(rng, p):
    cands = []
    for name, d in sorted(p.added.items()):
        if d["kind"] in ("fn", "const"):
            uses = use_statement_only(p, name)
            if uses is not None:
                cands.append((name, d, uses))
        elif d["kind"] == "field":
            cands.append((name, d, []))
    if not cands:
        return None
    name, d, uses = pick(rng, cands)
    # drop use statements bottom-up so earlier indexes stay valid
    for f, k in sorted(uses, key=lambda t: (t[0], -t[1])):
        del p.files[f][k]
    for f in sorted({f for f, _ in uses}):
        drop_unused_added_imports(p, f)
    lines = p.files[d["file"]]
    if d["kind"] == "field":
        for k, text in enumerate(lines):
            if re.match(rf"^\s+{re.escape(name)}\s*:", text):
                del lines[k]
                break
    else:
        for it in items_of(lines):
            if it.name == name:
                del lines[it.lead:it.end]
                while it.lead < len(lines) and it.lead >= 2 and lines[it.lead - 1] == "" and lines[it.lead - 2] == "" and lines[it.lead] == "":
                    del lines[it.lead]
                break
    del p.added[name]
    return d["file"], f"remove {name} and {len(uses)} use(s)"


def k_rename_added(rng, p):
    cands = [(s, d) for s, d in sorted(p.added.items()) if d["kind"] in ("fn", "const", "helper")]
    if not cands:
        return None
    name, d = pick(rng, cands)
    new = p.fresh("FZ_C_" if d["kind"] == "const" else "fz_fn_")
    word = re.compile(rf"\b{re.escape(name)}\b")
    for f in p.reachable():
        p.files[f] = [word.sub(new, text) for text in p.files[f]]
    p.added[new] = p.added.pop(name)
    return d["file"], f"rename {name} -> {new}"


def k_add_default_param(rng, p):
    got = pick_fn(rng, p, lambda f, fn: fn.public and fn.name != "main", prefer_added=True)
    if not got:
        return None
    f, fn = got
    lines = p.files[f]
    text = lines[fn.line]
    inner = text[fn.open_col + 1:fn.close_col]
    param = p.fresh("fz_p")
    piece = f"{param}: int = 0"
    text = text[:fn.close_col] + (", " if inner.strip() else "") + piece + text[fn.close_col:]
    lines[fn.line] = text
    k = fn.line + 1
    while lines[k].strip() == "" or lines[k].lstrip().startswith("#"):
        k += 1
    lines.insert(k, f"{body_indent(lines, fn)}_ = {param}")      # read it: an unused binding warns
    p.added[param] = {"kind": "param", "file": f, "public": True, "fn": fn.name}
    return f, f"{fn.name}: add {piece}"


PARAM_DEFAULT_RE = re.compile(r"(\w+)\s*:\s*(?:int|u32|u8|i32)\s*=\s*(-?\d+)\s*$")


def k_change_default(rng, p):
    cands = []
    for f, fn in p.all_fns():
        text = p.files[f][fn.line]
        inner = text[fn.open_col + 1:fn.close_col]
        offset = fn.open_col + 1
        for part in split_top(inner):
            m = PARAM_DEFAULT_RE.search(part)
            if m:
                a = offset + m.start(2)
                b = offset + m.end(2)
                cands.append((f, fn, a, b, m.group(1)))
            offset += len(part) + 1
    if not cands:
        return None
    f, fn, a, b, param = pick(rng, cands)
    text = p.files[f][fn.line]
    old = int(text[a:b])
    new = old + rng.randint(1, 9)
    p.files[f][fn.line] = text[:a] + str(new) + text[b:]
    return f, f"{fn.name}: default {param} {old} -> {new}"


def k_helper_call(rng, p):
    cands = []
    for f, fn in p.all_fns():
        if not fn.public or fn.ret not in SCALAR_TYPES or fn.end - fn.line > 14:
            continue
        for k, indent, expr in simple_return(p.files[f], fn):
            if not NO_INFER_RE.match(expr):
                cands.append((f, fn, k, indent, expr))
    if not cands:
        return None
    f, fn, k, indent, expr = pick(rng, cands)
    name = p.fresh("fz_help_")
    t = fn.ret
    lines = p.files[f]
    lines[k] = f"{indent}return {name}({expr})"
    body = "    return x" if rng.random() < 0.5 or t != "int" else f"    return x + {rng.randint(1, 9)}"
    insert_block(lines, pick(rng, boundaries(lines)), [f"def {name}(x: {t}) -> {t}:", body])
    p.added[name] = {"kind": "helper", "file": f, "public": False}
    return f, f"{fn.name}: return now goes through {name}"


CONST_RE = re.compile(r"^(public\s+)?const\s+(\w+)\s*:\s*(int|float|bool|str|bytes)\s*=\s*(.+?)\s*$")


def k_const_value(rng, p):
    cands = []
    for f in p.reachable():
        for k, text in enumerate(p.files[f]):
            m = CONST_RE.match(text)
            if not m:
                continue
            t, v = m.group(3), m.group(4)
            ok = ((t == "int" and re.fullmatch(r"-?\d+", v)) or (t == "float" and re.fullmatch(r"\d+\.\d+", v))
                  or (t == "bool" and v in ("True", "False"))
                  or (t in ("str", "bytes") and re.fullmatch(r'b?"[^"\\]*"', v)))
            if ok:
                cands.append((f, k, m))
    if not cands:
        return None
    f, k, m = pick(rng, cands)
    t, v = m.group(3), m.group(4)
    if t == "int":
        new = str(new_int(rng, abs(int(v)), ""))
    elif t == "float":
        new = f"{rng.randint(0, 9)}.{rng.randint(1, 9)}"
    elif t == "bool":
        new = "False" if v == "True" else "True"
    else:
        prefix = "b" if v.startswith("b") else ""
        new = f'{prefix}"{v.strip("b").strip(chr(34))}{rng.choice("xyz")}"'
    p.files[f][k] = re.sub(r"=\s*.+$", f"= {new}", p.files[f][k])
    return f, f"const {m.group(2)}: {v} -> {new}"


def k_add_const(rng, p):
    f = pick(rng, p.reachable())
    name = p.fresh("FZ_C_")
    public = rng.random() < 0.6
    t, v = pick(rng, [("int", str(rng.randint(0, 99))), ("float", f"{rng.randint(0, 9)}.{rng.randint(1, 9)}"),
                      ("bytes", 'b"fz"'), ("bool", "True")])
    line = f"{'public ' if public else ''}const {name}: {t} = {v}"
    lines = p.files[f]
    insert_block(lines, pick(rng, boundaries(lines)), [line])
    p.added[name] = {"kind": "const", "file": f, "public": public, "type": t}
    return f, f"add {line}"


def record_items(p):
    out = []
    for f in p.reachable():
        lines = p.files[f]
        for it in items_of(lines):
            if it.kind != "record":
                continue
            body = [text for text in lines[it.line + 1:it.end] if text.strip() and not text.lstrip().startswith("#")]
            if body and all(re.match(r"^\s+\w+\s*:\s*\S", text) for text in body):
                out.append((f, it))
    return out


def k_record_field_add(rng, p):
    cands = [(f, it) for f, it in record_items(p)
             if sum(1 for text in p.files[f][it.line:it.end] if "fz_f" in text) < 3]
    if not cands:
        return None
    f, it = pick(rng, cands)
    lines = p.files[f]
    last = max(k for k in range(it.line + 1, it.end) if lines[k].strip() and not lines[k].lstrip().startswith("#"))
    indent = lines[last][: len(lines[last]) - len(lines[last].lstrip())]
    name = p.fresh("fz_f")
    t, v = pick(rng, [("int", str(rng.randint(0, 99))), ("bool", "False"), ("str", '"x"')])
    lines.insert(last + 1, f"{indent}{name}: {t} = {v}")
    p.added[name] = {"kind": "field", "file": f, "public": True}
    return f, f"record {it.name}: add {name}: {t} = {v}"


def k_record_field_remove(rng, p):
    cands = [(n, d) for n, d in sorted(p.added.items()) if d["kind"] == "field"]
    if not cands:
        return None
    name, d = pick(rng, cands)
    lines = p.files[d["file"]]
    for k, text in enumerate(lines):
        if re.match(rf"^\s+{re.escape(name)}\s*:", text):
            del lines[k]
            del p.added[name]
            return d["file"], f"remove field {name}"
    return None


FIELD_DEFAULT_RE = re.compile(r"^(\s+)(\w+)\s*:\s*(int|bool|str|bytes)\s*=\s*(.+?)\s*$")


def k_change_field_default(rng, p):
    cands = []
    for f, it in record_items(p):
        for k in range(it.line + 1, it.end):
            m = FIELD_DEFAULT_RE.match(p.files[f][k])
            if m and (m.group(3) != "int" or re.fullmatch(r"-?\d+", m.group(4))) \
                    and (m.group(3) not in ("str", "bytes") or re.fullmatch(r'b?"[^"\\]*"', m.group(4))) \
                    and (m.group(3) != "bool" or m.group(4) in ("True", "False")):
                cands.append((f, it, k, m))
    if not cands:
        return None
    f, it, k, m = pick(rng, cands)
    t, v = m.group(3), m.group(4)
    if t == "int":
        new = str(new_int(rng, abs(int(v)), ""))
    elif t == "bool":
        new = "False" if v == "True" else "True"
    else:
        prefix = "b" if v.startswith("b") else ""
        new = f'{prefix}"{v.lstrip("b").strip(chr(34))}{rng.choice("xyz")}"'
    p.files[f][k] = f"{m.group(1)}{m.group(2)}: {t} = {new}"
    return f, f"record {it.name}.{m.group(2)} default {v} -> {new}"


def k_start_alloc(rng, p):
    got = pick_fn(rng, p, lambda f, fn: fn.end > fn.line + 1 and not fn.odd)
    if not got:
        return None
    f, fn = got
    lines = p.files[f]
    if rng.random() < 0.5:
        spots = stmt_positions(lines, fn)
        if not spots:
            return None
        k, indent = pick(rng, spots)
    else:
        k, indent = fn.line + 1, body_indent(lines, fn)
        while lines[k].strip() == "" or lines[k].lstrip().startswith("#"):
            k += 1
    name = p.fresh("fz_a")
    block = pick(rng, [
        [f"{indent}{name}: list[int] = [{rng.randint(0, 9)}, {rng.randint(0, 9)}]", f"{indent}_ = len({name})"],
        [f"{indent}{name} = str({rng.randint(0, 99)})", f"{indent}_ = len({name})"],
        [f"{indent}{name}: list[int] = []", f"{indent}{name}.append({rng.randint(0, 9)})", f"{indent}_ = len({name})"],
    ])
    lines[k:k] = block
    return f, f"{fn.name}: start allocating ({name})"


def k_stop_alloc(rng, p):
    cands = []
    for f in p.reachable():
        for k, text in enumerate(p.files[f]):
            m = re.match(r"^\s+(fz_a\d+)\b", text)
            if m:
                cands.append((f, m.group(1)))
    names = sorted({(f, n) for f, n in cands})
    if not names:
        return None
    f, name = pick(rng, names)
    word = re.compile(rf"\b{name}\b")
    p.files[f] = [text for text in p.files[f] if not word.search(text)]
    return f, f"stop allocating ({name})"


def call_arguments(rng, p, name):
    """Arguments for a call of tool-added `name`: the required int, then some of its defaulted parameters."""
    home = p.added[name]["file"]
    args = [str(rng.randint(0, 9))]
    for fn in p.fns(home):
        if fn.name == name:
            inner = p.files[home][fn.line][fn.open_col + 1:fn.close_col]
            defaulted = [part for part in split_top(inner) if "=" in part]
            args += [str(rng.randint(0, 9)) for _ in range(rng.randint(0, len(defaulted)))]
    return ", ".join(args)


def k_use_added(rng, p):
    cands = [(s, d) for s, d in sorted(p.added.items()) if d["kind"] in ("fn", "const")]
    if not cands:
        return None
    name, d = pick(rng, cands)
    home = d["file"]
    consumers = [home]
    if d["public"]:
        below = p.transitive(home)
        consumers += [f for f in p.reachable() if f != home and f not in below]
        consumers += [f for f in p.reachable() if f != home and f in below and module_of(home) in p.imports(f)]
    consumer = pick(rng, sorted(set(consumers)))
    got = [fn for fn in p.fns(consumer) if fn.end > fn.line + 1]
    if not got:
        return None
    fn = pick(rng, got)
    if consumer != home and not add_import(p, consumer, module_of(home)):
        return None
    lines = p.files[consumer]
    fn = next(x for x in p.fns(consumer) if x.name == fn.name)      # imports shifted the lines
    spots = stmt_positions(lines, fn)
    if not spots:
        return None
    k, indent = pick(rng, spots)
    qual = name if consumer == home else f"{module_of(home)}.{name}"
    stmt = f"{indent}_ = {qual}" if d["kind"] == "const" else f"{indent}_ = {qual}({call_arguments(rng, p, name)})"
    lines.insert(k, stmt)
    return consumer, f"{fn.name}: use {qual}"


def k_toggle_visibility(rng, p):
    cands = []
    for name, d in sorted(p.added.items()):
        if d["kind"] not in ("fn", "const"):
            continue
        if not d["public"]:
            cands.append((name, d))
        elif all(f == d["file"] for f, _ in uses_of(p, name)):
            cands.append((name, d))
    if not cands:
        return None
    name, d = pick(rng, cands)
    lines = p.files[d["file"]]
    for it in items_of(lines):
        if it.name == name:
            text = lines[it.line]
            lines[it.line] = text[len("public "):] if it.public else "public " + text
            d["public"] = not it.public
            return d["file"], f"{name}: now {'public' if d['public'] else 'private'}"
    return None


def k_comment(rng, p):
    f = pick(rng, p.reachable())
    lines = p.files[f]
    note = f"# fz note {p.fresh('')}"
    if rng.random() < 0.5:
        insert_block(lines, pick(rng, boundaries(lines)), [note])
        return f, "comment at top level"
    got = pick(rng, [fn for fn in p.fns(f) if fn.end > fn.line + 1])
    if not got:
        return None
    spots = stmt_positions(lines, got)
    if not spots:
        return None
    k, indent = pick(rng, spots)
    lines.insert(k, f"{indent}{note}")
    return f, f"{got.name}: comment"


def k_whitespace(rng, p):
    f = pick(rng, p.reachable())
    lines = p.files[f]
    if rng.random() < 0.5:
        lines.insert(pick(rng, boundaries(lines)), "")
        return f, "extra blank line at top level"
    cands = [k for k, text in enumerate(lines) if text.strip() and not text.endswith((" ", "\\"))]
    k = pick(rng, cands)
    lines[k] = lines[k] + "  "
    return f, f"trailing spaces on line {k + 1}"


def k_move_function(rng, p):
    f = pick(rng, p.reachable())
    lines = p.files[f]
    fns = p.fns(f)
    if len(fns) < 1:
        return None
    fn = pick(rng, fns)
    block = lines[fn.lead:fn.end]
    rest = lines[:fn.lead] + lines[fn.end:]
    while fn.lead < len(rest) and fn.lead >= 2 and rest[fn.lead - 1] == "" and rest[fn.lead - 2] == "" and rest[fn.lead] == "":
        del rest[fn.lead]
    insert_block(rest, pick(rng, boundaries(rest)), block)
    if rest == lines:
        return None
    p.files[f] = rest
    return f, f"move {fn.name}"


def k_add_required_param(rng, p):
    got = pick_fn(rng, p, lambda f, fn: fn.public and fn.name != "main" and fn.name not in p.added
                  and "=" not in p.files[f][fn.line][fn.open_col:fn.close_col])
    if not got:
        return None
    f, fn = got
    lines = p.files[f]
    text = lines[fn.line]
    inner = text[fn.open_col + 1:fn.close_col]
    param = p.fresh("fz_rq")
    lines[fn.line] = text[:fn.close_col] + (", " if inner.strip() else "") + f"{param}: int" + text[fn.close_col:]
    k = fn.line + 1
    while lines[k].strip() == "" or lines[k].lstrip().startswith("#"):
        k += 1
    lines.insert(k, f"{body_indent(lines, fn)}_ = {param}")
    return f, f"{fn.name}: add required {param}"


def public_existing(p):
    return [(f, fn) for f, fn in p.all_fns() if fn.public and fn.name != "main" and fn.name not in p.added]


def k_remove_public_fn(rng, p):
    got = pick(rng, public_existing(p))
    if not got:
        return None
    f, fn = got
    del p.files[f][fn.lead:fn.end]
    return f, f"remove public {fn.name}"


def k_rename_public_def(rng, p):
    got = pick(rng, public_existing(p))
    if not got:
        return None
    f, fn = got
    new = p.fresh(f"{fn.name}_r")
    text = p.files[f][fn.line]
    p.files[f][fn.line] = re.sub(rf"\bdef\s+{re.escape(fn.name)}\b", f"def {new}", text, count=1)
    return f, f"rename definition {fn.name} -> {new}"


def k_change_return_type(rng, p):
    cands = [(f, fn) for f, fn in p.all_fns() if fn.ret in ("int", "float", "bool", "bytes", "str") and fn.name != "main"]
    got = pick(rng, cands)
    if not got:
        return None
    f, fn = got
    new = pick(rng, [t for t in ("int", "float", "bool", "bytes", "str") if t != fn.ret])
    text = p.files[f][fn.line]
    p.files[f][fn.line] = text[:text.rindex("->")] + f"-> {new}:"
    return f, f"{fn.name}: return type {fn.ret} -> {new}"


def k_drop_record_field(rng, p):
    cands = []
    for f, it in record_items(p):
        for k in range(it.line + 1, it.end):
            if p.files[f][k].strip() and "fz_f" not in p.files[f][k] and "=" not in p.files[f][k] \
                    and sum(1 for t in p.files[f][it.line + 1:it.end] if t.strip()) > 1:
                cands.append((f, it, k))
    got = pick(rng, cands)
    if not got:
        return None
    f, it, k = got
    gone = p.files[f][k].strip()
    del p.files[f][k]
    return f, f"record {it.name}: drop `{gone}`"


WRONG = {"int": "True", "bool": "1", "float": "True", "bytes": "1", "str": "1"}


def k_break_type(rng, p):
    cands = []
    for f, fn in p.all_fns():
        if fn.ret in WRONG:
            for k, indent, expr in simple_return(p.files[f], fn):
                cands.append((f, fn, k, indent))
    got = pick(rng, cands)
    if not got:
        return None
    f, fn, k, indent = got
    p.files[f][k] = f"{indent}return {WRONG[fn.ret]}"
    return f, f"{fn.name}: return of the wrong type"


def k_noop(rng, p):
    return "-", "no edit"


EDIT_KINDS: dict[str, Callable] = {
    "int-literal": k_int_literal, "float-literal": k_float_literal,
    "insert-statement": k_insert_statement, "wrap-return": k_wrap_return,
    "add-private-fn": k_add_private_fn, "add-public-fn": k_add_public_fn,
    "remove-added": k_remove_added, "rename-added": k_rename_added,
    "add-default-param": k_add_default_param, "change-default": k_change_default,
    "helper-call": k_helper_call, "const-value": k_const_value, "add-const": k_add_const,
    "record-field-add": k_record_field_add, "record-field-remove": k_record_field_remove,
    "change-field-default": k_change_field_default,
    "start-alloc": k_start_alloc, "stop-alloc": k_stop_alloc, "use-added": k_use_added,
    "toggle-visibility": k_toggle_visibility, "comment": k_comment, "whitespace": k_whitespace,
    "move-function": k_move_function, "noop": k_noop,
    "add-required-param": k_add_required_param, "remove-public-fn": k_remove_public_fn,
    "rename-public-def": k_rename_public_def, "change-return-type": k_change_return_type,
    "drop-record-field": k_drop_record_field, "break-type": k_break_type,
}


EXCLUDED = set()     # kinds switched off by --exclude-kinds (a known bug's trigger)


def choose_edit(rng, proj):
    """Draw kinds by weight until one applies; returns (kind, trial project, file, description)."""
    kinds = sorted(k for k in WEIGHTS if k not in EXCLUDED)
    for _ in range(40):
        kind = rng.choices(kinds, weights=[WEIGHTS[k] for k in kinds])[0]
        trial = proj.clone()
        got = EDIT_KINDS[kind](rng, trial)
        if got:
            return kind, trial, got[0], got[1]
    raise SystemExit("no edit kind applied after 40 draws")


# --------------------------------------------------------------------------
# building and comparing
# --------------------------------------------------------------------------

ERROR_RE = re.compile(r"^(\S+?:\d+:\d+): error\[(\w+)\]", re.M)
PANIC_RE = re.compile(r"(^|thread \d+ )panic: ", re.MULTILINE)


@dataclass
class Built:
    rc: int
    seconds: float
    stdout: str
    stderr: str
    timed_out: bool

    @property
    def ok(self):
        return self.rc == 0 and not self.timed_out

    @property
    def counts(self):
        m = re.search(r'"module_build":(\{[^}]*\})', self.stdout)
        return json.loads(m.group(1)) if m else None

    @property
    def diagnostics(self):
        return sorted(set(ERROR_RE.findall(self.stderr + self.stdout)))

    @property
    def crashed(self):
        # A Zig panic prints "panic: ..." (after "thread N " when threaded). A bare
        # substring test would flag ordinary diagnostics that quote a name such as
        # the Lox port's `panic_mode` field.
        text = self.stderr + self.stdout
        return self.timed_out or self.rc not in (0, 1) or "host failure" in text or PANIC_RE.search(text) is not None

    def excerpt(self, limit=500):
        if self.ok:
            return "built ok"
        lines = [l for l in (self.stderr + "\n" + self.stdout).splitlines() if "error" in l or "failure" in l or "panic" in l.lower()]
        return ("\n".join(lines) or (self.stderr + self.stdout))[:limit]


def run_build(compiler, project, output, cache, extra):
    if os.path.exists(output):
        os.remove(output)
    args = [compiler, "build", "main.my", "--project", "-o", output, f"--cache-dir={cache}", "--report"] + extra
    start = time.monotonic()
    try:
        done = subprocess.run(args, cwd=project, capture_output=True, text=True, errors="replace", timeout=BUILD_TIMEOUT)
        return Built(done.returncode, time.monotonic() - start, done.stdout, done.stderr, False)
    except subprocess.TimeoutExpired:
        return Built(-9, time.monotonic() - start, "", "timeout", True)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


class Rig:
    """Owns the working copy, the persistent incremental cache and the fresh whole-program builds."""

    def __init__(self, compiler, work, extra):
        self.compiler = compiler
        self.work = work
        self.extra = extra
        self.project = os.path.join(work, "project")
        self.out = os.path.join(work, "out")
        self.inc_cache = os.path.join(work, "cache-inc")
        self.whole_cache = os.path.join(work, "cache-whole")
        os.makedirs(self.out, exist_ok=True)

    def incremental(self):
        return run_build(self.compiler, self.project, os.path.join(self.out, "inc"), self.inc_cache, self.extra)

    def whole(self):
        shutil.rmtree(self.whole_cache, ignore_errors=True)
        built = run_build(self.compiler, self.project, os.path.join(self.out, "whole"), self.whole_cache,
                          self.extra + ["--whole-program"])
        shutil.rmtree(self.whole_cache, ignore_errors=True)
        return built

    def compare(self):
        """Build both ways; returns (incremental, whole, verdict, digest of the executable or None)."""
        inc = self.incremental()
        whole = self.whole()
        if inc.ok and whole.ok:
            a, b = digest(os.path.join(self.out, "inc")), digest(os.path.join(self.out, "whole"))
            return inc, whole, ("match" if a == b else "binary-differs"), a
        if not inc.ok and not whole.ok:
            return inc, whole, "both-failed", None
        return inc, whole, ("incremental-failed" if not inc.ok else "whole-failed"), None


# --------------------------------------------------------------------------
# reproducers, replay and minimisation
# --------------------------------------------------------------------------

def unified(old_lines, new_lines, name):
    return "".join(difflib.unified_diff([l + "\n" for l in old_lines], [l + "\n" for l in new_lines],
                                        f"a/{name}", f"b/{name}"))


def patch_of(old, new):
    parts = [unified(old.files[n], new.files[n], n) for n in sorted(new.files) if old.files.get(n) != new.files[n]]
    return "".join(parts)


REPLAY_SH = r"""#!/bin/sh
# Replays the recorded edit sequence and, after the original state and after every
# edit, builds incrementally (persistent cache) and whole-program (fresh cache) and
# compares. usage: replay.sh COMPILER WORKDIR [--gc-runtime]
set -u
COMPILER=$1; WORK=$2; EXTRA=${3:-}
HERE=$(cd "$(dirname "$0")" && pwd)
rm -rf "$WORK"; mkdir -p "$WORK/out"; cp -rL "$HERE/original" "$WORK/project"; cd "$WORK/project"
check() {
  rm -f "$WORK/out/inc" "$WORK/out/whole"
  "$COMPILER" build main.my --project -o "$WORK/out/inc" --cache-dir="$WORK/cache-inc" --report $EXTRA >"$WORK/inc.log" 2>&1; ri=$?
  rm -rf "$WORK/cache-whole"
  "$COMPILER" build main.my --project --whole-program -o "$WORK/out/whole" --cache-dir="$WORK/cache-whole" $EXTRA >"$WORK/whole.log" 2>&1; rw=$?
  compiled=$(grep -o '"module_build":{[^}]*}' "$WORK/inc.log" || true)
  if [ $ri -eq 0 ] && [ $rw -eq 0 ]; then
    if cmp -s "$WORK/out/inc" "$WORK/out/whole"; then echo "$1: MATCH $compiled"; else echo "$1: MISMATCH (binaries differ) $compiled"; fi
  elif [ $ri -ne 0 ] && [ $rw -ne 0 ]; then echo "$1: both failed (matches)"
  else echo "$1: MISMATCH (incremental exit $ri, whole exit $rw)"; fi
}
check original
for p in "$HERE"/edits/*.patch; do
  patch -p1 -s -F0 < "$p" || { echo "$p does not apply"; exit 3; }
  check "$(basename "$p")"
done
"""


def save_reproducer(dest, original_dir, timeline, header):
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(os.path.join(dest, "edits"))
    shutil.copytree(original_dir, os.path.join(dest, "original"))
    for i, entry in enumerate(timeline, 1):
        with open(os.path.join(dest, "edits", f"{i:03d}-{entry['label']}-{entry['kind']}.patch"), "w") as handle:
            handle.write(entry["patch"])
    with open(os.path.join(dest, "replay.sh"), "w") as handle:
        handle.write(REPLAY_SH)
    os.chmod(os.path.join(dest, "replay.sh"), 0o755)
    with open(os.path.join(dest, "timeline.json"), "w") as handle:
        json.dump({"header": header, "timeline": [{k: v for k, v in e.items() if k != "patch"} for e in timeline]}, handle, indent=1)


def load_reproducer(directory):
    entries = []
    with open(os.path.join(directory, "timeline.json")) as handle:
        meta = json.load(handle)
    names = sorted(os.listdir(os.path.join(directory, "edits")))
    for name, info in zip(names, meta["timeline"]):
        with open(os.path.join(directory, "edits", name)) as handle:
            entries.append(dict(info, patch=handle.read()))
    return meta["header"], entries


def apply_patch(project, patch):
    done = subprocess.run(["patch", "-p1", "-s", "-F0", "--no-backup-if-mismatch"], cwd=project, input=patch,
                          capture_output=True, text=True)
    return done.returncode == 0


BAD_VERDICTS = ("binary-differs", "incremental-failed", "whole-failed")


def replay(compiler, work, original, patches, extra, every_state):
    """Replay `patches` one by one over a fresh copy of `original`.

    An incremental build follows every patch (the cache state matters); the
    whole-program comparison runs after every patch when `every_state`, else only
    after the last. Returns the first bad verdict, else the last verdict."""
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    shutil.copytree(original, os.path.join(work, "project"))
    rig = Rig(compiler, work, extra)
    verdict = rig.compare()[2]
    for i, patch in enumerate(patches):
        if not apply_patch(rig.project, patch):
            return "does-not-apply"
        if every_state or i == len(patches) - 1:
            verdict = rig.compare()[2]
            if verdict in BAD_VERDICTS:
                return verdict
        else:
            rig.incremental()
    return verdict


def minimize(compiler, work, repro, extra, log):
    """Delta-debug a reproducer's patch list down to a smaller ordered subset that still misbehaves.

    A failed edit and its revert form one unit. Returns (reproduces, entries): the surviving
    timeline entries in order."""
    _, entries = load_reproducer(repro)
    original = os.path.join(repro, "original")
    units, i = [], 0
    while i < len(entries):
        unit = [entries[i]]
        if entries[i]["label"] == "edit" and i + 1 < len(entries) and entries[i + 1]["label"] == "revert":
            unit.append(entries[i + 1])
            i += 1
        units.append(unit)
        i += 1
    trials = [0]

    def bad(subset):
        trials[0] += 1
        patches = [e["patch"] for unit in subset for e in unit]
        verdict = replay(compiler, os.path.join(work, "min"), original, patches, extra, every_state=False)
        log(f"  trial {trials[0]}: {len(subset)} unit(s) -> {verdict}")
        return verdict in BAD_VERDICTS

    if not bad(units):
        return False, [e for unit in units for e in unit]
    n = 2
    while len(units) >= 2:
        size = max(1, len(units) // n)
        chunks = [units[k:k + size] for k in range(0, len(units), size)]
        reduced = False
        for k in range(len(chunks)):
            complement = [u for j, c in enumerate(chunks) if j != k for u in c]
            if complement and bad(complement):
                units, n, reduced = complement, max(n - 1, 2), True
                break
        if not reduced:
            if n >= len(units):
                break
            n = min(len(units), n * 2)
    return True, [e for unit in units for e in unit]


# --------------------------------------------------------------------------
# synthetic project
# --------------------------------------------------------------------------

def gen_synthetic(seed, dest):
    """Write a small valid multi-module project: 6-10 modules in a chain/diamond/layered import graph."""
    r = random.Random(f"synthetic-{seed}")
    n = r.randint(5, 9)
    shape = r.choice(["chain", "diamond", "layered"])
    deps = {0: []}
    for i in range(1, n):
        if shape == "chain":
            deps[i] = [i - 1]
        elif shape == "diamond":
            pool = list(range(max(0, i - 3), i))
            deps[i] = sorted(r.sample(pool, min(len(pool), 2 if i >= 2 else 1)))
        else:
            deps[i] = sorted(r.sample(range(i), r.randint(1, min(3, i))))
    imported = {d for ds in deps.values() for d in ds}
    sinks = [i for i in range(n) if i not in imported]
    os.makedirs(dest, exist_ok=True)
    for i in range(n):
        base, limit = r.randint(2, 40), r.randint(20, 90)
        scale = f"{r.randint(1, 4)}.{r.randint(1, 9)}"
        out = [f"module m{i}"]
        out += [f"import m{d}" for d in deps[i]]
        out += [
            "", f"public const M{i}_BASE: int = {base}", f"public const M{i}_SCALE: float = {scale}",
            f'public const M{i}_TAG: bytes = b"m{i}"', f"const M{i}_LIMIT: int = {limit}", "",
            f"public enum Kind{i}:", "    ALPHA,", "    BETA,", "    GAMMA", "",
            f"public union Shape{i}:", "    empty,", "    circle: int,", "    box: int", "",
            f"public record Rec{i}:", "    id: int", "    weight: int", "    ratio: float", "    label: bytes", "",
            f"public def small{i}(x: int) -> int:", f"    return x + M{i}_BASE", "",
            f"public def scale{i}(x: float) -> float:", f"    return x * M{i}_SCALE", "",
            f"def clamp{i}(x: int) -> int:", f"    if x > M{i}_LIMIT:", f"        return M{i}_LIMIT", "    return x", "",
            f"public def make{i}(seed: int) -> Rec{i}:",
            f"    return Rec{i}(id=clamp{i}(seed), weight=small{i}(seed), ratio=scale{i}(1.5), label=M{i}_TAG)", "",
            f"public def kind{i}(r: Rec{i}) -> Kind{i}:", "    if r.weight > 10:", f"        return Kind{i}.ALPHA",
            "    elif r.weight > 5:", f"        return Kind{i}.BETA", f"    return Kind{i}.GAMMA", "",
            f"public def area{i}(s: Shape{i}) -> int:", "    match s:", f"        case Shape{i}.empty:", "            return 0",
            f"        case Shape{i}.circle(radius):", "            return radius * radius * 3",
            f"        case Shape{i}.box(width):", "            return width * width", "",
            f"public def score{i}(r: Rec{i}) -> int:", f"    k = kind{i}(r)", "    match k:", f"        case Kind{i}.ALPHA:",
            "            return r.weight * 3", f"        case Kind{i}.BETA:", "            return r.weight * 2",
            f"        case Kind{i}.GAMMA:", "            return r.weight", "",
            f"public def fill{i}(count: int) -> list[int]:", "    out: list[int] = []", "    idx = 0", "    while idx < count:",
            f"        out.append(idx * M{i}_BASE)", "        idx += 1", "    return out", "",
            f"public def bump{i}(r: mut Rec{i}, by: int):", "    r.weight = r.weight + by", "",
        ]
        for d in deps[i]:
            out += [
                f"public def combine{i}_{d}(x: int) -> int:", f"    r = m{d}.make{d}(x)",
                f"    return m{d}.score{d}(r) + m{d}.small{d}(x) + m{d}.M{d}_BASE", "",
                f"public def mix{i}_{d}(r: m{d}.Rec{d}) -> int:", "    return r.id + r.weight + len(r.label)", "",
                f"public def pick{i}_{d}(x: int) -> m{d}.Kind{d}:", f"    r = m{d}.make{d}(x)", f"    return m{d}.kind{d}(r)", "",
                f"public def shape{i}_{d}(x: int) -> int:", f"    return m{d}.area{d}(m{d}.Shape{d}.circle(x))", "",
                # small and public: dependents of `i` take it inlined, and it builds a record `i` does
                # not export a signature for, so a layout change of that record must reach them too
                f"public def probe{i}_{d}(x: int) -> int:", f"    r = m{d}.make{d}(x)", "    return len(r.label) + x", "",
            ]
        out += [f"public def total{i}(count: int) -> int:", "    acc = 0", f"    for v in fill{i}(count):", "        acc += v"]
        out += [f"    acc += score{i}(make{i}(count))"]
        for d in deps[i]:
            out += [f"    acc += combine{i}_{d}(count) + shape{i}_{d}(count)"]
            out += [f"    acc += m{d}.probe{d}_{e}(count)" for e in deps[d]]
        out += ["    return acc", ""]
        with open(os.path.join(dest, f"m{i}.my"), "w") as handle:
            handle.write("\n".join(out))
    mains = sorted(set(sinks) | set(r.sample(range(n), min(n, 3))))
    out = ["module main"] + [f"import m{i}" for i in mains] + ["", "def main() -> int:", "    acc = 0"]
    for i in mains:
        out += [f"    acc += m{i}.total{i}(3)", f"    rec{i} = m{i}.make{i}(4)", f"    m{i}.bump{i}(mut rec{i}, 2)",
                f"    acc += m{i}.score{i}(rec{i}) + m{i}.area{i}(m{i}.Shape{i}.box(2))"]
        out += [f"    acc += m{i}.probe{i}_{d}(5)" for d in deps[i]]
    out += ["    return acc", ""]
    with open(os.path.join(dest, "main.my"), "w") as handle:
        handle.write("\n".join(out))
    return {"modules": n + 1, "shape": shape}


# --------------------------------------------------------------------------
# the run loop
# --------------------------------------------------------------------------

def median(values):
    s = sorted(values)
    return s[len(s) // 2] if s else None


def fuzz(options):
    compiler = os.path.abspath(options.compiler)
    work = os.path.abspath(options.work)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    original = os.path.join(work, "original")
    meta = {}
    if options.project_kind == "synthetic":
        meta = gen_synthetic(options.seed, original)
    else:
        shutil.copytree(options.source or LOX_DEFAULT, original, ignore=shutil.ignore_patterns(".mylang-cache"))
    project_dir = os.path.join(work, "project")
    shutil.copytree(original, project_dir)
    extra = ["--gc-runtime"] if options.gc_runtime else []
    rig = Rig(compiler, work, extra)
    rng = random.Random(options.seed)
    proj = load_project(project_dir)
    header = {"seed": options.seed, "project_kind": options.project_kind, "gc_runtime": options.gc_runtime,
              "compiler": compiler, "excluded_kinds": sorted(EXCLUDED),
              "edits_per_step": options.edits_per_step, **meta}
    rows, timeline, findings = [], [], []
    by_kind = {}
    started = time.monotonic()

    def emit(row):
        rows.append(row)
        print(json.dumps(row), flush=True)

    def stop(ok):
        return finish(options, header, rows, findings, by_kind, started, ok)

    def keep(kind, step, row):
        """Record a finding and its reproducer; True when the run should stop."""
        findings.append(row)
        save_reproducer(os.path.join(work, f"repro-seed{options.seed}-step{step}-{kind}"), original, timeline, header)
        for name in ("inc", "whole"):
            path = os.path.join(rig.out, name)
            if os.path.exists(path):
                shutil.copy(path, os.path.join(work, f"repro-seed{options.seed}-step{step}-{kind}", name + ".bin"))
        return not options.keep_going

    inc, whole, verdict, good_digest = rig.compare()
    counts = inc.counts
    emit({"seed": options.seed, "step": 0, "kind": "cold", "file": "-", "compiled": counts and counts["compiled"],
          "modules": counts and counts["modules"], "seconds": round(inc.seconds, 3), "matched": verdict == "match",
          "verdict": verdict, "engaged": counts is not None})
    if verdict != "match" or counts is None:
        print("the unedited project does not build both ways through the module path; nothing to fuzz", file=sys.stderr)
        return stop(False)

    for step in range(1, options.steps + 1):
        drawn, trial = [], proj
        for _ in range(options.edits_per_step):
            kind, trial, fname, desc = choose_edit(rng, trial)
            drawn.append((kind, fname, desc))
        kind, fname, desc = "+".join(d[0] for d in drawn), ",".join(dict.fromkeys(d[1] for d in drawn)), "; ".join(d[2] for d in drawn)
        changed = sorted(n for n in trial.files if trial.files[n] != proj.files[n])
        patch = patch_of(proj, trial)
        write_files(project_dir, trial.files, changed)
        timeline.append({"label": "edit", "kind": kind, "desc": desc, "patch": patch, "step": step})
        inc, whole, verdict, digest_now = rig.compare()
        counts = inc.counts
        built = verdict in ("match", "binary-differs")
        engaged = built and counts is not None
        for one, _, _ in drawn:      # with several edits per step each kind shares the step's outcome
            stats = by_kind.setdefault(one, {"applied": 0, "built": 0, "failed": 0, "off_module_path": 0, "compiled": []})
            stats["applied"] += 1
            stats["built" if built else "failed"] += 1
            stats["off_module_path"] += 1 if built and not engaged else 0
            if engaged:
                stats["compiled"].append(counts["compiled"])
        good = verdict in ("match", "both-failed")
        row = {"seed": options.seed, "step": step, "kind": kind, "file": fname, "desc": desc,
               "compiled": counts and counts["compiled"], "modules": counts and counts["modules"],
               "seconds": round(inc.seconds, 3), "matched": good, "verdict": verdict, "built": built,
               "engaged": engaged}
        if verdict == "both-failed":
            row["error"] = inc.excerpt(300)
            row["diagnostics_same"] = inc.diagnostics == whole.diagnostics
        elif not good:
            row["error"] = f"incremental: {inc.excerpt(300)} | whole: {whole.excerpt(300)}"
        elif built and not engaged:
            row["off_module_path_because"] = (inc.stderr.strip().splitlines() or ["(no diagnostics)"])[0][:200]
        if inc.crashed or whole.crashed:
            row["crash"] = True
        emit(row)
        if (not good or row.get("crash")) and keep("mismatch" if not good else "crash", step, row):
            return stop(False)
        if verdict == "match" and engaged:
            proj, good_digest = trial, digest_now
            continue
        if verdict == "binary-differs" and options.keep_going:
            proj, good_digest = trial, digest_now
            continue
        # a failing edit, or one that moved the build off the module path, is reverted
        write_files(project_dir, proj.files, changed)
        timeline.append({"label": "revert", "kind": kind, "desc": "revert " + desc,
                         "patch": patch_of(trial, proj), "step": step})
        again = rig.incremental()
        back = again.ok and digest(os.path.join(rig.out, "inc")) == good_digest and again.counts is not None
        check = {"seed": options.seed, "step": step, "kind": "revert-check", "file": fname,
                 "compiled": again.counts and again.counts["compiled"],
                 "modules": again.counts and again.counts["modules"], "seconds": round(again.seconds, 3),
                 "matched": back, "verdict": "match" if back else "revert-differs"}
        emit(check)
        if not back and keep("revert", step, check):
            return stop(False)
    return stop(not findings)


def finish(options, header, rows, findings, by_kind, started, ok):
    step_rows = [r for r in rows if r["kind"] not in ("cold", "revert-check")]
    compiled = [r["compiled"] for r in step_rows if r.get("engaged")]
    hist = {}
    for c in compiled:
        hist[str(c)] = hist.get(str(c), 0) + 1
    modules = next((r["modules"] for r in rows if r.get("modules")), None)
    summary = {
        **header, "steps": len(step_rows), "ok": ok, "modules": modules,
        "matched": sum(1 for r in step_rows if r["matched"]),
        "built": sum(1 for r in step_rows if r.get("built")),
        "engaged": sum(1 for r in step_rows if r.get("engaged")),
        "off_module_path": sum(1 for r in step_rows if r.get("built") and not r.get("engaged")),
        "build_failures_both": sum(1 for r in step_rows if r.get("verdict") == "both-failed"),
        "diagnostics_differ": sum(1 for r in step_rows if r.get("diagnostics_same") is False),
        "revert_checks": sum(1 for r in rows if r["kind"] == "revert-check"),
        "findings": findings,
        "by_kind": {k: {"applied": v["applied"], "built": v["built"], "failed": v["failed"],
                        "off_module_path": v["off_module_path"], "compiled": v["compiled"]} for k, v in sorted(by_kind.items())},
        "compiled_hist": dict(sorted(hist.items(), key=lambda kv: int(kv[0]))),
        "compiled_mean": round(sum(compiled) / len(compiled), 2) if compiled else None,
        "compiled_median": median(compiled),
        "cold_seconds": rows[0]["seconds"],
        "incremental_seconds_median": median([r["seconds"] for r in step_rows if r.get("engaged")]),
        "wall_seconds": round(time.monotonic() - started, 1),
        "rows": rows,
    }
    if options.json:
        with open(options.json, "w") as handle:
            json.dump(summary, handle, indent=1)
    print(("ALL MATCHED" if ok else "FINDING") + f" seed={options.seed} steps={len(step_rows)} built={summary['built']}"
          f" wall={summary['wall_seconds']}s", flush=True)
    return 0 if ok else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--work", required=True)
    parser.add_argument("--source", help="project to copy (default: the Lox port)")
    parser.add_argument("--project-kind", choices=["lox", "synthetic"], default="lox")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--gc-runtime", action="store_true")
    parser.add_argument("--json")
    parser.add_argument("--keep-going", action="store_true")
    parser.add_argument("--edits-per-step", type=int, default=1,
                        help="apply this many edits (drawn one after another) before each comparison")
    parser.add_argument("--exclude-kinds", default="", help="comma-separated edit kinds to leave out")
    parser.add_argument("--replay", metavar="REPRO_DIR")
    parser.add_argument("--minimize", metavar="REPRO_DIR")
    options = parser.parse_args()
    EXCLUDED.update(k for k in options.exclude_kinds.split(",") if k)
    unknown = EXCLUDED - set(WEIGHTS)
    if unknown:
        parser.error(f"unknown edit kinds: {sorted(unknown)}")
    compiler = os.path.abspath(options.compiler)
    extra = ["--gc-runtime"] if options.gc_runtime else []
    if options.replay or options.minimize:
        repro = os.path.abspath(options.replay or options.minimize)
        header, entries = load_reproducer(repro)
        extra = ["--gc-runtime"] if header.get("gc_runtime") else []
        if options.replay:
            patches = [e["patch"] for e in entries]
            verdict = replay(compiler, os.path.abspath(options.work), os.path.join(repro, "original"), patches, extra, True)
            print(verdict)
            return 0 if verdict == "match" else 1
        log = lambda text: print(text, flush=True)
        work = os.path.abspath(options.work)
        found, entries = minimize(compiler, work, repro, extra, log)
        if found:
            save_reproducer(os.path.join(work, "minimal"), os.path.join(repro, "original"), entries, header)
        print(f"minimal edit list: {len(entries)} patch(es) in {os.path.join(work, 'minimal')}" if found
              else "the recorded edit list does not reproduce when only the last state is compared")
        return 0 if found else 1
    return fuzz(options)


if __name__ == "__main__":
    sys.exit(main())
