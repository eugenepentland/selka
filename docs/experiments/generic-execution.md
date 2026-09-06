# Executable pure generic specialization

Pure generic templates now execute through the existing typed IR, bytecode VM,
and C emitter. `examples/generics.my` sums both `u8` and `i64` values through the
same recursive template. This implements executable specialization for the
abstract body's supported subset; it does not complete all generic contracts.

## Checking and identities

Every template is checked against its declared guarantees before specialization,
including uncalled templates. Calling an invalid `copy`-only arithmetic template
with `i64` does not make it valid. Concrete callers must supply explicit type
arguments satisfying the template's requirements, and value arguments must match
the substituted parameter types. `main` cannot have type parameters.

Source declaration IDs and executable function IDs are separate. Ordinary
functions are registered first. Generic calls intern the resolved declaration
and concrete type identities, then append newly discovered instances to the
checking queue. Repeated and recursive requests reuse the instance. At most
4096 generic instances are accepted; ordinary functions do not consume that
budget. A located `E_GENERIC_LIMIT` rejects additional discoveries.

Each queued body resolves type-variable spans through that instance's type
arguments. Signatures at a call use the callee's substitutions, while argument
expressions use the caller's. Expression cache entries touched by the previous
body are cleared before the next body, preventing a checked `u8` expression from
being reused as `i64` or a different nominal type. Source spans and original
module context remain intact. Type arguments may include concrete nominal values
when their requirements permit them; template operations remain restricted to
what the declared requirements promise.

## Execution and public interfaces

Instances use ordinary binding, ownership, region, and effect validation and the
existing VM/C lowering. Internal names currently use a reserved `$` plus discovery
ordinal to distinguish instances in dumps and traces. These names are compilation
implementation details, not stable public names or a persistent cache identity.

Concrete module wrappers can call generic templates, execute publicly, and appear
in schemas/bindings. Internal instances are excluded from direct module export
roots. An exported generic template is not itself a callable schema entry: expose
an ordinary wrapper with a concrete signature. Generic schema descriptions and
public type-argument invocation remain unfinished tooling work.

## Boundaries and acceptance

Shared/exclusive reference inputs now have [separate acceptance](generic-references.md).
[Slice inputs](generic-slices.md) are supported too. Lexical
borrow scopes now have [separate acceptance](generic-borrows.md). Reference results,
conversions, general effectful/owned generic bodies, user-defined
requirements, and nominal/composite operations beyond the current abstract rules
still reject explicitly. Builtin `copy`, `equality`, and `integer` constraints do
not imply arbitrary operations, lifetime contracts, or move-only support.

Acceptance covers recursive width specialization, forwarding and repeated calls,
nominal copy values with distinct types, invalid concrete arguments/arity,
uncalled invalid templates, module identity and public schema roots, allocation
failure cleanup, and actual 4096/4097-instance discovery boundaries. Native parity
fixtures include generic recursion, nominal aggregates, integer overflow, and
module calls. Broader generic tooling and all remaining roadmap tracks stay open.

Validation: full core runs passed 573 tests in Debug and ReleaseFast; all 60 CLI
tests passed. Final generic-focused acceptance passed 40 tests, including the
additional returned-reference identity regression. Native parity passed 2640
comparisons across 86 single-file and 16 module fixtures with -O0/-O2 and undefined
behavior sanitization; 50 final targeted codec comparisons passed after inserting
an uninstantiated template before codec functions. Guardian passed all 88 checks
with baselines disabled. No new full resource/provider-suite result is claimed.
