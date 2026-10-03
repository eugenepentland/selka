# Checked AST carrier checkpoint — 2026-10-03

The selected AST refactor reduces tree-interpreter wall time by **3.05% on LLVM**
and **2.48% on QBE**, relative to the accepted callee/table source84. It matches
call/class nodes inside their handlers and removes two owning getter returns.
The canonical optimized migration now applies this AST-only patch. The
constant-read and composed candidates remain isolated experiments because their
VM timing gains are small relative to their paired-ratio spreads.

| Selected AST source, 13 workloads per engine | LLVM | QBE |
| --- | ---: | ---: |
| Tree wall-time reduction | 3.0541% | 2.4807% |
| Tree instruction reduction | 1.7871% | 2.0784% |
| Tree cases with lower median paired wall time | 11/13 | 13/13 |
| Median tree paired-ratio spread | 1.816% | 3.131% |
| VM / Rust wall ratio | 2.717× | 5.291× |
| Tree / Rust wall ratio | 4.116× | 7.430× |
| VM / Go wall ratio | 2.678× | 5.252× |
| Tree / Go wall ratio | 4.018× | 7.206× |

VM instruction work is effectively unchanged by the selected AST patch. Its
small VM wall movements are not attributed to a VM optimization. Rust/Go parity
remains unmet. LLVM tree `string_equality` and `strings` are 0.49% and 0.84%
slower; the other 11 LLVM tree workloads improve. QBE tree improves in all 13.
LLVM's tree all-workload per-round reductions are 4.62%, -0.40%, 3.41%; all
leave-one-round-out median-pair aggregates still improve by 1.41–3.99%. The QBE
per-round reductions are 2.11%, 3.40%, 2.67%. These descriptive checks support a
modest tree improvement without supplying a narrow confidence interval.

The complete factorial measures four source variants under both backends plus
the original frozen Rust/Go binaries. Wall time has 780 unique cells across
three rounds; counters have another 780. The diagnostic screen has 208 cells
and source smoke 208, giving 1,976 original rows. All 3,952 PMU running-rate checks
in the screen and full counters equal 100. A separate fresh reconstruction adds
260 behavior checks. Within-case paired ratios are reduced by their median,
then the 13 case ratios are combined geometrically. Wall sizes use the original
engine-specific timed tiers; counter sizes use the calibrated tree tier on both
engines. Builds exclude CPU 2/sibling 3 and CPU 10/sibling 11.

The selected source contains 84 public tests. Fresh accounted selected-compiler runs pass
84 tests in each LLVM/QBE RC/native-GC-stress arm (LLVM `--release`, QBE
`--mode ReleaseFast`): 336 executed, zero cache reuse,
failures, skips or drops. These directory tests are provider-free. Existing
selected d14 native LLVM/QBE RC/GC guests passed 1,168 bounded comparisons and
96 focused call/class/root/error comparisons, plus eight matched RC refusals.
Their identities match the selected source; native observations were not rerun
when closing the separate fresh public-test gap. The matrix retains 80 explicit
native-stress smoke omissions. The older accounted 4cbae public receipt remains
historical. Public Lox errors are exact; internal malformed-node helper PCs and
tight source-step cutoffs are outside these native parity claims.

All 37 canonical replay files match the measured AST source. The incremental
patch SHA256 is `b1fc1359603b549f7a06ed00a958d0d5dcf6f91515b78e2d4bad8719942d6f9b`.
The unchanged selected compiler is `d14a7040…`, adjacent QBE `99ad919d…`, and
reference sources are `4e48a09220c2e018eba8c4b1eb3fe1137a3dae73`. Measured selected
RC guests are LLVM `180575c3…` and QBE `246f2178…`. Bounds, overflow, COW and root
protocols remain enabled. No full 43-program compiler performance gate is
claimed by this Lox checkpoint.

[The factorial recipe and receipts](../../experiments/lox-ast-constant-20261003/README.md)
reconstruct the exact control and all candidates independently of future
canonical migration changes. All eight mylang guests and Rust reproduce byte
for byte; fresh Go has different path metadata and serves as behavior evidence.
The historical source80/source84 helper also reconstructs its pinned pair from
the fixed archive, rather than applying future canonical changes.

[The independent measurement closeout](../../experiments/lox-round3-independent-review-20261003/final-closeout.md)
verifies all original phases and 42 comparisons. Source review, native
qualification and fresh selected public qualification have separate full
receipts. The source84 constant trial and composed source85 passed qualification
but are not selected. Checked byte-sized opcode storage is a separately
qualified follow-on candidate awaiting measurement; its compiler guard remains
isolated. `main` and the original dirty checkout remain unchanged.

The completed checkpoint is sealed at
`/home/epentland/ai/canopy/evidence/lox-parity-20261003/ast-carrier`:
2,571 verified payloads, 22 referenced runtime objects, zero unavailable paths.
`MANIFEST.sha256` is `c5b1b628b6a0c41b277a8944d5b007a051de638d1b866f58def483eec5c35139`.
The archived selection/review tree is `30fc3997`; prior sealed archives remain
unchanged. Later byte-source timing is outside this archive.
