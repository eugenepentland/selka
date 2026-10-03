# Representative operation-family assessment

The suite represents a broad range of common single-threaded application code: **35 microbenchmarks across eight operation families and five composed applications**, in Rust, Go, Zig Safe/Fast, and MyLang LLVM/QBE. It is a useful general-application baseline, with the fixture limits below. No literal percentage of codebases is claimed.

The current results do **not** yet support broad performance parity with Go. LLVM has modest gaps in several routine families and larger gaps in strings, tagged values and composed jobs; QBE has substantial additional gaps in calls, records and numeric code.

[Full family assessment and 480 comparisons](results/assessment_main_20261003.md) · [Machine-readable assessment](results/assessment_main_20261003.json) · [Validation](results/validation.json)

Large-profile runtime ranges versus Go for individual microbenchmarks are below. These are ranges across different cases, not averages or a workload prediction; lower than 1× means faster than Go. The full report includes Rust and both Zig modes, both input sizes, confidence intervals, and each individual case.

| Operation family | MyLang LLVM / Go | MyLang QBE / Go |
|---|---:|---:|
| numbers and branches | 1.30–1.70× | 5.79–10.00× |
| lists and iteration | 1.20–1.48× | 2.63–8.25× |
| strings and bytes | 0.16–3.98× | 0.15–19.09× |
| dictionaries and sets | 1.67–3.21× | 2.04–4.25× |
| records and calls | 1.23–2.40× | 2.61–14.53× |
| optional values and errors | 1.89–4.15× | 5.25–10.76× |
| allocation and ownership | retained: 1.77×; shared snapshots: 0.39–0.41× | retained: 2.58×; shared snapshots: 0.48–0.49× |
| sorting and searching | native sorting: 0.05–0.19×; binary search: 1.23× | native sorting: 0.08–0.24×; binary search: 10.61× |

Short allocations are omitted from this compact range table because some compilers eliminate them; all their measurements remain in the full assessment. Snapshot wins include the documented copy-on-write versus explicit-clone behavior. Sorting uses different native APIs/algorithms, including Go `sort.Slice`/`sort.SliceStable`, so these wins do not establish general sorting superiority.

Composed application medians for the large fixtures, in **microseconds per job**:

| Application | LLVM | QBE | Rust | Go | Zig Safe | Zig Fast |
|---|---:|---:|---:|---:|---:|---:|
| word_count | 21.14 | 28.54 | 3.89 | 9.96 | 3.13 | 2.47 |
| csv_aggregate | 396.75 | 577.14 | 68.71 | 82.81 | 66.52 | 53.31 |
| json_transform | 3091.02 | 4157.30 | 124.23 | 543.44 | 230.41 | 187.25 |
| packet_decode | 1.64 | 8.29 | 0.79 | 1.95 | 1.34 | 0.66 |
| lox_eval | 75.79 | 82.98 | 10.66 | 12.64 | 30.53 | 29.79 |

These fixtures point to calls/records/options in QBE, dictionaries/sets, string splitting/formatting, and tagged values as useful optimization targets. The microbenchmarks help isolate an operation; the composed jobs check whether improvements carry through to application-shaped work. A fast result in one family does not cancel a slow result elsewhere.

The main remaining representativeness gaps are large working sets, recursion and graph traversal, diverse keys and map deletion, long-lived mixed-lifetime heap churn, and varied document/input shapes. Concurrency and I/O need separate workloads if those applications become part of the target scope. The current assessment assumes general single-threaded application logic.

All findings reuse the original **7,200 uninstrumented timed samples**. This task reanalyzed the results and independently revalidated the evidence; it did not rerun unchanged guest programs. Historical CPU samples and their old attribution targets are not coverage or performance acceptance criteria.

Generate an assessment from the immutable saved baseline, without running or
building any guest:

```sh
python3 benchmarks/runtime/assessment/assess.py
python3 -m unittest discover -s benchmarks/runtime/assessment -p 'test_*.py'
```

Default outputs are `results/assessment_main_20261003.json` and its Markdown
companion. The tool pins the selected baseline's SHA256, calls the independent
expanded verifier with `artifacts=False`, and checks all 40 cases, both profiles,
all six configurations and every documented per-iteration unit. It copies the
independently checked paired medians/95% intervals; it does not rerun samples,
discard outliers, tune builds or modify the baseline and historical profiles.

Eight operation-family panels show every micro comparison against Go, descriptive
faster/overlapping/slower counts, the range of individual median ratios and an
explicit worst observed comparison. Counts include small and large test profiles
separately. JSON also separates counts by profile. Go is labeled reference,
rather than counted as a performance win. A five-application table shows large
whole-job median microseconds and paired ratios/intervals for all six arms; the
480-row appendix preserves both sizes, units, time spread and classification.

The user's 80% goal is a qualitative design aspiration for representative breadth
of everyday application codebases. There is no quantified population percentage,
CPU-time attribution target, frequency weighting, acceptance threshold or global
language score. Counts describe only the selected test/profile comparisons.
An interval containing 1 means overlapping evidence, not proof of equivalence.
These exploratory intervals have no multiple-comparison adjustment. Family and
application reviews, confidence gaps and excluded workloads come from the reviewed
`expanded/coverage.json` taxonomy and are retained in the report.

The report explicitly flags short-allocation elimination/tiny samples, native
sorting and JSON library differences, ownership/allocation semantics, distinct
instruction-set policies and calibration limits. Some saved `slowest_arm_budget`
labels mean growth below 5% near the target, rather than an actual hard-cap hit.
The immutable calibration evidence is preserved as recorded.

The tool audits the measurement's 42 recorded source hashes against Git blobs at
`b725360f5f86ac67bc405db9407ae51c332a9931`. That is the benchmark-source snapshot,
while `6df58b02554401f9d37564cceffd14277a835ae1` is the separately recorded compiler
source revision. Current documents may legitimately differ. The tool does not
claim that current binaries/toolchains were verified or independently establish
compiler-source equivalence. A historical source mismatch fails generation;
unavailable Git objects produce an explicit incomplete/unavailable historical
audit status. Baseline SHA256, taxonomy SHA256, generator/verifier SHA256 and the
per-source historical audit are saved for review.

Overrides: `--baseline`, `--expected-baseline-sha256`, `--taxonomy`,
`--historical-revision` (full commit SHA), `--repo`, and `--output`. A different
baseline requires its explicit expected hash and still must pass the independent
full-inventory verifier. Output may not replace the baseline, its Markdown,
the taxonomy, or any expanded evidence/profile artifact. Input bytes must remain
unchanged through generation. An unavailable historical repository permits a
portable numerical replay, clearly labeled as lacking the historical source audit.
