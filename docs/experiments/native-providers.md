# Native clock and random providers

Generated C supports clock/random capabilities and reads through explicit trusted
host callbacks. No operating-system provider is selected implicitly. Without a
linked adapter, a requested clock or random entry grant fails with host
CapabilityUnavailable before guest instructions or read callbacks execute.
Unused and short-circuited reads still require declared entry grants.

`src/native_providers.h` defines the C adapter interface. The adapter implements
`mylang_native_providers()` and returns optional callbacks with host-owned contexts
that outlive the synchronous execution. Setup must not perform guest reads. The
header versions its factory symbol as `mylang_native_providers_v2`; incompatible
future interface versions must use a different symbol. Generated C embeds its
interface definition, while the builder supplies the header include directory to
the separately compiled adapter.

Clock callbacks return signed i64 Unix-epoch nanoseconds; random callbacks return
full-width u64 entropy words. Status 0 is success, 1 unavailable, 2 denied, 3 failed,
and 4 host OutOfMemory. The value member is read only on success. Invalid callback statuses are host InvalidProviderResult
failures. Each executed read invokes one callback. Errors propagate through the
language's existing typed-result rules; host failures release native owned storage.
Callbacks are trusted to honor effect declarations. Reads are not transactional:
a later failure cannot undo an already-observed provider call.

The native builder accepts `--provider path/to/adapter.c`. For a deterministic
acceptance adapter (not an operating-system adapter):

```sh
python3 scripts/native.py examples/external-capabilities.my \
  --provider tests/native_provider.c -o .zig-cache/native-providers
.zig-cache/native-providers
```

The focused acceptance driver passes 32 comparisons against shared expectations
also executed through VM callbacks: full-width values, mixed entry ordering,
capability wrappers, typed errors, missing grants, host OOM, and skipped reads.
It additionally passes 14 injected native allocation failures with live-memory
accounting and address/undefined sanitizers. Compiler emission allocation sweeps
pass. Complete Debug/ReleaseFast runs pass all 29 steps and 592 core/CLI Zig
tests after review tightened failed-result handling so ignored value fields are
never read. The existing 2,616 native value/module comparisons and 468 general
native allocation-failure cases also pass. Formatting and all 88 Guardian checks
pass without frozen violations.
[Native environment lookup](native-environment.md) extends provider ABI v2; its
full Debug/ReleaseFast acceptance passes. Filesystem/network resource operations remain pending.
