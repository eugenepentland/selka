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
| C1 | Focused context command | — | not started | the plan sequences it after F1, whose fact-status vocabulary it consumes |
| I1 | Native invocation of an ordinary export | — | not started | — |
| I2, I3, E1, P1 | remaining plan packages | — | not started | — |
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
`a6195a824f7f3c2c`:

| Command | Result |
| --- | --- |
| `zig build` | exit 0 — Guardian `88 check(s) passed`, install published |
| `zig build test --summary all` | exit 0 — **64/64 steps succeeded, 1436 tests passed, 0 failed** |
| `zig build test --summary all`, re-run after the D1 follow-up | exit 0 — **1438 tests passed, 0 failed** (the two added `DIAGNOSTIC-SITES-6` / `DIAGNOSTIC-ROLE-2` tests); doctest 327 files, 691 blocks, 0 mis-tagged, 0 failed; doc-coverage 0 failures |
| `zig build test --summary all`, after F1(a) and H1 | exit 0 — **64/64 steps, 1421 tests passed, 0 failed**; Guardian `88 check(s) passed`; doctest 328 files, 700 blocks, 154 run, **42 checked**, 0 mis-tagged, 0 failed; doc-coverage **164 features** across 46 pages, 0 failures |
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

## Closing state

All six workstreams reported and stopped. The whole-tree gate is green on the
installed binary, the idiom manifest is regenerated, and every package report
named at the top of this ledger exists.

**Delivered and verified by the lead:** W0 baseline and probe reproductions; S1(a),
D1, S1(b); D2, S1(c); L1; M1 including its CLI hook; the lane C instrument and its
before/after series; F1's reference half, wired into `dispatch()`; F1's honest-fact
half on both surfaces; and H1's bounded typed-hole obligations. Both consumers
broken by the fact-status change are fixed and the tree is green again.

**Not delivered, and not claimed:** C1, I1, I2, I3, E1 and P1. Nothing in this
session measured agent productivity; D1/D2/S1 are judged only by the lane C
numbers in this file, and L1 only by its finding counts.

**Honest shortfalls:** lane C's C3 reached 0.304 against the plan's 0.5 target for
D1, and C2 remains a blind spot rather than a certification because the suite's
only silent-wrong-answer probe no longer runs. Both are recorded above with their
reasons rather than rounded up.

**Follow-ups worth a future round**, in the order the evidence suggests:

1. **C1**, the focused context command — next in the plan's own order, and the
   reason this session stopped where it did: it consumes the fact-status
   vocabulary F1 has now settled, and its `agent-context-v1` envelope is the
   surface the plan's outcome 1 depends on. `main.zig` is free, and the
   path-based command pattern is `Command` → `Parsed` → an `ArgumentParser`
   option helper → a `runCommand` arm, as `tests-for` and `api-diff` do it.
2. **I1**, native invocation of an ordinary export, then I2 and I3.
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
