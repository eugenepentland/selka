# Combined loop parity and schematic evidence

Frozen compiler source: `49c6ca07`. This is a 30-program non-Lox diagnostic,
not complete Stage 4 acceptance. Every raw sample, command, manifest and
source/compiler/input identity is retained in `results.json.gz`. The immutable
accepted GC build manifest is retained separately. All 13 Lox programs per
backend remain required for the final acceptance run.

Run `python3 experiments/d9-rc-loops-joined-parity-20260927/verify.py` to
reparse raw evidence and recompute the complete 60-row diagnostic.
