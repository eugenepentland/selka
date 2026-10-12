# Support7 common source admission

All 87 assigned A06 sources were checked without modification against the clean
frozen tree at `bed11cf3bf3102ffec44487e431a1573fdf02ad5`. The complete Support7
ReleaseFast installation's compiler SHA-256 is
`540283317dab8009ba38f7bc13a521b1b5048cff99701498acd56da7902259ef`.

The 64 guest fixtures admit 62 and refuse two. All 23 additional core fixtures
admit. There are no tool failures or unmeasured sources. Both refusals are kept:

- `tests/lang/rc_semantic_publication.my:42`, list-field `+=`,
  `E_SINGLE_OWNER_BORROW`; compiler owner A02/coordinator.
- `tests/lang/recursive_values.my:127`, borrowed traversal cursor storage,
  `E_SINGLE_OWNER_BORROW`; migration owner A03. The original remains frozen.

This is source admission, not native qualification or a completed C1 milestone.
`results.json.gz` and `raw.tar.gz` retain every source hash, command, diagnostic,
receipt and exact harness snapshot. The adapter has no migration option and
asserts that compiler and source identities remain unchanged through the run.

The original 87-check run used nine shared leases of at most ten calls or
60 seconds. Receipts separate 572.354 seconds of queue wait from 0.440 seconds
of admitted work. These are scheduling observations, not paired compiler
benchmarks. After seeing that overhead, the coordinator approved subsequent
A03 batches of at most 50 actions or 30 seconds admitted work, whichever limit
is reached first at a completed-action boundary. The shared slot directory,
slot count, memory budget and timing admission rules are unchanged. An
individual action retains its existing timeout and is never killed at the
lease time boundary. No admission is nested.

Native preparation identifies 419 public zero-argument Boolean tests and
17 generated/property tests in the guest group. The actual guest runner must
cover the generated tests; appended-main execution alone is insufficient.
`rc_nonheld_captures.my` also has six private Boolean helpers called by its
native main. `migrated/surface_statements_case_2.my` is exercised through its
importing parent fixture. These contracts must not be omitted as empty files.

The unchanged pinned 81-case corpus plus six supplemental cases requires
435 builds and 695 guest executions across all five modes, plus 30 original
source checks. Its Support7 run is separate from this admission report.
