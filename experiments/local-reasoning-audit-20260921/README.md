# Local reasoning audit probes

Evidence for [the syntax audit](../../docs/audits/local-reasoning-syntax-2026-09-21.md).
Run from the repository root:

```sh
python3 experiments/local-reasoning-audit-20260921/probe.py
```

The script uses the installed `zig-out/bin/mylang`. It checks twelve programs and
runs the nine accepted programs through the ordinary native `mylang run` route.
Each accepted program prints 42 and exits 42, as specified by the language's
integer entry-point convention. Three programs intentionally reject: missing
mutation marker, augmented field assignment, and direct fixed-array indexed
assignment. The last two retain syntax limitations encountered while preparing
the probes; the accepted counterparts use full field assignment and `replace`.

`evidence.json` records commands, diagnostics, outputs, source hashes and compiler
hashes before and after capture. All twelve outcomes matched their expected
results, and the compiler hash remained stable during the retained run. The
revision records repository HEAD; it does not assert that a concurrently built
installed compiler contains every working-tree change.

The list/class write probes deliberately enable `--mutation-markers` even though
their callees omit `mutates(...)`: both accept unmarked calls and modify caller
state. Only the list case warns. The declared-write probe requires `&`, and the
marked counterpart accepts it.

Other probes demonstrate destination-dependent Option projection, shallow record
copying, alias-visible list `+=`, expected-type-dependent literal storage,
shadowing `Ok`, and explicitly discarding a failed Result.

No compiler rebuild or Guardian gate was run. These are small semantic probes,
not a full regression suite, performance benchmark or comprehension experiment.
Rerunning replaces only this directory's generated `sources/` and `evidence.json`.
