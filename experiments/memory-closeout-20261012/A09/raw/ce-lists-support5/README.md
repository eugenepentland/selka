# Intermediate checked list oracle evidence

Compiler source `a1f19edf255c8c0886731d8d7cce450d5f657720`, SHA256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
This is Support5, not a final candidate or installed-package qualification.
Its staged language components remain the separately disclosed legacy Support4
components. All compiler invocations used shared build admission. Elapsed fields
in the source-only probe are correctness diagnostics, not exclusive timings.

Seven source shapes were checked in raw and release IR. Six passed; the inline
field-store shape refused `xs[i].name = s.copy()` at line27 with
`E_SINGLE_OWNER_OVERLAP`. Its direct store is retained unchanged while A07's
prepared-slot checker fix qualifies. Five of six inline debug native fixtures
passed exact outputs, balanced counted cleanup, zero RC and zero exit-live bytes;
the sixth is that same refusal. Three of four full release fixtures passed exact
historical outputs: `ce_cow`, `ce_slices`, `ce_appends`. `ce_elements` refused its
string field store at line70 with the same diagnostic. Refusals remain in the
receipts and are not counted as passes.

`ce_cow` keeps the original40×500 interpreter/VM work and3000 builder inputs.
The migrated whole-Runtime write-back copies are source-required costs: release
351287 allocations,1634431400 allocation bytes,27262288 reallocation-added bytes,
262493 list copies /1614810180 copy bytes,227784 peak-live managed bytes and0
exit-live bytes. These are separate metrics; peak is not allocation traffic and
none is process RSS. No compiler-only improvement or wall-time claim follows.

Whole-element `Frame` stores build the new frame directly in its destination:
zero aggregate memcpy, two old-value loads and three direct managed child drops.
Selected wide-record copies duplicate only their string/list children; the
containing list is not copied. Exact structural assertions are being integrated
in the registered `ce_lists_test.zig` suite; these CLI probes do not replace it.
