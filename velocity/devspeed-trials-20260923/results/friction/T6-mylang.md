# FRICTION.md

Candid log of everything that cost time while writing `logstats` in mylang. I read
`kit/README.md` and most of `kit/docs/*.md` (python-syntax, statements, io, text,
standard-library, results-and-options, functions, records-and-unions,
managed-memory) before writing code, so most of what follows is friction that
survived that reading, not "I skipped the docs."

## 1. `mylang test` requires a module header; `check`/`build` do not (~10 minutes, 2 attempts)

My first probe file had no `module` line (the language guide's very first example
starts with a headerless script, and `check` and `build` both accepted it fine).
`mylang test probe.my --filter test_` failed immediately with:

```
probe.my:1:1: error[E_MODULE_HEADER]: file must begin with a module declaration
```

None of `python-syntax.md`, `functions.md` (which documents `@test`), or the
top-level README's "Run guest tests" section says that `mylang test` specifically
needs `module NAME` while `check`/`build --run` do not. I found the fix by trial
and error (add `module probe`) rather than from a doc pointer. Cost: one failed
run plus a couple minutes reading `--help` output again to see if a flag would
avoid it. Not a big deal once found, but it's a command-specific inconsistency
that isn't documented at the point where `@test` is introduced.

## 2. Working out whether a dict value that's a record can be mutated in place (~15 minutes, no failed compiles, just reading)

I needed a per-path aggregate (count, byte total, list of durations) keyed by
path. `managed-memory.md`'s intro line says list mutation methods "currently use
a named local or parameter as their receiver," which reads as if `d[key].append(x)`
or `d[key].count += 1` might be rejected. But `records-and-unions.md` shows
`second.seen.append(7)` where `second.seen` is a *field of a local*, not the bare
local itself — so the "receiver" rule is looser than that one sentence suggests,
and I couldn't find a single sentence anywhere that states the rule for
`dict[str, SomeRecord]` values directly. I did not want to find out at 500k-line
scale that a construct silently type-checked but behaved differently than
expected (records are value types, so mutating a dict's stored copy without
writing it back would silently lose updates).

I resolved this by writing a throwaway probe (`probe2.my`, since deleted) that
exercised exactly the pattern I planned to use — read a record out of a dict,
mutate two scalar fields and append to a list field on the local, write the
record back into the dict — and ran it before touching the real program. It
worked exactly as hoped (list mutation is visible even without the write-back,
because the list field is a shared reference; the write-back is only needed for
the two scalar fields). This cost time but no wrong answers, because I verified
before relying on it rather than after. I'd count this as "documentation was
silent," not "misleading" — `managed-memory.md` and `records-and-unions.md` just
don't have a combined example of "record-with-a-list-field, stored as a dict
value, mutated and written back," and I had to synthesize the answer from two
partial examples.

## 3. Confirming the exact CLI argument-passing rule for a *built* executable (~10 minutes, 1 wrong assumption caught before it shipped)

`io.md`'s "Arguments" section documents `mylang run ... -- args...` (compiler
options before `--`, guest args after) and separately says an installed
executable "receives every OS argument after `argv[0]`, unchanged... because it
reads its own runtime options from `MYLANG_OPTIONS`". I initially planned to
write `build.sh` assuming the grader would need to pass `--` before `FILE K`
(carrying over the `mylang run` convention), which would have been wrong for a
plain native binary invoked directly as `./prog FILE K`. I caught this by
building a tiny probe and running it as `./probe_bin -- a b c` vs `./probe_bin a
b`: the first gave `argc=4` (the literal `--` counted as an argument!), the
second gave the expected `argc=2`. The doc line ("every OS argument after
argv[0], unchanged... including `--`") does say this if read closely enough, but
it's easy to misapply the `mylang run` mental model to a built binary; I'd have
shipped a `build.sh`/usage mismatch without the probe.

## 4. Everything else went smoothly

No struggles with: the manual line scanner (no regex module exists, so I hand-
rolled a scanner using `find`, slicing and `Option[tuple[str,int]]` returns —
tuples, string slicing-as-view, and `Option` destructuring via `match` all
worked exactly as documented on the first try); `Filesystem`/`Stream` capability
threading through `main`; `Result`/`Option` propagation; keyed `.sort(key=lambda
row: (-row.count, row.path))` with a tuple key (worked first try, exactly as
`python-syntax.md`'s keyed-sorting section describes); or performance (500,000
synthetic lines summarized in 1.7s natively, no tuning needed — well inside the
10-second budget). `standard-library.md`'s per-module reference tables were
useful for confirming `sorted`/`.sort()` needed no import (they're prelude, not
`sort`-module), which saved a wasted `import sort`.

## Ranked changes that would have saved the most time

1. **Document the `mylang test` module-header requirement next to `@test`/`mylang
   test` in `functions.md` or the README's "Run guest tests" section**, or better,
   make `check`, `build`, and `test` agree on whether a headerless script is
   accepted. Right now three sibling commands differ on this and only one says so
   (by erroring, not by being documented).
2. **Add one worked example combining a `dict[str, Record]` value with a managed
   list field, mutated and written back**, in `managed-memory.md` or
   `records-and-unions.md`. This is the single most natural way to build a
   group-by aggregation (extremely common in exactly this kind of task), and the
   two docs currently only cover list-of-records and bare-record-local mutation
   separately.
3. **State explicitly, right where `mylang build -o` is introduced, that the
   resulting binary is a plain argv passthrough with no `--` convention**,
   contrasting it directly against `mylang run`'s `--` splitting in the same
   place (today the two facts are in the same file but several paragraphs apart,
   inviting exactly the wrong-assumption I made in point 3 above).

Total added friction from all of the above: well under an hour, out of a task
that otherwise went the way the docs described. The single biggest time sink
was point 2 (dict-of-records mutation) because it required writing and running
a throwaway probe program rather than being answerable from a doc search.
