# Text and strings

`str` is Selka's Unicode text type: an immutable owned UTF-8 value (see [managed collections](managed-memory.md) and [`bytes`](bytes.md)). This page covers indexing, ordering, repetition, the `strings` functions, `f"..."` formatting and number parsing. The [`strings` module](standard-library.md#strings) keeps further helpers.

## Managed Unicode strings

A `str` holds validated UTF-8 and has **octet** positions, not scalar positions. Strings are immutable: no `text[i] = c`, no `append`, and every operation that produces text (`+`, `split`, `join`, any `strings` function) answers a new string. `copy(value)` makes an independent owned string. A slice borrows its source, so a store or a return needs an explicit copy ([slices](#slices-are-views-of-their-source)).

Literals accept the ordinary escapes, `\u00e9` for `é` included ([a scalar in a literal](#writing-a-scalar-in-a-literal)). `str(value)` converts a scalar using Python's spellings and a collection as [the text of a collection](#the-text-of-a-collection).

```selka
# doc: expect 42
import strings

func main() -> int:
    mut greeting = "héllo"
    if strings.char_count(greeting) != 5:
        return 1
    if strings.char_at(greeting, 1) != "é":
        return 2
    if strings.char_at(greeting, strings.char_count(greeting) - 1) != "o":
        return 3
    if strings.char_slice(greeting, 1, 3) != "él":
        return 4
    if strings.char_slice(greeting, 2, 99) != "llo":
        return 5
    if strings.char_slice(greeting, 3, 1) != "":
        return 6
    mut joined = greeting + " " + "world"
    mut parts = strings.split(joined, " ")
    if len(parts) != 2:
        return 7
    if strings.join(parts, "-") != "héllo-world":
        return 8
    mut alias = copy(greeting)
    if alias != greeting:
        return 9
    if str(7) != "7":
        return 10
    if str(True) != "True":
        return 11
    return strings.char_count(joined) * 4 - strings.char_count(greeting) + 3
```

## Ordering and repetition

`<`, `<=`, `>` and `>=` order `str` by Unicode code point and `bytes` by octet, lexicographically with a proper prefix first, exactly as Python does: `"Zebra" < "apple"`, `"é" > "z"`. It is not a locale collation. `str` and `bytes` never compare with each other, and no other collection is ordered (`E_TEXT_OPERATOR`).

`strings.repeat(text, count)` and `byte_builder.repeat(data, count)` repeat text and bytes (a nonpositive count gives an empty value); `lists.filled(count, value)` fills a list. `selka fix` writes Python's `"-" * width` as `strings.repeat("-", width)` and adds the import.

```selka
import lists
import strings
# doc: expect 42
func main() -> int:
    if not ("apple" < "banana" <= "banana" and "ab" < "abc" and "Zebra" < "apple"):
        return 1
    if b"\xff" < b"a":
        return 2
    mut rule = strings.repeat("-", 3)
    if rule != "---" or strings.repeat("ab", 2) != "abab" or strings.repeat("x", 0) != "":
        return 3
    mut grid = lists.filled(4, 0)
    if grid != [0, 0, 0, 0]:
        return 4
    return strings.char_count(strings.repeat("ab", 3)) * 7
```

## Text is bytes; scalars have helpers

Text is bytes underneath (a Unicode scalar is one to four octets), so the short spellings count octets:

| Spelling | Meaning |
|---|---|
| `len(text)` | length in octets |
| `text[i]` | the octet at byte offset `i`, an `int` |
| `text[a:b]` | a borrowed view of the octets `[a, b)` |

A negative bound or an index past the end traps `R_TEXT_BOUNDS`; a slice end past the length clamps; a reversed interval is empty. An endpoint inside a multi-byte scalar traps `R_TEXT_BOUNDARY` at the call ([trap reports](tooling/native-build.md#trap-reports)), so a slice of valid text is valid text. A constant negative position is `E_NEGATIVE_INDEX_REMOVED` (`selka fix` repairs a certain one). A cut at a fixed width (`text[at:at + 1]`) traps at the first long character: `strings.cut_octets(text, limit)` ends a cut at a character, and `selka lint` reports the shape (`L_TEXT_SLICE_OCTETS`).

The scalar reading has its own words:

| Function | Answers |
|---|---|
| `strings.char_count(text)` | the number of scalars |
| `strings.char_at(text, index)` | the one-scalar `str` at a scalar position (the last: `char_count(text) - 1`) |
| `strings.char_slice(text, start, end)` | an owned `str` of the scalars `[start, end)`; an omitted endpoint is `None`; the end clamps |
| `strings.char_stride(text, start, end, step)` | the same, stepped |
| `strings.chars(text)`, `strings.bytes(text)` | loop sources of one-scalar `str`s, and of octets as `int`s |
| `lists.stride(values, start, end, step)` | the stepped copy of a list |

| Python habit | Selka |
|---|---|
| `for ch in text:` | `E_TEXT_ITERATION`; `selka fix` writes `strings.chars(text)` or `strings.bytes(text)` |
| `text[::2]` | `E_STEPPED_SLICE_REMOVED`: use the stride helper |

The search functions (`strings.find`, `rfind`, `text_index`, `text_rindex`, `count`, `starts_with`, `ends_with`) take and answer **byte** offsets; `strings.char_find`, `char_rfind`, `char_index`, `char_rindex`, `char_count_of`, `char_startswith` and `char_endswith` use scalars. A *bounded* search takes optional `start` and `end`: `strings.find(text, needle, start, end)` and `rfind` answer `int?`, `text_index` and `text_rindex` trap when the needle is absent, and `count`, `starts_with` and `ends_with` take the window too. The method spelling `text.find(needle, start, end)` is `E_METHOD_REMOVED`.

```selka
# doc: expect 42
import lists
import strings

func main() -> int:
    const text = "héllo"
    if len(text) != 6 or len("日本語") != 9:
        return 1
    if text[0] != 104 or text[1] != 195 or text[1:3] != "é":
        return 2
    if strings.char_count(text) != 5 or strings.char_count("日本語") != 3:
        return 3
    if strings.char_at(text, 1) != "é":
        return 4
    if strings.char_slice(text, 1, 3) != "él" or strings.char_slice(text, 2, None) != "llo":
        return 5
    if strings.char_slice(text, None, 2) != "hé" or strings.char_stride(text, None, None, 2) != "hlo":
        return 6
    mut scalars = ""
    for character in strings.chars(text):
        scalars += character
    if scalars != text:
        return 7
    mut octets = 0
    for octet in strings.bytes(text):
        octets += 1
    if octets != 6:
        return 8
    if lists.stride([1, 2, 3, 4, 5], None, None, 2) != [1, 3, 5]:
        return 9
    return 42
```

```selka
# doc: expect 42
import strings

func main() -> int:
    const text = "λbλb"
    if strings.find(text, "b") != Some(2) or strings.rfind(text, "b") != Some(5):
        return 1
    if strings.find(text, "z") is not None or strings.rfind(text, "z") is not None:
        return 2
    if strings.text_index(text, "b") != 2 or strings.text_rindex(text, "b") != 5:
        return 3
    if strings.count(text, "b") != 2:
        return 4
    if strings.char_find(text, "b") != 1 or strings.char_rfind(text, "b") != 3:
        return 5
    if strings.char_count_of(text, "b") != 2:
        return 6
    return 42
```

## Slices are views of their source

A slice `text[a:b]` is a byte-offset view: it names the octets in `[a, b)` without copying them, allocates nothing while only read, and traps when an endpoint cuts a multi-byte scalar. `strings.strip`, `lstrip`, `rstrip` and `char_slice` answer views too; a piece of `split`, `words` or `lines` is a new string. Give owning storage (a record field, a list element, a dictionary key) an explicit copy: it outlives the slice.

- A slice bound to a local (`const piece = text[a:b]`) is a view in every build mode, so a `@noalloc` helper can slice text; an owning operation (concatenation, a record field, a return) copies then.
- A write that would invalidate a live view of mutable text is `E_SLICE_ESCAPES`, naming the write and offering the `copy(value)` repair. The same code names a slice that reaches owning storage uncopied, and a returned slice that does not borrow the function's single borrowable parameter.
- A `bytes` slice is a view too; storing it needs `copy(value)`.

```selka
# doc: expect 3
func main() -> int:
    const text = "abcdef"
    const piece = text[1:4]
    const kept = [copy((text[0:2])), copy(piece)]
    return len(kept[0]) + len(kept[1]) - 2
```

## Scanning text

For a token that is one contiguous span, scan to its end and slice once. For one that needs unescaping, accumulate pieces in a `strings.Builder`: `append` takes a borrowed piece (a one-scalar `text[i]` too) and `finish` copies the field once; no `str[]` of characters or final `join`.

```selka
# doc: expect 42
import strings

# Read the quoted CSV field that starts at `start`. A real parser would also
# track line and column and return an error when the quote is unterminated.
func read_quoted(text: str, start: int) -> str:
    mut field = strings.builder()
    mut position = start + 1
    while position < strings.char_count(text):
        const ch = strings.char_at(text, position)
        if ch == "\"":
            if position + 1 < strings.char_count(text) and strings.char_at(text, position + 1) == "\"":
                strings.append(mut field, "\"")
                position += 2
                continue
            return strings.finish(field)
        strings.append(mut field, ch)
        position += 1
    return strings.finish(field)


func main() -> int:
    if read_quoted("\"a\"\"b\",c", 0) != "a\"b":
        return 1
    return 42
```

A list slice (`rows[1:]`) is an independent copy: changing it does not change `rows`.

## Indexing long text that is not ASCII

`text[i]` is free, but the scalar reading (`char_at`, `char_slice`, `chars`) must find an octet offset. On ASCII text the two are the same number; on a string with any non-ASCII scalar the runtime walks the octets. So on long non-ASCII text a loop that visits scalar after scalar (`for ch in strings.chars(text)`, `strings.char_at(text, i)` for each `i`, `strings.char_find(text, sub, start)` with a moving `start`) can cost time that grows with the square of the length. For large input and octet-shaped work (scanning for ASCII delimiters), convert once with `encode()` and scan the `bytes`:

```selka
# doc: expect 42
import bytes
import strings

func main() -> int:
    mut left: str[] = []
    for _ in range(20000):
        append(mut left, "(pin 12 ")
    mut prefix = strings.join(left, "") + "é"
    mut right: str[] = []
    for _ in range(20000):
        append(mut right, "(pin 12 ")
    mut text = prefix + strings.join(right, "")
    mut data = strings.encode(text)
    mut opens = 0
    for octet in data:
        if octet == 40:
            opens += 1
    mut start = 0
    mut pins = 0
    while start < len(data):
        mut at = bytes.find(data, b"(pin", start)
        if at < 0:
            break
        pins += 1
        start = at + 4
    if opens != 40000 or pins != 40000 or strings.char_find(text, "é") != 160000:
        return 1
    return 42
```

## String functions

Text operations are `strings` functions; `parse_int` and `parse_float` are prelude functions.

| Group | Functions |
|---|---|
| Search | `find`, `rfind`, `text_index`, `text_rindex`, `count`, `starts_with`, `ends_with` |
| Split and join | `split`, `words`, `lines`, `join(parts, separator)` |
| Trim | `strip`, `lstrip`, `rstrip` (Unicode whitespace); `strip_chars`, `lstrip_chars`, `rstrip_chars` (a character set) |
| Case and class | `upper`, `lower` (ASCII letters only); `is_digit`, `is_alpha`, `is_space` (`False` for empty text) |
| Other | `zfill` (keeps a leading sign before its padding), `replace`, `encode` |

Every method spelling (`text.zfill(width)`, `text.split()`, `sep.join(parts)`, `text.encode()`) is `E_METHOD_REMOVED`; `selka fix` rewrites each and adds the import. `ljust` and `rjust` are absent: use [`strings.pad_left` and `strings.pad_right`](standard-library.md#strings).

- None changes its argument or an alias of it: `strip`, `lstrip` and `rstrip` answer a view, the others a new value.
- `strings.find` answers `None` when the needle is absent; `strings.char_find` answers `-1`.
- Search bounds are nonnegative byte offsets: a constant negative is `E_NEGATIVE_INDEX_REMOVED`, a computed one traps `R_TEXT_BOUNDS`. An omitted bound keeps its default, and a positive start beyond the length keeps an invalid window, an empty needle included.
- Empty search needles match boundaries; empty split and replace needles trap `R_EMPTY_SEPARATOR`.

The exact rules are in the [Python text surface](python-text-surface.md).

```selka
# doc: expect 43
import strings

func main() -> int:
    mut escaped = "caf\u00e9"
    if escaped != "café":
        return 1
    mut padded = "  ready  "
    if strings.strip(padded) != "ready":
        return 2
    if strings.lstrip(padded) != "ready  ":
        return 3
    if strings.rstrip(padded) != "  ready":
        return 4
    if strings.upper("Selka") != "SELKA":
        return 5
    if strings.lower("Selka") != "selka":
        return 6
    if strings.zfill("7", 3) != "007":
        return 7
    if strings.zfill("-7", 4) != "-007":
        return 8
    if strings.replace("banana", "na", "NA") != "baNANA":
        return 9
    if strings.char_find("banana", "na") != 2:
        return 10
    if strings.char_find("banana", "zz") != -1:
        return 11
    if strings.count("banana", "na") != 2:
        return 12
    if not strings.starts_with("banana", "ban"):
        return 13
    if not strings.ends_with("banana", "ana"):
        return 14
    if not strings.is_digit("42"):
        return 15
    if strings.is_digit(""):
        return 16
    if not strings.is_alpha("abc"):
        return 17
    if not strings.is_space(" \t"):
        return 18
    mut lines = strings.lines("a\nb\r\nc")
    if len(lines) != 3:
        return 19
    if padded != "  ready  ":
        return 20
    return strings.char_count(escaped) * 10 + len(lines)
```

## Splitting on whitespace

`strings.words(text)` is Python's `text.split()`: it breaks on runs of the six ASCII whitespace scalars `strings.is_space` accepts (space, tab, line feed, carriage return, vertical tab, form feed), keeps the nonempty pieces and answers `str[]`; `strings.words("")` is empty. `bytes.words(data)` does the same on octets and answers `bytes[]`. `strings.split(text, separator)` keeps its exact meaning: adjacent separators give empty pieces, an empty needle traps `R_EMPTY_SEPARATOR`, and it requires its one argument. A wrong argument count is rejected with the callee's signature.

```selka
# doc: expect 42
import bytes
import strings

func main() -> int:
    mut words = strings.words("  one two\tthree  ")
    if len(words) != 3:
        return 1
    if words[1] != "two":
        return 2
    if len(strings.words("")) != 0:
        return 3
    if len(strings.split("a,,b", ",")) != 3:
        return 4
    if len(bytes.words(b" x\ty ")) != 2:
        return 5
    return len(words) * 14
```

## Unicode scalar values

`ord(text)` answers the scalar value of a one-scalar text and `chr(code)` the one-scalar text for a scalar value. `ord` of a one-scalar literal folds at check time, so `byte == ord("m")` needs no call. Both trap `R_TEXT_SCALAR` rather than answer a partial value: `ord` needs exactly one scalar, `chr` a code point in `0..0x10FFFF` outside the surrogates. `strings.ord` and `strings.chr` are the `Result` forms.

```selka
# doc: expect 42
import strings

func byte_code(marker: str) -> bool:
    return ord(marker) == 109


func main() -> int:
    if ord("A") != 65:
        return 1
    mut marker = "m"
    if ord(marker) != 109:
        return 2
    if not byte_code(marker):
        return 3
    if chr(65) != "A":
        return 4
    if ord(chr(233)) != 233:
        return 5
    if strings.char_count(chr(128512)) != 1:
        return 6
    return ord("A") - 23
```

### Writing a scalar in a literal

`\u` and exactly four hexadecimal digits (`"\u00e9"`), or `\U` and exactly eight above U+FFFF (`"\U0001f600"`). Braces (`"\u{fffd}"`) are `E_BYTE_ESCAPE`; `selka fix` writes one to four digits as `\u` and four, and for more digits you write `\U` by hand. A surrogate (`\ud800` to `\udfff`) is refused.

```selka
# doc: expect 6
func main() -> int:
    const smile = "\U0001f600"
    return len(smile) + len("\u00e9")
```

## Triple-quoted text

`"""..."""` and `'''...'''` write text that spans lines: exactly the bytes between the quotes, one-line escapes decoded, nothing else done.

- **Nothing is stripped or dedented.** The line ends next to the quotes and every space, tab and blank line are part of the text; for no indentation write lines from the first column.
- **A line end is kept as the file has it** (`\n` or `\r\n`).
- **A quote of either kind needs no escape**; the one-line escapes still work.
- **A backslash at the end of a line is `E_BYTE_ESCAPE`**: no line continuation.
- **The text ends at the first three unescaped quotes of its kind.** To end it in the quote character, escape it (`"""say \"hi\""""`); four in a row leave a stray quote.
- **`b"""x"""` is not a byte string**: it reads as `b""`, `"x"`, `""`.
- **Tokens after the closing quotes** continue that line (`x = """a\nb""" + y`, `"""a\nb""".upper()`).

```selka
# doc: expect 42
func main() -> int:
    const text = """first
  second "quoted" and 'single'

last
"""
    if text != "first\n  second \"quoted\" and 'single'\n\nlast\n":
        return 1
    if """say \"hi\"""" != "say \"hi\"":
        return 2
    return 42
```

## Format strings

An `f"..."` literal interpolates each `{expression}` hole with the conversion `str(value)` performs. A hole holds exactly one expression (a call, operator, index, field, even a nested format string) and takes any value `print` can render, through the same renderer, so a value has one spelling wherever it is written. Holes evaluate once, left to right. `{{` and `}}` write single braces, `f""` is empty text, and a `:` after the expression starts a [format specification](#format-specifications). A format string may be [triple-quoted](#triple-quoted-format-strings). The `f` prefix is Python-surface only.

Rejected: an empty hole, an unmatched or unterminated brace, more than one expression in a hole, a value with no rendering (a capability, an open file, a callback). A brace of CSS, JSON or JavaScript in the text is a hole until doubled; the refusal of one that reads as text (`f"p { color: red; }"`) writes it doubled.

| Written | Result |
|---|---|
| `f"{text!r}"` | `E_TOKEN` at the `!`: no `!r` or `!s`; call the function, `f"{repr(text)}"`. `selka fix` writes it (`{n!s:>8}` becomes `{str(n):>8}`) |
| `f"{d[\"k\"]}"` | `E_TOKEN` at the backslash: a hole holds an expression, so write the key in the other quote, `f"{d['k']}"`, or use a local |
| `f"{d["k"]}"` | `E_FORMAT_STRING`: the quote ended the literal; use the other quote in the hole or for the literal (`f'{d["k"]}'`), or a local |

```selka
# doc: expect 42
import strings

record Point:
    x: int
    y: int

func main() -> int:
    mut name = "ada"
    mut count = 3
    mut ratio = 1.5
    mut line = f"{name} has {count} items"
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
    mut values = [1, 2, 3]
    if f"{len(values)}" != "3":
        return 7
    if f"{values[0]}" != "1":
        return 8
    if f"outer {f'inner {count}'}" != "outer inner 3":
        return 9
    mut spot = Point(x=1, y=2)
    if f"{spot.x}" != "1":
        return 10
    if f"{strings.upper(name)}" != "ADA":
        return 11
    if f"{values} {spot}" != "[1, 2, 3] Point(x=1, y=2)":
        return 12
    return strings.char_count(line) * 3 - 3
```

### The text of a collection

`str(x)` and `repr(x)` take a list, set, dictionary, option, record, result or fixed array and answer the text `print(out, x)` writes, without the line end. `print`, `str`, `repr` and a format hole use one renderer.

- **Which types.** Any depth, if every part has a text. A capability, open file, owned resource, callback or `extern type` handle has none; a collection holding one is refused and the refusal names it.
- **The text** is what `print` writes: `[3, 1, 2]`, `{'b': 2, 'a': 1}`, `{5, 1, 3}`, `Some(3)`, `None`, `Point(x=1, y=2)`, `Ok(7)`; empty is `[]`, `{}`, `set()`. A text or bytes element is quoted as `repr` writes it (`['a', "it's"]`, `[b'ab']`). Nesting deeper than 24 levels shows `...`. A generic record's name is shown as the source writes it: `Pair[int, str](left=1, right='x')`.
- **`repr`** of a collection is the same text as `str`; a bare `str` differs (`str("a")` is `a`, `repr("a")` is `'a'`).
- **Order.** A set and a dictionary show insertion order (the first `add`, `include` or assignment of each element or key), in every build mode and run. Assigning an existing key keeps its place; removing and re-adding moves it to the end. Equal sets built in different orders show different text, so sort first when one text is needed.

```selka
# doc: expect positions [3, 1, 2]
# doc: expect ['a', "it's"] {'b': 2, 'a': 1} {5, 1} Some(3) None
func main(out: Stream) -> int:
    const order = [3, 1, 2]
    print(out, "positions " + str(order))
    mut table: dict[str, int] = {}
    table["b"] = 2
    table["a"] = 1
    const found: int? = Some(3)
    const missing: int? = None
    print(out, repr(["a", "it's"]), str(table), str({5, 1}), str(found), str(missing))
    return 0
```

`str` and `repr` of an enum, a tagged enum or a `bytes` by itself stay refused: `case_name(value)` is an enum's bare case name and `repr(data)` the `b'...'` spelling. A format hole takes any of them, and inside a collection each is shown as `print` shows it. An enum-indexed table (`[Kind]int`) is not a fixed array here: `str` and `repr` of one are refused, and its hole shows it.

```selka
# doc: expect Point(x=1, y=2) [Point(x=1, y=2)] Kind.alpha Ok(3) [1, 2]
record Point:
    x: int
    y: int

enum Kind:
    alpha
    beta

func parse(n: int) -> int fails str:
    if n < 0:
        fail "negative"
    return n

func main(out: Stream) -> int:
    const point = Point(x=1, y=2)
    print(out, str(point), str([point]), f"{Kind.alpha}", str(parse(3)), str(FixedArray[int, 2]([1, 2])))
    return 0
```

### A quote inside the text

A quote of the kind that opened a text ends it wherever it stands, inside a word too: `'the script's path'` is the text `'the script'`, then the code `s path`. Write such text in the other quotes (`"it's"`) or escape the quote (`\'`, `\"`). The quote that never closes is `E_BYTE_LITERAL`, and the code after it, when its quotes pair up, is `E_SYNTAX`; both say the text ended at the apostrophe.

```selka
# doc: expect the script's path / the script's path
func main(out: Stream) -> int:
    const where = "path"
    print(out, f"the script's {where}", "/", f'the script\'s {where}')
    return 0
```

### Triple-quoted format strings

`f"""..."""` and `f'''...'''` are format strings that span lines (markup, SQL, a report). The text is the [triple-quoted text](#triple-quoted-text) of the same source, and a hole is as in the one-line form. Three rules:

- **A hole closes on the line it opens**, its specification too: a line end inside one is `E_FORMAT_STRING` at its `{`. Bind a long expression to a local first. A brace of JSON, CSS or JavaScript is a stray hole: write `{{` and `}}`.
- **The literal ends at the first three unescaped quotes of its kind, wherever the holes stand.** A hole may hold a text in either single quote (`{row["name"]}`, `{row['name']}`), not three quotes of the literal's kind.
- **A name, call or run-time error in a hole is reported at its own line and column.** An unterminated literal is `E_BYTE_LITERAL` at its opening quotes.

```selka
# doc: expect 42
func card(id: str, title: str) -> str:
    return f"""<li class="card" id="project-{id}">
  <a href="/p/{id}/">{title}</a>
</li>"""


func main() -> int:
    const built = "<li class=\"card\" id=\"project-a\">\n  <a href=\"/p/a/\">b</a>\n</li>"
    if card("a", "b") != built:
        return 1
    const table: dict[str, int] = {"k": 4}
    const json = f'''{{"k": {table["k"]},
  "ids": [{len(built)}]}}'''
    if json != "{\"k\": 4,\n  \"ids\": [62]}":
        return 2
    return 42
```

## Format specifications

`f"{value:spec}"` formats a `str`, any integer type or a `float` under CPython's format-specification mini-language and answers the text CPython answers, byte for byte:

```text
[[fill]align][sign][z][#][0][width][grouping][.precision][type]
```

- **align** `<` left, `>` right, `^` centre, `=` padding after the sign; **fill** is any one character before it. Width and padding count scalars.
- **sign** `+`, `-` or a space; **z** turns a negative zero into `0`; **#** adds `0x`/`0o`/`0b` or keeps a decimal point; **0** pads with zeros after the sign.
- **grouping** `,` or `_` separates thousands (`_` groups hex, octal and binary by four); zero padding extends the groups: `f"{1:08,}"` is `0,000,001`.
- **type** `d b o x X n` for integers, `e E f F g G %` for floats (an integer under a float type is converted first), `s` for text. With no type a float prints the shortest round-tripping digits.

A float is rounded from its exact binary value, ties to even, as CPython does: `f"{2.675:.2f}"` is `2.67` and `f"{0.125:.2f}"` is `0.12`. `round(x, n)` and `strings.format_float` break an exact tie away from zero (the [declared `round` rule](python-syntax.md#prelude-builtins)): `round(0.125, 2)` is `0.13`.

The specification is checked with the program. `E_FORMAT_STRING`, with CPython's reason: a specification the value cannot take (a sign on text, a precision on an integer type, `d` on a float, `,` with `x` or `n`, a missing precision), a `bool` or other non-`str`, non-integer, non-`float` value, a width or precision above 4095, a nested `{...}` and the `c` type. `f"{value:}"` is the value's ordinary text.

```selka
# doc: expect 42
import strings

func main() -> int:
    mut price = 3.14159
    if f"{price:.2f}" != "3.14" or f"{2.675:.2f}" != "2.67" or f"{0.125:.2f}" != "0.12":
        return 1
    if f"{42:05d}" != "00042" or f"{42:>6}" != "    42" or f"{price:^10.3f}" != "  3.142   ":
        return 2
    if f"{1234567:,}" != "1,234,567" or f"{255:#x}" != "0xff" or f"{255:08b}" != "11111111":
        return 3
    if f"{1234.5678:.3e}" != "1.235e+03" or f"{0.25:.0%}" != "25%" or f"{-7:+}" != "-7":
        return 4
    mut name = "héllo"
    if f"{name:*^9}" != "**héllo**" or f"{name:.3}" != "hél":
        return 5
    return strings.char_count(f"{price:08.3f}") * 6 - 6
```

## Parsing numbers from text

`parse_int(text)` answers `int?` and `parse_float(text)` `float?`; text that is not a number answers `None`.

Both accept Python's base-10 grammar: optional surrounding ASCII whitespace, an optional `+` or `-`, then ASCII digits that may be separated by single `_` between two digits. `float` also accepts a `.` fraction, an `e`/`E` exponent with its own sign, and `inf`, `infinity`, `nan` in any case. These answer `None`: an alternate base (`0x10`), a non-ASCII digit, an interior space, a trailing character, a dangling separator, empty text, and for `int` a value outside the signed 64-bit range (it never wraps). `float` is correctly rounded: above binary64's range it is an infinity, below it a signed zero.

```selka
# doc: expect 8122
func port_of(text: str) -> int:
    match parse_int(text):
        case Some(value):
            return value
        case None:
            return -1

func main() -> int:
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
    match parse_float("2.5"):
        case Some(value):
            if value != 2.5:
                return 11
        case None:
            return 12
    match parse_float("nan"):
        case Some(value):
            if value == value:
                return 13
        case None:
            return 14
    match parse_float("two"):
        case Some(value):
            return int(value)
        case None:
            pass
    return port_of("8080") + port_of(" 42 ")
```

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/text.md).
