# Disk projects and incremental verification

> **Current status (2026-09-16):** this page records the 2026-09-07 disk-project
> and verification plan. The bytecode VM it assumes as the execution target was
> removed on 2026-09-14; QBE native code is the only runtime. Disk projects,
> affected verification and the native development host are live, but semantic
> query reuse is no longer conditional: C1-C4 added per-function checked-body,
> symbolic-template and concrete-specialization reuse plus receipt-first
> native-test selection. Per-function lazy lowering/emission remains open. See
> [development velocity implementation status](../audits/velocity-implementation/final-status.md).

Status: 2026-09-07. Disk loading and the bounded first implementations of phases
1–5 are available. [Verification commands and limits](verification-runtime.md) and
[the persistent development host](development-host.md) describe current behavior.
Production merge-gate adoption remains in shadow/full-gate rollout; no EDA gate was
weakened. Phase 6 has measurement support; finer semantic queries remain conditional.
The phase descriptions below retain the intended architecture and acceptance criteria;
this implementation status takes precedence over their original future tense.
The bytecode VM remains the execution target. Native guest execution is deferred.

## Objective and boundary

Make an application edit cost a language check, bytecode generation and the
verification affected by that edit. Reuse the installed host executable across
projects and agent worktrees. Zig and Guardian remain necessary when developing
the language implementation, VM, native host wrappers or their build configuration.
They are not prerequisites for running an already-built host against `.my` files.
A future language release can distribute host binaries and guest libraries together.

Keep three independent identities: the installed compiler/VM/host, the application
source snapshot, and each verification job's complete inputs. A source edit changes
the application identity; it need not change the installed executable. Loading a
project from disk does not itself provide incremental compilation, cached testing,
HMR, or an atomic snapshot of files being edited concurrently.

## Phase 0 — disk-loaded application development (implemented)

The existing `mylang run-project path/to/main.my` already reads source from disk.
Both application hosts now require an explicit source root:

```sh
# Once when building/updating the implementation, with the pinned Zig toolchain:
zig build -Doptimize=ReleaseFast

# Application iteration: these invoke installed executables directly.
zig-out/bin/mylang check-project src/schematic/guest/main.my
zig-out/bin/schematic-svg --project src/schematic/guest \
  experiments/schematic/fixtures/straps-synth-lmx2595.sexp \
  experiments/schematic/fixtures/lmx2595rhar.sexp \
  experiments/schematic/fixtures/spi.sexp > /tmp/schematic.svg

# Supply the contract's JSON request array, without expected answers:
zig-out/bin/board-trial --project src/board_trial/guest /tmp/requests.json
```

Each invocation freshly loads `main.my` and its transitive imports, checks the
project, emits bytecode in memory and executes it. Imports resolve under the
selected directory using existing module-name rules and project budgets. There is
no executable fallback to embedded guest source. Copying a binary does not copy
an application: supply its source directory explicitly. Absolute paths support
using one binary from an unrelated working directory or multiple worktrees;
relative paths resolve from the invoking process's working directory.

`src/project_files.zig` supplies bounded disk reads to the CLI and application
hosts. `src/embedded_project.zig` retains its historical name but owns compilation
for both provider-backed tests and disk applications. Source diagnostics are
rendered before failed compilation storage is freed. Missing source, invalid code,
and incompatible typed host contracts reject. The host grants the same registered
operations as before; loading source does not give guest code arbitrary filesystem
access. The directory is trusted developer input, not an OS filesystem sandbox.

Zig boundary tests may still embed immutable fixture sources. Running those tests
is implementation verification. The ordinary application loop runs the installed
host or Python acceptance driver directly and does not invoke `zig build`.
The repair-study coordinator still builds an isolated host for each immutable
submission, including Zig baseline submissions; that research harness is separate
from application execution and must report its compilation cost separately.

Acceptance: `tests/disk_projects.py` uses fixed host binaries with no build tools
on PATH. It changes an imported module, adds/removes imports, repairs syntax/type
errors, rejects an incompatible host signature, runs independent source roots,
and changes both real applications. The original schematic matches the saved SVG;
a guest renderer edit changes its colors. A board policy edit changes guest results
while the Zig baseline stays unchanged. Binary hashes and modification times are
unchanged. Zig tests check exact byte limits and cleanup after source/schema errors.

```sh
# No Zig rebuild or Guardian invocation for application acceptance:
python3 tests/disk_projects.py \
  --schematic-runner zig-out/bin/schematic-svg --board-runner zig-out/bin/board-trial
python3 tests/schematic_svg.py --runner zig-out/bin/schematic-svg
python3 tests/board_trial.py --runner zig-out/bin/board-trial --compiler zig-out/bin/mylang

# Implementation regression gate (deliberately uses Zig and Guardian):
zig build test-disk-projects --summary all
```

## Starting point before phases 1–5

- `check-session` and `scripts/watch.py` provide a persistent check process, bounded
  syntax reuse and an exact successful whole-project verdict cache. Watch checks;
  it does not rerun application requests or replace a running program.
- Evaluation and binding experiments cache specific successful results/artifacts.
  They do not constitute a general test-result cache or coordinate duplicate jobs.
- `scripts/verify.py --only` selects declared verification steps and prerequisites
  manually. It does not derive affected tests from changed source automatically.
- Guardian has its own input cache. Its changed-file test filter is an iteration
  aid: tests in transitive importing files can be reported as omitted. That is
  insufficient evidence for skipping those tests in a merge gate.

## Phase 1 — dependency inventory and affected verification (initial implementation)

Extend the existing verification manifest/driver with a versioned input schema
and dependency receipt. The compiler exports its freshly loaded module graph,
resolved import edges, source digests and generated-input receipts. The verification
driver adds test roots, fixtures, generators, configuration, tool executables,
command arguments, relevant environment values and directory/glob membership.
Retain the existing manifest version or explicitly migrate it; reject unknown
versions. No undocumented inference from test names.

Start at module and verification-suite granularity. For a changed dependency,
select the reverse transitive closure of importing modules and consuming suites,
then include prerequisite jobs. Function-level selection can follow once the
checker exposes dependable semantic dependencies. A call graph or last run's
coverage alone cannot prove that a test is unaffected: changed types, generic
instantiations, effects, unexecuted branches and registrations matter too.

Compare old and new inventories so deletions, renames, new imports and newly
matched glob members invalidate consumers. Compiler/VM/host-contract changes
invalidate their consumers. Unknown inputs or an incomplete graph select a broader
suite or the full gate. Treat an external input as declared and hashed, isolated,
or uncacheable; do not assume a filesystem read is harmless because it is rare.

Output every required job as executed, valid cached success, not selected with a
dependency explanation, failed, or blocked. Zero selected tests is never silently
reported as all tests passing. Run selection in shadow mode beside the full gate
before allowing it to reduce merge verification. Keep scheduled full comparisons
after rollout and disable selection on a demonstrated omission.

Acceptance: leaf edits, public type changes, new/deleted modules, generated inputs,
fixture-only edits, config changes and untracked files select the expected suites.
A deliberately broken importing test must be selected. Unknown dependencies must
fall back safely. Record selection time and unnecessary reruns as well as misses.

## Phase 2 — shared content-addressed verification cache (receipt reuse implemented)

Place successful verification receipts in a configurable shared local store,
initially shared by trusted worktrees on one machine. This belongs in reusable
verification tooling/Guardian integration so Zig and Python projects benefit too.
Avoid a language-only scheduling service when the job protocol can be shared.

A job key hashes a versioned canonical encoding of the job definition, dependency
contents and membership, tool identities, compiler/VM/host ABI, target/optimization,
relevant environment, budgets, seeds and gate-policy version. Include Git context
for checks that observe it (history, branch or cleanliness); do not remove HEAD
from Guardian globally. Pure source jobs can share results across different
commits with identical relevant content. Machine/timing identity is separate for
performance measurements. If a dependency cannot be identified, do not cache it.

Execute against an immutable captured snapshot at a stable path. Capture and
recheck a working tree before publishing a development receipt; merge verification
uses the exact candidate Git tree and declared external inputs. Never attribute a
result to a snapshot while reading mutable files from another worktree. Reuse of
Zig's mutable local `.zig-cache` across different worktrees is not a substitute:
the EDA release script documents previous wrong-worktree binary reuse and uses
isolated source-tree caches. Preserve that protection until independently replaced.

Publish complete receipts and artifacts atomically, validating their hashes on
read. Record command, input key, exit result, required test inventory/counts, logs,
producer, timestamps and policy. A hit references the original execution; it must
not pretend tests just ran. Interrupted, corrupt, partial, incompatible or missing
records are misses. Keep failures as diagnostic evidence, not reusable success.
Initially require the configured tests to actually execute on a miss; a build
cache hit alone does not certify a test execution. Bound disk use with garbage
collection that respects active readers/jobs. Scope trust explicitly before any
remote or cross-user cache is introduced.

Acceptance: identical inputs in ten worktrees share verified results; changing
any relevant fixture, tool, option or policy misses. Test truncated receipts,
modified artifacts, process crashes, external inputs and same names with different
contents. Demonstrate that no result can certify another worktree's source.

## Phase 3 — scheduler for concurrent agents (local coordinator implemented)

Build a local coordinator around immutable job keys and snapshots. Clients submit
the required job set; identical queued/running requests subscribe to one execution.
Use a transactional queue with atomic claim, renewable lease, generation/fencing
token and atomic result publication. A dead worker's lease can expire and retry;
a late worker cannot overwrite the replacement's result. Client disconnects do
not invalidate completed evidence or terminate work another client still needs.

Configure CPU, memory and worker limits, with interactive checks, merge verification
and background audit queues. Use bounded priority and aging so interactive demand
does not starve merges. Admit expensive builds according to memory estimates as
well as CPU count. Superseded speculative jobs may cancel when no consumers remain;
process-group cancellation must clean up descendants and release reservations.
Expose queue position, wait reason, subscribers, resource use and cancellation.

Run timing-sensitive performance jobs on a controlled worker or exclusive quiet
window. Cache correctness and structural performance assertions normally; reuse
timing measurements only under an explicit machine/environment/freshness policy.
A timing regression needs repeat measurements before attributing it to an edit.

Acceptance: ten clients requesting one key produce one execution; distinct keys
respect limits. Exercise worker crash, expired lease, stale publication, one-client
cancellation, full cancellation, queue starvation and resource exhaustion. Measure
queue wait separately from execution, not just end-to-end gate duration.

## Phase 4 — combined-merge verification (opt-in certificates implemented)

Verify the actual combined candidate against the latest target base, not merely
the agents' individually green branches. Construct an immutable candidate tree,
derive its full required job set, and obtain valid cached or fresh receipts for
all jobs. Record base commit, candidate tree, participating changes, external
inputs, policy and receipt identities in a merge certificate.

Publish only if that exact candidate and base still match the intended merge;
a moved base or changed candidate requires a new certificate. Reuse receipts only
when their full job keys still match. A rebased commit with identical relevant
content may reuse pure-source results; Git-sensitive checks still observe the new
context. Verify interacting changes together even when each branch passed alone.
Missing receipts, unknown inputs or incomplete selection block certification or
trigger the full gate. This verifies code; it grants no permission to merge/push.

EDA already has a shared prepare lock and same-source-tree/toolchain candidate
adoption. Integrate with that workflow instead of introducing a second competing
release authority. Do not change EDA's current gate policy as part of phase 0.

Acceptance: two individually passing branches that conflict behaviorally fail as
a combined candidate; moving main invalidates the certificate; source mutation
after verification cannot publish. Compare shadow certificates with full gates
before allowing cached/selected verification to certify a merge.

## Phase 5 — persistent development host and safe HMR (synchronous schematic host implemented)

First add an explicit development runner that retains the host process, watches
all guest sources and request inputs, debounces changes and reruns the last request.
Use a captured source snapshot, including newly discovered imports; discard builds
superseded during checking. Bound compiler storage across repeated reloads. This
restart-on-change experience is useful before preserving any guest state.

Then introduce a program-generation owner with checked bytecode, source mappings
and typed host registrations. Build and validate a replacement completely before
swapping the active generation at a request boundary. In-flight calls retain their
old generation and registrations until completion; new calls use the new generation.
Never patch active stack frames or change nominal layouts under live values.
Each initial application request starts with fresh guest state. Persistent native
host state remains subject to the host's explicit lifetime/thread-safety contract.

A compilation or host-contract error must remain visible and identify the failed
source generation. Retain the last successful preview if useful, clearly marked
stale; do not claim it represents the latest source. No failed SVG is published.
Keep successful output replacement atomic. Changes to host wrappers or VM semantics
require a host rebuild/restart. Arbitrary heap/state migration and instruction-level
hot swapping are deferred; later state preservation needs versioned serialization
and explicit migration rules, not memory copying.

Acceptance: source and fixture changes refresh the SVG without Zig; errors preserve
a labelled prior preview; recovery activates the new generation. Exercise edits
during a long request, added/deleted imports, rapid edits, host signature changes,
repeated reload memory bounds and clean cancellation/shutdown.

## Phase 6 — finer semantic reuse, only after measurement

Profile reload/check time after disk loading and job reuse. Extend the current
bounded syntax/verdict caches into explicit semantic queries only where worthwhile.
Keys include compiler semantics, resolved signatures and every observed dependency,
including negative lookups. Changing a body can reuse independent bodies; changing
a public type must invalidate its dependents. In-memory typed IR uses arena-owned
pointers today: do not persist or share those addresses between processes.
Persisted bytecode, if introduced, needs a versioned validated format and host ABI
identity. This work improves bytecode development, not native compilation.

Acceptance: differential cold versus incremental results and diagnostics agree
across additions, removals, ownership/effect/generic changes and failed repairs.
Invalidation traces explain misses; memory and cache size stay bounded.

## Rollout and measures

Deliver phases 1–4 in order, with shadow mode before gate changes. Phase 5 can run
independently once phase 0 is stable; phase 6 follows profiling. Keep ordinary `.my`
project development separate from changing the Zig implementation throughout.

Benchmark a cold run, unchanged repeat, leaf edit, widely imported type edit,
fixture edit, host implementation edit, two interacting branches, and ten concurrent
worktrees. Record median and p95 edit-to-diagnostic, edit-to-test-result and
ready-to-merge latency; queue/build/check/test/performance time separately; executed
versus cached jobs; duplicate jobs coalesced; invalidation reasons; peak memory;
and full-audit omissions. Report actual executions separately from cache hits.
Choose resource and latency targets after measuring this baseline, rather than
promising an unmeasured speedup.

Use the same task corpus and infrastructure for Python, Zig and `.my` comparisons.
Faster verification infrastructure is valuable, but does not by itself demonstrate
that the new language produces fewer bugs. Keep independent behavioral oracles,
repair success, regression/escaped defect counts and unrelated-edit counts in the
language evaluation alongside development latency.

Phase 0 validation on 2026-09-07: full Debug interpreter gate 40/40 steps,
864/864 Zig tests and all Python drivers; focused ReleaseFast disk/schematic gate
14/14 steps and 10/10 Zig tests plus application acceptance; formatting and gated
ReleaseFast installation pass. Guardian passes all 88 checks with baselines disabled;
existing report-only size/line findings remain. No speedup estimate is inferred
from these correctness runs.

## Measurement checkpoint and remaining scope

`scripts/profile_development.py` measures cold CLI checks, exact warm check-session
verdicts and changed-body checks on a private copy of an application. The recorded
[schematic sample](../../experiments/incremental-development/profile-schematic.json)
used the ReleaseFast host and five samples per case: median/p95 8.23/8.49 ms cold,
1.07/1.17 ms warm, and 3.91/4.49 ms after a renderer literal edit. Cold includes
process startup. This is a local checking measurement, not end-to-end SVG latency,
a controlled benchmark or evidence of language superiority.

These checks do not currently justify a new per-function semantic cache. Keep the
bounded existing caches while measuring larger applications; no persistent typed
IR pointers or bytecode format was introduced. Function-query reuse, produced
artifact transfer/cache, automatic per-test discovery, automatic receipt regeneration,
state migration, concurrent guest requests and production gate replacement remain
outside this bounded release. Verification runs self-contained suites over declared
input closures; tool runtime dependencies remain an explicit completeness obligation.
Native execution remains deferred.

Reproduce the measured check loop:

```sh
python3 scripts/profile_development.py --compiler zig-out/bin/mylang \
  --entry src/schematic/guest/main.my --edit-module svg.my \
  --before '#0d1117' --after '#123abc' --repeats 5 --output /tmp/check-profile.json
```
