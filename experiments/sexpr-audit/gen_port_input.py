#!/usr/bin/env python3
"""Generate a numeric-heavy S-expression corpus for the sexpr port.

The port's cost is dominated by numeric leaves (integers, decimals, `mm`/`mil`
measures, SI-suffixed literals) and by the printer's width measurement, so the
generator emits one balanced form per record mixing those kinds with atoms and
strings. The construction is deterministic — no RNG, no clock — so the byte
count alone decides the output, and two runs of the same size agree byte for
byte.

Usage: gen_port_input.py OUTPUT [BYTES]
"""
import io
import pathlib
import sys

LAYERS = ['"F.Cu"', '"B.Cu"', '"Edge.Cuts"', '"F.SilkS"', '"In1.Cu"']
UNITS = ["0.254mm", "10mil", "2.5mm", "100mil", "0.15mm", "6mil"]
SI = ["220k", "4.7k", "1M", "10u", "100n", "22p", "100nF", "1uH", "10mA", "3.3V", "47R", "10%"]

# One form per record: `module` holds `pad`, which holds `net`; `net` holds a
# nested `stack` (deeper than the printer's depth-3 width cutoff), a string with
# escapes, and a `tol` percentage. The six closing parentheses close `max`,
# `tol`, `net`, `pad` and `module` plus the record's own line.
FORM = (
    '(module (name "m{n}") (layer {layer})\n'
    "  (pad (id {i}) (at {x}.{fx} {y}.{fy}) (size {unit} {unit}) (angle {angle})\n"
    "    (net {scale} (code {i}) (rank {rank}) (atom{a} net-{net})\n"
    "      (stack (depth (a (b (c (d {scale} {unit} {i} -{i}))))))\n"
    '      (text "keep \\"escaped\\" atoms verbatim")\n'
    "      (tol {tol}% (max {scale2})))))\n"
)


def balanced(text):
    """Whether every parenthesis is closed outside a string literal."""
    depth = 0
    in_string = False
    escaped = False
    for char in text:
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0 and not in_string


def generate(target_bytes):
    out = io.StringIO()
    index = 0
    while out.tell() < target_bytes:
        out.write(FORM.format(
            n=index % 97,
            layer=LAYERS[index % len(LAYERS)],
            i=index,
            x=(index * 37) % 5000,
            fx=index % 1000,
            y=(index * 91) % 5000,
            fy=index % 100,
            unit=UNITS[index % len(UNITS)],
            angle=index % 360,
            scale=SI[index % len(SI)],
            rank=(index * 7) % 1000,
            a=index % 10,
            net=index % 251,
            tol=index % 5,
            scale2=SI[(index + 3) % len(SI)],
        ))
        index += 1
    return out.getvalue(), index


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: gen_port_input.py OUTPUT [BYTES]")
    output = pathlib.Path(sys.argv[1])
    target = int(sys.argv[2]) if len(sys.argv) > 2 else 4_000_000
    text, forms = generate(target)
    if not balanced(text):
        sys.exit("generated corpus is not balanced")
    output.write_text(text)
    print(f"{output}: {len(text)} bytes, {forms} forms, balanced")


main()
