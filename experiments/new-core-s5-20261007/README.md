# S5 evidence and tools (2026-10-07)

S5 is "switch and delete" (`docs/audits/new-core-s5-plan-2026-10-07.md`). Package S5-0
froze the old core's answers here, so S5's later packages can delete the old core and
still be qualified against it.

## `references/` (S5-D2)

**`oracles.json`.** The archived oracle binaries: the old core `d36658db…` and QBE
`b6139650…`. Both are in `~/.cache/mylang/oracles/old-core-d36658db/`, the same
binaries that qualified S3 and S4. They run standalone:

```bash
MYLANG_QBE=~/.cache/mylang/oracles/old-core-d36658db/qbe ~/.cache/mylang/oracles/old-core-d36658db/mylang test FILE --json
```

**`conformance-v1.json`.** The old core's verdict for every `tests/lang` test: 337
files, 1,636 tests, the 118 arena tests included. Each entry holds the name, status
and trap code, which is all `conformance.py` compares. Script:
`s5-0/freeze_conformance.py`.

**`fuzz-v1.json.gz`** (700 KB). The old core's build status and every native run
(arguments, status, stdout, stderr) for the 9 kinds × 200 cases. It is keyed by the
generated source's SHA-256, taken from S4's strict matrix on `af0bf538`
(`x-matrix-01`). The generators are deterministic per seed: the S3 and S4 runs produced
the same 1,800 sources. Script: `s5-0/freeze_fuzz.py`.

**`rows-old-v1.json`.** The old core's and Zig's cycles per unit for the 46 rows at
the S4 exit. The row tool keeps measuring the archived old core interleaved with the
new one; this column is the fallback. Script: `s5-0/freeze_rows.py`.

## `tools/`

These are S3's qualification tools, unchanged except where they ask the old core.

- **`qualify_merge.py`:** install, `test-core`, then full conformance with leak and
  verify, against `references/conformance-v1.json`.
  - `--compiler` names the binary under test: `zig-out/bin/mylang-core` until S5-A,
    then `zig-out/bin/mylang`.
  - `--install` names the `zig build` step: `core` until S5-D, then `install`.
- **`conformance_ref.py`:** `conformance.py` with `Tool.old` answered from the
  references; `--references` replaces `--mylang`.
- **`fuzz_matrix.py`, `fuzz_frozen.py`, `frozen-old-core`:** the strict matrix with
  old-core builds and runs answered from `fuzz-v1.json.gz`.
  - `--references` replaces `--old`.
  - `--cases` defaults to 200; use 50 per package.
  - A source or run without a reference stops the run, because the generator or the
    seed changed.

The 46-row tool stays S4's `experiments/new-core-s4-20261006/integration/measure_all46.py`,
with `--mylang` pointing at the archived old core.
