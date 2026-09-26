# Completed replay of the earlier identity checkpoint

`original-results.json.gz` and `original-run.log.gz` preserve the complete,
failed replay of compiler `d57fef032dae830699e491621027aa418bd05057` without
rewriting any outcome. All 231 selected cases ran on each actual backend:
QBE and LLVM O3/full LTO (`run --release`). The Debug compiler SHA256 is
`4e3cc120f065f63ecb3e8b75ce22c37582c1c4ba623a70853898d8063fd1aedb`.

`original-driver.py` is exactly the loaded driver from `3ab955cd`, whose hash
matches the receipt. The working source advanced while this immutable compiler
was running; the traceback consequently displays lines from a later driver.
The 462 stored outcomes and final failure lists are complete.

The original classifier incorrectly included a build-slot admission message
when recognizing one leading CLI refusal. `normalization-driver.py` preserves
the subsequent classifier, which removes only lines starting `build-slot: `.
`normalized-analysis.json.gz` applies its `signature` function to the original
status, decoded stdout and stderr. It separately verifies that every ordinary
executed guest, including a trap, has a counter record. This is analysis of the
original receipts, not a rerun or a changed expectation.

Results after that normalization:

- 440 executions report `rc-v2-counting`, ten explicitly select legacy GC,
  and twelve CLI refusals correctly have no guest counter record.
- Four output/trap mismatches remain: two arena cases on each backend
  (`6c55b0021d5ed868571a0a8ebed536d2`,
  `6e52fe21c1654619f755a88c87b174bf`). Both unexpectedly trap
  `R_ARENA_ESCAPE`. The later region correction is `1e708148`.
- Four file cases have correct outcomes but unbalanced retirement: two cases
  on each backend (`8af0d3b5da68d266c13761d5d9c83d40`,
  `9f115ba86084917f666491553203ad9f`). Their failed-open error allocation is
  not retired. The later cleanup correction is `dea5c301`.
- There are no other normalized mismatches or missing required counter records.

Both fixes are already on the integration branch with focused before/after
evidence. This receipt covers the old compiler only; it does not claim a full
golden replay of the current compiler or WP-4 performance acceptance.
