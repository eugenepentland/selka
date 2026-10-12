# Exact phi identity before ownership

Coordinator reservation: `src/core/phi_cleanup.zig` and focused tests. A07 owns
invocation in `own.functionWithScratch`; the helper alone is not the integrated
fix. Driver dependency `38dc781a897182ffbf1fff0906ec319a007a9154` was cherry-picked
under explicit coordinator authorization as local commit `7005ad4a3`.

A07 reproduced an equality loop whose redundant phi retained the same managed
value as a distinct owner. Initial construction simplification does not revisit
all dependent phis. The helper computes strongly connected components of exact
phi operands after resolving forwarding copies. An entire component rewrites to
one existing value only when every external incoming operand names that value.
All CFG edges remain relevant, including constant-dead edges; equal contents,
field identities and shared lengths do not establish pointer identity. Components
with no external value or distinct external values remain unchanged.

Traversal is iterative. Every phi edge is examined exactly twice, component
membership is constant-time, and existing forwarding copies resolve once through
memoization. Registered regressions cover self and mutual cycles, duplicate
operands, distinct equal-valued roots, missing external roots, malformed forwarding
cycles, 16/4096/16384-node cyclic graphs with equally deep copy chains, and valid
irreducible managed-value control flow verified before and after rewriting.
A07 reviewed the implementation.

`phi-cleanup-focused.log` exposed a test-only Zig parameter-name shadowing error,
corrected in v2. `phi-cleanup-focused-v2.log` passes three structural/scaling tests
and verifies the managed IR before its native build hits the known uncached-object
lifetime bug. After the authorized driver dependency, v3 builds the new test
binary but its component-preparation prerequisite fails rebuilding changed sources
with the immutable seed, which has the old driver bug on the changed host loader
cache. That prerequisite failure remains separate. The exact newly built phi test
binary is then executed directly under shared build admission; these Hand IR tests
do not use installed components. Final execution status is recorded in
`phi-cleanup-direct-v3.log` and must pass before claiming helper qualification.

Direct validation completed successfully: all four tests pass, including native
output `42`, zero leak-check diagnostics, verified IR and RC-free LLVM. Exact test
binary and source hashes are in `phi-cleanup-validation.json`. No full registered
gate or production hook is claimed by this helper commit.
