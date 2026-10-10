# Incremental fuzz campaigns

`scripts/fuzz_campaign.py` retains completed independent seed shards and concrete
inputs. An unchanged campaign executes no fuzz workers and takes no server gate
slot. Increasing `--shards` adds only new shards. Changing a target's complete
dependency identity first replays its retained inputs, then explores again.

The coordinator owns admission; run it directly. It hashes and checks evidence
outside shared admission, then acquires one gate slot for each missing action.
Existing `zig build test` differential checks keep their current commands and
verdicts. `zig build test-fuzz-campaign` tests the new coordination and storage
contracts as part of the full gate. These Python commands are developer tools;
building and running the installed compiler still requires no Python.

`--shared-cache-dir DIR` shares exact success receipts and immutable blobs while
keeping corpus catalogs private. Collection honors active leases and explicit
retention pins; see [shared evidence and retention](cache-retention.md).

## Compiler differential campaigns

```bash
python3 scripts/fuzz_campaign.py differential \
  --zig /path/to/pinned/zig --target incremental --steps 60 --shards 4 --seed 42
python3 scripts/fuzz_campaign.py differential \
  --zig /path/to/pinned/zig --target incremental --steps 60 --shards 8 --seed 42
```

The second command reuses the first four completed shards and runs four more.
Keep `--steps` fixed when extending a campaign: it belongs to shard identity.
Each shard starts a fresh mutation walk and compiler cache, with a stable nonzero
seed derived from the master seed and shard ordinal. A shard is the checkpoint
unit; interruption reruns its unfinished work. This preserves the existing
stateful mutation walks without pretending an arbitrary random-stream position
is a checkpoint.

Omit `--target` to run all four targets, or repeat it to select a subset:

| Target | Comparison |
| --- | --- |
| `incremental` | Cached versus cold check of the incremental fixture |
| `module-projects` | The same oracle with nested modules and import policy |
| `interfaces` | Interface hash assertions and per-module versus whole-program checks |
| `interfaces-generic` | The same interface oracles for generic fixtures |

`--compiler` selects an installed candidate and `--components` can select its
component deployment. The candidate's cold or whole-program mode is the reference
for these adapters. There is no separate reference executable. Both candidate and
oracle implementation therefore change when that compiler's bytes change.

Retained differential inputs contain the complete copied baseline, configuration,
concrete mutations and interface expectations, including rejected attempts.
Replay uses those bytes with current oracles; it does not regenerate the old
interface catalog from a new compiler. Strict campaign execution treats abnormal
compiler exits and timeouts as failures even when two failing commands agree.
Private projects have explicit configuration so an ancestor's `mylang.json`
cannot become an undeclared dependency.

## Coverage-guided targets

Supply a real instrumented libFuzzer executable and a stable target name:

```bash
python3 scripts/fuzz_campaign.py coverage \
  --name parser --engine /path/to/parser-fuzzer --corpus /path/to/seeds \
  --hermetic --input /path/to/runtime-data/ --runs 1000 --shards 4 --seed 42
```

`--hermetic` certifies that the target is deterministic and reads only its input
bytes, declared `--input` files and captured environment. Targets that read a
clock, network, undeclared configuration or other mutable providers cannot make
that promise. Without it, coverage campaigns always execute fresh. Declare all
transitive runtime file inputs, not merely files selected by observed coverage.
Recipes accept required files, recursive directories ending in `/`, and the same
suffix globs as the verification coordinator. Directory recipes exclude hidden
entries, `__pycache__` and `.pyc`; declare any such dependency as a literal file.

Each independent shard starts from an identical immutable copy of the visible
initial corpus, with fixed `-runs`, a nonzero seed and `-reload=0`. Discoveries are
retained for regression replay, but do not silently change later shards' initial
corpus. A changed engine binary, input, schema, flag or declared dependency
invalidates the corresponding target's evidence. Other named targets retain
their own evidence.

The supported completion schema is `libfuzzer-inline8-log-v1`. Workers require
actual inline 8-bit instrumentation and matching final execution counts, in
addition to a successful exit. Unsupported engine output fails qualification.
`--runs` counts libFuzzer executions, including corpus startup, not unique inputs.
Initial files larger than `--max-len` are rejected to prevent certifying truncated
inputs. Per-input timeouts, memory limits, bounded logs and a worker deadline
remain active.

Retained bundles hold raw corpus bytes and checksums independently of coverage
results. Changed targets execute these files before new exploration. Failed
workers preserve original inputs and attempt bounded minimization; minimized
artifacts must reproduce a failure. Neither a corpus nor a seed certifies the
continuation of an unfinished engine process. This adapter uses independent seed
shards, not opaque engine-state recovery. Its corpus and replay conventions follow
[LLVM's libFuzzer documentation](https://llvm.org/docs/LibFuzzer.html).

The repository includes a small native instrumentation fixture for qualification.
It does not yet supply a coverage-instrumented Selka compiler target or a Zig Maker
fuzzer backend. The normal regression tests use simulated engines explicitly;
the Wave 4B evidence also records an actual LLVM runtime smoke test.

## Evidence, interruption and force controls

Success keys include exact compiler/engine and component bytes, tool resources,
Python and harness code, loader libraries, fixtures, execution settings, seed,
environment and host contract. Live filesystem watches remain active through
publication and reject edits even if bytes and timestamps are restored. A compiler
binary change can legitimately invalidate every differential shard.

Only a complete successful shard or replay publishes evidence. Same-target
coordinators serialize outside the server gate; publication uses short per-record
locks and atomic checksummed files. Ctrl-C or termination retains prior completed
actions, while the report remains incomplete. `--force` reruns requested actions
and invalidates their earlier successes before trying them. Leak checking and
unsupported tool/loader environment overrides require fresh execution.

`--cache-dir` defaults to `.mylang-cache/fuzz-v1`; `--report` selects the JSON report
(default `last-run.json` there). Reports distinguish reused shards, executed
shards, corpus replays, completion, failure and admission wait/held durations.
Detailed worker logs and artifacts remain under the cache's `runs/` directory.

Damaged success records are misses. Damaged retained corpus data stops the
campaign: old concrete inputs may not be regenerable. Repair it, or explicitly
use `--discard-corrupt-corpus` to accept the loss and recover whatever valid shard
receipts still reference. This is bounded local cache evidence, with no power-loss
durability or general application-journal guarantee. Keep important regressions
as permanent fixtures and retain broader scheduled exploration.
