#!/usr/bin/env python3
"""Numeric text differential generation under the S1 fifteen-comparison protocol."""
import importlib.util
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]

class Gen:
    def __init__(self, rng, features):
        self.r = rng

    def program(self):
        strings = ["9223372036854775807", "9223372036854775808", "-9223372036854775808", "-9223372036854775809", "18446744073709551615", "18446744073709551616", "+", "-", "", "1__2", "_1", "1_", "é12", " \t-001_023\r\n", "000000000000000000000000000000000000000000001"]
        for width in range(1, 20):
            digits = ''.join(str(self.r.randrange(10)) for _ in range(width))
            sign = self.r.choice(['', '+', '-'])
            text = sign + digits
            if self.r.randrange(4) == 0:
                text = ' \t' + text + '\r\n'
            if self.r.randrange(4) == 0:
                text = text[:-1] + '_' + text[-1:]
            if self.r.randrange(5) == 0:
                text += self.r.choice(['x', '_', '🙂'])
            strings.append(text)
        literal = ', '.join(json.dumps(s, ensure_ascii=False) for s in strings)
        prefix = json.dumps(self.r.choice(['', '-', '+', '  +00', '000000000']), ensure_ascii=False)
        suffix = json.dumps(self.r.choice(['', ' ', '_1', 'x']), ensure_ascii=False)
        return f'''def number(text: str, fallback: int) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return fallback

def main(args: list[str], out: Stream) -> int:
    seed = number(args[2], 7)
    texts = [{literal}]
    texts.append({prefix} + str(seed % 1234567) + {suffix})
    acc = 0
    for text in texts:
        match int(text):
            case Some(value):
                acc = (acc + value % 1000003) % 1000003
                shown = str(value)
                if number(shown, 999) != value:
                    return 6
                out.print(shown)
            case None:
                acc = (acc + len(text) * 31) % 1000003
    out.print(acc, str(18446744073709551615u64))
    return acc % 7
'''

def main():
    spec = importlib.util.spec_from_file_location('number_s1', ROOT / 'experiments/new-core-s1-20261005/fuzz.py')
    harness = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(harness)
    harness.Gen = Gen
    return harness.main()

if __name__ == '__main__':
    raise SystemExit(main())
