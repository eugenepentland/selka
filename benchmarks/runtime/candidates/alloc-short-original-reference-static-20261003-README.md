The exact original Zig Fast winner for both alloc_short sizes has eliminated
its local four-int allocation/construction loop. This is static evidence from
the hash-verified original executable, not a new timing measurement.

The frozen source uses case index8. Its timed batch dispatch uses the jump
table at `0x1002260`; entry8 has signed offset `0x1352d`, resolving to
`0x101578d`. Reading the ELF load segments verifies this target independently
of objdump's text. The selected body is nine instructions, including its final
jump, with no call and no inner construction loop. It rejoins the ordinary batch
checksum reduction at `0x1015702`. Fixture allocations occur outside this
selected path and outside the kernel timer; the outer batch checksum loop,
timing calls and teardown still execute.

For source size n, seed s and batch b, the batch value reduces to
`4*n*(s+b) + 2*n*(n-1) + 6*n`. The source allocates and frees four ints for each
logical item, but that physical work is absent from this optimized path. This
supports treating the historical roughly3.7ns whole-pass target as an elision
and loop-simplification target, rather than allocator throughput. It does not
prove elimination on another reference/backend, and the nine instructions are
not the full batch-loop executed cost.

The archive contains whole-main disassembly, raw jump-table data, symbol table,
the resolved path excerpt, original source copy and source/binary/tool/command
receipt. No generated port, checksum, baseline or target was changed. MyLang's
eligible P7 witness is documented separately; the original alloc_short
acceptance row stays open until its actual measurements satisfy the target.

Executable SHA256: `ab34bafd6a39d4a6fefe32ab4720c6fa6b0c3b322072b9bac55ca1620b095d0b`.
Archive SHA256: `dbfca73e66f77d675776099d431ddb34ee3c581e4a1904148ed1d22a61c7d386`.
