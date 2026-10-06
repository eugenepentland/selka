# New compiler core, stage S3: implementation plan for Codex agents (2026-10-06)

This plan is for the Codex coordinator and its agents. S3 takes the new core from "the
microbenchmarks and their language areas" to "real programs":
- capabilities and I/O at run time;
- the rest of the text, bytes and number library;
- the standard-library modules;
- the five application workloads.

Its exit check, from the new-core plan's §6:
- the five application rows build and match the old core;
- **`tests/lang` passes in full under the new core**, except tests that need user
  modules (S4) and the retired arena tests.

S3 runs on the same rules that worked in S2: one locked worktree per package, the Wave B
pace rules, and a review stop between waves.

## Launch instruction

> Implement stage S3 of mylang's new compiler core following
> `docs/audits/new-core-s3-implementation-plan-2026-10-06.md` on
> `codex/new-core-s2-integration`, starting from the commit that adds this plan. Create
> `codex/new-core-s3-integration` from it and integrate there. Run Wave A (S3-0 and S3-L)
> and **stop for review**. After the user's go, run Wave B (S3-C, S3-T1, S3-T2, S3-M),
> then Wave C (S3-A), then S3-X. Hold every gate in §5 and the rules in §6. Never merge
> into `main`. Finish with the S3 exit report in §7 and stop for the user's go/stop
> decision on S4.

## 1. Where S2 left things

**Base.** `codex/new-core-s2-integration`, at the commit that adds this plan. It
contains S2 as accepted on 2026-10-06 (`26cd1b1d`) plus the review fixes below.

**The S2 review fixes** (commits `6121ed2d`, `c18d869c`, `9d6fa976`). These are now part of the base:
- **`test-core` sharding.** `test-core` runs as 4 concurrent Guardian-runner shards
  (`-Dcore-shards=N`): 205 tests in about 1m45 (it was 4m04 in one process).
- **Caller-derived parameter intervals** (`NEW-CORE-FACTS-10`). A parameter of an
  internal function that no `func_ref` names takes the hull of its argument intervals
  over every reachable call, and verify builds assert it on entry.
- **8-bit vector lanes summed with `psadbw`** (`NEW-CORE-VECTOR-3`).
- **Old-core text fast paths** (`NEW-CORE-TEXT-2`). Equality checks the ends of long
  texts first, and `find` counts scalars from the nearer end.
- **Inline small-table dictionary probes** (`NEW-CORE-DICT-SMALL-1`).

**Effect of the review fixes.** Three rows were slower than the old core and now are
not (CPU 10, `measure_all35.py`, checksums identical):

| Row | Old core | New core before (S2 exit) | New core after | After ÷ old |
|---|---:|---:|---:|---:|
| bytes_scan, 4096 | 0.085 | 1.23 | 0.051 | 0.60 |
| string_equal, 4096 | 53.6 | 135.5 | ~55 | 1.03 |
| string_search, 4096 | 422 | 1082 | 423 | 1.00 |

- **All 35 rows stay within 1.10× Zig ReleaseSafe and within 1.07× the old core.** The
  worst are `string_equal/64` at about 1.0–1.07× (noise band) and `sort_int`/`list_scan`
  at 1.03×.
- **`string_split` improved too,** to 61.8 against Zig's 66.2.
- **The emitted `word_count` dictionary model** went from 96.7 to 47.8 cycles per
  operation.

**Not done, with the reason: the fused `split` cursor** (design §3.5).
- The `string_split` row passes every piece to `score`, a user function with a loop.
  The leaf inliner does not take functions with loops, and the design admits views only
  into runtime helpers and inlined callees, so fusion cannot apply.
- The levers that would make it apply are multi-block inlining (S3-M stretch) or the
  view ABI. The view ABI stays deferred unless `string_split` misses the gate (S2
  decision 4).
- A "count the pieces first" variant was measured and rejected: it costs a second
  search pass, 82 against 62 cycles.

**Conformance at the base.** Full `tests/lang`, debug and release, gives 1,224 matching,
0 mismatching and 316 unsupported. The leak and verify sweep is clean.

**What blocks the 316 unsupported tests** (`conformance.py --set all --why`), as test
functions / files:
- **Capabilities, hosts and tests:**
  - `capability type` 31/5;
  - `test parameters other than Stream` (property tests, capability stand-ins) 22/5;
  - the runner cannot read a `Result[bool, E]` test result 1/1;
  - `print options` 1/1.
- **Bytes:** `byte_buffer type` 38/11; `blob` 8/2.
- **Text and numbers:**
  - `text of a non-integer value` (float text) 19/11;
  - `count` 8/4; `upper` 7/2; `lower` 2/2;
  - `extend` 7/4; `view` 6/3; `decode` 5/4; `contains` 5/4;
  - `number_format` 5/2; `find_any` 5/1; `replace` 4/3; `strip` 4/4;
  - `text_repr` 4/1; `parse_int_range` 3/2; `text_chr` 3/2; `index_of` 3/2;
    `find_range` 3/2; `text_ord` 2/2; `strip_chars` 2/1; `rfind_range` 2/2;
    `find_start` 2/1; `reverse` 2/2; `parse_float` 2/2;
  - `parse_int receiver`, `scalar_count`, `text_format`, `hex`, `slice_step` and
    `splitlines` 1 each.
- **Dictionary views:**
  - `aggregate storage of live dictionary views` 20/7;
  - `ordinary dictionary snapshot combined with a live view` 6/5;
  - `live dictionary view of an interior place` 4/3;
  - escaping, rebound, `mut`-argument, list-stored and unproved-identity views 2 each.
- **Numbers and values:**
  - `shift_right` 10/1, `saturating_add` 2/1;
  - `f64_sqrt` 4/4, `f64_trunc` 4/1, `f64_to_u64` 3/1, `f64_floor` 2/1, `f64_sin`,
    `f64_cos`, `f64_from_u64` and `float_round` 1 each;
  - `equality of a recursive value` 9/3; `operator on an aggregate value` 6/3;
  - `array` 3/1; `dictionary key type` 2/1.
- **Places:**
  - `interior mut argument ancestor changed during later argument evaluation` 8/2;
  - `keyword call with a mut argument that is not a local` 2/2.

**Statically excluded files** (`conformance.py`'s S1-era list), to re-examine in S3:
- generics: `option_*`, `python_variants`, `migrated/generic_results`;
- "other list methods, tuples or fixed arrays": `rc_append_loops`, `rc_match_scalars`,
  `rc_plain_aggregates`, `rc_plain_appends`, `rc_plain_retains`;
- `error_traces` (a `Filesystem` capability);
- imports: `migrated/propagation`, which is S4 unless its imports are standard-library
  ones;
- the five arena files and `*arena*` tests, which stay excluded (N6, arenas retired).

**Coverage at the base:** 3,185 of 3,627 qualified function names. The full first-refusal
table is in S2's `experiments/new-core-s2-20261005/wave-b/integration/coverage-refusals.md`.

**Read before any package:**
1. `docs/design/new-core-ir.md`, `docs/design/new-core-s1.md` and
   `docs/design/new-core-s2.md`, all sections, including the as-built sections and §19–20
   (S2's recorded limits).
2. `docs/audits/new-core-s2-implementation-plan-2026-10-05.md`: its "Status after Wave A"
   rules and "Wave B pace" rules carry over unchanged unless this plan says otherwise.
3. The S2 exit report: `experiments/new-core-s2-20261005/wave-b/` (`REPORT.md` and
   `integration/`).
4. `docs/audits/new-core-plan-2026-10-05.md` (on `claude/runtime-levers-plan`), §6 (the
   stage table) and §9 (the risks).
5. The one-count plan's D2 (`docs/audits/gc-retirement-and-one-count-plan-2026-10-03.md`
   §4.2, on `claude/gc-retire-plan`): stored dictionary views.

## 2. Decisions that bind S3

**Accepted earlier, unchanged:**
- **N1–N6, R1:** N6 means arenas are retired, and the new core lowers `with arena()` as a
  plain block.
- **D1–D4.**
- **L1–L4:** L4 means x86-64 Linux with AVX2 for the optimized path, with the
  portability layout kept.
- **S2 decisions 1–8:** `MUT-OVERLAP-RECEIVER-1`, `MUT-REBIND-CALLER-1` and D1
  regardless of sharing are in the old core and the new core.

**D2 now applies to the language** (package S3-L). A dictionary view (`d.keys()`,
`d.values()`, `d.items()`) may appear only as an iteration source or as an immediate
argument (`len`, `in`, `list`, `set`, `sorted`).
- **Storing one is a compile error** (`E_VIEW_STORED`) with the fix-it `list(d.keys())`.
- **Coverage:** this covers every view the new core refuses today: aggregate storage,
  escape, rebinding, `mut`-argument views, list storage, ordinary snapshots combined with
  a view, interior-place and unproved-identity views.
- **History:** the user accepted this on 2026-10-04 (one-count plan §4.2). Its checker
  half was planned as the runtime-levers plan's WP-5 C5 and never landed. **S3-L takes
  it over**, as S2-Lb took over C4.

**New rule from the S2 review: no row may regress against the old core.**
- Every row (35 micro and 5 application) must be at most **1.10× the old core** as well
  as at most 1.10× Zig ReleaseSafe, at both sizes.
- `measure_all35.py` already measures the old core; report both ratios.
- A row that beats the Zig gate but trails the old core is a miss to fix, as the S2
  review's text rows were.

**Open questions:** none. If a package finds that the old core's answer for some program
is an implementation accident (as S1 found for `mut` rebinding and D1), it stops and
reports. It does not decide.

## 3. Work packages

Estimates are agent-hours. For calibration: S2 Wave B was about 15–17 agent-hours over
4–5 lanes, and the S2 review fixes about 4 hours for one integrator.

### Wave A

#### S3-0. Design note and IR first (one agent; about 2–3 h)

**Write `docs/design/new-core-s3.md` first,** with concrete decisions (IR ops, runtime
layout, emission, ownership, facts) for:
1. **Capabilities at run time.**
   - `Filesystem`, `Network`, `Clock`, `Entropy` and `Environment` as values.
   - Resources and file handles: a handle type with an explicit close, ownership under the
     one count, and what a trap does to an open handle.
   - Host functions and `extern`.
   - The old core's runtime (`src/qbe_io.c`, `qbe_files.c`, `qbe_grants.c`,
     `qbe_providers.c`, `qbe_resources.c`, `qbe_host_runtime.c`) is the algorithm source,
     ported into the new core's own runtime per R1, never linked.
   - `mylang run`'s grants and `--restrict` must behave identically.
2. **`byte_buffer`** (mutable bytes) and `blob`: their layout next to S2's shared
   `str`/`bytes` block, copy-on-write, and `decode`.
3. **Number and float text.**
   - Float formatting and parsing must give the old core's output byte for byte (port its
     algorithm; do not substitute libc `printf` unless the output is proven identical
     over the old core's tests and a fuzzed corpus).
   - `number_format`, `hex`, `parse_int_range` and `parse_float`.
4. **The remaining text methods** in the list in §1, and which run in the runtime and
   which inline.
5. **Generics.** Determine whether `typed.Program` already gives the new core
   monomorphized functions (`src/generic_specializations.zig`). If it does, generics need
   only the static exclusion lifted and their refusals fixed. If it doesn't, design the
   minimum.
6. **Standard-library imports.**
   - The front end already merges a file and its imports into one `typed.Program`
     (`src/core/frontend.zig`).
   - Decide what the new core needs so that `import strings` and `import json` (the
     `text` benchmark and `json_transform`) build: standard-library modules only. User
     modules, `.myi` interfaces and incremental per-module builds are S4.
7. **The test runner:**
   - property tests (parameters other than `Stream`);
   - capability stand-ins;
   - `Result[bool, E]` test results;
   - `print` options.
8. **Floats and integers:** `f64_*` intrinsics, `shift_left`/`shift_right`,
   `saturating_add`, and their facts.
9. **Recursive-value equality and operators on aggregates.**

**Then the IR changes** the note requires: types, ops, verifier rules, dispatch stubs and
hand-built-IR tests, as S2-0 did. **`ir.zig` is frozen after S3-0.**

**Exit:**
- the design note, with an "as built in S3-0" section;
- test-core green, with a hand-built-IR test per new op;
- full conformance at 0 mismatches;
- S0/S1/S2 benchmark definitions identical.

#### S3-L. Language change: D2, views cannot be stored (one agent; about 2–3 h; parallel with S3-0)

**The rule.** `E_VIEW_STORED`: a view stored into a variable, a record, a list or a
return, passed as `mut`, or rebound is a compile error. The fix-it is `list(d.keys())`.
Iteration (`for k in d.keys()`) and the immediate arguments (`len`, `in`, `list`, `set`,
`sorted`) stay legal.

**Where:** the shared checker, plus the old core's tests:
- rewrite every `tests/lang` and `src/*_test.zig` test that stores a view into the
  `list(...)` form, or into a rejection test;
- retire the SPEC bullets that describe stored views (`RC-HELD-RECEIVER-1`, the live-view
  protocol bullets) or amend them;
- update the docs on dictionaries and views.

**Stop and report** if `examples/`, `bench/` or the Lox port store views. Document their
migration as S2-La did for the overlap rule; don't edit the external Lox checkout.

**Exit:**
- the full old-core gate green;
- new-core conformance at 0 mismatches, with the view refusals (about 36 tests) gone or
  turned into rejection tests.

**Wave A stops for review.** Report the design decisions and the IR shapes. Wave B
starts after the user's go.

### Wave B (in parallel after S3-0 and S3-L merge; at most four build-heavy agents)

#### S3-C. Capabilities, I/O and the test runner (one agent; about 5–6 h)

**What:**
- the design's §1 and §7: capability values, the stream, file, clock, network,
  entropy and environment operations, resources and handles, host functions and
  `extern`;
- the runner's property tests, capability stand-ins, `Result[bool, E]` results and print
  options.

**Owns:** new `build_cap.zig`, `emit_cap.zig` and `runtime/core_io.c`; the runner files
(`src/core/test_runner*.zig`); and `test/core/c_*.my`.

**Exit:**
- the capability, I/O, resource and property-test files of `tests/lang` (and
  `error_traces`) at 0 mismatches;
- leak check clean, with no handle left open at exit;
- `--restrict` denies exactly as the old core denies;
- fuzz unchanged, because I/O programs are tested by fixtures, not fuzz.

#### S3-T1. Text methods (one agent; about 4–5 h)

**What:** design §4. The text and bytes methods in §1's list: `count`, `upper`/`lower`,
`strip` and its variants, `replace`, `contains`, the `find`/`index` variants,
`splitlines`, step slices, `reverse`, `extend`, `chr`/`ord`, `repr`, `text_format`,
`scalar_count` and `decode`.

**Owns:** `build_text.zig`, `emit_text.zig`, `runtime/core_text.c`, `fuse_text.zig` and
`test/core/t_*.my`. It shares `build_text.zig` with T2 through one dispatch hook, as in
S2.

**Exit:**
- their `tests/lang` files at 0 mismatches;
- the `text` fuzz kind extended to the new methods, with random ASCII and non-ASCII input;
- no text row regresses against the old core.

#### S3-T2. Bytes, numbers and float text (one agent; about 4–5 h)

**What:** design §2–§3:
- `byte_buffer` and `blob`;
- float formatting and parsing, byte for byte the old core's;
- `number_format`, `hex`/`from_hex`, `parse_int_range` and `parse_float`.

**Owns:** `build_number.zig`, `runtime/core_number.c`, new `build_bytes.zig` and
`runtime/core_bytes.c`, and `test/core/n_*.my` and `b_*.my`.

**Exit:**
- their files at 0 mismatches;
- the `number` fuzz kind extended to floats, including special values, rounding edges and
  very large and very small magnitudes, compared with the old core;
- `packet_decode`'s byte operations supported.

#### S3-M. Numbers, values and generics (one agent; about 3–4 h)

**What:**
- design §5, §8 and §9: `f64_*`, the shifts, `saturating_add` and their facts;
- recursive equality, operators on aggregates, `array` and `dictionary key type` gaps;
- generics per the design: lift the static exclusions and fix what `--why` then shows;
- the remaining place refusals (`keyword call with a mut argument that is not a local`).
  Narrow the conservative interior-`mut` refusal only with exact old-core agreement.

**Owns:** the facts rules for the new ops, `build_fn.zig` for generics, and
`test/core/m_*.my`. Patches to `own.zig` go through the coordinator.

**Stretch:** multi-block inlining of small loop helpers. It would let S2's fused `split`
cursor apply (§1). Do it only if every gate holds and the rows do not regress.

**Exit:**
- their files at 0 mismatches;
- the S0/S1/S2 code identity unchanged, or justified row by row;
- fuzz `s0`/`s1`/`functions` unchanged.

### Wave C

#### S3-A. Standard library and the five applications (one agent; about 3–4 h; after S3-C, S3-T1 and S3-T2)

**What:**
- design §6: `import strings` and `import json` build;
- the five application rows as split programs where their setup needs it, as S1 and S2
  split theirs: `word_count`, `csv_aggregate`, `json_transform`, `packet_decode` and
  `lox_eval`;
- measured with `measure_all35.py` extended to all 40 rows: old core, new core, Rust and
  Zig ReleaseSafe, checksums identical.

**Gate:** each application row ≤ 1.10× Zig ReleaseSafe **and** ≤ 1.10× the old core, at
both sizes. A miss is reported with its profile and fixed in the owning package's files
through the coordinator.

**`word_count` first:** it is the small-dictionary and split case the S2 review targeted.

### S3-X. Integration and exit (coordinator)

Same as S2-X, with the S2 "Wave B pace" rules:
- **between merges:** cheap checks after every merge (test-core, full conformance);
- **at the end, once, on the integrated head:**
  - the full old-core gate;
  - the 200-case fuzz matrix over every kind, including the new or extended ones;
  - the full leak and verify sweeps;
  - all 40 rows against both gates;
  - coverage.

## 4. Order

| Wave | Packages | Notes |
|---|---|---|
| A | S3-0, S3-L | in parallel. S3-L changes the shared checker and the old core, so it runs the full gate. **Stop for review** after both merge. |
| B | S3-C, S3-T1, S3-T2, S3-M | after the review go; four build-heavy agents. T1 publishes any string-header change first, as in S2. |
| C | S3-A | after C, T1 and T2 merge; M may still be running. |
| X | S3-X | after all packages. |

## 5. Gates and tools

The table in the S2 plan §5 applies unchanged, with three changes.

**1. `test-core` runs as 4 shards by default.**
- Keep it under 5 minutes. If S3's new tests push a shard past about 90 s, raise
  `-Dcore-shards`, or move end-to-end fixtures into the conformance pins instead of
  `test-core`.
- Measure with the gate slot held (S2 rule 9).

**2. Rows.**
- `experiments/new-core-s2-20261005/wave-b/integration/measure_all35.py` extends to the
  five applications, becoming `measure_all40`.
- Report ratios against Zig ReleaseSafe and against the old core.

**3. Fuzz.**
- `experiments/new-core-s2-20261005/wave-a/integration/fuzz_qualification.py` gains
  kinds for the new text methods and for float text.
- Packages run 50 cases of their kinds; S3-X runs 200 of every kind.

**What runs the full old-core gate:**
- S3-L;
- any package that touches files outside `src/core/`;
- S3-X once.

## 6. Rules

Every rule of the S2 plan §6 and its "Status after Wave A" list still applies. These
are the ones worth restating, plus the rules new in S3:
- **A wrong answer is never acceptable.** Match the old core, or refuse precisely with
  `E_CORE_UNSUPPORTED`.
- **Never edit `tests/lang/`,** except S3-L for D2.
- **`ir.zig` is frozen after S3-0.**
- **No record phi is emptied** (`NEW-CORE-RC-12`).
- **Leak and verify sweeps check exit status and stdout,** not stderr only.
- **Persisted formats:** bump the version of any format a package changes. Today's are
  `module-interface-v5`, `check-summaries-v6` and `mutation-v2`.
- **Parameter positions:** aggregates must be within the first 64 (`ORIGIN-WIDE-1`).
- **Fact-driven code needs verify asserts.** S2's review added parameter-range asserts
  at function entry. Every new fact, uniqueness claim and stack promotion needs the same.
- **New in S3: I/O is deterministic in tests.**
  - Fixtures that touch files use a private temporary directory per test.
  - Clock and entropy go through the test runner's stand-ins.
  - No test reads the network.
- **New in S3: the no-regression gate against the old core** (§2).
- **The rebuild stop (amended 2026-10-06).** The S2 rule "a rebuild takes over 10 s"
  means a `mylang-core` rebuild (`zig build core`), measured with the build slot held
  and no gate running. It is the new core's edit-loop budget.
  - Rebuilds of the old `mylang` compiler are not gated. It took 20–31 s on 2026-10-05.
  - A rebuild timed while a gate or another build runs is not evidence. Remeasure it
    under those conditions before stopping.
  - Wave A stopped on a 12 s old-compiler rebuild timed during the full old gate. That
    was not a stop.
- **One log file per command run.** Never redirect a later run into an earlier run's
  log; evidence must survive.
- **Machine rules:**
  - build slots for builds and the gate slot for gate steps;
  - timing only on CPU 10, never CPUs 2, 3 or 11;
  - never prune `runtime-baseline-20261003`.
- **Branches:** no pushes, and nothing merged into `main`.

## 7. S3 exit check and report

**Exit:**
- **Applications:** the five application rows build, match and pass both gates.
- **`tests/lang`:** passes in full under the new core at debug and release, except:
  - tests that need user modules, which are S4 and listed by name;
  - the retired arena tests.
- **Fuzz, leaks and the old gate:**
  - the strict 200-case fuzz matrix over every kind;
  - full leak and verify sweeps clean;
  - the full old-core gate green.
- **Coverage:** before and after, with every remaining refusal reason.

**The report records, in the design note and in `experiments/new-core-s3-*/`:**
- commits per package;
- the 40-row table against both gates, with count updates in inner loops;
- conformance numbers and the S4-only list;
- the dev-loop times (rebuild, test-core);
- every remaining limit.

S3 then stops for the user's go/stop decision on S4 (modules, incremental builds, the
Lox port and an EDA slice).
