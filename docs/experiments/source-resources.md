# C: source external resources and completion

Status: nominal filesystem/network resource types, explicit entry grants, fallible
acquisition/completion, moves/wrappers, lexical and trap cleanup, and transitive
cleanup effects are implemented. Providers remain injected synchronous host
adapters. [Environment access](environment.md) and [fixed-byte-array reads/writes](resource-io.md)
are now implemented. Slice I/O, operating-system adapters, attenuation, arenas/pools,
and other roadmap tracks remain pending.

## Types and acquisition

```text
resource File: filesystem;
resource Socket: network;
result Open { ok: File, err: i64 }
```

`resource Name: filesystem;` and `resource Name: network;` declare distinct nominal,
move-only owned types. They cannot be constructed through record literals, casts,
or ordinary copies. Existing ownership transfer rules apply to locals, calls,
returns, arrays, variants, and wrappers. Whole-resource borrowing remains excluded
by the restricted borrowing experiment; data-access operations need a separate
checked interface.

`acquire_resource[Open](fs, request)` requires `filesystem_cap` for a filesystem
resource or `network_cap` for a network resource. The result success must be the
nominal resource and the error must be i64. Request values currently are fixed
`[N]u8` arrays, including empty arrays; element order and all byte values are
preserved. Capabilities and requests evaluate once, in that order. The adapter
receives borrowed bytes only for the synchronous call. The compiler does not
interpret those bytes as a path, URL, or unrestricted authority: each provider
specifies and validates its request protocol.

Entry parameters can request each of allocator, clock, random, filesystem, and
network capability kinds once, in any order. Helpers receive grants explicitly;
ordinary scalar copies/wrappers of grants share authority and quotas. Each run has
fresh store identities, and all requested entry grants are checked before guest
instructions or provider acquisition callbacks execute.

`vm.Options.resources` has optional `filesystem` and `network` providers,
`max_live_per_kind` (default 1024), and an optional two-entry statistics output
(filesystem then network). The provider/store contracts are defined in the
[backend record](external-resources.md). Missing requested providers produce host
`CapabilityUnavailable`. The CLI supplies neither; it can check/dump
`examples/resources.my`, but running the example exits 2 before acquisition.

Acquisition errors are `Unavailable = 1`, `Denied = 2`, `Failed = 3`, and the
runtime live-resource quota `ResourceLimit = 4`. Provider `OutOfMemory` remains a
host failure. Grant/kind/owner validation precedes resource operations. Ordinary
host allocation failures release all successfully acquired resources under the
provider contract; partial acquisition never implies completion.

## Fallible completion returns ownership on error

```text
struct Failure { code: i64, resource: File }
result Finish { ok: bool, err: Failure }

fn retry(file: File) -> Finish effects(filesystem) {
    match complete_resource[Finish](file) {
        Finish.ok(done) => { return new Finish.ok(done); },
        Finish.err(failure) => {
            return complete_resource[Finish](failure.resource);
        }
    }
}
```

`complete_resource[Finish](file)` consumes its resource expression. The declared
result has bool success and a nominal error record containing exactly the named
fields `resource: File` and `code: i64`, in either declaration order. On success,
the provider consumes the host handle and the result is `ok(true)`. On recoverable
failure, the runtime constructs the error record containing the still-owned resource
and error code. The original source binding remains moved in both cases. The caller
can transfer the returned resource into another completion attempt, propagate the
owned error, or release the error with `_ =` and let fallback release run.

Existing handling checks prevent silent loss of the result. Existing whole-value
projection rules still apply: projecting `failure.resource` transfers its owner;
projecting `failure.code` consumes the wrapper and releases its resource. Reading
the code without consuming the wrapper needed the removed `read_field`, so
code-dependent retry is not expressible today; a completion attempt either retries
unconditionally or propagates. Owned-wrapper borrowing remains pending.

Host OOM is terminal for the run, so the resource is released if completion failed.
If completion succeeded before a later allocation failure constructing its success
result, completion is not undone and no fallback release occurs. The runtime does
not promise transactional external effects. No scope exit, discard, trap, or
acknowledgement implicitly calls completion.

## Cleanup order and effects

Owned locals release in reverse slot order at lexical exits, returns, and unwind;
unfinished operands release in reverse operand order. Aggregates now release nested
fields depth-first in reverse schema order (arrays in reverse index order), without
host recursion or allocation. Named constructor expressions still evaluate in source
order, so schema cleanup order can differ from acquisition order for reordered
initializers. The store is a final safety net for remaining registered resources;
it releases those in reverse acquisition order. A normally released or completed
resource is absent from that final cleanup chain.

Acquisition, completion, and fallback cleanup contribute the resource kind's effect.
A function's owned parameter, local, or return types conservatively contribute all
contained resource cleanup effects, even if one execution forwards rather than
releases the value. This accounts for trap/early-return paths and containing records,
nonempty arrays, and variants. Empty arrays contain no owned values. Capability
possession alone adds no effect. Buffer cleanup still has no external effect.

`noio` rejects filesystem/network ownership and operations directly or through
callees. `effects(...)` enforces the same transitive bounds. `noalloc` permits these
operations because it means guest buffer backing allocation; host adapters and VM
bookkeeping are trusted and may allocate. This does not promise allocation-free
operating-system implementations.

Bytecode validation independently derives cleanup masks from schemas and ownership
signatures/locals, scans operations/calls, and rejects forged effect summaries. It
also validates resource schemas, request shapes, and completion results. Runtime
operand checks reject invalid values/owners. This remains internal emission
validation, not a public untrusted-bytecode loader.

Exact duplicate discovery is `exact-v19`, retaining resource acquisition/completion,
nominal types, capability/request operands, moves, and inferred/declared effects.

## Acceptance

297 tests pass in Debug and ReleaseFast (266 core, 31 actual CLI) on Guardian's
pinned Zig snapshot. Source tests cover explicit authority forwarding, separate
provider grants, full owned-result retry, fallback after all recoverable completion
errors, host OOM, partial acquisition, quota/denial errors, fabrication/type/move
rejection, implicit/transitive cleanup bounds, empty resource arrays, nested wrapper
release order, every instruction-budget trap boundary, recursive frame traps,
malformed emission, and exact discovery identity.

Allocation-failure sweeps exercise compilation, acquisition, failed completion,
retry, dumps, and discovery with no live provider resource left behind. 10,000
acquisition/completion cycles run within 16 KiB live VM storage under a one-resource
quota. Actual CLI tests cover checking, dumping, missing-provider denial, and cleanup
bound rejection across all commands. These tests use local deterministic fakes;
they establish no real filesystem/network protocol or durability guarantee.
