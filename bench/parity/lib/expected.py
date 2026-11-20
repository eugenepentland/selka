#!/usr/bin/env python3
"""CPython transcription of LIB.md: rewrites scan_{count,replace,split}.expected."""
from pathlib import Path

HERE = Path(__file__).resolve().parent


def text() -> str:
    block = "".join(f"item{i},{(i * 7919) % 100003},{'x' * (i % 7)}\n" for i in range(2000))
    return block * 110


def scan_count(t: str) -> str:
    total = 0
    for _ in range(12):
        a, b, c, d = t.count(",1"), t.count("\n"), t.count("item1"), t.count("x\nitem")
        total += a + b + c + d
    return f"{len(t)} {a} {b} {c} {d} {total}\n"


def scan_replace(t: str) -> str:
    total = 0
    for _ in range(4):
        a, b, c = t.replace("item", "it"), t.replace(",", ";;"), t.replace("x\nitem1", "|")
        total += len(a) + len(b) + len(c)
    return f"{len(a)} {len(b)} {len(c)} {total}\n"


def scan_split(t: str) -> str:
    lines = width = fields = runs = run_width = 0
    for _ in range(3):
        for piece in t.split("\n"):
            lines += 1
            width += len(piece)
        fields += len(t.split(","))
        for piece in t.split("x\nitem"):
            runs += 1
            run_width += len(piece)
    return f"{lines} {width} {fields} {runs} {run_width}\n"


def main() -> None:
    t = text()
    for name, program in (("scan_count", scan_count), ("scan_replace", scan_replace), ("scan_split", scan_split)):
        (HERE / f"{name}.expected").write_text(program(t))


if __name__ == "__main__":
    main()
