# Context marker preflight

Base: `bed11cf3bf3102ffec44487e431a1573fdf02ad5`.
Owned files: `src/core/marker_validation.zig`, `src/core/zero_rc_test.zig`.

A direct/fresh function containing only a borrowed-context marker could reach general validation with malformed block instruction references. The precise red regression crashed with exit 139. Run the existing provider validator's generic bounds preflight for every marker family before local contract and CFG proofs. This preserves all local contracts and does not claim a persisted-cache validation bypass: existing snapshot and lowering readers already reject the invalid block references.

The same focused regression now passes (1 passed, 0 failed, 0 skipped), including valid controls before and after `.none` and out-of-range instruction references. `red.json` and `green.json` record exact source and binary hashes; logs include build admission. Earlier test-authoring compile failures are retained in `initial-compile-errors.log`.

The coordinator completed this saved worker patch after A07 became unavailable. The focused test does not replace the integrated full verification gate. No shared-file request or unresolved issue remains for this defect.

Guardian first found the now-unused `aggregate_provider.hasMarker` public query. The coordinator removed that unreachable helper after the focused test; its tested hash remains in `green.json`, and `final-source.json` records the final source. This is the only post-test source change. Full integration compilation remains required.
