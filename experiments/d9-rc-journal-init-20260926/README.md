# Journal initialization evidence

See the [proof and results](../../docs/audits/d9-rc-journal-init-2026-09-26.md).
`identity.json` identifies the immutable Debug compiler and the exact candidate
patch over `19e16e1d`. `results.json.gz` retains the source/binary hashes,
native manifests, five interleaved instruction samples per backend and counters.
`validation-final.json.gz` retains all 20 successful before/after controls.
Build, focused-unit, formatting and whole-tree Guardian logs are compressed.

The Python files are the exact drivers used and retain their original worktree
paths. Run them from the original tree, with its on-disk `.tmp-init/tmp` and own
`.zig-cache-init`; `measure.py` uses the immutable cumulative n12 baseline in the
adjacent flat-destruction tree. `validate.py` reuses the first eight QBE rows from
`validation-probe-v2.json`; its remaining rows use the installed before compiler
and the hash-checked after compiler. The archived scripts and preliminary receipts
preserve the unsuccessful fixture setup attempts. `budget.my` and `floor.my` are
the final trap inputs; existing standalone inputs are under
`experiments/d9-rc-inert-return-20260926/direct`.

This evidence covers a local compiler optimization. It does not replace the
cumulative full gate or the required complete performance corpus.
