#!/usr/bin/env python3
"""FU-PORT: llvm_identity.py's normalization, compared one function at a time (by symbol name,
which the Lox and EDA modules keep across the redesign). usage: llvm_functions.py LABEL [A B]
prints, for the pair (default P X), the functions whose normalized bodies differ."""
import re, sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
import llvm_identity as l


def functions(tag, job):
    text = l.load(tag, job, symbols=False)
    out, name, body = {}, None, []
    for line in text.split("\n"):
        m = re.match(r'^define [^@]*@("[^"]*"|[\w.]+)\(', line)
        if m:
            name, body = m.group(1), [line]
        elif name:
            body.append(line)
            if line == "}":
                out[name] = "\n".join(body)
                name = None
    return out


def main():
    label = sys.argv[1]
    a, b = (sys.argv[2], sys.argv[3]) if len(sys.argv) > 3 else ("P", "X")
    job = {j[0]: j for j in l.jobs()}[label]
    fa, fb = functions(a, job), functions(b, job)
    differ = sorted(k for k in fa.keys() & fb.keys() if fa[k] != fb[k])
    only = sorted(fa.keys() ^ fb.keys())
    print(f"{label} {a} vs {b}: {len(fa)} / {len(fb)} functions, {len(differ)} differ, {len(only)} unmatched")
    for k in differ:
        print("  differs:", k)
    for k in only:
        print("  only in one:", k)


if __name__ == "__main__":
    main()


def quad(label):
    """Per function of LABEL: P==X, M==A, X==A, P==M, and whether the A->X delta equals the M->P
    delta once SSA value and block numbers are renumbered (`deltas_match`)."""
    import difflib
    job = {j[0]: j for j in l.jobs()}[label]
    f = {t: functions(t, job) for t in "AXMP"}

    def canon(text):
        names = {}
        return re.sub(r"%[\w.]+", lambda m: names.setdefault(m.group(0), f"%r{len(names)}"), text)

    def delta(old, new):
        return [s for s in difflib.unified_diff(canon(old).split("\n"), canon(new).split("\n"), lineterm="", n=0)
                if s[:1] in "+-" and not s.startswith(("---", "+++"))]

    rows = {}
    for name in sorted(set.intersection(*(set(v) for v in f.values()))):
        a, x, m, p = (f[t][name] for t in "AXMP")
        rows[name] = {"P==X": p == x, "M==A": m == a, "X==A": x == a, "P==M": p == m,
                      "deltas_match": delta(a, x) == delta(m, p)}
    return rows
