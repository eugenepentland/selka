# Making mylang more useful to coding agents

Status: **implementation plan, partly executed**. Prepared 2026-09-20 from
repository inspection and a small installed-compiler probe. Packages W0, S1,
D1, D2, L1, M1 and the lane C scorer were implemented in the working tree the
same day; their status, measured numbers, deviations and open build items are
in [`agent-usefulness-reports/ledger.md`](agent-usefulness-reports/ledger.md),
which outranks any status implied by the package text below.

## 1. Outcome

Make it easier for an agent to understand an unfamiliar project, implement a
bounded change, and establish that the resulting behavior is correct. Also make
mylang a practical language for the small reusable tools an agent creates while
working on other projects.

Deliver five improvements:

1. Dependable, bounded context for a symbol, source location, or diagnostic.
2. Native invocation of an exported function using structured inputs and outputs.
3. Typed-hole reports that describe the implementation obligation precisely.
4. Measured improvements to the complete read/edit/check/test loop.
5. Fewer repair rounds on first-try code: every call-site rejection names the
   callee's signature and the accepted alternative, the parser explains the
   declaration forms that differ from Python, and the small surface gaps a
   script hits first are closed.

The guiding design principle is to expose facts the compiler already knows,
with their provenance and limitations. Keep ordinary source files, the current
language semantics, and existing verification infrastructure.

## 2. Starting point

These are starting observations, not a substitute for checking the selected
implementation baseline. The inspected working tree contains substantial ongoing
changes; a Git revision alone does not identify its contents.

| Area | Existing foundation | Work proposed here |
| --- | --- | --- |
| Navigation | `index-project`, `list-interfaces`, `tests-for`, `api-diff`, and `scripts/navigate.py` | Compose focused answers with consistent fact status, bounded output, and freshness checks. |
| Project feedback | `scripts/project.py` combines navigation and declared verification; the declaration-store experiment has bounded context queries | Reuse these mechanisms in the ordinary file workflow; no mandatory source database. |
| Documentation | `--features`, checked schemas, embedded standard modules, executable documentation | Provide one current, compiler-pinned entry point and remove misleading current-to-historical routing. |
| Function execution | Native guest tests validate typed inputs, select reachable code, and execute in bounded child processes | Generalize the invocation machinery to ordinary public exports, then add a practical copied managed-value boundary. |
| Unfinished code | `todo[T]()` blocks publication; declaration inspection remains possible | Retain and expose the local facts needed to fill a hole. |
| Incrementality | Persistent checked-body/native caches, selective tests, receipts, and phase/work reports | Measure complete maintenance tasks and optimize the dominant remaining work. |

The review probe used compiler identity
`7d3d52d755a44aa7f8dc73a2792d223b6f6ccb408aced4b2130061cd8c05c79a`.
A module containing `todo[int]()` produced `E_TYPED_HOLE`, while
`list-interfaces` succeeded and printed declarations. Its incomplete bodies also
caused interfaces to display the full effect vocabulary alongside `ceiling()`.
This motivates distinguishing an unknown inferred effect set from a declared
ceiling; it does not establish a soundness defect in effect checking.

The README's compiler-derived-reference link leads to a historical page whose
Python generator was removed. Current capability discovery should not require
reconciling that history. The [typed JSON guide](../typed-json.md) also explicitly
records that arbitrary exported-function invocation was removed with the
interpreter; the current execution route is through native tests.

Relevant foundations:

- [Navigation](../tooling/navigation.md), [project feedback](../experiments/project-workflow.md), and [store sessions](../experiments/declaration-store-session.md).
- [Typed JSON](../typed-json.md), [guest tests](../tooling/guest-tests.md), and [effects](../effects.md).
- [Typed holes](../typed-holes.md) and [diagnostic recovery](../diagnostic-recovery.md).
- [Caches](../tooling/caches.md) and [previous velocity implementation status](velocity-implementation/final-status.md).

### Session probe, 2026-09-20

An agent session on the installed `zig-out/bin/mylang` (built 2026-09-20 13:37,
working tree dirty) wrote four small first-try programs, ran the S-expression
port's guest tests and timed a hot loop against CPython. The loop was never the
bottleneck:

| Action | Wall time |
| --- | --- |
| `check` on a 25-line single file | 80 ms |
| `run` on it (native build plus execution) | 414 ms |
| `mylang test experiments/sexpr-port/tests`, 114 tests across 7 programs | 4.0 s |
| Sieve to 5,000,000, `mylang build` output | 0.15 s |
| Same sieve under CPython 3.14 | 0.50 s |

Every repair round the session paid came from a Python habit meeting a small
surface difference, and every fix was one line:

| First-try spelling | What the compiler said | Turns lost |
| --- | --- | --- |
| `text.split()` | `E_ARITY: list method argument count does not match its signature`; the receiver is a `str` and no signature is shown | 1 |
| `union` cases on separate lines without commas | `E_SYNTAX: unexpected token; expected a dedent` at the second case | 1 |
| `import strings` at the top of a headerless script | `E_MODULE_HEADER: file must begin with a module declaration` | 1 |
| `b == strings.ord("m")` | `E_TYPE: expected int, found Result[int, strings.Error]`; the port's tokenizer and parser carry 33 comparisons against raw byte codes such as `109` for this reason | 1 |
| `lambda w: -counts[w]` | `E_LAMBDA_CAPTURE` naming the fix (top-level function with an explicit state parameter) | 0 |
| unused `x: int = 0` | `W_UNUSED_BINDING` naming the `_ =` idiom | 0 |

The two rejections that carried their fix cost nothing; the four that did not
cost a turn each. `mylang lint --profile=agent` on the port reported ten
`L_UNTESTED_EXPORT` findings on `sexpr/ast.my` accessors that every parser test
reaches transitively, because the rule counts only direct callees of `test_`
functions. The idiom suite already holds probes for the first two gaps
(`a64_split_noargs.my`, `a55_chr_ord_hex.my`; both `mylang_accepts: false` in the
17 September baseline), lane C3 of [`velocity/goal.json`](../../velocity/goal.json)
already counts "rejections naming the alternative or carrying a fix" (baseline
0.02, target 0.95), and [`velocity/friction/classifier.json`](../../velocity/friction/classifier.json)
already maps diagnostic code plus source regex to an idiom name. The packages
below reuse all three rather than adding instruments.

## 3. Scope and implementation rules

- Extend the existing checker, semantic index, native build path, and native
  execution machinery. No second frontend, interpreter, or independently inferred
  semantic graph.
- Keep QBE as the required implementation route for these features. An optional
  backend experiment is not a prerequisite or a reason to change language rules.
- Context queries are read-only. They never execute tests, edit source, apply a
  suggested fix, or infer that reachable tests establish behavioral coverage.
- Preserve current checked-result, effect, mutation, nominal-identity, and
  capability rules. Reporting incomplete information must not weaken checking.
- Preserve unrelated working-tree changes. Establish a content-pinned baseline
  before implementation, and use an isolated checkout/build directory when needed.
- Proposed command spellings below are design defaults. Freeze their exact
  contracts in W0 before implementation and document any adjustment once.
- Do not add an MCP server, mandatory daemon, source-store migration, editor
  integration, or broad package ecosystem as a dependency of the first release.
- Do not make automatic repair suggestions or an architecture score part of the
  initial treatment. Evaluate them separately if later evidence justifies them.

## 4. Release sequence

Size is relative implementation scope, not a calendar estimate.

| Package | Deliverable | Depends on | Size |
| --- | --- | --- | --- |
| W0 | Verified baseline, protocol decisions, and runnable task pack | — | Small |
| D1 | Call-site rejections print the callee's signature and the alternative | W0 | Small |
| D2 | Parser hints for declaration forms that differ from Python | W0 | Small |
| S1 | Close the first-try surface gaps a script hits first (`split()`, `ord`/`chr`, headerless imports) | W0 | Small |
| L1 | Untested-export lint counts test reachability, not direct calls | W0 | Small |
| M1 | Opt-in friction log on ordinary commands, folded into repair rounds per diagnostic | W0 | Small |
| F1 | Honest interface facts and current agent reference | W0 | Medium |
| C1 | Focused context command over existing compiler facts | F1 | Medium |
| I1 | Native invocation for the existing copied-value subset | W0, F1 | Medium |
| I2 | Managed data needed by useful tools | I1 | Large |
| I3 | Explicit capability provisioning for invocation | I1 | Medium |
| H1 | Structured typed-hole obligations and context integration | F1, C1 | Medium |
| E1 | Maintenance and tool-authoring comparisons | W0; each measured package | Medium |
| P1 | Targeted latency improvements selected by measurements | E1 profiling | Variable |

Recommended execution order: W0 → S1 → D1 → D2 → L1 → M1 → F1 → C1 → I1 → I2
→ H1 → I3. The five small packages go first because each is bounded to one or
two source files, each removes a repair round from every session that hits it,
and each is scored by an instrument that already exists (lane C of the idiom
suite, the port's lint finding count, the friction log itself), so their
verdicts arrive without waiting for the E1 cohorts. I1 is the largest missing
capability and follows as soon as F1's interface facts are honest. Capture
measurements throughout; start P1 when profiling identifies a concrete target.
Each package has its own correctness acceptance and can land independently of a
productivity claim. The useful-tool milestone requires I2; a scalar-only I1 is
infrastructure, not completion of that outcome.

### W0 — Establish the baseline and shared contracts

1. Capture selected source contents, existing modifications, compiler identity,
   toolchain/backend identities, mode, and relevant environment. Use the
   repository's pinned Zig toolchain; do not update it as part of this work.
2. Reproduce the incomplete-interface probe, typed-hole diagnostics, current
   navigation limits, and the actual native copied-value codec matrix. Mark
   already-fixed observations as such rather than reimplementing historical gaps.
3. Preflight two current applications and their independent acceptance checks.
   Prefer the S-expression port and a second application that works with this
   exact compiler. The M3 planner snapshot was blocked by obsolete syntax;
   select a compatible snapshot or another application before spending on trials.
4. Record baseline command timings and a few complete maintenance sessions.
   Preserve raw command events and output sizes, including unsuccessful attempts.
5. Freeze versions, required fields, exit statuses, size limits, and compatibility
   rules for the reference, context, invocation, and hole reports. Freeze the
   copied-value matrix separately from the host/native ABI.
6. Create an implementation ledger beside this plan with package status, source
   identity, evidence paths, and any deviations. Creating that ledger belongs to
   implementation; this planning task does not manufacture acceptance evidence.

**Acceptance:** both application baselines pass; the focused observations are
reproducible; protocol decisions and unsupported cases are explicit. No agent
productivity experiment begins against a nonworking baseline.

W0 also freezes three small decisions the repair-round packages need. All three
were taken on 2026-09-20 and are recorded in the ledger: a prelude `ord`/`chr`
**traps** `R_TEXT_SCALAR` on input that is not exactly one scalar (the user's
call; `Option` was the rejected alternative), diagnostic notes gain an optional
`role` inside `diagnostic-v1` with no `diagnostic-v2`, and the friction-log
record shape is pinned by the `friction_log.zig` unit test.

### D1 — Every call-site rejection prints the callee's signature and the alternative

**Entry points:** `src/sema.zig` (the `E_ARITY` sites near lines 1473 and 1488,
`E_LIST_METHOD` and `unknownMethodMessage`, argument `E_TYPE` at calls),
`src/buffer_operations.zig` (method vocabulary and arity), `src/removed_names.zig`,
`src/interfaces.zig` (existing signature rendering), `src/diagnostic.zig`, and
`src/diagnostic_output.zig`.

Today `"a b".split()` reports a list-method arity error with no signature. The
checker knows the receiver type, the method's checked signature and, through
`removed_names.zig`, which Python spellings are deliberately not accepted. Say
all three:

- Every `E_ARITY`, unknown-method and argument-position `E_TYPE` diagnostic at a
  call names the receiver type and renders the callee's signature exactly as
  `list-interfaces` prints it, through one shared renderer so the two can never
  disagree: `str.split(separator: str) -> list[str]`.
- When the rejected spelling matches a Python form the language does not accept
  (no-argument `split`, `sorted(..., key=lambda ...)` with a capture, `**`,
  `set`, tuples), attach a note whose role is `alternative` naming the accepted
  spelling, or a `fix` edit when the repair is mechanical. This is the field
  lane C3 already counts.
- Never describe a `str`, `bytes`, `byte_buffer` or `dict` receiver as a "list
  method"; the family is known at the failure site.

Keep the first-fault-per-function rule and every existing code. Do not add
heuristic repair prose for unknown cases; a rejection with no known alternative
prints the signature and stops.

**Acceptance:** every call-site rejection in `velocity/suites/idioms/` carries
the callee signature; `a64_split_noargs.my`'s rejection names `split(separator)`
and the whitespace alternative; the C3 score over the suite moves from 0.02 to
above 0.5 on this package alone (D2 and S1 take it further); diagnostics for
unaffected codes are byte-identical in text and JSON; each new behavioral line
has its `// spec:` tag and `SPEC.md` bullet.

### D2 — Parser hints for the declaration forms that differ from Python

**Entry points:** `src/parser.zig` (`expect` near line 104 builds
"unexpected token; expected <spelling>"; the enum/union case loop near lines
527–541 breaks on a missing comma and then fails on `expect(.dedent)`),
`velocity/friction/classifier.json`.

A `union` whose cases sit on separate lines without commas is the shape an
agent writes first, and the parser answers "expected a dedent" at the second
case. The parser knows it is inside a union body and that the offending token
is an identifier at the case column. Report `E_SYNTAX` with "union cases are
separated by commas" and a `fix` note inserting the comma after the previous
case. Apply the same treatment to the other declaration bodies whose syntax
departs from Python and already have idiom probes: a bare module-level
assignment such as `MAX = 42`, which fails with "expected def" and whose
accepted form is `const MAX: int = 42` (`a37_const.my`); a `def` inside a
`class` body, which fails with "expected a name" and whose alternative is a
top-level function taking the record (`a38_class_methods.my`); and
`from module import name`, which fails with "expected def" before the
`@dataclass` line is reached and whose accepted forms are `import module` and a
`record` declaration (`a39_dataclass.my`). Keep the list of hinted forms in the
friction classifier so the suite's classification and the parser's hints are one
table; a form present in one and absent from the other is a test failure.

This is targeted messaging at known failure points, not general error
recovery. The parser still stops at the first syntax error.

**Acceptance:** the listed probes reject with a note naming the accepted form;
existing `E_SYNTAX` tests keep their code and span; the classifier and the hint
table agree under a unit test; spec tags and `SPEC.md` bullets for each hint.

### S1 — Close the first-try surface gaps a script hits first

Three independently landable items, each with an existing probe or a measured
cost. Land them in this order.

**(a) `str.split()` with no argument.** Python semantics: split on runs of
whitespace and drop empty parts. Entry points: `src/buffer_operations.zig`
(arity table), `src/native_text_methods.c` and `src/qbe_text.zig` (the runtime
path `splitlines()` already uses), `docs/text.md`. Probe `a64_split_noargs.my`,
oracle CPython. Acceptance: the probe agrees with CPython on stdout and exit
status; `split(separator)` is unchanged; a doc example runs under `doctest`.

**(b) Prelude `ord` and `chr` with literal folding.** The `strings` module keeps
its `Result` forms. Add prelude `ord(text: str) -> int` and `chr(code: int) -> str`,
where `ord` of a one-scalar string literal folds at check time to an `int`
constant usable in comparisons, `case` arms and `const` initializers, and the
runtime form traps `R_TEXT_SCALAR` on text that is not exactly one scalar (the
W0 decision, taken 2026-09-20; the same trap `chr` raises on an invalid code
point). Entry points: `src/prelude_builtins.zig` (the ledger corrects the
original `src/prelude.zig`, which holds the canonical constructors),
`src/sema.zig` (the scalar-constant folder the `const` rule uses),
`src/stdlib/strings.my` (unchanged), `docs/text.md`. Probe
`a55_chr_ord_hex.my`. Evidence of cost: the port's tokenizer and parser compare
against raw byte codes with comments explaining which letter each means; a
narrow `== NNN` count gives 33, and the ledger's fuller count is 63, 29 of
them letter codes. Acceptance: `b == ord("m")` checks and
lowers to an immediate compare with no allocation and no call; the probe agrees
with CPython for `ord` and `chr` (`hex` is out of scope); rewriting the port's
33 comparisons to `ord("x")` produces byte-identical QBE for those functions.

**(c) A headerless script may import standard modules.** `src/parser.zig:325`
requires `module` whenever the first token is not `module`, so a script whose
first line is `import strings` fails with `E_MODULE_HEADER`. Let a file with no
`module` header import embedded standard modules and stay a single-unit
program; importing a project module still requires the header and still reports
`E_MODULE_HEADER`. Entry points: `src/parser.zig:325`, `src/project.zig`
(lines 300–308), the `run` entry rule in `src/main.zig`, `docs/modules.md`
(the single-file rule near line 242). Acceptance: the session's `probe4.my`
shape checks and runs; a headerless file importing a project module keeps its
current diagnostic; the module-graph commands are unaffected.

### L1 — Untested-export lint counts test reachability

**Entry points:** `src/lint.zig` (`runUntestedExport`, which marks only the
direct callees of discovered tests), `src/tests_index.zig` (`Index.reached`,
the direct-and-transitive answer `tests-for` already returns).

On the S-expression port the agent profile reports ten untested-export findings
on `sexpr/ast.my` accessors that every parser test reaches. A lint an agent
learns to ignore is worse than none. Build the rule on the shared reachability
index so `lint` and `tests-for` cannot disagree: under `--profile=agent` an
export reached by any test, directly or transitively, is tested. Keep the
direct-call rule available under `--profile=strict` with a message that says
"reached only transitively" rather than "not called", so the two profiles report
different facts rather than the same fact at different thresholds.

**Acceptance:** the port under the agent profile reports zero untested-export
findings for reached accessors and still reports a genuinely unreached export;
`tests-for` and the lint agree on every export of both real applications by
construction; the strict profile's findings carry the transitive-only wording;
existing lint tests and the `--gate` exit status are unchanged for reports that
do not involve reachability.

### M1 — Harvest friction from real sessions

**Entry points:** `src/main.zig` (`checkSession` and the one-shot `check`,
`run`, `test` commands), `velocity/friction/classifier.json`,
`velocity/backlog.json` item V2.

The velocity loop plans to measure repair rounds (A3) from solver sessions
against a task pack that does not exist yet. Every real session already
produces the same signal. Add an opt-in `MYLANG_FRICTION_LOG=PATH`
(`--friction-log=PATH` on the same commands) that appends one JSON line per
command: compiler identity, command, file path as given, source snapshot hash,
each diagnostic's code and span, exit status, and wall time. No source text, no
environment values, no absolute paths beyond what the user passed. Off by
default, and never read by the compiler.

Add `velocity/friction/harvest.py`, which folds a log into repair rounds: a
diagnostic code on a file followed, within the next few records for that file,
by a passing check is one round attributed to that code, and the existing
classifier names the idiom. Output is repair rounds per code and per idiom,
which is the ranking input for D1, D2 and S1 and the A3 value the loop wants,
from every session rather than a nightly run.

**Acceptance:** a unit test pins the record shape; the log is absent unless
requested; a replayed log of the 2026-09-20 session yields four rounds
(`E_ARITY` split, `E_SYNTAX` union comma, `E_MODULE_HEADER`, `E_TYPE` ord) and
attributes zero to `E_LAMBDA_CAPTURE` and `W_UNUSED_BINDING`; the harvest
script is documented beside the classifier; the record contains no secret and
no source text, checked by a test that logs a session over a file containing a
sentinel string and asserts the sentinel never appears in the log.

### F1 — Make compiler facts unambiguous and current

**Entry points:** `src/interfaces.zig`, `src/main.zig`, `src/navigation.zig`,
`src/schema_report.zig`, `src/features.json`, and `src/standard_library.zig`.

Separate three concepts everywhere they are reported:

- A declared ceiling: present or absent in source.
- An inferred effect or mutation summary: known only when the necessary checking
  completed successfully.
- Analysis status: checked, declaration-only, lexical-only, or unavailable, with
  the reason when unavailable.

Keep conservative internal masks if they are needed for checking. Render them as
unknown or conservative bounds when appropriate; never label an internal
fallback as an inferred fact. In particular, an empty declared ceiling remains
visible when a body contains a hole, while the inferred set is unavailable.
Apply the same distinction to return origins and test relationships.

Add a small compiler-derived reference entry point, provisionally
`mylang reference --query TERM --format=text|json`. It should expose current
syntax examples, builtins, embedded standard-library signatures, supported
boundaries, and relevant exclusions. Derive signatures and feature status from
the selected executable. Keep explanatory prose curated, versioned, and shipped
with that executable; execute its examples in the documentation gate. The command
must work outside the source checkout.

Route README/current-guide onboarding to this current surface. Mark historical
pages consistently and retain their evidence. This is a focused correction of
current entry points, not a rewrite of every experiment report.

**Acceptance:** incomplete and complete modules render distinguishable facts;
JSON uses explicit status/null fields rather than an empty set for unknowns;
existing checked contracts remain unchanged; reference examples match the
selected binary even when the surrounding checkout differs. Add feature pointers
and executable documentation with the implementation.

### C1 — Answer a focused change-context question

Proposed usage:

```sh
mylang context app/main.my --symbol 'model::validate' --context-bytes=8192
mylang context app/main.my --at 'model.my:42:12' --format=json
mylang context app/main.my --symbol 'model::validate' --against=api-baseline.json
```

The command composes existing navigation, interface, test-reachability, and API
comparison logic. Share implementations with existing commands; do not spawn a
full frontend independently for every section. Prototype selection/rendering
against the existing client if useful, then expose the maintained command through
the installed toolchain without requiring the repository's Python scripts.

Return, in deterministic priority order:

1. The requested declaration or diagnostic, its source span and relevant body.
2. Its signature, declared bounds, checked effects, mutation footprint, and
   return-origin information, each with fact status.
3. Definitions of directly relevant nominal types and generic requirements.
4. Resolved direct dependencies and caller signatures.
5. Direct and transitive test callers, labeled as static reachability.
6. Interface changes when the caller supplies an existing API baseline.

Support locating a diagnostic through its source span in the same source
snapshot. Report ambiguity instead of silently choosing a similarly named symbol.
For incomplete projects, return available declarations/local facts and the reason
resolved relationships are unavailable. Never reuse old checked edges as though
they described the current broken source.

The `agent-context-v1` envelope includes compiler/source identities, selector,
analysis status, section records, emitted byte count, and omissions by section.
Define the budget over the complete serialized response, including JSON escaping
and metadata. Use an 8 KiB default and a documented minimum large enough for the
envelope; retain complete records and valid UTF-8. If the requested declaration
does not fit, return its signature/location and an explicit continuation query.
Do not silently truncate a contract into a misleading fragment.

Use source identities and existing invalidation mechanisms for caching. Detect a
source change while assembling the response and return a stale-snapshot result;
do not combine facts from different versions. Keep the first version one-shot;
consider persistent service reuse only after measuring its contribution.

**Acceptance:** useful answers on both real applications; exact budget adherence;
deterministic ordering; ambiguous and missing selectors handled; partial-source
facts labeled; private helper edits invalidate relevant answers; source changes
during collection reject. Existing navigation/test semantics remain unchanged.

### I1 — Invoke an ordinary export through the native runtime

Proposed usage:

```sh
mylang invoke app/main.my --function 'app::normalize' --describe --format=json
mylang invoke app/main.my --function 'app::normalize' --input=request.json
```

`--describe` returns the selected function's checked argument/result contract,
wire representation, effects, required capabilities, limits, and invocation
eligibility. A checked signature is not necessarily serializable: explain the
first unsupported type path rather than advertising an unusable callable tool.
An optional generated JSON Schema describes the supported wire subset, including
decimal-string integers; it must not be confused with the language-contract graph.

Extract reusable invocation components from `native_test_execute.zig`,
`native_test_wire.zig`, `native_test_session.zig`, and the existing QBE
build/codec modules. Preserve the native test runner's behavior and receipts.
Select an exported concrete function without a `test_` prefix or expected-value
fixture. An exported concrete wrapper is the initial route for generic functions.
Support a library entry without requiring the user to add a dummy `main`.

I1 starts with the existing verified copied-value subset. Describe exactly which
types work at W0, and reject all others before executing guest code. Use named
arguments checked against the selected signature; reject missing, extra, duplicate,
or malformed inputs. Reuse the exact-integer representation and nominal identity
validation from the existing boundary.

Execute in a fresh native child with bounded input/output, wall time, memory, and
the existing execution quotas. Initially accept only exports whose effects and
signature need no external authority. Managed allocation and permitted mutation
of copied inputs do not themselves require an external grant.

Write one `native-invocation-v1` JSON response on stdout. Keep compiler diagnostics
and captured guest output separate from that channel. Distinguish a returned
language `Result.Err` from a runtime trap, timeout, invalid request, and host/setup
failure. A returned `Err` is a completed invocation and remains a typed result;
define exit 0 for completed calls, 1 for source/runtime failure, and 2 for
request/setup failure. Include source/compiler/schema identities and effective
limits in the response/report.

Reuse compilation artifacts, but execute every requested invocation. Do not
reuse cached test successes as function results, automatically retry a call, or
claim that process isolation constrains arbitrary trusted foreign code. Publish
the result only after validating the complete child response. Result publication
does not imply rollback of external side effects in later capability-enabled calls.

**Acceptance:** invoke a non-test public function without modifying it; validate
integer boundaries and nested values; distinguish `Err`, traps, and timeout;
reject private/unknown/generic-uninstantiated targets and unsupported type paths;
retain source-mapped failures; keep stdout parseable; preserve existing tests;
repeated calls execute while unchanged native artifacts are reused.

### I2 — Add useful copied managed values

Add support in this order: immutable `str`, `list[T]`, then combinations with
value records, `Option`, and `Result`. Support compositions according to the
verified language storage rules; do not silently relax must-handle restrictions
to accommodate a codec. Existing scalar and fixed-shape encodings remain stable.
Make `bytes` and `dict[str,T]` separate follow-ups when a concrete tool requires
them; specify their wire encodings before implementation.

This is a copied serialization boundary, not permission to pass arbitrary managed
objects through the C ABI. Decode into fresh guest-owned storage, retain every
temporary GC root, copy the result out before teardown, and release partial values
on failure. Input JSON describes value trees and introduces no shared aliases.
Repeated acyclic output references serialize as repeated values; cyclic output
fails with a located/type-path error. Bound expanded output size and traversal
work, not only the number of distinct heap objects.

Validate Unicode and embedded NUL handling, collection lengths, nesting depth,
total nodes/bytes, allocation failures, and integer ranges. Reject classes,
capabilities, resources, callbacks, and private-domain construction until an
explicit corresponding boundary contract exists. Version capability/schema
metadata and native codec cache keys when supported shapes change. Audit both
the parent codec and native runtime path; host-side validation alone is insufficient.

Deliver two small examples that use the invocation route without handwritten
JSON plumbing: a structured-record validator returning useful errors, and a
text/list transformation returning a typed report. Give them independent expected
results and document how an agent discovers their contracts and calls them.

**Acceptance:** nested Unicode/list/record/result round trips; empty and large
bounded values; no leaked references across repeated calls; `--gc-stress` and
allocation-failure coverage; malformed/cyclic/oversized cases reject cleanly;
both examples work through the public CLI. Record preparation and per-call cost.

### I3 — Supply capabilities explicitly

Reuse the existing grant resolution and capability runtime rather than adding a
new authority system. For `invoke`, make no external grants the default, and
document this difference from ordinary `run`. Missing required grants reject
before execution. Describe capability parameters separately from JSON data
parameters; JSON can never mint them.

The generated entry shim provisions declared capabilities, preserving the rule
that only an entry shim constructs them. Stage support by capability kind;
initial filesystem/stream grants are sufficient for a first useful slice. Keep
unsupported kinds explicit. Integrate existing restrictions for later network,
environment, clock, and entropy support rather than inventing parallel rules.
Host calls remain subject to their existing registration/trust contract.

**Acceptance:** a fixture reader can access its granted directory, denied access
fails, capabilities cannot arrive in JSON or escape in a result, guest printing
cannot corrupt the result channel, and effective grants are recorded without
serializing environment values or other secrets into receipts.

### H1 — Expose the obligation at a typed hole

**Entry points:** `src/sema.zig`, `src/generic_bodies.zig`, `src/diagnostic.zig`,
`src/diagnostic_output.zig`, and `src/typed_holes_test.zig`.

Retain a bounded context snapshot when ordinary or symbolic generic checking
reaches a valid `todo[T]()`. It contains the declared result type, enclosing
callable, available initialized bindings and types, generic requirements,
declared effect ceiling, and permitted mutation footprint. Include a contextual
expected type only when the checker actually knows it; expected-type inference
is not a new language feature in this package.

Copy the necessary facts into storage with a defined diagnostic lifetime before
failed-function recovery clears checker state. Preserve source locations and
nominal identities. Mark unavailable facts explicitly, especially transitive
effect summaries that require successful whole-program checking. Never expose
uninitialized, consumed, or out-of-scope bindings as usable inputs.

Keep the default error concise and the stable `E_TYPED_HOLE` code. Expose details
as a versioned structured obligation or through `context --at`; larger snapshots
may be collected on request to bound ordinary-check overhead. Associate an
obligation with function identity, source range, and snapshot identity. Old line
numbers alone must not identify a hole after edits.

An on-demand relevant-function list may use exact type relationships and checked
effect compatibility. Label declarations whose bodies are unverified. Defer
implementation synthesis and heuristic repair prose; source semantics and the
requirement to resolve holes before publication remain unchanged.

**Acceptance:** ordinary and uncalled generic holes expose correct local facts;
separate invalid functions retain independent diagnostics; incomplete global
facts stay unknown; formatting preserves holes; filling a hole removes its
obligation; stale queries reject. Do not promise recovery for multiple holes in
one function beyond the checker's existing safe recovery boundaries. Production
builds continue to reject all holes in their selected program.

## 5. E1 — Evaluate complete work

Use the existing velocity/project-invocation infrastructure and independent
application oracles. Preserve historical cohorts. The
[M1b readout](m1b-diagnostic-feedback-readout-2026-09-19.md) did not establish a
repair benefit from suggestions, and the
[elegance findings](../../experiments/elegance-metrics/findings-2026-09-19.md)
did not validate dependency-graph propagation cost as a proxy for agent effort.
Treat both as reasons to measure direct outcomes.

Prepare distinct development and held-out tasks in three families:

| Family | Example | Primary comparison |
| --- | --- | --- |
| Maintenance | Repair a parser edge case or change a validation rule across modules | Existing workflow vs focused context, with identical verification. |
| Incomplete implementation | Fill a helper under an effect/mutation contract | Existing hole diagnostics vs structured obligation context. |
| Small tool authoring | Validate records or transform text into a structured report | Existing mylang CLI plumbing vs native invocation; a matched Python baseline may be added as a separate comparison. |

Freeze task briefs, sources, compiler, prompts, model settings, tools, cache
policy, budgets, and grading before each cohort. Randomize matched assignments
and vary one feature at a time before testing the combined workflow. Both arms
receive accurate documentation and equivalent ordinary tools. Pilot on development
tasks to establish outcome headroom and variance, then preregister sample size and
decision thresholds before held-out runs. Do not treat repeated attempts at one
task as independent task diversity.

Retain failed attempts, retries, timeouts, and delivery failures. Record:

- Independent behavioral acceptance and unintended changes.
- Wall time to accepted completion, with unsuccessful attempts reported separately.
- Agent input/output tokens and tool-response bytes when directly available;
  otherwise mark missing values rather than inventing a token estimate.
- Failed compiler/test invocations and the underlying processes inside bundled
  commands, so a wrapper cannot manufacture an apparent reduction.
- Time reading context, waiting for tools, checking, compiling, linking, and
  executing tests; distinguish overlapping work from wall-clock totals.
- Cold, warm-unchanged, and warm-after-edit behavior, plus work/reuse counters.

D1, D2 and S1 do not need a cohort. Their productivity verdict is lane C of the
idiom suite (C1 first-try fidelity, C3 rejections carrying a fix, C2 silent
wrong answers as the gate), rerun against the same 110 probes and the CPython
oracle, with the manifest baseline regenerated and committed beside the change.
L1's verdict is the untested-export finding count on both real applications
before and after. M1 produces the A3 series itself; its verdict is that the
harvested rounds for a package's diagnostic codes fall after the package lands.

Feature correctness and productivity are separate verdicts. Recommend a default
workflow change only when the held-out comparison meets its preregistered useful
improvement threshold without an unacceptable correctness loss. Report uncertainty
and inconclusive outcomes; do not claim noninferiority from a small sample with
zero observed failures. An unsuccessful treatment remains useful evidence.

## 6. P1 — Improve the measured bottleneck

Keep the existing sub-500 ms check-feedback and sub-1 s affected-test objectives
as reference targets, with project size, machine, mode, and cache state stated.
They are targets, not assertions about this checkout.

Use `--timings=json`, work reports, and complete command wall time to determine
whether the next improvement belongs in source discovery, dependency keys,
checking, context serialization, lowering, linking, process startup, or execution.
Improve one dominant component per change and retain semantic/cache equivalence
checks. A persistent process, lazy lowering, or batched execution requires its own
measurement; none is automatically the answer.

**Acceptance:** compare the same frozen workloads before/after with retained raw
samples and noise controls; unchanged, implementation-edit, signature-edit, and
import-edit results agree with fresh execution. Demonstrate a reduction in actual
work and end-to-end latency, or report that the change failed its objective.
Small projects must not absorb a large fixed cost to improve a scale benchmark.

## 7. Verification and completion

For implementation packages, add focused tests at the relevant semantic, CLI,
native execution, and cache boundaries. Test observable contracts rather than
mirroring internal helper implementations. Register new tests in the maintained
suites. Use the existing `test-units`/`test-cli` filters while iterating, then run
the required integrated gates for the completed scope with the pinned toolchain.
Native invocation and codec work require native build/test coverage and GC stress;
all public commands require feature/documentation updates and executable examples.

Shared regressions to preserve: selected-provider tests with unfinished unselected
production bodies, checked effects/mutation, source-mapped diagnostics, empty-test
selection failure, exact cache invalidation, and existing typed JSON compatibility.

A package that changes what the idiom suite accepts or how it rejects (D1, D2,
S1) regenerates `velocity/suites/idioms/manifest.json` and records the C1, C2
and C3 values before and after in the ledger. A silent wrong answer (C2) blocks
the package regardless of its C1 gain.

After any task that exercises Guardian, append concrete feedback to
`~/ai/canopy/guardian-zig/FEEDBACK.md` and commit that feedback in the Guardian
repository, following the user's global instructions. A documentation-only task
that does not exercise Guardian does not need a feedback entry.

Complete each package with its implemented behavior, source/compiler identity,
commands and evidence, remaining limits, and measurement verdict recorded in the
ledger. The plan is complete when all five outcomes have implemented acceptance
evidence and an honest evaluation readout; a favorable productivity finding is
not something implementation can guarantee.
