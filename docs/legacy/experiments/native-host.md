# Native copied host declarations
> Removed on 2026-09-13: this page documents a feature that no longer exists in the language.

Native C output now executes `host fn` declarations through provider ABI 5.
Include `native_providers.h` and populate `MylangNativeProviders.host` with
`MylangHostBinding` registrations. The compiler emits private type descriptors;
bindings declare exact qualified function names, parameter/result type names,
effect masks and explicit granted effects. Every declaration is checked before
entry execution, including declarations that are never called. Missing, duplicate,
unknown, mismatched and under-granted registrations fail before guest effects.
The versioned provider factory symbol prevents silently linking ABI-4 adapters.
Recompile adapters against the new header; absent host registries remain empty.

`native_host.h` defines copied preorder `MylangHostNode` values. Scalars carry
bits; records and arrays carry child counts; variants carry their declared case
index and optional payload; domains carry one explicitly typed backing child.
The boundary handles signed/unsigned integer ranges, booleans, nested records,
arrays, enums, variants/results and scalar domains. Host parameters remain ordinary
copied values as required by source checking. Guest resources and borrowed views
do not cross this boundary. No guest pointer is exposed to callbacks.

The callback receives immutable copied argument nodes and a bounded output-node
buffer. Set `output_nodes`, write those nodes and return NULL, or return a static
host error name. `mylang_host_charge(call, amount)` must succeed before an external
effect. Failed charges remain sticky even if a callback later returns success.
The runtime also charges one work unit per call, validates output structure and
ranges, and copies outputs into guest-owned storage. Scratch is registered with
the ordinary native unwinder so traps and allocation failures release it.

Each entry invocation resets call/work budgets. Zero configuration selects 10000
calls, 1000000 work units, 65536 combined input/output nodes and depth 64. Explicit
node limits may not exceed 100000 and depth limits may not exceed 128. Work/call
and copy-budget failures trap as `R_HOST_LIMIT`; callback `HostFailure` traps as
`R_HOST_FAILURE`; malformed copied values trap as `R_HOST_CONTRACT`. Actual host
allocation failures remain host failures. Callbacks and provider contexts are
trusted, synchronous, non-reentrant and must outlive the invocation.

The test adapter writes guest output to stderr so independent VM byte output can
be compared without confusing the native CLI's numeric main return on stdout.
Tests cover Debug/ReleaseFast byte parity, preflight failures, callback failures,
call/work/node limits, malformed results and a generic composite/domain fixture
whose VM result is independently checked. The small five-process timing printed
by the test includes startup; it is not a claim about steady-state throughput.

This stage also implements native scalar domain equality. Typed source JSON operations remain a separately tracked native coverage gap.
[Ordinary JSON parsing](native-json.md) now uses the shared parser support object.
