# Combined ownership correctness checkpoint

Frozen source `c90c84beb39952df05941fa00775e7a71cf15e7d` passes the full four-command gate: 94/94 main steps with
2,335 executed tests, 51/51 QBE steps with 445 tests, native builds 29/29 and
formatting 2/2. The Debug compiler build is 19/19, and separate whole-tree
Guardian passes all 88 checks without a waiver. Its compiler SHA256 is
`1f3bca2c62180a58fcc54782f9414a2b272e8447f996096a6883dc330774e3c7`.

This combines dictionary tail `3c4251e8`, native type facts `c71d4046` and adjacent
variant read `4f60ff94`, with all previous integrated ownership fixes. The initial
`e5d47d20` main gate failed because the dictionary-tail structural test reads
`bench/parity/micro/dict_count.my` without declaring it in `build_test_inputs.zig`.
Its QBE, native-build and formatting gates passed. The failed main receipt is
preserved; it is not counted as a green gate. The one-line declaration correction
in `c90c84be` passes direct input coverage and a fresh full gate.

Both forced counted-RC backend sweeps pass 967 assertions across 165 programs,
with no failures, skipped, cached, dropped or unloaded cases. They ran on frozen
`e5d47d20` before the manifest-only correction. The rebuilt `c90c84be` compiler
is byte-identical; repeated guest executions were unnecessary. Source and HEAD
were frozen during each gate and sweep. Scripts and raw receipts are archived.

The ordinary runtime remains GC. This is a correctness checkpoint, not Stage 4
performance acceptance. The separately archived five-program combined diagnostic
still exceeds the 1.3 instruction cap on every measured row. Full unchanged
43-program instruction and lower median peak-RSS acceptance remains open; the
runtime-default transition is outside the active performance goal.
