# Explicit integer operations: how it works

Implementation detail moved out of `docs/integer-operations.md`. The guide keeps the user-visible rule.

## Explicit integer operations

Validation: `zig test src/integer_operations_test.zig` runs width-boundary, constant/generic, allocation-failure and located trap checks in Debug and ReleaseFast.
