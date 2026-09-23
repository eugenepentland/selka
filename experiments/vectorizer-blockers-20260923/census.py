#!/usr/bin/env python3
"""census.py DIR... — classify the innermost loops of the guest code in each post-LTO opt.ll.

For every innermost natural loop in `entry_run` or a surviving `myl_f_*` function it prints
the blocks, the exits by kind (the fail helper each trap exit calls, or `normal`), non-intrinsic
calls, stores, loads whose address is loop-invariant (candidates LICM did not hoist), float and
integer header phis, and whether the loop is a vector body.  With --hot PATTERN only loops whose
text matches PATTERN are printed.
"""
import re
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1] / "llvm-backend"))
from llvm_emit import Dominators  # noqa: E402


def functions(path):
    body, name = [], None
    for line in open(path):
        if line.startswith("define"):
            m = re.search(r"@([\w.$]+)\(", line)
            name = m.group(1) if m else None
            body = []
            continue
        if name is None:
            continue
        if line.startswith("}"):
            yield name, body
            name = None
            continue
        body.append(line.rstrip("\n"))


def blocks_of(body):
    blocks, order, cur = {}, [], "entry"
    blocks[cur] = []
    order.append(cur)
    for line in body:
        m = re.match(r"^([\w.$-]+):", line)
        if m:
            cur = m.group(1)
            blocks[cur] = []
            order.append(cur)
            continue
        if line.strip():
            blocks[cur].append(re.sub(r", !(dbg|alias\.scope|noalias|tbaa|llvm\.loop) ![0-9]+", "", line))
    return blocks, order


def loops(blocks, order):
    edges = {}
    for b in order:
        joined = " ".join(blocks[b])
        at = max(joined.rfind(" br "), joined.rfind(" switch "))
        edges[b] = [s for s in re.findall(r"label %([\w.$-]+)", joined[at:]) if s in blocks] if at >= 0 else []
    dom = Dominators(order[0], edges)
    preds = {b: [] for b in order}
    for b in order:
        for s in edges[b]:
            preds[s].append(b)
    found = {}
    for b in order:
        for s in edges[b]:
            if dom.dominates(s, b):
                body, work = {s, b}, [b]
                while work:
                    x = work.pop()
                    if x == s:
                        continue
                    for p in preds[x]:
                        if p not in body:
                            body.add(p)
                            work.append(p)
                found.setdefault(s, set()).update(body)
    inner = {h: bs for h, bs in found.items() if not any(o != h and o in bs for o in found)}
    return inner, edges


def exit_kind(blocks, label, depth=0):
    text = " ".join(blocks.get(label, []))
    m = re.search(r"@myl_qbe_fail_(\w+)\(", text)
    if m:
        return m.group(1)
    if "unreachable" in text and depth == 0:
        return "unreachable"
    return "normal"


def main():
    args = sys.argv[1:]
    hot = None
    if args and args[0] == "--hot":
        hot = re.compile(args[1])
        args = args[2:]
    for directory in args:
        name = directory.rstrip("/").split("/")[-1]
        for function, body in functions(f"{directory}/opt.ll"):
            if not (function == "entry_run" or function.startswith("myl_f_")):
                continue
            blocks, order = blocks_of(body)
            inner, edges = loops(blocks, order)
            defs = {}
            for b in order:
                for line in blocks[b]:
                    m = re.match(r"\s*(%[\w.$-]+) = ", line)
                    if m:
                        defs[m.group(1)] = b
            for header in sorted(inner, key=order.index):
                body_labels = [b for b in order if b in inner[header]]
                text = [l for b in body_labels for l in blocks[b]]
                if hot and not any(hot.search(l) for l in text):
                    continue
                exits = {}
                for b in body_labels:
                    for s in edges[b]:
                        if s not in inner[header]:
                            kind = exit_kind(blocks, s)
                            exits[kind] = exits.get(kind, 0) + 1
                calls = sorted({m for l in text for m in re.findall(r"call [^@]*@([\w.$]+)", l)
                                if not m.startswith("llvm.")})
                stores = sum(1 for l in text if l.strip().startswith("store"))
                invariant = 0
                for l in text:
                    m = re.search(r"= load [^,]+, ptr (%[\w.$-]+)", l)
                    if m and defs.get(m.group(1)) not in inner[header]:
                        invariant += 1
                fphi = sum(1 for l in blocks[header] if " = phi double" in l or " = phi float" in l)
                iphi = sum(1 for l in blocks[header] if re.search(r" = phi i(8|16|32|64) ", l))
                vector = any("<" in l and "x " in l for l in text)
                print(f"{name:16s} {function[:14]:14s} {header[:26]:26s} blocks={len(body_labels):2d} "
                      f"exits={exits} calls={calls} stores={stores} invariant-loads={invariant} "
                      f"fphi={fphi} iphi={iphi} vector={vector}")


main()
