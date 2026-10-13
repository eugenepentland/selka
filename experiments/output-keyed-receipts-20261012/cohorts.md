# Measurement cohorts (plan Section 5)

Five cohorts measure what the plan changes. Each is a fixed command sequence run
on a frozen tree, in an exclusive window, with admission queue time recorded
beside each sample and never added to it. None of them has been run yet: they
are phase 2 work on the merged tree, scheduled for a quiet window. The
correctness rows in `matrix.py` run first; a cohort is only meaningful on a tree
whose matrix rows pass.

## Common protocol

Every command below starts from a shell in the measured worktree `$T` with the
shared environment sourced:

```bash
cd "$T" && source ~/.config/mylang/dev-env.sh
H=$T/experiments/output-keyed-receipts-20261012     # or the harness checkout
```

**Frozen manifest.** Before the first sample, and again after the last one:

```bash
python3 -B $H/matrix.py --tree "$T" --manifest-only C<N>-before   # ... C<N>-after
```

A manifest (`evidence/manifests/<label>.json`) lists the compiler path and
SHA-256, the tree `HEAD` and the SHA-256 of `git status --porcelain` (null when
clean), the harness SHA-256, the options, the probed features, and the
environment projection: the values of `MYL_*`, `MYLANG_*`, `SELKA_*`, `ZIG*`,
`LD_*`, `LC_*`, `PYTHON*`, `TMPDIR`, `SOURCE_DATE_EPOCH`, `ZERO_AR_DATE`,
`LANG`, `TZ`, `HOME`, `XDG_CACHE_HOME`, and a 16-hex-digit digest (never the
value) of `CODEX_THREAD_ID`, `TERM` and `PWD`. A cohort whose before and after
manifests differ in compiler hash or tree state is void.

**Clocks.** The coordinator takes its own exclusive window with
`--timing-window-seconds`; its `last-run.json` gives the request window
(`elapsed_seconds`), gate occupancy (`gate_admitted_seconds`) and the queue
(`admissions[].admission_wait_seconds`). Other timed commands run as
`scripts/build-slot.sh timing /usr/bin/time -f '%e s %M KiB' CMD`, so the
reported elapsed time excludes the queue that `build-slot:` prints. Builds that
prepare a sample run under `build`, outside the window, and are not timed.

**Reporting.** Every sample, its queue time, the median and the range. Five
samples support a decision, not a p95. Zig summary steps and coordinator members
overlap: never sum them. Unknown telemetry stays unknown.

## C1. Unchanged complete verification, one-shot, 5 samples

Baseline: request window 33.54 s and 36.84 s, gate occupancy 23.02 s and 27.84 s,
35 of 46 groups reused, 11 always fresh, 3,616 of 5,412 guest tests reused
(`experiments/telemetry-cache-invalidation-20261012/REPORT.md`, 12 October, two
requests after the telemetry-directory fix; audit Section 2 quotes 33.5 to
36.8 s). Language fact/leak members are the 13 s critical path (audit B3, B4).
Target: about 13 s less gate occupancy once fact and leak receipts hit.

```bash
python3 -B $H/matrix.py --tree "$T" --manifest-only C1-before
python3 -B scripts/verify_cache.py --zig "$ZIG" --profile complete            # prime; not a sample
for i in 1 2 3 4 5; do
  python3 -B scripts/verify_cache.py --zig "$ZIG" --profile complete --timing-window-seconds 900
  cp .mylang-cache/verification-v*/last-run.json $H/evidence/cohorts/C1/sample-$i.last-run.json
done
python3 -B $H/matrix.py --tree "$T" --manifest-only C1-after
```

Record per sample: `elapsed_seconds`, `gate_admitted_seconds`,
`build_admitted_seconds`, each admission's wait, the reused/fresh counts, the
`language` member telemetry (`executed`, `reused`), and whether all 46 action
keys equal the prime's.

## C2. Front-end comment edit, `mylang test tests/lang`, 5 edits

Baseline: 78 s with 0 of 1,579 tests cached after a comment-only compiler edit
(`docs/audits/new-core-plan-2026-10-05.md`, line 38, 5 October; an empty cache
took 103.8 s, line 70). Target: zero trials; the time is lowering plus emission.

```bash
ln -sfn "$(realpath "$T/../guardian-zig")" $H/work/guardian-zig   # the build's ../guardian-zig
git -C "$T" worktree add --detach $H/work/c2-tree HEAD          # a scratch tree; $T is never edited
S=$H/work/c2-tree; C=$H/work/c2-cache
export ZIG_LOCAL_CACHE_DIR=$S/.zig-cache TMPDIR=$S/.tmp/work; mkdir -p "$TMPDIR"
(cd $S && scripts/build-slot.sh build zig build)
python3 -B $H/matrix.py --tree "$S" --manifest-only C2-before
(cd $S && scripts/build-slot.sh build zig-out/bin/mylang test tests/lang --json --cache-dir $C > /dev/null)   # warm
for i in 1 2 3 4 5; do
  printf '\n// cohort C2 edit %s\n' "$i" >> $S/src/parser.zig
  (cd $S && scripts/build-slot.sh build zig build)                                   # not timed
  (cd $S && scripts/build-slot.sh timing /usr/bin/time -f '%e s %M KiB' \
     zig-out/bin/mylang test tests/lang --json --cache-dir $C) > $H/evidence/cohorts/C2/edit-$i.json 2> $H/evidence/cohorts/C2/edit-$i.stderr
done
git -C $S checkout -- src/parser.zig && git -C "$T" worktree remove --force $S
```

Record per edit: elapsed and max RSS from `/usr/bin/time`, the queue from the
`build-slot:` line, `exec_receipts`, and the `cache.reason` histogram (every
eligible test should read `exec-receipt-hit` or `whole-exec-receipt-hit`). When
execution receipts are behind `MYLANG_TEST_EXEC_RECEIPTS` (rollout week 2),
export it as `1` before the warm run and record it in the manifest.

## C3. Front-end comment edit, complete verification

Baseline: 596 to 1,034 s request window and every group rerun on the 12 October
forced gates (audit Section 2; 612.70 s window and 595.68 s gate occupancy in
the telemetry report). Target: the Zig roots and drivers still rerun; guest and
language groups reuse. Two samples: each costs a near-full gate.

```bash
# In the C2 scratch tree after its warm run, one edit per sample:
printf '\n// cohort C3 edit %s\n' "$i" >> $S/src/parser.zig
(cd $S && python3 -B scripts/verify_cache.py --zig "$ZIG" --profile complete --timing-window-seconds 1800)
cp $S/.mylang-cache/verification-v*/last-run.json $H/evidence/cohorts/C3/sample-$i.last-run.json
```

Record the request window, gate occupancy, queue, every group's state and
reason, and the guest/language member telemetry. Report the remainder honestly:
which groups still rerun and why (their `invalidation` entries).

## C4. Second worktree at the same commit, first verification

Baseline: a cold gate plus hashing 28,859 files and 2.33 GB
(`experiments/development-loop-wave2-20261012/REPORT.md`, "Final complete and
warm verification" table). Target: equal to C1 once the snapshot is hashed.

```bash
# Matrix row 7 prepares both trees; then, in tree B only, as the timed sample:
(cd $B && python3 -B scripts/verify_cache.py --zig "$ZIG" --profile complete --timing-window-seconds 1800 \
   --shared-cache-dir $H/work/07-two-worktrees/shared/verification)
```

Record the request window, gate occupancy, queue, `snapshot_statistics`
(files hashed, bytes, metadata observations) and the reused/fresh counts. One
sample per fresh worktree; three worktrees give three samples.

## C5. Ten agents, one base commit, warm requests

Baseline: ten independent gates through one gate slot, about 100 to 170 minutes
of queue for identical work (audit B2). Target: one execution, nine hits.

```bash
for n in 0 1 2 3 4 5 6 7 8 9; do git -C "$T" worktree add --detach $H/work/c5-$n HEAD; done
# build each tree under `build` (not timed), then start all ten at once:
for n in 0 1 2 3 4 5 6 7 8 9; do
  (cd $H/work/c5-$n && ZIG_LOCAL_CACHE_DIR=$PWD/.zig-cache TMPDIR=$PWD/.tmp/work CODEX_THREAD_ID=c5-$n \
     python3 -B scripts/verify_cache.py --zig "$ZIG" --profile complete > $H/evidence/cohorts/C5/agent-$n.log 2>&1) &
done; wait
```

This cohort measures deduplication, not latency: it runs without a timing
window. Record per request the queue (`admissions[].admission_wait_seconds`),
gate occupancy, and the reused/executed counts; report how many requests
executed each group (target: one). Remove the ten worktrees afterwards.
