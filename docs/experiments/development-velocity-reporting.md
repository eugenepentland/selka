# Development velocity evidence reporting

`experiments.development_velocity.report` projects a completed runner cohort into
the existing `analysis.analyze` schema. It performs no application execution,
grading or clock correction. Create the report implementation before freezing a
cohort: runner registration includes all top-level harness Python files.

Inspect progress without aggregate or parity claims:

```
python3 -B -m experiments.development_velocity.report /external/study/cohort --inventory
```

Inventory (`development-inventory-v2`) lists the registered arms and every
registered task/pair/arm, with each arm's language and interface, including
not-prepared and unfinished attempts. It is an explicitly incomplete inventory, not
an accepted analysis projection. A full report requires all twelve task IDs and
every registered pair in both arms (at least 24 attempts):

```
python3 -B -m experiments.development_velocity.report /external/study/cohort \
  --output /external/study/reports/cohort-001
```

The output directory must be new. It contains `analysis-input.json`,
`summary.json`, and `report.md`; existing results are never overwritten. Private
case contents, seeds and execution outputs are not copied. Evidence paths and
file hashes remain available to the coordinator. Registration includes paths and
hashes for frozen inputs/tools and is not an external custody attestation.

Full projection verifies current registered tools/harness and task inputs,
registration/context bindings, session identity/budget, protected runtime inventory,
every submitted source snapshot, private case/source/result identities, exact
session hashes, and grading summary booleans. It recomputes telemetry against the
stored profile; incomplete operations or uncommitted command records fail closed.
A checked scope violation has the gateway's explicit rejection receipt and no
public execution directory. Reporting validates that exact receipt, including
budget-exceeded-during-capture rejection, and retains the failed check. All other
checked public submissions and private cases must match their on-disk pack and
per-case result. Command phase/argv and source/adapter/input identities are bound
to frozen inputs. Stdout/stderr files are retained by hash, and actual run stdout
is parsed to reconstruct behavior. A claimed pass requires isolated, successful
steps and the expected JSON result; not-run/deadline cases cannot pass. A correct
output already marked false (for example, late completion) stays false.
All read receipts and snapshots are checked again before publication. A missing
attempt, grade, profile, stale file or unfinished operation cannot disappear from
the denominator.

Each attempt may have a coordinator-authored `source-review.json`:

```
{"version":"development-source-review-v1","source_sha256":"...",
 "decision":"approve","findings":[]}
```

Decisions are `approve`, `approve_with_nits`, or `reject`; the source hash must
match the exact final submission. An absent review becomes `pending` and receives
no qualification, rather than excluding the attempt. A no-submission attempt has
no source to review. Context bindings supply `context_id` as analysis participant
identity; duplicate contexts are rejected. Runtime/transport modifications in
submitted work remain recorded scope violations, not eligible successes; changing
the protected inventory itself or tampering with frozen bytes rejects the report.

No-submission, abandonment, public/private failures and budget stops remain in
the analysis. All unqualified attempts cost the entire registered task budget;
a fast failure therefore cannot become a speed improvement. Raw elapsed time
remains visible, including over-budget duration. Passing checks alone are
insufficient: the terminal status, budget, behavior, verification and review must
all qualify under the existing analysis policy.

Timing uses the session's same-boot monotonic start/seal nanoseconds. UTC start/end
and raw clock records remain traceable, but UTC adjustments do not change the
cost. Preparation is separate. The report links the frozen readiness record and
retains each attempt's practice/preparation record and links the parent study journal.
It does not infer global preparation elapsed time. Any explicit
`preparation-start-correction` event supersedes the original manually converted
start when interpreting that journal, while the original record remains intact.

Identities iterate the registered arm labels from `configuration.arms`; a
registration without that field keeps the literal `my`/`python` pair, and its
projected attempts carry no `arm` field so `analysis.py` v1 still accepts them.
Attempts live at `task/pair/<arm label>`, and tools, adapters, practice packs and
frozen baselines are keyed by label: `task/<arm label>-baseline` carries that arm's
`WORKFLOW.md`, and a legacy cohort's labels are its language names, so
`my-baseline` and `python-baseline` are unchanged. Tables include task and family costs/completion by arm, named
`.my`/Python for a legacy cohort and by candidate/comparator label otherwise.

Observations include repeated diagnostic codes counted per operation, declared
operation purposes, captured output bytes, observed operation time and unobserved
wall time, each keyed by arm label.
Compiler/VM/Python phase records are grouped by arm, language, tool, phase name and
inclusive flag, with call count and summed duration seconds. These totals are
reported separately: parent/child and compound-command phases can overlap and
do not measure pure compiler CPU. Practice and private grading are excluded.
Phase totals are never added to operation/application wall time.
Store session metrics (`bytes_returned`, per-verb counts, `context_omitted_total`,
`if_match_conflicts`, `batch_rejections`) are projected per arm from each profile's
`store_metrics`; a files arm reports them as null. Profiles are
`development-profile-v2`, carrying the arm label, interface and that slot, so a v1
profile cannot be recomputed. Missing telemetry remains null. Unobserved wall time
combines drafting, reasoning, scheduling and orchestration; none is inferred
separately. Diagnostics are not bug counts, command/output counts are not
turns/tokens, and compiler phases nest inside operation time rather than adding
independent time.

Development-phase reports cannot trigger a parity stopping claim. Confirmation
criteria, family weighting, capped costs and uncertainty remain owned by
`analysis.py`; this projection does not introduce a different success criterion.
Fixture tests exercise stale source/review/grade/profile rejection, missing
operations, pending review, failed-fast outcomes, timeout costs, context uniqueness
and exclusive publication without starting participants or invoking a compiler.
