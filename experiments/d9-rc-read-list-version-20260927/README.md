# Read-only scalar-list version evidence

Matched immutable Debug compilers at clean control `e130e87f` versus the archived
source patch. Actual QBE and LLVM O3/full LTO, full unchanged inputs, CPU3,
median-three raw instructions, separate exact counted runs. All samples report
100% running. This is isolated evidence; Stage 4 performance acceptance remains
open.

Append after/before is 0.844146 QBE / 1.000000 LLVM; accepted-GC ratios remain
1.902061 / 2.301125. Sieve after/before is 0.902319 / 0.916250; GC ratios remain
2.963575 / 3.513822. All mixed alloc-churn/schematic results are retained in
`controls.json.gz`. GC values are completed rows of the original corpus
experiment, not new interleaved samples and not a claim that the whole earlier
corpus experiment finished.

The detailed proof, complete table and limitations are in
`docs/audits/d9-rc-read-list-version-results-2026-09-27.md` from repository root.
`identity.json` names original binaries/inputs; `source.patch.gz` freezes the
production/test patch. Emissions are labeled accounted versus unaccounted.
`development/` preserves rejected harness observations and `logs/` preserves
initial focused/Guardian failures. No rejected probe is positive coverage.

Verification:

```sh
python3 experiments/d9-rc-read-list-version-20260927/verify.py
python3 experiments/d9-rc-read-list-version-20260927/verify.py --live
```

The first audits the archive, the second additionally checks the original
immutable compiler/binary/input/output files. Scripts preserve explicit
MYLANG overrides only; inherited host environment values are not archived.
