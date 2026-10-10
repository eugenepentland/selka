# Wave 4A: resumable indexed property campaigns

This pass starts from main `1d202d41bfff888ee91354f706cb74e860dc4b94`, on
`codex/selka-cache-wave4a`, using the unchanged
`0.17.0-dev.1683+5ceec001b` Zig pin. Three Sol 6.1 agents handled generation,
checkpoint storage, and runner integration; the parent reviewed the boundaries,
documented the contract, and qualified real interruption and source edits.

## Behavior

`mylang test app.my --seed 42 --property-policy indexed-v1 --property-runs 4096`
uses a generation schedule independent of the requested passing-case budget.
Increasing the budget preserves earlier generated inputs. The default remains
the legacy policy, including its budget-dependent sizing and batching.

An eligible property stores one cumulative completed prefix. Its key uses the
existing validated target-closure planner, schema, seed, execution limits,
providers, environment, compiler and tool identities. Only the indexed passing
budget is omitted. Both passes and discarded inputs consume ordinals; ordered
precondition tallies survive restoration. Guard checks run before loading and at
each checkpoint, including previously absent cases files and nearer project
configuration candidates.

Publication checks the exact prior record under a per-campaign file lock, then
atomically replaces a checksummed, bounded file. Readers never scan a history of
chunks. Stale writers cannot overwrite another writer's progress. Corrupt,
missing, oversized or inapplicable evidence causes fresh execution. Allocation
failure is explicit; ordinary cache write failure loses reuse.

At most 128 generated inputs enter an indexed batch. A failure or exhaustion
cannot publish that batch. An incomplete or abnormal batch permanently disables
further publication in that search, preventing a later cumulative checkpoint
from covering uncertain work; guard checks continue. Shrinking and reproduction
retain their existing semantics, and indexed reproduction names the policy.

## Qualification

The native regressions cover deterministic scalar/nested generation, budget
extension, discards, exhaustion, shrinking, reproduction, transitive edits,
directory forwarding, corruption recovery, allocation failures, simultaneous
publishers, and source/configuration guards. Force, fact checking, leak checking,
native links and effect eligibility retain their freshness requirements. Fixed
argument tests remain ordinary single trials.

Complete inventory verification passed on the final implementation: **111/111
build steps and 2,640 native tests**, with zero failures. All 39 verification
groups executed, with no prior group results reused; the coordinator confirmed
that inputs remained stable. The documentation run executed 221 examples and
checked 62 more, with zero failures. Format checks and all 88 diff-scoped Guardian
checks also passed. See [verification.log](verification.log) and the coordinator's
[verification.json](verification.json).

The command was `python3 scripts/verify_cache.py --zig
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig -- -j3 --maxrss
8589934592`. It owned admission: build held 8.93 seconds, then the full gate waited
406.15 seconds and held 546.20 seconds. These are operational durations for this
qualification, not an isolated performance comparison. The build summary's
23,923 skipped entries are tests assigned to other shards; the native result
records total 2,640 passed, zero failed and zero skipped.

Focused checks additionally exercised partial reuse followed by an unanswered
failing trial: it reports execution, while a fully restored passing campaign
reports a prefix hit. Final install and that regression passed; see
[final-fix.log](final-fix.log).

The independent [restart harness](qualify_restart.py) sends SIGKILL to its own
campaign process group after observing a checkpoint, then compares restart and
warm results with forced execution. It also edits the source during a million-case
extension and requires `SourceChanged` without a completed report. The final
binary passed both checks; exact counters and hashes are in
[restart.json](restart.json).

| Passing property scenario | Fresh classifications | Reused ordinals | Property processes |
| --- | ---: | ---: | ---: |
| Cold budget 32 | 32 | 0 | 1 |
| Unchanged budget 32 | 0 | 32 | 0 |
| Extend 32 to 64 | 32 | 32 | 1 |
| Restart interrupted budget 4,096 | 3,968 | 128 | 31 |
| Unchanged budget 4,096 | 0 | 4,096 | 0 |
| Forced budget 4,096 | 4,096 | 0 | 32 |

The killed invocation exited with signal 9 and emitted no completed report. The
live-edit campaign stopped with exit 1 after its next checkpoint guard. These
are operational qualification runs under build admission, not isolated throughput
or server-lock speedup measurements. The final product/documentation hashes and
installed compiler identity are recorded in [qualified-inputs.json](qualified-inputs.json).

## Boundaries and follow-up

- This is disposable local process-crash cache progress. It provides neither
  power-loss durability nor a general application journal.
- One completed prefix is retained; smaller budgets can conservatively run fresh.
  There is no arbitrary range history or cross-worktree sharing.
- Indexed mode bypasses coarse test and whole-report success receipts. It still
  checks/builds the test executable through existing compilation caches; the
  zero-process claim refers to property execution. Plain fixed cases under this
  explicit policy remain fresh.
- Cold indexed campaigns may launch more processes than legacy campaigns because
  of the 128-input checkpoint bound. Source/tool validation also runs per chunk.
- Differential fuzz adapters and coverage-guided engine state are Wave 4B work.
  Performance evidence reuse, sharing and application durability remain later
  waves. The developer-only Python harness is not part of source builds or the
  installed compiler.
