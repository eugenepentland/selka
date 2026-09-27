# Composed borrowed-entry experiment

See [the report](../../docs/audits/d9-rc-borrowed-composition-2026-09-27.md) and
[reviewed design](../../docs/audits/d9-rc-borrowed-composition-design-2026-09-27.md).
The immutable base is `3b867d50`. `source.patch.gz` is the production/test delta
against that base. `identities.json` identifies the measured final compiler and
hashes every archived evidence file.

`measure.py` uses the unchanged schematic `pc.py` build/run/check API, all three
exact inputs, actual QBE/LLVM backends and separate counted binaries. The raw
commands, manifests, outputs, SVG hashes and unscaled instruction samples are in
`measure.json.gz`. Both emitted JSON files preserve complete generated IL.
`guests.py` and `traps.py` record standalone controls on GC stress and RC, each
using actual backend manifests. The scripts use explicit local scratch paths
recorded in their commands; adjust those paths deliberately for a rerun.

`*-initial` evidence records the earlier compiler before adding the public scalar
result filter. Those tests passed, but all final controls were rerun with the
final compiler. Only the final files contribute to the validation totals; the
initial files retain provenance rather than substituting a different compiler.
No performance samples use the initial compiler.

Run `python3 experiments/d9-rc-borrowed-composition-20260927/verify.py` to validate
archive hashes, compiler identities, actual backend manifests, all 24 schematic
output checks, 36 unscaled event samples, 20 guest assertions, 12 expected traps
and ownership balances. This is an isolated RC comparison; it does not establish
WP-4 acceptance against the frozen GC corpus.
