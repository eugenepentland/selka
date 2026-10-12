# S03 completed warm boundary comparison

B0 `c1857310e0bf623545380c8de24515f1b9970021` versus prior source
`fbfcaa7a923186a8e773c3760f81c10aa345a432`. No production code changed.

The same eight existing named scalar tests pass on every invocation: three
number grammar tests and five format oracle tests, retaining 115 grammar and
7,754 format rows. C0 compiles/runs seven unnamed import wrappers; B0 runs one.
The minimal `replay_build.zig` preserves the original modules, options, docs,
identity producer and Guardian runner while naming authenticated frozen Debug
compilers, so it avoids redundant compiler builds. This measures test-artifact
preparation/checking, not the whole verification coordinator or full developer
command graph. Snapshot file/recipe hashes are in `source-preparation.json`;
compiler/Zig/Guardian/component hashes are in `tool-authority.json`.

`W-window-00.log` records the S10-approved exclusive window: 20 seconds queue,
then a completed 112.907-second cohort (per-command timings below exclude
admission and source/tool authentication). The command after sourcing the shared
dev environment was:

```
scripts/build-slot.sh timing timeout --signal=TERM --kill-after=10s 300s python3 experiments/development-loop-wave2-20261012/S03/measure_boundaries.py warm-edits --pair 0 --edits 40 --timeout 20
```

Each variant used its qualified private Zig local cache and the existing shared
global cache. Every edit changed the embedded oracle with a different harmless
comment. Variant order alternated. All 80 invocations compiled, passed the eight
named tests plus wrappers, and produced 40 distinct artifact hashes per variant.
The matched comments had identical fixture hashes between variants. Sources were
restored after execution; no result receipt was retained. Raw commands, selected
counts, verdicts, cache paths, artifact hashes, CPU affinity and GNU time RSS/CPU
are in `warm-edits-pair-00.json` and `raw/warm-edits-00-*`.

| Metric | C0 broad filtered root | B0 independent root |
| --- | ---: | ---: |
| Complete command median | 1.041 s | 1.210 s |
| Complete command empirical p95 | 2.644 s | 2.090 s |
| First observed supported whole-root PASS median | 0.544 s | 0.524 s |
| First observed whole-root PASS empirical p95 | 1.109 s | 1.002 s |
| Median maximum process RSS | 180,470 KiB | 158,436 KiB |

p95 is the 38th sorted observation of 40, a cohort empirical estimate rather
than a stable population p95. PASS observation uses 10 ms polling of the
supported Guardian verdict; individual-test feedback remains unknown. GNU time
RSS is a maximum process value including waited children, not concurrent
aggregate memory. See `measurement-summary.json` and its reproducible summarizer.

The median complete command is approximately 16% slower on B0; the measured tail
and process RSS are lower. This is a mixed tradeoff, not a blanket speedup and not
qualification of the entire roadmap's five-/fifteen-second developer-loop targets.
No additional root split or optimization is justified by these observations alone.

## Cold and golden status at this commit

Both full root recipes compile under ordinary build admission without running
the broad test suite. Actual prepared full artifacts total 222,199,394 bytes for
C0 units versus 247,904,346 bytes for B0 units plus scalar. The +25,704,952 bytes
are an observed artifact cost, not a cold latency/RSS comparison. Paired full-root
cold windows remain the next required acceptance work and will be committed
separately.

The first cold experiment rejected an unsupported `zig build --global-cache-dir`
flag; corrected recipes use the environment variable. The corrected attempted
pair then exceeded an underestimated 120-second experiment bound during B0 cold
configuration. Neither attempt published a complete pair. C0's passed partial
observations are descriptive only. Logs are retained in
`A-window-00-rejected-command.log`, `A-window-00.log` and `raw/build-00-*`.
The approved follow-up is a named 240-second experiment exception with separate
300-second outer windows, not a production verification-limit change.

Three golden artifacts are compiled: old harness/old compiler, old harness/B0
compiler, and B0 harness/B0 compiler. Corpus bytes, selection, invocation,
retirement and signature functions match; each checked case retains one real
compiler invocation, so the preserved selection is 222. Prepared input work
remains 222→165 source files and 90,182→66,752 source bytes, with 222 fresh mutable
work directories. No new golden runtime or timing run is claimed.

S10 independently reproduced a native-link FileNotFound failure in a real
2-test command, selecting both tests and passing neither. The observed loader
cache digest differs from the frozen compiler platform review; the compiler
correctly enters an uncacheable path, whose link-staging cleanup bug blocks guest
qualification. Copied evidence/hashes and exact S10 argv are retained under
`native-link-blocker/` and `golden-runtime-blocker.json`. Golden execution is
**blocked/not attempted** after that finding, not a fabricated 222-case failure.
Platform pins were not weakened or refreshed. A memory-owner-approved fix and
matched authenticated repaired compiler are required before runtime comparison.
