# Installed parser qualification

`selfhost/tests/run_parser_component.py` qualifies an already installed parser
producer against the host `dump-syntax` boundary. Run it under admission:

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_parser_component.py \
  --compiler zig-out/bin/mylang --builder zig-out/tools/selka-components \
  --component-dir zig-out/libexec/mylang/components --zig "$(command -v zig)"
```

The coordinator verifies the qualified seed receipt using `--seed-only`; the
script independently verifies parser manifest identity and the installed
executable SHA-256. Ordinary qualification does not compile or install anything.
Every declared full parser fixture is passed to reference and shadow modes with
identical path, module mode, and untrusted source context. Exit status, binary
syntax stdout, and complete JSON diagnostic stderr must match exactly. Fixture
`trusted` flags belong to the pure producer harness; this CLI does not grant
private intrinsic authority based on fixture metadata.

The driver also exercises valid framed requests, malformed envelope/inner
lengths and versions, token count/span/kind/EOF corruption, invalid invocations,
and missing/corrupt deployment failures. Lexically invalid fixtures remain in
host comparison but cannot supply tokens for direct parser exchange. These are
separate counts in the result. Streams use disk-backed capture with a 64 MiB plus 64-byte
file-size limit and a process timeout. Native unit tests separately verify
sealed execution, stream overflow, malformed reply, and timeout behavior.

`--edit-check` explicitly rebuilds a private source copy using the verified
seed. It adds an executable classification branch to the resource signature
implementation, rebuilds, requires a different producer digest, and repeats
all host comparisons against a private deployment manifest. The host binary
must retain its original digest. `--release` adds release/fact verification to
these explicit private builds; use `MYL_CORE_LEAKCHECK=1` when qualifying them.
The installed deployment and fixture bytes remain unchanged.

`--self-test` validates framing helpers only and makes no installed producer
qualification claim. Complete fixture equality demonstrates the declared
corpus; it does not establish complete language or production cache adoption.
Defaults remain native. Timing runs belong to a separate isolated admission,
never alongside correctness gates.

The `whole-source-1m-v1` package profile uses outer protocol 1/schema 2 for
both whole-source components. Schema 1 manifests and frames are incompatible
and fail closed, even for a small source. The token IDs and inner `SLKPAR01`,
`SLKAST01`, and `SLKERR01` encodings are unchanged. Producer identities include
`whole-source-1m-v1/schema2` and the verified artifact digest.

Source admission is 1,048,576 bytes, shared token admission is 1,048,833 rows,
and parser framed requests are at most 64 MiB. Lexer binary replies are at
most 12,586,068 bytes. Parser replies are at most 64 MiB plus the outer 64-byte
header, with at most 1,048,576 value rows, 4,194,304 child edges, and 64 MiB of
value data and field names. Host decoding separately limits allocations to
512 MiB, graph visits to 4,194,304, expression/statement tables to 262,144 each,
and nesting to 256. The source bound alone does not promise admission of every
possible AST: exhausting an independent bound yields a host/profile failure
(exit 2), with no partial AST or reference fallback.

Profile qualification includes exact source limit and its first excess byte,
dense token transport above the old 100,000-row limit, and a scalar value table
at its exact 1,048,576-row bound followed by the first excess row. The scalar
case proves codec admission only. Native parity uses valid token-rich programs
and exact AST comparisons separately. Run the scalar producer tests with
`--max-memory 1G --max-steps 500000000`, then repeat with
`--release --verify-facts` and `MYL_CORE_LEAKCHECK=1`. These are explicit test
budgets, not a claim that the production launcher installs a new memory limit.
The launcher retains its bounded capture and deadline; final performance and
memory measurements belong to the independent qualification receipt.
