# Bounded affine resource ownership

Generic resource parameters and inline resource carriers preserve the front end's
existing consuming semantics. A function returning a resource carrier has exactly
one provider or resource input. The source checker tracks that input through
acquisition, calls, whole-owner transfer, match payloads and completion failure
carriers. Locally created provider escape and ambiguous origins refuse. Provider
replacement or transfer while a dependent owner remains live also refuses, including
later call arguments and record fields.

Lexical provider keepalive uses are inserted before ownership cleanup. A moved
provider's old binding is cleared before any later lexical use; assignment pins the
previous value before overwriting it. Native keepalive neither counts nor stores
pointers. Resource-owning parameter bits and whole affine match transfers agree with
source ownership. Arbitrary partial record moves remain unsupported.

Validation: `scripts/build-slot.sh build "$ZIG" build test-core
-Dtest-filter='zero RC' -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"`
passed 80/80 on this worker, including unoptimized and verified release execution
with managed leak checking and emitted LLVM RC auditing. Source hashes are recorded
in source-hashes.json; these are development tests, not final integrated evidence.
The standalone lifecycle.my prints `7\n2\n3\nFalse\n` and covers successful and
refused completion, returned failure ownership, try cleanup, lexical restricted
providers, explicit discarded acquisition, break/continue and provider replacement.
Negative tests cover local/ambiguous origin, scoped provider escape, live-provider
replacement and sibling record operand invalidation.

Builtin file-owner return forwarding (Result[TextFile, str]) and capability
aggregates remain separate, visible support work. No legacy RC retirement is
claimed by this commit.
