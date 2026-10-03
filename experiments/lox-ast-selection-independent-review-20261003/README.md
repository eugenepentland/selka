# Independent AST selection review

Selection commit `37df3ffbfab1f2ea4f269c769eb5b013c5270be3` passes this
read-only review with the previously stated semantic and measurement limits.
No actionable migration, historical reproduction or reporting defect remains.
The review changes only this isolated experiment; it runs no guests, public
tests, native probes or performance commands and edits no root/main/archive or
Guardian feedback files.

`review.json` SHA256 is
`94e583ae655893084a60f852747a973d57ac48ddfc90339bb19fab60106cf890`.
It rechecks 1,798 stable inputs. The new canonical patch is exactly the reviewed
author patch `b1fc1359…`; applying it in memory to the accepted source84 changes
only interpreter.my and produces the exact measured AST source. All 37 files of
the successful canonical replay match. The migration script differs from
accepted 44cd only by appending that patch, without fuzz, after callee/table in
the optimized path. The earlier relative-path preparation failure is retained
and excluded from success claims.

The historical callee/table helper now extracts the pinned source84 archive
`ecb25e84…` and reverses only the callee/table patch. Archive inspection, an
independent forward replay from source80, both exact 37-file maps, six successful
outer commands, tool/compiler/QBE identities and four native build receipts
pass. Four mylang ELFs and Rust match the original measured 80/84 guests byte
for byte. Fresh Go has a separate identity and remains behavior-only. All 156
smoke cells (six arms × 13 scripts × two engines) have exact output hashes and
complete equal collector statistics. Tracked copies match their private raw
receipts. These are new reproduction checks, not new timings.

Fresh selected d14 public qualification is instruction-accounted and distinct
from the prior unaccounted native evidence. Each of four reports has exactly
the 84 names declared by the selected source, 84 executed passes, zero cached,
failed, skipped, dropped or unloaded results, and an empty provider identity.
Their complete gzip reports, raw streams, source snapshots, native test
artifacts and compiler/tool identities pass hash checks. Actual commands use
LLVM `--release`, QBE `--mode ReleaseFast`, RC or native-GC-stress, and retain
the 1e9-step/120s qualification limits. There is no new provider execution,
unaccounted public-test or test O3/full-LTO claim. The inherited 1,264 native
comparisons and eight checked refusals remain separate; 80 native-stress smoke
omissions remain unrun. Historical 4cbae public 336 is not counted as selected
d14 public 336.

`payload-review.json` SHA256 is
`e21c80b7f7e6bcf44f16122d4530266ff512ea3e09df7f5790208db9dd1097c4`.
It verifies that compressed checkpoint copies decompress byte-for-byte to all
previously reviewed 1,976 original rows, and that copied commands, logs and
three analyses match. All ten measured ELFs plus build metadata and runtime
objects remain unchanged. The 42 independently verified comparisons are
inherited without adding rows or rerunning arithmetic on new observations.

The final checkpoint payload map, report, README, selected patch and replay
hashes pass. Metadata now names 44cd as the **control** commit, includes both
complete 780-row matrices, and labels the earlier partial review as historical.
The fresh selected public accounting and exact test modes are explicit.
AST-only tree wall reductions of 3.0541% LLVM / 2.4807% QBE are supported by the
complete paired result; the LLVM case exceptions, per-round variation, modest
gain and native diagnostic limits remain visible. Unused-engine wall movement
is not attributed to a VM optimization; uncertain constant/composed VM gains
remain unselected, and Rust/Go parity remains unmet. Root's separate selection
Guardian receipt passes 88 checks.

To reproduce the review using fresh outputs, run both host-only scripts:

```bash
taskset -c 16 python3 -B experiments/lox-ast-selection-independent-review-20261003/review.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --out .tmp-lox-round3-review-20261003/recheck-selection.json
taskset -c 16 python3 -B experiments/lox-ast-selection-independent-review-20261003/payload-review.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --out .tmp-lox-round3-review-20261003/recheck-selection-payload.json
```

These receipts do not add the preserved 62/320 partial prefixes, previously
reviewed 260 reproduction rows or native/public qualification counts to the
original 1,976 measurement rows. Raw performance stdout/per-sample CSV retention,
toolchain hermeticity, internal malformed-node frames/PCs and tight source-step
cutoffs retain the preceding review's explicit limits. The commit hook supplies
this review's Guardian gate; root consolidates feedback separately.
