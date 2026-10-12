# Support5 targeted Result-map qualification

This is intermediate generated-guest evidence, not C1 qualification or an
RC-free installed-package claim. The coordinator installation still contains
historical Support4 RC components; `installation.json` records their identities.

Compiler source: `a1f19edf255c8c0886731d8d7cce450d5f657720`.
Compiler SHA256: `8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.

The Result-list/map fixture passed release and ThreadSanitizer executions at
1, 2 and 8 workers (6/6), with output `27 4 5 4 5\n3889\n`. All three
counted release executions had zero RC events and zero managed exit-live bytes.
Both LLVM/native-symbol structural audits passed. The unhandled-list fixture
refused with `E_RESULT_UNHANDLED` as required.

`results.json` records source, compiler, harness, binary and LLVM hashes, commands,
raw outputs and counter summaries. Compressed counters retain exact raw bytes.
`run.log` includes admission wait; that wait is not compiler or guest timing.
No performance claim is made from these executions. Final C1/C2/C3 matrices remain
separate work against their exact frozen compiler installations.
