# Existing-word isolation receipts

`python3 verify.py` checks the compressed archive without compiling anything.
`python3 verify.py --live` additionally hashes the original immutable compilers,
measured executables, source and candidate production files. `files.json`
records the SHA256 and size of every uncompressed receipt; gzip timestamps are
zero. No executable is embedded here.

`measurements.json.gz` contains all 18 CPU11 median-three instruction receipts,
four independent count records, backend manifests, build commands and hashes.
`measure.py.gz` is the exact build/measurement driver; `controls.py.gz`,
`guests.py.gz` and `reentrant.py.gz` reproduce the bounded correctness runs.
Drivers use the worktree's `.tmp-rc/loop-operands` directory and the immutable
compiler paths recorded in the receipts. Extract them there to replay; do not
replace the original compilers or benchmark sources. Guest sources and the C
embedding harness are included.

The candidate was built on design HEAD `d68f06f2` plus the archived production
patch and new modules. Source hashes are in `source-identity.json.gz`. The
matched before compiler has the PC-context fix `238db806`; both compilers are
Debug host builds, while measured guest binaries use ReleaseFast. LLVM uses
O3 and full LTO. Root owns the later combined gate.

`root-diagnostic-*` preserves the original accounting-mode motivation without
alteration. Read `root-diagnostic-correction.txt.gz`: slots 62/63 were
write-only/unescaped with setup stores, not unused. The measured production
candidate independently selected slots 3/4. Its actual native disassembly is
`after-qbe-main.asm.gz`; there is no claim that the accounting diagnostic was
timed.

Failed preliminary fixture/driver receipts and Guardian logs are retained.
The first fixture expected six rather than four matches in the first sixteen
bytes; unsupported frame-accounting syntax, missing main, and invalid zero
embedding budget were harness mistakes, fixed without production changes.
These are not omitted from the final positive evidence.

See the report in `docs/audits/d9-rc-loop-operand-isolation-2026-09-27.md` for
proof boundaries, exact result and remaining Stage4 limits. No full corpus or
RSS acceptance is claimed.
