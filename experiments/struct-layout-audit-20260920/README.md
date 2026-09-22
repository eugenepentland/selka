**Record-layout audit evidence — September 20, 2026**

Read the [audit](../../docs/audits/struct-layout-optimization-2026-09-20.md) for
the decision and scope. Production compiler and language files were not changed.

- `layouts.json`: emitted sizes and recursively projected reordered sizes. All
  baseline descriptors passed size, alignment, field-offset, and stride checks
  where applicable. Pointer/scalar layouts remain fixed. No reordered compiler
  was built.
- `inspect_layouts.py`: descriptor reader and stable descending-alignment model.
  It accepts `emit-qbe` / `emit-project-qbe` JSON and asserts the baseline before
  reporting any projection. Unnamed private/synthetic types retain descriptor
  symbols when the public schema does not provide their names.
- `probe.my`: synthetic 24/16-byte layout comparison, record-copy/list checks,
  named-initializer order, and aggregate optimization probes.
- `dead_trap.my`: ignored field initializer must still divide and trap at zero.
- `aggregate-probes.json`: exact emitted IL and optimized QBE assembly for three
  functions. Debug-only statements and step/frame checks were disabled for these
  assembly inspections only; no timing is inferred from the output.
- `validation.json`: ordinary and GC-stress native execution outcomes, commands,
  and the negative initializer trap. These use ordinary `run` defaults and test
  existing behavior, not a changed layout algorithm.
- `provenance.json`: frozen compiler/QBE identities, revision, inspected source
  hashes, snapshot hashes, limitations, and the failed full-parser emission.

From the repository root, with an installed compiler and its companion QBE:

```sh
zig-out/bin/mylang emit-qbe experiments/struct-layout-audit-20260920/probe.my > /tmp/layout-probe.json
python3 experiments/struct-layout-audit-20260920/inspect_layouts.py /tmp/layout-probe.json
zig-out/bin/mylang run experiments/struct-layout-audit-20260920/probe.my
zig-out/bin/mylang run experiments/struct-layout-audit-20260920/probe.my --gc-stress
zig-out/bin/mylang run experiments/struct-layout-audit-20260920/dead_trap.my
```

The last command should exit 1 with `R_DIVISION_BY_ZERO`; the two positive runs
should exit 0. A newer compiler may produce different assembly or layouts.

Original manifests and the frozen compiler are local artifacts under
`.tmp/struct-layout-audit-20260920/`. The tokenizer census used `tokenizer/main.my`
there, containing `module main`, `import sexpr.tokenizer`, and a zero-returning
`main`; its `sexpr/` directory is a copy of the application modules. Schematic
emission used `src/schematic/guest/main.my`. Replay the local manifests with:

```sh
python3 experiments/struct-layout-audit-20260920/inspect_layouts.py .tmp/struct-layout-audit-20260920/tokenizer.json
python3 experiments/struct-layout-audit-20260920/inspect_layouts.py .tmp/struct-layout-audit-20260920/schematic.json
```

No compiler build or Guardian gate ran, so no Guardian feedback entry was required.
