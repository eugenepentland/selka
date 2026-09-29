# FRICTION.md — csvstats in mylang

Overall the language matched its own PRIMER.md closely: my first full-program
`mylang check prog.my` came back with zero errors and one warning, and the
first real end-to-end run of the built binary produced correct output. The one
genuine time sink was numeric formatting; everything else was minor.

## 1. `printf("%.2f")`-exact rounding has no supported path (biggest time sink)

**What I tried first:** the task requires sums/means/min/max printed "rounded
as C's `printf("%.2f")` does." The obvious tool is `strings.format_float(value,
2)` from `docs/standard-library.md`. But PRIMER.md itself flags, in the
Strings section: *"Caution: it rounds the shortest decimal text half away
from zero (`2.675 → "2.68"`, `0.125 → "0.13"`, `-0.001 → "0.00"`), unlike
C/Python `%.2f`."* That's a correct warning — I verified in a scratch Python
session that `"%.2f" % 2.675 == "2.67"` and `"%.2f" % 0.125 == "0.12"`,
exactly the opposite of what `format_float` would give. So `format_float` was
unusable for this task from the start; no compiler error was ever produced
here, the documentation itself was the (accurate) warning.

**What I tried next:** the naive fallback, "multiply by 100, round to
nearest, divide," has the same problem one level down — `2.675 * 100.0`
evaluates to exactly `267.5` in binary64 (a manufactured tie that isn't
present in the true value of `2.675`), so any tie-breaking rule applied to
the *scaled* double still disagrees with C in the same cases.

**Root cause:** correctly reproducing `printf`'s rounding requires knowing
which side of a decimal boundary the double's *true* (infinite-precision)
value falls on. `docs/floating-point.md` and `docs/bytes.md` were searched
for a mantissa/exponent accessor (`frexp`/`ldexp`, bit-cast, anything) — there
is none: *"No guest spelling reads a float's representation: `float` is a
private builtin domain and the raw `f64_*` spellings are removed."*
(`floating-point.md`). `math.round` is also documented to round "halves away
from zero" (`floating-point.md`), not ties-to-even, so it can't be used
as-is either.

**How I resolved it:** implemented the classic Dekker/Veltkamp "double-double"
technique entirely in ordinary mylang arithmetic — `split_double` (Veltkamp
split) and `two_product` (Dekker product) in `prog.my` — which recovers the
*exact* mathematical product of `value * 100.0` as an error-free `(hi, lo)`
pair using only `+`, `-`, `*`. This is only valid because the docs explicitly
guarantee no FMA contraction and round-to-nearest IEEE arithmetic
(`floating-point.md`: *"no fused contraction or reassociation is allowed"*),
which I relied on directly. `lo`'s sign then resolves the rare case where the
scaled value lands exactly on a `.5` boundary that the true value isn't
actually on. I validated the approach against Python's (libc) `"%.2f"` first
on hand-picked tie cases and then on 200,000 random doubles before writing
any mylang, then transcribed it directly — it type-checked and passed all
tests on the first attempt in mylang itself, and matches a from-scratch
Python/`csv`-module oracle on a 200,000-row generated file exactly (`diff`
clean).

**Cost:** roughly one exploratory pass through the docs (confirming no bit
access exists) plus one offline algorithm-design/verification pass before
touching mylang; zero compiler-rejected attempts once the mylang code was
written. Call it "cheap once you know the trick, expensive if you don't" —
an agent without float-formatting background would likely have shipped the
naive `format_float`-based or scale-and-round version and quietly failed the
hidden tests on exactly the cases PRIMER.md calls out.

**Documentation verdict:** PRIMER.md's caution here is accurate and
helpful — it stopped me from using `format_float` blindly — but it only says
what's wrong, not that there is no alternative in the standard library and no
lower-level escape hatch. `standard-library.md`'s `format_float` entry
repeats "rounds halves away from zero" but doesn't cross-reference the
discrepancy at all.

## 2. Minor: unused tuple binding warning

`fields, next_pos = parse_row(...)` in one test discarded `next_pos`.
`mylang check` reported:

```
warning[W_UNUSED_BINDING]: binding is never read; use it or remove it, preserving initializer effects with `_ =` when needed
```

Fixed by renaming to `_` in one attempt. The message named the exact fix;
no doc lookup needed.

## 3. Minor: formatter disagreed with my hand-formatting

`mylang fmt-module prog.my --check` returned `formatting differs` (exit 1)
against my hand-written source, which used PEP8-style double blank lines
between top-level `def`s and two spaces before a trailing `#` comment.
mylang's formatter wants single blank lines and one space before `#`. Fixed
in one attempt by piping through `mylang fmt-module prog.my` and taking its
output verbatim. Not documented anywhere I looked (`python-syntax.md` doesn't
mention blank-line conventions), but the tool is self-describing enough that
no docs were needed.

## 4. Non-issue worth flagging: contradictory ambient context

This session's system context happened to include the *host* repository's
`CLAUDE.md` (the mylang **compiler's own** dev instructions), which flatly
states "No tuples." for the language it governs. PRIMER.md — the document
TASK.md actually names as authoritative for this trial's frozen compiler
snapshot — shows tuples in routine use (`return a, b`, `tuple[A, B]`,
`for a, b in zip(...)`), and they worked exactly as documented (used them for
`parse_row`'s `(fields, next_pos)` return and the swap-free multi-assignment
in `find_column`/`aggregate`). No actual friction resulted because I trusted
the task's named docs over the ambient project file, but a less careful run
could easily have avoided tuples entirely, or worse, "fixed" working code to
avoid a nonexistent restriction, based on a stale/irrelevant instruction file
that happened to be in context.

## Everything else: no friction

Capabilities (`Filesystem`, `Stream`), `Result`/`Option`/`match`, byte-level
CSV scanning (`bytes` indexing, `.decode()`, slicing), `dict[str, int]`
grouping, and `mylang test`/`mylang build` all worked exactly as PRIMER.md
and the referenced docs (`io.md`, `bytes.md`, `tuples.md`,
`records-and-unions.md`) described, on the first attempt. Performance was a
non-issue: the built native binary summarizes a 200,000-row generated CSV in
about 70ms, roughly 140x inside the 10-second budget, with no special
tuning (no arenas, no manual buffer reuse beyond what's described above).

## Top 3 changes, ranked

1. **Add a `strings.format_float` variant (or fix the existing one) that is
   correctly-rounded against the double's true value, ties-to-even — i.e.
   matches C `printf("%.2f")` / Python `%.2f` — and document it as the one to
   reach for whenever output must match another language's numeric
   formatting.** This is the single highest-value fix: it would have turned
   my biggest time sink into a one-line library call, and it's exactly the
   kind of "obviously should just work" gap that costs the most agent time
   because it fails silently (wrong digits, not a compile error) rather than
   loudly.
2. **Expose *some* correctly-rounded bit-level or exact-decimal escape hatch
   for `float`** (even a single `float_to_exact_decimal(value) -> str`
   debug/library function), so that the *next* formatting edge case doesn't
   also require hand-rolling Dekker/Veltkamp arithmetic from first
   principles. Right now the only way to get exact rounding behavior is to
   already know a 30-year-old numerical-analysis trick.
3. **Cross-link the `format_float` caution in `standard-library.md` to
   PRIMER.md's warning (or vice versa) and state explicitly "there is
   currently no way to get C/Python `%.2f` rounding in mylang."** The
   caution exists in exactly one of the two documents that describe
   `format_float`; a reader who starts from `standard-library.md` alone (as
   the "more detail" doc TASK.md points to) would not see it and would ship
   the wrong rounding with no error at any stage.
