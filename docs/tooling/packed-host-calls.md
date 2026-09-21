# Packed host calls

Native provider ABI 6 adds `MylangHostBinding.invoke_packed` for copied integer
scalars and fixed arrays of `u8`. A provider can use it to transfer a byte block
without representing each byte as a separate `MylangHostNode`. This works with
the QBE and LLVM backends and requires no new language syntax.

Register the exact declaration name, parameter/result type names, effects and
grants as for an ordinary host callback. Keep the ordinary `invoke` callback as
the fallback for unsupported shapes or copy budgets. The runtime selects the
packed path only for supported integer widths and flat, padding-free byte arrays
whose schemas and logical node/depth counts fit the configured limits. Managed
objects, records, domains, variants and booleans use the existing node bridge.

`MylangHostPackedCall` supplies an argument array of byte spans and one output
span. Their storage belongs to the runtime for the duration of the callback;
arguments are copies and do not point into guest storage. The byte spans need
not be aligned for C scalar types, so use `memcpy` to read and write integers.
Do not retain these spans or reenter the guest.

Charge work with `mylang_host_packed_charge` before effects. Write the result
into the provided, initially zeroed output span, set `output_written` to its
exact size, and return `NULL`; otherwise return a static error name. Do not
replace the output pointer or change its capacity. The runtime checks work
accounting, output identity and size before copying the result to the guest.
Call, capability and reentry checks remain active. Any sticky trap or callback
failure prevents result publication.

The schematic provider uses `read_block(file, position) -> [256]u8` and
`write_block(payload: [256]u8, count: int) -> int`. Reads zero-fill the final
block and charge only available input bytes. Writes validate the count, charge
the requested bytes and enforce the output limit. `finish() -> int` checks the
final flush so buffered write failures cannot become successful renders.
The guest's `output_limit()` callback reports an accumulator overflow before
any output is written. The host application publishes the private SVG only
after a successful invocation.

Recompile external C providers against the new headers. The provider factory
symbol is versioned to prevent silently linking an old binding layout.
