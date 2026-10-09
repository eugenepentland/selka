# Incremental verification runtime

Implemented 2026-09-07 as opt-in development tooling. Existing Guardian and CI
merge gates remain full gates. These tools certify declared jobs; they do not
authorize a merge or establish that a project's dependency declarations are complete.

## Try it with a `.selka` project

From the repository root, use the installed compiler. Build/update it only when
changing the implementation. Put reports and the shared store outside project source:

```sh
export PATH="$PWD/zig-out/bin:$PATH"
python3 scripts/verify.py examples/incremental-development/verify.json \
  --cache-dir /tmp/selka-verification --report /tmp/verification-before.json
python3 scripts/verify.py examples/incremental-development/verify.json \
  --cache-dir /tmp/selka-verification --report /tmp/verification-warm.json
```

The first run executes two suites; the second reuses two successful receipts.
Edit `invoice/amount.selka` from `return 42;` to `return 40 + 2;`, then run:

```sh
python3 scripts/verify.py examples/incremental-development/verify.json \
  --cache-dir /tmp/selka-verification --previous /tmp/verification-before.json \
  --mode affected --report /tmp/verification-edited.json
```

Only `invoice` executes. `independent` is `not-selected`; the report does not claim
that it ran or that the full manifest passed. A change to `return 43;` fails the
invoice test. An unchanged affected run reports zero selected jobs and exits 1,
rather than calling zero tests a successful verification. `full` considers every
job, using valid receipts; `shadow` executes every selected job freshly and compares
its results with predicted selection. A shadow omission disables selection/reuse
for that policy in the shared store until the declaration is repaired and its
policy identity changed. Changing the policy is not evidence that it is correct.

## Manifest version 2

V1 manifests remain compatible. V2 adds a nonempty top-level `policy` string and
these fields to each existing step:

| Field | Meaning |
| --- | --- |
| `inputs` | Project-relative file globs, including directory membership and executable modes. Missing/new/deleted matches change identity. |
| `tools` | Additional executable/file identities. Command executables are always included automatically. |
| `env` | Environment variable names whose exact values are inputs. Complete jobs receive only these plus keyed absolute PATH entries. |
| `complete` | Explicit assertion that all relevant inputs are declared; defaults to false. |
| `module_graph` | Optional relative path to a current compiler dependency receipt. |
| `depends_on` | Existing prerequisite suite IDs; dependency keys invalidate transitive consumers. |

Command arguments, expectations, budgets, policy, tool contents/modes, PATH,
driver implementation, inputs, declared environment and prerequisite identities
participate in each key. Relative or empty PATH entries reject because executable
resolution must agree between coordinator and snapshot working directories.

`complete` is a trusted declaration, not a discovered proof or an OS sandbox.
Network, clock, randomness, ambient configuration and undeclared filesystem reads
require explicit isolation/inputs or `complete: false`. Executable hashes do not
automatically hash Python packages, Zig libraries or dynamically loaded libraries.
Declare those runtime dependencies too, or keep the job incomplete and uncached.
For complex toolchains, use a maintained dependency inventory; a version string
alone is insufficient. The `.selka` example runs a fixed installed host binary.

Unknown/incomplete inputs and stale graphs conservatively broaden selection and
disable caching for affected consumers. This does not add absent dependencies to
a falsely declared complete job; shadow comparisons and independent tests remain
necessary. Git-sensitive checks continue through existing full gates. The v2
source copies exclude `.git`, so no Git-context cache claim is made.

Each suite is self-contained. `depends_on` controls order/invalidation, but build
outputs are not transferred from one suite's private workspace to another. Put a
build and its consuming tests in one suite, or capture preexisting generated inputs
explicitly. Only verification receipts/logs are reused; produced artifact reuse is
not implemented. Benchmark steps always execute and never reuse timing results.

## Compiler-resolved dependencies

```sh
cd examples/incremental-development/invoice
selka project-dependencies main.selka > /tmp/invoice-dependencies.json
```

The checked `project-dependencies-v1` receipt contains entry name, complete resolved
module/import graph, exact source hashes/byte counts and compiler/toolchain identity.
`--inputs=manifest.json` includes exact manifest bytes consumed by generation;
in-memory generated modules do not need files on disk. Invalid source produces no
complete receipt. No guest code executes to discover dependencies.

To use `module_graph`, place its receipt under the manifest's project root, express
source and manifest paths relative to that root, and declare the current compiler
in `tools`. Regenerate it after edits. Stale/missing receipts select a full uncached
fallback; the driver never trusts an outdated graph to omit tests. Graph generation
is an explicit command in this release, not an automatic parser inside the Python
driver. Use one graph per suite's entry for independent module closures.

## Snapshot and cache guarantees

The coordinator captures a bounded source tree (50,000 entries, 128 MiB), rejects
symlinks/special files, and rechecks exact captured bytes and membership. Oversized
compiler repositories should use a bounded application/test root; this release
does not silently omit `.zig-cache` or introduce arbitrary snapshot exclusions.
Jobs execute at stable private paths keyed by their input identities, not in mutable
agent worktrees. Declared inputs/tools are revalidated before successful publication
and reporting, including after cache hits. Source edits during capture/reporting
fail explicitly. These are trusted-machine snapshots, not protection from a hostile
process rewriting files between checks.

Per-key locks, atomic receipts and hashes protect concurrent publication. Cached
logs retain bounded stdout/stderr bytes and their digests. Failures, interrupted
runs, corrupt receipts and mismatched identities cannot become cached success.
A fixed 256-shard lock namespace bounds lock-file growth; colliding keys may serialize.
Garbage collection respects active job locks; `--cache-max-bytes` controls retained
receipt bytes. Reusing a successful result is recorded separately from execution.
A build-cache hit alone does not assert that tests executed: the declared test
command and expectations must provide that evidence. This release records suite
executions, not automatically discovered per-language test counts or coverage.

## Shared scheduling across worktrees

Add identical scheduler/store locations in every worktree:

```sh
python3 scripts/verify.py examples/incremental-development/verify.json \
  --cache-dir /tmp/selka-verification --scheduler /tmp/selka-verification.sqlite \
  --scheduler-cpus 4 --scheduler-memory 4096 --scheduler-workers 4 \
  --job-cpus 1 --job-memory 256 --priority interactive
```

The SQLite coordinator needs no separate daemon. Clients cooperatively claim jobs;
matching keys subscribe to one execution. CPU/memory/worker budgets are admission
estimates, not kernel resource enforcement. Every client using a store must agree
on its capacity. Priorities are interactive, merge and audit, with aging. Use
`--exclusive` for a controlled performance window; repeat timing measurements and
interpret them independently from correctness receipts.

Worker and subscriber leases recover crashed clients, including abandoned queued
jobs. Generation tokens reject late publication. One cancelled subscriber does not
stop work others need; final cancellation terminates the process group. The Python
`Scheduler.status(key)` API reports queue position, subscribers, wait reason,
reserved resources, queue wait and execution duration. No graphical dashboard or
remote/multi-user scheduler is included.

## Combined-merge verification

```sh
PYTHONPATH=scripts python3 -m verification.merge --repo . --base main \
  --change feature-a --change feature-b --manifest path/to/verify.json \
  --cache-dir /tmp/selka-verification --scheduler /tmp/selka-verification.sqlite \
  --priority merge --output /tmp/merge-certificate.json
PYTHONPATH=scripts python3 -m verification.merge --repo . \
  --validate /tmp/merge-certificate.json --expected-tree EXPECTED_GIT_TREE
```

The tool constructs an unpublished combined candidate, verifies its actual source
in a temporary detached worktree, and records the base, participating refs/commits,
candidate tree, policy and every required v2 job receipt. Individually passing
branches are not sufficient. Validation rechecks moving main/feature refs, exact
candidate tree, tool/environment/driver identities and complete required evidence.
A certificate requires complete v2 inputs and full-manifest success; missing,
not-selected or incompatible evidence rejects. Current Git-sensitive production
gates remain separate requirements. The coordinator neither pushes nor changes a
branch. Production hooks have not been switched to these certificates.

## Evidence and rollout

`tests/verification/run_tests.py --compiler BINARY` runs legacy and v2 verification,
actual compiler receipt, corruption/race, ten-client coalescing, crash/lease,
cancellation and combined-branch regressions. `zig build test-verification` includes
these plus dependency-receipt CLI acceptance and Guardian. `test-interpreter` also
includes them. Keep full existing gates while collecting shadow evidence; a suite
of tool tests alone is not proof that every real project's declarations are sound.

Validation checkpoint: 43 verification tests pass without skips after final review.
The full Debug interpreter gate passed 42/42 steps (861 Zig tests executed, six
schematic tests reused); focused ReleaseFast gates passed 13/13 steps with six
schematic tests executed. Python-only final refinements were covered by the
43-test rerun. Guardian passes all 88 checks with baselines disabled.
