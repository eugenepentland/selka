# M3: does project configuration remove repeated invocation work?

Date: 2026-09-20. Status: implementation runbook; no M3 sessions launched.

> **Outcome (2026-09-20):** the instrument is implemented and its six no-model
> checks pass (`experiments/project-invocation-m3/`). Preflight then applied this
> runbook's own readiness rule: the frozen `sexpr-port` snapshot passes its public
> workload with the frozen toolchain, but the frozen planner baseline does not
> compile with it (pre-Wave-1 surface: `=>` match arms, plain `export`, `&[]`
> borrows), so `freeze` refused both cohorts and **no participant session was
> launched**. See [the M3 README](../../experiments/project-invocation-m3/README.md),
> [`evidence/readiness.md`](../../experiments/project-invocation-m3/evidence/readiness.md)
> and [`cohorts/pilot/readout.md`](../../experiments/project-invocation-m3/cohorts/pilot/readout.md).
> The text below is unchanged.

**Decision to make**

Run one bounded test of this claim: specifying a project's root, entrypoint and
verification manifest once reduces the effort agents spend delivering correct
changes across that project's workflows. This is a test of one structural
simplification, not a test of a universal elegance score or of mylang against
another language.

Start with an eight-session headroom pilot. Proceed only if it finds real,
repeated invocation friction. The main experiment is then exactly 36 sessions.
Maximum model spend is **44 sessions**, excluding no failures from that count.
Do not expand the cohort after seeing its result.

This narrows the [earlier M3 plan](elegance-next-step-plan-2026-09-19.md) to two
arms: both get good invocation documentation; one automates its application.
An additional poorly documented baseline would spend sessions answering a
different question. Leave M1/M2 artifacts unchanged.

**1. Build only the intervention and the small runner**

Create `experiments/project-invocation-m3/`, containing a thin `project` launcher,
`m3.py`, case definitions and immutable cohort artifacts. Reuse the existing
[project workflow](../experiments/project-workflow.md) and
[scripts/project.py](../../scripts/project.py). Do not add compiler semantics,
an abstraction learner, a dashboard or a new generic experiment framework.

Both arms use the same launcher and the same `project.run` / `project.compact`
backend. The launcher supplies the frozen compiler, cache location and fresh
report path identically. Only entry/manifest resolution differs:

| Arm | Participant command | Responsibility |
| --- | --- | --- |
| `manual` | `project verify --entry <path> --manifest <path>` | Agent reads the project metadata and supplies the paths. |
| `automatic` | `project verify` | Launcher resolves those paths from the active project's description. |

These are **interfaces to implement**, not existing commands. The automatic
arm must also permit explicit paths. The manual arm may write a convenience
script; charge its work normally and retain its assigned arm in the analysis.

Use one public, read-only project description per application with `entry` and
`manifest` paths relative to the description's directory. Supply its absolute
location to both arms through the same environment variable and briefing.
This makes the active project explicit even when the working directory changes.
Both arms receive the same description, metadata explanation, path-resolution
rules, examples, language documentation and public checks. Document the relevant
command syntax for each arm accurately; do not withhold useful baseline guidance.

Keep output, diagnostic remedies, navigation, test selection, caching and report
access identical. The wrapper must not edit source or public tests, supply a
solution, consult hidden checks, or accept a subset of the declared workload.
Record underlying compiler/check processes: bundling five calls into one command
does not count as removing four calls.

The existing script requires the manifest beside the entry and at least one
test/parity/mutation step. Respect those constraints. Adapt application test
launchers to a frozen snapshot and tool paths equally in both arms; do not change
the backend during a cohort.

**2. Freeze two real applications and ten distinct tasks**

Use these applications if their current snapshots pass preflight:

- [S-expression port](../../experiments/sexpr-port/README.md): nested modules,
  guest library tests and a CLI with independent parsing/rendering checks.
- [Workflow planner](../../experiments/application_comparison/baselines/planner/my/README.md):
  several modules, a CLI contract suite and an existing `verify.json`. Freeze its
  byte-I/O host as well as the compiler; its tests must use that host explicitly.

Snapshot the selected working-tree contents, including required uncommitted
files. Record content hashes; a Git revision alone is insufficient. Vendor any
required fixtures or oracle assets into coordinator storage so live sibling
repositories cannot change the result. Never alter these applications in place.
Do not port an incompatible application just to populate this experiment. If
either cannot pass with the chosen current toolchain, stop and report readiness
as the blocker before spending on participants.

Use ordinary behavioral maintenance tasks, with a small seeded regression and
an unambiguous requested behavior. **Do not seed bad module headers, broken
imports, wrong commands or misleading documentation in the scored tasks.**
Invocation mistakes must arise during reasonable work, not be planted as the
answer the experiment is designed to find.

Prepare this pack; pin the exact briefs, mutations and oracles before running:

| Split | Case | Behavioral repair | Initial working directory |
| --- | --- | --- | --- |
| Pilot | `sexpr-percent` | Restore percent literal scaling. | application root |
| Pilot | `sexpr-invalid-input` | Restore rejection of a malformed input category. | `tests/` |
| Pilot | `planner-empty` | Restore the contractual empty-graph result. | application root |
| Pilot | `planner-zero-duration` | Restore timing for zero-duration jobs. | workspace parent |
| Main | `sexpr-units` | Restore mm/mil conversion on several magnitudes. | `sexpr/` |
| Main | `sexpr-escaping` | Restore canonical quote/backslash rendering. | `tests/` |
| Main | `sexpr-nesting` | Restore correct parsing/rendering of nested empty forms. | workspace parent |
| Main | `planner-chain` | Restore earliest-finish propagation along dependency chains. | application root |
| Main | `planner-ties` | Restore lexical ordering of simultaneously ready jobs. | workspace parent |
| Main | `planner-boundary` | Restore the documented manifest-count boundary. | application root |

These are task specifications to author and preflight, not claims that these
bugs exist today. Use genuinely different edits and oracle cases: reject byte
duplicates and superficial renamings. Do not reuse M1's module-family faults.
If a proposed task does not fit the current contract, replace it **before the
pilot**, documenting why; freeze the complete pack then.

For every case, preflight the reference, starting regression and at least one
plausible wrong repair. Reference passes public and hidden checks; the regression
fails an appropriate behavioral check; wrong repairs fail independent checks.
Check the brief's examples against both oracles explicitly. Use the actual
`verify.py` manifest schema, not an invented `args` extension. Public and hidden
checks must demand the same contract with different inputs. Hide solutions,
mutations and hidden inputs from participant-readable files.

The current [guest test workflow](../tooling/guest-tests.md) already discovers
some enclosing roots and supports library entries. Record which planned
obligations it already handles. Use the current frozen compiler in both arms;
do not select an older compiler to recreate obsolete friction.

**3. Pass focused, no-model checks**

Extend the existing measurement machinery only where M3 needs it. Demonstrate:

1. Explicit and automatic resolution produce identical effective entry,
   manifest, selected checks, compiler arguments and feedback on the same source.
   Exercise root, nested and parent working directories.
2. A genuine invalid module header or missing import is rejected in both arms.
   These are offline negative controls, outside the scored task pack.
3. All launched compiler processes are counted, including children of manifest
   steps; shell grouping and repeated delivery do not change the count. Resolution
   failures before a compiler launch are recorded separately.
4. Evidence survives source cleanup, source changes during a check invalidate its
   receipt, and the coordinator grades the sealed snapshot with frozen tools.
5. The deadline stops further participant work; an unfinished or hidden-failing
   attempt remains in the score. Existing attempts and changed identities cannot
   be overwritten or silently resumed.
6. Synthetic scoring retains every repetition when resampling whole cases,
   handles missing evidence explicitly, and gets the improvement sign right.

Do not make a full compiler build or unrelated regression suite a prerequisite
for this wrapper-only change. Follow the repository's Guardian feedback rule if
implementation validation does exercise a Guardian gate.

**4. Run the headroom pilot: eight sessions**

Run the four development tasks in the `manual` arm, two fresh sessions each.
Use the eventual main model/settings and limits. No participant carries context
between sessions. This pilot measures opportunity, not a treatment effect.

Classify an avoidable invocation failure only when a coordinator replay of the
**same source snapshot**, with corrected root/entry/command selection, removes
that invocation error. The replay may expose a separate source error. A module
diagnostic code by itself is insufficient evidence. Keep replay work outside
participant cost and never show replay results to the participant.

**Proceed only if at least three of eight sessions have an avoidable invocation
failure, with at least one affected session in each application.** This is a
chosen practical screening threshold, not a literature-derived constant. Also
report time spent recovering from those mistakes and whether the automatic
resolver would have removed each one in an offline replay.

If the gate fails, publish the pilot and stop M3: this workload does not establish
enough remaining invocation friction to justify the proposed intervention.
Do not remove guidance, deepen paths or change faults to force the gate open.
If measurement or oracle defects invalidate the pilot, stop this run and report
the defect; do not quietly replace sessions within the 44-session allowance.

**5. If the gate passes, run exactly 36 main sessions**

Schedule six held-out tasks × two arms × three repetitions. A block is one
case/repetition pair. Randomize the block order and arm order within each block
with a recorded seed. Run one participant at a time, with a fresh source copy
and context; keep paired sessions close in time. No intermediate arm comparisons.

Freeze a **900-second participant deadline per session**. Preflight must establish
that a normal full public verification fits comfortably inside it. Start the
clock when the brief and workspace are available. Submission seals the source
and triggers coordinator public verification, which is included in the deadline
and elapsed time. An existing full public receipt may be reused only for the
identical sealed source and tool identity. Stop when submission verification
finishes or the deadline expires; a failed public submission ends that attempt.
This prevents skipping public checks from making delivery appear cheaper. Grade
hidden acceptance afterward, outside the participant clock. Hidden checks are
never feedback to participants.

Use identical model identity, reasoning setting, tool permissions and public
verification workload. Choose the same initially empty per-session build/test
caches; do not share a previous arm's receipts. Record cache and provider usage
fields and actual latency. This is **not** a matched-token-budget experiment.
Keep any underlying adapter limits identical and record their configuration.

Use disk-backed scratch under the workspace, not `/tmp`. Allocate separate cache,
report and staging directories outside candidate source trees. Preserve sealed
source, events, reports, usage and transcript before removing a working copy.
No automatic retries: record infrastructure incidents and missing evidence. If
those compromise the comparison, the cohort is inconclusive, not repaired by
quietly adding sessions.

**6. Score delivery first; explain the mechanism second**

Primary score is restricted delivery time. A submission passing the full public
and hidden workload receives its elapsed participant time; non-submission,
deadline expiry or hidden rejection receives 900 seconds. A missing or corrupted
record is unknown and blocks a definitive decision; it is never zero seconds.
Report acceptance separately so a time score cannot conceal correctness losses.

For each case, average its three repetitions per arm. Average those case means
with equal case weights, then report the relative saving:

```text
saving = 1 - mean(automatic restricted time) / mean(manual restricted time)
```

Report per-case and per-application results. For a descriptive 95% interval,
bootstrap whole cases within each application, retaining all paired repetitions
inside every selected case; use 10,000 draws and a frozen seed. There are only
six distinct tasks and two applications, not 36 independent generalization
examples. Intervals do not justify claims about programming projects generally.

Secondary measures: accepted submissions; generated tokens with reasoning counted
once; cached/uncached input under the provider's documented accounting; tool
steps; all underlying compiler calls; avoidable invocation failures; time to the
first correctly targeted check; and unnecessary source edits prompted by path
confusion. Retain both assigned-arm outcomes and actual command use. Do not
exclude agents who bypass the launcher or automate the manual commands themselves.

Record one-time wrapper implementation and per-project configuration effort.
Report configuration break-even as setup time divided by observed positive
per-task time saved; if savings are absent, there is no demonstrated break-even.
Keep engineering time and model-generated tokens in their own units.

Predeclare this decision rule before the pilot:

| Result | Action |
| --- | --- |
| At least 20% overall time saving; interval above zero; positive point saving in both applications; no lower observed acceptance in either application; fewer avoidable invocation failures | Keep the workflow improvement. Consider one later, separately specified transfer study. |
| Acceptance falls, or total delivery time worsens without an offsetting correctness benefit | Investigate the concrete regression; do not claim the intervention helps. |
| Smaller saving, mixed applications, uncertain interval, or insufficient invocation reduction | Report inconclusive or below practical target. Stop this research line for now; do not automatically add repetitions. |

The 20% threshold is a project decision about useful payoff. Equal observed
acceptance is not a non-inferiority proof. A benefit confined to one application
may justify a local convenience tool but does not pass this research criterion.

**7. Commands to implement, then run in order**

There is currently **no M3 runner**. Implement the following CLI contract in
`experiments/project-invocation-m3/m3.py`; do not mistake this block for commands
that already work. Only `run` may launch model sessions. All other commands are
local checks, freezing, monitoring or scoring. `freeze` must refuse an existing
cohort and `run` must verify the entire frozen identity before each new session.

```bash
cd /home/epentland/ai/canopy/mylang
mkdir -p .tmp/m3
export TMPDIR=/home/epentland/ai/canopy/mylang/.tmp/m3

# After implementing the thin launcher, runner and ten case definitions:
python3 experiments/project-invocation-m3/m3.py selftest
python3 experiments/project-invocation-m3/m3.py preflight --all

# Freeze tools, model settings, task pack, rules and eight-session pilot schedule.
python3 experiments/project-invocation-m3/m3.py freeze --cohort pilot --seed 20260920
python3 experiments/project-invocation-m3/m3.py run --cohort pilot --dry-run
python3 experiments/project-invocation-m3/m3.py run --cohort pilot --max-new-sessions 8
python3 experiments/project-invocation-m3/m3.py score --cohort pilot
```

The pilot score writes JSON and Markdown, including the gate result and its
source-pinned replay evidence. Read it before proceeding. `freeze --cohort main`
must refuse unless the pilot is complete, valid and passes the declared gate.

```bash
# Only after the pilot passes; preserve the frozen task pack and decision rules.
python3 experiments/project-invocation-m3/m3.py freeze --cohort main --seed 20260921
python3 experiments/project-invocation-m3/m3.py run --cohort main --dry-run
python3 experiments/project-invocation-m3/m3.py run --cohort main --max-new-sessions 36

# Safe from another terminal; integrity/status only, without arm comparisons.
python3 experiments/project-invocation-m3/m3.py monitor --cohort main

# Once all scheduled cells have terminal statuses:
python3 experiments/project-invocation-m3/m3.py score --cohort main
```

Resuming `run` launches only pending cells, never reruns terminal cells or exceeds
the frozen schedule. Dry-run prints every cell and the remaining/maximum counts.
Store each cohort's manifest, raw evidence, `readout.json` and `readout.md` together.
The final readout must name the decision-rule row it meets, disclose incidents,
show every scheduled outcome and link the evidence needed to reproduce the score.

**What finishing M3 means**

A clean pilot stop is a completed experiment. A main-cohort null or inconclusive
result is also completion. A positive result supports one narrow example of
removing repeated project-selection work. None of these results validates a
general elegance metric; that broader programme should remain paused.
