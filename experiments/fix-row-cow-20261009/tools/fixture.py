#!/usr/bin/env python3
"""Assemble experiments/fix-row-cow-20261009/shapes/*.my into one program: each shape's
`main` becomes `shape_<id>`, its helpers and records get the shape id as a suffix, and
the new `main` runs every shape in order. Writes the program and its expected stdout."""
import pathlib, re, sys

here = pathlib.Path(__file__).resolve().parent.parent
out_program, out_expected = map(pathlib.Path, sys.argv[1:3])
parts, mains, expected = [], [], []
for path in sorted((here / "shapes").glob("*.my")):
    sid = path.stem.split("_")[0] if not path.stem.startswith("r_") else path.stem.replace("_", "")
    text = path.read_text()
    expected += [l[len("# expect: "):] for l in text.splitlines() if l.startswith("# expect: ")]
    body = "\n".join(l for l in text.splitlines() if not l.startswith("#"))
    names = [n for n in re.findall(r"^(?:def|record) (\w+)", body, re.M) if n != "main"]
    for n in names:
        body = re.sub(rf"\b{n}\b", f"{n}_{sid}", body)
    body = body.replace("def main(out: Stream) -> int:", f"def shape_{sid}(out: Stream) -> int:")
    parts.append(f"# {path.name}\n" + body.strip() + "\n")
    mains.append(f"    _ = shape_{sid}(out)")
program = "\n\n".join(parts) + "\n\ndef main(out: Stream) -> int:\n" + "\n".join(mains) + "\n    return 0\n"
out_program.write_text(program)
out_expected.write_text("\n".join(expected) + "\n")
