# Reduced Lox clone audit

See [the report](../../docs/audits/d9-rc-lox-clones-2026-09-27.md) for findings,
limitations and the proposed physical ownership proof. No production change is
included. N4/N5 reductions are diagnostics, not the required N10 acceptance run.

- `historical/`: original uninstrumented QBE sample, exact perf commands, raw
  perf data, decoded records, event statistics and older output controls. This
  compiler predates the separately fixed argv exit leak. Substantial sampling
  throttling prevents treating hotspot percentages as precise shares.
- `matched/`: argv-corrected production RC and GC counted runs for both actual
  backends, exact build commands, output and complete manifests. The original
  absolute command paths are retained as provenance, not portable defaults.
- `probe/`: diagnostic-only runtime patch, bounded counter results, decoded
  descriptor/caller symbols, compiler build log and exact runner. Its timings
  and instructions are unusable for acceptance. It is a QBE-only diagnostic.
- `setter-il/`: exact cached GC/RC outer and inner setter functions, extracted
  read-only by the compiler agent from the matched manifests.
- `inputs/`: exact reduced scripts and deterministic archive of the unchanged
  Lox port, with file identities in `historical/port-identities.json.gz`.
- `identities.json`: base source, compiler/bundle/binary identities and hashes
  of original evidence files. `verify.py` checks archive hashes, matching output,
  complete probe accounting and production count balance without rebuilding.

The probe patch applies to commit `66054aab08b0fafa2b36b10c2df20bfac152e220`.
To reproduce it, use a separate worktree, apply only that archived patch, and
build a Debug compiler through `scripts/build-slot.sh` with a private Zig cache
and disk TMPDIR. Adapt the archived runner's paths to that worktree. Do not apply
it to the production integration tree or use its binary for timing comparisons.
