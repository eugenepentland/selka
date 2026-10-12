# Snapshot home overlap reproducer

Support5 compiler source `a1f19edf255c8c0886731d8d7cce450d5f657720`, SHA256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
These are counted release correctness probes, not timing measurements. The shared
admission wait was 426 seconds for the five minimized builds and two IR dumps;
JSON elapsed values measure commands after admission and exclude that wait.

The complete migrated `ce2_effects` still aborts with `free(): invalid size`.
Section controls isolate `takes_section`; prefixes through `return_value` and
`rename_and_pop` pass, adding `snapshot_between` aborts. The 29-line
`minimal-wide.my` retains only one managed int list inside a 40-byte child record.
It compiles but aborts. Removing only `it.depth = it.depth + 1` passes with exact
`605 9 5 0` output, zero RC events, and zero exit-live bytes. Shrinking the child
record to 16 bytes passes with `615 9 5 1`; inlining `take_pop` still aborts.

The owned Core in `minimal-wide-facts.txt.gz` constructs independent child `%8`,
then parent `%12` updates sibling depth; a whole-parent snapshot reads child `%13`
from `%12`. Its old child ownership can then be dropped. Generated LLVM instead
embeds `%8` directly in the source parent field before the snapshot reads it, so
that drop invalidates the new temporary. The per-field home liveness must follow
unchanged child bytes across the sibling update. A07 owns the production fix.
`a06_nested_write_test.zig` adds counted debug/verified-release cases with and
without that update; those registered tests require the fixed compiler.

Every source, raw diagnostic, owned IR, LLVM and successful counter record is
identified in `manifest.json`. JSON/LLVM/IR are losslessly gzip-compressed. Failed
runs have no counters because they abort before flush; no zero-RC/leak result is
inferred for them. `prefix0` was a rejected reduction with an unused output
capability, not a native failure. `stdbuf` could not flush the custom runtime output
buffer; the experimental preload abort handler produced no backtrace. Neither is
claimed as working instrumentation. No debugger/Valgrind was available, and this
compiler exposes ThreadSanitizer rather than AddressSanitizer.
