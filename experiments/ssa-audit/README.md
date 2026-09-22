# SSA-at-the-language-level audit — evidence

Companion to `docs/audits/language-level-ssa-2026-09-19.md`. Everything here was
produced with the installed compiler on `perf/lever-search` (head `4919ea9f`) and
the vendored `zig-out/bin/qbe`.

## Probes

- `scalar_loop.my` — three scalar locals (`total`, `i`, `v`) reassigned inside a
  `while` loop, Python style.
- `record_loop.my` — a 16-byte `record` local reassigned inside a `while` loop
  through a call that returns a record.

## Reproduce

```bash
zig-out/bin/mylang emit-qbe --drop-step-checks experiments/ssa-audit/scalar_loop.my > /tmp/scalar.json
python3 -c "import json,sys; [open('/tmp/sum_evens.ssa','w').write(u['il']) for u in json.load(open('/tmp/scalar.json'))['functions'] if u['name'].endswith('sum_evens')]"
zig-out/bin/qbe -d C /tmp/sum_evens.ssa 2>&1 >/dev/null     # IL after SSA construction + copy elimination
zig-out/bin/qbe /tmp/sum_evens.ssa                          # final amd64 assembly
```

`--drop-step-checks` removes the per-instruction step counter that `emit-qbe`
keeps by default; `mylang build` produces unbounded programs (`RUNTIME-UNBOUNDED-1`),
so the dropped form is the one a built program runs.

## Files under `evidence/`

- `*.emitted.ssa` — the IL `qbe.zig` emits for the probe function.
- `*.after-ssa.txt` — QBE's `-d C` dump: the function after `promote`, `ssa` and
  copy elimination. Every `%l{n}`/`%s{n}` `alloc8` that became a temporary prints as
  `nop`; loop-carried locals appear as `phi`.
- `scalar_loop.sum_evens.s` — the final assembly of the scalar loop.

## Corpus census

`python3 experiments/ssa-audit/reassign_census.py` counts, per function, how many
distinct local names are assigned more than once and how many of those are
assigned inside a loop, over `experiments/sexpr-port`, `tests/lang`,
`src/schematic/guest` and `src/stdlib`. It is a regex census (one assignment
statement per line), not a parse; treat its numbers as ±a few percent.
