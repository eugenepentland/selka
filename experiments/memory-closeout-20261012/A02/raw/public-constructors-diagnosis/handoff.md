# A02 set constructor and generator-extremum diagnosis

Read-only production investigation at worker commit `c3909f2c0fbb97b67acb94714567abe4be33a1ec`. No production patch yet. Source checks and typed dumps use frozen Support6 source `5167c588be79dd43d21d5013c36db15110bf239b`, binary SHA256 `bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`.

## Exact failures

A03's full `sets.my` first diagnostic points to `set({"b": 1, "a": 2})`, not the following `set(evens)`. `set_text_dict_valid.my` and `set_text_list_valid.my` reduce the managed-key issue. Integer set/list controls admit. The generated typed loop borrows the input with `iteration_check`, binds its string child, then submits that child directly to consuming dictionary `write`. A copied key in the handwritten constructor loop admits.

`max_generator.my` and `max_generator_copy.my` both refuse `E_SINGLE_OWNER_LOOP`. `sema_gathers.foldStep` initializes an empty owning string accumulator, then assigns the selected candidate's local. `single_owner.checkStore` interprets that compiler-created temporary assignment as a borrowed root. Its ownership differs from the untaken owner branch at merge, making the accumulator unavailable. This also happens when the yield already calls `.copy()`. The handwritten selected-copy loop admits.

## Proposed isolated changes

- `src/sema_collections.zig`, `checkSetFromIterable`: copy aggregate constructor elements through existing generic `.copy()` lowering before adding them to the independent destination. Leave scalar copies and explicit `set.add` semantics unchanged.
- `src/sema_gathers.zig`, `foldStep` min/max: copy a text candidate only on a selected path so the accumulator remains an owner after iteration. Keep yield evaluation once, scalar folds unchanged, and empty-generator assertion. Fresh/already-copied yields may require further copy optimization; do not claim a saving.

A07 approved these contracts on 2026-10-13 subject to native independence, cleanup, empty trap and side-effect regressions. A04's separate two-parent borrowed selection node and list-extrema best-index lowering are unaffected. Root reservation requested before any production edit.

## Raw evidence and limitations

`results.json`/`results-initial.json` contain exact command lines, source/compiler hashes and admitted elapsed durations. FIFO lease 907 had no wait. Four first handwritten controls accidentally used print without Stream and failed `E_OUTPUT_CAPABILITY`; those sources/results are preserved and are not ownership evidence. Corrected source names end `_valid.my`, with exact successful/ownership-failure commands in `results-corrected.json`, FIFO lease 908 (no wait). Typed dumps are separate `*.typed` files. Full A03 sources remain unchanged; public oracle denominators are18 sets and8 generator tests. This stage has no new native execution, allocation or performance claim.
