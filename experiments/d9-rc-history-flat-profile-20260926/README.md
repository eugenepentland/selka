# Cumulative corpus and profile receipts

The [report](../../docs/audits/d9-rc-history-flat-profile-2026-09-26.md) describes
the failed corpus checkpoint and the exact scope of the sample.

- `rc-builds.json.gz` and `gc-builds.json.gz` are unchanged manifests: all commands,
  binaries, inputs and completed checks. RC has 60 successful checks and one
  600-second timeout; 25 checks remain interrupted or unrun.
- `history-flat-stop.json.gz` records the exact owned driver and child stopped
  after the timeout. `build-rc-history-flat.log.gz` is its original output.
- `nbody-19e-qbe.data.gz` is the raw perf recording; the accompanying samples,
  log and report are retained. `symbols.nm` and the native manifest identify the
  symbol twin. Run `python3 decode.py` to reproduce `profile-decoded.json`.
- `identity.json`, `elf-sections.json` and `nbody-reconstruction.json.gz` document
  the compiler/source identities, instruction-byte equivalence and the metadata
  rewrite caveat. The initial nearest-symbol analysis remains archived separately;
  `profile-decoded.json` uses strict function extents.
- The GC stdout and perf stderr are from one diagnostic run, with exact expected
  output. They are not acceptance medians.

The supplied `nbody.my` is an exact source copy, with the original 5,000,000 steps.
No corpus workload or expected result was relaxed. Compressed data are gzip files.
