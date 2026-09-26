# Bounded inert-return evidence

See `docs/audits/d9-rc-inert-return-2026-09-26.md` for the proof, restrictions and
results. `measurement.json` retains every median-three sample, immutable compiler
and binary hash, and ownership count. No generated binary is checked in.

The Python helpers are exact diagnostic scripts from the contract worktree;
they expect the recorded `.tmp-rc/profile` immutable installations and sources.
Build commands and their manifests are retained in raw JSON. The `direct/`
bundle copies the source fixtures, adding module headers where import requires
them, and calls 54 public assertions without the test runner's step accounting.
`path-evidence.json` and compressed SSA confirm admitted and refused paths.
`direct53.json.gz` preserves the earlier driver before adding the tagged-union
case; `direct.json.gz` is the final 54-assertion result.

`traps.py` uses `build --run` so frame/step controls reach the runtime instead of
becoming guest arguments. `traps.json.gz` includes complete diagnostics and
balanced counters for all 12 before/after/backend scenarios. The native stack
floor uses a large recursion request with no artificial frame ceiling.

The archived broader `guests.json.gz` came from the initial prototype and covers
accounted fallback only. `final-guests.json.gz` covers the final eight new tests
under accounted RC and GC on both backends. These complement the independently
built unaccounted executables, not replace them. Full gates and WP-4 corpus
acceptance remain the parent agent's responsibility.
