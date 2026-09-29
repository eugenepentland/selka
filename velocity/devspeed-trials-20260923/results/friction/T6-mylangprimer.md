# FRICTION.md — logstats in mylang

Overall this went smoothly: `mylang check`, `mylang test`, and `mylang build` each
succeeded on the *first* attempt on the final source (no compiler-error loop at all).
The friction that did exist was almost entirely about **finding the right doc**, not
about the compiler rejecting anything I wrote. Details below, then the ranked
suggestions.

## What I tried, and where I had to dig

1. **Picking str vs. bytes for line scanning.** PRIMER.md's "Strings and bytes"
   section says building strings with per-character indexing is fine but calls
   out, in one line, that byte-level scanning of big inputs should use
   `fs.read_file` (bytes) instead: "`data[i]` is an `int`, `data[a:b]` a `bytes`
   slice." It does **not** name any of the actual scanning primitives
   (`find_any`, `.view()`, `parse_int_range`) — those only exist in
   `docs/bytes.md`. Since this task is 500k lines of exactly the
   kind of fixed-shape line parsing bytes.md is designed for, I read all of
   bytes.md before writing a line of the parser, rather than starting from the
   primer's str-indexing style and rewriting later. That was the single biggest
   time cost (maybe 10-15 minutes of reading), but it paid off: the resulting
   parser is allocation-free per character (only two `.decode()` calls per valid
   line, for `ip` and `path`) and 500k lines run in under 1 second. Had I started
   from the primer alone I'd have written a slower str-based scanner and likely
   had to redo it after hitting the 10-second budget, or not noticed at all
   since the budget is generous. No error message was involved here — this was
   purely "the primer doesn't mention the fast path exists," discovered by
   reading further, not by the tool telling me.

2. **`docs/match-expressions.md` looks stale/inconsistent with everything else.**
   I wanted to confirm whether a `case Ok(value):` binding is visible after the
   `match` block ends (I needed this for decoding `ip`/`path` bytes to `str`).
   The one doc whose title directly answers this — match-expressions.md — uses a
   completely different vocabulary than every other doc I'd read: it declares
   `result Read:` with `i64` payloads and matches with `Read.ok(number)` /
   `Read.err(code)`, whereas PRIMER.md, io.md and bytes.md all use the builtin
   `Result`/`Option` types matched directly as `case Ok(value):` / `case Err(_):`
   / `case Some(v):` / `case None:` with no type-qualified case names. Nothing in
   match-expressions.md ever mentions `Ok`/`Err`/`Some`/`None` at all. I couldn't
   tell whether this was an older/legacy variant-matching mechanism being
   documented on purpose, or a stale page nobody updated after `Result`/`Option`
   became builtins with the shorter spelling. It also never states whether an
   arm's binding survives past the `match` statement. I lost a few minutes on
   this and did not get an answer from it. I resolved it defensively instead of
   confirming it: I pre-declared an outer variable (`ip_str = ""`) before the
   `match` and only ever assigned into it from inside the arms, which works
   regardless of whether the binding is block-scoped or function-scoped. This
   cost no compile errors (I never tried the risky form), just design/reading
   time — roughly 2 attempts worth of hedging.

3. **Confirming dict-of-list aliasing before writing the accumulator.** The task
   needs `path -> list[int]` (durations per path) with `.append()` calls spread
   across many lines of a 500k-line file. PRIMER.md doesn't say whether
   `some_dict[key].append(x)` mutates the stored list or a copy. I found the
   answer by combining two separate sentences in `docs/managed-memory.md`: the
   list section ("Assignment and argument passing copy a reference rather than
   the contents") and the dict section ("A dictionary is shared by assignment
   exactly as a list is"), neither of which is about the dict-of-list case
   directly. It works as hoped (confirmed once the program ran correctly), but I
   would have liked one explicit worked example of "dict whose values are
   lists, mutated after retrieval" rather than inferring it by composing two
   general rules. Cost: maybe 5 minutes of doc reading, zero failed compiles.

## What did *not* cause friction (worth naming, since so much went right)

- Option/Result narrowing via `is None` (from PRIMER.md's own example) worked
  exactly as documented for `int(s)`, `line.parse_int_range(...)`, and my own
  `Option[ParsedLine]` return value — no surprises.
- `find_any`, `.view()`, and `parse_int_range` all worked exactly as described in
  bytes.md on the first try, including the "-1 means not found" and "clamps
  instead of trapping" semantics I relied on for malformed-line detection.
- Keyed sort with a tuple key (`sort(key=lambda e: (0 - e.count, e.path))`) for
  the two required "count desc, then name asc" orderings worked first try,
  including tie-breaking, exactly as python-syntax.md's "Keyed sorting" section
  describes.
- `mylang check`, `mylang test logstats.my`, and `mylang build logstats.my -o
  prog` each worked first try with zero syntax/type errors anywhere in a
  ~300-line program — genuinely surprised by this for a first program in an
  unfamiliar language.

## Ranked: the three changes that would have saved the most time

1. **Merge the "byte-level scanning" primitives into the primer, or link
   directly to bytes.md from that one line.** PRIMER.md's single sentence about
   `fs.read_file`/`data[i]`/`data[a:b]` is easy to read as "bytes are just like
   str but with ints instead of chars," when the actual value is a set of
   named, noalloc-friendly scanning operations (`find_any`, `.view()`,
   `parse_int_range`/`parse_int`) purpose-built for exactly this kind of task.
   A programmer who trusts the primer to be "the differences that matter" (its
   own words) has no way to know these exist without reading a second,
   much longer document cover to cover.

2. **Fix or clearly label `docs/match-expressions.md`.** It is the most
   directly-titled doc for "how does match/case work," but its vocabulary
   (`result`, `i64`, `Type.case(binding)`) doesn't appear anywhere else I read,
   and it never mentions the `Ok`/`Err`/`Some`/`None` spellings that PRIMER.md,
   io.md and bytes.md all use exclusively. Either it documents a different,
   legacy mechanism and should say so at the top with a pointer to the current
   one, or it's stale and should be rewritten to match current builtin
   Result/Option usage.

3. **State the scoping rule for a `match`/`case` payload binding explicitly,
   in one place.** I could find "the `for` loop variable ... stay[s] scoped to
   their block"-style rules for other constructs, but nothing that plainly
   states whether `case Ok(value):`'s `value` is visible after the `match`
   statement ends. Every example I found only uses the binding inside its own
   arm, which is consistent with either scoping rule, so it's easy to end up
   guessing (or, as I did, writing around the question rather than answering
   it).
