# FRICTION.md — csvstats (Python 3, stdlib only)

Overall this task had very little friction. Python's stdlib already has a
`csv` module built for exactly this problem, and the language has no static
type system to fight with, so most of the time went into reading TASK.md
closely rather than fighting tools. Below are the points that did cost real
time, in the order I hit them.

## 1. Confirming the `csv` module's quoting rules actually match the spec

TASK.md's quoting rules ("inside quotes, commas and line breaks are
literal", "`""` stands for one `"`", "quotes are only special at the start
of a field") read like a paraphrase of RFC 4180, and Python's `csv` module
implements something close to that dialect by default — but the Python
docs don't spell out the "only special at the start of a field" case (what
happens to a stray `"` in the middle of an unquoted field, or trailing
characters after a quoted field's closing quote) in enough detail to be
sure without checking. Nothing errored; I just didn't trust my memory of
the exact edge-case behaviour, so I ran a half-dozen inputs
(`ab"cd,2`, `"ab"cd,2`, embedded-newline fields, `""`-escaping, CRLF,
missing final terminator, a fully empty file, a single blank line) through
`csv.reader` interactively before committing to it. All matched the spec's
description or were undefined by the spec and got a reasonable default
(e.g. `"ab"cd` parses as `abcd`, folding the trailing unquoted text into
the field — TASK.md doesn't say what should happen there).

Cost: about 10 minutes and one throwaway script, no retries — this was
verification, not debugging. Docs: silent on the exact edge case; resolved
by experiment instead.

## 2. Making `./prog` executable without a real "build" step

The task requires `build.sh` to produce a native-looking executable
`prog` that the grader runs directly as `./prog ARGS...`, but this trial
has no compiler — only a `bin/python3` wrapper script the task says to
invoke by absolute path. Working out that this is safe requires tracing
through one layer of indirection: `bin/python3` has its own shebang
(`#!/usr/bin/env python3`) and, when exec'd via *another* script's shebang
line, receives that script's path as `argv[1]` and re-execs
`/usr/bin/python3` with the same argv tail — so a file whose shebang is the
given `bin/python3` path, and whose body is the actual Python program, runs
correctly under `./prog ARGS`. I verified this by hand (checking
`sys.argv` at each hop) rather than finding it documented anywhere, since
TASK.md doesn't describe the interpreter wrapper's mechanics at all — that
wasn't part of the named documentation, just a file I had to read to get
`build.sh` right.

Cost: about 10 minutes of tracing plus one verification run of `./prog`
with each error path (usage, missing file, missing column) to confirm exit
codes and streams came through the double hop unchanged. Not a
documentation gap in the strict sense (TASK.md doesn't promise to explain
the harness), but it's the only place I second-guessed myself.

## 3. Rounding: does Python's `%.2f`/`:.2f` match C's `printf("%.2f")`?

TASK.md is explicit that rounding must match C's `printf("%.2f")`, which
implies the grader's reference values were likely produced by an actual C
`printf` call and are sensitive to round-half-to-even vs round-half-away-
from-zero at exact ties. I couldn't find this guaranteed in Python's
documentation for `format()`/f-strings (it says the result is "correctly
rounded" but doesn't compare itself to C). I reasoned it through instead:
both use a correctly-rounded binary-to-decimal conversion of the same
IEEE-754 double, so they must agree except at a decimal value that is an
exact tie in binary — which is astronomically rare for computed sums/means
— and spot-checked a few classic "tricky" decimals (`2.005`, `1.005`,
`0.125`, `-0.0`) to make sure Python doesn't do naive decimal-tie rounding
that would disagree with the binary value. All matched the double's actual
value.

Cost: about 5 minutes, no retries, resolved by reasoning + a quick check
rather than any tool error. This is the one place I'd have liked TASK.md
(or a Python doc) to just state the guarantee instead of leaving it to be
inferred from "computed with 64-bit floating point."

## Ranked changes that would have saved the most time

1. **State the rounding equivalence explicitly in the spec** (e.g. "output
   formatting is guaranteed to match `printf("%.2f")` on the same IEEE-754
   double, including tie-breaking"), instead of letting the implementer
   infer it from "computed with 64-bit floating point." This is the one
   point where I was working from reasoning rather than a stated guarantee,
   and it's exactly the kind of thing that's cheap to state and expensive
   to get wrong silently.
2. **Define the undefined quoting corner case** — what a well-formed parser
   should do with trailing unquoted characters after a quoted field's
   closing quote (e.g. `"ab"cd`) — since the rest of the quoting spec is
   precise enough that this omission stands out.
3. Nothing about the language or standard library itself caused friction
   here; if anything, the `csv` module made this task faster than a
   from-scratch parser would have been. The only real time sink was
   verifying assumptions the task legitimately couldn't be expected to
   spell out (the build harness's shebang chaining), not the language.

If I'm honest, none of this rises to "blocked" — it's all diligence-driven
verification on a task where the stdlib already provides the hard part.
