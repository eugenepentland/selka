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
separate counts in the result. Streams use disk-backed capture with a 32 MiB
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
