# Text and strings

`str` is the language's Unicode text type: an immutable, garbage-collected value
with the same runtime shape as the [managed collections](managed-memory.md) and
the [`bytes`](bytes.md) byte string. This page covers the text surface itself —
scalar-value indexing, the Python string methods, `f"..."` interpolation, and the
two intrinsics that turn text back into numbers. Padding to a width, repetition
and number formatting live in the [`strings` module](standard-library.md#strings)
instead, because an intrinsic method takes no defaulted arguments.

## Managed Unicode strings

A `str` holds validated UTF-8 and is indexed by Unicode scalar value, not by byte
and not by grapheme cluster, so `len` counts scalar values and `text[0]` answers a
one-scalar `str`. Strings are immutable: there is no `text[i] = c` and no
`append`, and every operation that produces text — `+`, a slice, `split`, `join`,
a method — allocates a fresh string and carries the `managed_allocation` effect.
Assignment shares one traced object, which is safe precisely because nothing can
change it. An index outside the string traps with `R_TEXT_BOUNDS`, while slices
clamp both endpoints and produce an empty string for a reversed interval, exactly
as list and byte-string slices do. Literals accept ordinary escapes including
`é`, and `str(value)` converts a scalar using Python's spellings.

```mylang
# doc: expect 42
def main() -> int:
    greeting = "héllo"
    if len(greeting) != 5:
        return 1
    if greeting[1] != "é":
        return 2
    if greeting[-1] != "o":
        return 3
    if greeting[1:3] != "él":
        return 4
    if greeting[2:99] != "llo":
        return 5
    if greeting[3:1] != "":
        return 6
    joined = greeting + " " + "world"
    parts = joined.split(" ")
    if len(parts) != 2:
        return 7
    if "-".join(parts) != "héllo-world":
        return 8
    alias = greeting
    if alias != greeting:
        return 9
    if str(7) != "7":
        return 10
    if str(True) != "True":
        return 11
    return len(joined) * 4 - len(greeting) + 3
```

## String methods

`str` answers `strip`, `lstrip`, `rstrip`, `upper`, `lower`, `zfill(width)`,
`replace(old, new)`, `find(sub)`, `count(sub)`, `startswith`, `endswith`,
`isdigit`, `isalpha`, `isspace`, `split(separator)` and `splitlines()`. Each one
returns a fresh
value and leaves the receiver and every alias untouched. `find` answers `-1`
rather than raising when the needle is absent, the three classifications answer
`False` for empty text, case mapping covers ASCII letters and leaves every other
scalar alone, and `zfill` keeps a leading sign in front of its padding. An empty
needle traps `R_EMPTY_SEPARATOR`, and these methods are rejected on lists and
dictionaries. `ljust` and `rjust` are absent; use
[`strings.pad_left` and `strings.pad_right`](standard-library.md#strings). Every
one of these methods runs on the QBE native backend, over a single immutable
text runtime.

```mylang
# doc: expect 43
def main() -> int:
    escaped = "caf\u00e9"
    if escaped != "café":
        return 1
    padded = "  ready  "
    if padded.strip() != "ready":
        return 2
    if padded.lstrip() != "ready  ":
        return 3
    if padded.rstrip() != "  ready":
        return 4
    if "Mylang".upper() != "MYLANG":
        return 5
    if "Mylang".lower() != "mylang":
        return 6
    if "7".zfill(3) != "007":
        return 7
    if "-7".zfill(4) != "-007":
        return 8
    if "banana".replace("na", "NA") != "baNANA":
        return 9
    if "banana".find("na") != 2:
        return 10
    if "banana".find("zz") != -1:
        return 11
    if "banana".count("na") != 2:
        return 12
    if not "banana".startswith("ban"):
        return 13
    if not "banana".endswith("ana"):
        return 14
    if not "42".isdigit():
        return 15
    if "".isdigit():
        return 16
    if not "abc".isalpha():
        return 17
    if not " \t".isspace():
        return 18
    lines = "a\nb\r\nc".splitlines()
    if len(lines) != 3:
        return 19
    if padded != "  ready  ":
        return 20
    return len(escaped) * 10 + len(lines)
```

## Splitting on whitespace

`text.split()` with no argument is Python's whitespace split: it breaks the
receiver on runs of the same six ASCII whitespace scalars `isspace()` accepts —
space, tab, line feed, carriage return, vertical tab and form feed — keeps only
the nonempty pieces and answers `list[str]`. Leading, trailing and doubled
whitespace therefore produce no empty string, and `"".split()` is empty.
`bytes.split()` agrees on the octets and answers `list[bytes]`.
`text.split(separator)` keeps its exact-separator meaning: adjacent separators
still produce empty pieces, an empty needle still traps `R_EMPTY_SEPARATOR`, and
the separator form still requires its one argument. A call with any other
argument count is rejected with the callee's rendered signature, and the `split`
rejection also carries the accepted spelling as an `alternative` note.

```mylang
# doc: expect 42
def main() -> int:
    words = "  one two\tthree  ".split()
    if len(words) != 3:
        return 1
    if words[1] != "two":
        return 2
    if len("".split()) != 0:
        return 3
    if len("a,,b".split(",")) != 3:
        return 4
    if len(b" x\ty ".split()) != 2:
        return 5
    return len(words) * 14
```

## Unicode scalar values

`ord(text)` answers the one Unicode scalar value of `text`, and `chr(code)`
answers the one-scalar text for a scalar value. `ord` of a one-scalar literal
folds at check time to an `int` constant, so `byte == ord("m")` compiles to an
immediate comparison with no call and no allocation; any other text is measured
at run time. Both builtins trap `R_TEXT_SCALAR` rather than answering a partial
value: `ord` requires exactly one scalar, and `chr` requires a code point in
`0..0x10FFFF` outside the surrogate range. The [`strings`
module](standard-library.md#strings) keeps its `Result` forms — `strings.ord` and
`strings.chr` — for callers that would rather handle the failure.

```mylang
# doc: expect 42
def byte_code(marker: str) -> bool:
    return ord(marker) == 109


def main() -> int:
    if ord("A") != 65:
        return 1
    marker = "m"
    if ord(marker) != 109:
        return 2
    if not byte_code(marker):
        return 3
    if chr(65) != "A":
        return 4
    if ord(chr(233)) != 233:
        return 5
    if len(chr(128512)) != 1:
        return 6
    return ord("A") - 23
```

## Format strings

An `f"..."` literal interpolates each `{expression}` hole with the same conversion
`str(value)` performs, then concatenates the literal pieces and the converted
holes into one new `str`. A hole holds exactly one ordinary expression — a call,
an operator, an index, a field, even a nested format string — and is checked in
its own source position. A hole takes any value `print` can render — a list, a
dictionary, a record, an enum case, a result, an option or a byte string as well
as a scalar — and renders it through the very renderer `print` calls, so one
value has one spelling wherever it is written. `{{` and `}}` write single braces,
ordinary escapes apply to the literal pieces, and `f""` is empty text. An empty
hole, an unmatched or unterminated brace, more than one expression in a hole, a
format specification after `:`, and a value with no rendering — a capability, an
open file or a callback — are all rejected, so round or pad a number before
interpolating it. The `f` prefix is Python-surface only.

```mylang
# doc: expect 42
record Point:
    x: int
    y: int

def main() -> int:
    name = "ada"
    count = 3
    ratio = 1.5
    line = f"{name} has {count} items"
    if line != "ada has 3 items":
        return 1
    if f"{count + 1}" != "4":
        return 2
    if f"{ratio}" != "1.5":
        return 3
    if f"{True}" != "True":
        return 4
    if f"{{literal}}" != "{literal}":
        return 5
    if f"" != "":
        return 6
    values = [1, 2, 3]
    if f"{len(values)}" != "3":
        return 7
    if f"{values[0]}" != "1":
        return 8
    if f"outer {f'inner {count}'}" != "outer inner 3":
        return 9
    spot = Point(x=1, y=2)
    if f"{spot.x}" != "1":
        return 10
    if f"{name.upper()}" != "ADA":
        return 11
    if f"{values} {spot}" != "[1, 2, 3] Point(x=1, y=2)":
        return 12
    return len(line) * 3 - 3
```

## Parsing numbers from text

`int(text)` answers `Option[int]` and `float(text)` answers `Option[float]`. The
language has no exceptions, so text that is not a number produces `None` and the
caller decides what that means; `match` with `case Some(value)` and `case None`
is the way to read the answer.

Both accept one pinned base-10 grammar, the one Python's own `int()` and
`float()` accept for base 10: optional surrounding ASCII whitespace, an optional
`+` or `-` sign, then ASCII decimal digits that may be separated by single `_`
characters sitting between two digits. `float` additionally accepts a `.`
fraction, an `e`/`E` exponent with its own optional sign and digits, and the
case-insensitive spellings `inf`, `infinity` and `nan`. An alternate base such as
`0x10`, a non-ASCII digit, an interior space, a trailing character, a dangling
separator and empty text all answer `None`. `int` also answers `None` for a value
the signed 64-bit range cannot hold, so a valid-looking but oversized literal
never silently wraps, while `float` is correctly rounded: a magnitude above
binary64's range answers an infinity and one below it a signed zero.

One compiled grammar serves every build, and one shared table of vectors drives
the Zig unit test and the native driver, so `mylang run` and `mylang build`
cannot disagree about which text is a number or about the value it names.

```mylang
# doc: expect 8122
def port_of(text: str) -> int:
    match int(text):
        case Some(value):
            return value
        case None:
            return -1

def main() -> int:
    if port_of("8080") != 8080:
        return 1
    if port_of("+7") != 7:
        return 2
    if port_of("-7") != -7:
        return 3
    if port_of("1_000") != 1000:
        return 4
    if port_of(" 8080 ") != 8080:
        return 5
    if port_of("80x") != -1:
        return 6
    if port_of("") != -1:
        return 7
    if port_of("0x10") != -1:
        return 8
    if port_of("9223372036854775808") != -1:
        return 9
    if port_of("1_") != -1:
        return 10
    match float("2.5"):
        case Some(value):
            if value != 2.5:
                return 11
        case None:
            return 12
    match float("nan"):
        case Some(value):
            if value == value:
                return 13
        case None:
            return 14
    match float("two"):
        case Some(value):
            return int(value)
        case None:
            pass
    return port_of("8080") + port_of(" 42 ")
```
