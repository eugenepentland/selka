# FRICTION.md — csvstats in mylang

Overall this went smoothly once the right documents were found; the language's
Python-like surface meant most guesses from Python habits were either right or
rejected with a targeted message that named the fix. Below are the actual points
where I stopped and had to think, in the order they happened.

## 1. Module name must equal the file's dotted path

**Tried:** `module main` in a file named `csvstats.my` (mirroring the README's
`module main` / `main.my` example literally).
**Compiler said:** `error[E_MODULE_NAME]: declared module name does not match
its requested path` at the `module main` line.
**Fix:** rename the header to `module csvstats`. The entry function is still
called `def main(...)`, which is unrelated to the module name — that distinction
isn't obvious from the README's one example, which happens to use `main.my` for
its filename too, so the two names never visibly diverge there.
**Cost:** 1 attempt, ~1 minute. `python-syntax.md`/`modules.md` didn't call out
the rule directly at the point where I needed it (it's implied by "a project
module has to declare the name its importers request", but I only had one
importer-less file at that point, so the rule reads as not applying to me).

## 2. `strings.format_float` silently drops the sign of `-0.0`

**Tried:** delegate `%.2f`-equivalent formatting straight to
`strings.format_float(value, 2)`, since the standard library page says exactly
"rounds halves away from zero" and reads like the intended tool for this job.
**Found by testing, not by a compiler error:** `strings.format_float(v, 2)` for
a genuine negative zero (`float("-0")`, confirmed negative by `1.0 / v == -inf`)
returns `"0.00"`, not `"-0.00"`. C's `printf("%.2f", -0.0)` prints `"-0.00"`,
and the task spec asks for exactly that behavior, so a group whose minimum is
`-0` (a value the task's own numeric grammar explicitly allows) would have
printed the wrong sign.
**Fix:** compute the sign myself with the classic `value < 0.0 || (value ==
0.0 && 1.0/value < 0.0)` test, format `fabs(value)` (unsigned) through
`strings.format_float`, and prepend `-` myself when the sign check says so.
**Cost:** ~20 minutes — writing a probe program, printing intermediate values,
and confirming the discrepancy was in the library call and not in my own sign
logic. `standard-library.md` doesn't mention negative zero at all for
`format_float`; nothing in the docs warned me, so this was caught only because
I fuzz-tested a `-0`/`0` group by hand out of general caution, not because a doc
or a diagnostic pointed at it.

## 3. No regex, so the exact number grammar had to be hand-written

The task's grammar (`-?[0-9]+(\.[0-9]+)?`) is intentionally stricter than what
`float(text)`/`strings.to_float` accept (those allow leading `+`, `_` digit
separators, surrounding whitespace, `inf`/`nan`, exponents — all documented in
`text.md`). That's a correct, well-documented design choice (`float()` is
Python's grammar, not an arbitrary one), not a defect, but it meant I couldn't
reuse the intrinsic parser for validation and had to write a small hand-rolled
scanner (`is_valid_number`) before calling `float()` for the actual value. Not
really "friction" — the docs were accurate and told me exactly why the two
grammars differ — just extra code that a `strings` grammar-matching primitive
(even just an anchored-regex or a `str.match(pattern)`) would have saved.

## 4. Everything else worked on the first or second read

- `bytes`/`str` slicing, `byte_builder`... — actually unused in the final
  version once I moved to a byte-level scanner with `list[str]` field
  accumulation; `bytes.decode()` and slicing (`data[a:b]`) worked exactly as
  documented in `bytes.md` on the first try, including that slices clamp rather
  than trap.
- Tuple-returning helpers (`-> tuple[list[str], int]`) and
  `fields, pos = parse_record(...)` unpacking worked exactly as `tuples.md`
  describes, first try.
- `union`/`record` payload matching (`case StatsError.field_count(info):`)
  worked first try from `python-syntax.md`'s union example.
- `mylang test` discovering `public def test_*() -> bool` functions living in
  the same file as `main` worked exactly as `tooling/guest-tests.md` and
  `tooling/test-layout.md` describe — no separate test project needed.
- Performance: a 200,000-row, 3-column, ~3.7 MB file summarizes in well under
  0.1 s (`time ./prog big.csv name amount`), so no part of the "well under 10
  seconds" requirement needed any tuning; the naive byte-scanning parser with
  one `str` allocation per field was already far inside budget.
- Cross-checked output against a Python `csv`-module oracle on ~3,000
  fuzzed rows (quoted commas, escaped quotes, embedded newlines, CRLF, signed
  decimals) and a 200,000-row random file: byte-for-byte identical, including
  group order and every `%.2f` value.

## Ranked changes that would have saved the most time

1. **Warn, in `standard-library.md`, about `format_float`'s handling of
   negative zero** (or better: fix it to match `printf`/IEEE sign semantics).
   This was the only bug I found by luck rather than by reading — a program
   that instead trusted the doc's "rounds halves away from zero" description
   at face value would have shipped a silent wrong-sign bug on exactly the
   kind of edge-case input a CSV of real-world measurements is likely to
   contain (a row that nets to zero).
2. **State the module-name-equals-filename rule next to the first `module`
   example**, not just implicitly via the importer-visibility rule three
   sections later. A one-line note ("the name after `module` must be the
   file's own name without `.my`, independent of the file the command line
   names or the name of `main`") next to the very first `module main` /
   `main.my` example in `python-syntax.md`/`modules.md` would have caught this
   before it became a compiler error at all.
3. **A stricter numeric-literal check in `strings`** — e.g.
   `strings.matches_number(text, allow_sign=True, allow_fraction=True)` or an
   anchored regex primitive — for programs that need Python's/JSON's/a task
   spec's exact numeric grammar rather than the intrinsic parser's more
   permissive one. Small, but it's the one place I wrote non-obvious character-
   by-character code instead of calling a library function, and CSV-like
   numeric validation against a fixed grammar seems like a common enough task
   shape to deserve a primitive.
