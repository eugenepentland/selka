#!/usr/bin/env python3
"""S1 differential harness extended with shared live-place iteration programs."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main():
    spec = importlib.util.spec_from_file_location('s1', ROOT / 'experiments/new-core-s1-20261005/fuzz.py')
    s1 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s1)
    original = s1.Gen

    class Gen(original):
        def program(self):
            source = super().program()
            change = self.r.randrange(2, 100)
            loops = f'''
    live = [1, seed % 997 + 2]
    saved_live = live
    for at, value in enumerate(live):
        acc = (acc + value * {change}) % 1000003
        live[1] = seed % 991 + 3
        if at == 0:
            live.append({change})
            continue
    acc = (acc + fold(saved_live) * 3 + fold(live) * 5) % 1000003
    live = [1, 2]
    saved_live = live
    for value in live:
        bump(mut live, {change})
        acc = (acc + value + live[0]) % 1000003
        if len(live) >= 4:
            break
    acc = (acc + fold(saved_live) * 7 + fold(live)) % 1000003
    box = Bucket(0, [1, 2])
    saved_box = box
    for value in box.items:
        box.items[1] = {change}
        acc = (acc + value) % 1000003
    acc = (acc + fold(saved_box.items) * 11) % 1000003
    live = [1, 2]
    for value in live:
        live[1] = {change}
        live = [7, 8]
        acc = (acc + value) % 1000003
'''
            if self.r.randrange(4) == 0:
                loops += '''    live = [1, 2, 3]
    for value in live:
        acc = (acc + value) % 1000003
        _ = live.pop()
'''
            at = source.rindex('    out.print(')
            return source[:at] + loops + source[at:]

    s1.Gen = Gen
    return s1.main()


if __name__ == '__main__':
    raise SystemExit(main())
