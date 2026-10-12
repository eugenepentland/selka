# Support7 actual guest test command

All 64 source files remain in the inventory. Of these, 60 have admitted public
tests; their real supported guest test command ran in all five modes. Per mode,
412 test contracts passed, five failed and three were unsupported. None was
skipped or cached. This includes the 16 generated properties already executed on
the identical compiler and source; their exact evidence is reused, not rerun or
counted twice. Every passing row has an `execute` receipt. Leakcheck was enabled;
these uninstrumented executions make no measured RC-event or performance claim.

Two source-refused files retain 16 public contracts per mode as blocked:
`rc_semantic_publication.my` (six) and `recursive_values.my` (ten, including the
remaining generated recursive property). Two files require separate execution:
`rc_nonheld_captures.my` has six private helpers invoked by its main;
`migrated/surface_statements_case_2.my` is invoked by the passing importing module
`migrated/surface_statements.my`. An absent public test is never an execution pass.

Three additional native blockers repeat across all five modes:

- `value_equality.my`: three unsupported generated aggregate equality helpers.
- `frontend_mut.my`: one wrong mutable-writeback result and one lowering refusal.
- `rc_pin_elide.my`: three indirect mutable-call lowering refusals.

Exact sources, failing function bodies and diagnostics are in
`../Support7-guest-blockers/`. Direct whole-program controls confirm general
lowering/helper failures as well; these are not confined to per-test discovery.
Owners are the coordinator, A07 and A10, with precise dispatch controlled centrally.
No assertions, output oracles or supported API contracts were removed.

All results use frozen source `bed11cf3bf3102ffec44487e431a1573fdf02ad5` and compiler
SHA-256 `540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.
Commands, raw JSON and every receipt are archived. Admission uses up to 50 actions
or 30 seconds before yielding at a completed-action boundary. This is incomplete
Support7 implementation qualification, not C1/default/retirement qualification.
