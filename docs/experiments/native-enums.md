# Native closed enums

Native emission supports closed enums in locals, parameters, returns, copies,
mutation, same-type equality/inequality, and exhaustive matches. This works for
single-file programs and checked module projects.

```sh
zig build
python3 scripts/native.py examples/native-enums.my --mode ReleaseFast -o zig-out/enum-example
zig-out/enum-example
```

The example returns 7. Enum values occupy scalar slots containing their checked
variant index. Matching emits a C switch with direct branches to the resolved
arms; source arm order does not change tag identity. Each emitted instruction
retains its VM step-budget tick. Frontend nominal identity and exhaustiveness
checks run before emission, and the bytecode validator checks tag and arm bounds.
No runtime allocation is needed for an enum value in native execution.

Executable parity covers all tags with a weighted result that detects reordered
arms, copied and mutated enum values, equality and inequality, repeated matches
inside loops, a singleton enum, and a trapping arm. The module fixture passes
exported enum values across calls and compares every instruction budget through
completion, including original file paths and call frames. Every fixture runs
under C O0 and O2 with undefined-behavior sanitization. Allocation-failure sweeps
exercise emission and VM execution; semantic rejection cases retain nominal and
exhaustiveness checks. Both payloadless and payload-bearing union constructions
still reject with E_NATIVE_FEATURE.

The combined native harness has 32 single-file fixtures/236 comparisons and seven
module fixtures/156 comparisons per host build mode. These totals include earlier
scalar and domain cases, not only enums. Records, arrays, tagged unions/results,
borrowing, buffers, resources, pools, and arenas still need native implementations
and corresponding executable parity evidence.
