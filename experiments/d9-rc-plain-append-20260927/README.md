# Scalar append room-path evidence

This archive records a bounded RC optimization, not Stage 4 acceptance. The
four unchanged full-size workloads still have material residuals against the
accepted GC baseline. See [the audit report](../../docs/audits/d9-rc-plain-append-2026-09-27.md)
for the proof, results and limitations.

Run the archive-only verifier from any directory:

```sh
python3 experiments/d9-rc-plain-append-20260927/verify.py
```

`identity.json` records the parent source, production-file hashes, candidate
compiler and accepted-GC identities. `source.patch.gz` is the complete production
and permanent-test delta against that parent, excluding this report/archive.
`measurements.json.gz` contains all 32 builds, exact commands, binary hashes,
48 retired-instruction observations and 16 counted executions. The 32 native
manifests identify actual QBE versus LLVM O3/full-LTO compilation.
`accepted.json.gz` records 24 fresh runs of the original accepted-GC binaries;
`accepted-gc-builds.json.gz` authenticates their hashes. No accepted binary was
rebuilt or overwritten.

`guests.json.gz`, `controls.json.gz` and `standalone.json.gz` retain the full
outputs and commands for 364 assertions, 40 paired controls and two counted
program runs. `controls/` contains the standalone control sources. Emission
receipts, sanitizer, focused-test, Debug-build, Guardian and formatting logs are
also retained. Initial failed test/filter/fixture attempts are preserved and are
not counted as passes; `iteration-before-discard.my` explains the checker refusal
before the corrected eight iterator controls were rerun.

The Python drivers are the exact executed scripts. To reproduce measurements,
run them from the repository root after selecting fresh scratch directories and
reviewing their explicit compiler paths: `measure.py`, then `accepted.py`.
The recorded before compiler is the immutable joined a9eae92e build; the after
compiler is the separately installed Debug candidate. `guests.py`, `controls.py`,
`standalone.py` and `native.py` reproduce focused checks. They preserve build-slot
coordination, explicit GC stress and actual LLVM release selection. CPU 10 was
reserved for the timing observations. Private immutable binaries remain at the
absolute paths recorded in the receipts; they are intentionally not checked in.
