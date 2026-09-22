# M3 — project invocation (implementation)

Implementation of the [M3 runbook](../../docs/audits/m3-project-invocation-runbook-2026-09-20.md):
one bounded test of whether specifying a project's root, entrypoint and
verification manifest once reduces the effort agents spend delivering correct
changes across that project's workflows.

**Status: stopped at the readiness check. No participant session was launched.**

The runbook's own rule applies: *"If either cannot pass with the chosen current
toolchain, stop and report readiness as the blocker before spending on
participants."* The frozen `sexpr-port` snapshot passes its public workload with
the frozen compiler; the frozen planner snapshot does not compile at all. The
readiness record is [`evidence/readiness.md`](evidence/readiness.md), the machine
record is [`evidence/preflight.json`](evidence/preflight.json), and the published
stop is [`cohorts/pilot/readout.md`](cohorts/pilot/readout.md).

<!-- The line above is updated by the runner's readout; keep the links stable. -->

## What is here

```
project              thin launcher: `project verify [--entry P --manifest P]`
m3.py                runner: materialize, selftest, preflight, freeze, run, monitor, score
m3lib/               coordinator modules (pack, workspace, grading, scoring, cases)
pack/tools/          frozen compiler, QBE, byte-I/O host and workflow scripts + identity
pack/apps/<app>/     frozen application snapshot, description and public manifest
pack/cases/<case>/   task briefs and hidden fixtures (never participant-readable)
controls/base/       offline negative-control project (module header, missing import)
evidence/            selftest, preflight, readiness and the frozen hidden oracle values
cohorts/<cohort>/    manifest, raw evidence, readout.json and readout.md together
work/                scratch: per-session working copies, preflight and replay trees
```

## The two arms

Both arms use the same launcher and the same `project.run` backend, with the same
frozen compiler, cache location, report path, brief, metadata explanation, path
rules, examples, documentation and public checks. Only entry/manifest selection
differs:

| arm | participant command | who names the paths |
| --- | --- | --- |
| `manual` | `project verify --entry <path> --manifest <path>` | the agent |
| `automatic` | `project verify` | the active project's description |

The active project is a public, read-only `project.json` named by
`MYLANG_M3_PROJECT`; its directory anchors the relative entry and manifest paths,
so selection does not depend on the working directory. The automatic arm also
accepts explicit paths, which are used exactly as the manual arm uses them.

The launcher forwards `--only` step selection for local feedback. A submission is
the sealed source, never the selected subset: coordinator grading always runs the
full declared public workload plus the case's hidden checks, so skipping steps
cannot make delivery look cheaper.

Every compiler process — navigation, every manifest step, or a direct
invocation — goes through a counting shim that records one
`compiler-invocation-v1` event (the M1 event module, reused unchanged) and then
runs the frozen tool. Resolution failures that never reach a compiler are
recorded separately in a resolution ledger. The shim also keeps every cache root
outside the application source tree, so a check cannot look like an edit.

## Commands

```bash
cd /home/epentland/ai/canopy/mylang
mkdir -p .tmp/m3 && export TMPDIR=$PWD/.tmp/m3

python3 experiments/project-invocation-m3/m3.py materialize        # freeze tools + applications
python3 experiments/project-invocation-m3/m3.py selftest
python3 experiments/project-invocation-m3/m3.py preflight --all
python3 experiments/project-invocation-m3/m3.py freeze --cohort pilot --seed 20260920
python3 experiments/project-invocation-m3/m3.py run --cohort pilot --dry-run
python3 experiments/project-invocation-m3/m3.py run --cohort pilot --max-new-sessions 8
python3 experiments/project-invocation-m3/m3.py monitor --cohort pilot
python3 experiments/project-invocation-m3/m3.py score --cohort pilot
```

`materialize` is the only addition to the runbook's command list: the frozen pack
has to exist before `preflight` can be meaningful. Only `run` may launch model
sessions; every other command is a local check, freezing, monitoring or scoring
step. `freeze` refuses an existing cohort and refuses a pack that is not
preflight-ready; `run` re-verifies the entire frozen identity before each new
session and never reruns a terminal cell.

## What the instrument demonstrates (`selftest`)

1. **Resolution equivalence** — explicit and automatic selection produce the same
   effective entry, manifest, compiler, cache and feedback on the same source
   from the application root, `app/tests`, `app/sexpr` and the workspace parent,
   and on the frozen application itself.
2. **Negative controls** — a wrong module header and a missing import are rejected
   in both arms with `E_MODULE_NAME` / `E_MODULE_READ`; these are offline controls
   outside the scored task pack.
3. **Invocation counting** — three compiler processes in one shell command
   produce three events; one process produces one event however many diagnostics
   it prints; repeated reads change nothing; a resolution failure before any
   compiler launch is recorded in the resolution ledger and not as an event.
4. **Evidence integrity** — a sealed snapshot still grades after its working copy
   is deleted, and a check that edits the project during execution invalidates its
   receipt (`status: stale`, `identity_unchanged: false`).
5. **Attempt immutability** — an existing attempt directory is refused; a frozen
   schedule cannot be rewritten.
6. **Synthetic scoring** — whole cases are resampled with all repetitions inside
   each draw, a missing record stays unknown rather than zero, and the improvement
   sign is right in both directions.

## What the existing guest-test workflow already handles

Recorded here because it decides how much invocation friction the tasks can
honestly contain. The runner the applications already use
([`docs/tooling/guest-tests.md`](../../docs/tooling/guest-tests.md)) already:

- discovers an enclosing root for a standalone `*_test.my` in a subdirectory
  (nearest ancestor with `mylang.json`, or the nearest ancestor holding a
  non-test `.my` source) and resolves its imports and dotted module name there;
- accepts a library entry with no `main` (it checks a private copy with a stub
  `main`) and synthesises the dotted `module` header for a bare `*_test.my`;
- runs a directory as one project, selecting project roots and skipping generated
  `.mylang-cache`, `.zig-cache`, `zig-out` and `.git` trees, so a multi-module
  project is one program rather than one `E_MAIN` failure per module;
- reports a child compiler's located diagnostic with exit 1 rather than a generic
  host-failure line.

What it does **not** do — and what the two arms differ on — is select the
*verification workload*: the entry and the `verify.json` manifest still have to be
named, the manifest must sit beside the entry, and `scripts/project.py` runs the
manifest's commands from that directory. Neither arm withholds that guidance; the
`automatic` arm resolves the two paths from the active project description instead
of requiring the agent to supply them.

## Preflight

`preflight --all` materializes each variant of a case (reference, seeded
regression, wrong repair), grades it with the frozen tools through real
`verify.py` manifests, and requires: the reference passes public *and* hidden
checks; the seeded regression fails an appropriate public check *and* the hidden
checks; every plausible wrong repair is rejected by an independent check. Public
and hidden checks demand the same contract on different inputs; hidden inputs,
expected values, mutations and wrong repairs live only under `pack/cases/*/hidden`
and `evidence/oracles.json` and are never copied into a participant workspace.

## Scoring

The pilot gate is the runbook's: at least three of eight sessions with an
*avoidable* invocation failure, at least one in each application, where
avoidability is decided only by a coordinator replay of the same sealed source
snapshot with corrected root/entry/command selection. The replay may surface a
separate source error; that is recorded and the failure still counts. Replay work
is outside participant cost and is never shown to a participant.

The main cohort's primary score is restricted delivery time: elapsed participant
time for a submission passing the full public and hidden workload, 900 seconds for
non-submission, deadline expiry or hidden rejection, and *unknown* — blocking a
definitive decision — for a missing or corrupted record. Cases are averaged with
equal weight inside each arm; the interval is a bootstrap over whole cases within
each application (10,000 draws, frozen seed) that retains every repetition inside
each selected case. Results are reported per case and per application.

## Current readiness result

Frozen identity (`evidence/preflight.json`): compiler `4024b68f1815ba1a`, launcher
`668863638be91ccc`, runner `7f6b437be545f7e4`, case pack `474e732999bd8860`, model
`deepseek-v4-flash`/`max`, deadline 900 s.

| application | public workload | seconds | snapshot digest | compiler diagnostics | ready |
| --- | --- | ---: | --- | --- | --- |
| `sexpr-port` | passes | 38.2 | `c7b43e6be85e387e` | none | yes |
| `planner` | fails | 0.04 | `b1795b992bdc7240` | `E_REMOVED_SPELLING` | no |

Five cases are preflight-ready (`sexpr-percent`, `sexpr-invalid-input`,
`sexpr-units`, `sexpr-escaping`, `sexpr-nesting`): each reference passes public and
hidden checks, each seeded regression fails both an appropriate public step and
the hidden checks, each plausible wrong repair is rejected by an independent
hidden check, and explicit/automatic resolution agree from four working
directories. Five cases are *declared* only — the planner tasks — because the
application they belong to cannot run.

The planner baseline under `experiments/application_comparison/baselines/planner/my`
predates the 2026-09-14 Wave 1 surface migration (`=>` match arms, plain `export`,
`&[]` borrows, heap/allocator entry points). Porting it to populate the experiment
is explicitly out of scope, and it was not altered in place. `freeze --cohort
pilot` and `freeze --cohort main` therefore both refuse; no session was launched,
no model spend was incurred, and `cohorts/pilot/readout.md` publishes the stop
with `gate.evaluated = false` and decision-rule row `not-reached`.

### What would unblock it

The experiment needs a second application that (a) is written in the current
surface, (b) has a verification manifest whose workload fits comfortably inside
900 s, and (c) can be frozen as a snapshot. `src/schematic/guest` is the obvious
in-repo candidate but is not driven the way the runbook describes (`mylang-io
--project` needs its own argument contract) and lives inside the compiler tree, so
substituting it is a design decision for the runbook's owner rather than something
this implementation may take on its own. The five declared planner cases can be
authored against a current snapshot without changing the frozen task pack.
