# Support7 allocation classifications by compiler mode

All modes retain the original denominator and distinguish workload allocation
from whole-program entry/setup costs. A case allocates when any configured input
allocates or reallocates managed storage. Peak observations are not traffic.

| Corpus | Mode | Cases | Workload allocating / free | Whole-program allocating / free | RC cases | Refused / failed / unmeasured |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| original30 | release | 30 | 23 / 7 | 30 / 0 | 0 | 0 / 0 / 0 |
| original30 | debug | 30 | 28 / 2 | 30 / 0 | 0 | 0 / 0 / 0 |
| original30 | verify | 30 | 23 / 7 | 30 / 0 | 0 | 0 / 0 / 0 |
| original30 | optimized_debug | 30 | 23 / 7 | 30 / 0 | 0 | 0 / 0 / 0 |
| original30 | no_facts | 30 | 28 / 2 | 30 / 0 | 0 | 0 / 0 / 0 |
| pinned81 | release | 81 | 70 / 11 | 78 / 3 | 0 | 0 / 0 / 0 |
| pinned81 | debug | 81 | 76 / 5 | 79 / 2 | 0 | 0 / 0 / 0 |
| pinned81 | verify | 81 | 70 / 11 | 78 / 3 | 0 | 0 / 0 / 0 |
| pinned81 | optimized_debug | 81 | 70 / 11 | 78 / 3 | 0 | 0 / 0 / 0 |
| pinned81 | no_facts | 81 | 76 / 5 | 79 / 2 | 0 | 0 / 0 / 0 |
| supplement6 | release | 6 | 6 / 0 | 6 / 0 | 0 | 0 / 0 / 0 |
| supplement6 | debug | 6 | 6 / 0 | 6 / 0 | 0 | 0 / 0 / 0 |
| supplement6 | verify | 6 | 6 / 0 | 6 / 0 | 0 | 0 / 0 / 0 |
| supplement6 | optimized_debug | 6 | 6 / 0 | 6 / 0 | 0 | 0 / 0 / 0 |
| supplement6 | no_facts | 6 | 6 / 0 | 6 / 0 | 0 | 0 / 0 / 0 |

`original30` is contained in `pinned81`; do not add these denominators together.
The six supplemental API fixtures remain a distinct corpus. Original30 workload
23 allocating / 7 free is a release-mode observation, also seen in verified
release and optimized debug. Unoptimized debug and release without facts have
28 allocating / 2 free; they still pass all correctness, RC and cleanup checks.

All original30 programs allocate somewhere when entry/setup is included. Zero
heap allocation is not the contract. Compiler optimizations remove some workload
storage, while independent result storage, explicit copies, growth and native
task/provider work remain legitimate costs. `classifications.json` preserves every
case ID in each classification and both raw-result identities. No RSS, runtime
speedup or compilation claim follows from these allocation counts.

All results are intermediate Support7, source `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
See the separate87-source contract ledger for unresolved implementation blockers.
