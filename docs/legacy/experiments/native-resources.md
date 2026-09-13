# Native filesystem/network resources
> Removed on 2026-09-13: this page records the compatibility C backend, which no longer
> exists. QBE is the only native backend; see [../../experiments/incremental-qbe.md](../../experiments/incremental-qbe.md).

Native acquisition, completion, permission attenuation, and array/slice byte I/O
are implemented through explicit provider ABI v4. The native instruction switches
now cover every currently defined bytecode operation. This does not complete all
native embedding or performance requirements on the roadmap.

The source contracts remain [resource ownership](source-resources.md),
[resource I/O](resource-io.md), [attenuation](attenuation.md), and
[slice I/O](resource-slices.md).

## Provider interface

Include the current `src/native_providers.h`, implement its generic
`mylang_native_providers` name, and link the adapter with the native builder's
`--provider` option. The header maps that name to `mylang_native_providers_v5`;
older factory symbols cannot silently link against the changed structure.
Contexts outlive the run, and synchronous callbacks must not reenter the generated
program. No ambient filesystem/network adapter is selected.

Each provider family supplies acquisition, completion, and nonfailing,
nonallocating release callbacks. Entry grants check those mandatory callbacks
before guest execution, even when an operation would be skipped. Read/write
callbacks are optional and return guest Unavailable when absent. Permission masks
use read=1, write=2, complete=4; restriction intersects masks, and denied permission
takes precedence over callback availability. Requests are bounded byte sequences,
not implicitly interpreted as paths or URLs.

## Ownership and cleanup

Each family has a growable generation-checked registry, a default quota of 1024
live owners, and reverse acquisition links. Removed slots advance generation;
exhausted generations retire without reuse. Owners retain indices rather than
pointers into a registry that may grow.

Successful acquisition records a pending handle until guest-owner allocation
finishes. Failure there releases the new handle before older guest roots.
Successful completion consumes the handle before result allocation; recoverable
completion failure returns the owner and code in the declared record field order
for retry. Other exits release resources without implicitly completing them.

Emergency cleanup reconstructs temporary roots from reference counts and ownership
edges. It releases temporaries, operands, and locals in the required order using
nonallocating, nonrecursive destruction. Aggregate cleanup follows reverse schema
order, which can differ from construction or acquisition order. Propagation boxes
its outgoing result before clearing unfinished operands. Regression fixtures
reject the former ascending-local, raw-registry, and propagation cleanup orders.

## Byte transfers

Read/write keep the owner live on success and failure. Counts can describe partial
progress but must fit the supplied buffer. EOF is explicit; malformed counts and
invalid C EOF flags fail with host InvalidProvider. Failed-result count/EOF fields
are ignored.

Fixed-array reads return independent, zero-padded values. Array and buffer slice
reads stage provider bytes and commit only the successful prefix, preserving the
original tail and bytes outside the view. Failed reads and zero progress leave
guest bytes unchanged. Ordinary-array replacements are prepared before the
callback so existing snapshots remain intact. Result allocation follows a
successful slice commit, matching the VM's ordering.

## Acceptance evidence

Complete Debug and ReleaseFast runs pass all 31 build steps and 595 core/CLI tests
(535 core, 60 CLI), alongside the three separate provider VM oracle tests and
existing native acceptance drivers. All 88 Guardian checks pass without frozen
violations.

Resource acceptance at C O0/O2 with address/undefined sanitizers covers:

- 114 native outcomes, including 104 exact VM callback-trace comparisons and ten
  checks for malformed C-provider statuses/EOF representations.
- 392 injected allocation failures across lifecycle, array/slice staging, commit,
  result construction, pending acquisition, retries, and mixed-store cleanup.
- Partial and empty transfers, EOF, invalid metadata, retained snapshots,
  unchanged bytes after failed reads, missing callbacks, and attenuation without
  widening authority.
- A filesystem quota fixture that reaches 1024 live owners, rejects the next
  acquisition, releases them, and repeats in the same run to exercise slot reuse.
- Mixed filesystem/network field cleanup and actual `--provider` builder execution.

The unrolled quota fixture's sanitized O2 C compilation took about 106 seconds in
focused acceptance and 118–120 seconds in the full runs. The test harness uses a
separate 300-second C compilation budget and a 90-second execution budget. No
sanitizer or runtime memory check was removed. These are acceptance costs, not a
claim of production compilation performance.

## Registry stress follow-up

Focused acceptance now adds mirrored filesystem/network quota cases: each fills
one registry, successfully acquires in the other, rejects overflow without a
provider call, releases all owners, and repeats. All four O0/O2 executions match
exact VM callback traces. Their sanitized O2 compilations took 112 and 117 seconds.
The existing mixed-store fixture also passed both modes and 30 allocation failures.
These are focused results after the complete-suite baseline above.

A separate internal C harness runs automatically in resource acceptance. Six
sanitizer executions cover both families' stale lookup rejection, stale release
isolation, registry relocation, final-generation reuse and retirement, and both
registries simultaneously holding 1024 owners. Overflow invokes no callback;
release restores capacity. Stale lookup is an internal InvalidOwner host failure,
not a claim about malformed bytecode parity with the VM. All paths end with zero
tracked allocations. Deliberately allowing generation wrap or ignoring generation
on release causes regression assertions to fail.

## Remaining work

Broader native compilation performance and native embedding/bindings remain
open. Generics, source serialization, finer incremental compilation, and the
other requirements in the [roadmap](roadmap.md) remain open as well.

The current provider ABI is version 5, adding [copied host declarations](native-host.md).
Existing resource adapters remain source-compatible when rebuilt against the header.
