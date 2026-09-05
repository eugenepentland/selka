# C: bounded environment lookup

Status: read-only environment capabilities, bounded lookup, typed results, and
transitive environment effects are implemented with injected synchronous providers.
There is no ambient process-environment fallback or CLI provider. Resource data
operations, partial field moves, attenuation, arenas/pools, and other roadmap tracks
remain pending.

```text
struct Entry { bytes: [64]u8, length: u64, present: bool }
result Lookup { ok: Entry, err: i64 }
fn lookup(env: environment_cap) -> Lookup effects(environment) {
    return environment_get<Lookup>(env, new [1]u8 [75u8]);
}
```

`environment_get<Result>(capability, name)` evaluates the capability and fixed u8
array name once, left to right. The capability must be `environment_cap`. The result
must declare i64 error and a nominal record success containing exactly `bytes: [N]u8`,
`length: u64`, and `present: bool`, in any field order. N is the caller-selected
maximum complete value size. Enum-indexed tables do not substitute for byte arrays.

Names and values are raw bytes, with no implicit text encoding, NUL termination,
case normalization, or environment-name expansion. Each trusted provider defines
which names it permits and how they map to its environment view. Names passed to
helpers do not grant access to the process environment or enlarge provider authority.

A missing value succeeds with `present = false`, length zero, and all-zero bytes.
A present empty value succeeds with `present = true` and length zero. A present
nonempty value reports its full length and the exact bytes in that prefix. All
unused capacity is zeroed, even if a provider touched it. Values too large to fit
produce recoverable error 4; truncated success is forbidden. Capacity zero therefore
supports absent/empty values but rejects nonempty values.

Errors are `Unavailable = 1`, `Denied = 2`, `Failed = 3`, and `NoCapacity = 4`.
Provider `OutOfMemory` is a host failure. A provider reporting a length above the
output bound produces host `InvalidProvider`. Normal result handling, acknowledgement,
and propagation rules apply. Returned values are immutable snapshots; the provider
cannot legitimately retain or mutate the borrowed output after the call.

## Authority, providers, and effects

An entry may request one `environment_cap` alongside other distinct capability
kinds. Helpers explicitly copy/forward grants as ordinary capability values. Numeric
casts cannot fabricate them. Grants carry the unique live execution identity;
foreign/closed grants fail before callbacks. All entry grants are checked before
guest instructions run. Providing unused authority invokes no lookup.

Embedders set `vm.Options.environment` to an `environment.Provider` whose context
outlives the run. `get(context, name, output)` receives borrowed slices and returns
null for absent, a complete length for present, or a declared error. Context behavior,
name restrictions, consistency, and completeness are trusted host contracts. The
compiler cannot prove arbitrary host implementations report truthful values. No
mutation operation or cross-lookup snapshot consistency is promised.

Missing requested providers cause host `CapabilityUnavailable`. The CLI checks and
dumps `examples/environment.my`, but running it exits 2 without reading process
state. Local deterministic fakes are the providers used by acceptance tests.

Lookups contribute the `environment` effect through direct calls and recursion.
Possessing a grant alone has no effect. Explicit allowed-effect sets can forbid
lookup. `noio` excludes only filesystem/network and permits environment access;
`noalloc` still constrains guest buffer backing allocation, not host adapter/VM
bookkeeping. Neither bound implies determinism. Byte conversion storage and result
values can produce host OOM. The byte-array adapter is shared with resource requests.

Bytecode independently validates result/name schemas and effect summaries; runtime
checks capability values and provider lengths. Exact discovery is `exact-v21`,
retaining lookup operands, nominal result identity, and inferred/declared effects.

## Acceptance

319 tests pass in Debug and ReleaseFast (286 core, 33 actual CLI). Tests cover explicit
delegation, denied/unused grants, missing/empty/nonempty values, raw NUL/255 bytes,
zero padding, zero capacity, overflow, all provider errors, host OOM, invalid provider
lengths, forged/malformed inputs, transitive bounds, and foreign/closed identities.
Lookup failure through `try` ends active buffer borrows and releases the owner.
Allocation-failure sweeps cover compilation, conversion, lookup/results, dumps, and
discovery. 10,000 lookups fit within 16 KiB live VM allocation and release all storage.
CLI tests cover checking, dumps, missing-provider denial, and effect-bound rejection
across commands. Formatting/whitespace checks pass on Guardian's pinned Zig snapshot.
