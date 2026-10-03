# Runtime parity campaign evidence

`current-main-1fd1d566-20261003` is a fresh baseline of runtime/compiler sources
exactly matching main `1fd1d566793dcae92449d937aca595c55ee318c8`. The benchmark
harness is committed at `89f4f85b`. The compiler build receipt records a
ReleaseFast compiler-only build through `scripts/build-slot.sh`, private Zig
caches, disk TMPDIR and `-j2`. MyLang guests were rebuilt; reference guests were
copied only after checking their original manifest, executable, source and
toolchain hashes. The raw report includes these receipts and original commands.

The complete run took place from 20:04 to 20:33 UTC on 2026-10-03. All 40 cases
ran at both frozen sizes with six current arms, 15 randomized rounds and three
warmups. It saved 7,200 samples and 720 checksum qualification probes. The seven
plans originally won by MyLang also ran the original MyLang executable in the
same session: 105 supplemental reference samples and 21 warmups. Every guest
acquired the campaign timing lock and ran on CPU 2. Its sibling averaged 3.50%
busy; the recorded governor was powersave. Average activity does not exclude
short interference or frequency drift.

Both the independent verifier and candidate comparison passed with
`--check-artifacts` before subsequent harness edits. Compiler/runtime source
bytes and benchmark assets matched their receipts before and after sampling.
These are local provenance checks, not an independently attested build.

The raw report SHA256 is
`f2e24958ec044a12de49d93c73108ebfa8e2ccd2dcd9e94f92dfce38b3b9d5f9`.
The comparison SHA256 is
`873c83e8b9af6dbc43982915c58cf96891575f7c009f715305b29f7045246a89`.
The gzip files preserve the exact uncompressed JSON bytes. Replay without live
artifact checks after decompression:

```sh
gzip -dc benchmarks/runtime/candidates/current-main-1fd1d566-20261003.json.gz > /tmp/current-main.json
python3 benchmarks/runtime/expanded/verify.py /tmp/current-main.json
python3 benchmarks/runtime/compare_candidate.py /tmp/current-main.json --output /tmp/current-main-comparison.json
```

All 160 backend/case/size targets remain numerically open against the immutable
historical targets. Against the original winner rerun in the same session,
LLVM has 73 intervals wholly above one and seven inconclusive intervals; QBE
has 79 wholly above one and one inconclusive interval. These exploratory
intervals do not correct for repeated tuning or multiple comparisons. No
independent confirmation or campaign improvement is claimed by this baseline.

Large application ratios are shown separately; lower is better:

| Application | LLVM / frozen target | LLVM / concurrent original | QBE / frozen target | QBE / concurrent original |
|---|---:|---:|---:|---:|
| packet_decode | 2.647 | 2.504 | 13.764 | 13.020 |
| lox_eval | 11.248 | 6.895 | 11.778 | 7.220 |
| word_count | 10.788 | 8.809 | 14.003 | 11.434 |
| csv_aggregate | 9.684 | 7.640 | 13.751 | 10.849 |
| json_transform | 32.705 | 27.117 | 42.107 | 34.912 |

Calibration limits are retained for every affected row. In particular,
`alloc_short` permits optimizer elimination, with exceptionally short reference
pilots; its very large ratios do not measure physical allocation cost. Static
whole-function assembly observations alone do not isolate its executed path or
prove allocation absence. Causal micro diagnostics, allocation/RC counters,
holdouts and independent confirmation remain separate work.
