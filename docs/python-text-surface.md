# Python text surface

`sorted` and list `.sort()` accept bytes elements and bytes or str keys, including
recursively ordered record keys. Bytes order by unsigned octets, with a shorter prefix first.
Sorting is stable, including reverse sorting, and a key runs once per element.

```selka
func main() -> int:
    mut values = [b"\xff", b"a", b""]
    assert sorted(values) == [b"", b"a", b"\xff"]
    sort(mut values, reverse=True)
    assert values == [b"\xff", b"a", b""]
    return 0
```

## Trimming character sets

`strings.strip_chars(text, chars)`, `lstrip_chars` and `rstrip_chars`, and the `bytes` functions of the same
names, take a same-family character set; it is a set, with duplicates ignored, rather than an affix.
An empty set trims nothing. Without an argument, str uses CPython Unicode 16.0.0
whitespace; bytes uses space, tab, newline, carriage return, vertical tab and form
feed. The separate split and classification functions retain their ASCII rules.

```selka
import bytes
import strings

func main() -> int:
    assert strings.strip_chars("éabvaluebaé", "abé") == "value"
    assert strings.strip("\u2007value\u3000") == "value"
    assert bytes.strip_chars(b"\xff\x00value\xff", b"\xff\x00") == b"value"
    return 0
```

## Ranged search

`find`, `rfind`, `index`, `rindex`, `count`, `startswith` and `endswith` accept
`sub[, start[, end]]` on str and bytes. Bounds are nonnegative positional integers:
constant negatives report `E_NEGATIVE_INDEX_REMOVED`; computed negatives trap
`R_TEXT_BOUNDS` for text or `R_LIST_BOUNDS` for bytes. End clamps to the length.
A positive start beyond the length remains an invalid window. Text and bytes
indices both count octets; answers are global offsets in the receiver. A text
endpoint inside a multi-byte scalar traps `R_TEXT_BOUNDARY` at the call. Count is
nonoverlapping. The unbounded searches are the functions `strings.find` and
`strings.rfind`, which answer an `int?` offset, and `strings.text_index` and
`strings.text_rindex`, which trap `R_SUBSTRING_NOT_FOUND` when the needle is
absent. A bounded search passes the window to the same functions,
`strings.find(text, needle, start, end)` and the same for `rfind`, `text_index` and
`text_rindex`; the method spelling `text.find(needle, start, end)`, which answered
`-1`, is refused (`E_METHOD_REMOVED`, and `selka fix` writes the function). The scalar-window spellings are the
helpers `strings.char_find`, `char_rfind`, `char_index`, `char_rindex`,
`char_count_of`, `char_startswith` and `char_endswith`, whose bounds and answers
count Unicode scalars.

An empty needle matches every boundary in a valid window: find/index return
start, reverse variants return end, count returns end-start+1, and both affix
checks return True. Invalid or reversed windows yield -1, a checked miss, zero,
or False respectively. Empty split separators and replace needles still trap.

```selka
import bytes
import strings

func main() -> int:
    assert strings.rfind("aéaéa", "é") == Some(4)
    assert strings.find("λbλb", "b", 2) == Some(2)
    assert strings.char_rfind("aéaéa", "é", 1, max(strings.char_count("aéaéa") - 1, 0)) == 3
    assert strings.char_find("abc", "", 3, 3) == 3
    assert strings.char_find("abc", "", 4, 9) == -1
    assert bytes.count(b"ababa", b"aba", 0, 5) == 1
    return 0
```

## Scalar repr

`repr(value)` returns CPython's spelling for str, bytes, every integer width,
float and bool. String quote choice and escapes follow static Unicode 16.0.0
printability data, independent of host locales. Float repr is shortest round-trip
binary64 with Python exponent layout and signed zero. Ordinary printing, str
conversion and Zig-compatible formatting helpers retain their own formatting.

`repr` of a list, a set, a dictionary, an option, a record, a result or a fixed array is the text `print` writes for it,
with each text element quoted as above ([the text of a collection](text.md#the-text-of-a-collection)). Enums,
None, tuple affixes and explicit None charsets are outside this typed surface. Repr reports `E_REPR_TYPE` for
unsupported values.
Like other names, a binding or declaration may shadow the repr builtin.

```selka
func main() -> int:
    assert repr("'") == "\"'\""
    assert repr("\u00a0") == "'\\xa0'"
    assert repr(b"\xff") == "b'\\xff'"
    assert repr(1e16) == "1e+16"
    assert repr(-0.0) == "-0.0"
    return 0
```
