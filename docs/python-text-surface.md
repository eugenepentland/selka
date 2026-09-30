# Python text surface

`sorted` and list `.sort()` accept bytes elements and bytes or str keys, including
flat tuple keys. Bytes order by unsigned octets, with a shorter prefix first.
Sorting is stable, including reverse sorting, and a key runs once per element.

```mylang
def main() -> int:
    values = [b"\xff", b"a", b""]
    assert sorted(values) == [b"", b"a", b"\xff"]
    values.sort(reverse=True)
    assert values == [b"\xff", b"a", b""]
    return 0
```

## Trimming character sets

`strip(chars)`, `lstrip(chars)` and `rstrip(chars)` accept a same-family character
set on str or bytes; it is a set, with duplicates ignored, rather than an affix.
An empty set trims nothing. Without an argument, str uses CPython Unicode 16.0.0
whitespace; bytes uses space, tab, newline, carriage return, vertical tab and form
feed. The separate split and classification methods retain their ASCII rules.

```mylang
def main() -> int:
    assert "éabvaluebaé".strip("abé") == "value"
    assert "\u2007value\u3000".strip() == "value"
    assert b"\xff\x00value\xff".strip(b"\xff\x00") == b"value"
    return 0
```

## Ranged search

`find`, `rfind`, `index`, `rindex`, `count`, `startswith` and `endswith` accept
`sub[, start[, end]]` on str and bytes. Bounds are positional integers: negative
bounds count from the end, negative results clamp to zero and end clamps to the
length. A positive start beyond the length remains an invalid window. Text
indices count Unicode scalars; bytes indices count octets; answers are global
indices in the receiver. Count is nonoverlapping. Index and rindex trap
`R_SUBSTRING_NOT_FOUND` when absent; find and rfind return -1.

An empty needle matches every boundary in a valid window: find/index return
start, reverse variants return end, count returns end-start+1, and both affix
checks return True. Invalid or reversed windows yield -1, a checked miss, zero,
or False respectively. Empty split separators and replace needles still trap.

```mylang
def main() -> int:
    assert "aéaéa".rfind("é", 1, -1) == 3
    assert "abc".find("", 3, 3) == 3
    assert "abc".find("", 4, 9) == -1
    assert b"ababa".count(b"aba", 0, 5) == 1
    return 0
```

## Scalar repr

`repr(value)` returns CPython's spelling for str, bytes, every integer width,
float and bool. String quote choice and escapes follow static Unicode 16.0.0
printability data, independent of host locales. Float repr is shortest round-trip
binary64 with Python exponent layout and signed zero. Ordinary printing, str
conversion and Zig-compatible formatting helpers retain their own formatting.

Lists, dictionaries, records, None, tuple affixes and explicit None charsets are
outside this typed surface. Repr reports `E_REPR_TYPE` for unsupported values.
Like other names, a binding or declaration may shadow the repr builtin.

```mylang
def main() -> int:
    assert repr("'") == "\"'\""
    assert repr("\u00a0") == "'\\xa0'"
    assert repr(b"\xff") == "b'\\xff'"
    assert repr(1e16) == "1e+16"
    assert repr(-0.0) == "-0.0"
    return 0
```
