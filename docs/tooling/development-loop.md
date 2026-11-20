# Development loop measurements and limits

Use `python3 scripts/verify_cache.py --zig /path/to/pinned/zig` for complete
verification with reusable evidence. The coordinator owns admission. The retained
`scripts/cache_session.py` accepts the same options through its `verify` request.
These developer commands do not change installed compiler or guest-test defaults.

The required test matrix keeps optimized-debug language sweeps with the fact and leak
checks, and targeted unoptimized checks. Release builds are not in the gate (the user's
decision of 28 October 2026); `-Dtest-release=true` runs them. Broad unoptimized language sweeps and 28
core mode entries were deferred after the measured trial; see
`docs/tooling/test-layout.md`. Complete verification still requires every action
in that registered matrix. The archived trial's forced partial status does not
apply to the approved matrix.

The verifier records file digests per worktree and reuses them only when device,
inode, size, nanosecond modification/change times, mode and ownership match.
Files close to the record's write time, unsupported filesystems and inconsistent
records are rehashed. Live snapshots still detect mutations through execution
and publication. Use `verify_cache.py --verify` to rehash every input without
forcing valid action receipts to rerun, or `--force` to rehash and rerun the
selected actions. `--verify` executes in its own coordinator so a subscription
cannot discard its rehash requirement.

Admission defaults to `SELKA_ADMISSION_BACKEND=shadow`: the existing FIFO/flock
policy remains authoritative while the candidate scheduler records decisions in
`scheduler-shadow.jsonl` under the shared slot directory. `legacy` disables that
observation; `scheduler` explicitly opts into the candidate. A default switch
requires a reviewed day of real traffic on the final implementation; fixture
passes do not satisfy that requirement.

The candidate accounts for admitted wrappers in one token and memory pool,
serves quiet worktrees fairly within priority, and ages queued work. Reservations
are admission accounting, not process memory caps. Configured timing CPUs form a
persistent reservation; candidate builds exclude those CPUs and can continue
beside timing on disjoint CPUs. Older or unknown owners still drain. Without a
reserved CPU set, timing remains exclusive. Keyed verification subscribers share
an independently guarded worker, and each validates its own evidence; cancelling
one subscriber cannot cancel work still needed by others. These features remain
opt-in while shadow qualification is incomplete.

`--profile complete` is the default. `--profile quick --quick-actions 3` schedules
at most three pending actions, prioritizing changed dependencies and inexpensive
work using explicitly heuristic hints. It reports outstanding required action IDs
in `profile_coverage` and returns 3 for partial feedback, even if all eligible
results were already cached. It cannot report complete verification. The next
complete request reuses qualified completed work and executes the remainder.
Cold preparation still builds the required native artifacts; quick selection
does not promise a five-second cold build.

`--profile proofs` is the complete gate followed by one more run of the `ownership-proof` driver with
the Lean checker's size cap lifted (`docs/tooling/ownership-certificates.md#the-gate-action-ownership-proof`):
run it instead of `complete` before landing a change to `own.zig`, the ownership validator or `proofs/`.

`--profile long-qualification` completes the gate and then executes bounded,
fixed qualification recipes. Its eight obligations are fuzz, scaling, work counters,
Juice instructions, Juice native collectors, Juice runtime collectors, wall-clock
performance and bootstrap. It runs up to six supported obligations by default; `--qualification-target NAME` selects explicit
obligations without removing the others from required coverage.
`--qualification-max-actions N` bounds obligations, `--qualification-timeout N`
bounds each admitted command (default 300 seconds), and
`--qualification-fuzz-steps N` bounds differential steps (default 8, one shard).

Actual compiler work reports, exact completed-test inventories and authenticated
raw captures are retained. Instruction samples remain report-only until provider
coverage and repeatability qualify them. Wall-clock and bootstrap acceptance still
require their separate workstreams. Missing, failed, unsupported or unselected
obligations stay visible and yield partial status 3. Serialized success flags
cannot authorize completion; qualification authority belongs to the current guarded
request. The retained session accepts these options through its existing `verify`
request. Long qualification is not scheduled. The separately installed nightly
integration timer runs `--integration`, described below.

The first development-loop pass adds optional limits and diagnostic reports:

| Option | Meaning |
| --- | --- |
| `--build-timeout-seconds N` | Deadline for each admitted inventory/preparation command |
| `--gate-timeout-seconds N` | Deadline for the admitted selected gate as a whole |
| `--warn-after-seconds N` | Advisory target for coordinator elapsed time excluding admission queues |
| `--timing-window-seconds N` | Exclusive bounded coordinator request; queue and session startup excluded |
| `--budget-policy PATH` | Version 1 or 2 report-only policy with separate expected, regression, deadline, memory and work observations |

Values must be positive finite seconds. No new deadline is enabled by default.
Hard deadlines begin after admission and source revalidation, when the worker is
released. They do not include the queue, and they are command limits rather than
individual test limits. Changing an enforced limit conservatively changes receipt
identity; changing the advisory target preserves reusable evidence and pass/fail.
Scoped policies distinguish admitted action, setup/build and individual-test
clocks. Missing or incompatible measurements remain unknown. Policy loading errors
are reported without changing the test verdict. Automatic per-action enforcement
remains unqualified; a report-only deadline value never installs a watchdog.

For isolated request measurements, run the coordinator directly with
`--timing-window-seconds N`. It obtains shared timing admission before validation
and retains it through execution, publication and reporting. Checkout-lock and
admission waits are reported separately. The report's elapsed scope ends at final
report assembly; an external harness must measure report writing, final output
and session startup for end-to-end latency. Deadline expiry or holder failure
revokes new receipts and reports failure. The window schedules the request and is
no input to any action's result, so it stays out of every action key: a windowed
request reuses receipts a plain request published and the reverse, and windows of
different lengths share receipts (`last-run.json` records its length as
`measurement_window_seconds`). The command deadlines above remain identity
inputs. The 5-second feedback and 15-second p95 targets never become implicit
deadlines. Long qualification owns separate phase admissions and cannot be
combined with this request-wide measurement option.

A timed-out command returns 124. Its isolated Linux supervisor terminates and reaps
owned descendants, including helpers that start new process sessions. After normal
command exit, descendants get up to two seconds to finish existing temporary-cache
cleanup; this time counts against the execution deadline and is interruptible. The two
seconds are counted from the last time a descendant could not run for want of the machine
(it is runnable or in disk wait), up to 60 seconds in all, so a helper that ends in a
fraction of a second on a calm machine (an admission's shadow observer) is not called a
leftover because load slowed it; a descendant that sleeps is a leftover after two seconds
as before.
Live descendants remaining afterward are incomplete execution, status 125.
Before it kills them the supervisor writes one `supervisor: leftover` line per
descendant to standard error, which is the gate log: pid, parent, session,
state, start time and age, working directory and command line. A supervisor
that fails itself writes `supervisor: failed with ...` and its traceback
instead. The gate summary prints these lines as the failure of a run that ends
125 with every build step green.
Cancellation terminates the owned tree; another coordinator's work remains owned
by that coordinator. None of these incomplete outcomes publishes new success
receipts. A subsequent request can retry. The supervisor preserves inheritable
descriptors used by admission and child tooling. Admission's memory-settle helper
has separate ownership: it waits on the slot lock the job holds, for at most the settle
seconds, so a worker that is cancelled while a process of its job still holds the slot
keeps the delay, and one whose job has exited ends it at once.

`.selka-cache/verification-v3/last-run.json` records admission wait, input validation,
worker duration, final validation, publication, selected/reused actions and the
advisory loop target. Preparation failures also record their stage and status.
Per-action `invalidation` compares exact selected file identities and common
identity fields with the previous stable request. The previous request may have
failed; these differences are observations, not proof that it produced a receipt.
Missing, corrupt or oversized diagnostic summaries yield unknown explanations.

File additions, deletions and content/metadata changes name their path. Common
tool, environment and build-configuration changes currently identify
the changed digest field rather than its individual members. The diagnostic files
are separate from successful execution receipts and cannot authorize reuse.
Failed stability checks also retain bounded `stability_diagnostics`: snapshot
role, path or host facet, observed reason, and unknown/truncated status. An edit
restored to its old bytes still invalidates watch authority. Reading a diagnostic
does not clear dirty state. Retained-session runtime failures include the same
bounded reason in their restart message.

Bounded stdout/stderr captures are kept under `last-logs/{inventory,preparation,gate}`
in the same cache directory, with an 8 MiB ceiling per stream. They retain raw
command output locally and are overwritten on the next corresponding execution.
Report entries describe only captures made in that request. Captures, explanations
and report-storage errors are diagnostic and do not change the execution verdict.
Stream truncation and unavailable measurements are explicit.

Zig build summaries supply nested step durations, selected test counts and reported
per-process peak RSS. Registered actions have stable group/member labels that
also appear in the inventory's `action_metadata`. These steps may overlap: do not sum them to claim elapsed
gate time or aggregate concurrent memory. Test exclusions from sharding are
reported as skips, not unexecuted required coverage. Summary precision is whatever
the build tool printed, including rounded minute durations. The verification
self-tests use a supported unittest collector that records every selected test,
its outcome and duration, and runner-process CPU/RSS. Each request uses fresh
temporary sidecars; reused results receive no invented fresh timings. Registered native test members use a transparent proxy for the pinned Zig runner
protocol. Each actual dispatched test has a stable root/name identity, outcome and
start-message-to-result-message interval, including scheduling and reporting.
Skipped tests have no fabricated duration. This interval is not pure test-body
time. Supported guest JSON inventories supply outcomes while guest timing stays
unknown. Full group durations and aggregate concurrent memory also remain unknown. `action_coverage` includes every current action.
The parser bounds bytes, lines and observation count separately from log capture.

The first dependency split introduces `juice_pure`: 29 reviewed synthetic
contract/parser/report/calibration tests. Nine native Python Runner tests and the
native collector checks remain in the fresh `juice` group; live runtime collection
remains fresh too. New test classes default to the fresh group. All original tests
remain required. Whole-compiler and common configuration identities remain
conservative; this change does not establish function-level Zig test reuse.

Inventory v2 binds each receipt to its own registered action membership. Global
coverage is still validated on every request; adding inventory metadata alone
does not invalidate unrelated groups. The coordinator recognizes the existing
data-only `build_test_inputs.zig` declarations and binds their expanded local
recipes, so editing one list re-keys only the groups that declare it. This
projection also requires every build-configuration line that uses the lists to be
one of the reviewed consumer sites (`DECLARATIVE_CONSUMERS` in
`scripts/verify_cache.py`); an added or edited site disables projection until it
is reviewed, `verify_cache_test.py` fails until then, and `last-run.json` reports
`declarative_configuration` (`excluded`, or why not). Unrecognized syntax
retains broad configuration identity. Changes to `build.zig` and other common
execution semantics still invalidate all groups; every file `build.zig` compiles
from, transitively, is in `CONFIG_INPUTS`, which a test checks.

The independent `tooling_unit` group runs 27 named pure tooling tests (plus the
root import test) without linking the compiler. Its prepared artifact and declared
source closure are separate, so compiler-only edits can preserve its evidence.
The larger unit group still has broad source fixtures: edits to the extracted
tooling tests can still invalidate that group. This is a directional improvement,
not complete isolation of every native test dependency. Use `test-tooling-units`
or `scripts/focused_test.py tooling FILTER` to run the new root explicitly.

`text_scalar_unit` separates eight existing number-grammar/format tests plus one
root import test, including both embedded oracle files. Run
`scripts/focused_test.py text-scalar FILTER` or `zig build test-text-scalar-units`
through build admission. Unfiltered `test-units` includes both independent roots;
filtered `test-units` retains the compiler root and still rejects no matches.
The two independent roots use authenticated producer metadata covering executable
bytes, exact sources and embedded data, optimization mode, interface/ABI, and
the inherited build, test-runner and tool context. Missing or incompatible metadata keeps
the whole-artifact fallback. Other reviewed artifact selectors retain their
existing conservative source contracts. An unchanged wire schema alone never
authorizes replacement producer reuse.

## The gate's own compiler and test stores

An ordinary request (`verify_cache.py`, the landing gate) runs every build of its workers against an empty compiler store
and an empty test store of its own, as it already runs them against an empty stage store (the user's decision of 14 November
2026, measured on 15 November in `experiments/audit-work-20261111/GATE3.md`). `SELKA_COMPILER_SHARED_CACHE` and
`SELKA_TEST_SHARED_CACHE` name `compiler` and `tests` under `.selka-cache/verification-v3/gate-stores/stores-*`, made for
the request and removed when it ends: a gate makes about 42,000 files and 0.9 GB there, so a request that fails a test leaves
nothing behind. Both variables are placement, so no receipt key changes. What a gate reads from these stores is what the
same request stored, never what another worktree did, and a determinism mismatch one of them logs is this request's alone.

- **A caller that names a store keeps it**: a set variable, empty (disabled) too, is the caller's, as for the stage store.
  `--own-stores off` names none, so the per-user stores are selected as before.
- **A mismatch in the own stores fails a green request with status 5**, the integration gate's status, and keeps the stores
  until the checkout's next request removes them. The first 20 lines of each log are in `last-run.json` under `own_stores`.
- **A build of the request that opened a per-user store fails a green request with status 6**, the stage store's status.
  Every process that opens a store holds a shared lease on its `<namespace>/.retention.lock` for as long as it builds, so the
  request samples `/proc/locks` four times a second and keeps each holder that descends from the coordinator
  (`StoreLeaseWatch`; a process of another checkout is no finding). A holder that lives for less than a sample can be missed.
  No holder is exempt. The compiler the component builder runs (the build's own `selka`) is started with every `SELKA_`
  variable dropped on purpose, except the store locations (`SELKA_COMPILER_SHARED_CACHE`, `SELKA_TEST_SHARED_CACHE`,
  `SELKA_STAGE_SHARED_CACHE`: `selfhost/components.zig`, `inheritedEnvironment`), which pass through, so that compiler
  under a gate opens the request's own stores like every other build, and one that opened a per-user store fails the request
  with status 6. A component's bytes do not depend on a location
  ([the builder](selfhost-components.md#the-children-of-the-builder)).
- **What it cost** (twelve forced complete gates, alternating): wall time 1.05 times today's at the median, CPU time 0.98
  times; an unchanged tree 15.0 s against 15.3 s. The per-user stores are full (the test store holds exactly its 100,000
  entries) and a gate writes 42,000 files into them, so what a gate reads back from them saves it no measurable time.

## Integration gate

`--integration` is the request to run once per integrated commit; the nightly service runs it
(`scripts/nightly-integration.sh`, below). It runs the complete profile and then checks that ordinary
requests skip:

- **Its own stores.** Every build of the request, the complete profile's and the two checks' below,
  uses an empty compiler store and an empty test store of its own: `SELKA_COMPILER_SHARED_CACHE` and
  `SELKA_TEST_SHARED_CACHE` name `compiler` and `tests` under
  `.selka-cache/verification-v3/integration/stores-*` for the whole request. Both variables are
  placement, so no receipt key changes. The per-user stores are neither read nor written. The stores are
  removed when the request passes and kept when it fails, until the next integration request of the
  checkout removes them; retention never needs to know them.
- **One forced fact/leak run (D1).** Ordinary requests reuse the receipts of the
  language suites' `--verify-facts` members under `SELKA_CORE_LEAKCHECK=1` (the debug
  members; the release members of `-Dtest-release=true` are not in the default inventory),
  because both checks are keyed on the program they ran. The integration
  request reruns every such member it finds in the `language` inventory with
  `--force` under one gate admission, in a private cache directory that it
  removes afterwards, so the ordinary receipts stay valid. A failing test, or
  any test that reports `cached`, fails the request with status 7.
- **The two-run test step.** `zig build test-lang-rerun` (`scripts/test_lang_rerun.py`) runs each
  language suite twice in one fresh work directory, the second run forced, and fails on a test whose
  verdict changed or that is `unsupported`: a stored record served to a program it does not fit shows
  only on such a second run. It is not part of the per-landing gate (the user's decision of 14 November);
  it runs here, once a day, under one gate admission. A failure is status 8 and names the test.
- **No mismatch in its own stores (D3).** After the checks it counts the lines of the own stores'
  `mismatches.log`. Any line fails the request with status 5, distinct from a failing test: two
  producers of this request wrote different bytes under one key. The line names the store's key and
  both digests; the first 20 lines of each log are copied into the record. The per-user stores'
  logs (`~/.cache/selka/compiler-artifacts`, `native-tests`, or the stores the caller's environment
  names) are reported as counts, never as a failure: lines now, lines added during the request (other
  builds of the user's write them), and lines added since the checkout's last integration request.

```bash
python3 scripts/verify_cache.py --zig "$ZIG" --integration
```

The status names the step that failed:

| Status | Meaning |
| ---: | --- |
| 0 | The complete request, the forced fact/leak run and the two-run step passed, and the own stores logged no mismatch |
| 5 | The request's own stores logged a determinism mismatch (it outranks every other failure) |
| 1, 2, 6, 75, ... | The complete request failed with that status (1 a failing test or step, 2 a host or usage error, 6 a test reached the per-user stage store or a build of the request opened a per-user compiler or test store, 75 retry); the two checks did not run |
| 7 | The forced fact/leak run failed, or a test in it reported `cached` |
| 8 | The two-run test step failed |

The outcome is in `last-run.json` under `integration` and in
`integration-last-run.json` beside it: the step results, the own stores' size and whether they were
kept, the mismatch lines, the per-user counts and the `summary`, the same line the request prints last.
`--integration` takes neither another profile nor a timing window.

### The nightly service

`selka-nightly-integration.timer` (`scripts/install-nightly-integration-timer.py`) starts
`scripts/service_worktree.py --service nightly` in the registered service worktree, which moves the
detached checkout to the local `main` and runs `scripts/nightly-integration.sh`: `--integration` with
the whole output in `$XDG_STATE_HOME/selka/nightly-integration/<UTC stamp>.log`. The script's exit
status is the request's, and its one line on standard output, which is what the service's journal
shows, is `nightly: exit N: verification: integration PASS|FAIL (status N): <why>; per-user mismatch
logs (a record, not the verdict): ...; log: PATH`. When the complete request failed, `<why>` names its
failed action and its first two failed tests, and says why a failed test was not rerun alone
(`no flaky rerun: ...`; a leftover process is named with the test file whose scratch directory it runs in).
Read it with `journalctl --user -u selka-nightly-integration.service`: `service_worktree.py` relays the
script's standard output itself and stays alive three seconds after its last line, because journald names a
line's unit from the writing process's cgroup when it handles the line, and a script that exits at once
leaves its line without one.

## Measured on 12 October

On the merged output-keyed tree, all under exclusive timing windows:

| Cohort | Median | Range | Before |
| --- | ---: | ---: | --- |
| Unchanged complete verification, request (5 samples) | 29.9 s | 24.2 to 36.5 s | 33.5 to 36.8 s |
| Same, gate occupancy | 14.4 s | 13.8 to 24.8 s | 23 to 28 s |
| Comment edit in `src/parser.zig`, then `selka test tests/lang` (5) | 14.15 s | 7.75 to 16.17 s | 78 s, nothing reused |
| Same edit, then complete verification (2) | 762.6 s | 737.8 to 787.4 s | 596 to 1,034 s |
| First verification in a fresh worktree, after another published its evidence (2 of 3; the first ran cold, 828.7 s) | 83.5 s | 79.3 to 87.6 s | 600 to 1,000 s (941.5 s median before cross-worktree sharing) |
| Ten complete verifications started at once, one shared evidence store, total wall | 6,527 s | gate 720 to 1,044 s each | ten cold gates |

After a comment edit, 1,544 of 1,549 eligible language tests are answered from
execution receipts; the five that run call `function_digest`, which binds the
compiler identity. The complete verification after the edit still reruns the
Zig roots and drivers whose input is the compiler (19 actions), while every
guest and language member answers from receipts. A fresh worktree that names
the shared evidence store (`SELKA_VERIFICATION_SHARED_CACHE`) reuses every
action another worktree published except `tooling_unit` and `text_scalar_unit`,
whose test binaries carry the debug compile directory (F15); its guest and
language members still run every test unless the native test store is shared
too, which the gate does not yet tolerate (F18). Ten identical requests started
together do not share work: each looks up the evidence before it queues for the
gate and not again after, so all ten execute every group (F19). The
qualification and its findings are in
`experiments/output-keyed-receipts-20261012/` and the
[plan's outcome](../audits/output-keyed-shared-receipts-plan-2026-10-12.md#outcome-12-october).

## Prepared artifact inventory (`artifacts.json`)

`zig build verification-prepare` builds every prepared native artifact and writes
`zig-out/verification/artifacts.json`
through `scripts/verification_artifacts.py` (a developer step, never part of the
install graph). The inventory names the original emitted cache artifacts; preparation
does not retain an unused second copy of each binary under `zig-out/verification/bin`. `build_verification.zig` exports each artifact's producer
recipe, so the coordinator can identify an artifact by what produced it rather
than by its bytes, whose debug information names the worktree. Version 3:

```json
{
  "version": 3,
  "artifacts": {
    "units": {
      "path": "/abs/zig-out/.../test",
      "producer": {
        "recipes": ["./*.zig", "build.zig.zon", ".zigversion", "src/",
                    "test/fixtures/environment-identity/", "docs/primer.md",
                    "tools/test_runner/"],
        "optimize": "debug",
        "zig_version": "0.17.1",
        "test_runner": {"kind": "repository", "location": "tools/test_runner",
                        "runner": "test_runner.zig"}
      }
    }
  },
  "producers": {"tooling-units": {"version": 2, "domain": "...", "...": "..."}}
}
```

- `artifacts[label].path`: the exact absolute path of the prepared binary (a
  bare string in versions 1 and 2).
- `artifacts[label].producer.recipes`: unique root-relative recipes in the
  input-list syntax (`dir/`, `base/**/*SUFFIX`, `base/*SUFFIX`, or one file)
  that bound every compile-time input: the build files (`./*.zig`,
  `build.zig.zon`, `.zigversion`), the root's sources, the
  user guides `src/user_docs.zig` embeds (`selka` and `units`), and for a Zig
  test root the test runner's sources (`tools/test_runner/`).
- `optimize`: the artifact's optimize mode as the build spells it (`debug`,
  `safe`, ...); `zig_version`: the toolchain the build runs.
- `test_runner`: `{"kind": "repository", "location", "runner"}` for a test
  root, which links the repository's runner (`tools/test_runner/`, Guardian's
  runner kept when Guardian was turned off on 18 November 2026; until then
  `{"kind": "guardian", ...}` from the `../guardian-zig` path dependency),
  `{"kind": "zig-default"}` for a root on Zig's runner, or `{"kind": "none"}`
  for an executable. It holds no absolute path; the runner's content is bound
  through the `tools/test_runner/` recipe.
- `producers`: the reviewed closure metadata of `tooling-units` and
  `text-scalar-units`, unchanged from version 2.

Every prepared artifact has a producer: `selka`, `units`, `core`, `cli`,
`golden`, `memory-budget`, `component-support`, `component-builder`,
`tooling-units` and `text-scalar-units`, and so do the installed Selka
`components`. Their entry's `path` is `libexec/selka/components/test-index.json`
(the coordinator's provider is both manifests and the two executables they
name); recipes are the build files, `selfhost/*.zig`, `selfhost/components/`
and the recipes of the `selka` artifact that compiles them (`src/` and the user
guides), with `optimize: "debug"` and `test_runner: {"kind": "none"}`. A new artifact must name its recipes
in `build_verification.zig` or the build refuses to configure.

The report's `action_budgets` evaluates the current request diagnostically. The
[budget evaluator](verification-budgets.md) combines archived compatible reports
and reevaluates advisory targets without executing tests. A single measurement
cannot establish a calibrated target. Failures, reused results, incomplete logs
and ambiguous timing rows do not become fresh samples. Hard limits remain opt-in
command controls, and no per-action deadline is enabled by calibration.

Remaining work includes precise guest individual timing, calibrated action limits,
qualified ordinary-edit latency, broader useful boundaries and full self-hosting. The
[DL1–DL8 plan](../audits/selka-development-loop-plan-2026-10-11.md) and
[bootstrap handoff](../audits/selka-development-loop-bootstrap-handoff-2026-10-11.md)
define the larger work and ownership. The active self-hosting branch owns compiler
porting; this tooling pass preserves its completion and performance requirements.

## Receipt identities (schema 3)

Receipts are schema 3 under `.selka-cache/verification-v3/`; each receipt
records `"version": 3` and every action key starts from the domain
`selka-verification-action-v6`. Schema-2 receipts in `verification-v2` are never
opened, and a schema-2 record found under a v3 key is a miss, so the first
request after the change reruns every action once. Report schema remains 1.
`last-run.json` shows, per action, whether its key is path-free and which
variables entered it:

```bash
python3 scripts/verify_cache.py --zig "$ZIG"
jq '.actions[] | {id, path_free, environment_variables}' .selka-cache/verification-v3/last-run.json
```

An action key is path- and environment-free by construction:

- **Environment.** `normalized_environment` projects the launcher environment
  through the [environment identity contract](environment-identity.md): workers
  receive only keyed, host and placement variables, then the coordinator's
  constants (the `PYTHON*` pins, fixed `GIT_*` identity and config isolation,
  `PATH` limited to existing directories). `PWD`, `SHLVL`, `TERM`, `CODEX_*` and
  every other dropped variable never reach a worker; a worker's working directory
  comes from the process. The `environment` field of the common identity is the
  contract's host-scope digest of that environment plus the content digest of
  every tool `tool_contract` resolves, named by its snapshot label and taken from
  the tools snapshot. Two launchers that differ only in dropped or placement
  variables (another agent's `CODEX_THREAD_ID`, `TERM`, `PWD`, `TMPDIR`) share
  every key; a keyed change such as `SELKA_MEMORY_LIMIT` changes every key.
- **Paths.** The common identity holds no checkout path. The checkout lock and the
  shared store's coordinator lock still use the real path, for mutual exclusion only.
- **Prepared artifacts.** Native executables embed the checkout path in their debug
  information, so their bytes differ between worktrees. When
  `zig-out/verification/artifacts.json` (version 3) declares a `producer` for an
  artifact, the coordinator identifies it by what produced it instead: the
  content of every file of the preparation and build-configuration snapshots its
  `recipes` select, the recipes, `optimize`, `zig_version` and `test_runner`.
  An installed copy (`zig-out/bin/selka`) must have the produced bytes. A recipe
  that selects no watched file fails the request. An artifact without a valid
  producer keeps its byte identity. The two reviewed independent roots keep their
  closure metadata, which still binds executable bytes.

`last-run.json` names the choice per provider in `artifact_identities`
(`{"identity": "producer", "sources": N}` or `{"identity": "bytes", "reason": ...}`)
and, per action, `path_free` (true when the checkout path occurs in no part of
the key or of the documents its digests hash, no loaded-code digest changes when
the coordinator's code is rehashed as if loaded from another directory
(`relocation_dependent_code` names any that do), every `common` facet is one
the check knows how to judge, and every provider the action depends on has a
producer identity) and
`environment_variables` (the sorted names, never values, of the keyed and host
variables in its identity). A retained `cache_session.py` restores its startup
environment before each request and the coordinator projects it the same way,
so its retained snapshots and receipts serve launchers that differ only in
dropped variables.

Schema 2 separated canonical loaded-code identities from older marshal-based
identities; schema 3 keeps that encoder. The canonical encoder binds actual
loaded code, typed constants and source locations; since loaded-code format 2
(`loaded_code_format`) a file name enters by its base name only, so one commit
checked out twice binds one coordinator implementation. Retained bootstrap guards
separately authenticate its source. Neither migration changes deterministic fuzz
seed derivation or rewrites existing content stores.

## Compiler and focused test iteration

Use `scripts/build-slot.sh build zig build affected-compiler` for an ungated
compiler at `zig-out/focus/selka`, or `scripts/build-slot.sh build zig build
-Dgate-install=false` to install development artifacts at the normal paths.
`-Dgate-install` ran Guardian before the install; since Guardian was turned off
(18 November 2026) the option is accepted and does nothing.

The supported compiler inner loop is the watch loop, `scripts/dev_loop.py`: an
incrementally compiling watcher for the worktree that an agent can block on. Source
the shared development environment first, then:

```sh
source ~/.config/selka/dev-env.sh
python3 scripts/dev_loop.py start                 # once: the first build (about 40 s)
# ... edit src/ ...
python3 scripts/dev_loop.py wait                  # until a build that holds the newest edit is done
python3 scripts/dev_loop.py test units FILTER     # also core or cli; compiles nothing
python3 scripts/dev_loop.py stop                  # or leave it: it stops after twenty idle minutes
```

`wait` prints at most 20 lines: the build's number, its seconds and the seconds it
waited for a build slot, or each compile error's `file:line:col: error:` with its
source line (exit 1). Nothing changed since the last build returns at once. It fails
with exit 2 when there is no watcher, while a gate runs in this worktree (its
coordinator lock is held) and when the watcher ended; a watcher whose configure
input (a root `build*.zig`, `build.zig.zon`, `.zigversion` or a file they import)
changed, whose `HEAD` moved or which has over 1,000 changed files is restarted by
`wait`, which says so. `test ROOT FILTER` waits, then runs
`zig-out/focus/{unit,core,cli}-tests --test-filter=FILTER` as the edit
check runs its binaries, and names whether that binary is the last watch build or a
later normal build. A failure on a watch build counts as the watch build's until a
normal build confirms it (`focused_test.py ROOT FILTER --no-watch`). `test` holds the
thaw lock shared while the binary runs, so a `wait` meanwhile waits for it.
`python3 scripts/focused_test.py units|cli FILTER` uses the watcher's binaries the
same way when one runs (`--no-watch` builds as before). `status` reads the daemon's
state without waiting for it. `compare [--all] [--roots units,core,cli,lang]` copies
the watch binaries aside, builds normally (`-fno-incremental`), runs the newest edit
check's selection (with `--all`, every test of each root and `selka test tests/lang`
with each compiler) on both at the default stack limit, one ordinary build admission
for each root, and lists the verdicts that differ by name.

**The one known watch-only difference** (decision D9, the user's, 13 November: "Yes,
name it"). An incrementally linked compiler reserves room in its segments to patch
them in place: its `LOAD` segments map 433.7 MiB against a normal build's 77.9 MiB
(the heap is the same: 32 against 40 MiB resident on the case below). The compiler's
own memory ceiling allows the ceiling plus 256 MiB of address space, so under a low
`SELKA_HOST_MEMORY_LIMIT` the mapping alone reaches it. One test sets such a ceiling
and so fails on watch builds: `fix_cli_test.test.a project check with a type error in
one module and 600 ownership errors in another reports them all under a 192 MiB
ceiling`, which passes on a watch build from 224M and on a normal one from 16M. `test`
and `compare` recognise exactly this case (the test exits 2 with "the compiler
reached its own memory ceiling" from a compiler whose segments map over 64 MiB more
than its file holds) and report it as watch-only with that reason; any other
difference stays a difference. Confirm such a test on a normal build.

**Before a gate, nothing.** Leave the watcher running: it is frozen, holds no build
slot and no CPU, and its compilers do not block a normal build of the worktree or a
build elsewhere that shares `ZIG_GLOBAL_CACHE_DIR`. The gate builds normally and
never uses a watch build, and `wait` refuses while it runs. The edit check, a focused
build and a plain `zig build` coexist with it in the same way (the thaw lock below).

How it works. `start` launches `scripts/build-slot.sh watch python3
scripts/dev_loop.py --daemon` detached; the daemon runs `zig build --watch
-fincremental -Dwatch-identity=true install unit-test-binary core-test-binary
cli-test-binary --summary all` (the Maker) in a process group of its own, logs each
line with its time in `.selka-cache/dev-loop/watch.log` and each decision in
`events.jsonl`, and keeps the Maker stopped (SIGSTOP) except inside a `wait`. A
`wait` takes `.selka-cache/dev-loop/thaw.lock` exclusively, waits (at most a
minute, then refuses naming it) while a process runs one of the products, then an
ordinary build admission (its `build-slot.sh build python3 build_admission.py --hold` helper holds
the slot), continues the Maker, accepts the first build summary whose end snapshot
of the inputs (every file under `src`, `test` and `selfhost`, and the build files)
equals the snapshot at the end of the build before it, answers, and freezes the
Maker again at a verified idle before it gives the slot and the thaw lock back. The
watch installs the compiler and the three test binaries as relative symbolic links to
the artifacts the incremental linker rewrites in place (`build.zig`'s `installBinary`
under `-Dwatch-identity`, always under the default prefix `zig-out`), so a rebuild
copies nothing; an ordinary build's install replaces each link with a file, so a gate
or the edit check never runs through one. Because the linker cannot rewrite an
executable a process runs (`FileBusy`, after which the Maker waits for its exited
compiler for ever), `wait` does not continue the Maker under a running product, and a
Maker that leaves a compiler a zombie for ten seconds, or whose processes use no CPU
for 30 s while a build is awaited, is stopped and restarted by the next `wait`. Both
clocks count only the looks at which every thread of the Maker's tree was asleep (a
thread that is runnable, in disk wait or stopped, or used CPU, starts the clock again),
and one look counts at most half a second, so a Maker held off the CPU by a loaded
machine, or a daemon that could not look, is no stall. The state file is written before
a `wait` is answered, so a reader that looks at it when `wait` returns finds the state the
answer describes. An
edit made at once after a `wait` is built by the watch before the daemon freezes it;
the daemon adopts that build by the same snapshot rule, so the next `wait` answers
with it. After a freeze the Maker's poll resumes through `restart_syscall`, which the
daemon reads as idle until the Maker prints anything. `-Dwatch-links=false` keeps
copies under the watch. After an edit that changes the compiler identity the watch builds once
more by itself (the live identity run writes the new `identity.zig`), now in about
0.1 s; the identity tool leaves an unchanged `identity.zig` untouched, so a comment
edit draws no second build. Idle is the
Maker's main thread blocked in `poll` with no timeout on fanotify descriptors only
(`/proc/PID/syscall` and the pollfd array in `/proc/PID/mem`); the first build checks
that signature (busy during the build, idle after it), and without it the daemon
runs unfrozen, holding a build slot, and says so. The signature is qualified for
the pinned Zig (`QUALIFIED_ZIG`; a test fails when `.zigversion` moves). The daemon
stops itself after twenty minutes without a request, and stops a frozen Maker whose
machine has had less MemAvailable than a gate needs (`SELKA_GATE_MEM`) for a
minute; the next `wait` starts it again and says so. Killed in any state, stopped
included, the daemon takes everything with it: the Maker has a parent-death SIGKILL,
the kernel sends the Maker's orphaned, stopped compilers SIGHUP and SIGCONT, and the
watch slot, the build slot's helper and the thaw lock are released.

`scripts/build-slot.sh build zig build --watch -fincremental` by hand is no longer
the supported loop: it holds a build slot for its whole life. A watch session never
substitutes for the gate.

### The watch admission kind

`scripts/build-slot.sh watch CMD...` admits a compiler watcher's daemon (stage 3 of
`docs/audits/compiler-dev-loop-plan-3-2026-11-12.md`; the daemon is
`scripts/dev_loop.py`, above). It holds one `watchN.lock` in the slot
directory, and no build slot, for the command's whole life. The daemon keeps its
watcher frozen except while it holds an ordinary `build` admission for a rebuild,
so every rebuild is a build to the slots, the memory rule and a timing request,
and a frozen watcher uses no CPU. The limits are named settings (decision D2,
awaiting the user's confirmation):

| Setting | Default | Meaning |
| --- | --- | --- |
| `SELKA_WATCH_SLOTS` | 3 | watchers on the machine, at most one for each worktree |
| `SELKA_WATCH_MEM` | 3G | MemAvailable a watcher needs to start: its measured resident size |

A watch request never waits. It exits 3 when its worktree already has a watcher,
4 when every watch slot is taken and 5 when memory is short. It admits only the
daemon (`python3 scripts/dev_loop.py --daemon ...`) and refuses any other command
with exit 2, a bare `zig build --watch` included: the daemon starts the Maker only
inside an ordinary build admission, for the first build (about 37 s and 3 GB) as for
every later one. The daemon is the process the wrapper execs, so the owner record's
pid is the daemon's for its whole life; `dev_loop.py start` launches the wrapper
detached and returns.

| A watcher's state | What it holds |
| --- | --- |
| frozen (idle) | its `watchN.lock`, its resident memory (about 3 GB), its worktree's `.zig-cache` |
| rebuilding | the same, plus one ordinary build slot its daemon requested, and `.selka-cache/dev-loop/thaw.lock` exclusively |
| killed, in any state | nothing: the kernel releases the locks; the owner and state files it leaves are ignored |

`build-slot.sh status` lists each watcher with its worktree and the state its daemon
last wrote (`watchN.state`: `STATE RSS_BYTES EPOCH`). A timing request prints one
line naming the watchers beside it, how many are frozen and their resident memory.
A `build` or `gate` admission whose command is itself a `zig build` that is not a
watch takes its worktree's `thaw.lock` shared, when that file exists, so it never
writes `zig-out` while that worktree's watcher rebuilds. **The lock order is one for
everyone: thaw before ticket before slot, never the reverse.** A plain build takes
the thaw lock before its FIFO ticket, and the daemon takes it exclusively before it
asks for its build admission, so nobody waits for the thaw lock while holding a
ticket or a slot, no slot idles behind a rebuild, and the memory check is made when
the slot is taken. The wait prints one line and lasts at most 600 s. Not covered: a
command with a prefix (`nice`, `env`, `systemd-run`), the verification coordinator
(its admissions go through `--hold`) and the scheduler backend. The complete gate
will hold the thaw lock **shared** for its whole run (part P6): its own builds then
still start, and the daemon's non-blocking exclusive attempt refuses beside a gate,
so a watcher never rebuilds during one.

A live watcher counts as an active job of its worktree on every path that renames
or deletes a cache: an admission's trim, the verification coordinator's, and the
background deletion of renamed-aside directories; its daemon's lock
`.selka-cache/dev-loop/daemon.lock` counts too, through any slot directory. So a
worktree with a live watcher is never trimmed, on any cap; the daemon's twenty-minute
idle stop bounds how long that lasts. Wrappers that predate the kind read no
`watch*` file: they neither wait for a watcher nor change how it is counted.

### The build-identity step

Every build runs the build-identity tool (`build_identity.zig`, rules in
`src/build_identity_rules.zig`), which digests the production sources into the
compiler identity that keys every cache. It analyzes each source once (its token
digest and its import edges) and forms every closure and digest from those facts:
0.21 s for all of `src` on 13 November, against 3.0 s before. Under the admitted
watch (`build-slot.sh` adds `-Dwatch-identity=true`) the tool's cached run only lists
the sources, which keys the step and registers the watch, and the live run forms the
identity once per edit from a per-file record kept in the worktree's local Zig cache
(`selka-identity-record/record`). Every run still reads every source and hashes its
bytes (BLAKE3); the record serves a file's facts only for the same path and the same
hash, so what it saves is tokenizing and parsing, and no file status or time decides
anything. A record of another tool version or tree, or a damaged one, is ignored. A run
after a one-file edit takes about 0.02 to 0.03 s. A symbolic link under `src` fails the
tool: the identity covers regular files only.

Ordinary builds, and so every gate, analyze every source and never read the record.
`-Didentity-record=on` opts an ordinary build in; `-Didentity-record=check` computes the
identity with the record and without it and fails the build on any difference
(`-Didentity-record=off` turns the record off under the watch). The comparison cases
are in `tests/compiler_identity_cache.py` (`--only record`), and `--only fixtures`
requires the tool to reproduce what main's tool wrote for fixed trees
(`test/fixtures/build-identity/expected.json`; regenerate it with `--write-fixtures`
only when the rules change on purpose).

The test runner (`tools/test_runner/`) accepts repeatable
`--test-filter=SUBSTRING` arguments. The build passes `-Dtest-filter`
there and leaves the binary unfiltered, so a second filter reuses its compiled
artifact; a filter that names no test still fails. Filters make only the six selected native groups
uncacheable; unrelated groups retain their declared cache eligibility. Receipt
reuse still depends on all of each group's artifact and configuration identities.

Component preparation discovers its declared source inputs at make time with the
native builder. Its content stamp also binds the selected pin/archive, builder,
Zig binary and library, and native target. The component build consumes that stamp
and the live projected environment identity, and publishes generated outputs plus
a completion stamp only after success. Native installation validates both generated
manifests and executables, repairs installed copies, and leaves identical manifests
untouched. No Python process is added to the install graph.

The 13 October R3 exclusive measurements used two separate Guardian scopes.
With the unchanged sibling dependency, five gated compiler edits had a 6.834 s
median and five explicit ungated edits an 11.041 s median. Unchanged ungated
installs had a 0.867 s median; incremental watch completed an edit in 1.125 s
after startup. A second filter still compiled one binary through the compatibility
fallback. With the proposed Guardian branch, gated/ungated edit medians were
10.844/9.587 s and the second filter compiled zero new binaries. Its watch trial
did not complete a second build within 180 s and is not qualified. Neither normal
edit series meets about 1 s. Unchanged install and watch measurements are distinct
from normal compiler-edit builds; final-source evidence is recorded in the
[closeout ledger](../../experiments/caching-closeout-20261013/status.md).

## Core object retention and replay

New unit objects use `units-v1/ab/<key>.o` with adjacent checksum records. Verified
reads try the shard before the legacy flat path and refresh retention recency.
Replay can reuse a previously verified digest only while inode, size, modification
time and change time match; changed status rehashes, and `--verify-cache` bypasses
replay. Implementation-only runtime body edits preserve guest unit keys when the extracted
ABI surface and exact guest LLVM stay equal, while rebuilding the runtime object
and link. Declarations, layouts, macros, all preprocessing directives and ABI flags
remain inputs; unsupported C syntax conservatively binds the whole runtime source.

Run `bash scripts/systemd/core-store-maintenance.sh --store PATH` for a preview
and add `--apply` for maintenance. The wrapper sources the developer environment
and owns build admission. Review `inventory_complete` (every shard read at least once),
`retained_bytes`, `fresh_bytes`, `skipped_active`, `unmet_budget`, `exclusive_seconds`
and the phase times (`scan_seconds`, `evict_seconds`). Defaults are a 10 GiB cap
(counted in disk blocks, not file lengths), 14-day retention and a 6-hour grace period for anything used. The collector holds
no lease that builds wait on (see [the caches](native-build.md#the-caches)); a preview
reads the store and writes only the ledger, which `--ledger PATH` can place elsewhere. A
run that is out of time (`more`) or over budget by what the grace period keeps
(`unmet_budget` with `fresh_bytes`) does not establish that the store meets the cap; the
next run continues. Capacity eviction removes the object, its checksum and its flat aliases
together. The installer supports `--dry-run`. The closeout installed
`selka-core-store.timer` and its service in the user's systemd configuration;
it runs after boot and every 15 minutes after completion, with up to 2 minutes of
jitter.

R4 also installed `selka-nightly-integration.timer` and its service. It runs
`verify_cache.py --integration` directly after sourcing the developer environment,
at 01:30 local time with up to 30 minutes of jitter and persistent catch-up
(03:00 until 15 November 2026, when it overlapped the machine's backup at 03:30, which needs most of the memory).
The host timezone during rollout was UTC. Both services now point to the detached
`/home/epentland/ai/canopy/mylang-services` checkout. Reinstalling these units
enables their common service-worktree lease: the helper refuses a dirty or
attached checkout and refreshes it to local `main` before running. The lease
covers both refresh and the service child. Acceptance records actual invocation
status and distinguishes a manual service run from an observed scheduled firing.


## Native gate scheduling and fixture construction

At the default shard counts (core 10, unit 12, CLI 6), the test runner
receives the checked-in assignments in
`tests/shard-plans/`. These use per-test medians from three retained independent
cohorts. `tests/shard-plans/regenerate.py` verifies the archive hashes and rebuilds
them. The provenance records historical scheduling hints, not measured speedups.
Core weights use three compiler-edit samples from the batch-2 baseline; unit
weights use the batch-3 baseline, and CLI retains the closeout cohorts. Each
refresh checks exact-once coverage, including names added since older cohorts.
The former 45-program float-conversion test is split into nine target-specific
tests, preserving all five invalid inputs and trap assertions for each target.
Those new names use distinct modulo slots until three observations support
their own measured hints; their predecessor's weight is removed.
Unknown tests retain the runner's modulo fallback; unnamed blocks run once on
shard zero. A custom shard count
uses modulo unless an explicit matching `-Dcore-shard-plan`, `-Dunit-shard-plan`
or `-Dcli-shard-plan` is supplied. Filtered whole-root runs remain whole-root runs.
The coordinator watches default assignment bytes as configuration inputs, and
Zig binds them as run inputs. No CPU lanes or test coverage are added by a plan.

A Debug compilation of a test root or the compiler executable reserves 2 GiB
(`compileCeiling` in `build.zig`); an optimized one retains 4.5 GiB. The Debug
ceiling is more than twice the 740 MiB largest uncached Debug test-root compile
observed in the 2026-10-28 gate. The test-support objects (`juice_bytes_hash`,
`fast_blake3`, `core_number_text`) reserve 512 MiB; their uncached peaks were
112-138 MiB. A cached compile still needs its whole ceiling free before it can
run, and the core test binary waits on all three objects, so a 4.5 GiB ceiling
on a cache hit held every core shard behind the running unit shards. These
declarations remain per-step reservations, not a proven aggregate process-tree
memory limit.

The Python drivers that run the language suites, the ownership and cache proofs and `selka doctest` reserve
1 GiB (`rss.driver`); their process-tree peaks on 2026-10-28 were 168-925 MiB (doctest 925 MiB, the largest),
down from 2.5 GiB (`rss.suite`).

The pinned Maker blocks a step whose ceiling does not fit `--maxrss` on a LIFO
stack and releases the most recently blocked step first; its Io pool also queues
ready tasks last-in first-out. The dependency traversal is shuffled with the
`--seed`, so the order of `shardRegistrationOrder` does not select which shard
starts first. Scheduling changes therefore have to reduce declared ceilings
that are far above observed peaks, not reorder registrations.

Unit fixture subprocesses retain explicit `SELKA_COMPILER_SHARED_CACHE` and
`SELKA_TEST_SHARED_CACHE` selections. Empty values still disable sharing;
unset variables use the compiler's ordinary defaults. A fixture's restricted
environment must not silently redirect a selected store to the default store.

Golden replay has sixteen named partition tests (`replay_partitions` in
`test/golden_parity.zig`), scheduled by the build runner under the same CPU and
memory admission limits; each shard reserves 512 MiB, its observed peak being
62-63 MiB. A partition is chosen by hashing the source payload (or the entry key
for non-source entries), so equal source payloads stay in one partition and keep
source preparation reuse; every execution still gets a fresh working directory
and checks its recorded exit status, output and trap. Each partition runs about
a sixteenth of the corpus, so no single test interval approaches its deadline.
Each is a quarter of an old partition: about 37-55 s on a quiet machine, from the
147-219 s partitions of 2026-10-28. An independent full-corpus
classification audit retains the coverage and explicit-skip requirements. The
sixteen declarations must consume the exact ordered `replay_partitions` list, which
the coverage test checks. `-Dgolden-shards=1` runs all partitions in one process;
the default is 4, and 1 through 4 are accepted by complete verification.
Filtering also uses one process and selects named tests as before.

Native protocol telemetry now retains monotonic start/end timestamps for each
observed test interval. These are comparable within one host run and include
protocol scheduling; they are not CPU time or portable timestamps across boots.

The closed C fixtures for runtime threads and the two scheduler harnesses
reuse compiled binaries in `fixtures-v1` beneath the core suite cache
(`-Dcore-test-cache`, default `.selka-cache/core-tests`). The identity includes
the generated runtime and fixture bytes, toolchain and native target, C flags,
sanitizer, and `SOURCE_DATE_EPOCH`. Header dependencies and artifact digests are
validated; an unsupported tool/environment or fixture compiles privately. Each
execution receives a verified private binary copy and private counters. Every
existing stress mode, sanitizer run and assertion still executes whenever its
native test runs; this cache stores no verdicts. Source-guard compilation tests
remain fresh and outside this construction cache.
The cache contract test uses a small real C fixture for cold construction,
reuse, fresh counter output and corruption repair. Runtime stress/accounting
assertions remain in their existing tests; the contract test does not repeat
their heavyweight runtime compilation.

The gate runs some stress fixtures at shorter counts than their full ones: the two
ThreadSanitizer scheduler runs take 100,000 submits instead of a million, and the
allocator transfer growth run takes 10,000 rounds instead of 40,000. The transfer
run also bounds the blocks it carves (at most 4,096, where reuse keeps it near 400),
so it catches a cross-thread reuse leak within a few rounds rather than only past
the 64 MiB ceiling. The ordinary scheduler runs keep their million submits. Before
a change to the task scheduler or the allocator lands, run the core suite once
with the full counts:

```bash
SELKA_FULL_STRESS=1 scripts/build-slot.sh gate zig build test-core
```

`SELKA_FULL_STRESS` is keyed (`SELKA_*`), so a full run keeps verdicts of its own.
