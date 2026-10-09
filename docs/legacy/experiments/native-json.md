# Native source JSON
> Removed on 2026-09-13: this page records the compatibility C backend, which no longer
> exists. QBE is the only native backend; see [../../experiments/incremental-qbe.md](../../experiments/incremental-qbe.md).

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

Typed source `json_encode`/`json_decode` share the normative typed-json-v1
encoder and decoder through copied value trees and compiler-emitted schemas.
Integers (including u64), booleans, records, fixed and enum-keyed arrays, enums,
unions and fallible variants preserve canonical names and values. Operations
retain the VM's 32 MiB temporary budget, 65,536 visited values, depth 64, byte
limits and instruction charges. Compiler-owned metadata and copied input/output
storage use the parent allocator; temporary codec storage uses the bounded
allocator. Every allocation-failure position is checked for cleanup.

The typed parity suite adds 12 value/error and 48 step-budget comparisons across
Debug and ReleaseFast, including nested variants and zero-length arrays. Domain
codecs now invoke the compiler-selected machine-code methods with copied arguments
and results. Each call owns separate operand, frame and aggregate registries, so
rejections and arithmetic traps release only that invocation and preserve the
surrounding JSON operation. The bridge passes no providers or allocation authority.
As with authority-free VM invocation, programs containing host declarations yield
a domain failure instead of accessing the enclosing host registry.

Codec calls share the operation's 256-call budget, remaining instruction budget
and remaining frame budget after counting caller frames. Domain rejections and
ordinary codec traps return error 3; frame and instruction exhaustion remain
runtime traps. The trap recovery jump stays within C and never crosses Zig stack
frames. `tests/native_domain_json.py` checks rejection/trap recovery followed by a
successful call, call-budget exhaustion, recursive codecs, 114 step/frame parity
cases, and 238 allocation injection positions with subsequent successful reuse.
The allocation sweep runs with ASan/UBSan at O0 and O2. A failed resize may safely
fall back to a fresh allocation; every run must either complete correctly or
report OutOfMemory, and release all tracked allocations.

`tests/native_json_benchmark.py --compiler zig-out/bin/mylang --zig PATH` measures
200 nested composite roundtrips, checks the same checksum, and reports three-sample
median process times separately from native compilation. A local run measured
0.111 s for the supplied development VM binary, 0.00264 s for ReleaseFast native,
and 2.88 s to generate/build native code. These are workload observations, not a
backend-only speed comparison: VM timings include loading, checking and compiling
the source, and optimization settings differ. Rerun on the intended toolchain and
machine before making performance decisions.
