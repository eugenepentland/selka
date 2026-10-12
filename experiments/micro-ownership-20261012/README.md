# Microbenchmark ownership comparison — 12 October 2026

The complete measurement batch passed: **11 focused kernels plus 40 expanded
cases at two sizes**, retaining every case. The expanded suite comprises 35
microbenchmarks and five small application shapes. Compiler/runtime sources are
unchanged from the previously green verification gate. This batch records
performance; it does not implement optimizations.

Use [the full report](report/final/REPORT.md) for per-case paired confidence intervals,
Zig/Rust/Go comparisons, RSS and managed counters; [per-arm.csv](report/final/per-arm.csv)
for analysis; and [history.json](report/final/history.json) for separately identified
stored results. [report.json](report/final/report.json) retains validation, identities
and machine-readable comparisons. The earlier full applications are in the
[Lox/EDA comparison](../lox-eda-zero-rc-20261012/bench/full-final/COMPARISON.md).

## What to improve first

The following order combines this run with the earlier application evidence.
It is an investigation order, not a claim that every explicit copy can be removed.
Micro ratios below compare checked ownership with RC **on the same migrated
source**, except where explicitly stated. Above one means slower.

| Priority | Evidence | Next investigation |
| --- | --- | --- |
| 1. Repeated application copies | Earlier full Lox VM completed cases were about 19–67× slower than original RC; EDA was 10.46× slower than migrated RC. The new small Lox evaluator is approximately unchanged. | Review full-frame copying per VM instruction and EDA repeated list slices/accessor copies. Use checked local borrows or moves where only a read is needed; preserve genuinely independent snapshots. |
| 2. Tokenization and string-key updates | Word counting: **2.56–4.00×**; focused dictionary update: **5.35×**. The dictionary case performs 2,003,014 versus 3,014 managed allocations. | Investigate immediate split iteration and avoid copying a key before an update that only changes an existing value. Preserve independent ownership when inserting a new key. Read-only string lookup is a separate 1.25–1.27× cost, with its extra allocations in setup. |
| 3. Owned keyed sorting | Record sorting: **1.66–2.27×**, with **identical allocation counts and cumulative bytes**. Integer sorting is close to RC. | Profile the checked in-place permutation path against the RC copied-output gather path. Their source difference is a lead, not measured CPU attribution. |
| 4. Intermediate text-to-bytes copies | String splitting: **1.89–1.98×**; the integer-formatting case: **1.89–1.93×**. | The latter's additional allocation is in checksum helper `score(text)`, which calls `text.encode()`. Investigate borrowed byte readers when no independent bytes owner is required. This is not evidence that numeric formatting itself regressed. |

**Nested snapshots are a separate measured tradeoff:** 9.00–11.82× slower on
the migrated source. That contract deliberately makes an independent nested copy.
For the large case, cumulative allocation traffic rises from 188,893,464 to
1,666,133,144 bytes, while managed peak rises from 123,832 to 156,440 bytes and
process RSS stays approximately flat (2,156 versus 2,152 KiB). Do not remove the
required snapshot to make this benchmark faster. First remove copies from
application paths that do not need snapshot semantics, then assess necessary
deep-copy implementation costs separately.

The large word-count case similarly has **80.13×** cumulative allocation traffic
but RSS of 2,004 versus 2,052 KiB. Its checked runtime is 3.91× Zig Fast, 2.55×
Rust and 0.98× Go. Record sorting remains faster than Zig Fast at the large size,
despite its regression against MyLang RC. These are different comparisons and
should guide different follow-ups.

Most arithmetic, branches, calls, record operations, ordinary list operations,
integer dictionaries and the small Lox evaluator are close to their RC controls
in this session. Consult intervals and raw ranges before treating small
differences as changes. There is no aggregate language score.

`alloc_churn` has zero current MyLang heap allocations. Expanded `alloc_short`
has only 11 setup allocations and none in `batch_result`; its large gap against
Zig Fast is an existing optimization/native-port gap, not allocator throughput.
The canonical contracts permit scalar replacement and arithmetic simplification.

## Coverage and measurements

- **626/626 uninstrumented arm/case combinations passed:** six arms for each
  focused kernel, seven for each expanded cell. There is no canonical Go port in
  the focused suite. Expanded reference arms were freshly built and qualified.
- **8,994 measured samples**, 1,812 warmups and 1,878 separate child-RSS runs.
  Focused kernels use two warmups and nine randomized rounds; expanded cases use
  three warmups and fifteen randomized rounds. Both use three separate RSS runs.
- **273/273 counted runs passed** (three MyLang arms per cell), all with zero
  managed exit-live bytes. All 91 checked runs have zero RC events and uniqueness
  tests. Direct destruction is recorded separately from RC.
- A [native symbol audit](coordinator/symbol-audit.json) examined 90 MyLang
  binaries; all 30 checked binaries lack the known core retain/release symbols.
  This is a narrow helper-symbol audit, not a whole-package RC-retirement claim.

The MyLang arms are original source under RC, migrated source under RC, and
migrated source with `--experimental-zero-rc`. Original expanded copies received
mechanical syntax migration before the separate ownership edits. The source
pairs, diagnostics, patches and build/qualification evidence are in
[parity](parity/README.md), [expanded](expanded/README.md) and
[references](references/README.md).

All guests were pinned to CPU 8 inside shared exclusive timing admission. The
focused suite reports full-process wall time; expanded reports native kernel
time per documented CLI iteration, excluding setup. GNU time measures peak RSS
of the guest process, not a process tree. Managed counters cover their own
tracked storage and include setup; they do not measure allocator metadata,
provider buffers or all resident memory. Foreign managed-allocation counters
are unavailable. Instrumented executions never supply runtime timing samples.

The canonical expanded calibration targets a 50 ms fastest arm, a 1 s slowest
budget, at most 10 million iterations and ten pilots. Limits and durations are
published, including the inherited near-target `<5%` growth stop whose reason
label is `slowest_arm_budget` even when no arm reaches 1 s. In 34 of 80 expanded
cells the fastest pilot remains below the 50 ms target; raw durations remain
visible. Paired bootstrap intervals are exploratory single-session evidence;
independent confirmation is appropriate before optimization decisions.

Parity uses native-target Rust and fixed MyLang loop bounds versus the supplied
Zig/Rust optimization barriers. Expanded uses portable Rust, Go `GOAMD64=v1`,
host-default Zig and no forced per-operation barriers. Native collection/library
policies differ. Historical contracts describing RC string sharing describe the
old mode; the checked migrations use independently owned copies where required.

## Frozen identities and validation

- Run base: `e303d704d37d9cbd90c643ce4f06a4ecb9895718`.
- Compiler gate source: `4034a2fab29e3300b6f70549ce84727d647761db`.
- Current micro compiler SHA256:
  `8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa`.
- [Session/install identity](coordinator/session.json) and
  [host identity](coordinator/measurement-host.json).
- [Harness validation](coordinator/harness-tests.json), report mutation tests,
  and [final validation](coordinator/final-validation.json).

The earlier Lox/EDA binaries retain their own compiler hash, beginning `6e7938a1`;
this batch does not relabel them as new measurements. Stored October results
also retain their source/tool/host identities. Cross-date ratios are descriptive
context, not paired compiler-speedup evidence. The current command path is
LLVM-only; there is no new QBE measurement.

Raw immutable receipts, journals and counters are under [results](results/).
The per-cell specs pin sources, tools and executable hashes. The measurement
[scheduler](tools/schedule.py) acquires admission; [measure.py](tools/measure.py)
must not acquire a second timing lease. Revalidate the existing evidence into an
unused output directory with:

```sh
python3 -B experiments/micro-ownership-20261012/tools/report.py \
  --input-root "$PWD" --check-artifacts \
  --output .tmp/micro-ownership/revalidation-NEW
```

The complete registered gate remains the previously green
[4034 gate](../lox-eda-zero-rc-20261012/coordinator/integrated-gate.json).
This run changes only experiment evidence and adapters; benchmark qualification,
harness/report validation and Guardian cover the new files. Publication was not
performed.
