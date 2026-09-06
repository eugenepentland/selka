# Typed invocation for checked factories

The embedding API can now call an effect-free checked function with ordinary typed
arguments and receive an owned typed value or a source diagnostic. This is the
execution foundation for explicit domain codecs and callable wrappers. Source
codec declarations are described separately; invocation does not add domain support
to implicit JSON decoding.

`vm.invoke(allocator, program, function_id, arguments, options)` validates the complete
bytecode program and selects a function without rewriting its main entry. It rejects
private domain methods, effectful call graphs, reference parameters/returns, and
capability/resource/buffer/pool/handle types anywhere in the complete argument or
result type graph. Internal borrowing within a function remains available. The
existing run/runWithOptions API still returns an i64 and injects entry capabilities
according to its existing options.

For modules, `project_compile.Compilation.invokePublic` accepts a qualified function
name. It checks and lowers the complete loaded project, then selects only an exported
function or public method of an exported domain. It shares the export predicate used
by quality/schema root reporting. It does not allocate an intermediate export list.
Unknown, unexported, and private names cannot become calls through this API.

Arguments are borrowed from the host and copied into the invocation allocator.
The copy checks nominal type identities, integer ranges, aggregate shape, variant
tags/payloads, and moved-field state. Defaults limit the complete argument traversal
to 65,536 values and depth 64; depth cannot exceed 128. Counts are shared across
arguments, and child counts are checked before allocating field arrays. Independent
copies preserve host snapshots and may outlive the host argument allocator.

Invocation defaults are one million guest steps and 256 frames. An optional
steps_executed pointer resets on entry and reports the exact executed instruction
count, including on traps. Zero budgets and invalid traversal limits reject. These
limits do not bound frontend/bytecode validation work or total memory: the supplied
host allocator controls memory availability and may itself be bounded. They also
do not impose an output serialization/value-expansion budget. A future codec caller
must apply its whole-operation memory and traversal policy.

A successful ValueResult owns its value in the supplied allocator; release it there.
Aggregate values use independent owned storage, but nominal IDs refer to the checked
program's type catalog. Trap diagnostics retain compilation-owned names/spans, so
keep the compilation alive when examining/rendering them. Host code remains
responsible for interpreting typed result tags; releasing storage does not establish
that an error was meaningfully handled.

Structural validation cannot prove the invariants of a domain value fabricated by
host code. An explicit decoder must call its designated checked factory on ordinary
wire values and inspect that factory's typed result. The invocation tests demonstrate
this with a Positive domain: its public decoder rejects zero/negative integers and
its public encoder reads successfully constructed values. Raw/private construction
is unavailable through public project selection. Domain JSON decoding still returns
NoImplicitCodec; there is no automatic backing-value shortcut.

Acceptance in src/invocation_test.zig covers checked domain factory success/error
round trips, export/private boundaries, allocation failure at every compiler/call/
copy stage, nested partial-copy cleanup, independent argument allocators, snapshot
preservation, malformed/incorrect argument values, shared traversal budgets, exact
step boundaries, frame-limit traces, authority/effect/reference rejection, and the
unchanged integer main entry. Ordinary codec type checks now share a representation-
independent complete-graph checker while retaining their existing error categories.

[Explicit codec declarations and schema metadata](domain-codecs.md) are now
implemented. Whole-codec budgets, JSON integration, source codec operations,
generated callable wrappers, and other pending roadmap work remain open. This API is an embedding interface, not a foreign ABI or a new CLI mode.
