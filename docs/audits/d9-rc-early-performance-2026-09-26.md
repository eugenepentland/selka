# Early exact-workload RC performance diagnostics — 2026-09-26

The superseded RC correctness checkpoint `39f75f3f` fails the WP-4 performance
criterion by a large margin. These are exact-workload diagnostics from the
required harness inputs, not a complete acceptance result. The accepted GC
compiler is `f6bea5d9`; RC Debug compiler SHA-256 is
`a57ea3b5e2fd86630ba9711e81e2b0d1a83de22088c7f33dd48b1efa69d3646a`.

| Program | QBE instructions RC / GC | LLVM instructions RC / GC |
|---|---:|---:|
| binary_trees | 108.493 | 145.991 |
| fannkuch_redux | 101.423 | 202.970 |
| matmul | 464.529 | 7369.742 |

Each ratio is the median of three interleaved `instructions:u` samples pinned
to CPU 2. Binary hashes were checked against each side's build manifest; every
listed program produced the expected exact output. LLVM uses O3 and full LTO.
No RSS result or full-corpus geomean is claimed. The large LLVM matrix gap
indicates that removing ownership calls from inner loops is necessary; making
the generic runtime helpers faster cannot by itself restore baseline codegen.

All 58 native binaries built. Of 19 completed output checks, 16 passed;
knucleotide aborted on both backends, and QBE quicksort exceeded the harness's
600-second timeout. The sorted-receiver physical-anchor error responsible for
knucleotide is fixed by `c4066c99`, with corrected full-workload output evidence
in `d9-rc-knucleotide-anchors.json`. The remaining LLVM quicksort check and nbody
measurement were explicitly stopped because the checkpoint was superseded.
Only the exact owned driver and child PIDs recorded in the stop file were sent
SIGTERM; the accepted GC artifacts and corpus inputs are retained unchanged.

Evidence is preserved as `evidence/d9-rc-39f-builds.partial.json.gz`,
`evidence/d9-early-counts-39f.partial.json.gz`, and
`evidence/d9-rc-39f-stop.json.gz`. The reproducible subset driver is
`experiments/d9-rc-acceptance-20260926/early-counts.py`. Runtime pointer transfer,
read-only body borrowing, scalar receiver loans, and constructor token transfer
are being measured against this diagnosis. GC remains the default until the
complete WP-4 correctness, instruction, and peak-RSS gates pass.
