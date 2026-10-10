# Native negative coverage-adapter smoke — 2026-10-10

This is an intentional crashing C fixture, not compiler fuzz coverage and not
a successful campaign. `crash-target.c` aborts when an input begins with `!`.
The engine's expected crash status was **77**; `result.json` correctly records
`success:false`, `complete:false`, and that abnormal completion. The adapter
still retained the original 22-byte input `!original-native-crash` in both its
corpus and crash artifact, then retained a one-byte `!` reproduction of the
failure. `minimize-proof-0.log` shows a fresh fixed-input execution reaching the
same deadly-signal failure. This does not certify a particular sanitizer bug.

The original results, raw-input corpus, exploration/minimization/proof logs,
source, initial input, and crash/minimized artifacts are copied unchanged.
`native-crash-worker.log` and `link-crash.log` preserve the available outer
admission output. No binaries, runtime archives, or downloaded packages are
included, and no worker was rerun while preserving this evidence.

`provenance.json` records the execution-time engine hash from the result.
`parent-native-smoke-provenance.json` is the unchanged positive native smoke
provenance and supplies the parent toolchain/package/runtime context; its
positive-target command vectors and executable hash must not be interpreted
as this negative target's commands or hash. The exact outer negative command
vectors were not retained. Internal minimization commands remain in
`minimize-0.log`; no missing outer commands have been invented.

The parent native setup used pinned Zig with an explicit LLVM 19 libFuzzer
runtime and system libstdc++. No ASan instrumentation was enabled. The logs
warn about unavailable sanitizer stack/death callbacks. This evidence tests
abnormal engine completion, retention, and minimization on a native fixture;
it does not establish compiler correctness or compiler coverage.

`evidence-sha256.json` checksums every preserved file.
