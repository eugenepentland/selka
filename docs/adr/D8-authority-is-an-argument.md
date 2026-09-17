# D8: Authority is an argument

Status: accepted 2026-09-17; Wave 0 lands the reading surface, the remaining
waves land the semantics. Decisions D1-D8 are recorded in the plan
`docs/audits/effects-as-arguments-plan-2026-09-17.md` (section 2).

## Rule

Authority in mylang is an ordinary typed value that a caller passes as a
parameter, never an ambient facility a function reaches for by name. Five rules
hold at once:

1. **Capabilities are ordinary typed values passed as parameters.**
   `Filesystem`, `Network`, `Clock`, `Entropy` and `Environment` are scalar
   capability types. They may be passed, returned, reassigned, and stored in a
   `record` or `class` field like any other value; a bundle is a capability too.
2. **One entry point mints them.** Only the generated entry shim constructs a
   capability. `def main(fs: Filesystem, clock: Clock)` is the single source of
   authority for the process; there is no public constructor, cast, or literal
   that produces one.
3. **No forging.** A checked program cannot manufacture a capability of a kind
   the entry point did not declare, and the validator recomputes every effect
   summary independently rather than trusting the producer.
4. **Narrowing only.** A derived authority can be narrower than its source and
   never wider: `restrict_resource[read](fs)` intersects permissions, and any
   later `fs.read_only()`/`fs.dir(path)`/`env.only(...)` derivation follows the
   same intersection rule.
5. **Values over authority.** Where a value expresses the need, a value is
   preferred: `time.now(clock) -> Result[Instant, str]` and
   `random.from_entropy(rng)` hand back values so the authority need not travel
   with the data. Capabilities answer "may it"; the inferred effect mask answers
   "does it", and both stay.

Corollaries the rule already implies: no global `open()` or `now()` (the
capability comes first), no mutable global state (top-level declarations are
`const`), and closures cannot smuggle authority (lambdas are noncapturing and a
callback's effects are part of its type). `print`/`eprint` are the one remaining
ambient authority; D1 below closes that.

## Decisions

| # | Decision | Answer |
| --- | --- | --- |
| D1 | Output becomes a capability | **Yes.** Add a `Stream` capability; `out.print(...)` replaces `print(...)`, `err.print(...)` replaces `eprint`. Add a capability-free `debug(...)` stripped from `--mode ReleaseFast` builds. |
| D2 | Mandatory mutation footprint | **Yes.** An externally observable write without a `mutates(...)` clause is diagnosed regardless of a ceiling; one warning version (ADR D7) then an error. |
| D3 | Call-site `&` marker | **Defer**, decided with loop evidence after D2. |
| D4 | `inout` on value records | **No.** `class` is the reference type and `record` the copy. |
| D5 | `System` root bundle | **No**, keep per-capability entry parameters. |
| D6 | Foreign calls need a capability | **Yes.** Add a `Host` capability; every `extern def`/`host def` takes it as a checked leading parameter, dropped before the C call. |
| D7 | Allocation stays ambient | **Yes.** GC is the default; `managed_allocation`/`noalloc` keep tracking it. |
| D8 | Async | **No work.** Undecided in the sketch and needs no marker. |

## Rejected alternatives

- **A `System` root bundle** (D5). `def main(sys: System)` makes the reader open
  the body to learn which authorities the program can use, and weakens the
  command-line grant model (`--restrict`, `--allow-*`) that keys on one
  capability per entry parameter.
- **Capabilities alone, with effect inference removed.** Capabilities cannot
  express allocation or mutation, and the nine-bit effect mask is what lets a
  ceiling three calls up reject a leaf operation with a path in the diagnostic.
- **`inout`/by-reference records** (D4) and an **allocator parameter** (D7); see
  the decisions above.

## Compatibility consequence

Wave 0 changes no semantics: it repairs signature rendering so a reader sees
`Filesystem`/`Clock` rather than the removed `filesystem_cap`/`clock_cap` internal
names, and states this ADR. The semantic waves that follow carry the migration
costs the plan records — D1 rewrites printing call sites and moves the
CPython-oracle idiom probes that print, D2 needs a warning period, and D6 touches
every `extern def`/`host def`.
