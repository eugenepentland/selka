# Plan to reach the fastest runtime baseline

Audit date: 2026-10-03. Scope: **all 35 microbenchmarks, both sizes, both MyLang backends**, plus the five composed applications. This is a source and generated-code audit and implementation plan. No compiler, runtime, library, benchmark port, or measured baseline was changed, and no implementation agents were started.

The goal is useful, but reaching it everywhere requires compiler work as well as runtime work. It is particularly ambitious for QBE: several gaps involve constant division, calls, checked loops and vectorization. Faster allocation alone cannot close them. The changes below are candidates with evidence and validation requirements, not promised speedups.

[Every small/large comparison](measurements.md) · [Exact targets and audit evidence](evidence.json) · [Original assessment](../assessment/README.md)

## What counts as reaching 1.00

Freeze the fastest **original median for each case and size** as its target. The evidence file records all 80 targets, their units and reference configurations. A candidate's time divided by this fixed target can be less than 1.00. A dashboard renormalized to the fastest *current* configuration cannot show a value below 1.00; retain that dashboard for comparison, but use the fixed-target ratio to track progress.

There are 140 microbenchmark targets: 35 cases × two sizes × LLVM/QBE. Keep the 20 application targets alongside them. Each target must be assessed separately; a large win elsewhere does not offset a failure. Small cases matter: for example, `mutate_shared` is 11.33×/16.00× at the small size despite being 3.41×/4.23× at the large size.

For each candidate report two comparisons:

1. Candidate / frozen target, which measures progress against this request.
2. Candidate / the same reference configuration rerun in the same session, with randomized paired rounds, which checks that a changed host or toolchain did not create the apparent gain. Rerun all six configurations at milestones to identify a new competitor winner.

The numerical goal remains **≤1.00 on every target**. A confidence interval overlapping 1 is inconclusive, not proof of parity. A ratio within 5% can be labeled “near target” for triage, but does not satisfy the goal. Reserve “demonstrated faster” for a repeated same-session comparison whose upper confidence bound is below 1. Independent confirmation runs are needed because winner selection and repeated tuning bias exploratory results; retain the old report's explicit statistical limitations. Never pair new rounds with archived rounds as though they ran together. Matching a frozen historical number alone cannot establish same-session competitive parity.

Preserve MyLang's overflow, bounds, conversion, error trace, frame-limit, ownership, arena and snapshot behavior. The source explicitly rejects `--unchecked`. Optimization must prove checks redundant or retain an exact fallback, including observable failure order. Audit allocation-budget and resource-limit observability before introducing allocation elision. If a required semantic cost prevents a target, document the remaining cost and keep that target open.

## Evidence and the most useful findings

The measured compiler source is `6df58b02554401f9d37564cceffd14277a835ae1`; the benchmark-source snapshot is `b725360f5f86ac67bc405db9407ae51c332a9931`. At audit time, `src/` and `vendor/qbe/` match the compiler pin. All 24 saved guest executable hashes match the baseline. The audit reviewed all four MyLang ports and relevant reference implementations, extracted 14 functions from cached IL/manifests and inspected the corresponding executable disassembly. No fresh per-microbenchmark CPU profile has yet been collected. The first implementation milestone closes that attribution gap.

**Current-main reconciliation:** the local `main` branch has advanced to `1fd1d566793dcae92449d937aca595c55ee318c8`. The source-matching statement above refers to this audit worktree, not that newer branch. Its 33 changed source files include guarded positive list-index reads (`qbe_positive_index.zig`, commits `406c7eeb`/`f924e2ee`), direct closed-record field-inout calls (`rc_field_inout.zig`, `ac54b90b`), and checked QBE variant transfer/release policy (`native_variant_policy.zig`/`qbe_rc_native_variant.zig`, `d22f7fa7`). The new variant path covers edge-free active cases of eligible small **counted** variants, not every plain Int/Bool stack operation; LLVM retains the original policy. The relevant Git blobs and changed-file list are recorded in `evidence.json`.

P0 must first build and measure that newer main under a new identity against the original frozen targets. Start implementation worktrees from the reconciled main and extend its existing paths. Do not credit its gains to new work, reimplement these three mechanisms, or apply the old ratios to its binaries. The per-case tables below describe the measured old revision; current-main effects on this suite remain unmeasured. Refresh the package priority after that initial run. Constant-division lowering, entry/Result inlining exclusions, generic equality, text/JSON runtime bodies and the other audited unchanged mechanisms remain relevant candidates.

These observations are confirmed; their share of each benchmark's runtime still needs controlled experiments:

| Evidence | Implication |
|---|---|
| [The bytecode inliner](../../../src/bytecode_inline.zig) refuses calls from the entry function because it cannot yet charge logical frames there. It also refuses functions returning `Result` because their error-return traces need the callee frame. The compute IL retains calls to `affine_a`, `score`, `optional`, `forwarded`, `search` and `decode`. | Implement frame/trace-preserving inlining and scalar aggregate handling. Increasing a size threshold alone does not remove these explicit exclusions. LLVM may independently inline some calls; inspect final code for each backend. |
| [Checked scalar lowering](../../../src/qbe_scalar.zig) emits overflow/division guards; [LLVM lowering](../../../src/qbe_build_llvm_lower.zig) already recognizes overflow intrinsics. [QBE instruction selection](../../../vendor/qbe/amd64/isel.c) lowers integer division/remainder to hardware divide. `optional` has one `idiv` in the QBE binary and none in LLVM; `search` has two versus none. | Add general constant-divisor lowering and range proofs. Do not propose “enable LLVM overflow intrinsics” as new work: they already exist. Static divide counts include all function paths, not frequency-weighted costs. |
| [Scalar loop admission](../../../src/qbe_rc_scalar_version.zig) is restricted to integer/bool/unit, rejects inline provenance and has a narrow opcode set. Existing byte/read/append certificates also accept specific shapes. | Extend sound loop facts and their composition rather than adding one special case per benchmark. Float loops and calls will need more than the current scalar certificate. |
| The text benchmark's `score()` executes `text.encode()` and then scans the result. [Encoding](../../../src/native_bytes.c) allocates a list/backing and copies UTF-8. The LLVM `score` body still calls list allocation and `memcpy`. Rust's `score` reads bytes by reference. | Split, join and formatting measurements include an additional allocation/copy in MyLang. Audit their components separately; optimize nonescaping encoded-byte consumption without changing frozen benchmark work. |
| [Text splitting](../../../src/native_text.c) already reserves the output list and uses bulk delimiter search. Short pieces are copied; Rust collects `Vec<&str>`. Join already measures output and allocates once. | “Reserve split output” and “make join one allocation” are already implemented. Focus on temporary ownership, small pieces, UTF-8 access and consumer fusion, with retained-memory tests for views. |
| Text equality goes through generic `myl_native_equal` in the audited text kernel. Its leaf path eventually uses length plus `memcmp`. Historical CSV/JSON samples repeatedly land in generic equality and `leaf`; these are separate sampled symbols. | Specialize known immutable text/byte equality in lowering and optimize character/literal comparisons. Do not assume the underlying byte comparison is missing or write a new `memcmp` first. |
| [Dictionary code](../../../src/native_dictionary.c) already has specialized scalar/text probes, cached hashes for owned text, a last-probe cache and a 5/8 load policy. [The RC allocator](../../../src/native_rc_alloc.c) already uses slabs. | Measure the remaining scopes, transfers, lookup/write paths and allocation metadata. Avoid proposing caches or a slab allocator that already exist. |
| [`json.my`](../../../src/stdlib/json.my) stores its cursor in a one-element list, builds decoded strings through `list[int]`, and quotes text by repeated string concatenation. `control_code` scans 32 control characters for each ordinary character. | There are specific general-library improvements beyond backend tuning: a scalar cursor, byte buffer/string builder, and direct control-character classification. Preserve the public JSON contract. |

Historical CPU captures are only hotspot hints: they were throttled and contain hundreds of samples, not precise attribution. Examples: CSV LLVM has 102/344 samples in `myl_native_equal` and 60/344 in `leaf`; JSON LLVM has 102/296 and 63/296 respectively. Lox LLVM has 235/327 in `execute`; QBE has 72/328 in a generated list-append helper. The saved counts and hashes are in `evidence.json`. These are not estimates of common-code coverage.

## Audit of every microbenchmark

The ratios below are **large-fixture LLVM / QBE runtimes relative to the fastest saved median**. The [measurement table](measurements.md) includes both sizes and the winning configurations; `evidence.json` preserves absolute times, units and intervals. Proposed changes refer to work packages P0–P9 below. A source operation or static call identifies a plausible cost; it does not establish that removing it will close the entire gap.

### Numbers and branches

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `integer_math` | 2.21 / 11.32 | Includes indexed reads, checked arithmetic, floor division by 7, remainder by 1009 and a checksum. P1: reduce constant division/remainder and carry value bounds through the loop. P2: hoist invariant case selection and proven bounds checks. Inspect the timed loop for remaining divides and guards; validate negative operands and overflow outside the fixture. |
| `float_math` | 2.57 / 15.17 | Includes int→float, arithmetic, float→int and checked accumulation; raw float arithmetic is already emitted directly. P1/P2: reduce conversion/helper and bit-cast traffic, prove safe conversion ranges and expose vectorizable iterations. Keep IEEE/NaN and conversion traps; do not enable fast-math or reassociation to win this exact-dyadic fixture. |
| `branch_predictable` | 3.21 / 13.71 | One rare false flag per 16 entries plus indexed flag/value reads. Common compute dispatch and checks may dominate the branch itself. P2: loop unswitching, invariant loads and safe bounds/range facts; evaluate branch versus select using final machine code. Test additional branch patterns, not only this periodic one. |
| `branch_mixed` | 2.23 / 9.93 | Similar work with mixed flags. P2: same loop improvements; compare cycles and branch misses to determine whether select/vectorization is useful. A rewrite that wins predictable branches can lose here, so these are a paired acceptance gate. |

### Lists and iteration

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `list_scan` | 1.55 / 4.59 | A whole-list reduction includes `(value + batch) % 1009`; it is not a pure load-bandwidth test. P1/P2/P4: optimize modulus, borrowed iteration and stable storage/length access. Separate iterator overhead from arithmetic with a diagnostic scan; retain both checked iteration and mutation-invalidates-iterator tests. |
| `list_append` | 2.21 / 4.86 | Creates a fresh dynamic list, appends, then performs an indexed weighted fold. P4: prove freshness/uniqueness once, keep capacity-sufficient append as direct stores and move slow growth out of line. Infer reservations only when semantically legal; measure the fold separately. Test growth boundaries, aliases, relocation and failure cleanup. |
| `list_filter` | 2.35 / 5.81 | Builds the input list, filters into a second list and folds it. The result combines construction, filtering and allocation. P2/P4: reserved construction and direct append for fresh lists; explore producer/consumer fusion only after proving value, failure and iteration semantics. Test empty/all/alternating matches and retained input aliases. |
| `mutate_unique` | 1.69 / 9.47 | Repeated indexed writes into a unique list plus arithmetic; QBE also pays expensive scalar lowering. P1/P4: propagate unique ownership through loop backedges and remove redundant COW/scope operations while retaining index checks unless proved. Use `mutate_shared` and aliased-mutation tests as counterexamples. |

### Strings and bytes

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `bytes_scan` | 1.00 / 9.50 | LLVM already leads at both sizes. QBE's audited byte helper is scalar and contains ownership/check machinery. P2/P4: borrowed contiguous iteration and provable reduction bounds. If a scalar loop cannot match LLVM, P9 must supply general vector support or a recognized bulk reduction; preserve the LLVM win. |
| `string_equal` | 1.45 / 23.26 | Small is 5.30 / 12.00; case covers equal, early-different and late-different strings. Generic equality remains in the emitted kernel. P6: direct text-leaf lowering, length/pointer checks where valid and borrowed operands. Measure comparison versus RC/dispatch separately; preserve Unicode byte equality and keep NaN-sensitive structural equality on its existing path. |
| `string_search` | 1.04 / 1.00 | LLVM wins small, QBE wins large. Bulk search and scalar-index conversion already perform well. P6 maintenance target: remove surrounding overhead only with evidence; protect empty needle, long-prefix misses and non-ASCII index semantics. No algorithm replacement is justified by this baseline alone. |
| `string_split` | 7.81 / 9.57 | Reserved result list exists, but short owned pieces and per-piece `score().encode()` allocate. P6/P4: remove temporary encoding for read-only consumers, then evaluate compact short strings, batch ownership or safe split views. A view header per token may remain expensive; simply lowering the view threshold is not a complete solution. Test source lifetime, tiny pieces from huge owners and escaped results. |
| `string_join` | 1.75 / 2.14 | Join already allocates output once. The timed fold encodes and scans it afterward. P6: eliminate that nonescaping copy and redundant ownership/scalar-count work; tune copy loops only if they remain hot. Check empty pieces/separators, Unicode scalar counts, overflow and result lifetime. |
| `int_parse` | 2.09 / 3.71 | Current parser reads UTF-8 directly without allocation but supports a wider grammar than the fixture exercises. P6/P3: specialize the common decimal path, efficient overflow detection and scalar Option consumption, preserving whitespace/underscore/sign rules through the same canonical parser contract. Test min/max, overflow, invalid suffix, empty input and non-ASCII rejection. |
| `int_format` | 4.61 / 6.01 | `str(int)` uses a generic scalar-kind dispatcher, a 1024-byte temporary, decimal formatting and UTF-8 construction; the score then copies bytes again. P6: a dedicated integer helper with a small bounded buffer and known-ASCII construction, plus nonescaping-byte consumption. Inspect whether the compiler already folds individual steps; test zero, negatives and the minimum integer. |

### Dictionaries and sets

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `dict_lookup` | 1.77 / 2.59 | Read-only hit/miss workload with scalar keys. Specialized probing already exists. P5: inspect emitted read scopes/borrows, entry indirection and probe/hash cost; specialize known key/value layouts only where it removes measured work. Test misses, collisions, deletion histories and storage invalidation. |
| `dict_lookup_str` | 1.68 / 2.39 | Keys are prebuilt decimal strings, and owned-text hashes are already cached. P5/P6: optimize borrow/equality/probe integration and avoid reloading dynamic type metadata. Add distinct-but-equal strings, views and varied key lengths before claiming broad string-map gains. |
| `dict_update` | 2.64 / 3.44 | Includes initial construction, get/update pairs, growth and a final item fold. Small is 6.15 / 8.57, suggesting fixed costs deserve attention. P5/P4: a sound combined lookup/write path, proof of fresh ownership, growth/reservation policy and cheap iteration. Verify whether the existing last-probe cache already avoids the second hash before adding a new mechanism. |
| `dict_update_str` | 1.67 / 2.04 | Includes string-key insertion/update, then membership plus lookup in the final scan. P5: preserve a probe across an immediately related operation only if no effect invalidates it; reduce text ownership and scope bookkeeping. Preserve key lifetime, insertion order, aliases, growth and failed writes. |
| `set_dedup` | 3.98 / 5.27 | Duplicate-heavy integer set construction; small is 11.90 / 16.27. P5: measure new-set setup and duplicate insert separately, then specialize payload-free entries and avoid work on existing keys. Keep general hashing; a bitmap specialized to this fixture's bounded keys would not fulfill the language goal. |

### Records and calls

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `record_reads` | 1.49 / 3.17 | Reads two scalars and `payload[0]` from a record with a managed list field, plus modulo/checksum work. P3/P4: borrowed record projection, no whole-record ownership transfer, and frame-safe helper inlining. Keep the managed payload alive; test nested field lifetimes and aliases. |
| `record_construct` | 2.53 / 10.35 | A three-int record is constructed then passed to `score`. Do not assume it is heap-boxed: inspect aggregate stack storage/copies. P3: scalar replacement, direct field forwarding and frame-safe inlining; P1 handles arithmetic. Validate escaped/returned records and original trap positions. |
| `record_update` | 2.84 / 15.13 | Copies a record from the fixture, changes all three fields locally and scores it; the original list must remain unchanged. P3: dead-field/copy elimination and scalar record updates; compose existing plain-record-write machinery. Test partially updated and managed-field records so optimization does not mutate an alias. |
| `call_direct` | 4.02 / 24.34 | `affine_a(x + phase)` is called from `main`, where bytecode inlining is explicitly disabled. P3 is the primary remedy: preserve logical frame charging and inline the scalar helper. P1/P2 then expose a compact loop. Moving only this benchmark into a different caller is a diagnostic, not the compiler fix. |
| `call_indirect` | 1.69 / 7.95 | A function pointer is selected from two functions using the runtime seed. P3: efficient scalar indirect-call ABI; optionally guarded devirtualization/loop versioning when the possible targets are proved. Add truly changing targets and captured closures to prevent a static-target-only improvement from being overgeneralized. |

### Optional values and errors

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `tagged_stack` | 4.37 / 5.52 | Repeated pop/push/update on `list[Value]`; the Int/Bool union has no managed payload, yet collection operations still require ownership machinery. P4/P3: typed plain-variant append/pop, tag/payload scalarization and proof of stable unique capacity. Keep a general dynamic stack; do not hardcode its fixture length. Validate managed-payload variants as a separate fallback. |
| `option_handle` | 5.21 / 29.09 | Calls `optional`, constructs/matches a scalar Option and uses `% 4`. The QBE helper retains hardware division and aggregate setup. P1/P3: constant remainder, frame-safe inlining and scalar tag/payload propagation. Never label every Option as heap allocation; confirm layout first. Test both branches and escaped Options. |
| `result_propagate` | 4.51 / 21.00 | `checked` returns Err one time in five; `forwarded` uses `?`. Unlike the references, MyLang records error-return trace origins/propagation. P3: integrate logical trace metadata into inlining and optimize trace recording/consumption where provably unobservable. Retain full error traces and frame limits. Arithmetic and representation improvements may not remove all semantic overhead. |

### Allocation and ownership

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `alloc_short` | 18929.50 / 25384.72 | The fastest large result is about **3.715 ns per whole pass**, including 1024 logical short-list constructions; the small pass is also about 3.745 ns. This is an optimizer/elision target, not an allocator-throughput target. P7 must establish legal escape analysis, scalar replacement and loop simplification. Validate final reference assembly and budget/trap observability before promising parity; add an escaping companion rather than forcing artificial barriers into the frozen test. |
| `alloc_retained` | 2.28 / 3.34 | Inner four-int lists are retained in an outer list and traversed before destruction. P4/P7: count header/backing allocations, transfers and teardown; consider coallocation or lifetime-based batch allocation only after proving ownership/region behavior. The existing allocator already uses slabs. Check peak/live memory, retained aliases and mixed lifetimes. |
| `mutate_shared` | 3.41 / 4.23 | Preserves a snapshot while updating a list. MyLang COW and reference deep clones provide the same values with different physical work. P4: optimize the unavoidable clone path and ownership transitions; P7 may shorten snapshot lifetime if observations permit it. Preserve general snapshot behavior and benchmark longer-lived, escaping snapshots. |
| `mutate_nested` | 1.00 / 1.18 | LLVM already wins both sizes; COW has an advantage over explicit deep clones here. P4 maintenance plus QBE overhead removal: copy only necessary containers/path nodes and avoid redundant edge work. Test snapshots that outlive multiple mutations and inspect retained memory; do not trade a value-semantics win for aliasing. |

### Sorting and searching

| Case | LLVM / QBE | Audit and planned change |
|---|---:|---|
| `sort_int` | 1.00 / 1.28 | LLVM wins large, but small is 1.65 / 3.18. Includes constructing the input and folding sorted values. Existing specialized native sorting is already competitive. P4/P8: isolate setup/sort/fold, reduce small-input allocation and dispatch, then tune algorithm thresholds only across varied distributions. |
| `sort_records` | 1.19 / 1.91 | Stable sort with a key function, record construction and weighted fold. MyLang already has specialized keyed/counting/merge paths. P3/P8: reduce key-callback and key-materialization overhead, scalarize construction and improve small-input scratch handling. Verify stability via original ordinals and test wide/duplicate/reverse keys. |
| `binary_search` | 2.02 / 17.40 | Repeated searches include midpoint `// 2`, checked index arithmetic, function calls and input-dependent control flow. QBE's search body contains two hardware divides. P1/P3/P2: strength reduction, helper inlining, proof of `low <= middle < high <= len`, and safe midpoint/range handling. Test empty, singleton, missing and extreme values; do not rely on this fixture's arithmetic sequence. |

## The five application checks

These remain required downstream checks because matching isolated operations does not prove application performance. They also have their own targets.

| Application | Large LLVM / QBE | Plan and diagnostic split |
|---|---:|---|
| `word_count` | 8.56 / 11.56 | P4/P5/P6: token production, repeated lookups/updates, scope capture and final text scoring. Saved profiles point to `probe_text`, dictionary scope capture and ownership/unwinding as well as `word_job`. Measure tokenize/count/fold separately. Preserve five distinct words in the existing fixture; add a high-cardinality holdout. |
| `csv_aggregate` | 7.44 / 10.83 | P6/P5: per-character string values, generic equality, repeated concatenation, row/field allocation and grouped updates. Prefer general character-comparison and builder optimizations that accelerate the unchanged port. A byte-buffer rewrite of the benchmark alone is a separately versioned idiomatic-library experiment, not evidence that the original compiler target passed. Preserve the declared quoted-comma/doubled-quote grammar. |
| `json_transform` | 24.88 / 33.46 | P6/P8: replace the standard library's 32-character control scan with direct byte/code-point classification; use buffered quoting/serialization, efficient string spans and a scalar scanner cursor. P3/P4 reduce Result, record and ownership costs. Split parse/transform/serialize/fold diagnostics and test the full JSON library contract, not just this schema. |
| `packet_decode` | 2.50 / 12.60 | P1/P2/P3: bounds/range proofs after header validation, byte accumulation, Packet/Result scalarization, inlining and preserved error traces. The fixture is 75% errors; error-path costs are deliberately hot. Test valid, short and each invalid category separately without changing the frozen mix. |
| `lox_eval` | 7.11 / 7.78 | P3/P4: unique operand/return stacks, allocation-free plain-variant push/pop when capacity suffices, local variable access and dispatch simplification. Recheck final machine code and runtime transfers; do not specialize to the fixed bytecode sequence or remove dynamic stack semantics. Extend validation to differing instruction streams. |

## Implementation work packages

P0 is a prerequisite for accepting an optimization. Each other package starts with a small measured experiment, then generalizes the successful mechanism. No package is considered complete merely because its predicted hotspot disappears.

### P0 — Reproducible targets and attribution

Extend the benchmark tooling to accept a candidate compiler/source identity alongside the immutable reference. The current runner records a hard-coded main revision and the verifier requires that revision; this metadata is not an independent proof that a supplied compiler was built from it. A changed compiler must receive a new explicit source/build identity and output location; do not relax checks or substitute its binary under the old revision. First measure reconciled current main, including its selected QBE native-variant policy, before evaluating new changes. Store fixed-target and concurrent-reference ratios separately. The existing assessment assumes a complete inventory; focused runs need a focused comparison path instead of masquerading as full assessments.

Add optional microbenchmark profiling: the current `expanded/profile.py` CLI accepts only the five applications. Use task-pinned, checksum-verified guest runs with per-case duration calibration, not full-program instruction counts. Collect cycles/instructions/branch/cache counters when permitted; otherwise record that hardware counters are unavailable and use lower-frequency sampling plus disassembly and allocation/RC instrumentation. Keep instrumented timings separate from performance measurements. Lower sampling frequency to avoid the old throttling and report loss/throttling honestly.

Create paired diagnostic variants for dispatch outside the inner loop, arithmetic without collection access, collection access without arithmetic, text operation without `score().encode()`, and explicit escaped allocation. Apply workload changes consistently across languages and label them diagnostic/versioned. They identify costs; they do not replace failing original rows. Inspect optimized reference assembly for `alloc_short` and inlined/direct-call cases before setting instruction-level expectations.

**Deliverables:** candidate-aware comparison, source/binary/flag receipts, all 80 fixed targets, a causal attribution note per family, assembly/IR extracts and available counter/allocation evidence. Validate report math with synthetic candidate data that wins, loses, ties and changes winner. Preserve all original checksums and evidence.

### P1 — Arithmetic and constant division

**Primary files:** `src/qbe_scalar.zig`, `src/qbe_loop_facts.zig`, `src/qbe_loop_version.zig`, `src/qbe_build_llvm_lower.zig`; use `vendor/qbe/amd64/isel.c` only if a backend primitive is required.

Implement powers-of-two and general constant-divisor division/remainder lowering for supported widths/signedness. Share quotient/remainder work where valid. Preserve flooring versus truncation, negative operands/divisors, division by zero, `MIN / -1`, and the nontrapping `MIN % -1` result. General constants may require multiply-high support; establish that capability explicitly instead of assuming ordinary low-word multiply suffices.

Carry bounds through constants, casts, induction variables and expressions so redundant overflow/cast checks disappear. Preserve exact slow paths when facts are insufficient. Inspect float conversion/bitcast costs without weakening IEEE behavior. Do not copy all LLVM optimization work into text-pattern replacements in emitted IL; prefer typed facts and bounded passes.

**Gate:** semantic differential tests against the VM/reference arithmetic, boundary and randomized cases, no unexpected divide in the demonstrated constant cases, improvements in arithmetic/iteration/search targets on both backends and no regressions in result/checksum semantics.

### P2 — Loop facts, invariant dispatch and vectorization readiness

**Primary files:** `src/qbe_loop_facts.zig`, `src/qbe_loop_operands.zig`, `src/qbe_loop_version.zig`, `src/qbe_rc_scalar_version.zig`, `src/qbe_rc_read_version.zig`, `src/qbe_rc_byte_version.zig`, current main's `qbe_positive_index.zig`, LLVM emission metadata where justified.

Canonicalize induction variables; prove stable storage/length, index ranges and loop invariants. Move invariant dispatch outside a loop when legal and bounded for code size. Compose scalar/read/byte certificates with inline provenance, floats and plain records where sound. Remove ownership operations only after their lifetime conditions are proved. For guarded fast loops, guards must themselves be safe and the original fallback must preserve the first observable failure and partial mutations.

Use optimized LLVM IR/remarks to identify the actual vectorization blocker after simplification; only add alias/no-overflow information when proved. Test version guards, break/continue, empty loops, overflowing induction variables, aliased buffers and calls that mutate storage. Measure compile time and code size because the audited collection dispatcher is already large.

**Gate:** smaller measured hot loops, reduced executed instructions/branches, stable semantics and paired predictable/mixed results. Remaining QBE vector gaps become explicit P9 work rather than an unfulfilled “enable optimization” suggestion.

### P3 — Calls, records, Option and Result

**Primary files:** `src/bytecode_inline.zig`, `src/qbe_frame_map.zig`, `src/qbe_frame.zig`, `src/qbe_error_trace.zig`, `src/qbe_aggregate.zig`, `src/qbe_rc_plain_record_write.zig`, LLVM aggregate ABI lowering.

First implement logical frame-depth accounting for inlined calls from the entry function, including `--max-frames` and trap provenance. Then admit those calls under a code-size budget. Add scalar replacement/forwarding for nonescaping plain records and tag/payload pairs; inspect existing layouts before changing ABI. Eliminate proven dead temporary initialization without exposing uninitialized bytes at observable boundaries.

Result-returning functions require origin and propagation trace metadata through inlining. Optimize recording only after defining when a handled/discarded error trace is observable; retain exact traces wherever it is. Do not globally switch traces off. Handle indirect calls through a small typed ABI; guarded specialization needs a general fallback and must also pass changing-target/captured-closure tests.

**Gate:** direct-call and variant loops improve, record aliases remain unchanged, precise error/trap traces and frame limits agree before/after, and entry/cross-module/cache reuse tests pass. Inlining must compose with P2 rather than accidentally disabling its loop certificates.

### P4 — Borrowed reads, unique mutation and collection primitives

**Primary files:** `src/rc_readonly_calls.zig`, `src/rc_borrow_flow.zig`, `src/qbe_rc_read_loans.zig`, `src/qbe_rc_unique.zig`, `src/qbe_rc_append.zig`, `src/qbe_rc_append_loop.zig`, `src/qbe_rc_element_take.zig`, `src/native_collections.c`, `src/native_cow.c` and generated RC glue. On reconciled main, also account for `rc_field_inout.zig` and `qbe_rc_native_variant.zig` rather than rebuilding their existing certificates.

For read-only traversals, keep one proven live owner and borrowed element access instead of repeated captures/transfers. For fresh unique lists, put capacity-sufficient append/pop/index updates on a direct path with typed stores and no per-element managed work for pointer-free payloads. Extend existing paths; do not replace generic append/ownership semantics. Verify length, generation and relocation rules and retain growth, alias and held-reference fallbacks.

Optimize COW clone bookkeeping and nested path copying using actual live aliases. Separate removable RC bookkeeping from required reclamation. Measure allocations, bytes copied, retain/release/scope calls and live memory on diagnostic builds; report end-to-end timings from ordinary builds.

**Gate:** list/record/tagged-stack targets improve and Lox follows; alias/snapshot, arena escape, trap cleanup, managed payload, allocation refusal and reclamation tests stay correct. Preserve the existing `mutate_nested` and `bytes_scan` wins.

### P5 — Dictionary/set paths

**Primary files:** `src/native_dictionary.c`, `src/qbe_rc_dictionary_loop.zig`, `src/qbe_rc_dictionary_text_loop.zig`, `src/qbe_rc_dictionary_key.zig`, `src/qbe_rc_dictionary_tail.zig` and their typed planning counterparts.

Measure setup, probe, get/update and iteration separately. Remove redundant scope/ownership work for fresh or read-only maps; preserve the existing last-probe cache safely across related operations. Specialize hot key/value layouts and payload-free sets where dynamic metadata survives codegen. Add reserve/build-capacity inference only if it respects evaluation and failure contracts. Consider a different control-byte/group-probe table only if probing remains the measured limit after these changes; it is a larger design experiment, not the first patch.

**Gate:** integer and text hit/miss/update workloads, insertion order, collisions, tombstones, view/equal-distinct keys, clone/alias mutation and failed writes. Validate the high-cardinality holdout and `word_count`; fixed small-key tests alone cannot approve a new hash/table design.

### P6 — Text equality, byte consumption and conversions

**Primary files:** `src/qbe_managed.zig` (the equality branch around `myl_native_equal`), `src/qbe_text.zig`, `src/qbe_bytes.zig`, `src/native_text.c`, `src/native_equal.c`, `src/native_bytes.c`, `src/native_format.zig`, `src/number_text.zig`.

Start with known text/byte equality lowered directly to leaf operations, bypassing unnecessary generic dispatch and failure bookkeeping. Optimize one-character text comparisons/iteration using code-point facts where no identity or escaped text requires materialization. Keep arbitrary Unicode and general structural equality correct.

Next, recognize read-only nonescaping `encode()` consumers and borrow UTF-8 storage under a lifetime certificate. If a view must escape, it needs a valid owner and representation; do not return a dangling pointer or silently retain huge inputs without memory tests. This benefits split/join/format and applications. Improve short-text construction or split representation only after measuring residual per-piece allocation. Reserve-and-copy join and preallocated split already exist.

Add specialized integer formatting into a ≤20-character decimal payload (plus any internal terminator/storage requirements), with known ASCII metadata; signed minimum needs careful magnitude handling. Optimize the canonical decimal parser's common path without narrowing its grammar. Preserve VM/native agreement.

**Gate:** all seven string/byte cases plus Unicode/UTF-8 boundaries, view ownership, escaped output, retention, integer extremes and full parsing grammar. Demonstrate separate wins for the operation and its encoded-byte consumer; protect string-search and LLVM byte-scan performance.

### P7 — Escape analysis and allocation reduction

**Primary files:** typed/bytecode ownership planning, `src/qbe_list_literal.zig`, `src/qbe_rc_fresh_constructor.zig`, `src/native_collections.c`, `src/native_rc_alloc.c`. Introduce a dedicated analysis module if required instead of expanding a pattern-specific file beyond its role.

Prove nonescape and observable lifetime before stack promotion/scalar replacement of fixed small collections. Then enable dead allocation, store/load forwarding and loop simplification. Escaping, aliased, captured, returned or trace-visible collections retain correct storage. Allocation budget, arena and resource-limit behavior need an explicit semantic decision backed by current specification/tests before eliding events. This is the largest feasibility uncertainty for `alloc_short`; an allocator patch cannot deliver a 19,000× gain by itself.

For retained objects, investigate fewer header/backing allocations and cheaper teardown using measured lifetimes, without assuming all application objects die together. Keep a general fallback. This package depends on P3/P4 and should not begin as a wholesale allocator rewrite.

**Gate:** no heap allocation in eligible simple local probes when legally eliminable, correct boundary/escape counterexamples, retained-allocation throughput and peak-memory checks. Keep `alloc_short` marked open until the measured full-pass target is reached; its optimized-away nature is an explanation, not a waiver.

### P8 — Library and application carry-through

**Primary files:** `src/stdlib/json.my`, `src/native_collections.c` sort routines, compiler support from P3/P6 where necessary.

JSON: replace control-character scanning with direct classification; write quoted/serialized output into a growing byte buffer or builder; scan contiguous input spans, decode only escapes, and replace the list-backed cursor if mutability semantics permit it. Keep public result/error behavior, object order, number spelling, depth limits, escapes, malformed-input rejection and JSON meaning. Compare parse/transform/serialize components and then the unchanged full benchmark.

Sorting: measure setup, key extraction, sorting and fold; tune small-input scratch/thresholds and callback specialization before changing an already competitive large-input algorithm. Preserve stable record ordering and test sorted/reversed/duplicate/random/wide-key distributions. Native sort-library results remain library comparisons.

CSV and Lox: first apply compiler/runtime improvements to unchanged ports. Any subsequent source-level algorithm or API redesign gets its own versioned comparison across relevant languages and is reported as a library/application improvement. It cannot silently replace the original acceptance rows.

**Gate:** all five applications and the full library/semantic suites, plus holdout input shapes. This package can start with the narrowly scoped JSON control-classification change before the more invasive representation work.

### P9 — Remaining QBE backend gaps

After P1–P8, compare the remaining QBE hot loops with LLVM and the competitor's assembly. Classify each residual gap as scalar lowering, register spills/ABI, missed loop optimization or SIMD. The current evidence already makes `bytes_scan` a likely SIMD checkpoint, but scalar cleanup must be measured first.

For real vector gaps choose a general solution: recognize a proven bulk operation and call a vectorized runtime implementation, or add the requisite vector IR/codegen support and cost model. Preserve tails, alignment, aliasing and checked overflow. General loops that do not match a bulk operation may require a larger QBE/backend project. Calling LLVM-generated guest code and labeling it QBE would not satisfy this backend target.

**Gate:** match the remaining QBE rows under the recorded CPU policy and a documented portable policy, with correct fallback on unsupported CPUs. Report unresolved architectural costs explicitly. LLVM parity is a useful milestone but does not mark the two-backend goal complete.

## Order of work and Sol 6.1 handoff

Use **`gpt-6.1-sol`, reasoning effort `xhigh`**, when implementation is requested. Use at most three implementation agents plus the coordinator. Each agent gets its own worktree/cache, a bounded package, named acceptance rows and an evidence checklist. Assign one owner to each shared emitter/runtime file per wave; other agents send proposed interfaces or follow-up patches to that owner. Integrate dependency changes before downstream tuning, and serialize benchmark measurement so agents do not race for timing CPUs.

| Wave | Agent A | Agent B | Agent C | Integration gate |
|---|---|---|---|---|
| 0 | P0 candidate identity/reporting and micro profiling | P1 constant-divisor proof/design and a bounded prototype | P6 leaf-equality/code-point comparison prototype | Baseline replay, unchanged-port correctness and focused before/after evidence; no performance claim from diagnostics alone. |
| 1 | P1/P2 arithmetic and loop facts | P4 list/borrow/plain-variant paths | P6 equality, nonescaping encoding and integer formatting | Rerun affected micros on both backends; run Lox, CSV and text jobs; resolve ownership/lowering interfaces. |
| 2 | P3 logical-frame inlining, plain records and Option/Result | P5 dictionary/set paths, based on P4 | P8 JSON classification/buffering, based on P6 | Full 40-case × two-size milestone with all competitors; complete semantic and memory checks. |
| 3 | P7 escape analysis with P3/P4 owners assisting | P8 sort/snapshot/retained-allocation residuals, after explicit file ownership split | Independent validation and holdout workloads | Confirm wins on fresh paired runs; inspect small-size regressions and memory retention. |
| 4 | P9 residual backend work | Residual per-case investigations | Final independent comparison | Every individual target closed or explicitly still open; no aggregate score can declare success. |

The first prototypes should be **constant-divisor lowering, specialized text/character equality and unique plain-list operations**. They have concrete source/codegen evidence, affect many rows and can be evaluated in bounded changes. Frame-safe inlining follows as a larger cross-cutting change. Allocation elimination and QBE vectorization are research-sized work and should have explicit feasibility checkpoints rather than optimistic time estimates.

Each implementation handoff requires: observed cause; exact patch scope; before/after hot-code evidence; semantic tests and counterexamples; affected-row timings including small size; application results; memory/code-size/compile-time impact where relevant; and remaining uncertainty. Do not commit speculative optimizations solely because they are plausible.

## Validation that supports real applications

Keep the original fixture checksums, setup/timing boundaries, native APIs and six configurations. Save candidate results under a new identity. Use the build-slot wrapper, private cache and disk TMPDIR; keep timing CPUs quiet and record frequency/host contention. Preserve default CPU-policy results, and add a common-ISA sensitivity run for claims that depend on vector instructions. Do not silently enable native-only compiler flags for one competitor.

Run focused tests for each changed semantic mechanism, then the appropriate native/LLVM/QBE correctness and memory gates. At each integrated milestone run the complete suite, retaining randomized rounds, calibration receipts, no discarded inconvenient samples and absolute timings. Improve calibration for tiny/elided kernels before relying on their intervals; changing iteration count must still preserve the same per-iteration contract and checksum oracle. Stable reruns need not repeatedly rebuild or expand testing without a changed condition.

Add a compact holdout set before declaring broad application readiness:

- Unseen seeds and sizes, empty/tiny/boundary lengths, cache-sized and memory-sized working sets, and changed branch/error distributions.
- Long and diverse string/map keys, equal-but-distinct keys, collisions and deletion histories.
- Longer-lived snapshots, managed records/variants, escaped short lists and mixed allocation lifetimes.
- Different CSV/JSON shapes, more escapes/Unicode, varying nesting and high-cardinality word counts.
- Real indirect targets/closures, recursion or graph traversal, and different interpreter instruction streams.

Holdouts prevent fixture-specific optimizations from looking like general runtime progress. They do not establish a literal 80% population percentage. Concurrency, scheduling and I/O remain separate future workload classes. The immediate deliverable is both MyLang backends at or below each frozen runtime target, correct semantics, and evidence that the gains survive nearby application-shaped inputs.
