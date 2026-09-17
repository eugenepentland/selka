# Phase 3 notes — `net.host(name)` narrowing and the `network` module (`eaa3/net`)

Branch `eaa3/net`, based on `main` at `ece915f1`. This file collects the
orchestrator-owned changes a wave must not make directly: `SPEC.md` bullets,
`src/features.json` slugs, prose, the runnable doc example and migration notes.

## Status

Goal 1 (`net.host(name) -> Network` narrowing) is complete: the checker, the
bytecode model and validator, the QBE lowering, the host-side scope table and its
acquisition forcing are all wired, and the focused suites are green. Goal 2 (a
Python-shaped surface) landed as a new `network` standard module exposing
`connect`, `read`, `write` and `close`; only `connect` composes cleanly with
`net.host` because resources are linear (see the limitation below). Git writes
are denied in this sandbox, so the changes are in the worktree for the
orchestrator to commit.

`guardian-check all .` reports exactly three `spec` findings: the unlinked tags
`NETWORK-HOST-1` and `NETWORK-SURFACE-1`. Every other Guardian check passes
(`change-classification` is green because the tagged tests are in this change;
`formatting` is clean). A commit needs `--no-verify` only for the missing
`SPEC.md` bullet; the two bullets and slugs are proposed below.

## What landed

### 1. `net.host(name) -> Network`

Mirrors `fs.dir` end to end:

- **Checker** (`src/sema.zig`): a qualified call `net.host(literal)` on a local
  `Network` binding is recognized by `checkNetworkHost`/`checkHostCall`. Exactly
  one positional string-literal argument is required; a dynamic name (or an empty
  or NUL-bearing literal) is `E_NETWORK_HOST`. A non-`Network` receiver falls
  through to ordinary resolution. The node performs no I/O and contributes no
  effect.
- **Typed/bytecode**: new `typed.Node.host_resource` and
  `bytecode.Instruction.host_resource` carry the capability and the `[N]u8`
  literal bytes. Bytecode validation requires a `network` output resource and a
  fixed u8-array name. `lower.zig`, `native_ir.zig`, `typed_walk.zig`,
  `duplicates.zig`, `effects.zig`, `origins.zig`, `disassemble.zig` and `qbe.zig`
  all handle it; the disassembly prints `HOST_RESOURCE -> network_cap`.
- **Host runtime** (`src/qbe_resources.c`): `myl_qbe_host_resource` decodes the
  authority with the same `authority()` sentinel helper as `fs.dir`, requires a
  network capability, records the endpoint in the existing bounded scope table
  (`resource_scopes`, 64 entries) and returns the indexed sentinel
  `-16 - (scope*16 + kind*8 + permissions)`. Re-narrowing is idempotent for the
  same endpoint and traps `InvalidCapability` (`R_CAPABILITY`) for a different
  one, so a derived capability can never widen. `myl_qbe_resource_new` treats a
  scoped network authority specially: the effective request is always the
  recorded endpoint, so `connect` needs no request string. The provider's
  existing `endpoint()` check still decides whether that endpoint is in the
  `--allow-endpoint` grant, so a narrowed endpoint outside the grant is denied.
- **Generic bodies** (`src/generic_bodies.zig`): `capabilityMethodCall` mirrors
  the same literal/arity/`E_NETWORK_HOST` validation symbolically.

### 2. The `network` standard module

`src/stdlib/network.my`, registered in `src/standard_library.zig`, exports
`Connection` (a `network` resource), `Chunk[N]`, `Connected`, `Read[N]`,
`Written`, `Failure` and `Closed`, plus:

- `connect(net: Network) -> Connected effects(network)` — acquires over a
  narrowed capability with a placeholder request; the scope pins the endpoint.
- `read[const N: u64](connection: Connection) -> Read[N] effects(network)` —
  wraps `read_resource`.
- `write[const N: u64](connection: Connection, data: [N]u8) -> Written
  effects(network)` — wraps `write_resource`; `N` is inferred from the argument.
- `close(connection: Connection) -> Closed effects(network)` — wraps
  `complete_resource`.

The wrappers return declared `result` types rather than `Result[T, E]` because a
resource cannot be a `Result` payload (the `Result` template's requirements
reject a non-copyable resource). Guests match `network.Connected.ok(...)`,
`network.Read.ok(...)`, and so on.

### 3. Documentation and doc-coverage

Adding a `src/stdlib/*.my` file makes the doc-coverage gate require a `## network`
section in `docs/standard-library.md` with a runnable example naming every export,
and `doc_coverage.zig`'s `definition_keywords` did not recognize `result` or
`resource` definitions. Both are fixed: the guide gained a `## network` section
(the runnable example only imports the module and returns 0, because the native
`run` path provisions no network provider), and `definition_keywords` now
includes `result` and `resource`, with a `DOCCOV-2` unit test covering them.

## Design detail and the linear-resource limitation

`authority()` already decodes `(kind, permissions, scope)`. `fs.dir` joins the
scope prefix before the provider call; `net.host` instead substitutes the scope
endpoint for the request, which is what makes goal 3 work: after
`net.host("127.0.0.1:8000")`, `network.connect(scoped)` passes only a one-byte
placeholder and the runtime acquires `127.0.0.1:8000`.

The wrappers are **linear**: a resource passed to a function is consumed
(`E_OWNED_CONSUMED` on reuse), so `network.write(connection, ...)` consumes
`connection` and a later `network.read(connection)` is rejected. A guest that
needs several operations on one connection should keep using the raw
`read_resource`/`write_resource`/`complete_resource` builtins on the same local,
which do not transfer ownership. `connect` is the ergonomic, composable piece;
`read`/`write`/`close` are single-use conveniences. A future builtin method
surface (`connection.read[N]()`) would avoid the transfer but needs the checker
to synthesize a nominal result record for each `N`, which this wave did not do.

## SPEC.md bullets to add (proposed)

```markdown
- [NETWORK-HOST-1] `net.host(name) -> Network` narrows a `Network` capability to
  the single string-literal endpoint `name`. It records the scope lazily in the
  same bounded host-side table as `fs.dir`, performs no I/O, and contributes no
  effect. Every acquisition through the derived capability requests exactly the
  recorded endpoint, so a narrowed `Network` composes with a `connect` wrapper
  that takes no request string; an endpoint outside the active `--allow-endpoint`
  grant is still denied. Re-narrowing to a different endpoint traps
  `R_CAPABILITY`. A dynamic, empty or NUL-bearing name is `E_NETWORK_HOST` at
  check time, and the receiver must be a local `Network`.
- [NETWORK-SURFACE-1] The `network` standard module wraps provider acquisition
  and I/O so a guest does not spell the raw builtins: `connect(net)` acquires a
  `Connection`, `read[const N](connection)` and `write[const N](connection, data)`
  transfer bytes, and `close(connection)` completes the handle. The wrappers
  return declared `result` types and contribute the `network` effect; because
  resources are linear, each wrapper consumes the connection it receives.
```

## src/features.json entries to add (proposed)

```json
"network-host": {
  "kind": "language",
  "summary": "`net.host(name)` narrows a `Network` to one literal endpoint; it is lazy, effect-free, and every acquisition through it requests exactly that endpoint.",
  "doc": "docs/effects.md#network-host"
},
"network-python-surface": {
  "kind": "language",
  "summary": "The `network` standard module wraps `connect`, `read`, `write` and `close` over the raw network resource primitives.",
  "doc": "docs/io.md#network"
}
```

The `docs/effects.md#network-host` section is applied in this change (a
`# doc: check` block, so it compiles without a live endpoint); the
`docs/io.md#network` anchor still needs a section when the module slug is added.

## Doc example (applied at `docs/effects.md#network-host`)

````markdown
```mylang
resource Socket: network

result Connected:
    ok: Socket,
    err: int

def main(net: Network) -> int:
    # The narrowed capability pins the endpoint; the request below is ignored.
    scoped = net.host("127.0.0.1:8000")
    request: [1]u8 = [0u8]
    match acquire_resource[Connected](scoped, request):
        case Connected.ok(socket):
            _ = socket
            return 0
        case Connected.err(code):
            return code
```
````

## Migration notes

- No existing spellings changed: `acquire_resource`, `read_resource`,
  `write_resource` and `complete_resource` behave exactly as before for an
  unscoped `Network`. `net.host` is additive.
- `src/standard_library.zig` gains a `network.my` entry. The module list is not
  asserted anywhere, so no test needed migrating.
- The active `mylang build`/`run` runtime still provisions no network provider
  (`src/qbe_grants.c` sets `providers->network = absent`), so `net.host` is
  exercised by the Zig scoped-provider suite and by the `mylang-io` byte host,
  which supplies `scoped_providers.Context.network()`. Native `run` support for
  `--allow-endpoint` would be a separate change.

## Verification (this branch)

```
zig build test-compile                              # clean
zig build test-units                                # PASS 1163/1163
python3 scripts/focused_test.py units scoped        # PASS 27/27
python3 scripts/focused_test.py units standard      # PASS 36/36
python3 scripts/focused_test.py units bytecode      # PASS 20/20
python3 scripts/focused_test.py units nominal       # PASS 97/97
python3 scripts/focused_test.py units generic_bodies # PASS 23/23
python3 scripts/focused_test.py units effects       # PASS 74/74
python3 scripts/focused_test.py units parser        # PASS 15/15
python3 scripts/focused_test.py units doc_coverage  # PASS 19/19
python3 scripts/focused_test.py cli "narrows a Network" # PASS 1/1
python3 scripts/focused_test.py cli resource        # PASS 3/3
python3 scripts/focused_test.py cli capability      # PASS 7/7
python3 scripts/focused_test.py cli grant           # PASS 8/8
mylang doc-coverage .                               # 0 failures, 11 modules
mylang doctest .                                    # 0 failed
```

Runtime narrowing was additionally verified end to end against a recording
provider (scratch, not committed): a guest whose narrowed acquisition ignores an
`IGNORED!` request produced `REQUEST[127.0.0.1:7777]` and
`REQUEST[127.0.0.1:8888]` for two `net.host` scopes, proving the scope endpoint
is the effective request. Reproduce with:

```
zig-out/bin/mylang build netscope.my -o netscope \
  --provider netscope_provider.c --qbe zig-out/bin/qbe --zig "$(command -v zig)"
./netscope --print-result
```

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree; the default `~/.cache/zig`
is read-only under the workspace sandbox. A recording C provider is used instead
of a loopback socket because the native `run` path has no network provider.

## Remaining / deferred

- A builtin method surface on a live `Connection` (`connection.read[N]()`) that
  avoids the linear transfer; needs synthesized nominal result records.
- Native `mylang run`/`build` `--allow-endpoint` support and a loopback
  end-to-end test in the gate. Today only the `mylang-io` byte host serves
  network endpoints, and its Python driver (`tests/byte_io.py`) predates the
  `Host`/`Filesystem` spelling changes and is unwired.
