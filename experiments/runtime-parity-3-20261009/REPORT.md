# Runtime parity Wave 3 — accepted with a performance waiver

Status: closed at the user's direction on 2026-10-10. Merge the fully correctness-qualified implementation into local main. The original complete performance exit is **not passed**: remaining performance work is explicitly waived, and known regressions are retained below. No push is requested.

The user instructed: “You can stop the perf and just say its good enough, just merge it, give me a report and then we can do the juice updates after”. This supersedes the launch's no-main-merge instruction and mandatory remaining performance work. It does not change test outcomes or claim unmeasured performance.

## Source and validation

Frozen baseline: `41ed360fb361c49938488ad111795bad8a726b73`. Accepted qualified source: `6a40a150a84e3bc4a0091a539618ee04e2ec1193`, incorporating main `e9011d9c6513f63ae02881d0cfc8258c668e6b5e`. Production files and the build graph match that qualified source exactly. Subsequent commits contain evidence/report changes. Qualification was published by `37520ccec`; partial timing and rejection evidence by `a6642034e`. The final evidence branch is `codex/runtime-parity-3`.

[Complete qualification receipt](X/gates-final-fix-main-serial-01/receipt.json): build 9/9; repository 95/95 steps and 2,519 passed tests; formatting 15/15; raw/additive conformance exactly matches frozen M0 with leak/fact verification; fuzz 1,800 cases; Lox 974 conformance and 65 port tests; EDA 310 tests and 34 goldens; 199 counting cells; 151 instruction comparisons, none above 1.03. The raw oracle's expected exit 1 records its four unchanged PROBLEM cases; it is not silently treated as exit 0. Repository scheduling is serial with fresh test verdicts, retaining all shards.

The accepted ReleaseFast compiler SHA-256 is `7489a2882613c21a2b02b542d046f7976b686850dc790cb4e2b1290c50f42944`. The proposed subsequent BOX-release patch is excluded. Its focused test passed, but its performance-probe build was cancelled at the user's instruction; no new performance result is claimed.

## Measured performance and accepted risks

Latest completed groups against the paired frozen base:

| Group | Final/base | Change | Final/Zig RS |
|---|---:|---:|---:|
| parity | 0.8919 | -10.8% | 0.6701 |
| lox/vm | 0.9120 | -8.8% | 1.4368 |
| lox/tree | 0.9946 | -0.5% | 0.9641 |
| eda | 0.9572 | -4.3% | 1.1047 |

The [complete available-results table](X/user-waiver-results.md) covers 105 completed parity/Lox/EDA cells and both observations for 92 row-size cells. [Machine-readable closeout](X/user-waiver-closeout.json.gz) binds the source and input hashes. Row batch 3 and remaining bounds/review did not run; there is no claimed three-batch final row statistic.

- **Tree release:** tree_build_walk/4096 is 1.075945 and 1.057436 of base in its two completed batches. Any third value would leave the prescribed median at least 1.057436. Exact-binary CPU8 diagnostics show 0.969926 instructions and 1.052926 cycles, with raw unscaled events and checked outputs. This is an accepted known regression, not classified as noise.
- **Lox tree/invocation:** 1.034206 of base. Further confirmation was stopped; its significance remains unresolved and is covered by the user's waiver.
- **binary_search/4096:** batch ratios 1.033443 and 1.027320; final classification remains unavailable.
- **Reference gaps remain:** text_ops/my is 1.7762× Zig RS (though 0.6703× its paired base); scan_split is 0.4506× RS; sort_builtin is 0.6179× checked Rust. EDA's group is 1.1047× RS, just above 1.10. Group averages do not certify every individual cell; the linked table retains every available per-cell miss.

Fresh compile timing increased about 3.17% on Lox and 3.78% on EDA, below the plan's 10% investigation trigger. These compile results are separate from runtime acceptance.

## Lane exits and remaining work

U2 removes read_constant's 3 retains and 3 releases: all 37 recorded VM counting cells now show zero. Whole-frame copies remain, so the 80% copy-reduction target is missed. The validated headline sites report: lox-vm-invocation-1500000: 10080000224 bytes, unchanged; lox-vm-method_call-500000: 4853334440 bytes, unchanged. The Lox VM group reaches 1.4368× Zig RS, meeting its 1.50 group target. EDA improves to 0.9572× base but misses the 0.93 lane target. Generated release is retained; no whole-program allocation-share guarantee is made.

For `labstation`, sampled allocation/release share is 24.30% → 24.00% (conservative attributed lower bounds), missing 15%. Text materialization share is 7.28% → 8.09%, missing the half-share target.

For `rds3+flat`, sampled allocation/release share is 23.62% → 22.16% (conservative attributed lower bounds), missing 15%. Text materialization share is 6.04% → 7.35%, missing the half-share target.

S2 meets scan_split's 0.75× RS target and improves text_ops substantially, while text_ops still misses 1.5× RS. Escaping substring blocks were rejected after EDA instruction regressions. Plain debug retains copies. Stored tokenizer text remains a useful follow-up target.

R retains fixed-array addressing and the stable integer-sort improvements. sort_builtin meets 1.2× checked Rust. sret sharing and payload-destination prototypes remain rejected; P6 copied bytes remain 444,833,472 across 34 EDA designs. The original sound inline-free barrier remains. Full final R5/ladders and detailed exit refinements were stopped under the user waiver; historical bounds remain in the retained lane and first-run evidence and do not become fresh measurements.

The next performance repair to investigate is BOX child-release dispatch, with pointer-list controls. Other remaining work includes VM frame lifetime/interference proofs, EDA token materialization, and rejected R3/R4 ownership constraints. No language semantics, safety contract, count encoding or task ABI was weakened.

## History, preservation and follow-up

U2, S2 and R were integrated with real merge commits in order: `2cd674292`, `588fddb9d`, `20e7c340e`. Three advancing-main merges are retained. The first timing identified small-sort and pointer-list regressions; repair `98e946715` fixed those before the final correctness qualification. [Earlier progress report](X/report-before-user-waiver.md.gz), [decisions](DECISIONS.md), [M0 gap](M0/gap.md) and [counterfactuals](M0/counterfactuals.md) retain the full history and original bounds.

The second timing remains explicitly incomplete/rejected under the original 3% guard: [driver receipt](X/timing-run-02/receipt.json), [rejection receipt](X/timing-run-02/rejected-receipt.json), [output mapping](X/timing-run-02/output-preservation.json). All 336 primary executable paths were preserved using 138 pre-timing identities and 198 embedded parity hashes. All completed observations and ten prepared diagnostic paths remain available; unfinished diagnostic timing is labelled unavailable. Two pre-existing baseline context files were also copied by the archive step and restored to their original result paths; they are not new run 02 measurements.

The user-directed acceptance supersedes the earlier pending-repair status without rewriting those historical receipts. No further benchmark or repair work is queued by this report. The separate FIFO implementation remains on `codex/build-slot-fifo` at `986f54a5`; it is not part of this Wave 3 merge.

Juice follow-up: retain instruction score and add independently checked cycles per completed unit, with interleaved comparisons and explicit uncertainty. Validate detection of >3% slowdowns against prospective nightly timings on held-out changes before replacing merge-time performance checks. Current historical counters illustrate the need but do not validate such a model. No Juice changes, nightly automation or new general merge policy are implemented in this closeout. No Guardian feedback entry was requested or written.
## Shipped implementation

### U2: borrows, release and checked dispatch

Nested record-field reads can borrow through consuming updates when complete write summaries preserve the field path and the updated owner dominates the use (`src/core/borrow_fields.zig:16`). Unknown effects, overlapping writes and phi edges keep snapshot ownership. Ownership analysis allocates the forwarded structure in persistent storage (`src/core/own.zig:157`); its lifetime walk uses the original owner's definition (`src/core/own.zig:1532`). The latter correction fixes the early-release failure found by the expanded frame-snapshot fixture. Whole-frame copies remain: eliminating them still requires fieldwise lifetime and interference proofs.

Generated layout callbacks specialize child release, including nested union guards and separate dictionary key/value release (`src/core/emit_release.zig:14`, `src/core/runtime/core_rt.c:429`, `src/core/runtime/core_dict.c:187`). Generated guardless lists with one pointer per element at offset zero use a direct child-release loop (`src/core/runtime/core_rt.c:739`). The predicate requires the release visitor, list kind, pointer-sized stride, one reference, and the generated zero-guard marker. Whole-block callbacks and the pointer-list shortcut enqueue children in ascending descriptor/element order; destruction follows the existing LIFO pending chain. Dictionary key/value callbacks complete each child release in descriptor order. Both paths use the existing count primitive and iterative destruction (`src/core/runtime/core_rt.c:761`, `src/core/runtime/core_rt.c:775`). Publication and dictionary tombstones retain their existing traversal handling. Boxes and guarded layouts are excluded from the pointer-list shortcut but may use generated callbacks; legacy layouts retain the C fallback. Plain, shared and saturated semantics, count encoding and task ABI remain unchanged.

The dispatch optimization proves repeated constant arithmetic only when every incoming edge supplies the same checked operation or a safe constant (`src/core/overflow_edges.zig:11`). Verification mode restores the check (`src/core/emit_llvm.zig:1726`). Small read-only list projections inline their full checked control flow (`src/core/inline_cfg.zig:7`). Specs are `NEW-CORE-U2-BORROW-1`, `FRAME-1`, `RELEASE-1`, and `LOX-1/2` (SPEC.md:1555). The lane has eight language fixtures in five CLI modes, four IR tests and a C harness. The C harness preserves its 100,000 mixed-layout links and exact 50,001 generated-callback assertion with a generated descriptor whose element stride is 16 bytes. Separate pointer-list cases cover nulls, duplicate owners, unique-child destruction, saturation, publication exclusion and shared-count traffic from main and a worker thread; no particular interleaving is assumed (`src/core/u2_test.zig:244`, `src/core/u2_test.zig:288`, `src/core/u2_test.zig:303`, `src/core/u2_test.zig:318`).

### S2: split representations, byte views and search

Private split uses can become lazy iteration, offset lists, bounded stack prefixes or count-only operations (`src/core/fuse_text_split.zig:256`, `src/core/split_views.zig:69`). Whitespace dictionary insertion retains the existing lookup probe when the borrowed key materializes (`src/core/fuse_text_split.zig:226`). Read-only byte slices and supported text consumers use spans; source-update checks and the IR verifier prevent borrowed views from escaping through unsupported storage, returns or phis (`src/core/fuse_slice_key.zig:106`, `src/core/fuse_slice_key.zig:134`, `src/core/verify_ir.zig:423`). Plain debug keeps copies. Separator validation, empty pieces, Unicode scalar semantics, byte indexing and trap order remain intact.

Search uses single-byte memchr, bounded candidate checking, then libc memmem fallback (`src/core/runtime/core_text.c:431`). Replace retains its existing single-output-buffer design. Escaped parent-backed substrings were removed after their measured EDA instruction regressions; stored token text still materializes. Specs are `NEW-CORE-S2-SPLIT-1..4`, `VIEW-1` and `SEARCH-1` (SPEC.md:1561). Twelve language fixtures run in five CLI modes. The accepted 49-test focused run also includes the mixed-declaration regression that restored runtime-only authorization for whitespace fusion.

### R: fixed-array access and stable integer sort

Fixed-array access checks the index before addressing storage (`src/core/emit_fn.zig:21`). Reads use existing storage; writes reuse an input home only when the planner proves its old snapshot dead, otherwise copying the required live value (`src/core/emit_llvm.zig:2935`, `src/core/emit_homes.zig:643`). Literal elements seed a hull, writes widen it and joins use the existing convergent analysis (`src/core/facts.zig:1180`). A normalized index inside the fixed length is proved safe; verification restores the bounds trap (`src/core/facts.zig:1898`).

Ascending 64-bit integer sorting uses allocation-free insertion through 32 values, adaptive stable powersort for 33–256, and stable 256-bucket byte radix above 256 (`src/core/runtime/core_sort.c:335`, `src/core/runtime/core_sort.c:382`). Signed ordering flips the sign bit; radix skips constant bytes and already ordered inputs. Both allocating engines reserve scratch before mutation. The short merge path avoids fixed histogram cost; ordered short lists return to M0’s bounded scratch policy. Position-decorated keys preserve stable ties; narrower integer storage, other types and reverse sorting retain the merge engine. Keyed sorting gathers the final permutation from the borrowed source into its owning clone, avoiding repeated record cycle moves while preserving references and stable order; the initial owning source/key copies remain (`src/core/runtime/core_sort.c:827`). Specs are `NEW-CORE-R-ARRAY-1/2` and `SORT-1` (SPEC.md:1580).

The R3 and R4 prototypes remain rejected. Separate ordinary noalias inputs/results and disabled sret sharing are retained (`src/core/emit_homes.zig:38`); the payload ABI failed its copy/performance premise and exposed a destination-list lifetime constraint. Their regression fixtures and `NEW-CORE-R-SRET-1` / `PUSH-1` specs remain. F1's full memory barrier is retained (`src/core/emit_llvm.zig:4088`); no narrower sound replacement was established. Eleven R source fixtures run in five modes, with an additional hand-built IR fixture in the same modes. Expanded integer-sort cases cover signed/unsigned extrema, aliases, reverse order, packed decorated ties and the wide-key two-word path at sizes through 255–257 (`src/core/r_runtime_test.zig:100`, `src/core/r_runtime_test.zig:204`).

### Integration with advancing main

Three real main merges preserve the frozen M0 baseline while incorporating main's incremental cache, memory and frontend demand-reuse changes. U2 retains persistent borrow storage and its original-owner lifetime cutoff. S2 retains whitespace → split → slice pass ordering. Main's fusion checkpoint cannot reconstruct S2's generated compound types and full helper order, so eligible split catalogs prepare eagerly and skip demand/compact shortcuts (`src/core/passes.zig:589`). Ordinary transformation, final and emission caches remain active; other catalogs retain demand reuse. Four trusted/verify regressions cover cold/warm compilation, dirty helper ordering and byte-only reuse. Final fresh-unit compile timing measures this conservative cache restriction's cost.

The third merge incorporates `e9011d9c6`, including portable checked-type recipes, exact external-source provenance and reserved-array replay. Recipes support arrays, tuples and supported callable contexts. Unsupported contexts, missing or ambiguous nominal instances and shape mismatches fall back to fresh checking; arbitrary nominal graphs are not reconstructed. The interaction review found no reason to remove the split-catalog fallback: portable checked types do not reconstruct optimizer-generated split helpers or compound types. [X/main-e901-review.json](X/main-e901-review.json) records the review and its coverage limits. The earlier repair qualification was cancelled without claiming a repository verdict; all final gates were restarted on the merged source.

For R, the no-record shortcut now supplies module type information to both exploratory and returned field tables (`src/core/passes.zig:214`). It preserves array facts without forcing record-field rounds. Two additional regressions check literal/write hulls, cached equivalence, trusted check removal and verify restoration (`src/core/optimization_cache_test.zig:1640`, `src/core/optimization_cache_test.zig:1668`). All six focused integration regressions passed before full final qualification.
