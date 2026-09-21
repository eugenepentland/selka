# Implementation ledger — agent-usefulness plan

Plan: [`agent-usefulness-implementation-plan-2026-09-20.md`](../agent-usefulness-implementation-plan-2026-09-20.md).
Baseline evidence: [`baseline-2026-09-20.md`](baseline-2026-09-20.md).
Package reports: `sites.md` (S1a, D1, S1b), `parser.md` (D2, S1c), `lint.md` (L1),
`friction.md` (M1), `scorer.md` (lane C instrument).

Status values: `done`, `partial`, `not started`, `blocked`.

## Baseline identity

| Fact | Value |
| --- | --- |
| Git HEAD at capture | `b8f6ec3f1178f12971e7dcb1d2255ab8c055b024` |
| Baseline binary sha256 | `2c2ed027cb810836101474ba91f929f0a710f6b34b9f19842eccd4bc659acd21` |
| Baseline copy | `zig-out/bin/mylang-baseline-20260920` |
| Zig | `0.17.0-dev.1683+5ceec001b` |
| Working tree | dirty before this work began; pre-existing changes preserved |

## Package status

| Package | Deliverable | Owner | Status | Evidence |
| --- | --- | --- | --- | --- |
| W0 | Verified baseline, protocol decisions | lead | **done** | `baseline-2026-09-20.md`; decisions below |
| S1(a) | `str.split()` with no argument | sites | **done, verified** | `a64_split_noargs.my` runs and prints 42 = CPython; `split(separator)` unchanged; 2-arg split names the signature and the whitespace alternative |
| D1 | Call-site rejections carry the signature and the alternative | sites | **done, verified**; C3 target **not met** | receiver named, signature rendered from one shared renderer; C3 0.000 → 0.304 |
| S1(b) | Prelude `ord`/`chr` with literal folding | sites | **done, verified** | `chr(65)`, `ord("m")`, `ord("m") == 109` → `A 109 True`; runtime traps `R_TEXT_SCALAR`; `ord("x")` fold pinned QBE-identical by a test |
| D2 | Parser hints for Python-divergent declaration forms | parser | **done, verified** | a37/a38/a39 each name the accepted form as an `alternative` note; classifier and hint table agree under two tests |
| S1(c) | Headerless scripts may import standard modules | parser | **done, verified** | headerless `import strings` checks and runs; a non-standard import still reports `E_MODULE_HEADER` |
| L1 | Untested-export lint counts test reachability | lint | **done, verified** | port fixture 22 → 8 findings, the 8 exactly the `tests-for` `reached-by (0)` set; strict unchanged at 22 with 14 transitive |
| M1 | Opt-in friction log and harvest script | friction | **done, verified** | record, privacy, absence, env form, exit status and the 4-round harvest all reproduced by the lead; CLI hook wired by the lead |
| V0 (lane C) | `velocity/score.py` C1/C2/C3 instrument | scorer | **done, verified** | `scorer.md`, `score-baseline-2026-09-20.json`, `score-D1D2S1.json`; re-run reproduces every verdict |
| F1(b) | Compiler-derived reference engine and command | reference | **done, wired and verified** | `mylang reference --query …` answers text and JSON from the installed binary; 12 spec-tagged tests |
| F1(a) | Honest interface facts: ceiling vs inferred vs status | interface-facts | **done, verified** | `interface-facts.md`; both surfaces verified by the lead (see below) |
| C1 | Focused context command | lead | **done, verified** | `src/context.zig` + `src/context_test.zig`; `mylang context` answers `agent-context-v1` from the installed binary; six sections in priority order, exact budget adherence with per-section omissions and a continuation query, stale-snapshot rejection, and a labeled partial answer on an incomplete project; see below |
| I1 | Native invocation of an ordinary export | lead | **done, verified** | `src/invoke_command.zig` + inline tests; `mylang invoke` describes and calls one export of the installed binary through the native test runner's own schema, codec, child and artifacts; see below |
| I2 | Useful copied managed values | lead | **partial** — `str` and `list[T]` results carried end to end | `mylang invoke` returns guest-built texts as strings and guest-built scalar lists as arrays, one wire node per element, verified on literals, concatenation, `chr`, astral scalars and 300-scalar bounds, plain and under `--gc-stress`; `bytes` is excluded by the plan's staging and every managed *argument* is refused with its own reason until the codec runtime holds roots — see the I2 section |
| I3, E1, P1 | remaining plan packages | — | not started | — |
| H1 | Bounded typed-hole obligations | typed-holes | **done, verified** | `typed-holes.md`; a valid `todo[T]()` retains a bounded obligation carrying the declared type, enclosing callable, initialized bindings, requirements, declared ceiling, mutation footprint and an explicit `unavailable` list, keyed by a snapshot identity rather than a line number; `Diagnostic` still at seven fields |

### Where the work stood when the last automatic round ended

The tree was **red, and only on H1's in-flight cleanup**: `formatting`
(`diagnostic.zig:326`), `dead-pub` (`diagnostic.zig::findObligation`), two
`twin-drift` pairs between `generic_bodies.zig` and `sema.zig`,
`repeated-string-literal` (`diagnostic_output.zig`) and `error-path-test`. No
other file was implicated.

One consequence is worth recording so it is not misread later: Guardian gates
the install, so `zig-out/bin/mylang` is the last **green** build and therefore
predates F1(a)'s `navigation.zig` change. The verification of `list-interfaces`
above is valid for that binary; the `index-project` half was verified by reading
the source directly, which publishes `null` for every inferred field — effects,
mutation positions, return-origin and managed-write — plus an explicit
`analysis` status whenever the project was not checked. The next step is H1's
cleanup and gate run, then one full `zig build test` to certify F1(a) and H1
together.

Every row marked verified above was re-checked by the lead against the
**installed** `zig-out/bin/mylang` after the final green build, not against a
staged copy; the staged `zig-out/bin/mylang-current` was only needed while the
install was gated during development.

## W0 decisions to freeze

| Decision | Value | Where recorded |
| --- | --- | --- |
| `ord` on non-single-scalar input | trap (default; `Option` rejected as the alternative) | sites report |
| Diagnostic note role | optional `role` inside `diagnostic-v1`, no v2 (unless a concrete reason emerges) | sites report |
| Friction record shape | pinned by `src/friction_log.zig` unit test | friction report |

## Deviations from the plan text

1. D1's `a64_split_noargs.my` acceptance is restated: S1(a) makes the probe
   legal, so the signature-carrying rejection is asserted on the arities that
   stay illegal.
2. L1's "ten findings on reached accessors" premise does not reproduce: the
   port's `main.my` graph contains no tests, so all 42 findings are exports with
   no in-graph test at all. Acceptance is restated around a fixture whose graph
   contains tests plus the measured port numbers.
3. S1(b)'s entry point `src/prelude.zig` is the canonical-constructor module;
   builtins live in `src/prelude_builtins.zig`.
4. M1's classifier step needs source text the log deliberately omits; the
   resolution is recorded in the friction report.
5. **S1(a) is not confined to the files the plan names.** The plan says the
   runtime route is `src/native_text_methods.c` and `src/qbe_text.zig`; adding a
   `Kind` member also required `src/collection_lower.zig` (three arms),
   `src/bytecode.zig` (two arms), `src/qbe_bytes.zig` (the `bytes` whitespace
   emitter) and `src/native_bytes.c`. The plan's premise that one text path
   covers `str.split()` is wrong for `bytes.split()`.
6. **The port rewrite is 13 comparisons, not 33 or 63.** The plan's cost figure
   is understated (the measured count is 63 comparisons against printable byte
   codes, 29 against ASCII letters) and the acceptance asked for all of them to
   be rewritten. The evidence that matters — the `ord("x")` fold is QBE-neutral —
   is pinned two ways instead: a fixture asserting `code == ord("m")` and
   `code == 109` emit identical QBE, and a partial port rewrite of the letter
   classifiers whose 101 emitted function bodies are byte-identical before and
   after, with the port's own suite still 114/114.
7. **`mylang fmt` still rejects module-syntax files** (`fmt probe4.my` reports
   `E_SYNTAX` at line 1; `fmt-module` works). S1(c) therefore makes `check`,
   `run`, `build` and `list-declarations` accept the headerless form while `fmt`
   does not. Pre-existing for headered files, newly visible for this one;
   recorded as a follow-up rather than fixed here.
8. **Two new Python drivers are now in the gate** (`zig build
   test-agent-usefulness`): `tests/parser_hints.py` (static table agreement plus
   end-to-end probes) and `tests/test_friction_harvest.py`. The plan's §7 asks
   for new tests to be registered in the maintained suites; neither package
   owner could edit `build.zig`, so the lead registered them.

## Lead verification (independent, against the tree's own compiled binary)

The compiler built from the current tree was staged as
`zig-out/bin/mylang-current` beside `qbe` (the install is gated on a green
Guardian run, so `zig-out/bin/mylang` is still the pre-change binary). Every
result below was produced by the lead, not taken from a package report.

| Check | Command | Result |
| --- | --- | --- |
| S1(a) `split()` | `mylang-current run velocity/suites/idioms/a64_split_noargs.my --print-result` | prints **42**, matching the CPython oracle's 42; previously `E_ARITY` |
| S1(b) `ord`/`chr` | `mylang-current run` on `out.print(chr(65), ord("m"), ord("m") == 109)` | prints **`A 109 True`** |
| S1(c) headerless import | `check` on a headerless file whose first line is `import strings` | exit 0 (was `E_MODULE_HEADER`) |
| S1(c) negative | same, importing a non-standard module | still `E_MODULE_HEADER` |
| D2 hints | `check a37_const.my` / `a38_class_methods.my` / `a39_dataclass.my` | each names the accepted form as an `alternative` note |
| M1 record | `mylang-current check --friction-log=/tmp/f.jsonl a37_const.my` | one `friction-log-v1` line: command, path as typed, compiler identity, snapshot hash, `E_SYNTAX` span 18–21, status 1, `wall_ns` |
| M1 privacy | a program whose source contains `zzz_SENTINEL_DO_NOT_LOG_9137`, checked with `--friction-log` | the log holds **zero** occurrences of the sentinel, no identifier fragment, no `return`, and no diagnostic message — only `{code, severity, start, end}`, the path as typed, and the snapshot digest |
| M1 absence | same command without flag or env | no file created |
| M1 env form | `MYLANG_FRICTION_LOG=/tmp/f-env.jsonl check …` | one line written |
| M1 exit status | accept vs reject with logging on | 0 and 1 — logging never changes the command's status |
| M1 harvest | `python3 velocity/friction/harvest.py velocity/friction/session-2026-09-20.jsonl` | exactly 4 rounds (`E_ARITY`, `E_MODULE_HEADER`, `E_SYNTAX`, `E_TYPE`), 0 for `E_LAMBDA_CAPTURE` and `W_UNUSED_BINDING` |
| Lane C instrument | `velocity/score.py --self-test`; full re-run on the frozen binary | 14 + 5 self-tests pass; re-run reproduces the recorded metrics with **zero** verdict differences across 110 probes |

### Lane C before → after (110 probes, one detector)

| Metric | Frozen baseline | Current tree | Note |
| --- | --- | --- | --- |
| C1 first-try fidelity | 0.239 (16/67) | **0.254 (17/67)** | `a64_split_noargs.my` moved reject → agree |
| C2 silent wrong answers | 0 | 0 | a blind spot, not a certification (see the baseline doc) |
| C3 structured | 0.000 (0/80) | **0.304 (24/79)** | 24 rejections carry a note with `role = alternative`; 15 of them are the bare-`print` `E_OUTPUT_CAPABILITY` class |
| C3 text-any (secondary) | 0.250 | 0.354 | not comparable to `goal.json`; reported for completeness |

**C3 still does not reach the plan's D1 target of 0.5.** It moved from 0.000 to
0.304 across two measurement points: 0.114 from D1's method and argument sites
plus D2's four hint forms, then 0.304 once the bare-`print` rejection carried
its accepted spelling as a structured note (the same sentence its primary
message already printed, so no diagnostic text changed). The remaining 55
rejections have no structured alternative: 25 are `E_SYNTAX` forms D2 never
hinted, and the rest are `E_ARITY`, `E_TYPE`, `E_EXPRESSION` and single-instance
codes where no accepted spelling is known at the failure site. Reaching 0.5
would need broad per-form coverage beyond D1's and D2's scope. Recorded as an
unmet target, not a completed one.

## Final verification (whole-tree gate, installed binary)

`zig-out/bin/mylang` installed from the current tree, sha256 prefix
`57afa85bb11b974f`:

| Command | Result |
| --- | --- |
| `zig build` | exit 0 — Guardian `88 check(s) passed`, install published |
| `zig build test --summary all` | exit 0 — **64/64 steps succeeded, 1436 tests passed, 0 failed** |
| `zig build test --summary all`, re-run after the D1 follow-up | exit 0 — **1438 tests passed, 0 failed** (the two added `DIAGNOSTIC-SITES-6` / `DIAGNOSTIC-ROLE-2` tests); doctest 327 files, 691 blocks, 0 mis-tagged, 0 failed; doc-coverage 0 failures |
| `zig build test --summary all`, after F1(a) and H1 | exit 0 — **64/64 steps, 1421 tests passed, 0 failed**; Guardian `88 check(s) passed`; doctest 328 files, 700 blocks, 154 run, **42 checked**, 0 mis-tagged, 0 failed; doc-coverage **164 features** across 46 pages, 0 failures |
| `zig build test --summary all`, after C1 | exit 0 — **64/64 steps succeeded, 1471 tests passed, 0 failed**; Guardian `88 check(s) passed` across 40 files in scope; doctest **330 files, 710 blocks, 154 run, 43 checked, 10 skipped, 0 mis-tagged, 0 failed**; doc-coverage **165 features** (109 language, 56 tooling) across 47 pages, 12 standard modules, 168 exports, **0 failures** |
| `zig build test --summary all`, after I1 | exit 0 — **64/64 steps succeeded, 1498 tests passed, 0 failed**; Guardian `88 check(s) passed` across 41 files in scope; doctest **331 files, 716 blocks, 154 run, 43 checked, 11 skipped, 0 mis-tagged, 0 failed**; doc-coverage **166 features** (109 language, 57 tooling) across 48 pages, 12 standard modules, 168 exports, **0 failures** |
| `zig build test --summary all`, after the I2 reconnaissance | exit 0 — **64/64 steps succeeded, 1499 tests passed, 0 failed**; Guardian `88 check(s) passed` across 42 files in scope; doc-coverage **0 failures** |
| `zig build test-qbe --summary all` | exit 0 |
| `zig build test-qbe-build --summary all` | exit 0 |
| `zig build fmt-check` | exit 0 |
| `mylang doc-coverage .` (inside the gate) | 0 failures — 161 documented features across 45 pages, 12 standard modules, 168 exports |
| `mylang doctest .` (inside the gate) | 326 files, 687 blocks, 154 run, 41 checked, 10 skipped, **0 mis-tagged, 0 failed** |
| `zig build test-agent-usefulness` | exit 0 — the two new Python drivers, registered in `build.zig` by the lead |

`velocity/suites/idioms/manifest.json` was regenerated from the installed
binary with `python3 velocity/score.py --binary zig-out/bin/mylang
--write-manifest velocity/suites/idioms/manifest.json` (110 probes, version and
oracle rule preserved, `agree` null for `mylang-only`). The frozen before-values
remain in `score-baseline-2026-09-20.json`, and the after-values in
`score-D1D2S1.json`.

Both were refreshed after D1's signature follow-up and the lane C numbers are
**unchanged** by it — C1 0.254, C2 0, C3 0.304 — which is the expected result and
worth stating: signatures are not `alternative` notes, so adding them improves
what a rejection *says* without moving the metric that counts alternatives. The
manifest's recorded `binary` digest is `sha256:e76021f7…`, the installed
compiler at the time of writing.

### Reference command, exercised through the wired CLI

`mylang reference --query standard-sort` prints the feature's kind, summary and
doc anchor; `--query sort_ints --format=json` answers `reference-v1` with
`library.status: checked`, 12 modules, 168 exported declarations and a
declaration carrying `analysis: checked`,
`def(values:list[i64])->list[i64]`, `effects: ["managed_allocation"]` and the
same declared ceiling; `--help` exits 0; an unmatched query answers `match=none`
rather than failing.

### The plan's §7 shared regressions, named

The plan requires six behaviours to survive every package. Each has a named
guard, all of which ran inside the green gate:

| Regression | Guard |
| --- | --- |
| Selected-provider tests with unfinished unselected production bodies | `test/integration.zig:5126` "P1 ignores an unselected production body type error while its declarations stay valid" (re-run alone: 1 passed) |
| Checked effects and mutation | the effect/mutation suites in `src/*_test.zig` |
| Source-mapped diagnostics | `src/source_map_test.zig` "mapped source locations survive parser checking lowering and native traces…" |
| Empty-test selection failure | `test/integration.zig` "affected: 0 selected, 2 skipped against HEAD" |
| Exact cache invalidation | `src/check_cache_test.zig` successful/InvalidVerdict/replacement cases |
| Existing typed JSON compatibility | `src/typed_json_test.zig` |

### D1's signature criterion, measured directly

D1's acceptance says "every call-site rejection in `velocity/suites/idioms/`
carries the callee signature". Measuring it — `mylang check --diagnostics=json`
over all 110 probes, searching the primary message, every note and `fix` for a
rendered `name(...)` callable, for the call-site codes `E_ARITY`,
`E_COLLECTION_METHOD`, `E_LIST_METHOD`, `E_CALL_ARGUMENT`, `E_FILE_ARGUMENT`
and `E_OUTPUT_CAPABILITY` — gives **5 of 26 carrying a signature and 21 not**.

Three classes, recorded so the shortfall is legible rather than rounded away:

| Class | Count | Disposition |
| --- | --- | --- |
| Bare `print` (`E_OUTPUT_CAPABILITY`) | 15 | The callee is a known builtin with an arity in `io_builtins`, so a signature is renderable; routed back to the package owner. |
| Unknown method (`E_COLLECTION_METHOD`, `E_LIST_METHOD`) | 2 | No callee exists to render; the receiver plus accepted spellings is the correct answer and is D1's own rule. The exception belongs on the record. |
| Builtin arity (`range`, `enumerate`) and `E_CALL_ARGUMENT` (`sorted`) | 4 | Raised in `src/parser.zig` and `src/call_arguments.zig`, outside D1's file list; measured and handed back for a scoping decision. |

**Re-measured after the package owner closed the `print` block: 20 of 26 carry a
signature, 6 do not** — `a18_str_format`, `a79_str_methods` and
`d07_str_index_assign` (no callee exists to render), and `a26_sort_key`,
`a30_range_step`, `a44_enumerate_start` (raised in `parser.zig` /
`call_arguments.zig`, outside the package's file list). The added line is
`signature: stream.print(values..., sep: str, end: str) -> None`, and it was
checked against the source rather than trusted: `src/io_builtins.zig` splits a
`print` into positional values plus exactly the `sep=`/`end=` keywords, so the
rendering names the parameters the language really accepts. The same follow-up
gave `sorted` the rendering `sorted(values: list[T], key: callback) -> list[T]`.
The frozen baseline scores **0 of 27** by the same measurement.

Spot-checking the renderings for truth rather than presence: `sorted`'s matches
`src/sema.zig`'s "requires a list and optional key callback" rule;
`round`'s is embedded in its message from the prelude table; and
`dict[str, int].get(key: str, default: int) -> int` on `a62_option_or` renders
the receiver's **actual instantiated** key and value types rather than a generic
template, which is the harder and more useful case. The one remaining
`E_CALL_ARGUMENT` without a signature (`a26_sort_key`) is also the one whose
rendering could not be made truthful from where it is raised.

### Lead disposition of the six that carry no signature

The criterion's own wording is "every `E_ARITY`, unknown-method and
argument-position `E_TYPE` diagnostic **at a call** names the receiver type and
renders the callee's signature". Applied honestly, four of the six fall outside
it rather than merely outside the package owner's file list:

| Case | Disposition |
| --- | --- |
| `a18_str_format`, `a79_str_methods` (unknown method) | **Exempt by the rule's own terms.** There is no callee to render; naming the receiver and listing the accepted spellings is what D1 prescribes, and both cases do exactly that. |
| `d07_str_index_assign` | **Exempt.** The language forbids the operation outright, so no signature exists to print. |
| `a30_range_step`, `a44_enumerate_start` | **Exempt on accuracy grounds, not scope.** These are loop-header constructs parsed as calls with a one-or-two-argument shape (`range(end)` or `range(start, end)`) and a two-name binding form (`for i, x in enumerate(xs)`). No single callable rendering expresses that without being *less* precise than the existing message, which already names both accepted forms. Printing an approximate signature would trade a true sentence for a tidy metric. |
| `a26_sort_key` | **Genuinely open.** `src/call_arguments.zig`::positional runs before the receiver is known, and shared spellings (`pop`, `copy`, `clear`, `items`) would then render a signature that can contradict the one `sema.zig` renders. The right fix is to move the keyword check to where the receiver type is known; scheduled after H1 releases `sema.zig`. |

### D2's agreement test, falsified on purpose

D2's acceptance says "a form present in one [table] and absent from the other is
a test failure". An unfalsified test is not evidence, so I removed `method` from
`velocity/friction/classifier.json`'s `hints` array and re-ran both halves:

- `python3 tests/parser_hints.py` → exit 1;
- `zig build test-units -Dtest-filter=classifier` →
  `declaration_hints_test.test.the hinted forms and the friction classifier name one table`
  failed with **`expected 4, found 3`**.

The classifier was restored immediately (the four hints are back and the driver
exits 0). So the agreement is enforced by a test that really does fail when the
two tables diverge, in both the gate-running Zig half and the standalone driver.

### L1 on the second real application
The plan asks for L1's verdict on "both real applications". On the schematic
guest (`src/schematic/guest/main.my`) the agent and strict profiles both report
**51** `L_UNTESTED_EXPORT` findings — identical, and correctly so: that project
contains no tests at all, so direct and transitive reachability are both empty
and no profile difference can appear. The profile split is only observable on a
graph that really contains tests, which is why the port fixture (22 → 8, with 14
transitive under strict) is the meaningful measurement and the honest place to
read the change from.

### Repository state

Every change in this session is in the working tree and **uncommitted**, beside
the pre-existing modifications that were already there when it started. The plan
notes that the regenerated manifest is committed "beside the change"; that
commit is the user's to make, and the working tree should not be committed
wholesale because it also carries unrelated in-flight edits.

### Cross-surface finding: the `print` signature is a copied string

The call-site rejection for a bare `print` now renders
`stream.print(values..., sep: str, end: str) -> None`. I checked it against the
source rather than trusting it, and the *content* is right: `src/io_builtins.zig`
splits a `print` into positional values plus exactly the `sep=`/`end=` keywords.
But it is **not derived from that table** — it is a literal,
`pub const stream_print_signature` in `src/buffer_operations.zig:267`, while the
keyword spellings it names are separate literals inside
`io_builtins.printArguments`. Two copies of one fact, which is the drift risk the
plan's "one shared renderer so the two can never disagree" rule exists to remove;
the collection methods do not have it, because their signatures come from
`buffer_operations.signatureText`.

A second, milder inconsistency sits beside it:
`mylang reference --query print` reports `{kind: "function", arity: 0}` from the
same `io_builtins` table, where `arity` is documented as the number of *required*
positional arguments, while the diagnostic describes a variadic `values...`.
Neither statement is false, but a consumer reading only `arity: 0` would not
expect a variadic callee. Both are recorded as follow-ups rather than fixed in
this pass: `src/buffer_operations.zig` and `src/io_builtins.zig` belonged to the
package owner while it finished, and `src/sema.zig` now belongs to H1.

### F1(a) verified against its own reproduction

The W0 defect was that `list-interfaces` rendered a complete function and one
containing `todo[int]()` identically. With F1(a) in the tree:

```
complete module:    export function double def(x:i64)->i64 effects() ceiling(managed_allocation) tests(0)
incomplete module:  export function double def(x:i64)->i64 effects(unavailable) analysis(declaration-only) ceiling(managed_allocation) tests(unavailable)
```

The checked case keeps its real inferred set — `effects()` really is empty here,
because `x * 2` allocates nothing — while the unavailable case publishes
`effects(unavailable)` and an analysis status instead of the conservative
internal mask, and `tests(unavailable)` replaces a column that used to vanish
silently. A declared ceiling stays visible either way, including when the body
has a hole.

The same defect survives in one more place, found by running the second surface:
`mylang index-project` on the incomplete module emits `"checked": false` in the
envelope but still reports `effects: []` and `mutates: []` per symbol. In JSON an
empty array is a claim, not a silence, so those are still unknowns dressed as
facts; `return_origin: "unknown"` was already the honest shape. Routed to the
package owner with the exact command and output.

### H1's approach to the field-count trap

The brief warned that `Diagnostic` sits at exactly 7 fields and the type-size
ratchet denies growth, so an obligation payload could not simply be added. The
package's answer, reviewed mid-flight: the obligation pointer rides the **existing
inline `provenance` struct** as a third member
(`origin`, `requirement`, `obligation`), the snapshots themselves live in a
`holes: ?Holes` side table owned by the `Sink` and released in `deinit`, and
`Sink.typedHoleObserved(at, target, snapshot, observation)` replaces `typedHole`
at both call sites. `Diagnostic` therefore stays at seven fields while every
obligation still travels with the diagnostic it belongs to. The renderer gained
the `signature` role and now suppresses an `alternative` note whose text merely
repeats the primary sentence, which is what keeps the bare-`print` diagnostic's
terminal output byte-identical while its JSON gains structure.

### F1(a) verified on both surfaces

`list-interfaces`, the surface W0 reproduced the defect on:

```
complete module:    export function double def(x:i64)->i64 effects() ceiling(managed_allocation) tests(0)
incomplete module:  export function double def(x:i64)->i64 effects(unavailable) analysis(declaration-only) ceiling(managed_allocation) tests(unavailable)
```

and `index-project`, the second surface, after the install caught up:

| | `checked` | per-symbol |
| --- | --- | --- |
| incomplete module | `false` | `analysis: "declaration-only"`, `effects: null`, `mutates: null`, `return_origin: null` |
| complete module | `true` | `analysis` omitted (the pre-existing field set), real `effects`, real `return_origin` |

Explicit nulls replace what used to be empty arrays, which a JSON consumer reads
as a claim; the checked case is unchanged.

### One conflation F1(a) did not remove, and why

`src/navigation.zig:245` unions a declaration's **declared ceiling** into the
`effects` field whenever one exists, falling back to the inferred mask
otherwise — so `complete::double`, whose inferred set is empty and whose declared
ceiling is `managed_allocation`, reports `effects: ["managed_allocation"]`. The
field therefore means "the declared bound" for some symbols and "the inferred
summary" for others, which is the conflation F1 exists to remove.

It is recorded rather than fixed, for three reasons that should be weighed
before a later pass changes it: it **predates** this work and is not a fallback
published as an inferred fact; changing it alters a published `navigation-v1`
JSON field that existing consumers already read; and the lead's own byte-identity
constraint for checked output deliberately held it stable. The honest follow-up
is to publish a separate `ceiling` field and narrow `effects` to the inferred
set, under a version bump, so a consumer can tell the two apart.

### H1 verified against its own acceptance

Read from `mylang check --diagnostics=json` on the hole fixture, the obligation is
nested in the diagnostic record as a versioned `typed-hole-obligation` (v1) and
carries exactly the plan's list:

```
identity:    function "unfinished", site, snapshot bb1b2bf194018ced, omitted 0
declared:    int, with the location of the declared result type
expected_type: null            <- the checker does not know one here, and says so
bindings:    x: int, mutable, with its location
requirements: []
contract:    effects null (unavailable), mutation "none" with location, transitive …
unavailable: listed explicitly
```

The acceptance's remaining claims, each checked rather than taken on trust:

| Claim | Check |
| --- | --- |
| Filling a hole removes its obligation | the same program with `return x + 1` reports **0** obligation records and `check` exits 0 |
| A hole still cannot be published | `mylang run` on the unfilled program exits **1** |
| Old line numbers cannot identify a hole | the obligation is keyed by `identity.snapshot`, a digest of the declaring source |
| Unavailable facts stay unknown | `expected_type` is `null` and the contract's `effects` is `null` with an `unavailable` list, instead of an empty set that would read as a promise |
| Non-hole diagnostics unchanged | every non-hole `diagnostic-v1` record and all text output were byte-compared against pre-change captures by the package |

### F1(a)'s byte-identity proof, and the consumer it broke

The package proved its "checked output does not move" claim the only way that
counts: it copied the pre-change binary, then ran both over **2615 candidate
`.my` files** (569 checked programs) across `examples/`, `experiments/`,
`selfhost/`, `tests/lang/` and the schematic guest. Result: 8 listing lines in 4
files and 11 index symbols in 5 files changed, **every one a generic with no
checked instantiation** — exactly the case the change exists to fix — and all 480
manifest diffs are the single inserted `"analysis":"declaration-only"` key,
verified by deleting the key and re-comparing. No exit status moved.

That same change broke a consumer, which is the part worth recording. The plan's
navigation foundation (its §2 table) names `scripts/navigate.py` alongside
`index-project` and `tests-for`, and it treated `effects` as a list:

```
$ python3 scripts/navigate.py --compiler ./zig-out/bin/mylang --entry hole.my --effect managed_allocation
navigate: argument of type 'NoneType' is not a container or iterable
```

That is the correct consequence of publishing `null` for an unknown — the field
means "unknown" now, and a consumer that assumed an array has to say so. Fixed by
the lead in `scripts/navigate.py` and in the same pattern inside
`scripts/store_server.py` (`needle in (item.get('effects') or [])`); the
unchecked case now answers with an empty symbol list and exit 0, and the checked
case is byte-identical. The store's own `row['effects']` was deliberately left
alone: those rows come from the declaration store, not the navigation JSON, and
nothing there produces a null.

## C1 — the focused context command

(This package shares its name with lane C's `C1` first-try-fidelity metric. The
metric is the one in the lane C tables above; this section is the command.)

`mylang context <entry.my> --symbol 'model::validate'` answers one bounded
`agent-context-v1` object about one declaration. `--at 'model.my:13:12'` selects
by position instead, `--context-bytes=N` sets the total serialized budget,
`--format=json` is the accepted format, and `--against=FILE` classifies the
selection against an `mylang api-diff` baseline. Exactly one of `--symbol` and
`--at` is required; the plan's usage writes both with a space, so the parser
accepts `--symbol NAME` and `--symbol=NAME` alike.

### One frontend pass, shared

`navigation.zig` gained `Facts`, `Snapshot` and `collect`, extracted from
`render`; `render` is now `collect` plus the same serializer, so `index-project`
publishes exactly the bytes it published before while `context` reads the same
tables instead of paying for a second frontend pass. `context` re-checks nothing
and reimplements nothing: the declaration and contract come from the navigation
tables, the test callers from `tests_index` — the same reachability walk
`tests-for` and lint's related notes use — and the optional changes from
`api_diff.compare`.

### Verified behaviour, measured on the installed binary

Fixture: a two-module project (`main.my` importing `model.my`) with a record
type, four functions and one discovered test.

| Claim | Observed |
| --- | --- |
| The envelope names its question and its sources | `version agent-context-v1`, `status ok`, `selector.resolved main::tally`, `snapshot.modules 2`, a 64-hex `snapshot_sha256`, `emitted_bytes 2168` at the default budget |
| Sections are published in priority order | `declaration, contract, types, dependencies, tests` — and `changes` only when `--against` was supplied |
| The contract labels each fact | `analysis checked`, `declared_effects []`, `effects []`, `mutates []`, `return_origin fresh`, `mutation_writes false`; on a body that does not check the same fields are `null` with `analysis declaration-only` |
| Dependencies carry signatures both ways | outgoing `main::helper` and `model::helper`, incoming `main::main`, each with its checked signature |
| Test callers are static reachability | one record, `relation reached`, `basis static-reachability` |
| `--at` selects the innermost declaration | `model.my:13:12` (inside `validate`'s body) resolves `model::validate` |
| Ambiguity is reported, not resolved | a bare `helper` exits 2 with `status ambiguous` and candidates `[main::helper, model::helper]` |
| A missing name is reported | `model::nope` exits 2 with `status missing` |
| The budget is exact | at `--context-bytes=2169` the complete 2168-byte answer is published with no omissions; at 1536 the answer is 1394 bytes with `sections [declaration, contract]` and `omissions [{source}, {dependencies, 3}, {tests, 1}]` |
| Omissions come with a way forward | that reduced answer carries a `continuation` query asking for a larger budget |
| `--against` classifies | a body edit reports `compatible` / `body changed`; a signature edit reports `breaking` / `interface changed` |
| Usage errors are rejected | no selector, both selectors, `--context-bytes=10`, `--context-bytes=abc`, `--format=xml` and a dangling `--symbol` each exit 2 |
| A broken project still answers | a body that calls an undeclared function exits 0 with `status partial`, `analysis.status declaration-only`, a `reason`, a `declaration` record and empty `dependencies` |
| A file that does not even parse still answers | with `return +` in `model.my`, `context --symbol model::broken` exits 0, resolves the name through the lexical pass `index-project` already used, and publishes its location and kind with `analysis lexical-only` and `effects null` — rather than an empty answer |
| Source changes reject the answer | the answer is pinned to the receipt `collect` took; every file-backed input is re-read through a caller-supplied reader and re-hashed before publishing, and a changed or unreadable source returns `status stale` with no sections. An embedded standard module and a `--inputs` module have no file behind them and are skipped rather than misread as edits |
| A private helper edit invalidates the answer | editing `model::helper`'s declared effect changed `snapshot_sha256` from `d8cc17e7…` to `bf8a07f3…`, moved the contract's `analysis` from `checked` to `declaration-only`, and replaced `effects: []` with `effects: null`; the same invocation repeated on unchanged sources is byte-identical, so nothing is served from an earlier check |

`src/context_test.zig` pins all of the above in 36 tests, one primary
`// spec: CONTEXT-*` tag per bullet plus a `spec-case` for the lexical, unloaded,
allocation-failure and skipped-input paths, so every one of the seven new SPEC
bullets is verified by a test that actually runs. `test/integration.zig` adds
nine `spec-case` CLI tests, which is what caught the path-resolution bug below.

### On a real application, not only the fixture

`experiments/sexpr-port/main.my` is the repository's own ported application, and
it is the case that matters, because it imports an embedded standard module.

| Invocation | Observed |
| --- | --- |
| `context experiments/sexpr-port/main.my --symbol 'sexpr.parser::parse'` | exit 0, `status ok`, 3118 bytes, all five sections; the contract reads `analysis checked`, `effects ["managed_allocation"]`, `return_origin fresh`; the declaration's location is `sexpr/parser.my:211:12` |
| the same with `--context-bytes=1536` | exit 0, `status ok`, 1486 bytes, `sections [declaration, contract]`, `omissions [{source}, {declaration snippet}, {dependencies, 3}]`, and `continuation "mylang context experiments/sexpr-port/main.my --symbol='sexpr.parser::parse' --context-bytes=6144"` |

Running that second command is what exposed the embedded-module bug: the first
cut re-read `@stdlib/byte_builder.my` as if it were a file, failed, and reported
the whole answer stale. The fixture never imports a standard module, so only a
real application could have found it.

### Where the implementation departs from the plan's text

- **The documented minimum is 1536 bytes, not the plan's implicit 1024.** The
  plan asks for "a documented minimum large enough for the envelope"; 1024 was
  not. Measured floors were 1350 bytes for the two-module fixture and 1300 for a
  twelve-module one, because the compiler identity, both digests, the
  declaration's location and its whole contract are never given up. The budget
  ladder spends six reductions — four list sections, the per-input source
  receipt, then the declaration body — and if the declaration and its contract
  still do not fit the run exits 2 rather than publishing a fragment.
- **`--at` needed an extent that navigation does not publish.** A navigation
  symbol's location is its *name* span, so a position inside a body matched
  nothing at all; the extent is now the name span extended by the published
  snippet, which is the body. This was found by running the command, not by
  reading the plan.
- **Staleness needs a reader, not a re-serialization.** `receipt.inputs` derives
  its digests from the already-loaded buffers, so calling it twice compares a
  value with itself. `Options.revision` is a caller-supplied re-reader: the CLI
  reads the files from disk and re-hashes them, and the tests inject a reader
  that can drift.

### Seams C1 opened for the packages after it

`navigation.render` was split into `collect` plus a serializer, so any command
that needs the declaration and reference tables can now take them from the pass
`index-project` already pays for. `navigation_partial` was split the same way
into `candidates`, which is what lets `context` name a declaration in a file that
does not parse. `Options.revision` is the general shape of "prove the sources did
not move under this answer", which I1's invocation will need for the same reason.

### Two bugs the verification found, and what they cost

Neither was visible from the fixture alone, and both would have shipped from a
green unit suite:

1. **The answer was stale for any entry outside the working directory.** A
   receipt spells its module paths relative to the entry file's directory, so
   re-reading them against the process's working directory failed for
   `mylang context app/main.my …` from anywhere but `app/` — which is the
   documented usage. Every one of the nine CLI integration tests failed on it.
   The fix resolves each pinned path against the entry's load root.
2. **A standard-module import made every answer stale.** `@stdlib/…` modules are
   embedded in the compiler and have no file; re-reading them failed the same
   way. Found only by running the command on `experiments/sexpr-port`.

### Shortfalls this package does not close

- `--at` can only select what navigation declares. A position inside a class
  body that is not on a field name resolves to nothing, because a type
  declaration carries no body extent. On the lexical path the extent is the
  candidate's name span, because no body was recovered to extend it.
- The `types` section publishes a nominal type's declared members but not its
  generic requirements as their own field; those remain visible in the signature
  the contract section publishes, which is where the plan's "generic
  requirements" are readable today.
- `--against` is ignored on the lexical-candidate path, where body syntax failed
  before any declaration merged: there is no checked compilation to compare
  against, so the answer says so in `reason` instead of guessing.
- The reduction ladder gives up a whole section once no record from it fits, so
  a caller that needs `dependencies` at a tight budget must ask again with the
  `continuation` query rather than receive a truncated list.

## I1 — calling an ordinary export natively

`mylang invoke <entry.my> --function 'app::normalize' --describe` answers whether
one export can be called from JSON at all, and `--input=request.json` calls it
once and reports the typed result. It is the difference between reading a
library function and exercising it.

The command is a **reuse**, not a second runner. `snapshot.withTestEntry` supplies
the synthetic entry a library without a `main` needs, `sessions.Session` produces
the checked schema, `native_test_execute.Executor` starts the isolated bounded
child against the same QBE artifacts `mylang test` builds, and
`native_test_wire.Codec` validates the arguments. Nothing about the test runner's
behaviour or receipts changed; `native_test_command.zig` was not touched.

### A checked signature is not a callable one

This is the package's real content, and running it on a real project is what
found it. There are two boundaries, and the plan's warning only makes sense once
they are separated:

- the **codec** carries integers, booleans, records, results, unions,
  enumerations, wire-coded domains and fixed-length arrays; and
- the **native call ABI** carries integers, booleans and an injected `Stream`,
  and nothing else.

A record is therefore a perfectly good copied value that still cannot be a call
argument. The first cut advertised `lib::shift(p: Point, dx: i64) -> Point` as
eligible and then failed at runtime with `UnsupportedSignature`; `--describe` now
reports it as ineligible, names `parameters.p` or `result`, and gives the reason.
That is exactly the failure mode the plan's I1 section asks the command to
prevent.

### Verified behaviour, measured on the installed binary

| Claim | Observed |
| --- | --- |
| A library with no `main` is invocable | a module declaring only exports describes and calls with exit 0 |
| `--describe` runs no guest code | it reports the contract, the wire verdict, the effects, the capabilities and the limits, and publishes no outcome |
| Both selector spellings work | `--function 'app::identity'` and `--function=app::identity`, as the usage text and the plan each spell it |
| A scalar call returns an exact value | `{"a":"2","b":"3"}` on `add` → `outcome.status returned`, `outcome.value "5"`, `outcome.steps 4`, exit 0 |
| Integer extremes survive | `i64` bounds are carried as decimal strings and returned exactly |
| A boolean result is a JSON boolean | `x > 0` returns `true` |
| An injected `Stream` takes no JSON argument | its parameter reports `wire injected`, the call is eligible, and the printed text arrives in `outcome.output`, not on stdout |
| A record is refused before execution | `--describe` reports `eligible false` with the ABI reason; `--input` exits 2 |
| `str` and `list[i64]` are refused before execution | `unsupported_path` names `parameters.text` and `parameters.values` |
| An external capability is refused with its name | `--describe` reports `required_capabilities ["Filesystem"]`, `eligible false`; `--input` exits 2 with that name in the reason |
| A private function is not a target | it is absent from the schema, so the name is rejected as unknown and exits 2 |
| A generic template is refused as such | `--describe` exits 2 with "generic template with no checked instantiation; add a concrete wrapper" |
| Arguments are validated before any child starts | a missing argument, an extra argument, and `{"a":2}` where a decimal string is required each exit 2 with no guest code run |
| The request file is read before the project is | an unreadable path is an `invalid-request` refusal, not a build |
| A trap is not a returned value | `return 1 // x` with `x = 0` exits 1 with `R_DIVISION_BY_ZERO` and a source-mapped location |
| An exhausted budget is a trap | a long loop under `--max-steps=50` exits 1 with `R_STEP_LIMIT` and a source-mapped location |
| A timeout is its own verdict | the same loop under `--max-steps=100000000000 --timeout-ms=400` exits 1 with `status timeout` and diagnostics `Timeout` |
| A repeated request executes again | the same call run twice reports `value "5"`, `steps 4` both times, so artifact reuse never became result reuse |
| stdout stays one object | every success prints exactly one `native-invocation-v1` object and nothing else; diagnostics go to stderr and guest output into the object |

`src/invoke_command.zig` carries its tests inline, following `native_test_wire.zig`
and `native_test_contracts.zig`: 22 of them, covering the parser, the selector,
both eligibility boundaries, the description, the request parser and the status
mapping. `test/integration.zig` adds 16 `spec-case` CLI tests, which is what
caught the fixture defect below.

### Where the implementation departs from the plan's text

- **The copied-value subset the plan names is wider than what an invocation can
  carry.** The plan says I1 "starts with the existing verified copied-value
  subset" and lists records among I2's follow-ups, which reads as though records
  already worked for invocation. They work for the codec and not for the call
  ABI, and no amount of codec work changes that; `--describe` now says so
  precisely instead of promising a callable.
- **A timeout is recovered from the child, not from the executor.** The shared
  executor reports an expired deadline as a child failure, so the deadline is
  recognised from the error the child raised. That keeps `mylang test`'s own
  status vocabulary untouched rather than adding a value its consumers would
  have to learn.
- **`--describe` uses `native-test-graph`, not `emit-project-qbe`.** The facts it
  needs are all in the checked schema, and the graph query produces that without
  lowering or emitting anything.
- **Refusals keep the identities they judged.** A refusal reached after the
  project was checked names the compiler, tool, source and schema identities;
  only a refusal decided before a snapshot exists — an unreadable request file —
  reports empty ones. The first cut blanked them everywhere, which read as though
  no project had been read at all, and the documentation pass caught it.

### Shortfalls this package does not close

- Only copies cross the boundary. `str`, `list[T]`, `dict[str, T]` and every
  other managed value are refused, which is I2's work, and until I2 lands the
  command is useful for numeric and boolean libraries only.
- No external authority is granted, so a `Filesystem`, `Network`, `Clock`,
  `Entropy` or `Environment` export cannot be invoked at all. That is I3's work.
- The child runs the whole-project build rather than a lowered closure, so the
  first invocation of a project pays for a full native build. Repeated
  invocations reuse the object cache, which is why the second is cheap, but the
  selective-lowering path `mylang test` uses for a filtered run is not wired in.
- A generic export still needs a concrete wrapper by hand. The plan allows this
  as the initial route and it remains the only route.
- **I1's `Err`-versus-trap acceptance cannot be met inside I1, and the plan's
  own staging says why.** The acceptance asks the command to "distinguish
  `Err`, traps, and timeout", but a `Result` return needs a non-scalar call ABI,
  and the plan puts records, `Option` and `Result` in **I2**. So the distinction
  is implemented and pinned where it can be — `classify` maps a returned value
  to exit 0 whatever it carries, and the integration tests pin the exit-0 and
  exit-1 paths — but no live call in this session returned an `Err`, because
  `Result[i64, i64]` is refused at the description step with the ABI reason. Two
  of the CLI tests assert that refusal instead, and their fixtures and request
  files are already in place to flip to positive assertions when I2 widens the
  predicate. This is a plan-text inconsistency, not a shortfall invented here;
  it is recorded rather than papered over with a status the command cannot
  produce.

## I2 — where the copied-value boundary actually is

I2 was opened and **deliberately not attempted**, because the reconnaissance moved
the work from "widen one predicate" to "a compiler change across three layers",
and because a half-widened boundary is worse than none: it would let `--describe`
advertise callables that fail at execution, which is the exact failure I1 was
built to prevent. What follows is the measured map, so the next attempt starts at
the gate instead of rebuilding it.

### The chain, in the order it decides

1. `invoke_command.zig`'s `abiCarries` is the **last** gate, not the first. It
   refuses anything that is not an integer, a boolean or an injected `Stream`,
   and relaxing it only moves the failure.
2. `qbe_build_shapes.zig`'s `supported` is the second: an export is emitted only
   when `find(self.types, name)` resolves the result and every parameter, where
   `self.types` is the **codec wire table**.
3. `qbe_build_dispatch.zig`'s `lookup` turns a failed `supported` into
   `host_error(..., "UnsupportedSignature")`. That string is what a record call
   actually returns, with `steps: 0` — measured, not inferred.
4. The codec wire table is built by `qbe_codecs.describe` from
   `qbe_wire.describeWithDomains(catalog, true)`, which walks
   `0..record_base + catalog.records.len` and keeps an aggregate only when
   `native_wire.supported` flags it and its layout has neither `trace` nor `drop`.
5. `native_wire.supported` is therefore the **real** predicate, and it is
   correct: a record of copied scalars is flagged, and a record holding a
   capability, a resource or any other type without a copied representation is
   not. This is now pinned by a test rather than by reading.
6. `catalog.records` is `program.records`, which `lower.zig` sets from the typed
   checker's program. The layouts for aggregate records demonstrably exist in the
   emitted C: `runtime_data` for a two-record program carries
   `myl_native_type` entries with `MYL_NATIVE_RECORD` and real field offsets.

### What is measured, and what is not

| Claim | Evidence |
| --- | --- |
| A record call fails at the native boundary, not in the parent codec | with `abiCarries` temporarily relaxed, `lib::make` and `lib::sum` return `outcome.status infrastructure-failure`, `diagnostics "UnsupportedSignature"`, `steps 0` |
| The codec wire table carries a flagged value record | new test `NATIVE-WIRE-VALUE-1`: `qbe_wire.describeWithDomains` emits `Pair` as `kind record` with two fields and omits `Stamped`, the record holding a capability |
| The predicate itself is correct | the same test's sibling assertion in `native_wire`: `flags[0]` true for the copied record, `flags[1]` false for the capability-bearing one |
| No record reaches the emitted table for a real program | `emit-project-qbe` on a program whose only record is `Point(x: i64, y: i64)` prints nine scalar wire types and no record, for both `wire_types` and `codecs.types` |
| `mylang test --cases` cannot carry a record argument either | the same absence holds for a `test_point(p: Point)` fixture, so this is a pre-existing native-boundary limit and not something I1 introduced |

### The open question, answered

The emitter carries a flagged value record when the catalog is built directly,
and the real build produces a table with no record at all. Instrumenting the real
path — the probe was written into the manifest as synthetic `wire_types` rows,
because Guardian bans `std.debug.print` — settled it in one run. For a program
whose only record is `Point(x: i64, y: i64)`:

```
PROBE app::Point flag=true runtime=false move=false trace=true drop=false kind=managed size=8 nf=0 n=4
PROBE str        flag=false runtime=true  move=false trace=true drop=false kind=managed size=8 nf=0 n=4
PROBE bytes      flag=false runtime=true  move=false trace=true drop=false kind=managed size=8 nf=0 n=4
PROBE float      flag=false runtime=false move=false trace=false drop=false kind=domain  size=8 nf=1 n=4
```

Three facts follow, and they are the answer:

- `native_wire.supported` flags `app::Point` **true**. The predicate is not the
  gate, exactly as the direct test showed.
- The gate is the next line of `qbe_wire.describeWithDomains`:
  `if (layout.trace or layout.drop) continue;`. `Point` is skipped because
  `trace` reads true.
- The layout that guard sees is **not `Point`'s layout**. `Point` is two `i64`
  fields — 16 bytes, two fields, `kind record` — and `catalog.layout` reports
  `kind managed, size 8, no fields`. `str` and `bytes`, which are genuinely
  managed handles, report the identical shape, so the call is resolving the
  aggregate index to a handle layout rather than to the record's own.

So I2's first change is a **layout-resolution bug in `native_types.Catalog`**,
not a wire-table or predicate change: `catalog.layout` must return the record's
own layout for an aggregate index. Until that is fixed every value record is
invisible to the native boundary for the same reason `Point` is, which is why
`mylang invoke` refuses records and why `mylang test --cases` cannot pass one.

A second probe printed `managed`, `@backingInt(ty)` and `ty.recordIndex()`
together for the same slot, which is what the first one could not separate:

```
PROBE i=0 back=19 rec=0 name=app::Point managed=true  rt=false -> managed/8/trace=true
PROBE i=1 back=20 rec=1 name=str         managed=true  rt=true  -> managed/8/trace=true
PROBE i=2 back=21 rec=2 name=bytes       managed=true  rt=true  -> managed/8/trace=true
PROBE i=3 back=22 rec=3 name=float       managed=false rt=false -> domain/8/trace=false
```

The pairing is sound, and the answer is the first column: **`app::Point` is
`managed = true`**. `typed.Record.managed` is not "this record owns a buffer or a
resource" — it is "this record is a heap object", and in mylang a `class` is
exactly that. `native_types.Catalog.build`'s first line returns the opaque
`kind managed` handle for any such record, `trace` comes back true, and
`qbe_wire`'s guard drops it. So there was never a table bug and never a
predicate bug.

### This is I2, and the plan already said so

The finding is not that records are nearly working. It is that a mylang record
**is** a managed value, so carrying one across the boundary needs the same
machinery `str` and `list[T]` need, which is what the plan's I2 text describes:
decode into fresh guest-owned storage, retain every temporary GC root, copy the
result out before teardown, bound the expanded size and the traversal work. The
plan also stages it correctly — `str`, then `list[T]`, then records, `Option` and
`Result` — and tells the implementer to "reject classes ... until an explicit
corresponding boundary contract exists". `mylang invoke` refusing a record today
is therefore the specified behaviour, not a gap left by I1.

### Increment 1, landed: the text wire encoding

I2's first item is `str`, and the plan requires its wire encoding to be specified
before it is implemented. Both are now done on the parent side, and deliberately
inert: the native table still excludes `str`, so `--describe` reports it
ineligible and `--input` still exits 2. Nothing about the boundary's honesty
changed, which is why the increment could land without risking the failure mode
I1 exists to prevent.

The encoding, stated once so the native half has a contract to meet:

- `str` is declared as an **opaque list of 32-bit scalars**, and that is the whole
  of its wire contract. An opaque *byte* list is deliberately not text, because
  the plan stages `bytes` behind its own encoding — the boundary never guesses a
  representation for a type the plan handles separately.
- A text value is **one node per Unicode scalar**: the node's child count is the
  scalar count and each child carries one scalar. The fixed-size node format
  therefore carries the whole value with no byte payload, which is what makes
  this increment a codec change rather than a protocol change — and it is the
  reason the guest can rebuild exactly the same string in either direction.
- A byte string that is not UTF-8 is refused at the parent, which is also where
  the scalar count comes from, and a scalar count beyond the node budget is a
  `TestValueLimit` rather than a truncated value.
- A text the wire could not have produced — a root node carrying bits, or a child
  outside the Unicode range — is a malformed response, not a value to repair.

Measured: a mixed ASCII/two-byte/three-byte/astral string encodes to eleven nodes
for ten scalars and decodes back byte-identical; a record field of the same type
takes the same path; `"\xff\xfe"` and a three-byte surrogate are both refused;
70,000 scalars is a limit failure; and a text rebuilt under an exhausted
allocator reports `OutOfMemory` rather than a partial string.

Three tests carry it (`WIRE-TEXT-1`, `-2`, `-3`), and the increment is green on
the whole gate.

### Increment 2, landed: a copied text crosses in the return direction

The boundary is wider than it was, and the widening is real rather than
advertised-and-refused. `mylang invoke` now carries `str` as a **result**:

```
$ mylang invoke app.my --function 'app::letter' --input=r.json
"outcome": {"status": "returned", "value": "A", "diagnostics": "", "output": "", "steps": 5}
```

Measured on the installed binary, with a fixture per case: `chr(65)` returns
`"A"`, a frozen literal returns `"hello"`, a concatenation returns `"A!"`, a
200-scalar value returns all 200 scalars, and a mixed ASCII/two-byte/three-byte/
astral literal returns `héllo 世界 😀` unchanged. Each of those also returns the
same value under `--gc-stress`.

**Why the return direction is the safe half, and what made it land.** Reading a
returned text happens after the call has finished, and `co_write` allocates
nothing while it does so, so the handle in the caller's return slot never has to
survive a collection safepoint. The argument direction cannot say the same:
building a guest text while materialising the remaining arguments would need a
root held across the next argument's allocation, and the codec runtime has no
root slots. So the two directions were separated deliberately, and both the
description and the refusal say which one they are talking about rather than
reporting the type as uncarried.

`--describe` on a `str` parameter now answers with exactly that:

```
"unsupported_detail": "a copied managed text is carried in the return direction
 only in this version, because building a guest text while materialising
 arguments would need a root across the next argument's allocation"
```

**What it took**, all of it verified by running rather than by reading:

- `qbe_wire` emits a `text` entry for a managed buffer whose element is a 32-bit
  scalar. The element is `shape.buffer`, not `shape.array` — the first attempt
  looked in the wrong field and emitted nothing, which the probe found.
- `qbe_build_shapes.kindNumber` gained kind 5, and a text's `count` is zero
  because it has no fixed length.
- `qbe_codecs_runtime.c` writes a text result as one node per scalar, reading the
  guest list header through `native_collections.h`, which the codec unit did not
  previously include.
- `invoke_command.zig` gained `abiCarriesResult` and taught its codec walk that
  an opaque scalar list is a value the codec carries, so the direction question
  is decided by one rule instead of two.

**A wrong-answer bug found and fixed the same round.** The first cut recognised
text by its element width — a managed buffer of 32-bit scalars — which also
matches a user's `list[u32]`. Measured: a program returning `list[u32]` produced
`('List<u32>', 'text')` in the codec table, so the caller's array would have come
back as a *string* built from its code points. That is a silent wrong answer, the
class of failure lane C's C2 exists to catch, and neither the compile step nor
the existing tests would have seen it. The discriminator is now the builtin's own
name, which is how the prelude already tells its builtins apart, and
`[NATIVE-WIRE-TEXT-1]` pins it: `str` is text, `List<u32>` is not.

**A latent bug fixed on the way.** `co_write` had no capacity guard at all: it
checked a fixed 100000 ceiling but never the `capacity` the caller actually
passed, so a result with more nodes than the caller's buffer would have written
past the end. A text result is exactly the case that makes this reachable,
because its node count belongs to the *value* rather than to the signature. The
codec runtime now carries `co_capacity` from the call and refuses with
`WireLimit` instead. I have not tried to prove the old path was reachable in
practice — the guard is the fix either way, and it is cheap.

### Increment 3, landed: `list[T]` as a result

The same day's work generalised to the plan's second item, and it needed **no C
change at all**: kind 5 already marshalled a guest list one node per element
using the element descriptor's own width, so the only differences were which
types reach the table and what the parent reads them as.

```
$ mylang invoke app.my --function 'app::numbers' --input=r.json
"outcome": {"status": "returned", "value": ["7", "8"], "steps": ...}

$ mylang invoke app.my --function 'app::codes' --input=r.json      # list[u32]
"outcome": {"status": "returned", "value": ["1", "2", "3"], ...}
```

The second line is the point. Before this round's fix the same export answered
`"\u0001\u0002\u0003"` — a string built from the caller's array. The
discrimination is now explicit and pinned: a copied managed list is any opaque
buffer of one scalar, the table carries all of them whatever the element width,
and the parent reads exactly one of them — the builtin `str` — as a string.
`bytes` is excluded by name, because the plan gives it its own encoding rather
than letting it inherit this one.

A list *argument* is refused with its own reason, the same root the text
argument needs:

```
"parameters.values cannot cross the invocation boundary: a copied managed list is
 carried in the return direction only in this version, because building a guest
 list while materialising arguments would need a root across the next argument's
 allocation"
```

Two tests carry it (`INVOKE-LIST-1`, `NATIVE-WIRE-LIST-1`), and the six CLI tests
the documentation pass added for the text path are in the suite as well: a text
result, a multi-scalar round trip including an astral scalar, a literal and a
concatenation and a built string, the argument refusal, `--gc-stress` equality,
and a 300-scalar bound. They run 22 `CLI invoke` tests green.

### Increment 4, landed: the plan's worked example

I2's acceptance asks for "two small examples that use the invocation route
without handwritten JSON plumbing", the second being "a text/list transformation
returning a typed report". That one is now possible, so it exists:
`examples/invoke-report/` is a module that declares no `main`, with
`report::headline(n) -> str` and `report::digit_counts(n) -> list[i64]` and a
private helper that is not an export. Its README shows the `--describe` call
that discovers the contract and the `--input` call that uses it, with the
expected answers written out.

Measured: `headline(90210)` answers `n=90210 sum=12`, `digit_counts(90210)`
answers `["2","1","1","0","0","0","0","0","0","1"]` — the digit histogram of
90210 — and `--function 'report::render'` is refused because a private helper is
not an export. Both exports take one integer, so one request file calls either,
and neither needs a grant: allocating the result is the runtime's own business.

The first example the plan asks for — a structured-record validator returning
useful errors — still needs records, which is the next increment.

### Increment 5, attempted and reverted: the argument direction

`str` and `list[T]` as *arguments* were implemented and then withdrawn, because
the root mechanism crashes under the stress collector and I could not fix it.
This is recorded in full so the next attempt does not repeat the two mistakes.

**What was built and verified working without `--gc-stress`.** The codec runtime
gained a copied-managed kind in the argument direction: `co_read` builds a guest
text with `myl_native_text_new` or a guest list with `myl_native_list_new`, and
each materialised managed argument is held on a `myl_native_root` until the call
returns. Measured: `measure(text: str) -> i64` with `"héllo 世界"` answers `8`,
`total(values: list[i64]) -> i64` with `["1","2","3","4"]` answers `10`, a
two-text `join(left, right) -> str` answers `"abcd"`, and `echo(text) -> str`
returns the exact string. The one that matters is the two-argument join: the
first value must survive the allocation the second one makes, and it does.

**Where it breaks.** Under `--gc-stress` the same join aborts the child with a
null-pointer panic inside the collector:

```
NativeTestProcessFailed: .{ .signal = .ABRT }
thread … panic: member access within null pointer of type 'const myl_native_type'
```

**Two mistakes, both mine, and neither fixed.**

1. The first root descriptor was `{.size=8,.kind=MYL_NATIVE_POINTER}` with a null
   `element`. The collector follows the element descriptor, so a root cannot
   leave it null even when the elements are plain scalars and tracing one does
   nothing. The runtime's own text helpers can use that shape because they root a
   *text*, whose scalars the allocator never walks; a root the collector sees
   from a call frame is a different case.
2. The fix — a `co_list_types` table carrying `element = &co_plain_types[width]`
   — still aborts.

**What reading the collector then found**, which is the lead the next attempt
needs. `src/native_heap.h` declares
`enum { MYL_NATIVE_TRACE_LEGACY, MYL_NATIVE_TRACE_NONE, MYL_NATIVE_TRACE_FIELDS };`
so `MYL_NATIVE_TRACE_LEGACY` is **0** and `MYL_NATIVE_TRACE_NONE` is **1**. A
hand-written descriptor that leaves `trace_mode` unset therefore gets `LEGACY`,
not `NONE`, and `trace`'s first line — `if (type->trace_mode ==
MYL_NATIVE_TRACE_NONE) return;` — does not fire. Every descriptor the emitter
writes sets the field explicitly, which is why this never bites generated code
and does bite a descriptor written by hand. Two further facts from the same
read, so the next attempt does not have to find them again:

- `trace` dispatches on `kind`: a `MYL_NATIVE_POINTER` root reads the pointer and
  calls `mark`, and does not touch `fields` or `element`, so the root descriptor
  itself is only half the story;
- `mark`'s payload walk uses **the allocation's own** descriptor —
  `object->element`, set by `myl_native_heap_alloc_at` — and skips it only when
  `kind == MYL_NATIVE_PLAIN`. That is the descriptor a hand-built list is
  allocated with, and `co_plain_types` sets `kind = MYL_NATIVE_PLAIN` but leaves
  `trace_mode` at 0, so it is `LEGACY` rather than `NONE`.

So both hand-written descriptors in the reverted attempt carried
`trace_mode = LEGACY` rather than `NONE`.

**That lead was tested and it is not the cause.** Setting
`trace_mode = MYL_NATIVE_TRACE_NONE` on the plain descriptors and
`MYL_NATIVE_TRACE_FIELDS` on the list ones, with `count = 1`, changed nothing:
`join` still answers `"abcd"` without `--gc-stress` and still aborts with the
same panic under it. So the descriptor shape is not where this breaks, and a
third guess at it would waste another round. What is established is narrower than
I first wrote:

- `trace`'s POINTER branch only reads the pointer and calls `mark`; it never
  touches `fields`, `element` or `trace_mode` beyond the early return, so no
  field of the *root* descriptor explains a null dereference on that path;
- `mark`'s payload walk consults the allocation's own descriptor and skips a
  `MYL_NATIVE_PLAIN` one, which is what both the text and list allocations are
  built with;
- the crash therefore happens somewhere the reading did not reach, and the next
  attempt should get a stack rather than read further. Stack tracing is disabled
  in the child, so that means building the guest with a debugger or a symbolised
  abort, or bisecting the stress collector's entry points — not another
  descriptor edit.

The `MYL_NATIVE_TRACE_LEGACY`-is-not-`NONE` trap is still worth knowing and is
recorded above, but it is a trap that did not fire here rather than the bug.

### The argument direction, third attempt: a wrong answer instead of an abort

Applying the patch with anchored assertions — so it either lands whole or fails
loudly — got further than either previous attempt, and the `trace_mode` fix did
change the failure: with `MYL_NATIVE_TRACE_NONE` on every descriptor the child no
longer aborts under `--gc-stress`. It returns the **wrong value** instead:

```
join plain                 ok | 'abcd'
join --gc-stress           ok | 'cdcd'
```

`left` reads the *second* argument's text. Both arguments are materialised into
separate `co_arguments` slots, each is pushed as a root before the next is read,
and the guest still sees one value twice — so the aliasing is not in the rooting
but somewhere between the root and the call. The likely places, none of which I
had the budget to check:

- what the emitter passes for a managed parameter — whether the call reads
  `co_arguments[i]` (the pointer) or something derived from it, since a text's
  wire-table `size` is 8 and the emitted C type for it is an 8-byte struct;
- whether `myl_native_text_new`'s single-allocation layout survives being handed
  to a *guest* call as an argument, given that its `storage` is a tail pointer
  rather than a payload, and the runtime's own comment says such a text "still
  grows an ordinary backing array" when appended to;
- whether the root slot address is the slot the call later reads.

That is the state to hand over. The `MYL_NATIVE_TRACE_NONE` correction is a real
fix and should be kept in the next attempt: without it the child aborts, and with
it the child runs and answers — which is a strictly better place to debug from,
even though the answer is wrong.

### The two attempts bracket the answer, and the next step is one experiment

Reading both sides of the boundary after the third attempt explains the wrong
answer, and it is a mistake in the *third* attempt rather than in the second.

`myl_native_heap_collect` marks from the root chain:

```c
for (myl_native_root *root = heap->roots; root; root = root->previous)
    trace(heap, root->type, root->address);
```

and `trace`'s first line is `if (type->trace_mode == MYL_NATIVE_TRACE_NONE)
return;`. The third attempt set `MYL_NATIVE_TRACE_NONE` on the list descriptors —
I changed them from `FIELDS` to `NONE` while chasing the abort — which makes the
root a **no-op**: nothing is marked, the first text is collected, the second
allocation reuses its block, and both arguments arrive as the same object. That
is precisely the `'cdcd'` signature, so the wrong answer is explained and the
rooting code itself is correct.

So the two attempts bracket the answer:

| Root descriptor | Result |
| --- | --- |
| `trace_mode = MYL_NATIVE_TRACE_FIELDS` (second attempt) | the child aborts under `--gc-stress` |
| `trace_mode = MYL_NATIVE_TRACE_NONE` (third attempt) | the child runs and answers the wrong value, because the root marks nothing |

### The experiment ran, and it answered the question

The probe was landed cleanly this time — the earlier failure was two colliding
copies of it in the same file, one malformed — and it reported through the
response code, because the child's stderr is discarded when the call succeeds:

```
PROBE n=2 a0=0x391b8f20 a1=0x391b8f20
```

**The two argument slots hold the same object before the call.** That settles the
three candidates in one line: the aliasing is in materialisation, not in the
emitted call, and not a dangling pointer either — both slots were written by
`co_read` with the same address.

So the question narrows to: why does the second `myl_native_text_new` return the
block the first one already owns, when the first is on the root chain before the
second allocation runs? The root is pushed with `&co_arguments[i]` — a live slot,
which the header documents as the supported form — and `collect` walks
`heap->roots` and traces each entry. Something between those two facts is wrong,
and it is now a small, specific question about one allocation rather than about
descriptor shapes, the emitted call, or the guest.

That probe was then run, at the moment of the second `myl_native_text_new`:

```
PROBE roots=1 head=0x7ccec11fff50 holds=0x357e6100 slot0=0x357f1f20
```

Read it carefully, because it rules out the obvious explanation and names the
next one:

- `roots=1` — exactly one root is registered, so the push for argument 0 did run;
- the root's slot holds `0x357e6100`;
- `co_arguments[0]` holds `0x357f1f20`, a **different** address.

So the root is not addressing the slot the probe is reading. If `root->address`
were `&co_arguments[0]` those two numbers would be equal by construction. Either
the push used a different slot, or the root at the head is not the one argument 0
pushed. The aliasing follows from that: argument 0's text is unreachable, the
second allocation reuses its block, and the stale pointer still sitting in
`co_arguments[0]` happens to equal the new one — which is exactly the
`a0 == a1` measurement from the previous probe, now explained rather than merely
observed.

That probe was run, and it **contradicts the reading above**:

```
PROBE head_addr=0x74645b7b4f00 slot0=0x74645b7b4f00 pt0=10 k0=5 k1=5
```

`heap->roots->address` **is** `&co_arguments[0]`, and both parameters are kind 5,
so the root addresses the right slot and the push is correct. My previous
conclusion — that the root was not addressing the slot — was drawn from a probe
that printed the *pointee* twice, `*(void **)heap->roots->address` beside
`*(void **)co_arguments[0]`, and read two different numbers out of what is, by
this measurement, the same memory. Those two reads cannot have disagreed unless
something wrote the slot between them, so the earlier inference was unsafe and
should not have been written down as a finding. It is corrected here.

**What is actually established, after two probes.**

- the root is pushed for argument 0, addresses `&co_arguments[0]`, and the
  descriptor is a pointer kind, so `collect` marks what the slot holds;
- after argument 0's text is built and rooted, the slot's contents are not what
  the root will mark by the time argument 1 is materialised — the two pointees
  read differently, and argument 1's `myl_native_text_new` returns the address
  argument 0's text had;
- therefore something between the push and argument 1's allocation either
  rewrites `co_arguments[0]` or frees argument 0's text despite the root.

That probe was run, and it **contradicts the one before it**:

```
PROBE rooted=0x38375100 slot=0x38380f20 objects=0x38380ec0 roots=1 same=0
```

At the second text argument's allocation the root's pointee and `co_arguments[0]`
differ, `co_root_count` is 1, and the object list head is a third address. But the
previous probe measured `heap->roots->address == &co_arguments[0]` at the same
point in the same run. Both cannot be true of one stable root chain: if the head's
address is `&co_arguments[0]`, reading through it and reading the slot are the
same read. So the honest conclusion is not "the slot was rewritten" but **the head
of `heap->roots` is not stable between those two reads, and the two probes were
each describing a different head.** `native_heap.c` says as much in passing —
"generated frames restore that stack to a per-frame mark, which would drop a
lazily pushed entry" — so roots from the runtime and roots from a call frame share
one chain, and a probe that assumes the head is its own root is unsound.

**What the next probe must establish, and it is a different shape of probe.** Not
another pointer pair: print the head's *identity* rather than its contents —
`heap->roots`, `heap->roots->address`, `heap->roots->type`,
`&co_list_types[...]`, and `co_root_count` in one `snprintf`, so the head is shown
to be mine or not. If it is not, the question becomes which code pushes and does
not pop around argument materialisation, and that is answerable by reading
`myl_native_text_new` and the heap's own root use rather than by more probing.

**Reading the allocation path then resolved the contradiction, and in favour of
the code.** `myl_native_heap_alloc_at` collects when a collection is due — which
under `--gc-stress` is every allocation — and then `calloc`s and links the new
object into `heap->objects`. It never touches `heap->roots`. `collect` walks
`heap->roots` and traces each entry, and my root is a `MYL_NATIVE_POINTER`, so it
marks the text it addresses. Nothing on that path pops a root, clears the chain,
or reuses a live block. So the chain is intact and the rooting is sound from push
to allocation, which means the disagreement between the two probes is a **probe
artifact**, exactly as the retraction above suspected, and not evidence about the
runtime.

That is where this increment should resume: not with another probe of the same
shape, but with one that prints the head's identity, run against a runtime whose
allocation and rooting paths have now been read end to end and found consistent.
If the identity probe shows the head is mine and the slot is intact, then the
remaining suspect is the emitted call, which is the one part of the chain not yet
read.

**The call path reads correct too, so all three links now do.** `ctype` maps a
text parameter to a `CodecValue{n}` (or `WireValue{n}` when the type is in the
ordinary table), `typedefs` emits the matching
`typedef struct { _Alignas(8) unsigned char bytes[8]; }` for it, and `argument`
passes `*(<that type> *)co_arguments[i]` — an eight-byte copy of the pointer,
which is what the guest parameter expects. Nothing there explains the aliasing
either.

So push, collect and call have each been read and each is consistent, while the
behaviour under `--gc-stress` is still wrong (`'cdcd'` for `join("ab","cd")`). The
remaining conclusion is that the reproducible fact and the code as read do not
yet meet, and that the next round should stop reading and **bisect the trigger**
instead of re-reading the three links a fourth time. The cheapest bisection, and
the one worth writing down because it is one export and one run:

| Fixture | What it separates |
| --- | --- |
| `join(left: str, n: i64) -> i64` (returns `len(left) + n`) | a managed argument followed by a scalar one: no second managed allocation, so if this is correct the trigger is the second allocation |
| `join(left: str, right: str)` with `--gc-stress` but a one-element text | whether the reuse needs two non-empty texts |
| the same join with `--gc-stress` disabled | already known correct, so it isolates stress-triggered collection as the condition |

That is a smaller and more decisive round than any of the last three, and it does
not depend on trusting a probe whose head identity I never established.

### The bisection ran, and it is decisive

Two fixtures, value-sensitive, because the first attempt at this used `len(left) +
len(right)` which is the same number whether or not the arguments alias — a
mistake worth recording on its own:

| Case | Under `--gc-stress` | Plain |
| --- | --- | --- |
| `cat(left: str, right: str) -> str` | **`'cdcd'`** | `'abcd'` |
| `cat_scalar(left: str, n: i64) -> str` | `'ab5'` | `'ab5'` |

This narrows the bug to one interaction and exonerates three things at once:

- **the root push is correct.** `cat_scalar` returns `'ab5'`, so `left` was still
  argument 0's text after the loop moved on to a second argument. A dropped or
  mis-addressed root would have lost it there too.
- **the emitted call is correct.** Nothing about how the parameter is passed
  differs between the two fixtures; only the *type* of the second argument does.
- **the trigger is the second managed allocation specifically.** A scalar second
  argument allocates nothing Guest-side, and the first text survives; a managed
  second argument allocates, and the first text is gone by the time the call
  runs.

So the question is exactly: during `myl_native_text_new` for argument 1 — the
only guest allocation between the push and the call — why does the collection not
keep argument 0's text, when the same root demonstrably survives argument 1 being
a scalar? `alloc_at` reads as collection-then-allocate with no root handling, and
`collect` reads as mark-roots-then-sweep, so the answer is in the part of
`collect` after the root walk: the pending drain, the region rules, or the sweep
predicate. That is a bounded read of one function, and it is where the next
attempt should start.

**Two retractions in three rounds** is itself the finding worth keeping: I have
been writing conclusions from probes whose semantics I had not established, and
each cost a round to undo. A probe should print the identity of what it is
reporting on, not just values read through it.

**The earlier version of this step said** to print, at the same moment:
`*(void **)heap->roots->address`, `*(void **)co_arguments[0]`, and
`heap->objects` — the object list head — plus `co_root_count`. If the two
pointees differ the slot was rewritten and the writer is the thing to find; if
they agree and the object is still in `heap->objects`, then the allocation reused
a live block and the bug is in the allocator's free list rather than in rooting.
Both of those are now single-line questions, which is where this should have got
to several rounds ago.

**The previous attempt's failure, for the record.** The patch applied cleanly with
anchored assertions (roots at `FIELDS`, plains at `NONE`) and two `fprintf`
probes were added to print each argument slot, the pointer it holds and the text
it built — but the generated C would not compile with the probes in place, and
the failure surfaced only as the two `fprintf` lines themselves with no error
text captured, so I could not read the cause. Rather than leave a tree in an
unknown state I reverted the whole attempt again. The tree is green and the
argument direction is refused.

That is the sixth round on this one increment without landing it, and the honest
summary is that my loop has been wrong: I have alternated between reading code
and re-applying a patch, when the thing that would actually resolve it is a
*running* probe. The probes are written and the patch is known-good up to the
compile step; what is needed is one session spent getting a sanitizer or
`fprintf` line out of the child and reading it, not another descriptor theory.

**What the next attempt should do, concretely.**

1. Re-apply via `argpatch2.py`-style anchored replacement (roots `FIELDS`,
   plains `NONE`), which is known to apply cleanly.
2. Add the `fprintf` probe **without** the `#include <stdio.h>` line — reach
   `stderr` through a declaration the runtime already has, or write to fd 2 with
   the runtime's own failure path — since adding the include was the step that
   broke the compile and I did not diagnose why.
3. Run `join --gc-stress` and read the two lines. They distinguish the three
   remaining candidates in one shot: if the two slots hold the *same* pointer the
   aliasing is in materialisation; if they hold different pointers but the guest
   receives one value the aliasing is in the emitted call; if the first pointer is
   already dangling the root is still not marking.

**The earlier experiment's premise, for the record.** `trace`'s POINTER branch does not read `fields`,
`element` or `trace_mode` beyond that early return, and `mark`'s payload walk
skips a `MYL_NATIVE_PLAIN` element, so nothing on the read path explains the
`FIELDS` abort. The next attempt should set the root descriptors back to
`FIELDS` while keeping every *plain* descriptor at `NONE`, and — this is the part
that was missing — print the two argument pointers and the two text addresses
from inside the child, so the abort is located rather than inferred. A single
`fprintf` in `co_execute` under `--gc-stress` answers what three rounds of
descriptor edits could not.

**Also learned, and it is procedural.** The
abort message is UBSan-shaped rather than a Zig safety panic — `member access
within null pointer of type 'const myl_native_type'` names a C struct — so the
child almost certainly carries a sanitizer report with a **file and line**, and
`mylang invoke` was showing only its first two lines because the diagnostics
field was truncated by the caller reading it. The next attempt should print
`outcome.diagnostics` in full rather than a prefix: that is where the answer is,
and it costs one call. My own reproduction never reached it, because the third
re-application of the patch left the codec runtime and the template
inconsistent — the template assigned a variable the C file no longer declared —
and I reverted rather than debug a half-applied patch. The lesson is procedural:
these patches must be applied with anchored assertions, not bare replacements
that no-op silently when an anchor has drifted.

**Why it was reverted rather than left in.** The crash is inside guest code
execution, so it can corrupt or abort a call that the description said was
eligible — the exact class of failure this command exists to prevent. A red or
aborting path is worse than the refusal that shipped, so the tree carries the
refusal again and the whole gate is green. The result direction, which allocates
nothing after the call and needs no root, is untouched and still verified.

### The remaining native half

Reading the layers the native half has to cross turned up a constraint that
changes how it must be attempted, so it is recorded before any of it is written.

**The table widening and the C marshalling cannot be staged separately.** The
moment `str` appears in the wire table, `qbe_build_shapes.supported` returns true
for a `str`-taking export and `qbe_build_dispatch.lookup` stops emitting
`UnsupportedSignature` — so the dispatch emits a real invoke case and the guest
is called with whatever the codec produced. If the runtime has no kind for text
at that point, that is a wrong-shaped value reaching guest code, not a clean
refusal. The earlier experiment showed the shape of this: relaxing one gate did
not produce a refusal, it produced `infrastructure-failure` at `steps 0`. So the
increment is one change, and the only safe order is: land the C side and the
table together, then relax `abiCarries`.

**Four things the C side needs that do not exist yet**, each verified by reading
rather than assumed:

1. *A heap handle in the codec runtime.* This one is already solved:
   `co_execute(void *ctx)` stores `co_context = ctx`, and
   `myl_native_heap *myl_qbe_heap(void *context)` is declared in
   `src/qbe_runtime.h`. Nothing to add.
2. *Root slots.* `src/qbe_codecs_runtime.c` contains **zero** occurrences of
   `root`. Materialising a guest pointer into the C `co_arguments` array and then
   allocating a second guest value would leave the first unrooted across a
   collection safepoint. `myl_native_root_push(heap, &slot, &address, type)` and
   `myl_native_root_pop` are the mechanism, and the plan's "retain every
   temporary GC root" is exactly this requirement.
3. *A `myl_native_type` per rooted value.* Rooting needs a descriptor, and the
   descriptors live in a **different translation unit**: `qbe_build_outputs.metadata`
   emits `runtime_data` plus the host bridges into the metadata unit, while
   `qbe_build_codecs.write` emits `CoType`, the dispatch and `co_execute` into the
   codecs unit. The `myl_t_<digest>` symbols are file-scope names in the former.
   The codecs unit therefore needs an emitted binding — a `const myl_native_type *`
   column on `CoType` — which means the wire-type entry has to carry its
   descriptor's symbol name, and that mapping does not exist in the manifest
   today.
4. *A copied-managed kind.* `CoType`'s kinds are scalar (0), array (2), variant
   (3) and domain (4); a managed value is none of them. `co_read` needs to build
   a guest text from the scalar children and `co_write` to read one back out, and
   `src/native_text.c` already has every guest-side helper that needs:
   `myl_native_text_new(heap, count)`, `myl_native_text_from_utf8`, and
   `myl_native_text_utf8` for the return direction.

**Why this is the honest stopping point.** Items 2 and 3 are not type support —
they are the memory-safety machinery the boundary has never needed, and item 3
crosses a translation-unit boundary that only the emitter can bridge. A partial
landing here does not degrade gracefully: it either leaves a guest pointer
unrooted under `--gc-stress`, or it hands guest code a value the codec built
wrongly. Both are worse than the refusal that ships today, and neither would be
caught by the existing gate.

### What the next increment needs

`CoType`'s kinds are scalar, array, variant and domain; a managed value is none
of them. `src/native_text.c` already has `myl_native_text_new(heap, count)` and
the text builders, so the guest-side construction exists — but the codec runtime
(`co_read`/`co_write` in `src/qbe_codecs_runtime.c`) takes no heap handle, so the
first change is to thread one through, add a kind for a copied managed value,
emit it, and version the schema and codec cache keys because the supported shapes
changed. That is the increment, and it is a compiler change of several hundred
lines across C, the Zig emitters and the parent codec — not a table fix.

The tempting shortcut is now closed by evidence rather than by judgement, which
is the useful thing this round bought: no future attempt needs to spend a round
discovering that `supported` and `layout` disagree about what a record is. Both
of the tests below now pin that disagreement so a change cannot quietly resolve
it in the wrong direction.

### Why this is not a small change

Widening the table is the easy half. Carrying a record end to end also needs the
emitted C `CoType` row to agree with the parent codec's field order and offsets,
the schema and codec cache keys to be versioned because the supported shapes
changed, and — for `str` and `list[T]`, which the plan stages first — real
marshal/unmarshal code that copies out of guest-owned storage before teardown and
retains every temporary GC root. The plan's own acceptance for I2 asks for
`--gc-stress` and allocation-failure coverage on top of that.

### What I2 inherits from this round

- The parent half of `str`, with its encoding specified and three tests pinning
  it, so the native half has a contract rather than a guess to satisfy.
- Two regression tests. `[NATIVE-WIRE-VALUE-1]` fails if the emitter stops
  carrying a finite value record or starts carrying an unsupported one;
  `[NATIVE-WIRE-VALUE-2]` records that a managed record is flagged by the
  predicate and still omitted by the table, so the necessary-not-sufficient
  relationship is enforced rather than incidental.
- A precise statement of which file decides what, so the next attempt measures
  `program.records` and `typed.typeName`'s spelling before changing anything.
- I1's tests, which already assert the *refusal* on the record and `Result`
  paths; those are the tests to flip when the boundary widens.

## Closing state

All six workstreams reported and stopped. The whole-tree gate is green on the
installed binary, the idiom manifest is regenerated, and every package report
named at the top of this ledger exists.

**Delivered and verified by the lead:** W0 baseline and probe reproductions; S1(a),
D1, S1(b); D2, S1(c); L1; M1 including its CLI hook; the lane C instrument and its
before/after series; F1's reference half, wired into `dispatch()`; F1's honest-fact
half on both surfaces; H1's bounded typed-hole obligations; C1's focused context
command; and I1's native invocation, all wired into the installed binary. Both consumers broken by the
fact-status change are fixed and the tree is green again.

**Not delivered, and not claimed:** I2, I3, E1 and P1. Nothing in this session
measured agent productivity; D1/D2/S1 are judged only by the lane C numbers in
this file, L1 only by its finding counts, and C1 and I1 only by the behavioural
tables above — no cohort was run against either.

**Honest shortfalls:** lane C's C3 reached 0.304 against the plan's 0.5 target for
D1, and C2 remains a blind spot rather than a certification because the suite's
only silent-wrong-answer probe no longer runs. Both are recorded above with their
reasons rather than rounded up.

**Follow-ups worth a future round**, in the order the evidence suggests:

1. **I2**, useful copied managed values, then I3. I1 named the exact boundary
   I2 has to widen: the native call ABI carries integers, booleans and an
   injected `Stream`, and everything else the codec already understands —
   `str`, `list[T]`, records, `Result` — is refused at the description step
   rather than at runtime, so I2 has one predicate to change and one place that
   reports it.
3. **`navigation`'s `effects` still merges the declared ceiling with the inferred
   summary**, so the field means different things for different symbols. Fixing
   it means a separate `ceiling` field and narrowing `effects`, under a version
   bump, because existing consumers read the current bytes.
4. **`a26_sort_key` carries no call-site signature** and cannot truthfully carry
   one where it is raised; the keyword check needs to move to where the receiver
   type is known.
5. **The `print` signature is a copied string** (`buffer_operations.zig:267`)
   rather than derived from `io_builtins`, so it can drift from the table it
   names; and `mylang reference --query print` reports `arity: 0` beside a
   variadic rendering, which is true but reads as a contradiction.
6. **C2's blind spot**: the suite needs a `round` probe that runs, or the gate it
   guards cannot see the divergence backlog item C-1 already tracks.
7. `mylang fmt` still rejects module-syntax files (S1(c) made the gap visible).
8. `list-interfaces --contracts` fails on any project importing the embedded
   `network` module (`E_UNKNOWN_SYMBOL` at `public resource Connection: network`;
   reproduced with the frozen binary by the reference workstream).
9. `mylang test` as a friction-log entry point, which needs the parent to keep
   structured codes rather than only child statuses.
10. `tests/parser_hints.py` and `tests/test_friction_harvest.py` are registered in
    the gate, but `scripts/navigate.py` and `scripts/store_server.py` have no test
    that would have caught the null-`effects` crash; a small consumer test would
    have turned a runtime `TypeError` into a gate failure.
