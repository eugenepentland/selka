# D9 pure recursive-box reads — 2026-09-26

Recursive box reads whose types reach no mutable value collections now bypass
`myl_qbe_cow_unbox`. Their immutable bodies require neither descendant sharing
nor pinned-child replacement. Ordinary field lowering retains its private
aggregate copies and borrow lifetime rules. These reads are not allocation
safepoints. Boxes containing mutable collections retain the existing rooted
unbox path, and the conservative boxed-parent lifetime restriction is unchanged.

This removes the parity binary-tree outlier in the joined 43-workload diagnostic.
The full performance acceptance gate remains pending: the other workload ratios
must be measured again on the final combined candidate.

## Measurements

The mandated `pc.py` parity binary-tree workload ran with its original size and
stdout check, pinned to CPU 10, with three interleaved instruction-count samples
for exact `60b668cf`, joined `5bdd99ea`, and this candidate. The two current arms
use identical migrated source. Compilers are Debug; guests are ReleaseFast,
with LLVM `-O3` and LTO. All six stdout checks passed.

| Backend | 5bdd99ea / baseline | Candidate / baseline | Candidate / 5bdd99ea |
| --- | ---: | ---: | ---: |
| QBE | 3.305924× | 1.203502× | 0.364044× |
| LLVM | 2.152965× | 1.065888× | 0.495079× |

The Debug compiler SHA-256 is
`cec188428e5382f6977b5cadb68bb6358afe4cba5250481df2c7b59766e41302`.
[Raw counters and hashes](d9-pure-box-perf.json) retain each observation.

## Validation

- Full gate: 93/93 steps, 2115 main tests; QBE 428/428, build 29/29,
  format 2/2; Guardian 88 checks passed without ratchet changes.
- Focused COW suite: 27/27 tests passed, including existing mutable-box
  snapshot and pinned projection coverage.
- Two new pure-box guest tests passed on both QBE and LLVM with native GC
  stress. They check independent scalar updates and liveness across allocations.
- [All 44 switch-off IL comparisons](d9-pure-box-off-il.json) compiled
  successfully and were byte-identical to exact `60b668cf`.
