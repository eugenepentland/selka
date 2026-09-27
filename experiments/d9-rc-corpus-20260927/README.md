# Historical full-corpus RC comparison at e926d1e1

The complete unchanged 43-program corpus fails the Stage 4 instruction requirements on both backends. Median peak RSS is lower than accepted GC. This is the historical `e926d1e13bf61ae3125102b46309225ca963a38d` build, not the current integration: the long-running comparison finished after several later compiler improvements had landed on the integration branch.

| Backend | Instruction geomean | Maximum / GC | Within 1.3 | GC median RSS KiB | RC median RSS KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| qbe | 13.833063 | 247.639550 | 7/43 | 7216 | 5284 |
| llvm | 20.538954 | 676.426443 | 8/43 | 7076 | 5544 |

There are 58 RC builds and 86 workload/backend rows, each with separate exact-output checks, three instruction observations and three direct guest peak-RSS observations per GC/RC side. All 516 instruction observations and 516 RSS observations succeeded, with no failure or missing row. Every instruction counter reports 100% running. The required thresholds remain geomean at most 1.0, every row at most 1.3, and lower median peak RSS. The largest instruction ratios are string equality: 247.64 QBE and 676.43 LLVM. Correct output and lower RSS do not satisfy the instruction requirements.

The complete receipts account for 164.58 minutes of instruction-counter enabled time in Lox versus 2.37 minutes in parity and schematic combined: 98.58% belongs to Lox. This is cumulative recorded counter time, not total elapsed session time, and excludes builds, output checks and separate RSS runs. It explains why repeatedly running the full corpus during development is expensive.

The immutable Debug compiler SHA256 is `aee67f9abfe65b61a960eaf3390082d9c338553e5b086ad1cfc7723b933ab475`. The accepted GC compiler remains `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`. Guest builds use ReleaseFast; archived manifests verify actual QBE/LLVM selection and LLVM O3/full LTO. Measurements use reserved CPU11.

The archive preserves exact compressed result and baseline bytes, raw measurement output, build manifests with guest hashes, the unchanged driver, and an independent verifier. Archive construction rechecked every used compiler and guest binary hash against the run records. The verifier reparses raw counters and RSS strings, recomputes medians, checks the selected corpus and validates build manifests. Only explicit MYLANG environment overrides are retained. No guest or baseline was changed to obtain a pass.

Run `python3 experiments/d9-rc-corpus-20260927/verify.py` from the repository root.
