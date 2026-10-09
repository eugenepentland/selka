# P1 runtime and P2-0 report

**Status: P1 and P2-0 complete; final merged-source elapsed-time tax unverified by user instruction.** Work is on `codex/concurrency-p1`. Main `35df839be1bd836f91f5d40f3d5881848423ca9c` is integrated by real merge `1844fcc33`; no push or main/Claude modification occurred. P2-0 is analysis only; P2 has not started.

## Implementation and source identities

| Step | Commit | Result |
|---|---|---|
| P1-0 | `4673418f1`, `0034715e0` | Complete original runtime/global/count inventory and ABI feasibility |
| Revision-3 launch | `0ee93b396` | Requested fast-forward from claude/concurrency-plan |
| Main integration | `42041fa45` | Real merge of cafe7fea7 into P1; comparison base 94dc1c3a2 |
| P1-1 | `9c2559a45`, `5042d85a5` | Selected B2 count path and complete early correctness checkpoint |
| P1-2 | `9d2524f5e` | Per-thread runtime state, synchronization, stacks and fatal reporting |
| P1-3 | `020ee5422` | Common iterative child enumeration for sharing and destruction |
| P1-4 | `8a3782b05` | Lazy work-stealing scheduler and C-to-fastcc task bridge |
| P1-5 | `9f911528f` | Actual emitted-IR proofs and sanitizer build/cache integration |
| TLS selection/review | `f4eb26606` | Measured local-exec TLS; package review and P2-0 analysis |
| Native test linkage | `98cb3a49f` | Explicit C bridges and exit-status checks in old native harnesses |
| Final main integration | `1844fcc33` | Real merge of 35df839be; retain F1/S1, renumber P1 metadata |
| P1-6 selection | `c26c95de7` | Measured candidate C; stronger live-accounting proof |

The 32-byte header keeps plain/shared/immortal counts. LLVM reads are unordered; ordinary updates remain non-atomic, and shared updates use saturation-safe CAS. The emitted slow path is one preserve-most call with the selected 32:1 branch weight. Last-owner release uses acquire-release CAS, with release-only decrements for other owners.

Free lists, allocation cursors, traces, sites, stacks and counting slots are thread-local. Retired-thread records preserve accounting until process exit. Output is staged as complete units after worker startup; provider operations serialize. A fatal worker uses a bounded stream-lock attempt and raw stderr fallback, then exits without Host/provider cleanup.

Sharing and freeing use one child enumeration. The lazy pool uses Chase–Lev deques, round-robin stealing, helping waits and futex parking. It starts N−1 workers, publishes shared task results, keeps groups/handles alive through completion, supports post-close result handles and rejects unsafe fork paths. The real emitted bridge calls fastcc thunks; return PCs and current range-item indices identify task failures.

## Inventory and review

The original P1-0 inventory is preserved in [the historical report](HISTORY.md#2-accepted-p1-0-inventory-and-abi-findings), with its 103 declarations (97 definitions and six externs), every managed-count access and emitted global. [SELF-REVIEW.md](SELF-REVIEW.md) maps every state family to its owner/synchronization and reviews counts, sharing, fatal paths, scheduler lifetime, caches and scope. The [final committed-source typed inventory](r3/selected-inventory/inventory.json) finds **128 static declarations and eight managed count-access lines**, with successful object compilation and no source diff. Its known Zig AST-wrapper FileNotFound status is retained separately from the valid parsed AST.

There is no P1-authored change to the frozen front-end `src/*.zig`, `src/core/ir.zig` or `src/core/own.zig`: their final bytes exactly equal incoming main. `core_host.c` also equals main. Incoming F1/S1/row-COW changes are preserved.

## Correctness

All final gates below use committed implementation `c26c95de7`, with no source changes during qualification, fuzz or sanitizer repetitions.

| Check | Final result | Evidence |
|---|---|---|
| Full Debug gate / fmt | 88/88 steps; 2,144 executed tests; fmt passes | [checkpoint](r3/P1-final-03/summary.json) |
| Core qualification | 553/553 tests; 64 shards | [qualification](r3/P1-final-03/P1-final-03-qualify/summary.json) |
| Frozen conformance | 1518/0/0 in both modes | same qualification |
| Frozen fuzz | 9×50 and 9×200 pass; source/oracles unchanged; 209.02s / 620.55s | [50](r3/P1-final-03/fuzz50-matrix.json), [200](r3/P1-final-03/fuzz200-matrix.json) |
| Actual TSan fixtures | 100 repetitions × 3 programs at eight threads; 300/300, zero reports, 682.32s | [TSan](r3/P1-final-03-tsan/summary.json) |
| Counted/plain corpora | All 132 cells pass (48 Lox, 34 EDA, 4 parity, 46 rows) | [external](r3/results/P1-final-03-external.json) |
| Lox / EDA | VM 246/246 and tree 241/241, normal + stress; 65 Lox port tests; 310 EDA tests; 34 goldens | same external evidence |
| Every benchmark output | 45 parity arms and 26 Lox engine/case cells match exact expected bytes | [output checks](r3/results/P1-final-03-corpus-correctness.json) |
| Controlled proxy | 132 identical-path paired cells; zero exit live bytes in both arms; no timing verdict | [proxy](r3/results/final-deterministic-proxy.md) |

The final merged fuzz launcher first rejected uncommitted documentation drafts before running a case. Those drafts were preserved privately, the tracked tree restored, and both unchanged matrices passed. The rejected preflight remains in the checkpoint’s `failed_attempts`. The baseline ReleaseFast install also retained a stale-Guardian selfcheck failure and successful cached retry. No correctness gate or threshold was waived.

The first final full gate failed two old native-only C harness links, fixed in 98cb3a49f. The complete checkpoint at that commit passed full Debug (88/88 steps; 2,114 executed tests and seven cached), 530 Core qualification tests, conformance 1518/0/0 in both modes, frozen 9×50 and 9×200, external corpora and all 132 counted/plain comparisons. Its exact native/capture/range binaries passed 100 repetitions each at eight threads (300/300), with no reports, leaks or output mismatches. Runtime changes selected after that checkpoint require the fresh results above.

## Performance verdict: merged version unverified by user instruction

The user's final instruction explicitly allowed merging without repeating performance checks or using a proxy that does not require idle hardware. We skipped the new timed suite, kept every earlier result, and ran fresh correctness plus the deterministic proxy below. Numeric thresholds remain unchanged; **this package does not claim a passed merged-source tax gate**.

The selected runtime C was completely measured before the final main merge, against historical base `94dc1c3a2` (main `cafe7fea7`). Its core_rt.c bytes match the final selected runtime. The final compiler also includes upstream F1/S1/row-COW changes and metadata conflict resolution, so these historical ratios cannot certify final performance.

| historical corpus | cells | C geomean | cells >1.03 | load range | all cells/alignments |
|---|---:|---:|---:|---|---|
| rows | 92 | 1.0027158207 | 12 | 1.07–1.55 | [table](r3/results/P1-final-CD-tax-rows.md) |
| EDA | 34 | 1.0190069662 | 0 | 1.07–1.19 | [table](r3/results/P1-final-CD-tax-eda.md) |
| parity | 45 | 1.0035887383 | 1 | 0.99–1.08 | [table](r3/results/P1-final-CD-tax-parity.md) |
| Lox tree | 13 | 1.0145199288 | 2 | 1.00–1.20 | [table](r3/results/P1-final-CD-tax-lox.md) |
| Lox VM | 13 | 1.0024991900 | 0 | 1.00–1.20 | [table](r3/results/P1-final-CD-tax-lox.md) |

Those measurements use ReleaseFast compilers, CPU 10 under cpu10.lock, matching K=4/5/6 alignments, paired interleaved samples and recorded load; no own builds or stress overlap timing. Each cell is the median of its three batch ratios. Targets remain corpus GM ≤1.010 and every cell ≤1.03. Only C's historical VM corpus passes both strict targets; every historical C corpus is below the 1.03 premise boundary.

The final investigation tried A–G. A/B/F exceeded 1.03 on EDA and were rejected. C is simpler than E/F/G and has a complete sweep; G was interrupted after rows/EDA when main moved, with partial parity and no Lox results. D/E also remained below the premise boundary but left larger allocation/tree regressions. Exact patches, source identities, every table and all failed/partial raw samples remain in [HISTORY.md](HISTORY.md). Initial P1-6 ratios were rows 1.024664, EDA 1.026959, parity 1.029112, Lox tree 1.013767 and VM 1.006302; these failures are not erased.

## Deterministic work and code-size proxy

The [controlled proxy](r3/results/final-deterministic-proxy.md) compares main `35df839be` with package `c26c95de7` across **132 cells** and **52 plain binaries**. With identical executable/output paths, all outputs, allocation/free/copy/growth/call counts, and emitted-operation count/byte totals match; every counter run exits with zero live bytes. Rounded allocation bytes, realloc movement, peak live bytes and runtime-retain hook totals differ and remain explicit. The initial comparison exposed tag-dependent EDA path strings; it is retained alongside the corrected fixed-path run.

Code size grows: EDA .text is 1,067,670 → 1,203,286 bytes; Lox .text is 474,710 → 513,558; json::read_value is 7,286 → 8,338. These changes reinforce why this proxy cannot certify the time target. Exact per-cell deltas and ELF hashes/sizes are linked from the proxy report.

These checks run off the reserved timing CPUs, without a timing lock or quiet-hardware requirement. They can reveal extra counted work, wrong output or changed code size. They cannot measure instruction latency, cache effects or elapsed-time overhead.

## TLS model comparison

The complete paired 92-cell sweep used two verified archives of P1-2 commit 9d2524f5e, differing only in the C and LLVM TLS declarations. Initial-exec/base GM was 1.0150306005 (20 cells >1.03); local-exec/base was 1.0124433780 (18 misses). Direct paired local/initial GM was 0.9979028166, with load 0.47–1.98. Local-exec was selected; neither arm passed all tax targets. [All cells and alignments](r3/results/tls-rows.md) retain both arms.

## P2-0 and remaining limits

[P2-0.md](P2-0.md) finds no Core IR or ownership-pass gap. Existing helper calls, func_ref, records, boxes, loops and phis support group/submit/result and ordered map ranges. Hand-built proofs cover mixed managed captures/results, parent copy-on-write, repeated result reads, ordered values 100–131 and exact failing item 17 at 1/2/8 threads, including actual emitted LLVM under TSan.

P2 must implement checker confinement and Host/resource exclusions, all-exit group close lowering, thunk reachability, overflow-safe range boundaries, and CLI job/stack accounting. Workers, old deque rings, small-allocation chunks and registry records live for the process; shared marks remain permanent. Provider operations serialize, and fatal parallel exit skips external cleanup. P2 starts only after F4 and the user's go.

## Decisions and surprises

[DECISIONS.md](DECISIONS.md) records every choice, evidence and reversal. Material decisions include the B2 path after complete R9/R10 comparison; last-owner acquire CAS to provide synchronization this TSan can observe; persistent retired-thread records; one shared child iterator; retained old deque rings; a weak_odr hidden bridge; exact item reporting; and sanitizer salts in runtime, unit and foreign-object caches.

Older optimized native fixtures put side effects inside assert while NDEBUG was defined. Their old contention claims were superseded; the corrected fixtures explicitly enable assertions and verify eight live workers. A single million-task sanitizer group exceeded the existing RSS allowance, so the same 1,010,000 simple submits run in 100 groups of 10,000 plus the preserved nested/own-deque cases. No workload count or correctness threshold was relaxed. The later wall-time gate waiver is explicit above.

Files outside the expected list were logged: build_cap.zig supplies complete dynamic-print boundaries; driver.zig owns runtime assets and native flags; driver_cache_test.zig proves sanitizer cache separation; root_test.zig wires the tests; own_test.zig supplies C-only fixture bridges; and experiment helpers record exact evidence. New Core support/fixture files implement the sanitizer transformation and executable proofs. The final runtime selection adds no new production-file scope. Three experiment helpers provide reproducible fixed-corpus output checks, identical-path counter runs and the deterministic proxy.

Historical P1-0 and pre-revision P1-1 stops were superseded by the user’s revision/resume instructions. Premise failures in rejected candidates were investigated and avoided in selected C. The sole final gate waiver is the user-authorized absence of merged-source timing; it is not an inferred permission or a numeric pass. No other §9.1 hard stop remains.

## Evidence and reproduction

[EVIDENCE.md](EVIDENCE.md) describes archives, exact restoration and per-member hash verification. The final package contains 9,266,885 bytes. All final correctness evidence, failed measurements, build identities and commands are retained. Temporary caches and generated source archives are private and reconstructible. Guardian feedback was appended and committed in guardian-zig as `630743177`.
