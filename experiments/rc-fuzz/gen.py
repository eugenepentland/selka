#!/usr/bin/env python3
"""Random well-typed mylang programs exercising value semantics, mut records,
read-only parameters, element/field paths, loops and snapshots, for GC-vs-RC
differential testing. usage: gen.py SEED > prog.my"""
import random
import sys

TYPES = ["L", "LL", "R", "D", "S"]
TYNAME = {"L": "list[int]", "LL": "list[list[int]]", "R": "R", "D": "dict[str, list[int]]", "S": "str", "int": "int"}

PRELUDE = '''record P:
    xs: list[int]
    k: int

record R:
    items: list[int]
    rows: list[list[int]]
    name: str
    n: int
    inner: P

def make(n: int) -> list[int]:
    out: list[int] = []
    for i in range(n):
        out.append(i * 3 + 1)
    return out

def total(xs: list[int]) -> int:
    t = 0
    for x in xs:
        t = t + x
    return t

def total2(xss: list[list[int]]) -> int:
    t = 0
    for xs in xss:
        t = t * 3 + total(xs) + len(xs)
    return t

def rsum(r: R) -> int:
    return total(r.items) * 7 + total2(r.rows) * 5 + len(r.name) * 3 + r.n + total(r.inner.xs) * 11 + r.inner.k

def dsum(d: dict[str, list[int]]) -> int:
    t = 0
    for k, v in d.items():
        t = t * 5 + len(k) + total(v)
    return t

def push_list(xs: mut list[int], v: int):
    xs.append(v)

def bump_rows(rows: mut list[list[int]], v: int) -> int:
    if len(rows) > 0:
        rows[0].append(v)
    rows.append([v])
    return len(rows)

def touch(r: mut R, v: int) -> int:
    r.n = r.n + v
    return 0

def grow(r: mut R, v: int) -> int:
    r.items.append(v)
    return 1

def swap_items(r: mut R, v: int) -> int:
    r.items = [v, v]
    return 0

def deep(r: mut R, v: int) -> int:
    push_list(mut r.inner.xs, v)
    if len(r.rows) > 0:
        r.rows[0].append(v)
    return 0

def replace_rows(r: mut R, v: int) -> int:
    _ = bump_rows(mut r.rows, v)
    return 0
'''

MUTATORS = ["touch", "grow", "swap_items", "deep", "replace_rows"]


class Fn:
    def __init__(self, name, params):
        self.name = name
        self.params = params  # list of (name, type, mut)


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.fns = []
        self.lines = []

    def pick(self, xs):
        return self.r.choice(xs)

    def int_expr(self, env, depth=0):
        opts = ["lit", "lit", "len", "n"]
        c = self.pick(opts)
        if c == "lit":
            return str(self.r.randint(0, 9))
        if c == "len":
            v = self.var(env, ["L", "LL", "S", "D"])
            if v:
                return f"len({v[0]})"
            return "1"
        v = self.var(env, ["R"])
        if v:
            return f"{v[0]}.n"
        return "2"

    def var(self, env, types, mutable=None):
        cands = [(n, t, m) for (n, t, m) in env if t in types and (mutable is None or m == mutable)]
        if not cands:
            return None
        return self.pick(cands)

    def expr(self, env, ty):
        """An expression of type ty that only reads."""
        r = self.r
        if ty == "L":
            opts = [f"[{r.randint(0,9)}, {r.randint(0,9)}]", f"make({r.randint(0,4)})"]
            v = self.var(env, ["L"])
            if v:
                opts += [v[0]] * 3
            rv = self.var(env, ["R"])
            if rv:
                opts += [f"{rv[0]}.items", f"{rv[0]}.inner.xs"]
            ll = self.var(env, ["LL"])
            if ll:
                opts += [f"({ll[0]}[0] if len({ll[0]}) > 0 else [5])"]
            d = self.var(env, ["D"])
            if d:
                opts += [f'{d[0]}.get("a", [8])']
            return self.pick(opts)
        if ty == "LL":
            opts = [f"[[{r.randint(0,9)}], [{r.randint(0,9)}, {r.randint(0,9)}]]"]
            v = self.var(env, ["LL"])
            if v:
                opts += [v[0]] * 3
            rv = self.var(env, ["R"])
            if rv:
                opts += [f"{rv[0]}.rows"]
            lv = self.var(env, ["L"])
            if lv:
                opts += [f"[{lv[0]}, {lv[0]}]"]
            return self.pick(opts)
        if ty == "R":
            opts = [f"R(make({r.randint(0,3)}), [[1], [2, 3]], \"nm{r.randint(0,9)}\", {r.randint(0,9)}, P([4], 1))"]
            v = self.var(env, ["R"])
            if v:
                opts += [v[0]] * 3
                lv = self.var(env, ["L"])
                if lv:
                    opts += [f"R({lv[0]}, {v[0]}.rows, {v[0]}.name, {v[0]}.n + 1, {v[0]}.inner)"]
            return self.pick(opts)
        if ty == "D":
            opts = ['{"a": [1], "b": [2, 2]}']
            v = self.var(env, ["D"])
            if v:
                opts += [v[0]] * 3
            lv = self.var(env, ["L"])
            if lv:
                opts += [f'{{"a": {lv[0]}}}']
            return self.pick(opts)
        if ty == "S":
            opts = ['"ab" + "cd"', '"xyz"']
            v = self.var(env, ["S"])
            if v:
                opts += [v[0], f"{v[0]}[0:2]", f'{v[0]} + "q"']
            rv = self.var(env, ["R"])
            if rv:
                opts += [f"{rv[0]}.name"]
            return self.pick(opts)
        raise ValueError(ty)

    def checksum(self, name, ty):
        return {"L": f"total({name})", "LL": f"total2({name})", "R": f"rsum({name})", "D": f"dsum({name})",
                "S": f"len({name})", "int": name}[ty]

    def stmt(self, env, locals_, ind, depth, loopvars):
        r = self.r
        pad = "    " * ind
        out = []
        kinds = ["assign", "assign", "mutate", "mutate", "mutate", "call", "call", "acc", "snapshot"]
        if depth < 2:
            kinds += ["if", "for", "while"]
        if depth < 1:
            kinds += ["arena"]
        k = self.pick(kinds)
        mutables = [(n, t, m) for (n, t, m) in env if m and n not in loopvars]
        if k == "assign":
            ty = self.pick(TYPES)
            ex = self.expr(env, ty)
            existing = [n for (n, t, m) in env if t == ty and m and n in locals_ and n not in loopvars]
            if existing and r.random() < 0.5:
                name = self.pick(existing)
            else:
                name = f"v{len(locals_)}"
                locals_.append(name)
                env.append((name, ty, True))
            out.append(f"{pad}{name} = {ex}")
        elif k == "snapshot":
            v = self.var(env, TYPES)
            if v:
                name = f"v{len(locals_)}"
                locals_.append(name)
                env.append((name, v[1], True))
                out.append(f"{pad}{name} = {v[0]}")
        elif k == "mutate":
            cands = [x for x in mutables if x[1] in ("L", "LL", "R", "D")]
            if not cands:
                return self.stmt(env, locals_, ind, depth, loopvars)
            n, t, _ = self.pick(cands)
            i = self.int_expr(env)
            if t == "L":
                out.append(self.pick([
                    f"{pad}{n}.append({i})",
                    f"{pad}if len({n}) > 0:\n{pad}    {n}[0] = {i}",
                    f"{pad}push_list(mut {n}, {i})",
                    f"{pad}if len({n}) > 1:\n{pad}    _ = {n}.pop()",
                ]))
            elif t == "LL":
                out.append(self.pick([
                    f"{pad}{n}.append({self.expr(env, 'L')})",
                    f"{pad}if len({n}) > 0:\n{pad}    {n}[0].append({i})",
                    f"{pad}if len({n}) > 0:\n{pad}    {n}[0] = {self.expr(env, 'L')}",
                    f"{pad}_ = bump_rows(mut {n}, {i})",
                    f"{pad}if len({n}) > 0:\n{pad}    push_list(mut {n}[0], {i})",
                ]))
            elif t == "R":
                out.append(self.pick([
                    f"{pad}{n}.items.append({i})",
                    f"{pad}{n}.n = {n}.n + {i}",
                    f"{pad}{n}.items = {self.expr(env, 'L')}",
                    f"{pad}{n}.inner.xs.append({i})",
                    f"{pad}{n}.name = {self.expr(env, 'S')}",
                    f"{pad}if len({n}.rows) > 0:\n{pad}    {n}.rows[0].append({i})",
                    f"{pad}push_list(mut {n}.items, {i})",
                    f"{pad}_ = {self.pick(MUTATORS)}(mut {n}, {i})",
                    f"{pad}acc = acc + {self.pick(MUTATORS)}(mut {n}, {i})",
                    f"{pad}if len({n}.items) > 0:\n{pad}    acc = acc + {n}.items[{self.pick(MUTATORS)}(mut {n}, {i}) % len({n}.items)]",
                    f"{pad}acc = acc + total({n}.items) + {self.pick(MUTATORS)}(mut {n}, {i})",
                    f"{pad}if len({n}.rows) > 0:\n{pad}    acc = acc + len({n}.rows[{self.pick(MUTATORS)}(mut {n}, {i}) % len({n}.rows)])",
                ]))
            elif t == "D":
                out.append(self.pick([
                    f'{pad}{n}["a"] = {self.expr(env, "L")}',
                    f'{pad}if "b" in {n}:\n{pad}    {n}["b"].append({i})',
                    f'{pad}{n}["k" + str({i})] = [{i}]',
                ]))
        elif k == "call" and self.fns:
            f = self.pick(self.fns)
            args = []
            for (pn, pt, pm) in f.params:
                if pm:
                    cands = [x for x in mutables if x[1] == pt]
                    if not cands:
                        return self.stmt(env, locals_, ind, depth, loopvars)
                    args.append("mut " + self.pick(cands)[0])
                else:
                    args.append(self.expr(env, pt))
            out.append(f"{pad}acc = acc + {f.name}({', '.join(args)})")
        elif k == "acc":
            v = self.var(env, TYPES + ["int"])
            if v:
                out.append(f"{pad}acc = acc * 3 + {self.checksum(v[0], v[1])}")
        elif k == "if":
            c = f"{self.int_expr(env)} > {r.randint(0, 4)}"
            out.append(f"{pad}if {c}:")
            body = self.block(env, locals_, ind + 1, depth + 1, loopvars, r.randint(1, 3), scoped=True)
            out.extend(body)
            if r.random() < 0.5:
                out.append(f"{pad}else:")
                out.extend(self.block(env, locals_, ind + 1, depth + 1, loopvars, r.randint(1, 3), scoped=True))
        elif k == "for":
            src = self.var(env, ["L", "LL"])
            if not src:
                return self.stmt(env, locals_, ind, depth, loopvars)
            lv = f"x{len(locals_)}"
            locals_.append(lv)
            et = "int" if src[1] == "L" else "L"
            out.append(f"{pad}for {lv} in {src[0]}:")
            inner = env + [(lv, et, False)]
            body = [f"{pad}    acc = acc + {self.checksum(lv, et)}"]
            # the body must not mutate the iterated list itself (that traps in both runtimes, which is fine but ends the run)
            body += self.block(inner, locals_, ind + 1, depth + 1, loopvars | {src[0]}, r.randint(0, 2), scoped=True)
            out.extend(body)
        elif k == "while":
            cv = f"c{len(locals_)}"
            locals_.append(cv)
            out.append(f"{pad}{cv} = 0")
            out.append(f"{pad}while {cv} < {r.randint(1, 3)}:")
            out.append(f"{pad}    {cv} = {cv} + 1")
            out.extend(self.block(env, locals_, ind + 1, depth + 1, loopvars, r.randint(1, 3), scoped=True))
            if r.random() < 0.3:
                out.append(f"{pad}    if acc % 2 == 0:\n{pad}        break")
        elif k == "arena":
            out.append(f"{pad}with arena():")
            v = self.var(env, TYPES)
            out.append(f"{pad}    tmp{len(locals_)} = {self.expr(env, 'L')}")
            out.append(f"{pad}    acc = acc + total(tmp{len(locals_)})")
            locals_.append(f"tmp{len(locals_)}")
            if v:
                out.append(f"{pad}    acc = acc + {self.checksum(v[0], v[1])}")
        if not out:
            out.append(f"{pad}acc = acc + 1")
        return "\n".join(out)

    def block(self, env, locals_, ind, depth, loopvars, count, scoped=False):
        # names assigned in a nested block are not definitely assigned after it
        local_env = list(env)
        out = [self.stmt(local_env, locals_, ind, depth, loopvars) for _ in range(count)]
        if not out:
            out = ["    " * ind + "acc = acc + 0"]
        # later reads inside this block may use local_env; after it, only env
        if not scoped:
            env[:] = local_env
        return out

    def function(self, idx):
        r = self.r
        params = []
        for p in range(r.randint(1, 4)):
            ty = self.pick(TYPES)
            mut = ty in ("L", "LL", "R", "D") and r.random() < 0.4
            params.append((f"p{p}", ty, mut))
        f = Fn(f"f{idx}", params)
        env = [(n, t, m) for (n, t, m) in params]
        locals_ = []
        sig = ", ".join(f"{n}: {'mut ' if m else ''}{TYNAME[t]}" for (n, t, m) in params)
        lines = [f"def {f.name}({sig}) -> int:", "    acc = 0"]
        # every mut parameter must be written
        for (n, t, m) in params:
            if m:
                w = {"L": f"    {n}.append(1)", "LL": f"    {n}.append([1])", "R": f"    {n}.n = {n}.n + 1",
                     "D": f'    {n}["w"] = [1]'}[t]
                lines.append(w)
        body = self.block(env, locals_, 1, 0, set(), r.randint(4, 10))
        lines.extend(body)
        sums = " + ".join(self.checksum(n, t) for (n, t, m) in env if t != "int") or "0"
        lines.append(f"    return acc * 7 + {sums}")
        self.fns.append(f)
        return "\n".join(lines)

    def main(self):
        r = self.r
        lines = ["def main(out: Stream) -> int:"]
        env = []
        seeds = {"L": "make(3)", "LL": "[[1, 2], [3]]", "R": 'R(make(2), [[1], [2, 3]], "nm", 1, P([4], 1))',
                 "D": '{"a": [1], "b": [2, 2]}', "S": '"hello"'}
        for i, ty in enumerate(TYPES * 2):
            lines.append(f"    m{i} = {seeds[ty]}")
            env.append((f"m{i}", ty, True))
        lines.append("    acc = 0")
        locals_ = [n for (n, _, _) in env]
        for _ in range(r.randint(4, 10)):
            lines.append(self.stmt(env, locals_, 1, 1, set()))
            lines.append(f"    out.print(acc, {', '.join(self.checksum(n, t) for (n, t, m) in env if t != 'int')})")
        lines.append("    return 0")
        return "\n".join(lines)

    def program(self, nfns):
        parts = [PRELUDE]
        for i in range(nfns):
            parts.append(self.function(i))
        parts.append(self.main())
        return "\n\n".join(parts) + "\n"


if __name__ == "__main__":
    seed = int(sys.argv[1])
    g = Gen(seed)
    print(g.program(g.r.randint(3, 7)))
