# Language performance audit evidence

Read the [audit](../../docs/audits/language-performance-ergonomics-2026-09-20.md)
for recommendations and interpretation. No production source was changed by this
audit. The working tree and compiler changed concurrently, so initial and later
compiler observations are recorded separately.

- `provenance.json`: initial compiler/source hashes, guest snapshot location,
  initial guest build command, historical-data hashes and observed concurrent
  changes. The initial compiler hash matches the first benchmark's toolchain hash.
- `checked-qbe-vs-zig.json`: fresh initial checked-QBE/Zig comparison, 21 rounds,
  raw ordered samples, randomized round order, paired bootstrap intervals, and
  executable/input/output identities. Timings include process launch and file I/O.
- `aggregate-change-vs-zig.json`: separate matched batch comparing both frozen
  checked-QBE executables with Zig, using the same guest-source snapshot.
  `concurrent-aggregate-change.json` identifies the compiler used for `after`;
  the harness's top-level compiler hash reflects the live installed compiler.
- `findanyused-*.json`, `final3-counters.json`: unmodified copies of the prior
  `.tmp/bench` evidence. These concern the experimental compact-arena build.
  Historical wall samples are sorted, so they cannot support paired bootstrapping.
  Counter values and wall times are separate runs; do not combine their cycles
  with a different report's instruction totals to compute IPC.
- `aggregate_probe.my`, `probes.json`, `aggregate-assembly.json`: initial copy
  probes, emitted IR excerpts and optimized QBE assembly. Full initial manifests
  remain under `.tmp/language-performance-audit-20260920/`.
- `concurrent-aggregate-change.json`: repeat IR probes using the separately frozen
  compiler with the new aggregate parameter lowering. Simple parameter reads
  have zero `blit`s; this does not prove all aggregate copies are removed.
- `bytes_alias_probe.my`: executable demonstration of mutability through a heap
  `bytes` alias and refusal by an equal-content literal.
- `validation.json`: parser tests, retained goldens and focused validation scope.
  `tests-after.log` records the full parser-suite rerun with the frozen later
  compiler. `goldens-after.json` records the later executable's 17 direct native
  comparisons against the retained Zig outputs. No compiler-wide gate or Guardian
  gate was run by this audit.

Run the two small positive probes from the repository root:

```sh
zig-out/bin/mylang emit-qbe experiments/language-performance-audit-20260920/aggregate_probe.my --drop-debug --drop-step-checks --drop-frame-checks
zig-out/bin/mylang run experiments/language-performance-audit-20260920/bytes_alias_probe.my
```

`probes.json` contains the complete sources/commands and diagnostics of the
negative `noalloc` checks. They import a snapshot of the actual `sexpr.view`
module. Check them as separate projects; their expected result is
`E_EFFECT_BOUND`, not successful compilation.

Reproduce the later wall batch while the captured executables are retained:

```sh
python3 experiments/llvm-backend/measure.py \
  --work .tmp/language-performance-audit-20260920/recheck \
  --input .tmp/runtime-audit-20260919 \
  --rounds 21 --warmups 3 --cpu 6 --sink null --no-counters \
  --binary before=.tmp/language-performance-audit-20260920/qbe \
  --binary after=.tmp/language-performance-audit-20260920/qbe-after \
  --binary zig=.tmp/llvm-streaming-20260919/before/zig \
  --reference after \
  --json .tmp/language-performance-audit-20260920/recheck.json
```

The `.tmp` executables and source snapshot are local artifacts, not portable
checked-in builds. Rebuilding from a later checkout measures that later checkout;
use the stored identities to avoid mislabeling it as an exact reproduction.
The later compiler was copied to `zig-out/bin/mylang-audit-20260920` to keep this
audit's follow-up independent of further compiler rebuilds.
