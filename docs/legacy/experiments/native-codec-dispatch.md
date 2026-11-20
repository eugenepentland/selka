# Internal native codec invocation
> Removed on 2026-09-13: this page records the compatibility C backend, which no longer
> exists. QBE is the only native backend; see [../../experiments/incremental-qbe.md](../../experiments/incremental-qbe.md).

The native embedding runtime can invoke a compiler-selected declared decoder or
encoder inside an existing execution. Generated dispatch cases select only the
functions referenced by checked domain codec contracts. They do not provide a
public function-ID API or make other private helpers callable.

An internal invocation transfers one owned argument, enters the existing compiled
function body, and returns one owned value at the caller's original frame depth.
The caller's earlier operands and frames survive. Instruction and frame budgets,
source locations and the emergency cleanup destination remain shared with the
surrounding operation. Normal public entry/value calls retain their existing
return and cleanup behavior.

The public codec wire API now uses this dispatcher for domain conversion; see
[native-codec-wire.md](native-codec-wire.md). The ordinary wire API retains domain opacity; generated
NativeClient selects the opt-in codec path for domain signatures. Source codec declarations require public, effect-free methods and
complete ordinary wire/error representations without domains or runtime owners.
The internal dispatcher consumes those already-checked contracts.

## Acceptance

`tests/native_codec_dispatch.py` invokes declared codecs from a controlled C test
hook inside a live embedding call. A decoder doubles a positive wire integer and
an encoder adds one to its domain backing; the host observes 15 from input 7.
Negative inputs produce packed scalar or boxed record rejection payloads with
correct ownership. A caller-owned aggregate operand and its frame remain intact
across all calls. A non-codec private helper is rejected by internal dispatch.

Four address/undefined-behavior sanitizer hosts (-O0/-O2, packed/boxed rejection)
check repeated calls, shared step/frame limits, exact decoder/caller trap frames,
allocation-failure sweeps, cleanup and recovery. A Zig compiler allocation sweep
covers emission of declared codec dispatch. The host driver runs in `zig build test`.

## Remaining integration

Public input/output conversion, typed rejection reporting, shared call quotas and
once-only output staging are implemented in the versioned codec wire API.
Generated Python bindings consume that API and expose typed decoder rejections. Existing ordinary-call ABI behavior remains compatible.
