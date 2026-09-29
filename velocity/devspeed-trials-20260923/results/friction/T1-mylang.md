# FRICTION.md

Overall this was a smooth build: two real compiler rejections total, both resolved
on the very next attempt, and the program worked correctly against hand-built and
generated inputs (including a 10 MB file and pathological single-10MB-word and
5M-tiny-word inputs) the first time I ran it after `check` went clean. Below are
the specific points that cost time or could have gone faster, roughly in the order
I hit them.

## 1. Empty list literal as a direct call argument doesn't infer its type

**What I tried:** `buf = byte_buffer([])` to get an empty growable byte buffer.

**What the compiler said:**
```
wordfreq.my:35:23: error[E_LIST_INFERENCE]: empty list requires an expected List type
      buf = byte_buffer([])
                        ^
```

**How I resolved it:** Predeclare a typed empty list and pass that instead:
`empty_bytes: list[int] = []` then `byte_buffer(empty_bytes)`. One attempt to fix.

**Documentation:** `docs/bytes.md`'s own `byte_buffer` example actually does exactly
this (`empty: list[int] = []` then `byte_buffer(empty)`) — I just didn't follow the
example literally the first time and wrote the more natural-looking Python idiom
inline. So the doc *had* the answer; the surprise is that an empty collection
literal only infers its element type from an assignment/annotation context, not
from an arbitrary call parameter's declared type, even though the callee's
parameter type is unambiguous (`list[int]`). A Python programmer's first instinct
(`byte_buffer([])`) will hit this every time. Cost: 1 wasted attempt, ~1 minute.

## 2. `mylang fmt --check` rejects any file with a `module` header

**What I tried:** `mylang fmt wordfreq.my --check` and `mylang fmt wordfreq_test.my --check`
to sanity-check formatting before finishing, since `fmt`/`fmt --check` is what
`docs/experiments/formatter.md` and the top-level `--help` both describe first.

**What the compiler said:**
```
wordfreq.my:1:1: error[E_SYNTAX]: unexpected token; expected def
  module wordfreq
  ^
```

**How I resolved it:** Found `fmt-module <file> --check` and `fmt-project <entry> --check`
in the `--help` output's own line for those two commands and used those instead
(`fmt-module` for the standalone test file, `fmt-project` for the module entry).
One extra command tried before landing on the right one.

**Documentation:** Misleading by omission rather than wrong. `docs/experiments/formatter.md`
introduces `fmt` and `fmt --check` as *the* formatting story and never mentions that
it only accepts headerless single-unit files, nor that a file starting with `module`
needs `fmt-module`/`fmt-project` instead. The top-level `mylang --help` lists `fmt`
in the same undifferentiated bucket as `check`/`run`/`build` and only gives
`fmt-module`/`fmt-project` their own explanatory lines elsewhere in the same
`--help` text, so the split is discoverable but not signposted from the command
that actually fails. Cost: 1 extra invocation, a minute of re-reading `--help`.

## 3. Working out the O(n) way to build words, not obviously the default idiom

Not a compiler error, just slower-than-necessary research. The task's 10 MB/10s
budget made me want to avoid an accidentally quadratic implementation, but the
"natural" Python-flavored approach — decode the file to `str` and build each word
by repeated `+` concatenation of one-character slices — is exactly the shape that
risks O(n²) on a pathological single giant word, because `str` is immutable and
`text.md` documents `+` as always allocating a fresh value. Working out that
`bytes` + `byte_buffer.append_byte` (documented in `docs/bytes.md` as amortized
O(log N) allocations via doubling) was the right primitive, and that word
boundaries can be decided at the byte level (matching the task's own "every other
byte separates words" phrasing) without ever decoding to UTF-8 `str` at all, took
reading three sections of `docs/bytes.md` and `docs/text.md` before writing any
code. This paid off — I tested a 10 MB single unbroken "word" afterward and it ran
in 43 ms — but a "building text incrementally / avoiding O(n²) concatenation"
callout next to the string-slicing-shares-storage section would have saved that
cross-referencing.

## What actually went smoothly (no friction)

Capabilities (`Filesystem`, `Stream`), `dict[str, int]` with `.get(key, default)`
and `.items()`, `list.sort(key=lambda ..., ...)` with a tuple key for the
count-desc/word-asc ordering (`lambda p: (0 - p.count, p.word)`), `Option`/`Result`
matching for argument/file validation, and `fs.read_file` all worked exactly as
`docs/python-syntax.md`, `docs/io.md`, and `docs/bytes.md` describe on the first
try. `mylang test <file>` found and ran the `public def test_*() -> bool`
functions in a separate `*_test.my` file with no extra configuration.

## Ranked changes that would have saved the most time

1. **Make `fmt` recognize a `module`-headed file and delegate to the same logic as
   `fmt-module`/`fmt-project` (or at minimum have its error name the right command),
   instead of a bare `E_SYNTAX` at the `module` line.** This is the one place the
   tool's error message actively pointed away from the fix rather than toward it.
2. **Let an empty collection literal infer its element type from the parameter type
   of the function it's being passed to**, the same way it already does from a
   variable's declared type — `byte_buffer([])` should just work, mirroring the
   Python idiom every user will reach for first.
3. **Add a short "building a large value incrementally" pointer from `docs/text.md`
   to `docs/bytes.md`'s `byte_buffer`**, so the amortized-append/no-quadratic-blowup
   guarantee is discoverable from wherever someone is reading about strings, not
   only from the bytes page.
