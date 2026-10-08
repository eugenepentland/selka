# Ordinary dictionary found-probe publication

This candidate starts from accepted `eaf4cda8f5c758cadafaadfa5e328c0fba252ac6`. The runtime change is limited to locate()'s successful ordinary probe: write key, entry and FOUND state while retaining the fields not interpreted under FOUND. All other publishers and all invalidation are unchanged. It is independent of typed lookup specialization. Production source is pinned at `64fb7e62732db9cea46414248fd59ba362e31b56`; the initial exploratory screen and independent repeat are complete. Source adoption and target confirmation belong to the coordinator.

| Probe state | Fields consumed | Consumers |
|---|---|---|
| NONE | no payload | every lookup refuses the hint |
| FOUND | key, entry | recall; entry bounds and actual stored-key equality are revalidated |
| ABSENT | key, slot, hash | locate; rc_insert_result after publication callbacks |
| FOUND_SPAN | key, entry, offset, bytes | recall_span through same_query; stored octets are revalidated |
| ABSENT_SPAN | key, slot, hash, offset, bytes, epoch | locate_span with matching query and valid heap epoch |

Each consumer checks its exact state before interpreting the payload. Ordinary found publication is the only changed writer. Ordinary absence, span found/absence, insertions and construction retain complete initializers. No prior stale span or slot/hash fields can become required by the new state. Future publication of any other state initializes its required fields as before. Dict tracing visits entries/index, not this untraced hint. Object layout/size, allocation, counters, roots, GC epochs and COW behavior remain unchanged.

The frozen G4 LLVM read_walk hit has required key/entry/state stores at0x105d855,0x105d85c,0x105d86e, plus an unused slot/hash clear at0x105d863 and vector clears at0x105d87c/0x105d884 (with zero-vector setup at0x105d878). The optimization removes the latter work without modifying generic probing, equality or value-copy dispatch. This is static causal motivation, not a measured fraction of lookup cost. Baseline inputs/ELF/disassembly are bound by the committed runtime-goal110-map-audit-20261004 evidence; accepted index14 collections allocated code is identical to G4.

Four focused native suites passed under GCC15 O2 plus ASan/UBSan: text/dictionary, RC collections, counted RC stats and the new native_dictionary_probe suite. The new suite executes four cases under each GC/RC mode: poisoned irrelevant fields and absent→found transitions; ordinary↔span transitions with heap collection and equal distinct texts; an actual constructed collision followed by delete/reinsert/settle; and real growth refusal preserving all accepted entries, output and allocation counts. Borrowed aliases share the correct receiver; an independent clone preserves separate values. Native executable paths/hashes, source snapshots, compile commands, status and streams are captured before/after invocation. The source-bound Debug host generated all 24 ordinary ReleaseFast guests. LLVM metadata confirms O3/full LTO. All 720 edge qualifications and 516 nearby holdouts passed. Actual optimized LLVM `read_walk` and `contains_walk` each shrink by 32 bytes (695→663 and 653→621); their found-hit paths retain key/entry/state stores and remove the redundant slot/hash clear, two vector clears and zero-vector setup. Matched frontend collections IL is identical.

Guardian's first whole-tree run rejected only an unverified new DICT-PROBE-FOUND-1 requirement tag despite native C coverage. C spec-case comments are outside its verified Zig test-root linkage. The invariant now refines existing PY-DICT-4, the same probe-cache contract; corresponding C comments changed without changing any runtime/test body. The original failed gate and passing native source binding are retained. No fake verification marker or gate relaxation was introduced. The corrected whole-tree Guardian run passed 88/88; the final source commit hook and Debug compiler build passed as well. The comment-only source reconstruction binds the earlier executed native semantic bodies to this final pin. Root independently replayed all four sanitizer suites and the final-source reconstruction.

The initial 14-row six-arm screen and 14-row matched current14→64 pairs both passed artifact, oracle and status checks. The initial matched LLVM ratios are 0.96436 for integer lookup small, 0.97328/0.98794 for string lookup small/large, and 1.01183/1.00818 for string update small/large. Stable LLVM nested-mutation and substring-search controls are near unchanged. All dictionary cells remain above the 1.10 current-fastest target. These five-round results are exploratory; the completed eight-row 15-round repeat used unchanged binaries and exact original calibrated plans.

An initial static helper failure was a diagnostic bug: it searched for found publication inside the public read wrapper, where no publication exists. The corrected helper restricts that test to the two actual publishing walk functions. Original helper/log and corrected result are retained; no runtime, compiler or guest bytes changed.

The independent matched repeat ran 15 measured rounds and 3 warmups per arm. Measurement UUID `b7da64b9-de9d-4d3d-8e23-f03eb229deb7` spans `2026-10-04T10:45:33.088679+00:00` to `2026-10-04T10:47:27.459712+00:00`; its driver UUID is separately `24a896a1-f4a1-4452-a5a2-d9a47cecefdb`. Initial paired measurement UUID is `20163cae-701c-4036-b7f6-b26c9fdc1483`. Timing records preserve parsed validated checksum, exit status, kernel/process durations, shuffled order and pre/post host counters. The runner validates the expected checksum and process-output format, but timing records do not retain stdout/stderr; full process streams are retained by the native-suite receipts. Artifacts and receipt identities passed before/after checks.

| Repeat case/size | LLVM candidate/control [95% interval] | QBE candidate/control [95% interval] |
|---|---|---|
| dict_lookup/small | 0.96528 [0.96152,0.96903] | 0.99429 [0.99206,0.99785] |
| dict_lookup_str/small | 0.98217 [0.97552,0.98568] | 0.98983 [0.98880,0.99086] |
| dict_lookup_str/large | 0.98622 [0.98227,0.99251] | 0.99759 [0.99222,1.00079] |
| dict_update/small | 0.99174 [0.98831,0.99490] | 1.00502 [1.00291,1.00770] |
| dict_update/large | 0.99379 [0.99116,0.99518] | 1.00364 [1.00104,1.00698] |
| dict_update_str/small | 1.01401 [1.00982,1.01658] | 1.01333 [1.00687,1.02115] |
| dict_update_str/large | 1.00916 [1.00405,1.01319] | 0.99396 [0.99008,0.99642] |
| set_dedup/small | 0.99388 [0.99028,0.99535] | 1.01624 [1.01244,1.01956] |

This is a bounded store-publication improvement, not the typed-lookup hypothesis. It repeats the small integer/string lookup gains and small integer-update gains, with approximately 1.4%/0.9% LLVM string-update costs and 1.6% QBE small-set cost. Those costs are retained explicitly. No dictionary row meets the 1.10 current-fastest goal; an integrated confirmation is still required after any source adoption. Compiled executables/caches remain in their pinned original paths and are excluded from this compact archive. Deterministic gzip reports and tar packs retain complete raw evidence and source/helper/tool identities.

Documentation correction: the initial archive README claimed full stdout/stderr retention for every timing sample. That claim was inaccurate; only the parsed validated timing outcomes above are retained. Native-suite receipts contain their full streams. Raw artifacts and source bindings are unchanged, and the original archive commit remains preserved.
