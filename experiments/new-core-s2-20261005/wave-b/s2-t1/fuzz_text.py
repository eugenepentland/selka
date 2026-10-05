#!/usr/bin/env python3
"""Differential text programs: ASCII/non-ASCII loops, slices, find, split and bytes."""
import argparse
from pathlib import Path
import random
import subprocess
import tempfile

def quoted(text):
    return '"' + text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

def program(rng, index):
    text = ''.join(rng.choice('ab|éΩ🙂') for _ in range(rng.randrange(1, 40)))
    start, end = rng.randrange(-45, 45), rng.randrange(-45, 45)
    needle = rng.choice(['a', '|', 'é', 'Ω', '🙂', 'absent', ''])
    return f'''module text_{index:04}

def number(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return 0

def score(text: str) -> int:
    value = len(text)
    for octet in text.encode():
        value += octet ^ 7
    return value

def main(args: list[str], out: Stream) -> int:
    seed = number(args[0])
    original = {quoted(text)}
    changed = original
    for j in range(seed % 7):
        if j % 3 == 0:
            alias = changed
            changed += alias
        else:
            changed += "é🙂a"
    rebuilt = ""
    for ch in changed:
        rebuilt += ch
    sliced = changed[{start}:{end}]
    parts = changed.split("|")
    value = score(original) + score(changed) + score(rebuilt) + score(sliced) + score("::".join(parts))
    value += changed.find({quoted(needle)}) + len(parts)
    out.print(value)
    return 0
'''

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cases', type=int, default=50)
    parser.add_argument('--seed', type=int, required=True)
    parser.add_argument('--keep', type=Path, required=True)
    parser.add_argument('--mylang', required=True)
    parser.add_argument('--core', required=True)
    parser.add_argument('--features', default='all')
    args = parser.parse_args()
    args.keep.mkdir(parents=True, exist_ok=True)
    rng = random.Random(args.seed)
    compared = mismatches = 0
    with tempfile.TemporaryDirectory(prefix='fuzz-text.') as temporary:
        tmp = Path(temporary)
        for case in range(args.cases):
            source = args.keep / f'text_{case:04}.my'
            source.write_text(program(rng, case))
            old = tmp / 'old'
            built = subprocess.run([args.mylang, 'build', str(source), '-o', str(old), '--release', '--cache-dir', str(tmp / 'old-cache')], capture_output=True, text=True)
            if built.returncode:
                print(built.stderr); return 1
            expected = [subprocess.run([str(old), str(seed)], capture_output=True, text=True) for seed in (0, 1, 3, 7, 23)]
            for label, flags in [('debug', []), ('release', ['--release']), ('verify', ['--release', '--verify-facts'])]:
                new = tmp / label
                built = subprocess.run([args.core, 'build', str(source), '-o', str(new), '--cache-dir', str(tmp / 'core-cache'), *flags], capture_output=True, text=True)
                if built.returncode:
                    print(built.stderr); return 1
                for seed, before in zip((0, 1, 3, 7, 23), expected):
                    after = subprocess.run([str(new), str(seed)], capture_output=True, text=True)
                    compared += 1
                    if (before.returncode, before.stdout, before.stderr) != (after.returncode, after.stdout, after.stderr):
                        mismatches += 1
                        print(f'mismatch case={case} mode={label} seed={seed}: old={before.returncode,before.stdout,before.stderr} new={after.returncode,after.stdout,after.stderr}')
                        return 1
    print(f'cases={args.cases} compared={compared} mismatch={mismatches} fact=0 old_rejected=0 new_refused=0')
    return int(mismatches != 0)

if __name__ == '__main__':
    raise SystemExit(main())
