# Wave 4B qualification

Implementation baseline: `028b7a3f7` (Wave 4A), with main unchanged at
`1d202d41b`. Branch `codex/selka-cache-wave4b`, pinned Zig
`0.17.0-dev.1683+5ceec001b`. Three Sol 6.1 agents implemented differential
replay, evidence storage and coverage workers; the parent integrated and reviewed
the coordinator. The [plan](PLAN.md) and [developer documentation](../../docs/tooling/fuzz-campaigns.md)
describe the contract.

## Behavior

`scripts/fuzz_campaign.py` coordinates the four existing compiler differential
targets and explicit libFuzzer executables. Each shard starts independently with
a stable nonzero seed and fixed work budget. Increasing the shard count preserves
previous action keys. Only complete successful shards and concrete corpus replays
publish reusable evidence; an interrupted shard runs again.

The identity includes candidate/component/tool bytes, complete declared inputs,
generator/oracle implementation, settings, environment and host contract. Changed
targets replay retained concrete inputs before new exploration. Old coverage is
never proof about a new binary. External targets require `--hermetic` to attest a
complete deterministic input contract before success evidence can be reused.

Corpus retention is separate from success evidence. Differential bundles preserve
the private baseline, configuration, actual mutations and expectations; coverage
bundles preserve raw bytes. Failed native workers retain original inputs and
attempt bounded minimization, with a separate reproduction check. Corrupt retained
corpus data stops execution unless the user explicitly accepts its loss with
`--discard-corrupt-corpus`.

Lookup, hashing, staging and publication happen outside shared server admission.
Only missing worker actions acquire the gate. Live watches cover all selected
targets until final validation, plus each staged request and its input files
through publication. The worker checks the original request digest before parsing
it, and consumes only explicitly listed initial corpus files. Same-target
coordinators serialize outside server admission; record publication uses short
local locks and atomic checksummed files. Warm hits do not rewrite the corpus
catalog.

## Native qualification

The [actual coordinator harness](qualify_campaigns.py) passed ten invocations
using the installed compiler and an actual LLVM 19 libFuzzer executable. Raw
reports, commands, logs and input identities are preserved in
[coordinator-native](coordinator-native/README.md).

| Scenario | Executed shards | Reused shards | Explored inputs | Replayed inputs | Gate admissions |
| --- | ---: | ---: | ---: | ---: | ---: |
| Differential cold, all four targets | 4 | 0 | 8 | 0 | 4 |
| Differential unchanged | 0 | 4 | 0 | 0 | 0 |
| Differential extension, one to two shards each | 4 | 4 | 8 | 0 | 4 |
| Coverage cold | 1 | 0 | 32 | 0 | 1 |
| Coverage unchanged | 0 | 1 | 0 | 0 | 0 |
| Coverage extension, one to two shards | 1 | 1 | 32 | 0 | 1 |
| Changed engine identity | 2 | 0 | 64 | 8 | 4 |
| Differential restart after interruption | 1 | 1 | 2 | 0 | 1 |
| Differential unchanged after restart | 0 | 2 | 0 | 0 | 0 |

The changed-engine check appends one harmless ELF trailer byte to a private copy.
It establishes exact binary-identity invalidation, not a semantic compiler edit.
Both retained bundles execute before the two fresh exploration shards.

The interruption check sends SIGTERM to its own coordinator after observing one
completed shard. It exited 143 with an incomplete report. Restart reused that
completed shard and executed only the missing one. A subsequent unchanged request
performed no work and requested no admission.

After that run, review found an aggregate-memory-limit issue in the newly added
manifest reader. It now checks inputs while streaming instead of loading all
files before enforcing the limit. A regression proves that it stops reading at
the boundary. The [four native coverage scenarios passed again on that final
worker](coordinator-coverage-final/README.md), with the same execution/reuse
counts shown above. The differential implementation was unchanged.

The [direct differential adapter smoke](differential-native/README.md) separately
passed exploration and exact replay for all four targets under an ancestor with
deliberately invalid configuration. The [positive native engine smoke](coverage-native/README.md)
completed 32 executions and replayed four retained inputs. The
[negative native smoke](coverage-negative/README.md) records expected status 77,
an incomplete result, the retained original input and a one-byte reproduction.

## Repository verification

Full inventory verification passed on the final implementation: **116/116 build
steps, 2,640 native tests, and all 80 new regression checks**. All 40 verification
groups ran, with zero group results reused and stable inputs confirmed. The
inventory covers all 81 required actions with no unclassified actions. Format
checks, documentation coverage, and all 88 diff-scoped Guardian checks passed.
See [verification.log](verification.log) and the coordinator's
[verification.json](verification.json). The build summary's 23,923 skipped entries
are tests assigned to other shards; native result records total 2,640 passed,
zero failed and zero skipped.

The command was `python3 scripts/verify_cache.py --zig
/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig -- -j3 --maxrss
8589934592`, with the worktree-local Zig cache, shared global Zig cache, and
on-disk temporary directory. It owned admission. Inventory/preparation held build
slots for 2.015 seconds total, after 336.533 seconds of FIFO waits; the full gate
waited 5.249 seconds and held 633.984 seconds. These are operational qualification
durations, not an isolated performance comparison. A prior queued invocation was
cancelled before admission to apply the streaming bound fix.

The new suites comprise 13 differential-corpus, 16 evidence-store, 26 coordinator
and 25 coverage-worker regressions. They cover concrete replay/configuration isolation, concurrent
publication, corruption and lost blobs, force/failure behavior, exact request
binding, queued and restored-byte edits, staged input changes, warm reuse,
extension, cancellation and worker process cleanup. The final implementation and
installed compiler hashes are in [qualified-inputs.json](qualified-inputs.json).

## Scope and measured limits

- These are operational correctness runs on the shared server, not isolated
  performance comparisons. In the ten-case run, warm differential validation
  took 9.32 seconds and warm coverage validation 1.59 seconds, despite zero fuzz
  workers and zero gate admission. Exact tool/source snapshots still cost time
  outside the lock. Raw wall/CPU/RSS and admission values are preserved.
- A compiler binary change can correctly invalidate every differential target.
  Selection uses complete declared dependencies; observed coverage alone cannot
  justify excluding code.
- The native C fixture qualifies the libFuzzer adapter. This pass supplies neither
  a coverage-instrumented Selka compiler entry point nor a Zig Maker backend.
- Independent seed shards checkpoint completed work; they do not restore opaque
  engine state midway through a run. Coverage execution counts include startup
  inputs, not only unique discoveries.
- Evidence is bounded local cache state, with no power-loss durability, remote
  sharing or general application-journal guarantee. Broader scheduled exploration
  remains useful.
- The coordinator and its tests are developer-only Python. Existing differential
  gate defaults and the Python-free installed compiler/install graph are preserved.
