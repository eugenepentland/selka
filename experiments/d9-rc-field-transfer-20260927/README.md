# Closed field transfer evidence

See [the report](../../docs/audits/d9-rc-field-transfer-2026-09-27.md) for the
physical ownership proof, measured effects and limits.

The archived runners retain exact machine-local provenance paths. Adapt those
paths in a separate worktree to reproduce; do not mutate the accepted GC tree.
Use a Debug compiler built through `scripts/build-slot.sh`, a private Zig cache
and disk TMPDIR. LLVM means `--backend=llvm --llvm-opt=3 --lto`.

- `lox.json.gz` is the median-three uncounted before/prototype experiment plus
  separately counted executions on both backends.
- `lox-final.json.gz` rechecks final compiler/binary identity and output/counts,
  and records bounded attempts at the unchanged mandated N10 script.
- `guests-final.json.gz` and `failures-final.json.gz` contain all standalone
  runtime/backend controls. `controls/` preserves exact trap sources.
- `source.patch.gz` records the final code and permanent regression delta from
  the two-parent base. `identities.json` hashes the archived artifacts.
- `verify.py` checks hashes, backend identity, exact output and RC balances.

N4/N5 reductions are diagnostics. N10 attempts and their deadlines are recorded
separately; they do not replace full-corpus acceptance or silently turn a timeout
into a successful check. The preceding clone audit retains the unchanged port
and reduced input sources; this archive adds the exact N10 script and expected
output.
