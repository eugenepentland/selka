# Representative operation-family assessment

The suite represents a broad range of common single-threaded application code: **35 microbenchmarks across eight operation families and five composed applications**, in Rust, Go, Zig Safe/Fast, and MyLang LLVM/QBE. It is a useful general-application baseline, with the fixture limits below. No literal percentage of codebases is claimed.

Each benchmark and input size uses its **lowest median runtime across all six configurations as 1.00×**. Every other value is its median runtime divided by that fastest median: 2.00× means twice the runtime. The reference can change between benchmarks and between small and large inputs. Exact median ties share 1.00×.

[Full family assessment and 480 comparisons](results/assessment_main_20261003.md) · [Machine-readable assessment](results/assessment_main_20261003.json) · [Validation](results/validation.json)

The following ranges describe individual large microbenchmarks relative to each benchmark's fastest configuration. They are ranges across cases, not pooled workload scores. The full report includes all six configurations, both sizes, raw times, and uncertainty intervals.

| Operation family | MyLang LLVM / fastest | MyLang QBE / fastest |
|---|---:|---:|
| numbers and branches | 2.21–3.21× | 9.93–15.17× |
| lists and iteration | 1.55–2.35× | 4.59–9.47× |
| strings and bytes | 1.00–7.81× | 1.00–23.26× |
| dictionaries and sets | 1.67–3.98× | 2.04–5.27× |
| records and calls | 1.49–4.02× | 3.17–24.34× |
| optional values and errors | 4.37–5.21× | 5.52–29.09× |
| allocation and ownership (excluding alloc_short) | 1.00–3.41× | 1.18–4.23× |
| sorting and searching | 1.00–2.02× | 1.28–17.40× |

Short allocations are omitted from this compact range table because some compilers eliminate them; all their measurements remain in the full assessment. Snapshot results include copy-on-write versus explicit-clone behavior. Sorting uses different native APIs/algorithms, including Go `sort.Slice`/`sort.SliceStable`, so these results do not establish general sorting superiority.

Composed applications on the large fixtures, **runtime relative to the fastest median**:

| Application | Fastest | LLVM | QBE | Rust | Go | Zig Safe | Zig Fast |
|---|---|---:|---:|---:|---:|---:|---:|
| word_count | zig-fast | 8.56× | 11.56× | 1.58× | 4.03× | 1.27× | 1.00× |
| csv_aggregate | zig-fast | 7.44× | 10.83× | 1.29× | 1.55× | 1.25× | 1.00× |
| json_transform | rust | 24.88× | 33.46× | 1.00× | 4.37× | 1.85× | 1.51× |
| packet_decode | zig-fast | 2.50× | 12.60× | 1.20× | 2.96× | 2.04× | 1.00× |
| lox_eval | rust | 7.11× | 7.78× | 1.00× | 1.18× | 2.86× | 2.79× |

Current MyLang results show substantial gaps to the fastest implementations across many common operations. The winner is Rust or Zig Fast in these five application fixtures; other microbenchmarks can have a different winner.

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
all six configurations and every documented per-iteration unit.

For each case/size it selects the smallest observed median runtime and divides
all six medians by that value. The selected reference is fixed for that case/size;
it does not switch to each round's winner. Exact median ties are all marked
fastest; a stable configuration order selects one of them for uncertainty
calculations. Ratios are of medians, not medians of paired ratios.

Intervals use 2,000 paired bootstrap resamples from the raw rounds. Each resample
uses the same round indices for a configuration and its fixed reference, then
computes the ratio of their medians. The original Go-relative intervals are not
reused or divided. The reference compared with itself has interval [1, 1];
another exactly tied configuration can have a nonzero-width interval. These
exploratory intervals do not account for selecting the winner from the observed
data, and are not adjusted for multiple comparisons.

Family panels show every micro comparison, fastest/overlapping/slower counts,
ranges of individual ratios, and worst observed cases. An unusual nonwinner
interval entirely below 1 is labeled explicitly rather than changing the
observed fastest median. Counts include small and large profiles separately;
JSON also separates counts by profile. The five-application table and 480-row
appendix preserve reference names, ratios, times, units, spread and both sizes.

The user's 80% goal is a qualitative design aspiration for representative breadth
of everyday application codebases. There is no quantified population percentage,
CPU-time attribution target, frequency weighting, acceptance threshold or global
language score. Counts describe only the selected test/profile comparisons.
An interval containing 1 means overlapping evidence, not proof of equivalence.
Family and application reviews, confidence gaps and excluded workloads come from the reviewed
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
