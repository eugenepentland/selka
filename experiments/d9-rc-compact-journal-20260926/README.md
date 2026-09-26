# Compact RC journal experiment

Retained compiler optimization: omit a journal position only when every reachable
physical type at that position is plain. The runtime ABI and logical cleanup
order are unchanged. The [audit](../../docs/audits/d9-rc-compact-journal-2026-09-26.md)
records the proof boundary and validation. This diagnostic is not WP-4 corpus
acceptance.

`results.json.gz` contains all eight build commands, compiler/binary hashes,
full output expectation, balanced counted traffic, and three interleaved
`perf stat -e instructions:u` samples per uncounted binary. QBE and LLVM guests
both use ReleaseFast; LLVM explicitly selects `--backend=llvm --llvm-opt=3
--lto`, with no overriding QBE flag. Both compilers are Debug builds.

Run the checked-in drivers from the repository root. They expect the preserved
compiler installations under `.tmp/compact-journal/{before,after}/bin/mylang`
and write only under `.tmp/compact-journal`. `run.py` builds and validates the
n12 fixture before sampling; `guests.py` forces all language tests to execute;
`probes.py` checks six standalone outcomes and ownership balances per backend.
The language-test driver selects actual LLVM with `--release`.

`before-identity.json` records the original compiler source commit and its
identical-tree replacement adding the required co-author trailer. No measured
source changed in that metadata correction. `source-identity.json` and
`candidate.patch.gz` identify the complete candidate source. The original runner
captured its patch before new files were marked intent-to-add; the original
snapshot remains in `raw-results.json.gz`, while `results.json.gz` adds the
complete patch and identity. No commands, binaries, counters or instruction
samples were altered. The guest/probe records are `guests.json.gz` and
`probes.json.gz`. A preliminary copied probe failed module-name checking before
execution; the archived source uses its correct `positive` module name. The
bounds assertion uses the runtime's canonical `R_LIST_BOUNDS` code.

The two `*-manifest.json.gz` files and extracted `*-make.ssa.gz` files preserve
actual emitted metadata and IL. The eight small `.qbe-manifest.json` receipts
identify the compiled backend/mode. Recursive `make` uses four entries instead
of six: table plus guards shrink from 240 to 160 bytes. Payload buffers and both
transactional scratch entries remain.
