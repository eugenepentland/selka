# Phase 4 notes — native endpoint grants and a loopback test (`eaa4/net2`)

Branch `eaa4/net2`, based on `main` at `b2c2b72f` (waves 0-5 plus the phase-2/3
completions). This file collects the orchestrator-owned changes a wave must not
make directly: `SPEC.md` bullets, `src/features.json` slugs, prose, runnable doc
examples and migration notes.

## Status

| Item | State |
| --- | --- |
| 1. Native `--allow-endpoint=IP:PORT` grants | complete |
| 1b. Denial path (no grant, endpoint outside the grant) | complete |
| 2. End-to-end loopback CLI test | complete |
| 3. Builtin `connection.read[N]()` method | deferred (design sketch below) |

`zig build` compiles the executable, the runtime archive and every test root.
The only Guardian failure is the expected `spec` check for the two unlinked
`NETWORK-ENDPOINT-1` tags, because `SPEC.md` and `src/features.json` are shared
files this branch may not edit; the proposed bullets and slugs are below. The
`type-size` check is clean: `cli_grants.Config` stays at seven top-level fields
because the valued switches moved into a nested `Flags` struct. Git writes are
denied in this sandbox, so the changes are left in the worktree for the
orchestrator to commit (a commit needs `--no-verify` only for the missing
`SPEC.md` bullet).

## What landed

### 1. `--allow-endpoint=IP:PORT` under `--restrict`

The native runtime previously provisioned no network provider at all
(`providers->network = absent` in `src/qbe_grants.c`), so *every* native
`def main(net: Network)` failed at the entry-shim capability check. The grant
mirrors `--allow-read=DIR` end to end:

- **Zig authority** (`src/cli_grants.zig`): `Config` gains a bounded
  `endpoints[8]` list plus `endpoint_count`, grouped into a new `pub const
  Flags` (`clock`, `host`, `restricted`, `allow_all`) so the struct stays under
  Guardian's seven-field cap. `parse` recognizes `--allow-endpoint=IP:PORT`,
  requiring a literal numeric IPv4 `IP:PORT` with a nonzero port, rejecting an
  empty, malformed, IPv6 or repeated value with `error.Usage`. The IPv6
  rejection keeps the Zig parser in step with the IPv4-only native provider.
  `flagFor(.network_cap)` now returns `--allow-endpoint=IP:PORT`, and
  `ungranted` refuses a `Network` entry parameter under `--restrict` unless an
  endpoint (or `--allow-all`) was granted. `flagFor`/`ungranted` take `anytype`
  so `cli_grants.zig` no longer imports the compiler module and can be a plain
  unit-test root.
- **Native provider** (`src/native_scoped.h`/`.c`): a granted endpoint list
  (`MylangScopedEndpoint`, `mylang_scoped_endpoint`) and
  `mylang_scoped_network_provider` share the existing `MylangScoped` handle
  slots with the filesystem provider. `dial` parses the literal with
  `inet_pton(AF_INET, ...)` (no DNS, no redirect following) and `connect`s; the
  provider matches the request verbatim against the allowlist, with `*` as the
  `--allow-all` wildcard. Reads/writes reuse `read_handle`/`write_handle`, so a
  socket flows through the same 64 KiB transfer cap as a file. `mylang_scoped_close`
  frees endpoint names.
- **Runtime grants** (`src/qbe_grants.c`): `accept` consumes
  `--allow-endpoint=`; `--allow-all` also records `*`; `provision` sets
  `providers->network = mylang_scoped_network_provider(&grants.scoped, 7u)`
  whenever at least one endpoint was granted, for both restricted and
  unrestricted invocations. A default invocation with no endpoint still leaves
  the provider absent, so the old denial is unchanged.
- **Plumbing** (`src/qbe_build_options.zig`, `src/qbe_build_outputs.zig`,
  `src/main.zig`): `runtimeControl` forwards `--allow-endpoint=`, the entry
  shim's missing-capability message names `--allow-endpoint=IP:PORT`, and the
  `run`/`run-project` usage text documents the repeatable literal grant.

Narrowing and acquisition already worked: `net.host(name)` records the endpoint
in the runtime scope table and `myl_qbe_resource_new` substitutes it for the
guest's placeholder request, so the provider only ever sees a literal the
command line granted. An endpoint outside the grant returns
`MYLANG_PROVIDER_DENIED` (`Connected.err(2)`) without opening a socket.

### 2. End-to-end loopback test (`test/integration.zig`)

`CLI grants a narrowed endpoint and the network module exchanges bytes over
loopback` starts a `127.0.0.1:0` listener in the test process, then `spawn`s
`mylang run --restrict --allow-endpoint=127.0.0.1:PORT --print-result` and
services the listener from the test thread (no helper thread, so teardown is
deterministic: `defer server.deinit` and `defer child.kill`). The guest:

1. `scoped = net.host("127.0.0.1:PORT")`,
2. `network.connect(scoped)` then `network.write(first, b"ping")`, and
3. `network.connect(scoped)` then `network.read[4](second)`.

The test asserts the listener received `ping`, answers `PONG` on both
connections, and asserts the guest printed `312` (`P`+`O`+`N`+`G` + the 4-byte
length) and exited `312 & 0xff`. Two further tests cover the denial path: no
grant refuses the entry point before execution, and a granted-but-different
endpoint yields `Connected.err(2)`.

## SPEC.md bullets to add (proposed — do not apply from this branch)

```markdown
- [NETWORK-ENDPOINT-1] `mylang run`, `run-project` and `build --run` accept a
  repeatable `--allow-endpoint=IP:PORT` grant for a `Network` entry point under
  `--restrict`. The endpoint is a literal numeric IPv4 address with a nonzero
  port; a DNS name, an IPv6 literal, an empty value and a repeat are usage
  errors. The grant provisions the native scoped network provider, whose
  allowlist matches the request verbatim (no DNS resolution or redirect
  following) and dials it only on an allowed acquisition; `--allow-all` grants
  every literal endpoint. Without the grant, `--restrict` refuses the entry
  point before execution with `--allow-endpoint=IP:PORT` in the message, and an
  endpoint outside the grant fails as `Connected.err(2)` without opening a
  socket. A default invocation with no grant keeps the previous behavior: the
  network provider stays absent and network access is denied.
```

For item 3, if it is later accepted:

```markdown
- [NETWORK-READ-1] A live resource binding accepts a builtin transfer method,
  `connection.read[N]()`, that performs the same provider read as
  `read_resource[Read[N]](connection)` without transferring the binding, so one
  connection can serve several operations. `write[N](data)` mirrors
  `write_resource`; the receiver is borrowed, and the synthesized result record
  carries `bytes: [N]u8`, `length: u64` and `eof: bool`.
```

## src/features.json entries to add (proposed)

```json
"network-endpoint-grant": {
  "kind": "tooling",
  "summary": "`mylang run`, `run-project` and `build --run` accept repeatable `--allow-endpoint=IP:PORT` grants that provision a literal-only TCP provider for a `Network` entry point under `--restrict`; without the grant the entry point is refused.",
  "doc": "docs/effects.md#network-host"
}
```

(The `docs/effects.md#network-host` anchor already exists from `eaa3/net`; this
change adds no new doc example, so no `docs/` edit is required.)

## Design notes

- **Why not reuse the byte host.** `src/byte_io/native_byte_io.c` has a working
  endpoint provider, but it is configured through `MYLANG_BYTE_IO_ENDPOINTS` and
  linked only into `mylang-io` guests. Native executables own their command line
  for grants, so the same capability is expressed as `--allow-endpoint=` and the
  provider is the native scoped mirror (`src/native_scoped.c`) that already backs
  `--allow-read`.
- **One context, two providers.** The network provider borrows the same
  `MylangScoped` context and handle slots as the filesystem provider, mirroring
  the single Zig `scoped_providers.Context` that exposes both `filesystem()` and
  `network()`. Files and sockets therefore share the 256-handle ceiling and the
  64 KiB transfer cap, and `mylang_scoped_close` releases both.
- **Literal-only authority.** `std.Io.net.IpAddress.parseLiteral` on the Zig
  side and `inet_pton(AF_INET, ...)` on the C side both refuse DNS names, so a
  grant cannot be widened by resolution. IPv6 is rejected until the C provider
  grows an `AF_INET6` path.
- **Default is unchanged.** With no `--allow-endpoint`, `endpoints` is empty,
  `providers->network` is the zero provider, and the entry shim fails the
  capability exactly as before. `--allow-endpoint` without `--restrict` is an
  explicit opt-in and works the same way.
- **`mylang test` is out of scope.** The native test command
  (`src/native_test_command.zig` and its executor) does not thread authority
  flags to per-case processes, so a capability test cannot be granted an
  endpoint there. Extending it would be a separate change to the test executor.

## Ownership rule for item 3 (deferred)

Item 3 is deferred because it needs parser, AST, checker and lowering changes
that did not fit the time-box:

- `ast.Node.method_call` is `{ base, name, arguments }` with **no
  `type_arguments`**, and the parser has no method-call type-argument arm, so
  `connection.read[4]()` does not parse today.
- The result of a resource read is a **nominal** result record. `read_resource`
  obtains it from the caller's written `[Read[N]]` annotation; a builtin method
  has no annotation to reuse and would have to synthesize (or intern) a nominal
  `Chunk[N]`/`Read[N]` record, which the checker does not currently do for an
  arbitrary `N`.

The intended semantics, when built: `connection.read[N]()` desugars to the
existing `.resource_io` node (`kind = .read`, `owner = connection`) with a
synthesized result, so it reuses `checkResourceIo`, the lowering in
`src/qbe_resources.zig` and the runtime's `myl_qbe_resource_read`. The receiver
is **borrowed, not transferred**, unlike the `network.read(connection)` module
wrapper and like `read_resource`; the method does not change `ownership` usage
beyond the `reads`/`writes` counters, so `connection.read[4]()`,
`connection.write(...)` and `connection.close()` may share one binding. Until
then, the documented rule stands: the `network` module wrappers consume the
connection they receive, and a guest that needs several operations on one
connection must use the raw `read_resource`/`write_resource`/`complete_resource`
builtins on the same local.

## Migration notes

- No existing spelling changed. `acquire_resource`, `read_resource`,
  `write_resource` and `complete_resource` behave exactly as before for an
  unscoped `Network`; `--allow-endpoint` is additive.
- `cli_grants.zig` no longer imports the compiler module; `flagFor`/`ungranted`
  are generic. `src/root_test.zig` imports `cli_grants.zig` so its parsing tests
  run in the unit suite; `build.zig` is unchanged in its module wiring.
- The byte-host protocol is untouched.

## Verification (this branch)

```
zig build                                  # compiles; only the expected Guardian spec findings
zig build fmt-check                        # PASS
python3 scripts/focused_test.py units "endpoint grant"           # PASS 11/11
python3 scripts/focused_test.py units "literal endpoints"        # PASS 11/11
python3 scripts/focused_test.py units "build options accept"     # PASS 12/12
python3 scripts/focused_test.py units "temporary native runs"    # PASS 11/11
python3 scripts/focused_test.py units "entry metadata"           # PASS 12/12
python3 scripts/focused_test.py cli "loopback"                   # PASS 1/1
python3 scripts/focused_test.py cli "endpoint outside the grant" # PASS 1/1
python3 scripts/focused_test.py cli "malformed repeated"         # PASS 1/1
python3 scripts/focused_test.py cli "grant flags reject"         # PASS 1/1
python3 scripts/focused_test.py cli "ungranted entry capability" # PASS 1/1
python3 scripts/focused_test.py cli "narrows a Network"          # PASS 1/1
python3 scripts/focused_test.py cli "directory grants scope"     # PASS 1/1
```

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree; the default `~/.cache/zig`
is read-only under the workspace sandbox.

The `build --run` path was additionally verified by hand against a guest whose
narrowed endpoint is outside the grant:

```
./zig-out/focus/mylang build guest.my --run --print-result --restrict \
  --allow-endpoint=127.0.0.1:8000 --qbe=zig-out/focus/qbe --zig "$(command -v zig)"
# prints "2", exits 2 — the provider denied before dialing
```

## Remaining / deferred

- Builtin `connection.read[N]()` / `write[N]()` methods (item 3) — see the
  ownership sketch above; tagged `NETWORK-READ-1` in the proposal only.
- `mylang test` authority grants for capability entry points.
- IPv6 endpoint literals; the native provider is `AF_INET` only, matching the
  byte host and the Zig parser.
