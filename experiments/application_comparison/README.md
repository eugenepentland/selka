# Application comparison coordinator v2

Current checkpoint (2026-09-07): suite-local verified Zig build reuse is implemented,
51 targeted checks and the real 21-input practice probe passed, and three direct
coding-agent blocks (nine sessions, no API key) have completed private grading.
See [build reuse and EDA repair results](../../docs/experiments/direct-agent-clearance-20260907.md)
and [pin-role shared-contract results](../../docs/experiments/direct-agent-pin-roles-20260907.md).
Later chronological implementation notes retain historical API/fixture status;
these exploratory runs do not enable scored launch or establish a language win.

Implementation in progress for the [application maintenance plan](../../docs/experiments/application-comparison.md).
The active objective is the full evaluation plan, including real application
baselines and measured agent attempts. This checkpoint is executable harness
infrastructure; it does not establish that `.my` improves productivity.

## Implemented and exercised

- Linux user/mount/PID/network namespaces, a private root, writable candidate/cache
  mounts, read-only tools, dropped capabilities and no-new-privileges.
- Bounded stdin/stdout/stderr, command deadlines and per-process memory/file/CPU
  limits. Killing a timed-out command or its coordinator kills its PID namespace,
  including detached descendants. A namespace setup failure never falls back to
  unrestricted execution.
- Separate preparation and task clocks, explicit practice failure, timeout and
  abandonment states, and preserved failed submissions.
- Multi-file edits, added/deleted files, protected-file enforcement, FD-based
  bounded source capture, exact source identities and immutable submission copies.
- Sealed three-language blocks; matching checks for language, model label, cohort,
  arm and budgets. All hidden executions receive the same request, never expected
  answers. Frozen grading plans reject changed requests, answers or tool adapters.
- Coordinator-owned command adapters execute all phases in isolation and preserve
  raw output and phase timing. Completed per-language grading can resume. An
  unfinished execution fails closed pending explicit investigation; automatic
  interrupted-execution recovery is not implemented yet.
- Behavioral correctness is separate from on-time development acceptance. A late
  required check cannot become an on-time success just because hidden tests pass.
  Actual main-arm agent grading requires a Zig Guardian phase.

The participant command gateway now chooses the practice/task mount itself,
checks phase deadlines and frozen tools, and keeps command records outside the
participant mount. Fixture tests cover source separation and rejection of arbitrary
coordinator paths/operations. Public checks now capture immutable submissions, execute trusted cases/adapters
within the remaining task budget, and expose bounded diagnostics. Completion rejects
unchecked edits and retains late attempts as budget exhaustion. Gateway configuration
is pinned across restarts. The explicit model loop and bounded HTTP transport are implemented and fixture-tested;
reported usage is retained with missing-usage flags. Live API compatibility, complete
phase orchestration and cohort launch receipts remain unverified, so this is not
yet evidence of whole-agent isolation for a scored session.

## Application contracts, oracles and baseline construction

The [workflow planner v1 contract](contracts/workflow-planner-v1.md) specifies
bounded JSON parsing, deterministic validation, dependency ordering, synchronous
layers and unlimited-worker timing. `planner_oracle.py` supplies coordinator-only
expected results and reproducible mixed fixtures. Its tests exhaust all 512
three-vertex directed graphs against separate permutation/path enumeration,
including self-cycles and blocked downstream jobs. These are specification tests,
not participant results. The contract still needs independent review and freezing
before scoring.

The [EDA inspector v1 contract](contracts/eda-inspector-v1.md) defines board units,
connectivity, clearance checks, net-span estimates and deterministic SVG output.
`eda_oracle.py` is coordinator-only. Tests compare its geometry with independent
lattice-point/cell enumeration across 784 rectangle/clearance combinations and
exercise unit equivalence, report ordering, references and SVG structure. It now also has raw transport handling and seeded mixed construction cases.
Shared coordinator transport rules live in `oracle_transport.py`; applications
have their own independent parsers.

An independent agent built the [Python planner baseline](baselines/planner/python/README.md)
from the contract without reading the oracle or other implementations. It has its
own independent tests. Coordinator conformance additionally executes its CLI inside the
namespace runner against 64 reproducible public construction cases and raw
transport cases (including nesting and Unicode scalar boundaries). These seeds are public and cannot become hidden trial seeds.
The compact v1 application is a starting baseline: it does not yet meet the plan's
larger maintenance-workload requirements. Do not pad its files or count baseline
construction as a scored session. An independent [Python EDA baseline](baselines/eda/python/README.md) also passes
its own independent tests and the same form of isolated oracle/transport conformance.
It passes the valid 55 MB output amplification fixture with an explicitly enlarged
runner budget; see [feasibility findings](contracts/feasibility-notes.md).
An independent [Zig planner baseline](baselines/planner/zig/README.md) compiles
with the pinned compiler and passes its own 12 Debug tests and eight actual-stdin
checks. Coordinator tests rebuild it in ReleaseSafe inside isolation. Its main-arm Guardian adapter now passes the strict gate in isolation; cohort freezing remains pending.
The independent [Zig EDA baseline](baselines/eda/zig/README.md) also passes isolated
coordinator conformance, plus its own Debug tests and stdin tests in both build
modes. The [.my planner baseline](baselines/planner/my/README.md) also passes independent
functional tests and isolated generated conformance. Owned buffers resolved the
initial large-array storage problem: dense 128-job cycles and 16,384 distinct
unknown references now pass its stress checks. Initial resource failures and the
corrected missing-I/O probe diagnosis remain documented. The [.my EDA baseline](baselines/eda/my/README.md) passes coordinator conformance
and the identical 55 MB output fixture used for Python and Zig. That fixture exposed
and verified a fix for host arena retention under the common memory limit.
All six initial baselines are implemented. Independent idiom/contract review,
cohort policy freezing, and realistic product growth remain before their trials.

Adapters support both canonical JSON and exact raw bytes. Coordinator case files
contain either `{"request": ..., "expected": ...}` or
`{"request_base64": "...", "expected": ...}`, never both input fields. Base64
must use canonical padded encoding. The raw path can transmit malformed JSON,
duplicate keys, invalid UTF-8 and over-contract-size input without parsing it first.
The coordinator permits at most 2 MiB per input, allowing boundary tests above the
planner's 1 MiB limit. Exact bytes, encoding, byte count and SHA-256 are retained
in grading receipts; any change invalidates a grading retry. Inputs go only to
the application run phase. This is transport infrastructure acceptance, not proof
that application parsers conform. Public fixture seeds must never be reused for
hidden scoring.

## Run acceptance

From the repository root:

```sh
python3 -m unittest discover -s tests/application_comparison -v
python3 -m experiments.application_comparison.cli --help
```

The tests require Linux unprivileged namespaces, `/usr/bin/unshare`, `mount`,
`setpriv`, and the installed Python, Zig and `.my` binaries. Isolation tests are
not skipped when unavailable. Toolchain acceptance compiles a small multi-file Zig
program and executes equivalent Python and `.my` programs inside the boundary.
These are **fixture tests**, not participant attempts or application benchmarks.
The grading lifecycle fixtures intentionally use tiny Python adapter programs for
all labels; they validate orchestration separately from actual toolchain execution.

A read-only prerequisite probe, with a dedicated empty working directory:

```sh
mkdir -p /tmp/comparison-doctor-work
python3 -m experiments.application_comparison.cli doctor --work /tmp/comparison-doctor-work
```

The CLI exposes `prepare`, `start-preparation`, `start-task`, `submit`, `check`,
`seal`, `grade` and `status`. These are trusted coordinator commands. They must not
be exposed unrestricted to participants: their arguments can identify baselines,
adapters and hidden grading files. `check` expects a frozen adapter JSON produced
by `execution.freeze_adapter` and public cases in one of the JSON/raw formats above. `grade` takes the corresponding three adapters and coordinator-only hidden
cases, after sealing. Grade exit success means grading completed; inspect each
language's `accepted` result to judge its submission.

`record_kind=fixture` is the default. Selecting `agent` is a record label, not proof
of an actual isolated agent session. Independent agents have constructed baselines, but no scored participant attempts
have been collected.

## Work required before the scored pilot

`cohort.py` now generates matched schedules (36 pilot sessions and 144 main
sessions) and snapshots supplied baseline/task packs. Loading verifies the exact
scheduled inventory, configuration and snapshot contents. These are construction
manifests with launch disabled; checksums detect changes, not authenticate authors.
The six [pilot briefs](pilot_tasks/README.md) and their public schedule preview
are drafts, not launched trials. `planner_pilot_oracle.py` implements the separate
priority, cycle-group and input-boundary task expectations. Its checks enumerate
all 512 three-job graphs, compare priority orders with exhaustive valid permutations,
and compare cycle groups with independent graph search. `eda_pilot_oracle.py`
adds separate pin-role and rotation expectations, with regression checks for
unchanged v1 inputs, electrical role combinations, occupied rectangles, unit
conversion, net spans, board edges and SVG. These are coordinator-only code.
Complete grading packs and independent reference review remain pending.

1. Implement the [participant runtime boundary](contracts/participant-runtime.md)
   that routes **every** participant filesystem/process
   tool through this boundary and preserves fresh model contexts, practice history,
   exact model settings, usage and command events. Isolating candidate execution
   alone does not isolate an agent with unrestricted host tools. Preparation must
   not expose the scored task/source; task and preparation deadlines need enforcement
   by the gateway in addition to the coordinator's submission/sealing checks.
2. Freeze complete toolchain, runtime/system-library and documentation receipts in
   a cohort manifest. Adapters currently hash their declared mounted tools/resources;
   the explicit read-only system mounts are still backed by the mutable host. Freeze the
   application stdlib inventory and audit dependencies before scoring.
3. Finish and review the six application baselines against the two contracts.
   The [raw-byte I/O host](contracts/byte-io-host.md) is now built and independently
   exercised inside isolation. All six baseline implementations pass construction
   conformance; complete independent review and the frozen dependency inventory.
   The old board geometry callback is not an allowed business-logic shortcut.
4. Add cohort randomization, human/model telemetry, resource accounting, explicit
   interrupted-job recovery and reports that retain failures and paired outcomes.
   The current grading API trusts the coordinator-supplied grader identity; the
   cohort launcher must pin and verify the actual oracle/generator artifacts.
5. Freeze the main Zig Guardian policy, reject attempts to weaken it, then run
   unscored calibration and the 36-session pilot with all launch prerequisites met.
6. Continue to the plan's meaningful larger snapshots, selected follow-ups and
   concurrent trials when the staged evidence warrants that investment.

The namespace boundary is not a VM. It mounts reviewed tools and system binaries,
provides no external network, and isolates candidate processes from coordinator
files. Per-process rlimits do not cap aggregate memory/process counts across a
forking tree; cgroup/team quotas and a persistent worker lifecycle registry are
still needed for production concurrent-agent waves. A coordinator killed abruptly
can also leave scratch directories for later verified cleanup, even though its
worker processes are terminated. Do not claim live ten-agent throughput from this
checkpoint or from the current four-slot agent setup.

The raw-byte application host adds `src/byte_io` and `mylang-io` to the normal
Guardian-backed build/test graph, with baseline freezing disabled. Its installed
ReleaseFast executable loads application source from disk. Language semantics were
not changed for this bridge. Application coordinator acceptance uses installed
tools; `zig build test-byte-io` validates host changes and exercises Guardian.

The [main Zig Guardian adapter](guardian_policy/README.md) is implemented and tested
in isolation for both baselines. It enforces coordinator policy and source coverage;
main-agent checks reject arbitrary commands merely labeled as a Guardian phase.
No scored trials have launched.

`cohort_sessions.prepare_fixture` now provisions a scheduled row from a verified
cohort and task pack. Repair tasks receive the matching source mutation; feature
tasks retain the baseline. Every language receives identical protected public
brief/case files under `.trial-public/`, which becomes visible with task source
only after preparation ends. Seeds, mutation receipts and hidden cases remain in
coordinator-owned directories. Zig main-arm policy and root entry are protected.
Common time/submission budgets and model limits come from the cohort manifest.

Per-arm, per-session atomic reservations reject duplicate provisioning even when
workers choose different output directories. Failed provisioning remains reserved
for explicit investigation; automatic recovery is not implemented. The runtime
reservation registry lives under the cohort's `fixture-reservations/`; it does not
alter the frozen baseline/task snapshots. The session and grading report record
`pair_id`, preventing a three-language result from mixing repetitions of one task.
This entry accepts fixture cohorts only and does not start a model or a task clock:

```sh
python3 -m experiments.application_comparison.cohort_sessions \
  --cohort /private/fixture-cohort --session-id planner-priority-r1-my \
  --directory /private/fixture-runs/planner-priority-r1-my
```

The gateway must receive the resulting `session/` subdirectory, never the full
envelope. The practice gateway and preparation model loop now pass simulated-model
acceptance: practice is independently checked, failed/budget practice is retained,
and its history continues into a separate task loop. Frozen practice curricula,
scored-launch validation remain separate work.

`session_driver.run_fixture` now orchestrates both phases from a fresh prepared
fixture session. It captures the supplied practice source before timing starts,
pins the gateways/prompts/model limits, runs checked preparation, carries only that
session's practice transcript into its task, and seals the task. Its report records
separate phase durations/usage and combined reported usage with completeness flags.
An unexpected transport/tool failure preserves an interrupted record and active
phase; the driver refuses to restart over it. This is fixture-only orchestration,
not scored-launch authorization. Both phases accept either one case or a complete named public pack. Every case
uses the same captured source and shared remaining phase budget. Failures remain
visible, deadline-skipped cases fail acceptance, and diagnostics have a shared
64 KiB raw-output budget. Per-case outcomes are returned to the participant.
Reviewed matched curricula, cohort-to-driver binding and live-access prerequisites
remain to be connected.

`scheduled_driver.run_fixture` binds a prepared reservation to the fixture session
driver. It verifies the cohort, reservation registry/output path, captured source,
attempt identity, model and budgets before any model call. The task prompt and all
public checks come from the verified task pack; callers cannot substitute them or
override model limits. Main-arm Zig adapters must use the trusted Guardian sequence.
Unsupported additional model settings reject rather than being silently ignored.
The integration test uses a simulated participant to repair the real Python planner
boundary variant and pass all three public checks after practice. It also rejects
a changed task budget before starting the model. This is construction evidence;
practice curricula, tool/system receipts and live launch prerequisites still need
to be frozen and reviewed before scored use.

Cohort v2 accepts `practice_paths` for all three languages, snapshots those packs,
and validates their language identities. Provisioning retains protected practice
guides/contracts during the task. The scheduled driver derives practice source,
checks and prompts from the cohort and rejects substitutions. V1 remains available
for legacy fixtures; neither version authorizes scored launch.


Environment receipt construction now lives in `environment_receipt.py`. V2
hashes file contents, executable permissions, ownership, directory entries and
symlink targets; tool receipts retain the original selection path so retargeting
an executable alias is detected. Unreadable files fail capture with their path.
CLI verification requires coverage of all configured system mounts; a receipt
of selected tools alone cannot pass that check. Five focused tests cover content,
permissions, alias changes, missing mounts, incomplete coverage and read failures.

On 2026-09-07, receipts for the installed Python, Zig, `mylang-io` and Guardian
executables were captured and reverified at
`/tmp/application-tools-environment-receipt.json`. These cover executable files,
not complete toolchains. The original full-`/usr` capture failed at unreadable
`/usr/local/sbin/server-backup-check`. The runtime now uses a shared, explicit
`runtime_policy.py` mount list: distribution executables/libraries/headers and
selected locale, timezone, terminal and Git data. `/usr/local` and unrelated
service data are absent from both execution and inventory. Every execution records
its actual system mount mapping. The revised full-system receipt captured and
reverified successfully at `/tmp/application-explicit-system-receipt.json`
(52,415 entries, 4,195,252,270 bytes; approximately three seconds per scan).
This is complete coverage of the revised system mounts, not a complete toolchain
receipt or immutable image. Cohort binding and pre/post-session verification
remain prerequisites for scored use.
Receipts detect observed drift, not an immutable host, transient changes between
scans, or resource contention. Scans belong outside participant timing.


`session_driver.run_fixture(..., environment=receipt)` now verifies a supplied
full-system receipt before preparation starts and again after the task is sealed.
Build the receipt with `environment_receipt.capture(tools=
environment_receipt.session_tools(tools, task_adapter, practice_adapter))` so it
covers every participant, practice-check and task-check tool mount. Missing system
coverage or a mismatched tool inventory rejects before any model call. The original
receipt and successful before/after scans are stored privately under `driver/`;
the session configuration and result bind its hash. Verification elapsed time is
reported separately and occurs outside the participant phase clocks.

A post-task mismatch retains the sealed source and model transcripts, records
`interrupted.json`, and does not emit `driver/result.json`. Six session-driver tests
include real full-system scans, incomplete coverage rejection and a tool changed
during a simulated task. Five receipt tests also pass. Legacy fixture calls without
a receipt explicitly report `environment.status = not-requested`; they are not
verified trials. Mandatory cohort binding, grading eligibility checks and scored
launch remain unfinished. These checks do not prove host immutability or catch a
change that is completely reverted between scans.


Cohort v3 freezes an `environments` mapping keyed by
`<arm>/<task-block>/<language>` for both arms and every scheduled task/language.
It requires frozen practice packs and full system-mount coverage in each receipt.
Cohort loading validates retained receipts without scanning the current host;
session startup performs the live scan. The scheduled driver selects the frozen
receipt without accepting a caller override. Provisioned sessions retain its hash,
so invoking the lower-level driver without that receipt also rejects.

For these bound sessions, grading requires the retained before/after scans and a
successful driver result matching the exact sealed session and configuration.
Missing evidence, an interrupted driver, or inconsistent hashes reject before
hidden candidate execution. The grading plan includes the environment identity
and driver-result hash. Legacy fixture cohorts remain available and make no
verified-environment claim. V3 still does not authorize scored launch.


`trial_configuration.freeze(language, application, arm, zig=..., guardian=...,
byte_io=...)` constructs concrete task/practice adapters, participant tool mounts,
and full environment receipts. `zig` names the complete toolchain directory,
including `lib`, rather than just its executable. The main Zig task uses the
trusted Guardian wrapper/policy, Debug tests and ReleaseSafe build; its
language-focused counterpart retains the tests/build and omits Guardian. Practice
uses the common exercise without Guardian. Python uses the system interpreter
with `-S -B`; `.my` invokes the installed raw-byte host and loads source from disk.
All three receive the same per-command resource limits. This does not impose a
whole-session aggregate memory quota or authorize live/scored execution.

Two command-selection tests cover all twelve application/language/arm conditions
and missing required tools. Four actual planner configurations (Python main,
`.my` main, Zig main and Zig language-focused) have been captured and reverified
using installed tools; see `evidence/trial-configuration-validation.json` for
retained local artifact paths. Construction verification hashes tools and does
not run Guardian or launch a model. These configurations still need freezing with
coordinator/transport and grader provenance for an actual calibrated cohort.


Trial configuration metadata validation now checks the declared condition against
both adapters: exact command sequences, common limits, language identity,
participant/check tool inventories and required environment receipts. Recomputing
a checksum after changing a Python planner configuration to the EDA command, a
different language, unknown arm, extra tool or unequal limit does not make it valid.
`validate` checks frozen metadata without reading current tool contents; `verify`
also checks live tools and system contents. The factory and validator share command
plans to keep the intended arm difference explicit. Three focused tests pass,
including seven rehashed-invalid variants, and all four retained installed-tool
configurations remain valid under the stricter checks.


Cohort v4 accepts `configurations` keyed by `<arm>/<task-block>/<language>`.
Each entry is a validated `trial_configuration.freeze` result matching the
scheduled application, language and arm. It requires frozen practice packs and
derives its environment mapping from the configurations; supplying a separate
environment mapping rejects. Both mappings are covered by the cohort hash.

For v4, call `scheduled_driver.run_fixture` without `tools`, `task_adapter` or
`practice_adapter`: it selects them from the cohort and rejects replacements.
Provisioned sessions retain the full configuration hash as well as the environment
hash. The lower-level session driver requires that configuration and exact matching
arguments; grading checks the retained driver configuration identity. This closes
the gap where receipts pinned mounted files but commands or limits were selected
after the cohort was frozen. Versions 1–3 remain legacy construction formats; none
of these versions authorizes scored launch. Model transport and coordinator/grader
provenance, calibration, and actual scored-launch handling remain separate work.


`coordinator_receipt.capture(transport_identity)` records every top-level Python
module in the coordinator package, the running Python executable and standard
library tree, interpreter version/implementation, and the supplied transport
identity. `verify` checks the same source root, module inventory, contents and
runtime; added/deleted modules or transport substitutions reject. Policies,
documentation and task data remain covered by their separate receipts.

Construction validation captured and reverified 39 current modules using the
Responses transport's actual implementation identity (no API request or credential
was used). Two tests cover source edits/additions/removal, aliases, receipt edits
and transport mismatch. Evidence is in
`evidence/coordinator-receipt-validation.json`. This records on-disk provenance,
not loaded-code attestation: a running Python process may retain modules imported
before files changed. Cohort binding and a fresh coordinator process using the
verified source/runtime are still needed before claiming a trial ran that version.


`fresh_coordinator.py` is a standalone `python -I -S -B` entry for provenance
probes and deterministic fixture replay. Its coordinator-owned request contains
an operation, coordinator receipt, transport identity, and (for replay) cohort,
prepared envelope and bounded response list. Replay transport identity is
`fixture-replay:<canonical-response-list-sha256>`; no network model is invoked.

Before importing the harness, the entry reads all recorded module files and checks
the exact bytes/metadata against their receipts. A dedicated importer compiles
those captured bytes in memory, rejects unlisted coordinator imports, and bypasses
on-disk bytecode caches. Python/runtime and on-disk provenance are verified before
and after the operation. This addresses stale coordinator module imports; child
setup scripts and native libraries still need their existing execution receipts.
The entry itself and Python bootstrap remain trusted. This is not a hostile-host
attestation system or a live-model launcher.

Two focused tests exercise required startup flags, transport mismatch, unknown
imports and source changed after capture. The v4 Python fixture test now invokes
the fresh process for the full practice-and-repair sequence. Coordinator receipts
still need to be frozen into the cohort, and durable launch/output records and
parent-death cleanup for this outer worker remain unfinished.


`coordinator_run.run(request, directory, wall_seconds=..., output_bytes=...)`
wraps the fresh process in a unique launch directory. It records the exact request,
launch identity/limits, PID, bounded stdout/stderr and terminal result. Reusing the
directory rejects. Verification/startup exceptions retain `interrupted.json`;
timeouts, failed exits and output-limit termination retain their outcomes and
captured bytes. A zero exit also requires a matching fresh-worker result identity.
The wrapper uses the existing Linux parent-death launcher and kills the process
group on timeout, output exhaustion or cleanup. Its deadline includes coordinator
setup and receipt scans; participant phase times remain separately recorded.

Four focused tests pass for successful provenance probes, retained pre-spawn
failure, output bounds, timeouts and parent-death cleanup. The full v4 Python
fixture integration now uses this durable launcher. This still runs only probes
or deterministic fixtures; no network model access is enabled. Interrupted launch
directories require explicit investigation rather than automatic replay. Freezing
coordinator provenance in a cohort and the independent grading runtime remain
unfinished.


Cohort v5 adds a frozen `coordinator` receipt to the complete v4 configuration.
Its transport identity must match the scheduled run. Provisioned sessions retain
the coordinator hash; the session driver requires a matching verified in-memory
importer, rather than accepting an ordinary already-imported coordinator process.
The fresh worker compares its supplied receipt to the cohort before running a
fixture. Wrong transport identities and ordinary in-process invocation reject
before participant work starts.

Before/after coordinator receipts are retained under `driver/`, outside participant
clocks. The driver configuration binds their identity, and grading requires both
records to match the sealed session and transport. Missing coordinator evidence
rejects. The complete Python fixture now covers v5 through the durable fresh
launcher. Live-model transport, grader execution provenance, calibration and
scored-launch authorization remain unfinished; v5 is still a construction format.


`verified_grading.capture(adapters)` records the complete system mounts and all
three graders' declared tools. `verified_grading.grade_fixture(...,
environment=receipt)` verifies that inventory before and after a full hidden
fixture pack. It uses a new attempt directory, retains before/after receipts,
and binds the environment and pack-result hashes in its verified report.

Missing coverage rejects before hidden execution. A tool/runtime change preserves
intermediate pack records and `interrupted.json` but produces no verified final
report. Attempt directories cannot be overwritten; lower-level pack resume remains
available for explicit construction investigation and does not itself certify the
runtime. Tests include an induced grader-tool change and the full seven-case
three-label fixture (21 isolated executions, deliberately incorrect programs),
with original failure accounting and unchanged per-case resume still checked.
This wrapper remains fixture-only. Deriving the grader environment from a frozen
cohort and running grading through the verified fresh coordinator are still needed.


`verified_grading.from_configurations({language: frozen_configuration, ...})`
derives hidden-grader adapters and tool receipts directly from all three frozen
task configurations. It requires matching application/arm and identical recorded
system environments, selects only task-check tools, and preserves full Zig and
Guardian resources. It makes independent copies so editing a derived adapter
cannot mutate the supplied cohort configuration. No live recapture selects newer
tools during derivation; the existing grading wrapper verifies the derived receipt
against the actual runtime before and after execution.

The derived receipt's `capture_seconds` is zero because derivation performs no
scan; its enclosing record explicitly says `derived-from-frozen-task-configurations`.
Verification still measures real scan durations. A focused test builds three
configurations, verifies the combined runtime, checks all main-arm Guardian mounts,
and rejects a rehashed mismatched system environment and incomplete language set.
The scheduled/fresh grading entry still needs to enforce this derivation.


The fresh coordinator accepts `grade-fixture` requests with a v5 cohort, three
sealed session roots and a new grading directory. `scheduled_grading.run_fixture`
requires verified fresh imports, matches each session to its cohort schedule and
reservation, checks frozen configuration identities, and derives all grader
adapters/runtime receipts from the cohort. It accepts no caller-supplied grading
commands or tools. Coordinator and grader environment receipts surround execution;
only the outer successful report certifies the complete scheduled grading attempt.

The construction integration exercises three registered, deliberately abandoned
attempts through fresh session workers and then fresh scheduled grading. Fake
language executables are never run because none of the attempts submits code;
this tests end-to-end failure retention, reservation/configuration binding and
provenance, not language behavior, Guardian execution or development productivity.
The separate pack-grading fixture still exercises real isolated executions.
No API calls or scored launches are enabled by this grading entry.


`cohort_summary.summarize(cohort_directory, grading_directories, arm='main')`
produces a descriptive fixture report over every assigned schedule row. It follows
reservation/session/driver records and the scheduled → verified → pack grading
hash chain. Duplicate grading pairs, mismatched session identities and results
outside the selected arm reject. The report distinguishes unlaunched, incomplete
provisioning, active, infrastructure-failed, sealed-ungraded and graded attempts.

Language totals retain all assignments in the acceptance denominator and flag
incomplete grading. Preparation and task durations include all observed sealed
attempts, not just successes, and report missing counts. Token totals explicitly
state observation count/completeness; missing data is unknown, and monetary cost
per accepted change remains undefined without cost records. Summed phase time is
not experiment wall time. Behavioral rejections are not classified as root-cause
bugs. This is descriptive construction reporting, not a statistical language
comparison or causal productivity claim.

Two unit tests cover failed/unlaunched denominators and missing telemetry. The
three-language abandoned-trio integration checks one graded failure and one
unlaunched repetition per language, and rejects duplicate grading directories.
Navigation, diagnostic repair, cache/queue intervals, monetary costs, blinded
quality labels and paired statistical analysis remain future report work.


Cohort summaries now include all three pairwise language comparisons matched by
attempt ID. Counts distinguish both accepted, neither accepted, each language-only
acceptance and incomplete pairs. The paired acceptance difference uses explicitly
graded pairs; the report also shows all assigned pairs and the incomplete count.
Task-time ratios use only pairs where both were accepted and both durations are
known and positive, with missing timing counts. These conditional ratios must not
be interpreted as overall productivity or a treatment-effect estimate.

Export a descriptive fixture summary with:

```sh
python3 -m experiments.application_comparison.cohort_summary   --cohort /private/cohort --grading /private/graded-pair-1   --grading /private/graded-pair-2 --arm main --output /private/summary.json
```

The output path must be new. Omit grading paths to report pending assignments.
Three focused summary tests cover the denominator, missing data, discordant pairs,
conditional timing and duplicate identities; the full abandoned-trio integration
also checks paired failure and incomplete-repetition counts. Statistical inference,
calibration and actual agent comparisons remain unfinished.


`tool_metrics.summarize(session_root)` reads command records anchored by session
events and reports preparation/task command counts, failures, captured output bytes,
direct `rg`/`grep`/`find` invocations and the union of recorded command intervals.
It reports task-check count, adjacent checks of unchanged captured source, and
submission-to-check latency. Orphan command requests remain visible as uncommitted
records. Cohort summaries include these observations for each provisioned attempt
and reject a session changed between reads.

These are explicit proxies: shell/script searches are not classified, output bytes
are not source-read/context bytes, unchanged checks do not prove cache reuse, and
submission-to-check latency is broader than test execution. Cache hits, queue wait
and time to a relevant source location remain unknown. Two tests use real isolated
gateway commands and check records, verify overlap handling and retained orphan
requests, and reject altered command results. Semantic navigation labels and
fine-grained verification attribution remain unfinished.


A scheduled-grading regression reproduced acceptance of a copied session placed
beside the registered `session/` directory. Its record contents matched, so the old
envelope-level checks allowed it through. Grading now also requires the canonical
registered session directory. The end-to-end test retains the normal trio's result,
then submits a sibling copy and requires rejection before a grading directory is
created. This is a harness provenance defect, not evidence of a language defect or
an agent escaping isolation.


`dependency_audit.audit(root, language, entry)` records the reachable application
source files and static dependency declarations. Python uses its AST and installed
stdlib catalog, follows local modules/packages before classifying stdlib names,
and flags selected dynamic-loading/external-execution capabilities. Zig and `.my`
use a lexical declaration scanner that excludes comments/strings; unresolved or
nonliteral imports and external interfaces require review. Dependencies outside
the application source root reject. Auxiliary construction tests are outside the
application-entry inventory.

All six current entry inventories are retained in
`evidence/baseline-dependency-inventory.json`: Python entries reach one local file
each, Zig two each, `.my` planner six and `.my` EDA two. No declarations were flagged
in those entry graphs. Three tests cover local stdlib-name shadowing (including
package precedence), dynamic capabilities, comments, path escape and extra host
declarations. This is not proof of stdlib-only behavior: indirect dynamic loading,
source provenance/vendoring and trusted native host behavior still require review.
The inventory deliberately reports `stdlib_only_proven: false`; it is not a scored
launch approval or an import-policy enforcement mechanism.


The raw-byte native boundary has now been inspected through the runner, registry
and VM host-call dispatch. The comparison bridge registers only `io::length`,
`io::byte` and `io::put`; these callbacks implement scalar byte access and output
buffering. Installed-host tests reject additional callbacks and changed signatures,
and verify no buffered output is published after guest failure or a trap. Raw
invalid-text echo, disk source reload and the existing 8 MiB memory-bound output
case also pass (three tests, including four boundary rejection cases).

Source, binary and test identities and review limits are recorded in
`evidence/raw-host-boundary-review.json`. This is implementation inspection and
behavioral validation, not independent blinded review or a new reproducible-build
attestation. Zig and Guardian were not rebuilt or invoked for these checks.


Unscored calibration now has a distinct `record_kind = calibration`, separate
`calibration-reservations/`, and explicit `prepare_calibration` /
`run_calibration` coordinator APIs. Calibration cohorts require full v5 configuration
and coordinator provenance; lower-level sessions also require environment,
configuration and coordinator identities. Fixture entry points reject calibration
records instead of relabeling them. Driver/model records preserve the calibration
kind, and main-arm Zig retains the trusted Guardian requirement.

The fresh-process entry now exposes unscored calibration execution (see below).
No external API model request has been made. Scored launch remains disabled. Focused tests reject missing provenance and kind substitution;
the full frozen-cohort fixture also provisions a calibration attempt and checks its
separate reservation and session identity. Actual model selection, calibration budget values and model-driven calibration
still need completion.


Calibration grading and reporting now have explicit paths: `grade_calibration`
for pack/runtime verification, `scheduled_grading.run_calibration`, and the fresh
worker's `grade-calibration` operation. They preserve the calibration record kind,
use its reservation namespace, and retain the same source, environment and
coordinator checks. Fixture grading rejects calibration sessions. Summary reports
accept either unscored kind and reject grading artifacts from the other kind.
Neither path enables agent scoring or live model requests.

The seven-case pack test now runs both fixture and synthetic calibration records,
checks kind preservation and unchanged resume, and rejects kind substitution.
Synthetic test records are not measured model sessions. Legacy fixture grading
plans retain their original fields so this extension does not invalidate their
resume identities. Fresh scheduled calibration grading is now covered by the local HTTP integration
test below. Actual model-driven calibration with submitted edits remains pending.


Frozen model settings may now include `max_reported_tokens_per_phase`. The
scheduled driver propagates the same positive limit to preparation and task;
provisioned session identities retain it, and lower-level loops reject omission
or replacement of a frozen limit. Reports preserve the separate phase limits,
reported usage and observed overshoot. On reaching the threshold, the response is
retained but its requested tool is not executed and no further model request is
made in that phase. Preparation records a budget outcome and task execution uses
its own separately bounded phase.

This is a response-boundary stop policy, not a hard billing cap: input/output usage
is known only after a request, so one response can overshoot. Missing or inconsistent
usage stops the phase with `usage-unknown`; unknown overshoot remains null. No API
price or dollar cost is inferred. Common values still need explicit selection and
unscored calibration before actual trials. Tests cover overshoot, suppressed tools,
unknown usage, frozen-limit substitution, separate phase budgets and propagation
from a scheduled cohort.


Fresh calibration transport
---------------------------

`coordinator_run.run(request, new_launch_directory, api_key=local_key)` now
supports `operation: "calibration"`. The request contains `cohort`, `envelope`,
`coordinator`, `transport_identity`, and optionally `endpoint`; it must not contain
credentials. Supply the key from the trusted caller's local credential source.
There is no automatic model selection or automatic trial launch.

Freeze a v5 `calibration` cohort with the actual `ResponsesTransport` identity,
complete tool configurations, model name, wall/turn/output budgets and a positive
`max_reported_tokens_per_phase`, then reserve the attempt with
`cohort_sessions.prepare_calibration`. The worker verifies that frozen transport
before entering the existing preparation/task driver. Fixture and scored cohorts
cannot use this operation. The reported-token threshold remains a response-boundary
stop policy, not a hard billing cap.

The outer launcher passes the credential through a bounded private pipe. Its saved
request and command line contain no credential value; the fresh worker closes the
pipe before participant execution. Only the trusted HTTP transport subprocess
receives the credential environment. The normal participant environment remains
minimal. Completed launch reports count attempted transport calls; a failed or
interrupted calibration launch reports that count as unknown rather than zero.
Inspect retained session records for partial usage and do not silently retry an
attempt in a new directory.

The integration test uses a loopback HTTP server and the transport's literal
`fixture` credential restriction. It runs the fresh worker and both session phases,
checks calibration record identity and frozen limits, and rejects changed transport
identity and a missing token limit before any HTTP call. A separate sentinel key is
absent from retained rejection artifacts. These are harness fixtures, not actual
model calibration or comparative evidence. Official API credential handling:
https://developers.openai.com/api/reference/overview#authentication


Calibration CLI and full-path fixture
-------------------------------------

After freezing the cohort and selecting a scheduled session ID, provision an
attempt without executing a model:

```sh
python3 -m experiments.application_comparison.cohort_sessions \
  --kind calibration --cohort /absolute/cohort \
  --session-id planner-input-boundary-r1-python --directory /absolute/attempt
```

Save the credential-free request described above to a JSON file. With the key
already configured locally as `OPENAI_API_KEY`, execute one attempt:

```sh
python3 -m experiments.application_comparison.coordinator_run \
  --request /absolute/calibration-request.json --directory /absolute/launch \
  --wall-seconds 3600
```

The CLI returns nonzero on a failed launch and refuses to overwrite a launch
folder. A missing credential is rejected before creating the folder. It supplies
credentials only for the `calibration` execution operation; grading does not need
an API key. The same launcher accepts a `grade-calibration` request containing
`cohort`, the three registered session `roots`, a new grading `directory`,
`coordinator` and `transport_identity`.

The full-path test launches `.my`, Python and Zig calibration records against a
local response server, deliberately abandons all three, runs fresh scheduled
hidden grading, and summarizes the matched trio. Every failure and unlaunched
repetition remains visible; timings and usage observations are retained, incomplete
telemetry is explicit, and fixture grading rejects calibration cohorts. The test
uses placeholder compilers that are never invoked: it validates failed-attempt
accounting and provenance, not submitted program behavior or actual model quality.


Observed stops in cohort reports
-------------------------------

Each attempt now exposes `preparation_stop`, `task_stop`, `seal_reason`, and any
recorded `interruption_type` / `interruption_phase`. Language totals count observed
reasons and explicitly report missing observations. For example, an early
`transport-timeout` remains distinguishable from `budget` and
`reported-token-limit`, even when all receive unsuccessful behavioral outcomes.
A failed preparation phase can coexist with an accepted task; neither fact erases
the other. Grade status and the all-assigned denominator are unchanged.

These fields describe recorded events. An exception type alone cannot establish
whether the fault belongs to the provider, harness, language implementation, or
participant; independent failure review remains necessary. A hard-killed worker
may leave no final driver report, so absent phase stops remain unknown. Interrupted
attempts still require explicit investigation and must not be silently restarted.

Completed phases survive interrupted drivers
--------------------------------------------

If preparation finishes and a later transport or verification error prevents a
final driver report, the cohort summary retains preparation elapsed time and
completed phase stop/usage receipts. `partial_reported_tokens` is separate from
`reported_tokens`, with `partial_token_observations` in language totals. It covers
only completed phase reports; it is not a complete attempt total. The interrupted
phase can have additional unreported usage. No missing task time is inferred from
the current wall clock, and `usage_complete` remains false.

Each recovered phase includes configuration/result hashes. The reader verifies the
configuration digest, model, phase, record kind and usage arithmetic. Completed
driver totals and recovered partial phase totals are mutually exclusive for each
attempt, avoiding double counting. This does not authorize grading or retrying an
interrupted attempt.

A local HTTP regression reproduces preparation completion followed by a task HTTP
500. Before the fix, the summary lost the completed preparation stop and time;
after the fix it retains that phase and its two fixture tokens, while task time and
full attempt usage remain unknown. This is a harness reporting defect, not a defect
found in any of the three participant languages.

The stricter partial receipt check also exposed a configuration-hash mutation:
`initial_input` shared the growing transcript list, so the final loop report hashed
more input than the saved configuration contained. The loop now snapshots its
initial input. A regression checks the final hash against the saved configuration
after real tool turns. Historical phase receipts with inconsistent configuration
hashes are rejected; this change does not rewrite or retroactively certify them.


The [interruption recovery policy](recovery-policy.md) defines retained evidence,
liveness checks, phase clocks, partial usage, grading limits, and treatment of
additional calibration attempts. It does not enable automated recovery or scored
replacements; human review records and optional summary integration are implemented; cohort binding remains pending.


`cohort_summary --reviews /absolute/private/reviews` adds evidence-checked human
failure labels to the report. Current, stale, unreviewed, and not-requested statuses
are explicit; only current reviews contribute category counts. The report retains
the review chain head and selected record hashes. Labels never alter acceptance,
assignment denominators, or paired outcomes. See the recovery policy for details.


Baseline boundary inspection
----------------------------

`evidence/baseline-boundary-review.json` records the reviewed source identities,
inspection scope, and remaining limitations. All six current application-entry
inventories match the earlier inventory. Full Python entry inspection and targeted
Zig/my boundary inspection found no application business logic delegated to an
external helper. This is not an independent source-origin audit or installed-binary
attestation; those remain open.

The reachable application files currently have these physical source-line counts
(including comments and blank lines, excluding auxiliary tests):

| Application | .my | Python | Zig |
| --- | ---: | ---: | ---: |
| Planner | 1,181 | 222 | 501 |
| EDA inspector | 1,471 | 219 | 412 |

These counts are descriptive, not productivity results. In particular, the `.my`
implementations carry local JSON parsing code while Python uses its standard JSON
library. That difference belongs in adoption and maintenance cost measurements.
Do not pad the other implementations to equalize line counts or attribute the
entire difference to language syntax without measuring the maintenance tasks.

Typed JSON is not the benchmark's plain JSON boundary
----------------------------------------------------

The language already has source-level `json_encode` / `json_decode`; they use the
`typed-json-v1` envelope and checked nominal types. The comparison contracts use
ordinary JSON requests such as `{"cases":[]}`. Those formats are different.
`evidence/installed-json-boundary-probe.json` preserves three source-loaded probes
against the installed byte host, its hash, and the generated source template:
typed boolean decoding succeeds, while a plain boolean and plain application
envelope return the checked malformed-input error. No compiler rebuild was needed.

The probes test direct calls, not every possible adapter. Together with
`docs/experiments/source-json.md`, they establish why simply replacing the baseline
parser with the existing typed decoder would change the wire contract. They do not
show that a general JSON library or contract-preserving source adapter is impossible.
Do not add host-side business parsing to make this arm appear smaller. If a suitable
source library is implemented later, freeze a new cohort and report that toolchain
change. Library maturity is part of present-day adoption cost; these probes are not
comparative development-speed results.


Main `.my` tooling configuration
-------------------------------

New trial configurations use `application-trial-configuration-v2`. For `.my` in
the main arm, `trial_configuration.freeze` requires explicit `compiler` and
`navigate` paths in addition to `byte_io`. These are mounted as `/tools/compiler`
and `/tools/navigate`, with all identities included in practice, task and grading
environment receipts. The language-focused arm retains the byte host only. Run
commands and behavioral grading contracts are unchanged.

The practice guide describes bounded navigation and compiler inspection commands.
A real isolated probe using the installed compiler and `scripts/navigate.py`
resolved `planner::run` with checked source locations, signature and effects;
`evidence/isolated-navigation-trial-probe.json` records the tools and source hashes.
No compiler rebuild or Guardian gate was exercised by that probe.

Historical v1 configurations remain readable as historical records. New main `.my`
calibration execution requires v2 so it cannot silently use the earlier restricted
tool inventory. Do not compare those two tool conditions as identical workflows.
This corrects tool availability; actual use and benefit still require agent trials.


Observed language-tool use
--------------------------

Tool metrics now include per-phase `language_tool_commands` and
`failed_language_tool_commands`, grouped by navigation client, compiler index,
dependency graph, schema, checks, quality reports and duplicate discovery. Only
direct invocations of declared tool mounts are counted. Shell/script contents and
lookalike workspace executables are not interpreted as tool use. A count records
an invocation attempt, not a relevant location found or a correctly repaired error.
Cache reuse remains unknown in these metrics.

`evidence/navigation-metrics-probe.json` records an installed navigation query for
`planner::run` through the isolated participant gateway. The metric reports one
navigation invocation and no failed navigation command, with declared tool
identities and captured output. This is an instrumentation fixture with zero model
calls, not an agent productivity trial. Unit tests also cover failed direct calls,
undeclared mounts, and command strings embedded in shells or Python `-c`.

Installed v2 `.my` planner configurations have now been captured and reverified
for both arms. `evidence/my-tooling-configurations-v2.json` indexes the complete
configuration/verification records. This establishes that the actual installed
byte host, compiler and navigation client can be included in the frozen environment,
not merely placeholder fixture files. These records are point-in-time evidence:
verify them again before a future launch, and capture a new configuration if tools
or the runtime environment change. No model cohort or scored launch is authorized
by these receipts.


Recovery policy in frozen cohorts
--------------------------------

`application-coordinator-v2` receipts include the complete recovery policy text and
its SHA-256, in addition to coordinator modules and Python runtime identities.
Cohorts retain that receipt. Receipt verification detects policy changes, and new
fresh calibration execution requires v2. An old cohort cannot silently acquire
new retry rules from an edited working document. Legacy v1 receipts remain readable
for historical fixtures; they do not retroactively attest a recovery policy.


New coordinator process records retain Linux boot/namespace/start-tick identity.
`process_identity --record /absolute/launch/process.json` performs a read-only
liveness observation; legacy PID-only records remain unknown. It never sends a
signal or authorizes a retry. See the recovery policy for observation limits.


The current broad harness regression passed 141 tests across 39 modules.
`evidence/harness-regression-current-v2.json` records coordinator/runtime/policy
identities, test hashes, included and excluded modules, and the retained log hash.
Sources remained unchanged during execution. Application/compiler rebuild checks
were excluded; this result does not replace baseline conformance or binary
attestation, and no external model calls occurred. The earlier 118-test evidence
remains available as a historical snapshot.


Installed runtime source validation
----------------------------------

`evidence/byte-runtime-source-validation.json` and its build log record a
ReleaseFast `test-byte-io` build with a new local Zig cache. All eight build steps,
three Zig tests and the raw-byte/reload/publication/input-bound CLI checks passed.
Captured Zig sources, build files, policy and CLI test inputs remained unchanged.
The emitted `mylang-io` SHA-256 exactly matches the installed runtime, which was not
replaced. Guardian selfcheck passed and its unchanged-input gate result was cached
with zero blocking findings; this was not a fresh execution of all quality checks.

This is evidence connecting the inspected runtime sources to the installed binary
under the recorded local toolchain. It is not a hermetic supply-chain attestation
or independent source-origin review. The navigation compiler has separate source-validation evidence below; the actual
trial cohort still needs validation. No model calls occurred.


Installed navigation compiler source validation
----------------------------------------------

`evidence/navigation-compiler-source-validation.json` records a ReleaseFast build
with a new local cache and temporary installation prefix. All 12 build steps and
8 navigation-client tests passed. The emitted compiler exactly matches installed
`zig-out/bin/mylang`. Captured source, navigation client/test inputs and Zig standard
library hashes remained unchanged; no installed tools were replaced. Guardian
selfcheck passed and its unchanged-input gate result was reused with zero blocking
findings. The build log and hashes are retained. This connects the installed
inspection tool to the current source under the recorded local toolchain; it is not
an independent origin audit or a comparative agent trial.


Single-command calibration setup
--------------------------------

`calibration_setup` freezes a new unscored cohort from selected small pilot blocks.
It requires explicit model, reported-token limit, common budgets and tool paths.
It does not require a credential, make API calls, reserve participants, or launch
attempts. The budget JSON must contain positive integer `preparation_seconds`,
`task_seconds`, `max_submissions`, `max_turns`, and `max_output_tokens` fields.
Choose these values before invoking the command; the provisional study timings are
not automatic authorization for a live run.

```sh
python3 -m experiments.application_comparison.calibration_setup \
  --directory /absolute/calibration-setup \
  --block planner-input-boundary --seed calibration-order-1 \
  --model "$CALIBRATION_MODEL" \
  --reported-tokens-per-phase "$CALIBRATION_PHASE_TOKENS" \
  --budgets /absolute/common-budgets.json \
  --byte-io zig-out/bin/mylang-io --compiler zig-out/bin/mylang \
  --navigate scripts/navigate.py --zig /absolute/zig-toolchain \
  --guardian /absolute/guardian-check
```

Repeat `--block` to select additional catalog blocks. Setup captures both arm
configurations, three practice packs, fresh private task data, actual baseline
snapshots, coordinator/runtime/policy identity and the common model settings. The
cohort has two repetitions of each matched three-language block; each arm uses its
own reservations. Subsequent `cohort_sessions` and `coordinator_run` commands remain
explicit. Setup does not bypass remaining launch review or scored-launch restrictions.

The destination cannot be overwritten. Failures retain `setup.json` and
`interrupted.json`, with no successful result. A successful result identifies the
frozen `cohort/` directory and its hash. Keep the whole setup directory private from
participants; their gateway receives only the projected public task/practice files.
The integration test uses placeholder executables without running them, verifies
full cohort binding and no reservations, and covers invalid settings, overwrite
rejection and retained setup failure.
