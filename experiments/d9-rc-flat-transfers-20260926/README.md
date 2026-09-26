# Flat aggregate transfer diagnostic

The depth-12 source and expected stdout are the unchanged copies in
`../d9-rc-pointer-fastpath-20260926/`. They differ from the full binary-tree
corpus only in `max_depth = 16` becoming `12`. This is not corpus acceptance.

`isolated.json` captures three interleaved QBE runs of the pointer/local-stack
runtime and the added flat aggregate path, compiled by Debug compilers with
default guest optimization and no LTO. Compiler, binary, source and runtime
source hashes are included. CPU 0 is a private diagnostic CPU on the shared
machine; only retired user instructions are interpreted, not wall time/cycles.
The instrumented artifacts are separate from measured artifacts. Output and
complete ownership counters match exactly between these two arms.

The emitted native metadata contains a 16-byte record with two ordinary
pointer leaves at offsets 0 and 8, and its one-field boxed wrapper. Both satisfy
the cached flat-plan admission rule. `profile.txt` is a sampled self profile;
it guides prioritization and is not exact per-operation accounting.

Use the build/perf commands in the preceding experiment README with the desired
Debug compiler revision. Reproduce stats separately with `--rc-runtime=stats`.
The committed constructor-take/read-only compiler optimizations are deliberately
absent from this isolated pair; their combined measurement is recorded separately.
