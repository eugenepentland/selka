# FRICTION.md — logstats (Python 3, stdlib only)

Overall: nothing in the language or its runtime blocked me. Python 3's stdlib
(`re`, `sys`, `unittest`) covers this task directly, and there were no
compiler/runtime error messages to fight at all — the handful of rough edges
below came from the *task's own contract* (a "build then run a binary"
pipeline bolted onto an interpreted language) and from spec ambiguities I had
to resolve by reading TASK.md closely, not from anything Python's docs got
wrong. I'm logging them anyway since they cost real time.

## 1. `./build.sh` producing `./prog` for an interpreted language

**What I tried:** the deliverable contract is "build.sh builds prog; the
grader runs ./prog ARGS...", which presumes a compiled artifact. Python has
no compilation step, so there is no natural "build."

**What happened:** no error — this is a design gap, not a tool complaint.
I resolved it by writing `logstats.py` as an importable module (so
`unittest` can `import logstats` directly) and having `build.sh` concatenate
a `#!/…/bin/python3` shebang line (using the *exact* pinned interpreter path
from TASK.md) in front of a copy of `logstats.py`, then `chmod +x` it. That
makes `./prog ARGS` work exactly like a native binary would.

**Attempts:** 1 — the shebang-wrapper approach worked first try, but I had to
stop and think of it since nothing in TASK.md suggests it.

**Docs:** N/A — this is a trial-harness convention, not a Python doc issue.
TASK.md doesn't mention an interpreted-language exception, so I made a
judgment call rather than asking.

## 2. "Blank line" vs. "malformed line" boundary

**What I tried:** TASK.md says "a non-blank line that does not match is
malformed" and "blank lines are ignored entirely," but doesn't define
"blank" precisely — does a whitespace-only line (e.g. a line of just
spaces) count as blank (ignored) or non-blank (malformed)?

**What happened:** no tool error; this is a spec-reading ambiguity. I chose
the literal reading: "blank" = zero-length content after stripping the line
terminator; a line containing any character (including only spaces) is
non-blank, fails the required shape (IP is a *non-empty run of non-space*),
and is therefore malformed. I added a unit test
(`test_whitespace_only_line_is_malformed_not_blank`) to pin this decision
down and make it visible.

**Attempts:** 1 (no retries — just careful re-reading of TASK.md's exact
wording before committing to an interpretation).

**Docs:** TASK.md is the only doc in scope and was silent on this specific
case; it wasn't misleading, just underspecified.

## 3. Percentile rank arithmetic and float rounding

**What I tried:** the nearest-rank formula is `rank = ceil(p/100 * n)`.
Computing that as floating point (`math.ceil(p / 100 * n)`) is a latent
correctness trap: for some `(p, n)` pairs, `p / 100 * n` lands a hair below
an integer (e.g. representable-fraction artifacts) and `ceil` silently
returns one rank too high, which would only show up on specific input sizes
— exactly the kind of bug that passes small hand-tests and fails hidden
ones.

**What happened:** no runtime error — I caught this by inspection before
running anything, and switched to exact integer ceiling division,
`rank = (p * n + 99) // 100` (equivalently `-(-(p*n) // 100)` in Python),
which has no float involved and can't misround.

**Attempts:** 1 (caught during design, not by trial-and-error).

**Docs:** N/A — general numerical-methods knowledge, not something
TASK.md or Python's docs needed to cover.

## Nothing else slowed me down

Line parsing was a single anchored regex (`re.fullmatch` semantics via
`^...$`), argument/error handling was straightforward `sys.argv` + `sys.exit`
codes, and the 500k-line performance bar (task asks for "well under 10s")
was met with a plain single-pass loop over the file object — 1.16s wall
time on a synthetic 500k-line log, no profiling or optimization needed.
`bin/python3 -m unittest` ran all 21 tests in well under a second.

## Top 3 changes that would have saved the most time

1. **State explicitly whether interpreted-language submissions get an
   exception to the "build.sh produces a binary called prog" contract**, or
   give the shebang-wrapper pattern as the sanctioned approach. It's a small
   thing but it's the one place I had to invent a convention instead of
   following one.
2. **Define "blank line" precisely in the task spec** (e.g. "a line with no
   characters other than its terminator") rather than leaving readers to
   infer it from the surrounding non-empty-run wording. This is a
   spec/documentation fix, not a language one, but it's exactly the kind of
   ambiguity that produces divergent, equally-defensible implementations.
3. **Give the percentile examples with the exact expected value spelled
   out** (TASK.md states the formula but not a worked example). A single
   `p50`/`p95` worked example alongside the format line would let an
   implementer verify their rank arithmetic against the spec directly
   instead of deriving and unit-testing it themselves.
