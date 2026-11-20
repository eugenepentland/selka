# Python text surface

`sorted` and list `.sort()` accept bytes elements and bytes or str keys, including recursively ordered record keys. Bytes
order by unsigned octets, a shorter prefix first. Sorting is stable; a key runs once per element.

```selka
func main() -> int:
    mut values = [b"\xff", b"a", b""]
    assert sorted(values) == [b"", b"a", b"\xff"]
    sort(mut values, reverse=True)
    assert values == [b"\xff", b"a", b""]
    return 0
```

## Trimming character sets

`strings.strip_chars(text, chars)`, `lstrip_chars`, `rstrip_chars` and the `bytes` functions of the same names take a
character set of the same family (duplicates ignored; not an affix). An empty set trims nothing. Without an argument,
str trims CPython Unicode 16.0.0 whitespace and bytes trims space, tab, newline, carriage return, vertical tab and form
feed. Split and classification functions keep their ASCII rules.

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

`find`, `rfind`, `index`, `rindex`, `count`, `startswith` and `endswith` accept `sub[, start[, end]]` on str and bytes.

- Bounds are nonnegative positional integers: a constant negative is `E_NEGATIVE_INDEX_REMOVED`; a computed one traps
  `R_TEXT_BOUNDS` (text) or `R_LIST_BOUNDS` (bytes). End clamps to the length; a start beyond the length is an invalid
  window.
- Indices count octets in text and bytes alike. A text endpoint inside a multi-byte scalar traps `R_TEXT_BOUNDARY`.
  `count` does not overlap.
- `strings.find` and `rfind` answer an `int?`; `strings.text_index` and `text_rindex` trap `R_SUBSTRING_NOT_FOUND`. A
  bounded search passes the window: `strings.find(text, needle, start, end)`.
- Python habit to Selka: `text.find(needle, start, end)` is `E_METHOD_REMOVED`; `selka fix` writes the function.
- `strings.char_find`, `char_rfind`, `char_index`, `char_rindex`, `char_count_of`, `char_startswith` and `char_endswith`
  count Unicode scalars.
- An empty needle matches every boundary in a valid window: find and index return start, the reverse variants end, count
  end-start+1, and the affix checks True. An invalid window gives -1, a checked miss, zero or False. Empty split
  separators and replace needles trap.

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

`repr(value)` returns CPython's spelling for str, bytes, every integer width, float and bool. Quotes and escapes follow
Unicode 16.0.0 printability, not the host locale. Float repr is the shortest round-trip binary64 with Python's exponent
layout and signed zero.

`repr` of a list, set, dictionary, option, record, result or fixed array is the text `print` writes, with text elements
quoted as above ([the text of a collection](text.md#the-text-of-a-collection)). Enums and None are outside this surface;
unsupported values are `E_REPR_TYPE`. A binding may shadow `repr`.

```selka
func main() -> int:
    assert repr("'") == "\"'\""
    assert repr("\u00a0") == "'\\xa0'"
    assert repr(b"\xff") == "b'\\xff'"
    assert repr(1e16) == "1e+16"
    assert repr(-0.0) == "-0.0"
    return 0
```
