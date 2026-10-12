# Numeric formatting ownership and selected-header ABI

The external Zig number-text object was compiled with an explicit legacy
`count, kind, len, cap, reserved` header. Checked ownership's C runtime puts kind
at byte zero, rather than byte four. Numeric formatting allocated through the
correct C runtime, then cleared the ASCII flag through the wrong Zig field. A
non-ASCII fill could therefore leave a false ASCII premise: exact output octets
were correct, but scalar length/index operations were wrong. This is separate
from the selected C layout audited elsewhere. The previously unadmitted
`myl_core_format_float`/`myl_core_format_number` helpers kept this path refused by
checked guest compilation; no absence-of-RC-event claim would expose the defect.

The adapter now treats the first eight bytes as opaque. Length remains at byte
eight and payload at byte 32 in both existing layouts. A tiny C shim updates kind
through the selected C type. The unit test asserts size, offset and absence of
named count/kind fields; the actual object probe checks ordinary and owned layouts.

The full audited path is scalar-only `(f64,u64)->str` or `(u64,u64)->str`:
checker-validated format packing, synchronous bounded-stack measure/render passes,
C `str_new` allocation, fresh returned text, direct owning destruction. Neither
numeric helper borrows or retains any managed input. The internal Zig text helper
also reads only stable len/payload fields, borrows its input for synchronous
rendering and returns independent text. It is tested but does not gain a guest
helper contract merely because it shares this object. `round_float(f64,i64)->f64`
uses bounded stack decimal work and has no managed input, result or allocation.
A07 statically reviewed the full paths. Root owns the exact registry additions.

`abi.py` links actual concatenated runtime C with before/after prebuilt Zig objects
under ordinary and `MYL_ZERO_RC` headers. It records compiler, source, object and
binary hashes. The scalar-only probe supplies an aborting task-call stub required
by the general destructor's link graph; it creates no tasks. Unicode float fill
at three dynamic precisions, integer fill, borrowed text formatting, scalar index
caches, independent copies and zero remaining managed blocks are asserted.
Formatting ties round to even; the language's separate round helper uses ties away
from zero. No source semantics are changed.

Initial attempts are retained. `abi-01` and `abi-03` mistakenly asserted the raw
allocator carved-block total was zero; that total includes blocks on free lists.
The corrected assertion uses the runtime's `live_count()`, which subtracts the
free lists just as the actual leak checker does. `abi-02` switched to the selected
destructor but missed the generated task-call symbol. These harness failures are
not production leaks and are not counted as passing ABI gates. The selected
destructor is retained in the corrected probe so full owned cleanup is exercised.
The corrected `abi-04` probe passes both ordinary variants and the new owned ABI;
the old owned ABI fails exactly on its false ASCII flag. All other variants have
correct Unicode results and zero actual live managed blocks. The focused header
and invalid-fill units pass 2/2; the compiler's focused number-text set passes 3/3.

Root applied the exact audited format_float/format_number fresh contracts and
round_float scalar contract. The prototype compiler SHA256
`7c23fcb21a543cec9d9e1813f2b7171e1ccbf5d5ee68d0da343fe1445a90c699`
passes all five counted ownership modes and ordinary release in `prototype-01/`.
The checked runs have zero RC events, zero managed exit bytes and clean LLVM/symbol
audits. The exact embedded numeric object and byte offset are recorded in
`compiler-build.json`, along with compiler/source identities. Release/debug replay
requests link but do not replay because this prototype lacks the coordinator's
approved host closure; those two failures are preserved. A08 owns final numeric
object/cache invalidation qualification, and the integrated candidate must rerun
these guest cases and the complete registered gate. No default/retirement or
package-wide RC-free milestone is claimed.
