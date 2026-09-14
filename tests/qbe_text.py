#!/usr/bin/env python3
"""Native parity for every Python string method and the pinned number grammar.

The method cases compare freshly checked VM execution against the QBE build, with
and without collection stress. The number cases are generated from
``src/number_grammar.txt`` — the same table ``src/number_text_test.zig`` reads —
so the documented grammar, the VM and the native runtime cannot drift apart.
"""
import argparse
from pathlib import Path
import struct
import sys
import tempfile

from qbe_parity import ROOT, run, signature

ESCAPES = {'s': ' ', 't': '\t', 'n': '\n', 'r': '\r', 'v': '\v', 'f': '\f', '\\': '\\'}
BATCH = 24
PRELUDE = '''def show_int(text: str) -> str:
    match int(text):
        case Some(value):
            return f"{value}"
        case None:
            return "none"

def show_float(text: str) -> str:
    match float(text):
        case Some(value):
            return f"{value}"
        case None:
            return "none"

def main() -> int:
'''


def cases():
    """Guest programs covering every documented string method and its traps."""
    yield '''def main() -> int:
    padded = "  value  "
    if padded.strip() != "value":
        return 1
    if padded.lstrip() != "value  ":
        return 2
    if padded.rstrip() != "  value":
        return 3
    if "\\t\\n\\u000b\\u000c\\r x \\r ".strip() != "x":
        return 4
    if "".strip() != "":
        return 5
    if "   ".strip() != "":
        return 6
    if padded != "  value  ":
        return 7
    return len(padded.strip()) * 3
'''
    yield '''def main() -> int:
    if "aB\\u00e9".upper() != "AB\\u00e9":
        return 1
    if "aB\\u00e9".lower() != "ab\\u00e9":
        return 2
    if "".upper() != "":
        return 3
    if "7".zfill(3) != "007":
        return 4
    if "-7".zfill(4) != "-007":
        return 5
    if "+7".zfill(4) != "+007":
        return 6
    if "1234".zfill(2) != "1234":
        return 7
    if "".zfill(3) != "000":
        return 8
    if "-".zfill(3) != "-00":
        return 9
    if "7".zfill(0 - 5) != "7":
        return 10
    if "7".zfill(0) != "7":
        return 11
    return len("7".zfill(9))
'''
    yield '''def main() -> int:
    line = "banana"
    if line.find("na") != 2:
        return 1
    if line.find("zz") != 0 - 1:
        return 2
    if line.find("banana") != 0:
        return 3
    if line.find("bananas") != 0 - 1:
        return 4
    if line.count("na") != 2:
        return 5
    if line.count("ana") != 1:
        return 6
    if line.count("zz") != 0:
        return 7
    if "".count("a") != 0:
        return 8
    if not line.startswith("ban"):
        return 9
    if not line.endswith("ana"):
        return 10
    if line.startswith("nan"):
        return 11
    if not line.startswith(""):
        return 12
    if not line.endswith(""):
        return 13
    if line.startswith("bananas"):
        return 14
    return line.count("a") * 10 + line.find("n")
'''
    yield '''def main() -> int:
    if "banana".replace("na", "NA") != "baNANA":
        return 1
    if "aaa".replace("aa", "b") != "ba":
        return 2
    if "abc".replace("x", "y") != "abc":
        return 3
    if "aaa".replace("a", "") != "":
        return 4
    if len("".replace("a", "b")) != 0:
        return 5
    if "aa".replace("a", "bb") != "bbbb":
        return 6
    lines = "a\\nb\\r\\nc\\rd".splitlines()
    if len(lines) != 4:
        return 7
    if lines[3] != "d":
        return 8
    if len("".splitlines()) != 0:
        return 9
    if len("a\\n".splitlines()) != 1:
        return 10
    if len("\\n\\n".splitlines()) != 2:
        return 11
    return len(lines) * 10
'''
    yield '''def main() -> int:
    if not "42".isdigit():
        return 1
    if "4a".isdigit():
        return 2
    if "".isdigit():
        return 3
    if not "abZ".isalpha():
        return 4
    if "ab1".isalpha():
        return 5
    if "".isalpha():
        return 6
    if not " \\t\\n\\r\\u000b\\u000c".isspace():
        return 7
    if " a".isspace():
        return 8
    if "".isspace():
        return 9
    if "\\u00e9".isalpha():
        return 10
    if "\\uff14".isdigit():
        return 11
    return 42
'''
    yield '''def main() -> int:
    text = "caf\\u00e9 na\\u00efve"
    if text.upper() != "CAF\\u00e9 NA\\u00efVE":
        return 1
    if text.find("\\u00e9") != 3:
        return 2
    if text.count("a") != 2:
        return 3
    if not text.startswith("caf"):
        return 4
    if not text.endswith("ve"):
        return 5
    if text.strip() != text:
        return 6
    return len(text)
'''
    # Iterating text visits its scalar values, and enumerate adds the position.
    yield '''def main() -> int:
    total = 0
    for letter in "h\\u00e9llo":
        total += len(letter)
    for index, letter in enumerate("ab"):
        total += index * 2 + len(letter)
    letters = [letter.upper() for letter in "abc"]
    if len(letters) != 3:
        return 1
    if letters[2] != "C":
        return 2
    for line in "a\\nb".splitlines():
        total += len(line.strip())
    return total
'''
    # Fresh values survive repeated collection while retained aliases stay equal.
    yield '''def make() -> list[str]:
    return "a-b-c".upper().split("-")

def main() -> int:
    kept = make()
    i = 0
    while i < 60:
        _ = ("  x  ".strip() + "y").replace("x", "z").splitlines()
        i += 1
    if kept[2] != "C":
        return 1
    if "-".join(kept) != "A-B-C":
        return 2
    return len(kept) + len("-".join(kept))
'''
    # Methods reached through parameters rather than literal receivers.
    yield '''def trimmed(text: str) -> str:
    return text.strip()

def widened(text: str, width: int) -> str:
    return text.zfill(width)

def main() -> int:
    if trimmed("  a  ") != "a":
        return 1
    if widened("5", 4) != "0005":
        return 2
    values = ["  one ", " two", "three  "]
    total = 0
    for value in values:
        total += len(trimmed(value))
    return total
'''
    # Traps: an empty needle is rejected by find, count and replace alike.
    yield '''def main() -> int:
    return "abc".find("")
'''
    yield '''def main() -> int:
    return "abc".count("")
'''
    yield '''def main() -> int:
    return len("abc".replace("", "x"))
'''


def unescape(text):
    """Expand the vector table's escapes into the scalars it names."""
    out, at = [], 0
    while at < len(text):
        if text[at] != '\\':
            out.append(text[at])
            at += 1
            continue
        if text[at + 1] == 'u':
            out.append(chr(int(text[at + 2:at + 6], 16)))
            at += 6
            continue
        out.append(ESCAPES[text[at + 1]])
        at += 2
    return ''.join(out)


def vectors():
    """Every shared vector as (kind, input text, expected outcome)."""
    found = []
    for line in (ROOT / 'src/number_grammar.txt').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        kind, text, outcome = line.split('|')
        found.append((kind, unescape(text), outcome))
    return found


def literal(text):
    """Spell one input as a mylang string literal the lexer accepts."""
    out = ['"']
    for scalar in text:
        if scalar in ('"', '\\'):
            out.append('\\' + scalar)
        elif ' ' <= scalar <= '~':
            out.append(scalar)
        else:
            out.append('\\u%04x' % ord(scalar))
    return ''.join(out) + '"'


def batches():
    """Group the vectors into guest programs that print one answer per line."""
    found = vectors()
    for start in range(0, len(found), BATCH):
        chunk = found[start:start + BATCH]
        # Both helpers are always called, so neither is an unused declaration.
        chunk = chunk + [('int', '0', '0'), ('float', '0', '0.0')]
        body = ''.join(f'    print(show_{kind}({literal(text)}))\n' for kind, text, _ in chunk)
        yield PRELUDE + body + '    return 0\n', chunk


def matches(kind, printed, outcome):
    """Whether one printed answer is the value the shared table pins."""
    if outcome == 'none':
        return printed == 'none'
    if printed == 'none':
        return False
    if kind == 'int':
        return printed == str(int(outcome))
    if outcome == 'nan':
        return printed == 'nan'
    return struct.pack('<d', float(printed)) == struct.pack('<d', float(outcome))


def build(args, source, output, cache):
    return run([sys.executable, ROOT / 'scripts/qbe.py', source, '-o', output,
                '--compiler', args.compiler, '--qbe', args.qbe, '--zig', args.zig,
                '--cache-dir', cache])


def check(args, source, output, cache, text):
    """Build one guest program and compare both backends, plain and stressed."""
    source.write_text(text)
    built = build(args, source, output, cache)
    assert built.returncode == 0, (text, built.stderr.decode())
    vm = run([args.compiler, 'run', source, '--print-result'])
    results = []
    for options in ([], ['--gc-stress']):
        native = run([output, *options])
        assert signature(vm) == signature(native), (text, options, vm, native)
        results.append(native)
    return results[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-text-') as directory:
        temp = Path(directory)
        source, output, cache = temp / 'case.my', temp / 'program', temp / 'cache'
        methods = 0
        for text in cases():
            check(args, source, output, cache, text)
            methods += 1
        parsed = 0
        for text, chunk in batches():
            native = check(args, source, output, cache, text)
            lines = native.stdout.decode().splitlines()
            assert len(lines) > len(chunk), (text, lines)
            for (kind, value, outcome), printed in zip(chunk, lines):
                assert matches(kind, printed, outcome), (kind, value, outcome, printed)
            parsed += len(chunk) - 2
    print(f'QBE text parity: {methods} method cases and {parsed} number vectors passed')


if __name__ == '__main__':
    main()
