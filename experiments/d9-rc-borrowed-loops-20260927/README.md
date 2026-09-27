# Bounded borrowed-entry loop experiment

See [the report](../../docs/audits/d9-rc-borrowed-loops-2026-09-27.md).
The base is immutable `6ce92814`. `source.patch.gz` is the production/test delta
against that base, with the actual measured compiler identity in `identities.json`.
Final installation and measured installation have the same SHA-256.

`measure.py` uses the unchanged schematic `pc.py` build/run/check API, all three
exact inputs, actual QBE/LLVM backends, and separate counted binaries. Its raw
commands, manifests, outputs, SVG hashes and unscaled instruction samples are in
`measure.json.gz`. `before-emitted.json.gz` and `after-emitted.json.gz` preserve
full generated IL. `guests.py` and `traps.py` preserve exact standalone controls.
They use local scratch paths recorded in their raw commands, not portable install
assumptions; adjust those paths explicitly for a rerun.

`traps-missing-runtime-options.json.gz` is the first invalid step control: the
binary was built with accounting but run without the requested runtime budget.
It is retained for provenance and excluded from successful validation totals.

Run `python3 experiments/d9-rc-borrowed-loops-20260927/verify.py` to check archive
hashes, actual backend manifests, all 24 schematic output checks, 36 event samples,
20 guest assertions, 12 expected traps and ownership balance. These measurements
compare consecutive RC slices; they are not acceptance against the frozen GC
corpus.
