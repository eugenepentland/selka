# A08 source-unit formatter dependency regression correction

Base `0b6f765caceda171aad92fce80f9ce13b13d7dfb`. Coordinator reserved
`src/core/emit_units_test.zig`; no production files changed.

The full gate found two stale assertions that required the floating-point
formatter dependency to belong to a helper unit. Aggregate rendering now emits
`myl_core_values_render` directly against a stack image in the source unit.
`Catalog.finish` follows that unit's descriptor graph and attaches the formatter
declaration when the graph reaches a float; `units.unit` records its dependency.
The implementation already carries the formatter into the native link.

The corrected tests require the dependency on the exact rendering source module
and forbid it on every other unit. They also require the direct render call,
float descriptor and formatter declaration in that same unit. Fresh/cold/warm
text and dependency equality remain checked, as do lazy native-handle identities.
The cache test now links those cached handles and executes the expected float
rendering output. It performs the ordinary ownership pass before this new native
execution and asserts counted exit-live bytes are zero. Counter output uses the
test's private temporary directory.

Both registered focused tests pass, including native output, clean stderr,
formatter linkage and cached-handle restoration. `results.json` records exact
source/test-binary hashes and `focused-02.log` the final result. The first run's
counts remain archived separately; it used the existing ordinary RC path and
observed two runtime releases. This test correction makes no zero-RC claim and
does not alter cache or runtime implementation.
