# Development loop measurements and limits

Use `python3 scripts/verify_cache.py --zig /path/to/pinned/zig` for complete
verification with reusable evidence. The coordinator owns admission. The retained
`scripts/cache_session.py` accepts the same options through its `verify` request.
These developer commands do not change installed compiler or guest-test defaults.

`--profile complete` is the default. `--profile quick --quick-actions 3` schedules
at most three pending actions, prioritizing changed dependencies and inexpensive
work using explicitly heuristic hints. It reports outstanding required action IDs
in `profile_coverage` and returns 3 for partial feedback, even if all eligible
results were already cached. It cannot report complete verification. The next
complete request reuses qualified completed work and executes the remainder.
Cold preparation still builds the required native artifacts; quick selection
does not promise a five-second cold build.

`--profile long-qualification` completes the gate and then executes bounded,
fixed qualification recipes. Its six obligations are fuzz, scaling, work counters,
Juice instructions, wall-clock performance and bootstrap. It runs up to four
supported obligations by default; `--qualification-target NAME` selects explicit
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
request. No scheduled job is installed.

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
revokes new receipts and reports failure. This explicit bound changes execution
identity; the 5-second feedback and 15-second p95 targets never become implicit
deadlines. Long qualification owns separate phase admissions and cannot be
combined with this request-wide measurement option.

A timed-out command returns 124. Its isolated Linux supervisor terminates and reaps
owned descendants, including helpers that start new process sessions. After normal
command exit, descendants get up to two seconds to finish existing temporary-cache
cleanup; this time counts against the execution deadline and is interruptible.
Live descendants remaining afterward are incomplete execution, status 125.
Cancellation terminates the owned tree; another coordinator's work remains owned
by that coordinator. None of these incomplete outcomes publishes new success
receipts. A subsequent request can retry. The supervisor preserves inheritable
descriptors used by admission and child tooling. Admission's memory-settle helper
has separate ownership and retains its original delay after a worker finishes or
is cancelled.

`.mylang-cache/verification-v3/last-run.json` records admission wait, input validation,
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
the inherited build/Guardian/tool context. Missing or incompatible metadata keeps
the whole-artifact fallback. Other reviewed artifact selectors retain their
existing conservative source contracts. An unchanged wire schema alone never
authorizes replacement producer reuse.

## Integration gate

`--integration` is the request to run once per integrated commit. It runs the
complete profile and then two checks that ordinary requests skip:

- **One forced fact/leak run (D1).** Ordinary requests reuse the receipts of the
  language suites' `--release --verify-facts` members under `MYL_CORE_LEAKCHECK=1`,
  because both checks are keyed on the program they ran. The integration
  request reruns every such member it finds in the `language` inventory with
  `--force` under one gate admission, in a private cache directory that it
  removes afterwards, so the ordinary receipts stay valid. A failing test, or
  any test that reports `cached`, fails the request with status 1.
- **No shared-store mismatches (D3).** It counts the lines of every
  `mismatches.log` in the native shared stores the request's environment selects
  (`MYLANG_COMPILER_SHARED_CACHE`, `MYLANG_TEST_SHARED_CACHE`, or their per-user
  defaults once `default_sharing` is on) before and after the request. A log that
  grew, or one that is not empty, fails the request with status 5, distinct from
  a failing test: two producers wrote different bytes under one key.

```bash
python3 scripts/verify_cache.py --zig "$ZIG" --integration
```

The outcome is in `last-run.json` under `integration` and in
`integration-last-run.json` beside it. `--integration` takes neither another
profile nor a timing window.

## Measured on 12 October

On the merged output-keyed tree (`7313c483e`), a comment edit in `src/parser.zig`
followed by `mylang test tests/lang` took a median 14.15 s over five edits
(7.75 to 16.17 s, exclusive timing windows), answering 1,544 of 1,549 eligible
tests from execution receipts; it took 78 s with nothing reused on 5 October.
The five that still run call `function_digest`, which binds the compiler
identity. An unchanged complete verification then took 532 s because every
request ran the original complete gate (`coverage.unknown_actions` named the
unregistered `build-env` compile step), not the 34 to 37 s it took before. With
the tool registered as infrastructure (`2ea257471`), two consecutive unchanged
requests observed under load took 40.7 s and 23.1 s, gate occupancy 22.6 s and
13.4 s, with the 11 always-fresh actions executed and 35 reused. The
qualification and its findings are in
`experiments/output-keyed-receipts-20261012/` and the
[plan's outcome](../audits/output-keyed-shared-receipts-plan-2026-10-12.md#outcome-12-october).

## Prepared artifact inventory (`artifacts.json`)

`zig build verification-prepare` installs every prepared native artifact under
`zig-out/verification/bin/` and writes `zig-out/verification/artifacts.json`
through `scripts/verification_artifacts.py` (a developer step, never part of the
install graph). `build_verification.zig` exports each artifact's producer
recipe, so the coordinator can identify an artifact by what produced it rather
than by its bytes, whose debug information names the worktree. Version 3:

```json
{
  "version": 3,
  "artifacts": {
    "units": {
      "path": "/abs/zig-out/.../test",
      "producer": {
        "recipes": ["./*.zig", "build.zig.zon", ".zigversion", "guardian.toml", "src/",
                    "test/fixtures/environment-identity/", "docs/primer.md",
                    "../guardian-zig/build.zig", "../guardian-zig/build.zig.zon", "../guardian-zig/src/"],
        "optimize": "debug",
        "zig_version": "0.17.0-dev.1683+5ceec001b",
        "test_runner": {"kind": "guardian", "dependency": "guardian",
                        "location": "../guardian-zig", "runner": "src/test_runner.zig"}
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
  `build.zig.zon`, `.zigversion`, `guardian.toml`), the root's sources, the
  user guides `src/user_docs.zig` embeds (`mylang` and `units`), and for a Zig
  test root the Guardian sources its runner and diagnostics compile from.
- `optimize`: the artifact's optimize mode as the build spells it (`debug`,
  `safe`, ...); `zig_version`: the toolchain the build runs.
- `test_runner`: `{"kind": "guardian", "dependency", "location", "runner"}`
  for a test root, which links Guardian's runner from the path dependency in
  `build.zig.zon`, or `{"kind": "none"}` for an executable. It holds no
  absolute path; the runner's content is bound through the Guardian recipes.
- `producers`: the reviewed closure metadata of `tooling-units` and
  `text-scalar-units`, unchanged from version 2.

Every prepared artifact has a producer: `mylang`, `units`, `core`, `cli`,
`golden`, `memory-budget`, `component-support`, `component-builder`,
`tooling-units` and `text-scalar-units`, and so do the installed Selka
`components`. Their entry's `path` is `libexec/mylang/components/test-index.json`
(the coordinator's provider is both manifests and the two executables they
name); recipes are the build files, `selfhost/*.zig`, `selfhost/components/`
and `selfhost/component-seed.json`, with `optimize: "debug"` and
`test_runner: {"kind": "none"}`. The seed archive is fetched from outside the
tree, but the pin's `archive_sha256` fixes its bytes and the component build
refuses any other archive, so the pin's recipe bounds it. A new artifact must name its recipes
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

Receipts are schema 3 under `.mylang-cache/verification-v3/`; each receipt
records `"version": 3` and every action key starts from the domain
`selka-verification-action-v6`. Schema-2 receipts in `verification-v2` are never
opened, and a schema-2 record found under a v3 key is a miss, so the first
request after the change reruns every action once. Report schema remains 1.
`last-run.json` shows, per action, whether its key is path-free and which
variables entered it:

```bash
python3 scripts/verify_cache.py --zig "$ZIG"
jq '.actions[] | {id, path_free, environment_variables}' .mylang-cache/verification-v3/last-run.json
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
  every key; a keyed change such as `MYLANG_MEMORY_LIMIT` changes every key.
- **Paths.** The common identity holds no checkout path. The checkout lock and the
  shared store's coordinator lock still use the real path, for mutual exclusion only.
- **Prepared artifacts.** Native executables embed the checkout path in their debug
  information, so their bytes differ between worktrees. When
  `zig-out/verification/artifacts.json` (version 3) declares a `producer` for an
  artifact, the coordinator identifies it by what produced it instead: the
  content of every file of the preparation and build-configuration snapshots its
  `recipes` select, the recipes, `optimize`, `zig_version` and `test_runner`.
  An installed copy (`zig-out/bin/mylang`) must have the produced bytes. A recipe
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
