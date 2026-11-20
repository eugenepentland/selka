# Plain inline results from inert collection receivers

The existing receiver proof accepted scalar results and certified nested managed
read chains, but rejected a terminal `list[Body]` read because the all-float `Body`
is an inline record. Exact `nbody::advance` therefore emitted 24 private
`myl_rc_native_loan` calls. This change removes those calls by admitting a terminal
result whose physical shape has neither counted edges nor unique-drop obligations.

Only the terminal-result predicate changes. The intervening instruction whitelist
remains scalar-only, with existing bounded analysis, anchor liveness, caller-storage,
mutation, callback, projection and arena refusals. H-bearing views, managed values
outside the existing certified nested chain, unique resources and unknown effects
remain on their prior paths.

`qbe_rc_values.finish` copies a borrowed plain inline result into its per-instruction
aggregate scratch before input cleanup. The later anchor cleanup therefore cannot
leave the result pointing into retired collection storage. Named record and fixed
array results survive source replacement or clearing. There is no ordinary owner,
semantic SHARE or callback event removed: these are private lifetime holds during
an inert interval. As with the existing scalar-read proof, their elimination also
eliminates failures from acquiring those internal holds or metadata. Semantic
publication, bounds traps and callback snapshots keep their existing behavior.
No GC lowering, runtime API, arena escape rule or ownership ABI changes.

## Matched diagnostic

Both Debug compilers use the same source with only `steps = 5000000` reduced to
`steps = 10000`. Guests use ReleaseFast QBE or actual LLVM O3/full LTO. These results
isolate this proof extension from the concurrent plain-record write/update and
runtime `retain_replace` work.

| Backend | Before instructions | After instructions | After / before |
| --- | ---: | ---: | ---: |
| QBE | 4,643,037,016 | 2,154,459,021 | 0.464019 |
| LLVM | 3,714,721,205 | 1,647,551,163 | 0.443519 |

Counts are medians of three `instructions:u` runs pinned to CPU10. All outputs
match exactly: `-169075163` and `-169016441`. LLVM baseline samples vary by about
2%; all raw samples are retained. Counted runs on both backends reduce balanced
H pairs from **3,620,039 to 1,520,009**, while O acquisitions/releases remain 1/3,
heap allocations/retirements 2/2, clones zero and uniqueness checks 20,007.
These reduced-input diagnostics do not constitute the full WP-4 acceptance run.

## Correctness checks

- Five guest files pass **44/44 assertions in each of four combinations**:
  QBE/LLVM and explicit GC stress/RC counting, 176 assertions total.
- Four negative-index bounds executions retain `R_LIST_BOUNDS`, including RC
  cleanup on both backends.
- The nine-case unaccounted read-loan driver passes on both backends with identical
  balanced totals: heap 82/82, O 35/117, H 11/11 and six arena allocations.
- Permanent additions cover plain records and fixed arrays after source clearing,
  an index callback that replaces the list, and arena reads during pending writes.
  Structural checks prove inert record reads remove loans while callbacks retain them.
- Focused RC tests **56/56**, formatting and whole-tree Guardian **88/88** pass.

Before compiler SHA-256:
`26ea2be612a3fcd1041e02fc51f402843847cbd8a8850663a2b59be7fb21427c`.
After compiler SHA-256:
`11d7a1936e91503c4d84259ff00bd0ded643aa974a6afff5b514b898effab044`.
The parent source is `32aa30cf`; the combined integration gate remains parent-owned.

[`experiments/d9-rc-plain-read-loans-20260926`](../../experiments/d9-rc-plain-read-loans-20260926)
preserves source hashes, manifests, commands, full outputs, counted controls and
instruction samples. An initial diagnostic build combined `--mode ReleaseFast`
with `--release` and was correctly refused by the CLI; that raw receipt is retained
separately and contributes no measurement. The corrected commands use one form.

To reproduce the matched instruction sample:

```sh
python3 experiments/d9-rc-plain-read-loans-20260926/compare.py \
  /path/to/before/mylang /path/to/after/mylang /path/to/output --cpu 10
```

The driver uses a build slot for each build. Provide separate worktree cache and
temporary directories through the normal environment. Permanent guest checks are
in `tests/lang/rc_read_loans.my`; run with explicit `--gc-stress` or
`--rc-runtime=stats`, adding `--release` for LLVM.
