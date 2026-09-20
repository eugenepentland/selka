# Streaming and output experiment evidence

See [the report](../../../../docs/audits/streaming-parser-byte-output-2026-09-19.md)
for scope, limitations, and interpretation.

- `measure.json`: final 31-round wall and separate ten-round counter batches;
  all ten arms, raw samples, round orders, toolchain, inputs, outputs, and hashes.
- `ratios.json`: additional paired-round bootstrap comparisons, including
  previous/new arena, QBE, and text/byte comparisons.
- `qualification.json`: 730 final valid-input comparisons, including arena arms.
- `verification.json`: 360 final safe-build golden, error, and GC-stress checks.
- `malformed-verification.json`: 600 extra malformed-input comparisons. Its
  renderer predates the final padding-only change; the parser is identical.
- `heap-stats.json`: untimed large-input allocation/collection/payload/RSS data.
- `build.json`, `text-arena-builds.json`, `bytes-arena-builds.json`: build commands,
  source/object identities, and experimental transformations.
- `sources.json`: final relevant source hashes; `inputs.json`: baseline revision
  and frozen control hashes; `validation.json`: validation scope and log hashes.
- `indent-slices-measure.json`: preceding 31-round implementation experiment,
  retained separately. Do not pool its samples with the final results.
- `headroom-profile-summary.json`, `headroom-profile-commands.json`, and
  `headroom-*.tsv`/`headroom-*.asm`: subsequent read-only profiles of the final
  executables and three hot mylang functions. See the
  [remaining-headroom audit](../../../../docs/audits/remaining-runtime-headroom-2026-09-19.md).

## Reproduction

Run `zig build` first. The checked-in port uses the streaming parser and text
renderer. Build it with `mylang build experiments/sexpr-port/main.my
--mode=ReleaseFast --keep-symbols`; add
`--qbe=experiments/llvm-backend/qbe_llvm.py` for LLVM. Use separate fresh cache
directories and explicit `-o` paths for each variant. The byte variant changes
the render branch to these two statements (the following is source text, not a
standalone program):

```text
_ = out.write(printer.render_bytes(nodes))
_ = out.write(b"\n")
```

For the previous-source control, copy the port tree and restore main.my,
sexpr/parser.my, sexpr/tokenizer.my, and sexpr/printer.my from `4919ea9f`. For the
parser-only control retain the new parser/tokenizer with the old main/printer.
The original work directories and complete build commands are recorded in JSON.

Emit each final closure using `mylang emit-project-qbe ENTRY --drop-debug
--drop-step-checks --drop-frame-checks` to a manifest file. Follow
[`maxperf/README.md`](../../maxperf/README.md) with that manifest, the matching safe
LLVM receipt, runtime sources and ReleaseFast formatter to build `control` and
`compact-o3`. A fresh cache avoids stale objects confusing that script's entry /
metadata object inventory. Arena and unchecked behavior retain that experiment's
valid-input-only contract.

Use `maxperf/qualify.py` and `verify_binaries.py` before timing. Use `measure.py`
with the binary paths recorded in `measure.json`, `--rounds 31 --warmups 3
--cpu 6 --sink capture`, and `--reference before-safe`. Supply every executable
using repeated `--binary NAME=PATH`; do not time while building or testing. The
full work directory from this run is `.tmp/llvm-streaming-20260919/final/`.
