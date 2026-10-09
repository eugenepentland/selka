# Scorecard against the agent-oriented language audit guide — 17 September 2026

**Question asked:** the "Audit Guide for an AI-Agent-Oriented Programming Language"
(the user's document, 17 September 2026; it is not checked in) scores a language
0–3 on seventeen weighted categories, asks for evidence per row, and ends with a
list of decisions the audit must produce. Where does the language stand today, and
what has to change for it to meet the guide's goal of maximising an agent's
development speed on a large codebase?

**Method.** Nothing in the implementation was changed and no gate was run. Every
claim below is a probe executed against the installed `zig-out/bin/mylang`
(compiler identity `4a035f2a606e4e72…`) on 17 September 2026, built from the
working tree at `bcd0c652` plus 70 uncommitted paths. That uncommitted work
matters for the scores: it already removes `E_EFFECT_CEILING` in favour of inferred
export ceilings, stops counting `str` literals as allocation, limits the overlap
check to a declared `mutates(...)`, lets tests print, accepts library modules and
`*_test.my` files as test entries, discovers project roots in directory runs,
raises the module cap to 4,096 and removes the default step and frame budgets from
`run`. The scores are for the binary as built, not for the last commit. The
evidence file
[`agent-audit-guide-scorecard-2026-09-17-probes.json`](agent-audit-guide-scorecard-2026-09-17-probes.json)
holds 54 probes with their sources, exact commands and outputs, nine wall-clock
timing series, and a rerun of the 110 idiom probes from
[this morning's velocity audit](agent-velocity-2026-09-17.md). Probe IDs below
(`D01`, `I06`, `T05`, …) refer to that file. The machine's load average was 1.6 to
2.5 during the run; the velocity audit's timings were taken at 12 to 32, which is
why its edit-loop numbers are higher than the ones here.

## Verdict

**307 of 441 weighted points, 69.6%**, which the guide reads as "strong prototype
target; begin controlled agent evaluations". No category scores zero. Three score
one: change-impact analysis, runtime tracing and observability, and source token
efficiency. Everything the guide puts first — repository-scale comprehensibility
and semantic simplicity — is either already in place or within reach of work that
needs no new language design, with one exception: the language runs Python syntax
over two aliasing models, and the guide's "what is copied or shared at a call?"
question still has a "depending" answer. That is the one semantic decision left.

In the guide's own priority order, the state is:

1. **Repository-scale comprehensibility:** the module graph, per-declaration
   interface and body fingerprints, exported contracts with inferred effects and
   mutation facts, and a navigation index all exist and are machine-readable. The
   gap is that change-impact questions are answered by an external script and go
   dark the moment the project fails to check, which is the state an agent
   iterates in.
2. **Semantic simplicity:** no inheritance, overloading, implicit conversion,
   exceptions, closures or macros; GC by default with lexical arenas and a static
   escape check. The gap is `record`/`class` copying while `list`/`dict` share.
3. **Feedback quality:** every diagnostic is located, most carry related spans,
   several carry a causal chain, and all of it is available as versioned JSON. The
   gap is the oracle half: no suggested names, no machine-applicable fixes, and
   internal type spellings in messages.
4. **Edit-build-test cycle:** checking is fast and precisely incremental. Running
   and testing are not: a warm unchanged native build of the 14-module schematic
   guest spends 2.3 s in the frontend and 0.6 s in codegen to compile nothing.
5. **Surface syntax:** Python-shaped and terse inside bodies; ceremony at module
   boundaries; the Python idioms an agent writes first still mostly fail.

## 1. What already meets the guide

These rows scored 3, or scored 2 for reasons that need no redesign. Leave them
alone and build on them.

- **Memory model.** GC is the only allocation path, `with arena()` is the only
  lifetime control, and a value that would outlive its arena is a static
  `E_ARENA_ESCAPE` whose message names the fix, the arena and the declaration
  (`D03`). No allocator parameters, no lifetimes, no borrow annotations. This is
  the "GC plus lexical arenas plus explicit escape hatch" shape the guide
  recommends, implemented rather than intended.
- **Interface and body fingerprints.** `project-dependencies` reports a separate
  `interface_sha256` and `body_sha256` per declaration and a project-wide
  interface hash (`P09`). A comment-only edit rechecks zero of 114 bodies
  (`T03`); a one-line semantic edit rechecks one (`T04`); an interface edit is
  explained with `first_changed: interface` and fails only the true dependents
  (`I05`). Keys include the compiler identity, so a rebuilt compiler never reads
  an older build's entries.
- **Test isolation and reuse.** Each test runs as a fresh native process with no
  ambient capability. Receipts are keyed by dependency closure: after a
  body-only edit to an unexported helper, the unrelated `test_area` was reused
  and only its dependents ran (`I04`). Print inside a test is captured and shown
  on failure, and a failed comparison prints `expected true, got false` (`P04`).
- **Structured diagnostics.** `--diagnostics=json` emits one `diagnostic-v1` line
  per error with byte ranges, role-tagged notes and, for traps, a source-mapped
  stack with structured detail (`D14`–`D16`, `R02`). Visibility violations point
  at the private declaration (`D17`), cycles print the path (`D19`), unhandled
  results name the binding (`D05`), and an effect bound broken one call down names
  the path and the originating operation (`D13`). Errors in separate functions
  are all reported (`D10`).
- **Dependency graph.** `list-modules`, `project-dependencies` and
  `index-project` give the import graph with hashes, the declaration identities,
  and call, read and type edges with source ranges (`P08`–`P10`).
- **FFI boundary.** `extern def` is the only foreign surface, it carries a
  mandatory `effects(host)`, it accepts scalars only, and a wrong signature is
  rejected at the declaration with a message listing what is allowed (`D09`).
  Unsafety is one grep away.
- **Determinism.** Objects are content-addressed, tests get no clock, entropy or
  filesystem unless a fixture grants them, and `--allow-random=SEED` pins the
  stream. Nothing in the language reads a wall clock or a random source without
  a capability value.

## 2. What must change, in priority order

### 2.1 Decide the aliasing model

`record` and its alias `class` copy on assignment and on call; `list`, `dict`
and `str` share. A Python-shaped write through a record parameter still compiles,
runs, and changes nothing:

```text
# doc: not-mylang
record Counter:
    n: int

def bump(c: Counter):
    c.n = c.n + 1

def main() -> int:
    c = Counter(n=1)
    bump(c)
    return c.n          # S03: prints 1, no warning under run or check (S03c)
```

The new `W_DEAD_RECORD_WRITE` warning catches the loop-variable and alias copies
(`S01`, `S04`) but not the parameter case, and a warning is not a stop: `S01`
still exits 0 with the wrong count. A Python programmer, and every agent trained
on one, reads `class` as a reference type; here `class` is the value type with
the opposite behaviour, which is the most dangerous spelling in the language. The
guide's charter question "what is copied, shared or moved at a call?" has the
answer "scalars and records are copied, collections are shared, and a record
holding a collection copies the record but shares the collection", which is the
"depending on context" answer the guide says to simplify away.

**Recommendation.** Make `class` a managed reference type, like `list`, and keep
`record` as the explicit value type. The answer then becomes Python's own:
`class`, `list` and `dict` share; `record` and scalars copy. Until that lands,
extend the dead-write analysis to by-value parameters and make it an error, not
a warning. This was recommended in the velocity audit (§1.1 there) and is the
only item in this scorecard that needs a language decision rather than tooling.

### 2.2 Answer change-impact questions while the project is red

The guide's §4.4 lists six questions. Today two are answerable — who calls this
symbol, and what does this symbol reach — and only through
`scripts/navigate.py` over the JSON `index-project` dumps, with a default cap of
20 rows. The moment any body fails to check, the index drops every semantic edge:
`I06` asks for the callers of `area` after an interface edit and gets
`checked: false`, `semantic_relations_available: false` and no references. On the
same project restored to green, `I08` and `I09` list both callers. An agent
performing a multi-file change is red between the first edit and the last, which
is exactly when it needs "who else calls this".

Not answerable at all: which tests transitively cover a symbol (the test runner
holds that graph in its receipts but exposes no query), which modules must
recompile for a body versus an interface change (the invalidation report says it
after the fact, per stage, not per symbol), and which serialized formats or FFI
boundaries mention a type.

**Recommendation.** Keep edges from every function that did check and mark only
the failed ones unknown. Move callers, callees, impact and a new tests-for query
into the binary, without the row cap, so no Python is needed. This is the highest
weighted gap after the aliasing decision.

### 2.3 Make `run` and `test` as cheap as `check`

Measured on a copy of the 14-module, 2,186-line schematic guest with a fresh
cache directory (`T01`–`T09`):

| Step | Wall time | What the report says |
| --- | --- | --- |
| `check-project` cold | 0.26 s | |
| `check-project` warm, unchanged | 0.050–0.056 s | |
| comment-only edit, `check-project` | 0.17–0.18 s | 0 of 114 bodies rechecked |
| one new statement, `check-project` | 0.17–0.19 s | 1 of 114 bodies rechecked |
| `build` warm, unchanged | 2.9–3.0 s | 0 functions compiled, 115 reused; frontend 2.32 s, codegen 0.63 s, link 0.05 s |
| `run` warm, unchanged | 2.7–3.9 s | the program itself exits immediately |
| `build` warm, single-file `factorial.my` | 0.08–0.10 s | frontend 0.04 s |
| `build` warm, three-module `examples/modules` | 0.08–0.10 s | |
| `check` of a 20-line file | 0.02–0.03 s | |

The checker's per-body reuse does not reach the build path: with nothing to
compile, the build's own frontend takes 2.3 s where `check-project` takes 0.05 s
on the same sources, and codegen spends 0.6 s deciding that all 115 functions are
reusable. Small programs hide this; the cost grows with the project. Agents call
`run` and `test`, not `check`, so this is the largest wall-clock win available
and needs no language change.

### 2.4 Show inferred mutation where an agent looks first

The checker already infers which parameters a function writes: `index-project`
reports `mutates: [0]` and `mutation_writes: true` for two unannotated helpers
that append to their arguments (`I10`), and `schema-project` carries the same
facts (`I12`). The compact view an agent would read first, `list-interfaces`,
prints only names (`I11`). Print the effect set and the mutated parameter names
there. That meets the guide's "explicit mutation at parameter sites" requirement
without adding a `mut` keyword, in the way Go does for slices and maps: no marker
in source, but the fact is one query away.

### 2.5 Finish removing the ceremony

The uncommitted tree already removed the largest items. What remains, with the
probe that shows it:

| What an agent writes | What happens | Probe |
| --- | --- | --- |
| `mylang check main.my` on a project entry | `E_SYNTAX: expected def` on `module main`; only `check-project` accepts it, and `run` auto-detects | `P02` |
| `def test_area() -> bool:` without `export test_area` | not discovered; the run reports only the exported tests | `P04` |
| `module shared.geometry` in `shared/geometry.my` | required, and it repeats the path | `P01` |
| one `export name` line per public declaration | 140 export lines for 189 functions in the standard library, 59 for 103 in the schematic guest | source counts |
| `effects(managed_allocation)` on 65 standard-library functions | now redundant since literals stopped counting, still present | source counts |

Derive the module name from the path, let `check` detect a project entry the way
`run` does, discover `test_` functions without `export`, and either export by
default with Python's leading-underscore convention or accept a prefix on the
declaration. Then delete the 65 redundant annotations.

### 2.6 Turn the diagnostics into the oracle the guide describes

The guide wants a diagnostic to carry the span, the rule, expected versus actual,
the origin chain, and a machine-applicable fix. The first two are always present.
The rest:

- **No suggestions anywhere.** A one-letter typo in a function name gets
  `no function has this qualified name` with no candidate (`D06`); an unknown
  field names neither the record nor its fields (`D07`); a misspelled method on a
  list is `unknown managed collection method` with no list of methods (`D11`,
  second error); `E_ARITY` says `missing required argument` without expected and
  given counts (`D08`).
- **No origin for type mismatches.** `expected i64, found str` points at the
  argument and not at the parameter declaration that imposed the type (`D01`),
  while the arena, effect, result and unbound errors all do carry their origin.
- **Internal spellings.** Messages say `i64`, `List<i64>` and `Option<i64>`
  where the source says `int`, `list[int]` and `Option[int]`; an agent that
  copies the diagnostic's type into source produces a second error.
- **Fixes are prose, not data.** Only the arena escape and the removed
  spellings name a fix, and only in the message text; the JSON has no fix field.
- **No catalogue.** 203 diagnostic codes, no `explain` command and no page that
  lists them.

### 2.7 Add the Python that removes turns

Re-running this morning's 110 idiom probes against this binary changed five
outcomes: non-capturing lambdas and `sorted(key=...)` now work, `dict.items()`
now yields keys, and the step and frame budgets no longer stop honest programs.
The other 105 are unchanged, so the velocity audit's §3 table stands: ternary
expressions, tuples and destructuring, `is None` with narrowing, docstrings,
module-level constants, f-string format specs, `**`, bit operators, `set`,
literal `match` patterns and nested comprehensions all still fail on the first
try. Docstrings matter twice: the API views have no summary field because the
language has nowhere to write one.

### 2.8 Rebuild observability natively

A trap prints a source-mapped stack with structured detail (`R01`, `R02`), an
assert prints its message (`R03`), and `--timings` reports native nanoseconds
(`R04`). That is all. The instruction trace and host transcript left with the
interpreter on 14 September and nothing replaced them: no opt-in call or
dataflow tracing, no arena or allocation statistics from a native run, no
record-and-replay. Replay is cheap to add here because every nondeterministic
input already arrives through a capability value.

### 2.9 Remove surface that competes for the agent's attention

Unchanged since the velocity audit: the lexer still reserves the `f64_*`,
`*_cap`, `codec_*` and resource keywords; eleven subcommands that no development
loop calls share the usage text with `run` and `check`; 144 Python files under
`scripts/` and `tests/` run in no gate; `dump-bytecode` survives without a
bytecode runtime.

## 3. Scorecard

Weights are the guide's. A score of 3 required a representative program, not an
example; the schematic guest and the three-module probe project were the
representative code.

| Category | Weight | Score | Weighted | Evidence and next action |
| --- | ---: | ---: | ---: | --- |
| Local semantic clarity | 10 | 2 | 20 | no inheritance, overloading, conversions, exceptions or closures; two aliasing models under one syntax (`S01`–`S05`). Next: §2.1 |
| Mutation and side-effect visibility | 9 | 2 | 18 | effects and `mutates` inferred and exported (`I10`, `I12`); invisible in source and in `list-interfaces` (`I11`); by-value parameter writes silent (`S03`). Next: §2.1, §2.4 |
| Memory-model simplicity | 10 | 3 | 30 | GC default, lexical arenas, static escape check with fix (`D03`) |
| Escape-hatch locality | 8 | 2 | 16 | arenas local and dynamic-extent; `extern def` scalars only (`D09`), `[N]T` O(N) per access (velocity audit §7). Next: bytes and lists across the C boundary when a workload needs it |
| Type-system predictability | 9 | 2 | 18 | `Option`, `Result`, exhaustive unions (`D04`, `D05`), fixed widths; no tuples or narrowing, internal spellings in messages (`D01`). Next: §2.6, §2.7 |
| Generic and interface resolution | 8 | 2 | 16 | monomorphized, checked universally, contract failures located (`D02`); contracts must be repeated along forwarding chains; no call-site query for the chosen specialization |
| Module and API clarity | 10 | 2 | 20 | explicit exports and privacy (`D17`), cycles rejected (`D19`), compact API view (`P07`); header repeats the path, exports are separate lines, `check` rejects an entry (`P02`). Next: §2.5 |
| Machine-readable dependency graph | 9 | 3 | 27 | `list-modules`, `project-dependencies`, `index-project` (`P08`–`P10`) |
| Change-impact analysis | 8 | 1 | 8 | callers and impact only via a script, only when green (`I06` vs `I08`); no tests-for query. Next: §2.2 |
| Diagnostic quality | 10 | 2 | 20 | located, structured, chained (`D13`–`D19`); no suggestions, fixes or surface spellings (`D01`, `D06`–`D08`, `D11`). Next: §2.6 |
| Incremental build speed and correctness | 10 | 2 | 20 | check warm 0.05 s, one body of 114 on a semantic edit (`T02`–`T04`); warm unchanged build 2.9 s with nothing compiled (`T05`); failing verdicts never cached. Next: §2.3 |
| Test reproduction and affected-test selection | 9 | 2 | 18 | fresh isolated processes, receipts select affected tests (`I04`), `--filter` reproduces one test; no `--affected` or tests-for query; a test that prints is never reused (`I02b`); `export` still required (`P04`) |
| Runtime tracing and observability | 8 | 1 | 8 | trap stacks with structured detail (`R01`–`R03`); nothing else. Next: §2.8 |
| Source token efficiency | 5 | 1 | 5 | bodies are Python-terse; module headers, export lines, a `match` for every `Option`, a record for every multi-value return. Next: §2.5, §2.7 |
| Discovery-context efficiency | 9 | 2 | 18 | `list-interfaces`, `schema-project`, `index-project` snippets; spread over four commands, 20-row caps, no summaries because no docstrings (`P07`, `P10`, `P11`) |
| FFI and unsafe-boundary auditability | 7 | 3 | 21 | `extern def` plus mandatory `effects(host)`, rejected at the declaration (`D09`) |
| Determinism and build reproducibility | 8 | 3 | 24 | content-addressed keys with compiler identity (`P09`), capability-scoped clock, entropy and filesystem |
| **Total** | **147** | | **307 of 441** | **69.6%** |

Minimum score in a critical category: 1 (change-impact analysis). The guide warns
that an average must not hide a zero in module clarity, diagnostics, build
correctness or reproduction; none of those is below 2.

## 4. The decisions the guide asks for

| Decision | Answer today | Evidence |
| --- | --- | --- |
| Is GC unquestionably the default allocation path? | Yes, and the only one. | `docs/managed-memory.md`, `D03` |
| Are lexical arenas sufficient, or is another ownership mode necessary? | Sufficient for the code that exists. No workload has asked for more; the thin spots are the escape hatches, not ownership. | velocity audit §7 |
| Can arena values escape, and how is that diagnosed? | Only through `name.escape(value)`. Statically `E_ARENA_ESCAPE` with the arena, the declaration and the fix; at runtime the `R_ARENA_ESCAPE` write barrier. | `D03`, `D15` |
| Are mutation and side effects visible at API boundaries? | Inferred and exported in `index-project` and `schema-project`; not shown in source or in `list-interfaces`; by-value parameter writes are silent. | `I10`–`I12`, `S03` |
| Are generics and interface resolution deterministic and easy to explain? | Yes: one specialization per argument list, universal checking, no overlapping implementations possible. Contracts must be restated along forwarding chains. | `D02`, `docs/generics.md` |
| Is any macro system necessary before version 1? | No. None exists; compile-time evaluation is bounded to scalar constants. Decided. | `features.json` limits |
| Can the compiler emit the complete module and symbol graph? | Yes, versioned JSON; semantic edges vanish when any body fails to check. | `P08`–`P10`, `I06` |
| Can public interfaces be fingerprinted independently of bodies? | Yes, per declaration and per project. | `P09`, `T03`, `T04` |
| Can affected tests be selected safely? | Yes, by receipts keyed on the dependency closure; there is no explicit query and printing tests are never reused. | `I04`, `I02b` |
| Can an agent reproduce and trace failures with one command sequence? | Reproduce: yes, `mylang test <entry> --filter NAME` is a fresh isolated process. Trace: a trap stack only. | `P04`, `R01` |
| Is there a canonical compressed repository representation? | Partly: four commands with different scopes and caps, no summaries. | `P07`, `P10`, `P11` |
| What is the token and time cost per successful repository change? | Not measured. No matched trial has run. | — |
| Which design choices are supported by measurements versus intuition? | Measured: GC plus arenas covers the schematic application; incremental checking reuses bodies; receipts reuse tests; the 110-probe first-try rate. Intuition: everything about token efficiency and the value of any single diagnostic improvement. | this file |

## 5. Should the surface stay Python-shaped?

The guide puts syntax last and weights it 5 of 147, so this is a small
decision, but it comes up. The evidence in this repository favours keeping the
Python surface:

- **The agent's prior is Python.** All 79 first-try failures in the velocity
  audit's 110 probes were Python idioms the language lacks, not Python idioms
  that misled the agent. A Go or Rust surface would move the prior, and the
  agent would then write `:=`, `nil`, `if err != nil`, `&mut`, `impl … for`,
  `.iter().map()` and closures instead. Rust syntax in particular carries
  semantic expectations (ownership, traits, lifetimes) that this language
  deliberately does not have, so the first-try failure rate would rise, not
  fall.
- **Go-like semantics do not need Go-like syntax.** Everything the guide praises
  in Go is semantic: one obvious construct, no inheritance, explicit errors,
  small interfaces, simple generics. The language already has those under
  indentation and `def`.
- **The cost is not the surface but the places where it lies.** Where the
  language keeps Python's meaning (lists, dicts, `for … in`, comprehensions,
  f-strings, `match`/`case`), the prior helps. Where it silently breaks it
  (`class` copying, §2.1), the prior hurts more than any keyword choice could.
  Rust-shaped constructs that look different — `Result`, `?`, `Option` — are
  fine precisely because they look different: an agent sees `?` and stops
  expecting exceptions.
- **Token cost, unmeasured but directional.** Indentation instead of braces, no
  semicolons and no local annotations make Python one of the terser surfaces
  for current tokenizers; Rust's `::`, `<>`, `&`, `'a` and `|x|` are the
  opposite. This is reasoning, not a measurement, and the guide's Phase 6 is
  the place to measure it.

The recommendation is therefore: stay Python-shaped, make every deliberate
departure either look like Python and behave like it (`class`, tuples,
`is None`) or look visibly different (`Result`, `?`, `with arena()`), and let
the matched Go/Rust/mylang trial the guide calls for settle anything beyond
that.

## Appendix A — probe index

Each row is one entry in the evidence file; the command, working directory, sources and full output are there. `exit` is the child's status: 1 is a check error or trap, 2 a usage or host failure, 3 an empty test selection, and anything else the program's own return.

| Probe | Purpose | Exit | First line of output |
| --- | --- | ---: | --- |
| `D01` | type mismatch: does the message point at the parameter declaration? | 1 | p01_type_mismatch.my:5:19: error[E_TYPE]: expected i64, found str |
| `D02` | missing interface implementation: structural contract not satisfied | 1 | p04_structural_missing.my:7:30: error[E_GENERIC_ARGUMENT]: type lacks a required field with the declared type |
| `D03` | arena value escaping its scope | 1 | p05_arena_escape.my:5:16: error[E_ARENA_ESCAPE]: `values` is assigned to `kept`, which outlives arena `scratch`; assign … |
| `D04` | non-exhaustive match | 1 | p06_nonexhaustive.my:7:5: error[E_INCOMPLETE_MATCH]: match does not handle variant `empty`; every variant requires an ex… |
| `D05` | error not handled: Result dropped | 1 | p07_result_unhandled.my:8:5: error[E_RESULT_UNHANDLED]: result-bearing value leaves scope without being handled, returne… |
| `D06` | unknown function with a one-letter typo: is a candidate suggested? | 1 | p08_unknown_name_typo.my:8:12: error[E_UNKNOWN_FUNCTION]: no function has this qualified name |
| `D07` | unknown field: are the record's fields listed? | 1 | p09_unknown_field.my:7:14: error[E_UNKNOWN_FIELD]: field does not exist on this record type |
| `D08` | arity: are expected and given counts shown? | 1 | p10_arity.my:5:12: error[E_ARITY]: missing required argument |
| `D09` | FFI type mismatch on extern def | 1 | <scratch>/single/p11_ffi_mismatch.my:1:16: error[E_EXTERN_SIGNATURE]: extern signatures support fixed-width integers, bo… |
| `D10` | two errors in two functions: are both reported? | 1 | p13_two_errors.my:2:14: error[E_TYPE]: expected i64, found str |
| `D11` | removed spelling and misspelled method | 1 | p14_wrong_method.my:3:8: error[E_REMOVED_SPELLING]: `push` was removed; use `append(value)` |
| `D12` | read before definite assignment | 1 | p15_unbound.my:4:12: error[E_UNBOUND]: name may be read before it is assigned; some control-flow path reaching here leav… |
| `D13` | effect bound exceeded three calls down: causal chain? | 1 | t03_effect_bound.my:6:20: error[E_EFFECT_BOUND]: effect `managed_allocation` exceeds declared bound: count -> labels; in… |
| `D14` | JSON diagnostics: type mismatch | 1 | {"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_TYPE","severity":"error","message":"expected i64,… |
| `D15` | JSON diagnostics: arena escape with notes | 1 | {"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_ARENA_ESCAPE","severity":"error","message":"`valu… |
| `D16` | JSON diagnostics: two errors as two lines | 1 | {"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_TYPE","severity":"error","message":"expected i64,… |
| `S01` | write through a loop-variable record copy (Python expects 2) | 0 | p02_record_copy_write.my:8:9: warning[W_DEAD_RECORD_WRITE]: field write to a record copy is never read; the binding hold… |
| `S02` | dict.items() binding (Python expects 330) | 74 | 330 |
| `S03` | write through a by-value record parameter (Python expects 2); run | 1 | 1 |
| `S03c` | same program under check: any warning? | 0 |  |
| `S04` | the class spelling has value semantics (Python expects 1) | 0 | t04_class_alias.my:6:5: warning[W_DEAD_RECORD_WRITE]: field write to a record copy is never read; the binding holds a va… |
| `S05` | list mutation through a parameter is invisible at the call site (Python-like, expects 43) | 43 | 43 |
| `R01` | trap three calls deep: source-mapped stack | 1 | t01_trap_deep.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 7, length 3) |
| `R02` | same trap as JSON with structured detail | 1 | {"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"R_LIST_BOUNDS","severity":"error","message":"native… |
| `R03` | assert with a message | 1 | t02_assert.my:2:12: error[R_ASSERT]: native execution failed: n must exceed ten |
| `R04` | --timings on a run | 1 | t02_assert.my:2:12: error[R_ASSERT]: native execution failed: n must exceed ten |
| `P01` | run a project entry (exports carry no effect ceilings) | 42 | 12 |
| `P02` | single-file check on a project entry | 1 | main.my:1:1: error[E_SYNTAX]: unexpected token; expected def |
| `P03` | check-project | 0 |  |
| `P04` | test from the entry: print inside a test, expected/got, unexported test_area not discovere… | 1 | failed util::test_prints: expected true, got false |
| `P05` | test with a library module as the entry | 1 | failed util::test_prints: expected true, got false |
| `P06` | directory test run discovers project roots | 1 | failed util::test_prints: expected true, got false |
| `P07` | compact API view | 0 | module interfaces v1; declarations/signature visibility checked; bodies not type checked |
| `P08` | module graph with hashes | 0 | module graph v1; header discovery only; bodies/exports/types not checked |
| `P09` | dependency report with per-declaration interface and body identities | 0 | {"version":"project-dependencies-v1","complete":true,"entry":"main","policy":null,"implementation":{"compiler_sha256":"4… |
| `P10` | navigation index: symbols with effects, mutates, return origin, call and read edges | 0 | {"version":"navigation-v1","checked":true,"reference_scope":"resolved concrete bodies and specializations; generic decla… |
| `P11` | exported contracts with types | 0 | {"version":"language-schema-v1","scope":"reachable-module-exports","representation":"language-contracts-no-wire-format-o… |
| `P12` | parse-only declaration listing with byte ranges | 0 | {"version":"declarations-v1","module":"util","header":{"start":0,"end":11},"imports":[],"exports":[{"name":"twice","byte… |
| `D17` | invalid cross-module visibility (text) | 1 | main.my:5:12: error[E_PRIVATE_SYMBOL]: declaration is private to its module |
| `D18` | invalid cross-module visibility (JSON) | 1 | {"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_PRIVATE_SYMBOL","severity":"error","message":"dec… |
| `D19` | import cycle | 1 | b.my:2:8: error[E_IMPORT_CYCLE]: a -> b -> a |
| `I01` | warm unchanged check-project work report | 0 | {"version":"frontend-cache-v1","syntax_hits":0,"syntax_misses":0,"syntax_stored":0,"verdict_hits":1,"verdict_misses":0,"… |
| `I02` | baseline directory test run | 0 | passed shared.geometry::test_area |
| `I02b` | second unchanged directory test run: which tests are reused? | 0 | cached shared.geometry::test_area |
| `I03` | body-only edit of the unexported helper `hidden`: work report and invalidation explanation | 0 | {"version":"invalidation-report-v1","hits":0,"misses":6,"skipped":3,"queries":[{"stage":"load_source","status":"miss","k… |
| `I04` | directory test run after the body-only edit: test_area reused, dependents only | 0 | cached shared.geometry::test_area |
| `I05` | interface edit (area gains a parameter): dependents fail, invalidation names the interface | 1 | main.my:6:11: error[E_ARITY]: missing required argument |
| `I06` | callers of area while the project is red | 0 | {"version": "navigation-query-v1", "checked": false, "snapshot_sha256": "0c2924fdb27bee1cc17ecb9f42854d93b7773c13e84f525… |
| `I07` | revert the interface edit and add an exported record plus two unannotated mutating helpers | 0 |  |
| `I08` | callers of area on a green project | 0 | {"version": "navigation-query-v1", "checked": true, "snapshot_sha256": "00d3e7f99f7b8b9475fc94d69ab5f3332342842309e29800… |
| `I09` | impact of area on a green project | 0 | {"version": "navigation-query-v1", "checked": true, "snapshot_sha256": "00d3e7f99f7b8b9475fc94d69ab5f3332342842309e29800… |
| `I10` | index-project: inferred mutation facts for the unannotated helpers | 0 | {"version":"navigation-v1","checked":true,"reference_scope":"resolved concrete bodies and specializations; generic decla… |
| `I11` | list-interfaces: does the compact view show effects or mutation? | 0 | module interfaces v1; declarations/signature visibility checked; bodies not type checked |
| `I12` | schema-project: record fields and inferred mutates | 0 | {"version":"language-schema-v1","scope":"reachable-module-exports","representation":"language-contracts-no-wire-format-o… |

## Appendix B — timing series

Wall-clock seconds around the child process, three samples unless noted; load average 2.1 at the start and 2.5 at the end.

| Series | Purpose | Samples (s) | Report |
| --- | --- | --- | --- |
| `T01` | cold check-project of the schematic guest (14 modules, 2186 lines), fresh cache | 0.259 |  |
| `T02` | warm unchanged check-project | 0.05, 0.056, 0.053 |  |
| `T03` | comment-only edit to circuit.my then check-project with work report | 0.169, 0.176, 0.181 | "checked_bodies":{"status":"hit","performed":0,"reused":114} |
| `T04` | semantic one-line edit (new statement) in circuit.my then check-project with work report | 0.186, 0.169, 0.186 | "checked_bodies":{"status":"miss","performed":1,"reused":113} |
| `T05` | warm unchanged native build of the schematic guest with its qbe-build report | 2.935, 2.953, 3.043 | {"compiled_functions": 0, "reused_functions": 115, "runtime_reused": true, "frontend_seconds": 2.323877805, "codegen_seconds": 0.630793174, … |
| `T06` | warm unchanged `run` of the schematic guest (exits 2: it wants arguments; the cost is the build) | 3.939, 2.698, 2.693 |  |
| `T07` | warm unchanged native build of the single-file examples/factorial.my | 0.084, 0.084, 0.098 | {"compiled_functions": 0, "reused_functions": 2, "runtime_reused": true, "frontend_seconds": 0.036694197, "codegen_seconds": 0.003987355, "l… |
| `T08` | warm unchanged native build of the three-module examples/modules/main.my | 0.097, 0.096, 0.084 | {"compiled_functions": 0, "reused_functions": 4, "runtime_reused": true, "frontend_seconds": 0.026676617, "codegen_seconds": 0.005156258, "l… |
| `T09` | warm unchanged check of a 20-line single file | 0.019, 0.03, 0.019 |  |

## Appendix C — rerun of the velocity audit's idiom probes

All 110 programs from `agent-velocity-2026-09-17-probes.json` were rerun with `mylang run FILE --print-result` on this binary. 105 kept their exit status. The 5 that changed:

| Probe | Exit before | Exit now | Output |
| --- | ---: | ---: | --- |
| `a15_lambda_nocapture.my` | 1 | 42 | 42 |
| `a20_dict_items.my` | 45 | 74 | 330 |
| `a27_sorted_key.my` | 1 | 42 | 42 |
| `e01_step_budget.my` | 1 | 21 | 21 |
| `e07_recursion_depth.my` | 1 | 0 | 0 |
