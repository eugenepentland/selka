# Text and strings

`str` is the language's Unicode text type: an immutable owned value
with the same runtime shape as the [managed collections](managed-memory.md) and
the [`bytes`](bytes.md) byte string. This page covers the text surface itself —
scalar-value indexing, ordering, repetition, the Python string operations as `strings` functions, `f"..."`
interpolation with format specifications, and the two intrinsics that turn text
back into numbers. The [`strings` module](standard-library.md#strings) keeps
explicit helpers such as `pad_left` and `format_float` beside them.

## Managed Unicode strings

A `str` holds validated UTF-8 and has **octet** positions, not scalar positions:
`len(text)` counts octets, `text[0]` answers the first octet as an `int`, and
`text[a:b]` is a **view** of the octets in `[a, b)`. Unicode scalars have their own words
in the `strings` module
([below](#text-is-bytes-scalars-have-helpers)). Strings are immutable: there is no `text[i] = c` and no
`append`, and every operation that produces text — `+`, `split`, `join`, any
other `strings` function — answers a new string value. Checked ownership controls moves,
read-only borrows and views; `copy(value)` makes an independent owned string. A
slice borrows its source instead of copying it, and a store or a return needs
an explicit copy ([below](#slices-are-views-of-their-source)). A negative index
or slice endpoint, and an index past the end, traps with `R_TEXT_BOUNDS`. Slice
endpoints above the length clamp to the length, and a reversed interval
produces an empty string.
Use `strings.char_at(text, strings.char_count(text) - 1)` for the last scalar, and
`text[len(text) - 1]` for the last octet. Constant negative positions report
`E_NEGATIVE_INDEX_REMOVED` with a certain migration fix where available. Literals accept ordinary escapes, including
`\u00e9` for `é` ([writing a scalar in a literal](#writing-a-scalar-in-a-literal)), and `str(value)` converts a scalar using Python's spellings, and a list, set,
dictionary, option, record, result or fixed array as
[the text of a collection](#the-text-of-a-collection).

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

`<`, `<=`, `>` and `>=` order two `str` values by Unicode code point and two
`bytes` values by octet, lexicographically, with a proper prefix first — exactly
Python's order, so `"Zebra" < "apple"` (uppercase letters come first) and
`"é" > "z"`. It is not a locale collation. `str` and `bytes` never compare with
each other, and no other collection is ordered (`E_TEXT_OPERATOR`).

Use `strings.repeat(text, count)` for text and `byte_builder.repeat(data, count)`
for bytes. A nonpositive count gives an empty value. Use
`lists.filled(count, value)` to fill a list with one value, or explicit loops to
repeat the elements of an existing list. These are ordinary calls: arguments
are evaluated once in source order, and managed elements retain value semantics.
`selka fix` writes Python's `"-" * width` (or `width * "-"`) as `strings.repeat("-", width)` and adds the import.

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

A `str` is valid UTF-8, and a Unicode scalar (as Python calls a code point) is
one to four octets wide. Text is **bytes** underneath, so the short spellings
are byte operations:

- `len(text)` is its length in octets;
- `text[i]` is the octet at byte offset `i`, an `int`;
- `text[a:b]` is a view of the octets in `[a, b)` by byte offset, borrowed from
  its source rather than copied. An endpoint that falls inside a multi-byte
  scalar traps `R_TEXT_BOUNDARY`, so a slice of valid text is always valid text;
  a negative bound traps `R_TEXT_BOUNDS` and an end past the length clamps.
  A cut at a fixed width (`text[0:WIDTH - 1]`, `kind[0:1]`, `text[at:at + 1]`) passes every test with ASCII texts and traps
  at the first long character: `strings.cut_octets(text, limit)` ends a cut at a character, `selka lint` reports the shape
  (`L_TEXT_SLICE_OCTETS`), and the trap's message names the helpers.

The scalar reading has its own words in `strings`, and each one measures
scalars:

- `strings.char_count(text)` — the number of Unicode scalars;
- `strings.char_at(text, index)` — the one-scalar `str` at a scalar position;
- `strings.char_slice(text, start, end)` — an owned `str` of the scalars in
  `[start, end)`; an omitted endpoint is `None`, and the end clamps;
- `strings.char_stride(text, start, end, step)` — the same, with a step;
- `strings.chars(text)` — a loop source yielding the one-scalar `str` values in
  order;
- `strings.bytes(text)` — a loop source yielding the octets as `int`s; and
- `lists.stride(values, start, end, step)` — the stepped copy of a list.

Iterating a `str` directly is an error (`E_TEXT_ITERATION`): its fix writes
`strings.chars(text)` for scalars or `strings.bytes(text)` for octets. A stepped
slice is an error too (`E_STEPPED_SLICE_REMOVED`), because a slice is
contiguous: use the stride helper.

The search functions (`strings.find`, `rfind`, `text_index`, `text_rindex`, `count`,
`starts_with`, `ends_with`) take and answer **byte** offsets like every other text position, and
an endpoint that falls inside a multi-byte scalar traps `R_TEXT_BOUNDARY` at the
call. `strings.find` and `strings.rfind` have their bodies in the library, so the trap's own site is a line of
`@stdlib/strings.selka`; the report's first line still names the program's call, and the frame
`in strings::find at @stdlib/strings.selka:...` follows it as context
([trap reports](tooling/native-build.md#trap-reports)). When the window and the answer should count scalars, the helpers do it —
`strings.char_find`, `char_rfind`, `char_index`, `char_rindex`, `char_count_of`,
`char_startswith` and `char_endswith` measure roles, starts, ends and answers in
scalars, and their negative-position repair counts `strings.char_count(base)`
rather than `len(base)`.

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

Search offsets follow the same split. `strings.find` and `strings.rfind` answer
octet offsets as `int?`, which is what a byte-shaped scan wants, and the scalar
helpers answer scalar offsets, which is what a scalar-shaped one wants:

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

A *bounded* search takes the window as the optional `start` and `end` operands of
the same functions: `strings.find(text, needle, start, end)` and `strings.rfind`
answer `int?`, `strings.text_index` and `strings.text_rindex` trap when the needle
is absent, and `strings.count`, `starts_with` and `ends_with` take the window too.
The method spellings `text.find(needle, start, end)` and the rest are refused
(`E_METHOD_REMOVED`) and `selka fix` writes the function, with `is None` in place of a
comparison with `-1`.

## Slices are views of their source

A slice `text[a:b]` is a **byte-offset view** of its source: it names the octets
in `[a, b)` without copying them, and it traps when an endpoint cuts a
multi-byte scalar. A piece of `split(separator)`, `split()` or `splitlines()` is
a new string holding its own octets, because those operations build a list of
values. `strings.strip`, `strings.lstrip` and `strings.rstrip` answer a view too:
the octets between the whitespace they remove, so they allocate nothing. A slice
does not allocate while only read, so reading a small piece of a large text is
free.

```selka
# doc: expect 42
import strings

func main() -> int:
    mut pieces: str[] = []
    for i in range(10000):
        append(mut pieces, f"line {i}\n")
    mut text = strings.join(pieces, "")
    mut start = 0
    mut lines = 0
    while start < strings.char_count(text):
        mut end = strings.char_find(text, "\n", start)
        start = end + 1
        lines += 1
    mut half = copy(strings.char_slice(text, strings.char_count(text) // 2, None))
    if lines != 10000 or not strings.starts_with(half, "5055\nline"):
        return 1
    return strings.char_count(strings.lines(strings.strip(text))[9999]) - 7 + 40
```

A text slice is a view of its source. Read it, pass it to a function that
borrows it, or bind it to a local; give owning storage — a record field, a list
element, a dictionary key — an explicit copy, because that storage outlives the
expression that made the slice. A slice **bound to a local**
(`const piece = text[a:b]`) is a view in every build mode: it allocates
nothing, so a `@noalloc` helper can slice text, and `len`, printing and the
scalar helpers read the borrowed octets. Reading it through an owning operation
— concatenation, a record field, a return — copies then, not
before. A slice written **at its use** (`len(text[a:b])`) borrows in every
build mode when the only thing the program does with it is a read the compiler
can borrow for: a length is one, and so is any read inside a `@noalloc` function
(where the promise forbids the copy, so a helper call borrows there too). A
debug build still copies when the use needs an owned value — printing, a
dictionary insert, a comparison whose helper has no span form — and a release
build borrows every read-only use. A write that would
invalidate a live view of mutable text is refused with `E_SLICE_ESCAPES`, which
names the line of the write and offers reading the view before it, then the
`copy(value)` repair on the binding. `strings.char_slice` is a view too, of
the octets that hold the scalars it selects. `E_SLICE_ESCAPES` names the
`copy(value)` repair when a text slice reaches owning storage without one — and
the same code names a returned slice that does not borrow the function's single
borrowable parameter. A `bytes` slice follows the same rule: it is a view, and
storing it needs `copy(value)`.

```selka
# doc: expect 3
func main() -> int:
    const text = "abcdef"
    const piece = text[1:4]
    const kept = [copy((text[0:2])), copy(piece)]
    return len(kept[0]) + len(kept[1]) - 2
```

## Scanning text

A parser walks a string to decide where a token ends and then materializes it.
When the token is one contiguous span, scan to its end and slice once: for a
comma-terminated field, `text[start:end]` is the whole copy. When the token needs
unescaping or other assembly, accumulate its pieces in a `strings.Builder`; each
`append` takes a borrowed piece, including a one-scalar `text[i]`, and `finish`
copies the field once. There is no need for a `str[]` of one-character strings
or a final `join`.

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

A slice of a list, including `rows[1:]`, is an independent copy of its elements,
not a view: changing the slice does not change `rows`. A `str` slice is likewise
an independent string.

Scanning scalar by scalar is convenient for short fields and for text whose
encoding matters. For a large document whose delimiters are ASCII, the next
section's byte route avoids scalar indexing altogether: encode once, scan the
octets, and decode the finished pieces once.

## Indexing long text that is not ASCII

A string is stored as UTF-8 and indexed by octet, so `text[i]` is free. The
scalar reading — `strings.char_at`, `strings.char_slice`, `strings.chars` — is
what turns a scalar position into an octet offset. On ASCII text the two are the
same number. On a string that holds any non-ASCII scalar, the runtime finds the
offset by counting scalars through the octets, 32 at a time, from the start
(or from the offset of the previous lookup, when the string has one recorded).
The runtime stops updating these lookup caches before worker threads can borrow
text. Later reads may reuse existing metadata but do not update it, so uncached
lookups after worker-pool startup may require a longer read-only walk.

So on long non-ASCII text, a loop that visits scalar after scalar
(`for ch in strings.chars(text)`, `strings.char_at(text, i)` for each `i`, or
`strings.char_find(text, sub, start)` with a moving `start`) can cost time that
grows with the square of the text's length. When the
input is large and the work is octet-shaped (scanning for ASCII delimiters, as a
parser does), convert it once with `encode()` and scan the `bytes`, whose indexing
is always one octet per element:

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

Text operations are `strings` functions: `strings.zfill`, `strings.find`,
`strings.rfind`, `strings.text_index`, `strings.text_rindex`, `strings.count`,
`strings.starts_with`, `strings.ends_with`, `strings.split`, `strings.words` (the
whitespace split), `strings.join(parts, separator)`, `strings.encode`, the trimming
functions `strings.strip`, `lstrip` and `rstrip` (with a character set,
`strip_chars`, `lstrip_chars` and `rstrip_chars`), `strings.upper`, `strings.lower`,
the three classifications `strings.is_digit`, `is_alpha` and `is_space`,
`strings.lines` and `strings.replace`; `parse_int(text)` and `parse_float(text)` are
prelude functions. Most of these were methods once. Every method spelling is refused
(`E_METHOD_REMOVED`; the last of them, such as `text.zfill(width)`, `text.split()`,
`sep.join(parts)`, `text.encode()` and `text.parse_int()`, since W13-S5), and `selka
fix` rewrites each, adding the import.
None of them
changes its argument or an alias of it: `strip`, `lstrip` and `rstrip` answer a view of
the text they keep, and the others a new value. `strings.find` answers `None`
rather than raising when the needle is absent (`strings.char_find` answers `-1`),
the three classifications answer
`False` for empty text, case mapping covers ASCII letters and leaves every other
scalar alone, and `zfill` keeps a leading sign in front of its padding.
The search functions require nonnegative positional start/end bounds in byte offsets:
constant negatives report `E_NEGATIVE_INDEX_REMOVED` and computed negatives trap
`R_TEXT_BOUNDS`; an endpoint inside a multi-byte scalar traps `R_TEXT_BOUNDARY`
at the call, and the scalar-window spellings are the `strings.char_*` helpers.
An omitted bound keeps its default, and a positive start beyond the length
keeps an invalid search window, including for an empty needle. The trimming functions
default to Unicode whitespace, and their `_chars` forms take a character set. Empty
search needles match boundaries; empty split/replace needles trap `R_EMPTY_SEPARATOR`.
See the [Python text surface](python-text-surface.md) for these exact rules. `ljust`
and `rjust` are absent; use
[`strings.pad_left` and `strings.pad_right`](standard-library.md#strings). Apart from
`find` and `rfind`, which wrap a native offset search, these functions are native code
over the C runtime's one immutable text representation.

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

`strings.words(text)` is Python's whitespace split (`text.split()` in Python): it breaks the
text on runs of the same six ASCII whitespace scalars `strings.is_space` accepts —
space, tab, line feed, carriage return, vertical tab and form feed — keeps only
the nonempty pieces and answers `str[]`. Leading, trailing and doubled
whitespace therefore produce no empty string, and `strings.words("")` is empty.
`bytes.words(data)` agrees on the octets and answers `bytes[]`.
`strings.split(text, separator)` keeps its exact-separator meaning: adjacent separators
still produce empty pieces, an empty needle still traps `R_EMPTY_SEPARATOR`, and
the separator form still requires its one argument. A call with any other
argument count is rejected with the callee's rendered signature, and the `split`
rejection also carries the accepted spelling as an `alternative` note.

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

`ord(text)` answers the one Unicode scalar value of `text`, and `chr(code)`
answers the one-scalar text for a scalar value. `ord` of a one-scalar literal
folds at check time to an `int` constant, so `byte == ord("m")` compiles to an
immediate comparison with no call and no allocation; any other text is measured
at run time. Both builtins trap `R_TEXT_SCALAR` rather than answering a partial
value: `ord` requires exactly one scalar, and `chr` requires a code point in
`0..0x10FFFF` outside the surrogate range. The [`strings`
module](standard-library.md#strings) keeps its `Result` forms — `strings.ord` and
`strings.chr` — for callers that would rather handle the failure.

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

A text literal writes a scalar as `\u` and exactly four hexadecimal digits, `"\u00e9"` for `é`, or as `\U` and exactly eight for a
scalar above U+FFFF, `"\U0001f600"`. There are no braces: the spelling of Rust and JavaScript, `"\u{fffd}"`, is `E_BYTE_ESCAPE`, and its
message gives the spelling above. When the braces hold one to four hexadecimal digits, `selka fix` writes the same digits as `\u` and four
(`"\u{e9}"` becomes `"\u00e9"`); for more digits the escape is written by hand, `"\u{1f600}"` as `"\U0001f600"`. A surrogate
(`\ud800` to `\udfff`) is not a scalar and is refused.

```selka
# doc: expect 6
func main() -> int:
    const smile = "\U0001f600"
    return len(smile) + len("\u00e9")
```

```selka
# doc: expect-error E_BYTE_ESCAPE
func main() -> int:
    return len("\u{fffd}")
```

## Triple-quoted text

`"""..."""` and `'''...'''` write text that spans lines. The text is exactly the bytes between the opening three quotes
and the closing three, with the escapes of a one-line text decoded and nothing else done to it:

- **Nothing is stripped or dedented.** The line end right after the opening quotes and the one right before the closing quotes are
  part of the text, and so are every space and tab of an indented line and every blank line. Where the text should have no
  indentation, write its lines from the first column.
- **A line end is kept as the file has it**: `\n`, or `\r\n` in a file saved with them.
- **A quote of either kind needs no escape**, single or doubled. `\"` and `\'` still work, and so do the other escapes of a
  one-line text (`\n`, `\t`, `\\`, `\xNN`, `\uXXXX`).
- **A backslash at the end of a line is `E_BYTE_ESCAPE`**: there is no line continuation.
- **The text ends at the first three quotes of its kind in a row that no backslash escapes.** To end a text in the quote
  character, escape it (`"""say \"hi\""""`). Four quotes in a row close the text at the first three and leave a stray quote.
- **A `b` before three quotes is not a triple-quoted byte string**: `b"""x"""` is `b""`, `"x"` and `""`.
- **The tokens after the closing quotes** are on the line the text ends on and continue it as they would after any other
  token: `x = """a\nb""" + y`, `if """a\nb""" == y:`, `"""a\nb""".upper()` and a comment after the quotes are read as they
  look. Until 14 November 2026 the layout pass took such a token for the first of a line of its own, and the line after it
  was refused with `E_INDENTATION` unless the text stood inside brackets.

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

```selka
# doc: expect 42
func main() -> int:
    const name = "ada"
    const text = """first
second""" + " " + name
    if """a
b""" == "a\nb":
        return len(text) + 26
    return 0
```

## Format strings

An `f"..."` literal interpolates each `{expression}` hole with the same conversion
`str(value)` performs. Printing or writing one writes its literal pieces and each
hole's rendering straight to the stream, so a scalar, text or byte hole allocates
nothing and no pieces are joined; storing one in a `str` fills one exactly-sized
allocation instead: its literal lengths, its text holes' lengths and each scalar
rendering's bound. A single piece returns its rendered text directly, so
`f"{text}"` needs no allocation when `text` is already a `str`. Each hole
evaluates and renders once from left to right; the implementation does not
repeatedly copy a growing prefix. A hole holds exactly one ordinary expression — a call,
an operator, an index, a field, even a nested format string — and is checked in
its own source position. A hole takes any value `print` can render — a list, a
dictionary, a record, an enum case, a result, an option or a byte string as well
as a scalar — and renders it through the very renderer `print` calls, so one
value has one spelling wherever it is written. `{{` and `}}` write single braces
(a brace of CSS, JSON or JavaScript in the text is a hole until it is doubled, and a refusal of a hole that reads as
text, as `f"p { color: red; }"` does, quotes this hole's opening and writes it doubled: ``write `{{ color:` ``; so does a name the
program lacks in a hole with white space around it or a space after its colon, `f"body { margin: 0 }"`, and a hole of the
JSON shape `f'{"a": 1}'`; in a generic function too),
ordinary escapes apply to the literal pieces, and `f""` is empty text. A format string may be
[triple-quoted](#triple-quoted-format-strings) to span lines. An empty
hole, an unmatched or unterminated brace, more than one expression in a hole, and
a value with no rendering — a capability, an open file or a callback — are all
rejected. A `:` after the expression starts a
[format specification](#format-specifications). A hole has no `!r` or `!s` conversion
after the expression: `f"{text!r}"` is `E_TOKEN` at the `!`, and the message says to call
the function in the hole, `f"{repr(text)}"` or `f"{str(text)}"`, and `selka fix` writes it (a specification after the
conversion stays: `{n!s:>8}` becomes `{str(n):>8}`). The `f` prefix is Python-surface
only.

```selka
# doc: expect-error E_TOKEN
func main(out: Stream) -> int:
    const text = "a"
    print(out, f"{text!r}")
    return 0
```

A hole holds an expression, not escaped text, so a quote inside it is never written `\"`: `f"{d[\"k\"]}"` is `E_TOKEN` at the
backslash, and the message says to write the key in the other kind of quote, `f"{d['k']}"`, or to put the value in a local first
(`const k = d["k"]`, then `f"{k}"`). A quote of the literal's own kind, written plainly, ends the literal there: `f"{d["k"]}"` is
`E_FORMAT_STRING` ("unterminated interpolation"), and its message says the quote ended the literal inside the hole and gives the same
three ways out, the other kind of quote in the hole (`f"{d['k']}"`), the other kind for the literal (`f'{d["k"]}'`), or a local first.

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

`str(x)` and `repr(x)` take a list, a set, a dictionary, an option, a record, a result or a fixed array, and answer the
text `print(out, x)` writes for it, without the line end. `print`, `str`, `repr` and a format string's hole write that text
through one renderer, so the four cannot differ, and a program that reports a list or a record has no helper to write
(D-F38-1; a record, a result and a fixed array alone are F-38b, the user's decision of 14 November 2026).

- **Which types.** A list, a set, a dictionary, an option, a record, a result or a fixed array, of any depth, whose parts all have a text: integers, `bool`,
  `float`, `str`, `bytes`, records, enums, tagged enums, options, results, fixed arrays and further collections do.
  A capability, an open file, an owned resource, a callback or an `extern type` handle has none, so a collection that
  holds one is refused and the refusal names it (`str of Stream[] is refused: it holds a Stream, which has no text`).
- **The text.** `[3, 1, 2]`, `[1.5, 2.0]`, `[True, False]`, `{'b': 2, 'a': 1}`, `{5, 1, 3}`, `Some(3)`, `None`,
  `[Some(3), None]`, `[Point(x=1, y=2)]`, `[Kind.alpha]`, and alone `Point(x=1, y=2)`, `Ok(7)`, `Err('empty')` and `[1, 2, 3]`
  for a fixed array. An empty list is `[]`, an empty dictionary `{}` and an empty set
  `set()`. A text or bytes element is quoted and escaped the way `repr` writes it (`['a', "it's", 'x\ny']`, `[b'ab']`),
  because `print` writes it that way inside a collection. Nesting deeper than 24 levels shows `...`.
- **A generic record's name.** It is shown as the source writes it, with its type arguments spelled as in source and
  without their modules: `Pair[int, str](left=1, right='x')`, `Holder[int[]](value=[1, 2])` and `Choice[int].nothing`, where
  the checked name `Pair<i64,str>` printed until 14 November 2026.
- **`repr`.** `repr(x)` of a collection is the same text as `str(x)`: its brackets around the `repr` of each element, which
  is how every element is already written. Only a bare `str` differs between the two (`str("a")` is `a`, `repr("a")`
  is `'a'`); inside a collection both quote.
- **Order.** A set and a dictionary are shown in insertion order, the order of the first `add`, `include` or assignment
  of each element or key: no hash seed and no address decides it, and every build mode and every run shows the same text.
  Assigning an existing key keeps its place; removing an element and adding it again moves it to the end. Equal sets built
  in different orders are equal but show different text (`{5, 1, 3}` and `{1, 3, 5}`), so sort the elements first
  when a program needs one text for one set.
- **Cost.** One pass over the value: the elements are read in place and not copied, the text is built in one growing
  buffer, and the result is copied out of it once. The cost grows in step with the length: the text of 100,000 numbers takes milliseconds.

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

```selka
# doc: expect Pair[int, str](left=1, right='x') Holder[int[]](value=[1, 2])
record Pair[A, B]:
    left: A
    right: B

record Holder[T]:
    value: T

func main(out: Stream) -> int:
    print(out, Pair[int, str](left=1, right="x"), Holder[int[]](value=[1, 2]))
    return 0
```

`str` and `repr` of an enum, a tagged enum or a `bytes` by itself stay refused: the sentence names the type and what
shows it. `case_name(value)` is an enum's bare case name, and `repr(data)` is the `b'...'` spelling of a `bytes`. A
format string's hole takes any of them (`f"{value}"` is the text `print` writes), and inside a collection every one of them
is shown as `print` shows it. An enum-indexed table (`[Kind]int`) is not a fixed array here: `str` and `repr` of one are
refused, and its hole shows it.

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

Text takes either quote, `'he said "hi"'` or `"it's"`, and a quote of the kind that opened it ends it wherever it
stands, inside a word too: `'the script's path'` is the text `'the script'`, then the code `s path`, then a quote
that opens a text of its own. Write such text in the other quotes, or escape the quote: `\'` in single quotes, `\"`
in double quotes. When a text ended at a quote inside a word, the refusal says so with a note at that quote: the
quote that never closes is `E_BYTE_LITERAL` ("this quote opens a text that never closes: the single-quoted text before
it ended at the apostrophe in `script's`"), and the code after it, when its quotes happen to pair up, is `E_SYNTAX`
with the same explanation. A literal that does not close on its line for any other reason is named for what it is:
an unterminated text, format string or byte literal.

```selka
# doc: expect the script's path / the script's path
func main(out: Stream) -> int:
    const where = "path"
    print(out, f"the script's {where}", "/", f'the script\'s {where}')
    return 0
```

### Triple-quoted format strings

`f"""..."""` and `f'''...'''` are format strings that span lines (F-19): markup, SQL or a report with values in it, written as it
reads. The text is the [triple-quoted text](#triple-quoted-text) of the same source, piece by piece: nothing stripped or
dedented, every line end, space, tab and blank line kept, a quote of either kind needing no escape, a backslash at a
line's end refused. A hole is what it is in the one-line form: `{expression}`, `{expression:spec}`, `{{` and `}}`. Three
rules are new, and each only says what the one-line form already does:

- **A hole closes on the line it opens**, its specification too. A line end inside one is `E_FORMAT_STRING` at its `{`, with
  a message that says so (a one-line format string has no line end to span, so nothing it accepts changes). Bind a long
  expression to a local before the literal. A brace of JSON, CSS or JavaScript in the text is a stray hole: write `{{` and `}}`.
- **The literal ends at the first three unescaped quotes of its kind, wherever the holes stand**, as the plain form does and as a
  one-line format string ends at its quote without looking at its holes. A hole may hold a text in either single quote
  (`{row["name"]}`, `{row['name']}`) and a one-line format string, all on its line; it cannot hold three quotes of the
  literal's own kind, so spell the outer literal with the other kind.
- **A name, a call or a run-time error in a hole is reported at its own line and column** in the file, by `check`, in a trap's
  location and in a debug build's line table. An unterminated literal is `E_BYTE_LITERAL` at its opening quotes and names
  the line it opened on.

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

`f"{value:spec}"` formats a `str`, any integer type or a `float` under CPython's
format-specification mini-language and answers the text CPython answers, byte
for byte:

```text
[[fill]align][sign][z][#][0][width][grouping][.precision][type]
```

- **align** `<` left, `>` right, `^` centre, `=` padding after the sign; **fill**
  is any one character before it. Width and padding count Unicode scalars.
- **sign** `+`, `-` or a space; **z** turns a negative zero into `0`; **#** adds
  `0x`/`0o`/`0b` or keeps a decimal point; **0** pads with zeros after the sign.
- **grouping** `,` or `_` separates thousands (`_` groups hex, octal and binary
  digits by four), and zero padding extends the groups: `f"{1:08,}"` is `0,000,001`.
- **type** `d b o x X n` for integers, `e E f F g G %` for floats (an integer
  under a float type is converted first, as `float(value)` would), `s` for text.
  With no type a float prints the shortest round-tripping digits.

A float is rounded from its **exact binary value**, ties to even, as CPython does:
`f"{2.675:.2f}"` is `2.67` because the binary value of 2.675 lies just below the
half, `f"{0.125:.2f}"` is `0.12` because 0.125 is an exact tie, and
`f"{-0.001:.2f}"` keeps its sign as `-0.00`. `round(x, n)` rounds the same exact
value, but breaks an exact tie away from zero, the language's
[declared `round` rule](python-syntax.md#prelude-builtins): `round(0.125, 2)` is
`0.13`. `strings.format_float` also rounds ties away from zero, so it agrees with
`round(x, n)` and differs from `:.nf` only on an exact tie.

The specification is literal text checked with the program. One the value cannot
take — a sign on text, a precision on an integer type, `d` on a float, `,` with
`x` or `n`, a missing precision — is `E_FORMAT_STRING` with CPython's reason, as
is a `bool` or any value other than a `str`, an integer or a `float`, a width or
precision above 4095, a nested `{...}` (a computed width) and the `c` type. An
empty specification, `f"{value:}"`, is the value's ordinary text.

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

`parse_int(text)` answers `int?` and `parse_float(text)` answers `float?`. The
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
the Zig unit test and the native driver, so `selka run` and `selka build`
cannot disagree about which text is a number or about the value it names.

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

See [Python text surface](python-text-surface.md) for ranged searches, trim character sets and scalar repr.
