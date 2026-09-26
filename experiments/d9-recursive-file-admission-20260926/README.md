# Recursive boxes and builtin file admission

The existing `RECURSIVE-VALUES-1` contract prohibits owned resources, pending
results and capabilities inside shared immutable recursive boxes. The exact
`unique_box_direct.my` source violated that rule: its `Owner` body contains a
`TextFile`. Before this correction it checked successfully, then GC printed `13`
and crashed, while RC printed `7` and crashed. The parent's independent reboxing
prototype instead reached the RC invariant forbidding a finalized body. Those
historical receipts are `parent-qbe-before.json.gz`; all four historical commands
requested QBE, despite using different prototype/compiler labels.

This is an admission bug. Ordinary scoped file bindings are protected by
`E_WITH_RESOURCE`, but a direct `fs.open(...)?` constructor argument is not a named
binding. Generic primitive file traits also serve existing fallible-return
contracts and do not mark a file leaf as a nominal move-only record. The old
recursive-box check therefore missed builtin files through stored fields.

The correction extends the existing iterative schema dependency walk with file
ownership. It follows inline records, variants and nonempty arrays, including
later declarations and instantiated wrappers. Zero-length arrays carry no file;
managed references retain their separate layout. Existing box admissibility now
rejects these file-bearing bodies with `E_RECURSIVE_RECORD`. Native box transfer,
finalization and reboxing invariants are unchanged: no legal finalized recursive
body needs to be relocated under the current language contract.

Global `typed.moveOnly`/`storable` behavior remains unchanged. An initial broader
trial changed those helpers, which rejected legal `Result[TextFile,str]` types at
generic admission; that trial was discarded. Failed unit/build receipts are kept.
The narrow trial first exceeded Guardian's boolean-operator limit; naming the
combined resource obligation resolved it without a waiver.

Validation, using the Debug compiler identified in `summary.json`:

- New focused units: 15/15 cover direct binary/text files, arrays, tuples, a generic
  wrapper declared after its owner, legal empty arrays and acyclic file Results.
- Existing recursive-layout and IO-12 controls: 14/14 pass.
- All four requested backend/runtime combinations reject the exact illegal
  source before native execution. These are frontend diagnostic checks, not
  claims that rejected programs ran on a backend.
- Existing `rc_contract_results` and `recursive_values` run 52 assertions across
  actual QBE/LLVM and GC/RC, with forced uncached verdicts; all pass.
- A nonrecursive record holding a directly opened file crosses a Result return,
  drops cleanly and prints `13` and `Ok('')` in all four combinations. Both RC runs
  allocate/retire 1, acquire/release 0/1 and acquire/release no holds.
- The named-file control still rejects with `E_WITH_RESOURCE`.
- The records/unions guide runs 15 examples and checks the new negative example:
  16 blocks, no failures. Debug install and whole-tree commit Guardian 88 pass.
  Formatting and `git diff --check` pass.

Actual LLVM commands use `--release` without a QBE override. Compressed receipts
retain exact commands, sources, statuses and stderr. Full cumulative gates remain
with the parent integration task; this is no new WP-4 acceptance claim.
