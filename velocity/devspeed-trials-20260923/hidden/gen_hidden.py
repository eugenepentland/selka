#!/usr/bin/env python3
"""Generate hidden acceptance cases for T1/T2/T3/T5 from the reference implementations.

Each case: cases/<task>/<name>/{case.json, files...}; case.json holds args (with {dir}
substituted by the case directory at run time), expected stdout, exit status, and an
optional expected stderr first line and time limit.
"""
import json
import random
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "cases"
REF = HERE / "ref_others.py"
CALC = HERE / "ref_calc.py"


def write_case(task, name, files, args, limit=10.0, check_stderr=True):
    d = OUT / task / name
    d.mkdir(parents=True, exist_ok=True)
    for fname, content in files.items():
        mode = "wb" if isinstance(content, bytes) else "w"
        with open(d / fname, mode, **({} if mode == "wb" else {"newline": ""})) as f:
            f.write(content)
    real_args = [a.replace("{dir}", str(d)) for a in args]
    if task == "calc":
        cmd = [sys.executable, str(CALC)] + real_args
    else:
        cmd = [sys.executable, str(REF), task] + real_args
    p = subprocess.run(cmd, capture_output=True)
    assert p.returncode != 99, (task, name, p.stderr)
    case = {
        "args": args,
        "stdout": p.stdout.decode("utf-8", "replace"),
        "exit": p.returncode,
        "stderr_first_line": p.stderr.decode().split("\n")[0] if (check_stderr and p.stderr) else None,
        "limit_s": limit,
    }
    (d / "case.json").write_text(json.dumps(case, indent=1))


def wordfreq_cases():
    t = "wordfreq"
    write_case(t, "basic", {"in.txt": "The cat and the hat. THE end, and fin!\nCat? cat.\n"}, ["{dir}/in.txt", "3"])
    write_case(t, "fewer_than_n", {"in.txt": "b a c b\n"}, ["{dir}/in.txt", "10"])
    write_case(t, "ties_sorted", {"in.txt": "zeta alpha mid alpha zeta mid beta\n"}, ["{dir}/in.txt", "4"])
    write_case(t, "digits_and_apostrophes", {"in.txt": "Don't stop: 42 times, don't 42x x42 42.\n"}, ["{dir}/in.txt", "10"])
    write_case(t, "non_ascii_separators", {"in.txt": "café naïve 日本 word—word résumé\n".encode()}, ["{dir}/in.txt", "10"])
    write_case(t, "crlf", {"in.txt": b"one two\r\ntwo three\r\nthree three\r\n"}, ["{dir}/in.txt", "5"])
    write_case(t, "empty_file", {"in.txt": ""}, ["{dir}/in.txt", "3"])
    write_case(t, "missing_file", {}, ["{dir}/nope.txt", "3"])
    write_case(t, "bad_count_zero", {"in.txt": "a\n"}, ["{dir}/in.txt", "0"])
    write_case(t, "bad_count_negative", {"in.txt": "a\n"}, ["{dir}/in.txt", "-2"])
    write_case(t, "bad_count_word", {"in.txt": "a\n"}, ["{dir}/in.txt", "three"])
    write_case(t, "usage", {"in.txt": "a\n"}, ["{dir}/in.txt"], check_stderr=False)
    rng = random.Random(11)
    vocab = ["w%d" % i for i in range(5000)] + ["The", "and", "of", "to", "A", "in"]
    weights = [1.0 / (i + 1) for i in range(len(vocab))]
    words = rng.choices(vocab, weights=weights, k=1_600_000)
    text = []
    for i, w in enumerate(words):
        text.append(w)
        text.append("\n" if i % 13 == 12 else (", " if i % 7 == 0 else " "))
    write_case(t, "large_10mb", {"in.txt": "".join(text)}, ["{dir}/in.txt", "25"], limit=10.0)


def calc_cases():
    t = "calc"
    cases = {
        "arith": "print 1 + 2 * 3\nprint (1 + 2) * 3\nprint 10 - 4 - 3\nprint 2 * 3 % 4\n",
        "vars": "let x = 5\nlet y = x * 2 + 1\nprint y\nlet x = x + y\nprint x\n",
        "trunc_div_mod": "print 7 / 2\nprint -7 / 2\nprint 7 / -2\nprint 7 % 3\nprint -7 % 3\nprint 7 % -3\n",
        "unary": "print -3\nprint --3\nprint -(2 + 3) * 2\nprint 4 - -2\n",
        "comments_blank": "# header\n\nlet a = 1\n   # indented comment\nprint a\n\n",
        "big_ints": "let big = 4000000000\nprint big * 1000000\nprint 9000000000000000000 / 3\n",
        "err_undefined": "let a = 1\nprint a\nprint a + b * 2\nprint 99\n",
        "err_div_zero": "let z = 0\nprint 5\nprint 10 / (z * 3)\n",
        "err_mod_zero": "print 7 % 0\n",
        "err_unexpected_char": "print 1 + 2\nprint 3 $ 4\n",
        "err_expected_expr": "print 1 +\n",
        "err_expected_expr_mid": "let q = (2 * )\n",
        "err_expected_paren": "print (1 + 2\n",
        "err_expected_paren_token": "print (1 + 2 3\n",
        "err_trailing": "print 1 2\n",
        "err_bad_statement": "x = 3\n",
        "err_let_no_eq": "let x 3\n",
        "err_left_first": "print a / 0\n",
        "whitespace_tabs": "let\tv = \t 3\nprint\tv*v\n",
        "no_trailing_newline": "print 42",
    }
    for name, src in cases.items():
        write_case(t, name, {"prog.calc": src}, ["{dir}/prog.calc"])
    lines = ["let x0 = 1"]
    for i in range(1, 20000):
        lines.append(f"let x{i} = (x{i-1} * 3 + {i}) % 1000003 - -{i % 7}")
    lines.append("print x19999")
    write_case(t, "many_lines", {"prog.calc": "\n".join(lines) + "\n"}, ["{dir}/prog.calc"], limit=10.0)
    write_case(t, "missing_file", {}, ["{dir}/none.calc"])


def route_cases():
    t = "route"
    g1 = "A B 4\nA C 1\nC B 2\nB D 5\nC D 8\n"
    write_case(t, "small", {"g.txt": g1}, ["{dir}/g.txt", "A", "D"])
    write_case(t, "reverse_dir", {"g.txt": g1}, ["{dir}/g.txt", "D", "A"])
    write_case(t, "same_node", {"g.txt": g1}, ["{dir}/g.txt", "B", "B"])
    write_case(t, "unreachable", {"g.txt": g1 + "X Y 1\n"}, ["{dir}/g.txt", "A", "Y"])
    write_case(t, "unknown_node", {"g.txt": g1}, ["{dir}/g.txt", "A", "Q"])
    write_case(t, "comments_spacing", {"g.txt": "# roads\n\nhome   shop\t3\nshop  work 4\n  home work 9\n"}, ["{dir}/g.txt", "home", "work"])
    write_case(t, "zero_weights_multi", {"g.txt": "a b 0\nb c 0\na c 1\na b 5\n"}, ["{dir}/g.txt", "a", "c"])
    write_case(t, "bad_edge", {"g.txt": "a b 1\na c\n"}, ["{dir}/g.txt", "a", "b"])
    write_case(t, "bad_weight", {"g.txt": "a b 1\nb c -2\n"}, ["{dir}/g.txt", "a", "c"])
    write_case(t, "usage", {"g.txt": g1}, ["{dir}/g.txt", "A"], check_stderr=False)
    rng = random.Random(7)
    n = 50000
    names = [f"n{i}" for i in range(n)]
    edges = []
    for i in range(1, n):
        edges.append((names[i], names[rng.randrange(i)], rng.randint(1, 1_000_000)))
    while len(edges) < 200000:
        a, b = rng.randrange(n), rng.randrange(n)
        if a != b:
            edges.append((names[a], names[b], rng.randint(1, 1_000_000)))
    text = "".join(f"{a} {b} {w}\n" for a, b, w in edges)
    write_case(t, "large_200k", {"g.txt": text}, ["{dir}/g.txt", "n0", "n49999"], limit=10.0)
    write_case(t, "large_200k_b", {"g.txt": text}, ["{dir}/g.txt", "n123", "n45678"], limit=10.0)


def csv_cases():
    t = "csvstats"
    base = "city,product,amount\nParis,apple,1.3\nLyon,pear,2\nParis,pear,3.5\nNice,apple,\nLyon,apple,-0.8\n"
    write_case(t, "basic", {"d.csv": base}, ["{dir}/d.csv", "city", "amount"])
    write_case(t, "group_by_other", {"d.csv": base}, ["{dir}/d.csv", "product", "amount"])
    quoted = ('name,"note, with comma",value\n'
              '"Smith, J","said ""hi""",10\n'
              'Lee,"multi\nline",2.5\n'
              '"Smith, J",x,4.2\n'
              '"",empty group,1\n')
    write_case(t, "quoted", {"d.csv": quoted}, ["{dir}/d.csv", "name", "value"])
    write_case(t, "quoted_header_lookup", {"d.csv": quoted}, ["{dir}/d.csv", "note, with comma", "value"])
    write_case(t, "crlf", {"d.csv": "k,v\r\na,1\r\nb,2\r\na,3.5\r\n"}, ["{dir}/d.csv", "k", "v"])
    write_case(t, "no_trailing_newline", {"d.csv": "k,v\na,1\nb,2"}, ["{dir}/d.csv", "k", "v"])
    write_case(t, "bad_number", {"d.csv": "k,v\na,1\nb,1.2.3\n"}, ["{dir}/d.csv", "k", "v"])
    write_case(t, "bad_number_exp", {"d.csv": "k,v\na,1e5\n"}, ["{dir}/d.csv", "k", "v"])
    write_case(t, "field_count", {"d.csv": "k,v\na,1\nb,2,3\n"}, ["{dir}/d.csv", "k", "v"])
    write_case(t, "no_column", {"d.csv": "k,v\na,1\n"}, ["{dir}/d.csv", "k", "value"])
    write_case(t, "usage", {"d.csv": "k,v\n"}, ["{dir}/d.csv", "k"], check_stderr=False)
    rng = random.Random(5)
    groups = [f"g{i:03d}" for i in range(300)] + ['"quoted, group"', '"has ""q"""']
    rows = ["id,group,score,comment"]
    for i in range(200000):
        g = rng.choice(groups)
        cents = rng.randint(-50000, 500000)
        sc = f"{cents // 100}.{cents % 100:02d}" if cents >= 0 else f"-{(-cents) // 100}.{(-cents) % 100:02d}"
        if rng.random() < 0.02:
            sc = ""
        rows.append(f'{i},{g},{sc},"c{i}, ok"')
    write_case(t, "large_200k_rows", {"d.csv": "\n".join(rows) + "\n"}, ["{dir}/d.csv", "group", "score"], limit=10.0)


if __name__ == "__main__":
    if OUT.exists():
        shutil.rmtree(OUT)
    wordfreq_cases()
    calc_cases()
    route_cases()
    csv_cases()
    for task in sorted(p.name for p in OUT.iterdir()):
        print(task, len(list((OUT / task).iterdir())))
