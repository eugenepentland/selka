# Packed host calls

> **Removed 2026-10 (new core S5-D5).** Host providers, `host def` and their
> packed-call ABI were retired; `extern def` with `--link FILE.c` is the remaining C
> interop ([direct C imports](../c-ffi.md)). This page is kept as a record.

Native provider ABI 7 offers `MylangHostBinding.invoke_packed` for copied integer
scalars, fixed arrays of `u8`, and whole immutable `bytes` payloads. A provider
can use it to transfer a byte block, or a whole document, without representing
each byte as a separate `MylangHostNode`. This works with the QBE and LLVM
backends and requires no new language syntax.

Register the exact declaration name, parameter/result type names, effects and
grants as for an ordinary host callback. Keep the ordinary `invoke` callback as
the fallback for unsupported shapes or copy budgets. The runtime selects the
packed path only for supported integer widths, flat padding-free byte arrays
whose schemas and logical node/depth counts fit the configured limits, and the
`bytes` byte string. Managed collections other than `bytes`, `byte_buffer`,
records, domains, variants and booleans use the existing node bridge.

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

## Owned `bytes` payloads

A declaration may take or return the immutable `bytes` byte string at the
boundary itself — not nested inside a record, which the copied node graph could
not carry. It is the one shape whose octet count is not in the schema, so the
registry's `max_payload` bounds it (zero selects 1 MiB; above 64 MiB the
registry is rejected outright).

- **As an argument** it arrives as a runtime-owned copy of the guest byte
  string's exact octets, with `size` equal to its length. Writing through that
  copy cannot reach guest storage. Every argument is measured against
  `max_payload` before any of them is copied, so an oversized payload is refused
  before the callback observes the call.
- **As a result** it is the one output the callback owns. The runtime hands over
  an empty output (`bytes` `NULL`, `size` 0); the callback publishes by setting
  `output.bytes` to its own read-only octets and `output.size` and
  `output_written` to their length. The runtime only reads them, copies them
  into a fresh guest byte string before returning, and publishes nothing after a
  sticky trap, a refused allocation or an inconsistent span. A declaration whose
  result is `bytes` therefore has no node-bridge fallback.

A provider that hands a whole document to the guest and takes a whole rendering
back declares two operations:

```mylang notest
public host def read_document(host: Host, file: int) -> bytes effects(host)
public host def write_bytes(host: Host, payload: bytes) -> int effects(host)
```

and implements them against the payload contract:

```c
static const char *read_document_packed(void *context, MylangHostPackedCall *call) {
    (void)context;
    if (call->argument_count != 1 || call->arguments[0].size != 8) return "HostFailure";
    int64_t id;
    memcpy(&id, call->arguments[0].bytes, 8);
    if (id < 0 || (size_t)id >= document_count) return "HostFailure";
    size_t count = document_length[id];
    if (!mylang_host_packed_charge(call, 1 + count)) return "HostWorkLimit";
    call->output.bytes = document_bytes[id]; /* the provider keeps these octets */
    call->output.size = count;
    call->output_written = count;
    return NULL;
}

static const char *write_bytes_packed(void *context, MylangHostPackedCall *call) {
    (void)context;
    if (call->argument_count != 1 || call->output.size != 8) return "HostFailure";
    size_t count = call->arguments[0].size; /* the guest's octets, already copied */
    if (count > output_capacity - written) return "HostWorkLimit";
    if (!mylang_host_packed_charge(call, 1 + count)) return "HostWorkLimit";
    if (count && fwrite(call->arguments[0].bytes, 1, count, output_file) != count) return "HostFailure";
    written += count;
    int64_t status = 0;
    memcpy(call->output.bytes, &status, 8);
    call->output_written = 8;
    return NULL;
}
```

The schematic provider (`src/schematic/native_schematic.c`) is exactly this,
with `max_payload` set to its 4 MiB output capacity. It also retains
`read_block(file, position) -> [256]u8` and
`write_block(payload: [256]u8, count: int) -> int`. Reads zero-fill the final
block and charge only available input bytes. Writes validate the count, charge
the requested bytes and enforce the output limit. `finish() -> int` checks the
final flush so buffered write failures cannot become successful renders.
The guest's `output_limit()` callback reports an accumulator overflow before
any output is written. The host application publishes the private SVG only
after a successful invocation.

Recompile external C providers against the new headers. The provider factory
symbol is versioned to prevent silently linking an old binding layout.
