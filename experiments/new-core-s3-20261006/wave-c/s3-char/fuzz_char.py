#!/usr/bin/env python3
"""Extend the S3 text matrix with observable character branches and snapshots.

Use through the strict S3 qualification wrapper's explicit --harness option.
The original S3 generator and its UTF-8/method cases remain active. Every case
also exercises multiple character consumers, all UTF-8 widths, NUL, destination
growth and a saved output snapshot, with randomized literal branch selectors.
"""
import importlib.util
from pathlib import Path


BASE_PATH = Path(__file__).resolve().parents[2] / "wave-b/s3-t1/fuzz_text.py"
SPEC = importlib.util.spec_from_file_location("s3_extended_text", BASE_PATH)
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
ORIGINAL_PROGRAM = BASE.program


def program(rng, index):
    source = ORIGINAL_PROGRAM(rng, index)
    first = BASE.quoted(rng.choice(["a", "é", "€", "🙂", "\0"]))
    second = BASE.quoted(rng.choice(["B", "é", "€", "🙂", "\0"]))
    first, second = first.replace("\0", "\\0"), second.replace("\0", "\\0")
    before = '    rebuilt = ""\n    for ch in changed:\n        rebuilt += ch\n'
    after = f'''    fused = "\\0é€🙂" + changed
    fused_rebuilt = ""
    selected = ""
    matches = 0
    for ch in fused:
        if ch == {first}:
            matches += 1
            fused_rebuilt += ch
            selected += ch
        elif ch != {second}:
            fused_rebuilt += ch
            selected += "."
        else:
            fused_rebuilt += ch
            selected += ch
    saved = fused_rebuilt
    fused_rebuilt += "é"
'''
    if source.count(before) != 1:
        raise RuntimeError("S3 text generator reconstruction shape changed")
    source = source.replace(before, before + after)
    checksum = '    value += changed.find('
    if source.count(checksum) != 1:
        raise RuntimeError("S3 text generator checksum shape changed")
    return source.replace(checksum, '    value += score(fused_rebuilt) + score(selected) + score(saved) + matches\n' + checksum)


BASE.program = program


def main():
    return BASE.main()


if __name__ == "__main__":
    raise SystemExit(main())
