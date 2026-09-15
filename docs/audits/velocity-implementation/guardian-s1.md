# Guardian feedback — S1

Package S1 (representative workloads and consistent resource budgets), branch
`codex/velocity-s1`, base `5988575bf25ba96f1e9f5f79c8c824c1852a661c`.

## Findings worth keeping

- The repaired `scripts/profile_large_project.py` **validates generated source
  against the current language before timing it**. This caught the old
  generator's removed brace/`fn` syntax, which would otherwise have produced
  confident but meaningless numbers.
- The harness records the compiler's own work-report stage counts
  (`parsed_modules`, `checked_bodies`, `instantiated_specializations`, …) beside
  each raw sample, and compiler-verified `list-modules` module/import structure.
  It does not derive reuse from equal fingerprints.
- Edit samples are made independent by writing a deterministic token unique to
  each sample. Without that, the persistent verdict cache replays every second
  alternating edit and makes edit latency look artificially low.
- Bounded failure is exercised directly: 257 modules, a >4 MiB file and a
  >16 MiB project all reject with the documented codes, so the measurements do
  not accidentally claim an unsupported size succeeded.
- The maintained family reuses the repository's real `src/schematic/guest` and
  `selfhost/prototype` programs instead of inventing a second benchmark stack.

## Friction (concrete, reproducible)

- `mylang check-project entry --cache-dir DIR` exits 2 with the usage text;
  only `--cache-dir=DIR` is accepted. Scripts that pass the value as a separate
  argument silently measure a usage failure unless they parse for
  `work-report-v1`. The one-shot help text shows the `=` spelling, but the
  failure mode is easy to miss.
- `check-session` does not accept `--cache-dir`. A session started from a
  repository root creates `.mylang-cache/` in that root, so an isolated
  harness has to set the process working directory instead.
- `index-project` rejects both 100k-line workloads with
  `mylang: host failure: NavigationLimit` while `check-project` accepts them.
  The navigation symbol/reference budgets are not part of the loader/snapshot/
  package budget set; call-graph depth is therefore unsupported at 100k.
- The in-process checked-body cache is initialized with the same 16 MiB as the
  source budget (`src/main.zig:1715`). At 100k the ordinary workload's retained
  bodies exceed that and the cache reports `functions.bypassed=1`, `reused=0`,
  so every session edit rechecks all 33475 bodies. At 10k reuse works. The
  quantity being bounded (retained checked trees) is not the same as source
  bytes, so reusing the constant is a resource-budget inconsistency.
- The named reference machine is shared: another agent's `zig build test-units`
  and a `netlisp` process were active during part of the collection. The task
  asks for an idle machine; the S1 evidence notes the concurrency and keeps
  paired states in the same session, but a fully idle window would be better.
- Background measurement processes were killed twice by the surrounding shell
  after long foreground sleeps (reported as `Error: kill ESRCH`). The artifacts
  were recovered by splitting workloads and polling with short sleeps; the
  harness now writes after every workload so partial progress survives.

## Gate result

`zig build` exit 0 from the worktree:

```text
guardian: diff-scoped vs a9e29d4845ab2f8a700eeb238ed03023d2ac701e: 71/341 source file(s) in scope for the 50 per-file check(s); 38 whole-tree check(s) still read everything. NOT a whole-tree verification — use --full, or `guardian-check commit`.
guardian: file-size: 4 finding(s) — report-only
guardian: function-length: 6 finding(s) — report-only
guardian: line-length: 1544 finding(s) — report-only
guardian: run-all: 88 check(s) passed
```

`zig build fmt-check` exit 0. The commit hook then ran the whole-tree Guardian
gate: `run-all: whole-tree run`, `run-all: 88 check(s) passed` (4 file-size,
12 function-length and 3018 line-length report-only findings).
`~/ai/canopy/guardian-zig/FEEDBACK.md` was not edited.
