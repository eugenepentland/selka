#!/usr/bin/env python3
"""S3 integer/float text, byte ranges and formatting, with fifteen oracle comparisons."""
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
        floats = ["0", "-0.0", "+0", "nan", "-NaN", "+INFINITY", "-inf", "0.125", "2.675", "9.995", "1.7976931348623157e308", "1.7976931348623159e308", "2.2250738585072014e-308", "4.9406564584124654e-324", "2.4703282292062327e-324", "1e-999", "1e+999", "  -1_2.5e+1\t", "1e+", "_1.0", "1__2", "1.2_", "١.0", "1\x00.0"]
        for _ in range(8):
            coefficient = ''.join(str(self.r.randrange(10)) for _ in range(self.r.randrange(1, 24)))
            split = self.r.randrange(len(coefficient)+1)
            floats.append(self.r.choice(['', '+', '-']) + coefficient[:split] + '.' + coefficient[split:] + 'e' + str(self.r.randrange(-330, 311)))
        # The retained-digit bound and sticky remainder must match the old parser.
        floats.append('0.' + '0'*self.r.randrange(740, 790) + str(self.r.randrange(1, 10)) + 'e+740')
        float_literal = ', '.join(json.dumps(s, ensure_ascii=False) for s in floats)
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
    float_texts = [{float_literal}]
    for text in float_texts:
        framed = ("prefix" + text + "suffix").encode()
        match float(text):
            case Some(value):
                out.print(str(value), f"{{value:.0f}}", f"{{value:.2f}}", f"{{value:.4e}}", f"{{value:.17g}}")
                match framed.parse_float_range(6, len(framed) - 6):
                    case Some(ranged):
                        if str(ranged) != str(value):
                            return 6
                    case None:
                        return 6
                buffer = byte_buffer([])
                if not buffer.append_float(value):
                    return 6
                if bytes(buffer) != str(value).encode():
                    return 6
            case None:
                if framed.parse_float_range(6, len(framed) - 6) != None:
                    return 6
                out.print("invalid", len(text))
    out.print(acc, str(18446744073709551615u64), f"{{seed:#020x}}", f"{{seed:+020d}}")
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
