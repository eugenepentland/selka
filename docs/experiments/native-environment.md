# Native environment lookup

Generated C supports environment capabilities and bounded lookup through an
explicit host provider. The native builder never grants ambient process-environment
access by default. A missing provider fails entry provisioning with host
CapabilityUnavailable, including when a declared lookup would be skipped.

Provider ABI v2 adds an environment callback receiving borrowed name bytes and
caller-owned output storage with an explicit capacity. Names are byte sequences,
including embedded NUL bytes; they are not implicitly interpreted as C strings.
The result reports presence and complete length. Missing and present-empty values
remain distinct. Output starts zeroed, and bytes beyond a present value's length
are cleared; absent results clear the whole output. Oversized lengths or invalid
presence flags fail with host InvalidProvider instead of returning truncated data.

Statuses unavailable/denied/failed become guest errors 1/2/3. The C provider status
MYLANG_PROVIDER_NO_CAPACITY (5) becomes guest error 4; provider OutOfMemory remains
a host failure. Failed-result length/presence fields and absent-result length are
ignored. The host callback is trusted to stay within its borrowed output buffer.
Returned ordinary values own independent copies, so later lookups cannot alter
prior snapshots. Temporary bytes and partial values join native failure cleanup.

The current factory symbol is mylang_native_providers_v5. Adapters should include the
current native_providers.h and implement its generic mylang_native_providers name.
The builder compiles the adapter source with that header; a stale v1 factory cannot
silently link against v4 emission. Clock/random adapters remain supported when
rebuilt against v4, with absent environment fields granting no environment access.

Acceptance passes 38 VM-checked value/error/call-count comparisons and
56 injected allocation failures at C O0/O2 with address/undefined sanitizers and
live-memory accounting. Coverage includes NUL-containing names, empty names,
zero-capacity output, zero padding, absent/empty values, malformed provider lengths,
errors/OOM, retained snapshots, skipped reads, and missing grants. The actual
builder adapter and ABI rejection checks pass in complete Debug and ReleaseFast
runs: all 30 build steps and 593 core/CLI tests (533 core, 60 CLI). The two provider
VM oracle tests execute separately. Existing native acceptance also passes: 2,616
value/module comparisons, 468 general allocation failures, and 32 clock/random
comparisons with 14 allocation failures.

[Native resource lifecycle](native-resources.md) extends provider ABI v3. Resource
byte I/O now passes acceptance; the wider roadmap remains open.

[Native resource byte I/O](native-resources.md) now extends provider ABI v4; full
array/slice I/O regression acceptance passes.

The current provider ABI is version 5, adding [copied host declarations](native-host.md).
Existing resource adapters remain source-compatible when rebuilt against the header.
