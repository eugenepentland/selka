# Frozen 7d68202d parity and schematic diagnostic

This is a negative performance checkpoint, not Stage 4 acceptance. It preserves
60 measured rows (30 programs per backend), their exact output checks,
median-three counters/RSS, input/compiler/binary identities and two qualitative
profiles. All 13 Lox VM cases per backend are excluded.

Run `python3 experiments/d9-rc-parity-diagnostic-20260927/verify.py` from a checkout
to verify the archived receipts without rebuilding or repeating measurements.
The [audit](../../docs/audits/d9-rc-parity-diagnostic-2026-09-27.md) explains the
method, limitations, failed initial serialization and exact continuation.

- `results.json.gz`: completed diagnostic; inherited host environment redacted
  to explicit `MYLANG_*` overrides only.
- `run.py`, `run-initial.py`, `partial-initial.json.gz`, and the two run logs:
  exact initial and corrected drivers and preserved continuation evidence.
- `gc-builds.json.gz`: accepted baseline artifact and corpus identities.
- `summary.json` and `measurements.md`: aggregate and every per-program result.
- `fannkuch/` and `schematic/`: raw compressed perf recordings, emitted IR,
  symbol maps, exact balanced counters, command identities and read-only ELF
  `.text` comparisons. Perf throttled both profiles; they are qualitative only.
- `profile_schematic.py` and `fannkuch/probe.py`: exact profile drivers.

The original full-corpus acceptance manifests are left intact. Final
acceptance must include every one of the 43 required programs per backend and
retain raw performance-event accounting as well as exact outputs and RSS.
