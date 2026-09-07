# Native ordinary JSON parsing

Native `json_parse` links the same `json_document.zig` parser used by the VM.
`scripts/native.py` automatically builds its small Zig support object and links
it with the generated C. The support object contains parsing/allocation code,
not a bytecode interpreter. Direct consumers of emitted C must link the matching
`native_json_bridge.zig` object when `MYLANG_NATIVE_JSON` is defined.

The generated source pins SHA-256 over the bridge, parser and codec support source
snapshot. The build driver checks that pin before compiling the support object;
changed support sources require rebuilding the compiler. The exact project Zig
toolchain remains required. The support-object ABI takes caller-supplied allocation
callbacks, so allocator-failure injection and ownership remain with the native
runtime. Successful tape storage transfers to C and is freed after copying into
the requested guest allocator region. A pending-output cleanup hook handles
failure before publication.

Parsing preserves the ordinary JSON tape, duplicate decoded key and UTF-8 rules,
integer/fraction boundaries, syntax/depth/token limits and 128 MiB parser memory
budget. Invalid byte budgets return 4, operation/quota limits return 2, malformed
input returns 1, and actual allocator exhaustion remains a host failure. Byte and
tape-word instruction charges match the VM. The parity suite checks 24 value/error
comparisons and 72 shared step-budget comparisons in Debug and ReleaseFast.

Typed source `json_encode`/`json_decode` are still rejected explicitly in this
stage; their checked value/domain codec bridge remains separate work.
