# C: source external resources and completion

Status: nominal filesystem/network resource types, explicit entry grants, fallible
acquisition/completion, moves/wrappers, lexical and trap cleanup, and transitive
cleanup effects are implemented. Providers are injected synchronous host
adapters. [Environment access](environment.md) and [fixed-byte-array reads/writes](resource-io.md)
are also implemented; the slice-I/O, operating-system-adapter and arena/pool tracks
this page once listed went with the explicit storage tier on 2026-09-13.

## Types and acquisition

```mylang
# doc: check
resource File: filesystem
resource Socket: network

result Open:
    ok: File,
    err: int
```

`resource Name: filesystem` and `resource Name: network` declare distinct nominal,
move-only owned types. They cannot be constructed through record literals, casts,
or ordinary copies. Existing ownership transfer rules apply to locals, calls,
returns, arrays, variants, and wrappers. The language has had no references or
slices since 2026-09-13, so a resource value is never borrowed: reading and
writing one go through the fixed-array operations in
[resource reads and writes](resource-io.md), and completion consumes the owner.

`acquire_resource[Open](fs, request)` requires `Filesystem` for a filesystem
resource or `Network` for a network resource. The result success must be the
nominal resource and the error must be a 64-bit `int`. Request values currently are fixed
`[N]u8` arrays, including empty arrays; element order and all byte values are
preserved. Capabilities and requests evaluate once, in that order. The adapter
receives borrowed bytes only for the synchronous call. The compiler does not
interpret those bytes as a path, URL, or unrestricted authority: each provider
specifies and validates its request protocol.

Entry parameters can request each of clock, random, filesystem, and
network capability kinds once, in any order. Helpers receive grants explicitly;
ordinary scalar copies/wrappers of grants share authority and quotas. Each run has
fresh store identities, and all requested entry grants are checked before guest
instructions or provider acquisition callbacks execute.

A host supplies the filesystem and network providers. The runtime admits at most
1024 live resources per kind; exceeding that quota reports the recoverable
`ResourceLimit = 4`. A requested provider the host does not offer produces host
`CapabilityUnavailable`. `mylang run` registers a filesystem provider over the
same directory authority as `open` — the working directory by default, and the
`--allow-read`/`--allow-write` trees under `--restrict` (see
[printing, files and command-line authority](../io.md#capabilities)) — and it
registers no network provider, so a network acquisition there fails recoverably.
The request bytes still have to name a path the provider accepts, so
`examples/resources.my`, whose one-byte request names no path, returns the
recoverable `Denied = 2` code.

Acquisition errors are `Unavailable = 1`, `Denied = 2`, `Failed = 3`, and the
runtime live-resource quota `ResourceLimit = 4`. Provider out-of-memory remains a
host failure. Grant/kind/owner validation precedes resource operations. Ordinary
host allocation failures release all successfully acquired resources under the
provider contract; partial acquisition never implies completion.

## Fallible completion returns ownership on error

```mylang
# doc: check
resource File: filesystem

result Open:
    ok: File,
    err: int

class Failure:
    code: int
    resource: File

result Finish:
    ok: bool,
    err: Failure

def retry(file: File) -> Finish effects(filesystem):
    match complete_resource[Finish](file):
        case Finish.ok(done):
            return Ok(done)
        case Finish.err(failure):
            return complete_resource[Finish](failure.resource)


def main(fs: Filesystem) -> int effects(filesystem):
    request: [1]u8 = [42u8]
    match acquire_resource[Open](fs, request):
        case Open.ok(file):
            match retry(file):
                case Finish.ok(done):
                    if done:
                        return 7
                    else:
                        return 0
                case Finish.err(failure):
                    return failure.code
        case Open.err(code):
            return code
```

[`examples/resources.my`](../../examples/resources.my) is this program as a
standalone example. `complete_resource[Finish](file)` consumes its resource
expression. The declared result has bool success and a nominal error record
containing exactly the named fields `resource: File` and `code: int`, in either
declaration order. On success, the provider consumes the host handle and the
result is `ok(true)`. On recoverable failure, the runtime constructs the error
record containing the still-owned resource and error code. The original source
binding remains moved in both cases. The caller can transfer the returned
resource into another completion attempt, propagate the owned error, or release
the error with `_ =` and let fallback release run.

Existing handling checks prevent silent loss of the result. Existing whole-value
projection rules still apply: projecting `failure.resource` transfers its owner;
projecting `failure.code` consumes the wrapper and releases its resource. Reading
the code without consuming the wrapper needed the removed `read_field`, so
code-dependent retry is not expressible today; a completion attempt either retries
unconditionally or propagates.

Host out-of-memory is terminal for the run, so the resource is released if
completion failed. If completion succeeded before a later allocation failure
constructing its success result, completion is not undone and no fallback release
occurs. The runtime does not promise transactional external effects. No scope
exit, discard, trap, or acknowledgement implicitly calls completion.

## Cleanup order and effects

Owned locals release in reverse slot order at lexical exits, returns, and unwind;
unfinished operands release in reverse operand order. Aggregates release nested
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
possession alone adds no effect.

`noio` rejects filesystem/network ownership and operations directly or through
callees. `effects(...)` enforces the same transitive bounds. `noalloc` permits these
operations because it means guest managed allocation; host adapters and runtime
bookkeeping are trusted and may allocate. This does not promise allocation-free
operating-system implementations.

Lowering derives cleanup masks from schemas and ownership signatures/locals, scans
operations and calls, and rejects forged effect summaries before emission. It also
validates resource schemas, request shapes, and completion results. Runtime operand
checks reject invalid values and foreign owners. This remains internal emission
validation, not a public untrusted-bytecode loader.

Exact duplicate discovery is `exact-v19`, retaining resource acquisition/completion,
nominal types, capability/request operands, moves, and inferred/declared effects.

## Checkpoint record

The evidence below was recorded against the bytecode runtime that was the only
runtime until 2026-09-14 and against the explicit storage tier removed on
2026-09-13. It records what the experiment established, not the current runtime.

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
