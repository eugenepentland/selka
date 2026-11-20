# Language levers with cascading benefit — candidates and how to test them

Status: research proposal, 21 September 2026. Nothing here is implemented and no
agent session was run for it. Every number is taken from an existing audit,
experiment record or a static probe run for this document; every predicted
benefit is labelled as a prediction and carries the probe that would falsify it.

The question asked: which single language rules would each unlock several
improvements at once — local reasoning, runtime speed, loop latency, finding
bugs, implementing features, simpler code — for agents developing in mylang, and
how would an experiment show whether they do.

## 1. What the record says moves agent cost

The experiments already run constrain what a lever can be. The relevant results:

| Finding | Source |
| --- | --- |
| Session cost tracks activity, not change size. Within a task the correlates of cost are steps (+0.57), tool results showing a failure (+0.55), bytes returned by `read` (+0.31) and seconds inside compiler calls (+0.30); diff lines (−0.12) and blast radius (−0.22) do not predict it. | [cascade results](cascade-experiment-results-2026-09-19.md) |
| Phase split of one baseline change: 49,755 tokens reading, 8,907 editing, 43,277 verifying. Editing is under a tenth of a session; a design can only remove the editing part. | same |
| A design that states each domain fact once did not beat the baseline on any of seven tasks beyond run-to-run spread, and a static propagation score ranked the worst arm best. | same; [elegance-metrics](../../experiments/elegance-metrics/findings-2026-09-19.md) |
| Every repair round in a fresh session came from a Python habit meeting a small surface difference; rejections that carried their fix cost 0 turns, the four that did not cost 1 turn each. | [agent-usefulness plan §2](agent-usefulness-implementation-plan-2026-09-20.md) |
| Authored fix suggestions did not reduce failed compiler invocations (M1b: text 10 vs text_fix 23 failed checks; the only interval excluding zero is harm for JSON suggestions). | [M1b readout](m1b-diagnostic-feedback-readout-2026-09-19.md) |
| The invocation family (module name / module path) sat at 3.0 repair rounds in every feedback condition. Feedback cannot close it; only the design can. | [diagnostic-feedback findings](../../experiments/diagnostic-feedback/findings-2026-09-19.md) |
| Loop latency is negligible at small scale (check 80 ms, `run` 414 ms, 114 tests 4.0 s) and O(project) at scale: a 100k-line fixture rechecks all 33,475 bodies on a private edit (1.06 s), and a 53k-line synthetic project measured on 2026-09-17 paid 3.9 s per one-line-edit check and 70 s per warm unchanged build (that generator was not retained; the 100k matrix is the repo's record). | plan §2; [s1 final matrix](velocity-implementation/s1-final-2026-09-16/) |
| Runtime is 2.61× / 4.30× / 2.95× / 5.40× Zig on the four parser workloads under checked QBE; the composed experimental arm reaches 1.25× / 1.37×; the residual is memory volume (headers, list growth slack, root records, views). | [performance ergonomics](language-performance-ergonomics-2026-09-20.md), [parity gap](llvm-arena-parity-gap-2026-09-20.md) |
| First-try Python fidelity is 17 of 67 CPython-oracle probes; silent wrong answers 0; rejections naming an alternative 24 of 79. | [usefulness ledger](agent-usefulness-reports/ledger.md) |

Two instrument lessons bind the experiment section: total session tokens have an
assessment floor near 90k with a spread of 20k–85k, so three runs per cell cannot
resolve a design effect; and per-invocation, per-phase measures (failed checks on
changed source, bytes read before the first edit, verify-phase generated tokens,
compiler seconds) are what the M0 harness now records and what the post-mortems
recommend scoring.

So a lever qualifies only if it removes one of: bytes an agent must read to reach
a correct edit; failed checks per change; verification work per change; compiler
seconds per change; runtime memory volume. The more of these one rule touches,
the better the candidate.

## 2. Scoring frame

Each candidate is scored on the six axes in the question plus the three costs
the prior work says to price:

| Axis | What counts as evidence |
| --- | --- |
| Local reasoning | bytes an agent reads before its first edit; whether a signature or `context` answer is complete without a body |
| Runtime | cycles, instructions, memory volume on the parser workloads |
| Loop latency | check / build / test seconds per edit, and how many bodies or objects an edit invalidates |
| Finding bugs | where a violation is reported; whether a failure can be replayed |
| Implementing features | failed checks on changed source, repair rounds, first-try fidelity |
| Simpler code | annotations, declarations and lines the rule removes from the corpus |
| Fidelity risk | effect on C1 (first-try) and C2 (silent wrong answers, a hard gate) |
| Migration | how much existing `.my` changes and whether a tool can rewrite it |
| Implementation | which compiler stages change |

The corpus used for the static counts below is the non-test guest code in the
repository: `src/schematic/guest` (14 files, 2,127 lines), `experiments/sexpr-port`
(13 files, 2,678 lines), `src/stdlib` (23 files, 3,700 lines) and `examples`
(88 files, 1,795 lines): 757 function definitions.

## 3. Candidates

Ordered by how many axes one rule touches, weighted by the strength of the
evidence that the axis is a real cost today.

### L1. The signature is the whole contract

**Rule.** What a function may do is exactly what its parameters allow. Effects
follow from parameter types: a `Stream` parameter permits `output`, a
`Filesystem` parameter permits `filesystem`, a `Host` parameter permits `host`,
and so on; allocation stays ambient (decision D7); mutation is permitted only
through parameters marked writable. Nothing inferred from a body crosses a
function boundary. An omitted `effects(...)` clause means "the derived set", not
"no bound"; `noalloc`, `noio` and an explicit `effects(...)` survive only as
narrowings.

Spelling is secondary and two options fit the "identical to Python or visibly
different" rule the scorecard set: mark the parameter (`values: mut list[int]`)
or keep the existing `mutates(values)` clause and make it mandatory, which
decision D2 of the effects-as-arguments plan already accepted. Either way the
compiler already prints the exact clause to paste (`W_MUTATES_MISSING`), so
`fmt --fix` can apply it.

**What is true today.** Effects are inferred and the inferred mask is frozen as
the published ceiling. The incremental audit records the consequence: "a callee
body that adds an effect still rejects an unchanged effect-bounded caller, and a
changed inferred effect changes the declaration's `interface_sha256` so callers
are rechecked" ([wave 3](wave3-incremental-2026-09-15.md)). `list-interfaces`
must therefore distinguish `ceiling`, inferred and `unavailable`, and does so only
after the F1 package. The `effect_origin_passes` stage (`effects.check` with the
mutation/origin pass, [warm profile](velocity-implementation/s1-profile-warm-2026-09-16.md))
cost 0.24 s of the 3.9 s one-line-edit check on the 53k-line synthetic project.

Static counts for this document:

| Measure | Count |
| --- | --- |
| `effects(...)` clauses written in schematic + port + stdlib | 185 |
| of which exactly restate the parameter-derived set | 93 (50%) |
| of which are strictly narrower (an explicit `effects()` on a function with no capability parameter, i.e. `noalloc`-like) | 80 (43%) |
| other | 12 |
| functions taking a `list` or `dict` parameter | 102 of 757 |
| of which mutate that parameter (append / index write / pop …) | 10 |

So the rule deletes half the effect clauses in the corpus and asks for roughly
ten writable-parameter markers per 750 functions.

**Predicted cascade.**

| Axis | Prediction | Why it is plausible |
| --- | --- | --- |
| Local reasoning | An agent reads the signature and has the whole contract; `context` and `list-interfaces` never answer `unavailable`, and both work from a parse alone on a red project (scorecard item 2). | The facts are in the parameter list; no body check is needed to publish them. |
| Loop latency | A body edit never invalidates a dependent's checked body or native object unless the signature text changed; the effect verdict becomes per-body and cacheable. | Today an inferred-effect change rewrites `interface_sha256` and rechecks callers; the object cache is keyed on IL text, which a callee's inlined body can change. The 0.24 s effect pass is the smaller part; the reuse unlock is the larger. |
| Finding bugs | A violation is reported in the body that violates its own signature, never at a distant caller whose ceiling the callee just exceeded. | Quoted wave-3 behaviour: the rejection lands on the unchanged caller. |
| Implementing features | Fewer rounds spent discovering that a helper's write does not reach the caller (probe S03, `W_DEAD_RECORD_WRITE`), because a read-only parameter cannot be written at all and a writable one is visible at the call. | The aliasing decision's own argument. |
| Simpler code | −93 clauses in the corpus; `effects(host, managed_allocation)` disappears wherever `host: Host` is already in the parameter list. | Counted above. |
| Runtime | A callee that does not take `lx` writable cannot reassign `lx.src`, so `len(lx.src)` is loop-invariant across the call; the tokenizer's remaining reloads are exactly this. | [hot loops landed](hot-loops-landed-2026-09-19.md): "the only fix is proving that a named class instance and a managed list cannot alias each other". Unmeasured for this rule. |
| Runtime (second order) | A function with no capability parameter and no writable parameter is pure by signature, so a call with literal arguments can be evaluated at compile time; today's hand-written `ord("m")` fold becomes the general case and a module `const` no longer compiles to a call per use. | [runtime audit](runtime-performance-2026-09-18.md) root causes. |

**Costs.** Breaking for public functions that rely on an unbounded inferred
ceiling; the migration is mechanical (the compiler prints the derived clause).
First-try risk: an agent trained on Python will not write the writable marker,
so the rejection must carry the paste and `fmt --fix` must apply it; C1 and C2
are unaffected because the idiom probes are single-file scripts with no public
boundary. Implementation: `effects.check` becomes per-body; `sema` resolves the
ceiling from the parameter list; the interface digest drops inferred fields.

**Falsify before building.** (1) On a checked project, count exports whose
inferred effects are not a subset of the parameter-derived set plus allocation:
if more than about a tenth need a narrowing other than `noalloc`, the rule taxes
rather than derives. (2) On the 53k synthetic, make a body edit that adds an
allocation and one that does not, and count rechecked bodies with
`--explain-invalidation`: if the two invalidate the same set, the loop-latency
claim is already false for the checker. (3) Run `context --symbol` on the port
with and without body facts and compare the bytes needed for a complete answer.

### L2. Examples are the third part of a signature

**Rule.** A `>>>` example inside a function's docstring is a test. The compiler
runs it, caches its verdict by the body hash of the function and its callees,
selects it incrementally, counts it for the untested-export lint, accepts it for
the documentation gate, and shows it in `context` and `list-interfaces`. A
function that is pure by signature under L1 runs its examples through the
existing native invocation path; one that takes a capability needs a fake for it
and is out of scope for the first version.

Precondition: every value prints as an expression that reconstructs it.
Structural `==` on aggregates landed on 2026-09-18; a canonical printed form is
the remaining half.

**What is true today.** Tests are `public def test_*() -> bool` in separate
files, must be exported, cannot live in a subdirectory of a project, and reach
the code only through calls, so the untested-export rule had to be taught
reachability (22 → 8 findings on the port). Verification is the second-largest
phase of a session (43,277 of 101,939 tokens on B/T7), and reading test files is
part of the read phase. Docstrings already parse (probe a12). `mylang doctest`
runs fenced examples in Markdown, not in source.

**Predicted cascade.**

| Axis | Prediction | Why it is plausible |
| --- | --- | --- |
| Implementing features / verify | The verify phase shrinks: the agent writes the example next to the function while it has the function in context, and the test needs no file, no export and no name discipline. | Doctest is a Python habit; the session probe shows habits that match cost 0 turns. |
| Local reasoning | The example is the cheapest specification to read; `context` returns it with the signature. | Reading is half of a session. |
| Loop latency | The test set for an edit is exactly the examples of the bodies whose hash changed plus their dependents; pure examples are evaluated in one process rather than one native build each. | Selective tests already exist; the guest test path pays a native build per test today (1/8/32 cached tests = 47.5 / 378.6 / 1,811.6 ms). |
| Finding bugs | A failing example names the function and the literal input; nothing to navigate. | Locality by construction. |
| Simpler code | The 118 `test_` functions in the corpus that only call a pure function and compare a value collapse into one line each beside the function. | Counted; the fraction that is pure by signature is the number probe (1) under L1 gives. |

**Costs.** A doctest grammar, the canonical repr, a runner; no change to
semantics, so fidelity and migration risk are nil. Depends on L1 only for
knowing which functions are example-able without fakes.

**Falsify before building.** From the cascade run records, split the verify
phase into reading test output, reading test files and editing tests; if the
first two are small, the lever has no room. Then a dry pilot: rewrite the
port's 79 tests as docstring examples where the function is pure by signature
and report the fraction covered; if it is under half, capability fakes are a
prerequisite, not a follow-up.

### L3. A module is its path; visibility is spelling; tests live anywhere

**Rule.** A module's name is its path from the project root. Every top-level
declaration is visible to importers unless its name starts with `_`. A
`test_` function is discovered wherever it is under the root. There is no
`module` header and no `public` keyword.

**What is true today.** The header must repeat the path, the entry file's
directory is the root, and a mismatch is `E_MODULE_NAME` before anything else is
checked — the probe for this document hit it on its first attempt. The M1
experiment's invocation family stayed at 3.0 repair rounds under every feedback
condition; idiom probes a36 and a41 fail on the header; tests cannot live in a
subdirectory (readiness item 5); the M3 experiment exists only to test whether a
wrapper can hide the root question. The corpus carries 99 headers and 437
`public` lines. Backlog item D-1 already describes this rule.

**Predicted cascade.**

| Axis | Prediction | Why it is plausible |
| --- | --- | --- |
| Implementing features | The invocation family's failed checks go to zero; every `E_MODULE_NAME` / `E_MODULE_HEADER` / `E_PRIVATE_SYMBOL` round disappears. | These are exactly the rounds no feedback could remove. |
| Local reasoning | File path = import path; the agent navigates the project as it navigates any Python package. | Python habit. |
| Simpler code | −99 header lines, −437 `public` tokens, no `export` ceremony on tests. | Counted. |
| Loop latency | None directly; but interface queries need no root argument, so the M3 wrapper and the root-inference code path vanish. | — |
| Finding bugs | None. | — |

**Costs.** `public` also feeds the `undocumented-export` and untested-export
lints; the underscore convention keeps that signal. Two-segment qualification
(backlog C-13) must work first. Migration is a mechanical rewrite. Implementation
is confined to the parser and module loader.

**Falsify before building.** Rerun the M1 invocation-family cases under a
compiler flag that derives the module name from the path: repair rounds should
fall from 3.0 to about 0 on every case, with nothing else changed. If they do
not, the family's cause is not the header.

### L4. Arena scopes are real regions (cash in an existing rule)

**Rule (already in the language).** A managed value first assigned inside
`with arena()` is confined to the block; reading it afterwards is a static
`E_ARENA_ESCAPE`, and `escape()` copies. What is missing is the runtime
exploiting the rule: allocation inside an arena is "not bump allocation", each
object carries its header, and collection still runs ([arenas](../arenas.md)).

**Evidence for the size of the prize.** The compact-arena experimental arm
(LLVM, no collecting GC, checks removed) measures 1.51× / 2.37× / 1.62× / 2.98×
against 2.61× / 4.30× / 2.95× / 5.40× for checked QBE; the parity audit names
"a frozen slice, and an arena that grows the youngest allocation in place" as
the largest remaining item and prices the 96-byte object header at −11 M / −30 M
cycles. The one known defect is `buffer_frozen` reading a header the compact
allocator never writes.

**Cascade.** Runtime and memory volume only; reasoning, latency and code are
unchanged because the rule already exists. It is listed because it is the
largest runtime lever on the table and needs no new syntax, which is the
cascade test passed in the cheapest possible way.

**Falsify.** The arena-maxperf experiment already did; what remains is the
engineering plan in the parity audit. Not an agent experiment.

### L5. Record and replay (cash in capabilities as arguments)

**Rule (already in the language).** Every source of nondeterminism enters
through a capability parameter, so a run can be recorded at the capability
boundary and replayed exactly. Missing: `run --record`, `replay --at
file:line` printing the bindings, and turning a recording into a test.

**Evidence.** The scorecard scores observability 1 of 3 ("trap stacks only")
and ranks tracing/replay eighth; no experiment has measured debugging cost at
all, and no lever above touches it except by locality.

**Cascade.** Finding bugs (reproduce without reasoning about the input), test
generation (a recording is a golden), flake elimination. No syntax; runtime
shims per capability plus a trace format.

**Falsify.** Needs a new task family: seeded runtime faults with a failing
input and a hidden root cause, scored by steps and failed checks to the fix,
with and without replay. Nothing in the existing packs measures this.

### L6. Python fidelity under one rule: identical or visibly different

The scorecard's own recommendation: every construct either behaves like Python
or looks different. The concrete items are the backlog's C-2 (tuples), C-3
(`is None` narrowing, `unwrap_or`), C-4 (ternary, chained comparison), C-6
(methods as receiver-first sugar), C-7 (format specs, `round(x, n)`), C-10
(sets), C-11 (nested generators, dict comprehension).

**Evidence.** C1 is 17 of 67; every repair round in the 20 September session
was a Python habit. Strongest evidence of any lever, narrowest cascade: it
touches implementing features and, through tuples, simpler code (a single-use
record per multiple return). One expected cascade is smaller than it looks:
of 135 `match` statements in the corpus, 18 are on `Option` and 72 on `Result`,
so `is None` narrowing removes at most 18 blocks; the `Result` matches are
error handling that `?` cannot replace.

**Falsify.** The idiom suite is the instrument (`velocity/score.py`), and it
already exists; a greenfield task pack adds repair rounds.

### Compositions

- **L1 + L2.** Purity by signature makes examples evaluable at check time, so
  for pure functions verification collapses into `check`.
- **L1 + L3.** With effects in the parameter list and modules on paths, the
  complete interface of a project is available from a parse, so
  `list-interfaces`, `context`, `tests-for` and impact queries answer on a red
  project in the time a parse takes.
- **L2 + L5.** A replayed failing run is one example away from a regression
  test.

## 4. Ranking

Predicted axis coverage (● strong, ○ some, — none), evidence that the axis is
a real cost today, and the costs:

| Lever | Reasoning | Runtime | Latency | Bugs | Features | Simpler | Evidence | Fidelity risk | Migration | Impl |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L1 signature is the contract | ● | ○ | ● | ● | ○ | ● | medium: wave-3 coupling, corpus counts, S03 | low (single-file unaffected); the writable marker needs its paste | mechanical | medium |
| L2 examples in the signature | ● | — | ○ | ● | ● | ○ | medium: verify phase 43%, test-path costs | none | none | medium |
| L3 modules are paths | ○ | — | ○ | — | ● | ● | strong: M1 invocation family, probes a36/a41 | none | mechanical | small |
| L4 real arena regions | — | ● | — | — | — | — | strong: maxperf arm, parity audit | none | none | large (runtime) |
| L5 record and replay | — | — | — | ● | ○ | — | weak: no debugging measurement exists | none | none | medium |
| L6 fidelity batch | — | — | — | — | ● | ○ | strong: C1, session probe | improves C1; C2 gate must hold | none | small each |

Recommendation: run the agent experiment on **L1 + L3** as one dialect and
**L2** as a second, because those are the levers whose cascade claims the
existing instruments can falsify and whose predicted axes are the ones the
cascade post-mortem says dominate cost (reading, failed checks, verification).
L4 belongs to the runtime plan and needs no agent runs. L5 needs a new task
family first. L6 goes through the idiom suite, which already scores it.

## 5. The experiment

Built from the pieces that already exist and the corrections the reviews
demanded; nothing below needs a new harness.

**Subjects.** The cascade pack: the port as arm B with tasks T1–T7, hidden
Zig goldens and guest tests at `../mylang-eval/cascade/`, 79 tests pinned by
`arm_gate.py --expect-tests 79`. For L3 add the M1 fault corpus's invocation
family. For a greenfield reading, the twelve-task development corpus under
`experiments/development_velocity/corpus/`.

**Treatments as dialects of one codebase.** Same compiler binary, one frozen
flag set per arm, hidden verification independent of the arm:

| Arm | Source | Compiler flags |
| --- | --- | --- |
| B | the port as is | none |
| B+L3 | headers removed, `_` privacy, tests moved beside the code | `--modules=path` |
| B+L1+L3 | above, plus derived effects and writable-parameter markers, effect clauses deleted where derivable | `--contract=signature` |
| B+L1+L2+L3 | above, plus docstring examples replacing every test that is pure by signature | `--doctest` |

The three rewritten arms are produced by a script, not a designer, so there is
no designer cost to recover and no representation choice to confound the
result — the cascade experiment's upfront term is zero here by construction.

**Measures.** From the M0 event collector (one event per compiler process,
source hash per invocation, outcome classified): failed checks on changed
source; distinct failed candidate versions; steps; bytes returned by `read`
before the first edit; generated tokens per phase (read / edit / verify);
compiler seconds; hidden acceptance as the gate. Cost term v2 or generated
tokens, never input plus output. Both Zig caches pinned inside the working
copy; the wrapper unreadable; one participant at a time; 900 s deadline and a
20-invocation cap enforced by the runner.

**Design.** Paired blocks per (task, repetition), arm order randomized within a
block with a recorded seed. A pilot of two tasks × four arms × three
repetitions first, to size the per-phase spreads (the only spreads known are
on total tokens); then the main cohort with the repetitions the pilot says are
needed, expected five or more per cell. Frozen cohort manifest before the
first cell; retries are new attempts; scoring reads the manifest only.

**Predeclared decisions.**

| Lever | Passes if | Fails if |
| --- | --- | --- |
| L3 | failed checks from the invocation family are 0 in every B+L3 cell | any cell still pays one |
| L1 | bytes read before the first edit fall by at least a fifth against B+L3, and failed checks on changed source do not rise | failed checks rise (the writable-marker tax) or reading does not fall |
| L2 | verify-phase generated tokens fall by at least a quarter against B+L1+L3 with hidden acceptance unchanged | acceptance drops or verification does not fall |

If a treatment moves only total tokens and none of the phase measures, the
result is reported as inconclusive, not as a benefit.

**Budget.** The cascade cohort cost 11.9 M tokens for 80 sessions on the v1
term. Four arms × seven tasks × five repetitions is 140 sessions, so plan for
about that order again; the pilot is 24 sessions. The static falsification
probes in §3 cost minutes and should run first; any lever they kill leaves the
cohort.

## 6. Measured already; do not re-test

| Idea | Result | Where |
| --- | --- | --- |
| Authored fix suggestions in diagnostics | no fewer failed invocations; JSON rendering harm-leaning | M1b readout |
| Design-level "state each fact once" | 0 wins, 0 losses beyond spread; R < 0 | cascade results |
| Static propagation / blast-radius score | does not predict change cost | elegance-metrics |
| Surface single-assignment | QBE already builds phis from reassignment | language-level SSA audit |
| Frozen child sequences in the AST | 4–18% slower | byte-buffer landed |
| Descending-alignment field reordering | zero bytes saved on 130 descriptors | struct-layout audit |
| Scalar field caching | 0 cycles | hot-loop plan |
| `list[int]` as a byte buffer | 2× worse | performance ergonomics |

## Appendix: what each lever looks like in source

Every "before" below is real corpus code; every "after" is the proposed
spelling. Diagnostics in the "after" column are illustrative wording.

### L1 — the signature is the whole contract

Effect clauses that restate the parameter list disappear; narrowings stay.

```text
# doc: not-mylang
# before — src/schematic/guest/layout_graph.my
public def rail(host: Host, span: text.Span) -> bool effects(host, managed_allocation):
public def find(host: Host, nets: list[Net], span: text.Span) -> int effects(host):

# after — `host: Host` already says `host`; allocation is ambient; `find` was a narrowing
public def rail(host: Host, span: text.Span) -> bool:
public def find(host: Host, nets: list[Net], span: text.Span) -> int noalloc:
```

Mutation moves from an advisory clause to the parameter.

```text
# doc: not-mylang
# before — src/stdlib/json.my (accepted today; W_MUTATES_MISSING is advisory)
def write_value(pieces: list[str], value: Json):
        pieces.append("null")

# after — either spelling; the compiler prints the one to paste and `fmt --fix` applies it
def write_value(pieces: mut list[str], value: Json):
def write_value(pieces: list[str], value: Json) mutates(pieces):

# a write through a read-only parameter is one error, for record and class alike
def bump(c: Counter):
    c.n = c.n + 1
# error[E_READONLY_PARAM]: `c` is read-only here; declare `c: mut Counter` to write through it
```

The violation is reported where it happens, not at a bounded caller.

```text
# doc: not-mylang
# before — the callee gained an allocation; the unchanged caller is rejected
layout.my:21: error[E_EFFECT_BOUND]: rail exceeds effects(host): g.rail performs managed_allocation

# after — the body is checked against its own signature
layout_graph.my:19: error[E_EFFECT_BOUND]: rail is noalloc but text.matches(...) allocates
```

Interfaces come from a parse and never say `unavailable`:

```text
# doc: not-mylang
module sexpr.parser
  public parse(src: bytes) -> Result[list[Node], ParseError]          pure
  public parse_with_depth_cap(src: bytes, cap: int) -> Result[...]    pure
module json
  write_value(pieces: mut list[str], value: Json)                     writes pieces
module layout_graph
  public rail(host: Host, span: Span) -> bool                         host
```

Runtime consequence (prediction): the tokenizer copies `lx.src` to a local in
five functions by hand so `len(src)` stays hoisted; with `lx: mut Lexer` only
on the functions that advance, a helper taking `lx: Lexer` provably cannot
reassign `lx.src`, so the hoist survives the call without the manual copy. A
function with no capability and no `mut` parameter is pure by signature, so
`value * mil_to_mm()` and `si_scale(ord("k"))` fold at compile time.

### L2 — examples are the third part of a signature

```text
# doc: not-mylang
# before — experiments/sexpr-port/tests/parser_test.my: ~40 lines of helpers, then
public def test_parse_atom() -> bool:
    return node_count(b"(hello)") == 1 and child_kind(b"(hello)", 0, 0) == 1 and child_text(b"(hello)", 0, 0) == "hello"

# after — beside the function, in sexpr/parser.my
def si_scale(letter: int) -> float:
    """The multiplier an SI suffix byte selects; 1.0 for anything else.

    >>> si_scale(ord("k"))
    1000.0
    >>> si_scale(ord("x"))
    1.0
    """

public def parse(src: bytes) -> Result[list[ast.Node], ParseError]:
    """
    >>> parse(b"")
    Ok([])
    >>> parse(b"(a")
    Err(ParseError(message="unexpected end of input — a '(' was never closed", line=1, col=1, offset=0))
    """
```

Running and selecting:

```text
# doc: not-mylang
$ mylang test sexpr/                       # examples and test_ functions alike
sexpr/parser.my:96  si_scale  example 1 … ok
sexpr/parser.my:96  si_scale  example 2 … ok (cached)
sexpr/parser.my:210 parse     example 2
  expected: Err(ParseError(message="unexpected end of input — a '(' was never closed", line=1, col=1, offset=0))
  got:      Err(ParseError(message="unexpected end of input", line=1, col=1, offset=0))

$ mylang test sexpr/ --affected            # after editing si_number_end: only its dependents' examples run
selected 4 examples: si_number_end, parse_si, parse_leaf, parse
```

`context --symbol sexpr.parser.parse` returns the signature and the examples
first. A function taking `host: Host` or `out: Stream` is not example-able in
the first version; it keeps a `test_` function.

### L3 — a module is its path

```text
# doc: not-mylang
# before
sexpr/ast.my            module sexpr.ast … public record Span … public def is_form … def is_atom_named
tests/parser_test.my    module tests.parser_test … public def test_parse_atom
main.my:1:8: error[E_MODULE_NAME]: declared module name does not match its requested path

# after — no header, `_` is private, tests sit beside the code
sexpr/ast.my
    import sexpr.view as view
    record Span:
        line: u32
        col: u32
        offset: u32
    def is_form(node: Node, name: str) -> bool: …
    def _is_atom_named(node: Node, name: str) -> bool: …
sexpr/parser_test.my
    def test_parse_atom() -> bool: …
```

The root is the nearest ancestor holding `mylang.json`, else the entry file's
directory as today; `mylang test sexpr/` works from any working directory.

### L4 — arena scopes are real regions

Source is unchanged; the runtime changes.

```text
# doc: not-mylang
def census(src: bytes) -> Result[int, ParseError]:
    with arena() as scratch:
        forms = parse(src)?            # today: one host allocation with a 96-byte header per node, still traced
        return Ok(count(forms))        # after: bump-allocated, headerless, freed in one step, never traced
```

The compact-arena arm already measures 1.51× Zig on census against 2.61×
checked; `escape()` keeps copy semantics until a unique-owner move is proven.

### L5 — record and replay

```text
# doc: not-mylang
$ mylang run main.my --record trace.myrec -- board.kicad_sch
$ mylang replay trace.myrec --at sexpr/parser.my:151
parse_leaf(src=<bytes 927415>, raw=RawToken(kind=Kind.si_val, text_start=8812, text_end=8816, …))
  span = Span(line=214, col=9, offset=8812)
  end  = 3
$ mylang replay trace.myrec --to-test sexpr/parser_test.my::test_board_regression
```

Everything nondeterministic entered through `fs`, `clock` or argv, so the
recording is the capability call log and replay is exact.

### L6 — identical or visibly different

```text
# doc: not-mylang
# before                                   # after
record Split:                              def split_at(v: list[int], i: int) -> (list[int], list[int]):
    head: list[int]                            return v[:i], v[i:]
    tail: list[int]                        head, tail = split_at(values, 3)
def split_at(...) -> Split

match maybe:                               if maybe is not None:
    case Some(v): use(v)                       use(maybe)        # narrowed to the payload
    case None: pass

def next_raw(lx: Lexer) -> …               class Lexer:
next_raw(lx)                                   def next_raw(self) -> …     # sugar for next_raw(lx: Lexer)
                                           lx.next_raw()
```

### L2 with effects — how an example tests a function that needs capabilities

The rule that makes this work is one the language already has: authority is an
argument. A function that prints takes `out: Stream`; one that reads files takes
`fs: Filesystem`; time, randomness and the environment are `Clock`, `Entropy`
and `Environment` parameters. So an example never needs to intercept anything.
It builds the capability from a literal, passes it, and afterwards reads the
capability back like any other value.

**Mechanics.** Each docstring is compiled as one synthetic test body returning
`Result[None, str]`: expression lines are compared against their canonical
printed form, statement lines print nothing, `?` propagates and a propagated
`Err` fails the example with its payload. The body is built and run exactly
like a `test_` function today — its own native process, no ambient capabilities,
memory ceiling, `--gc-stress` available, verdict cached by the body hash of the
function and its callees. Nothing new in the runtime; the fakes are library
types.

**In-memory capabilities** (proposed constructors; the method names are the
existing ones from `docs/io.md`):

| Capability | Constructor | Inspect afterwards |
| --- | --- | --- |
| `Stream` | `Stream.buffer()` | `out.text()` |
| `Filesystem` | `Filesystem.memory({"in.sexp": b"(a b)"})`, or `Filesystem.dir("fixtures/", read_only=True)` for real fixture files (the `--allow-read=DIR` grant that already exists) | `fs.read_text(path)`, `fs.exists(path)`, `fs.listdir(path)` |
| `Clock` | `Clock.fixed("2026-09-21T10:00:00Z")` or `Clock.stepping(start, step_ms)` | — |
| `Entropy` | `Entropy.seeded(7)` (what `--allow-random=SEED` pins today) | — |
| `Environment` | `Environment.of({"HOME": "/tmp"})` | `env.names()` |
| `Network` | `Network.scripted({"10.0.0.1:80": [b"200 OK…"]})` | `net.requests()` |
| `Host` | not constructible from a literal; see below | — |

**Examples.**

```text
# doc: not-mylang
def export(fs: Filesystem, out: Stream, path: str) -> Result[int, str]:
    """Write the canonical form of the S-expression at `path` back to `path`.canon
    and report the byte count.

    >>> fs = Filesystem.memory({"a.sexp": b"( a   b )"})
    >>> out = Stream.buffer()
    >>> export(fs, out, "a.sexp")
    Ok(5)
    >>> fs.read_text("a.sexp.canon")
    Ok("(a b)")
    >>> out.text()
    "wrote 5 bytes to a.sexp.canon\n"
    >>> export(fs, out, "missing.sexp")
    Err("missing.sexp: no such file")
    """

def stamp(clock: Clock, entropy: Entropy) -> str:
    """
    >>> stamp(Clock.fixed("2026-09-21T10:00:00Z"), Entropy.seeded(7))
    "20260921-100000-4d2f"
    """

def write_value(pieces: mut list[str], value: Json):
    """Append the JSON text of `value` to `pieces`.

    >>> pieces: list[str] = []
    >>> write_value(pieces, Json.integer(42))
    >>> pieces
    ["42"]
    """

public def next_raw(lx: mut Lexer) -> Result[RawToken, LexError]:
    """
    >>> lx = lexer(b"(net 1)")
    >>> next_raw(lx)
    Ok(RawToken(kind=Kind.lparen, text_start=0, text_end=1, source=Source(span=Span(line=1, col=1, offset=0))))
    >>> lx.pos
    1
    """
```

The effect checker applies to the example as to any body: an example under a
`noio` function cannot pass a real filesystem, and an example that forgets a
required capability is rejected at check time, not at run time.

**Transcript form.** A capturing `Stream` can also be compared as a trace,
which is the form the L5 recorder emits, so a replayed run and a docstring
example share one text:

```text
# doc: not-mylang
>>> greet(out, "bob")
out: hello bob
```

**What stays a `test_` function.** Large fixtures (the 927 KB board), anything
that needs a real directory tree beyond `Filesystem.dir`, and functions taking
`host: Host`. `Host` is the one capability with no literal constructor because
its members are provided by the embedding program; the honest first version
keeps those on the existing native test fixtures, and the L5 composition adds
`Host.replay("fixtures/board-1.myrec")` later, where the recording is the
host-call transcript of a real run.
