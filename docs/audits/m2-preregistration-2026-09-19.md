# M2 preregistration — the token envelope as a policy comparison (2026-09-19)

This freezes the full M2 comparison **before any of its sessions run**. It was written
after the 8-session mechanism pilot (`docs/audits/m2-pilot-2026-09-19.md`) and the
one-session low-cap enforcement probe (§7), and it changes no result: **no M2
comparison session has been launched.** The only participant sessions this module has
ever spent are the pilot's 8 (runner v1, cap 5000, dev cases) and the probe's 1
(runner v1, cap 1000, `dev-checked/repair`), all under cohort
`cohorts/pilot-5000/` and `cohorts/overshoot-1000/`.

**Revised 2026-09-19, before any session: the design list is 13 cases, not 14.** The
corpus on disk contains `variant-a` and `variant-b` as byte-identical tasks; a
paired-by-case analysis must not count one task twice, so `variant-b` is excluded from
the design list. §3.1 and §13 record the discovery; the corpus and its digest are
untouched.

Machine-readable identity and design record:
`experiments/diagnostic-feedback-m2/cohorts/m2/design.json`.

A design that is frozen is frozen with its artifacts: §1 pins the exact bytes, and if
any pinned artifact changes before the first session, this sheet is re-frozen first
(a new `design.json`, a new digest block, and a note saying what changed and why). No
cell may run against a digest this sheet does not carry.

---

## 1. Frozen artifacts and identities

All digests are sha256 of the file's bytes as it stands at freeze time.

| artifact | path | sha256 |
| --- | --- | --- |
| participant runner (v2, tri-state stop, `--cohort-id`) | `experiments/diagnostic-feedback-m2/enforcing_runner.py` | `f8b70c35ad67ba4de9600005cfb05b413f45b7f6aea01987abc73824b79c0cfd` |
| budget contract (unmodified) | `experiments/diagnostic-feedback-m2/budget.py` | `28b4fd13d119536b4777890b7176a30dc18f2806e4b87a602ff52e3dbe0080ef` |
| usage reader (unmodified) | `experiments/diagnostic-feedback-m2/m2_usage.py` | `3f6941b469dcd8e0a53f5f6235ac02ab0b726576b026ce94bd531817e11a4cee` |
| M1 runner the working copy and grading come from | `experiments/diagnostic-feedback-m2/run.py` | `eea7b7cc331ee656cbf2c8ffd24e1e46bb98ec4d63a8eba93396be24bbd36f66` |
| prompt template (`enforcing_runner.PROMPT`, 922 chars, placeholders `{request} {limit} {cap}`) | inside the runner | `73f425c69ad2c4820cb8f05e7821c0b9172066446ab4335e9893df32e39e8e43` |
| M1 base template `run.py` extends | `experiments/diagnostic-feedback-m2/run.py` | `ae2fba8f334fb92a489a328e28d1d07615ca84f314d0fb89f39980aa8187ab30` |
| frozen compiler (participant wrapper **and** grading) | `experiments/cascade/tools/bin/mylang` | `4a9ad0c17789e422fa90dbb8e91497f007abdc2ef5152f3123889dbdc2cfbcb2` |
| test-split corpus (14 case directories, 551 files; the design uses 13 of them) | `experiments/diagnostic-feedback-m2/cases/test/` | `7efcd5738e970bb06271c93159caa3bf2721ad73ce18986a17b4864035f4bcdb` |

Superseded runner revisions, kept for attribution: v1
`52018fe9c5197cecf67332bdf159bc560d55a15af4659236772886665aa4c955` produced the 8-session
pilot and the cap-1000 probe; v2 `5548c55541fce4c58d724872d0eb003fd269d330fe17589367087abb2c4f2ba1`
produced no live session and produced the probe's `reclassification.json`. The frozen
revision differs from that v2 only by the `--cohort-id` flag and one dry-run check; it
re-derives the reclassification with identical content apart from the provenance fields.

The corpus digest is computed exactly as `freeze.py` computes it (relative path +
bytes, every file under the split, sorted) and is **identical to the `corpus_sha256`
the M1b manifest froze** (`7efcd5738e970bb0`, `experiments/diagnostic-feedback/cohorts/m1b/manifest.json`):
the cases M2 will run are byte-for-byte cases the M1b cohort measured, so the
M1b replay in `docs/audits/m2-budget-calibration-2026-09-19.md` is a replay of these
instances. The digest pins the corpus *as it is on disk*, duplicate included; the
design's case list (§3) is the 13 distinct tasks and is what the analysis uses.

Participant identity, frozen: launcher `dsh --profile headless <prompt>`, model
`deepseek-v4-flash`, reasoning effort `max`, arm `text`, invocation limit 20 compiler
invocations per candidate, session deadline 900 s, Zig caches per candidate inside the
working copy, and grading per case of 2 public checks plus a hidden manifest of 3–4
steps (4 steps in 11 of the 13 design cases; `generic-c` and `generic-e` have 3). The
participant's `bin/mylang` wrapper embeds
this same frozen compiler and its hash (`conditions.install`), so the toolchain the
participant used and the toolchain that grades it are one artifact.

---

## 2. The question, and the metric that answers it

The envelope asks: **under one fixed task budget, which policy turns tokens into
accepted answers more cheaply — one session per task, or fresh candidates that each
charge the same envelope?**

* **Primary metric.** Generated (output) tokens charged to the task envelope **per
  accepted answer**, `R = Σ spend / Σ accepted`. Input volume per accepted answer,
  `RV = Σ input volume / Σ accepted`, is reported alongside it as the second half of
  the same primary metric (a policy that buys answers with context re-sends is not
  cheap even when its generated tokens are low).
* **Secondary metrics.** Public acceptance, hidden acceptance, candidates started,
  candidates ended by overshoot, compiler invocations, and the "correct at kill"
  sensitivity of §6.
* **Why cost per answer is the informative part.** Acceptance has almost no headroom
  in the comparable evidence: the M1b cohort (unbudgeted, 112 cells) accepted
  **111/112** hidden, and the M2-matching `text` arm alone accepted **28/28**. A
  comparison that can only move between 13/14 and 14/14 cannot show much; the cost of
  the answers it does keep can.

  *Brief-versus-evidence note.* The task brief for this freeze said "M1b's unbudgeted
  text arm accepted 111/112". The frozen M1b readout says 111/112 **across the whole
  cohort** with the single miss inside `text_fix`, and 28/28 for the `text` arm
  (`docs/audits/m1b-diagnostic-feedback-readout-2026-09-19.md` §1, §2). Both numbers
  are recorded here exactly as the evidence has them; the ceiling argument is the
  same either way.

---

## 3. Cases

**The 13 distinct test-split tasks in `cases/test/`** (the corpus holds 14 directories;
`variant-b` is excluded as a byte-identical duplicate, §3.1), grouped by the family
their `case.json` declares:

| family | cases | n | status |
| --- | --- | ---: | --- |
| bool-int | `bool-a`, `bool-b` | 2 | paired |
| checked-result | `checked-a`, `checked-b`, `checked-c`, `checked-d`, `checked-e` | 5 | paired |
| generic-requirement | `generic-a`, `generic-b`, `generic-c`, `generic-d`, `generic-e` | 5 | paired |
| variant-coverage | `variant-a` | 1 | **descriptive only** — one pair cannot form an interval, and it is excluded from the overall composition (§9) |

**Why the test split and not the dev cases.** Cap 5000 does not bind on the dev cases:
the pilot's largest dev cell used 2,592 generated tokens = **51.8 % of the cap** and no
dev session was cut. On the test corpus the M1b replay shows cap 5000 binding: `repair`
is cut short on **3 of 14** tasks and keeps **11 answers** (mean spend 3,459.6), while
`independent` starts 28 candidates, ends 13 by overshoot, and keeps the same 11 answers
at mean spend 5,552.5 — a first, *simulated*, sign that the policies differ in cost and
not in coverage at this cap. `repair` at unlimited keeps 14/14 at mean 4,932.1, so the
cap binds on the long tail rather than on the median session. *Those replay denominators
are 14 corpus tasks and therefore count the duplicated variant task twice; they are
indicative of binding, not the 13-case sheet's own denominators.*

### 3.1 Corpus hygiene, found at freeze time (flagged, not silently frozen)

Two properties of the corpus were discovered while pinning its digest.

1. **`variant-a` and `variant-b` are the same task — corrected in this sheet.** Their
   `project/`, `public/` and `hidden/` trees are byte-identical and their `request.md`
   files are identical; `case.json` differs only in its `id` field (so their rendered
   prompts hash the same:
   `191564e5f55de19ec30d1052ab788d06b180737215f3422f1fc63e6fe303bb20`). The 14 corpus
   directories are therefore **13 distinct tasks**. The first version of this sheet
   froze all 14 as the design list; it was corrected on 2026-09-19 **before any M2
   session** to **13 cases / 26 task-cells**, dropping `variant-b`, because a
   paired-by-case analysis that counted both would count one task twice and inflate n.
   The corpus on disk and its digest are unchanged — the corpus is also what M1b
   measured. This was already true of M1b's frozen corpus; it is a property of the
   shared corpus, not something M2 introduces. Effective paired **n = 13**.
2. **Three of the four "dev" cases are byte-identical to test cases.** `dev-bool` ≡
   `bool-a`, `dev-checked` ≡ `checked-a`, `dev-variant` ≡ `variant-a`/`variant-b` on
   `project/` + `public/` + `hidden/`; only `dev-generic` is a distinct instance. The
   pilot therefore ran on three instances that are also M2 design cases, and the pilot's
   §4 claim that the dev cases "have no prior trajectories" does not hold for those
   three (their prompt shas equal the `*-a` cases' in the pilot's own §5 table). There
   is **no treatment contamination in M2** — every M2 session is fresh, no state carries
   between participants, and nothing was tuned on the dev cases — but the **pilot's spend
   figures describe some of M2's own tasks** and are not independent of them, so they
   must not be read as a separate sample.

### 3.2 Sheet size

**13 cases × 2 policies = 26 task-cells**, one observation per (case, policy): the
analysis is paired by case, which fixes one pair per case. M1b ran two repetitions per
cell (112 sessions); adopting repetitions here would double the session budget and would
have to be frozen as a new sheet **before** the first session, not discovered during
analysis. The session ceiling is **13 + 13 × M** (§8).

---

## 4. Policies, one envelope per task

Both policies charge **one `budget.Envelope(5000)` per task**, shared by every
candidate of that task and by the selection step. A charge that exceeds the allowance
is charged at what was really generated and refuses; there is no per-candidate
envelope and no extension.

* **`repair`** — one session per task. Every call it makes is charged to the task
  envelope; an overshoot ends the task's only candidate, so the task keeps no answer.
* **`independent`** — fresh sessions, one after another, each charging the **same**
  envelope instance. Another candidate starts only while `remaining() > 0`, up to the
  pool bound of §8. After the pool stops, selection runs on the candidates that are
  complete.

**The live-versus-replay difference, stated explicitly.** `envelope_replay.py` models
enforcement over trajectories that were measured with no budget, and it can inspect a
candidate's *first call* before deciding whether to start that candidate ("first call
exceeds remaining" ⇒ unaffordable, never started). Live there is no look-ahead: a
call's size is unknown until it has been generated, so `independent` starts a candidate
whenever `remaining() > 0` and **that candidate's first call may itself overshoot and
end the cell**. Live `independent` is therefore weakly more expensive per *started*
candidate than the replay's, and it can lose a candidate on its first call; the
replay's "unstarted" counts have no live counterpart. A second, non-mechanical
difference: the replay's caps were never shown to the agents it replays, while here the
cap is in the prompt and the kill is real and mid-session, so the replay is not
evidence about pacing either.

---

## 5. Cap, selection, and what the cap actually bounds

* **Cap: 5000 generated (output) tokens per task**, reasoning included once, charged
  per model call. One envelope per task for both policies and for the selection step.
* **Selection: the public check only.** Hidden grading never chooses. After the
  candidate pool stops, the selected answer is the first complete candidate that
  passes the public examples, else the last complete candidate, else **nothing** — a
  task with no complete candidate contributes no answer, and its hidden acceptance is
  `null` (not `false`).
* **What the cap bounds, honestly.** The harness can only kill *after* the
  overshooting call's usage line is written, so live spend is bounded by **cap + one
  call**, never by the cap alone. The probe measured this exactly: cap 1000, spend
  1131, overshoot 131 on the final call. Poll lag (0.2–2.0 s observed) sets how many
  successor calls can arrive before the process dies; on a slow or large call the
  overshoot is correspondingly larger. Every figure in this sheet is a real charged
  spend, not a cap.

### 5.1 Candidate-end semantics (a deliberate commitment device)

An **overshoot-ended candidate is incomplete and unselectable even when its sealed
snapshot passes**. This binds both policies symmetrically: it is what makes the cap a
commitment device rather than a suggestion, and it is the mechanism by which a binding
cap costs a task its answer. It also means the *last* call's overshoot can discard an
answer that was already correct when the harness stopped the session.

**Observed, live, at cap 1000 (probe, §7):** `dev-checked/repair` spent 1131 generated
tokens over 7 calls; call 7 (134 tokens) had an allowance of 3 and overshot by 131, so
the task closed 131 tokens past a cap of 1000; the harness stopped the participant
mid-step; the candidate is incomplete, so the task selected nothing — while its sealed
snapshot passes the public checks (2/2) and **all four hidden steps** under the frozen
compiler. The envelope discarded an answer that was already correct, because the budget
it had been given was 131 tokens short of what the session took. This is one observed
instance of the cost the cap can impose, not an estimate of its frequency.

---

## 6. Metrics and the "correct at kill" sensitivity (predeclared)

Per task-cell, from the sealed record (and re-derived at audit time):

| symbol | meaning |
| --- | --- |
| `S(c,p)` | generated tokens charged to case `c`'s envelope under policy `p` (`record.totals.spent`) |
| `V(c,p)` | input volume charged to that envelope (`record.totals.input_volume`) |
| `A(c,p)` | 1 iff the selected answer passes the hidden manifest (`record.hidden_acceptance is True`); no selection ⇒ 0 |
| `A_pub(c,p)` | 1 iff the selected answer passes the public checks (`record.public_acceptance`) |
| `K(c,p)` | candidates started; ended-by-overshoot; invocations (`record.candidates_started`, per-candidate `ended_by_overshoot`, `events.jsonl`) |

**Secondary sensitivity, "correct at kill" (never substituted for the primary).** For
every overshoot-ended candidate, its **sealed snapshot** is graded out of band (public
2 checks + the hidden manifest; no model calls) and reported separately, per policy, as
(i) the number of task-cells where the envelope ended a candidate whose snapshot passes
public **and** hidden, and (ii) the generated tokens those cells spent. The observed
probe instance is the first entry of this table. It is a sensitivity because it prices
work the primary metric deliberately throws away; the primary metric keeps using the
frozen selection rule of §5 and nothing else.

Missing or invalid observations — a session log that cannot be matched, a grader that
did not run, an absent sealed snapshot — stay visible as missing and are **never
imputed**, never dropped, and never counted as zero spend. A task whose cell is invalid
is reported as invalid and excluded from no table silently: the exclusion is listed.

---

## 7. Enforcement evidence, and what the probe established

### 7.1 The enforcement mechanism

`enforcing_runner.py` launches one participant at a time (on-disk lock + `/proc` scan),
re-decompresses the whole growing session log every ~2 s through the verified reader,
charges each call exactly once keyed by `(session, call index)` with
`allowance = remaining()` at the moment of the charge, and on a refusal terminates the
participant's **process group** (SIGTERM, SIGKILL after a 5 s grace). After the process
stops it keeps reading for up to 3 s so calls flushed during shutdown are charged too;
`spent` always equals what was generated, and no charge is ever dropped.

### 7.2 Stop classification: tri-state, runner v2

The pilot's gate was "confirm `killed_by_harness=true`". That predicate cannot be
satisfied by this launcher: `dsh --profile headless` installs
`process.on("SIGTERM", () => interrupt(0))`
(`@deepseek-ai/dsh/lib/profile-boot-Dk-7KqJc.js`) and **shuts down gracefully with exit
status 0**, so a real, effective stop never produces the signal exit the old predicate
required. Runner v2 (`5548c555…`) replaces it with a tri-state `stop`, derived by
`classify_stop` from the recorded exit, the stop request, the reaped-after delta and the
charge list (so it re-derives offline), and it records `stop_requested_utc`,
`reaped_after_request_seconds` and `grace_seconds`:

| `stop` | meaning | status |
| --- | --- | --- |
| `signal` | the process died from the signal the harness sent | success |
| `graceful-after-request` | SIGTERM sent, process reaped inside the grace window, and **no call charged after the refusal** | success — the expected `dsh` shape |
| `none` | no stop requested, process outlived the grace window, or calls continued after the refusal | failure |

`mechanism_failures` fires on `ended_by_overshoot` with `stop == none`, on any call
charged after the refusal that does not carry `after_overshoot`, on an overshoot above
3× the cap, and on a candidate that overshot yet is marked complete. `graceful-after-request`
is a **success**, not a mechanism failure. Nothing else changed: charging, policies,
selection, rubric and evidence layout are the frozen v1 behaviour, and v1's sha still
names its own evidence.

The stricter reading is deliberate: **one** call charged after the refusal is enough to
downgrade the cell to `stop: none` and stop a pilot run. `late_calls_after_stop` and the
late call keys are recorded, so an operator can see whether that was an in-flight flush
or generation that continued.

### 7.3 The probe: one session, live, enforced

`dev-checked` / `repair` / cap 1000, runner v1 unmodified, run 2026-09-19T21:19:06Z–21:19:24Z.
Evidence: `cohorts/overshoot-1000/dev-checked/repair/{record.json,reclassification.json}`,
raw log copy in `logs/`, sealed snapshot in `sealed/repair-1/`.

| check | result |
| --- | --- |
| overshoot | yes — 7 calls, **1131** generated charged, 1 refusal |
| overshooting call | call #7: charged 134 at allowance **3** ⇒ overshoot **131** (`refused=true`, charge stands at actual spend) |
| charged live, not at settle | 7/7 (`calls_charged_before_settle = 7`) |
| spend recomputed independently from the raw log | 1131 = 1131 (0 malformed lines; the same log double-carries each usage, naive sum 2262) |
| input volume | 78,858 |
| stop | `graceful-after-request`: SIGTERM sent at ≈21:19:24.04, process reaped ≤0.234 s later (upper bound; v1 did not record the delta), grace 5 s |
| `late_calls_after_stop` | **0**, and 0 calls charged at settle |
| session log | 1 log matched (cwd + start time), 0 malformed lines, last record `step/start` at 21:19:23.194 with no `turn/end` — the session was cut off mid-step, not finished |
| budget reached the participant | the cap sentence `You have 1000 generated (output) tokens …` is in the raw session log and in `prompt.md` (sha `e020a3d8…`) |
| sealed and pruned | `work_dir_pruned=true`, no work dir on disk, sealed snapshot hashed |
| audit | **12/12** with runner v2's legacy-aware classification (the same byte-identical record, sha `450fabcc…`, scored 10/12 under v1's own signal-exit predicate — the two failures were exactly the stop checks) |
| out-of-band grading of the killed snapshot | public **2/2**, hidden **4/4** — a correct answer discarded (§5.1) |

**The kill path is established behaviourally, and the classifier was the broken part.**
Refusal observed live, all calls charged live at 0.2–2.0 s lag, SIGTERM sent, process
gone 0.23 s later with zero further calls, session log truncated mid-step — and spend
bounded exactly as predicted, `1131 = 1000 + 131`.

**Approved but unspent: the second probe.** Two sessions were approved for the
overshoot probe; one was spent. The second (`dev-bool/repair`, cap 1000) was **not**
run: with a SIGTERM-trapping launcher it would reproduce the same v1 classification
dead-end that the first probe hit, so it could not have added evidence, and the stop
rule ("if the kill did not happen, stop and report") forbade spending it. The session
remains unspent and is not needed now that the classifier is fixed.

---

## 8. UNRESOLVED — how many independent candidates a cell may start, and whether a per-candidate sub-allowance exists

**This is the one parameter this sheet does not fix. It is the user's choice, and it
must be fixed before the first M2 session.** The pilot could not resolve it: its
`independent` cells ran **one candidate per cell** because the approved budget bought
one session per cell, so each `independent` cell's `stop_reason` is `session-budget`,
not `envelope-exhausted` — its envelopes still had 2,408–4,250 generated tokens left.
Multi-candidate `independent` is demonstrated only against stand-in processes in the
dry run.

The options, with what each costs and buys (all figures below the line are **simulated**,
from the M1b replay at cap 5000 in `docs/audits/m2-budget-calibration-2026-09-19.md`;
none of them is a live measurement):

| option | candidate-start rule | consequences | session ceiling (13 tasks) |
| --- | --- | --- | --- |
| **A. Pool bound `M`, no sub-allowance** (recommended, `M = 5`, the runner's `DEFAULT_MAX_CANDIDATES`) | start while `remaining() > 0` **and** `started < M`; the envelope is the only spending bound | replay `independent`@5000 started 28 candidates over 14 *corpus* tasks (2.0/task on average; worst task 3, three tasks at 3 — *simulated*, and those denominators count the duplicate variant task twice), so `M = 5` is slack against the replay's maximum and the envelope, not the bookkeeping, decides. The bound exists so a pathological cell cannot spin up candidates forever | repair 13 + independent ≤ 65 = **≤ 78** |
| **B. Envelope only** (`M` effectively unlimited) | start while `remaining() > 0` | closest to "the envelope is the policy"; but the session count is unbounded a priori and the worst case is set by the smallest first call (~40 generated tokens in the M1b measurement), not by anything the design states | **unbounded** |
| **C. Per-candidate sub-allowance** (e.g. `cap/M` each) | a candidate may spend at most its sub-allowance; exceeding it ends that candidate | changes the treatment: a candidate can be stopped while the task envelope still has budget, which no replayed policy models. It also widens the live-versus-replay gap (§4), because the replay never applied a per-candidate cap | depends on `M`; ≤ 78 at `M = 5` |
| **D. `M = 3`** | as A with a tighter pool | exactly the replay's worst task (3 started, headline; 2 in the text pool — *simulated*), so it would bind on 3 of 14 replay cells and could bind more often live, where a candidate may be started without look-ahead; it stops being a pure bookkeeping bound | repair 13 + independent ≤ 39 = **≤ 52** |

**Recommendation: option A with `M = 5` and no per-candidate sub-allowance**, i.e.
`--max-candidates 5 --sessions-allowed 5`. It keeps the envelope as the only spending
bound (which is what the treatment claims), it matches the runner's declared default so
no new parameter is invented, and the replay's per-task candidate counts suggest it
will rarely bind. Consequences the user is accepting: up to 65 `independent` sessions
and a **78-session ceiling** for the whole comparison, and a pool bound that is a
bookkeeping limit rather than a modelled behaviour. If the user prefers a smaller
commitment, option D (`M = 3`, ≤ 52 sessions) is the next best and is a one-flag
change; option C should be rejected unless the user *wants* to change what `independent`
means.

*Resolved before the run (was an operational caveat).* `--cohort-id` was added to the
runner, defaulting to `pilot-5000` so no existing invocation or record changes; the M2
run passes `--cohort-id m2`, so M2 records carry `cohort_id: "m2"` and the participant's
`MYLANG_COHORT` is `m2`. This is the only change between the first v2 revision and the
frozen one (`f8b70c35…`).

---

## 9. Predeclared decision rule

**Sign convention.** Treatment = `independent`, baseline = `repair`; every contrast is
`independent − repair`, paired by case. The assignment only fixes the sign — a win for
one policy is a loss for the other.

**Estimands, per family and pooled.**

* `R_p = Σ_{c ∈ group} S(c,p) / Σ_{c ∈ group} A(c,p)` — generated tokens per accepted
  answer.
* `RV_p = Σ V(c,p) / Σ A(c,p)` — input volume per accepted answer.
* Primary contrast per group: **`ΔR = R_ind − R_rep`** (positive ⇒ `independent` costs
  more per accepted answer).
* Interval: **paired bootstrap by case** — 10,000 resamples of the group's case indices
  with replacement, seed `20260919`, both policies evaluated on the same drawn cases
  each time, percentile interval at 2.5 %/97.5 %. Families: `bool-int` (n=2),
  `checked-result` (n=5), `generic-requirement` (n=5), `variant-coverage` (**n=1** — one
  pair cannot form an interval, so it is descriptive only; see the composition rule
  below). Pooled = all 13 design cases.
* **Equivalence margin `δ = 1000` generated tokens per accepted answer**, predeclared
  as one fifth of the per-task cap: a difference smaller than a fifth of one task's
  budget per answer is treated as no material separation. This is a judgement fixed
  before the data, not estimated from it.

**The three outcomes, per group** (let `[lo, hi]` be the 95 % interval for `ΔR`):

| outcome | criterion |
| --- | --- |
| **No separation** | `lo ≥ −δ` and `hi ≤ +δ` — the whole interval lies inside the margin. **Materiality outranks significance:** an interval inside the margin gives `no separation` even if it excludes 0 |
| **A policy wins** | `hi < −δ` ⇒ **`independent` wins** (cheaper per accepted answer, the whole interval beyond the margin); or `lo > +δ` ⇒ **`repair` wins** |
| **Inconclusive** | every other interval (it contains a value inside the margin *and* is not wholly inside it — i.e. it crosses a margin boundary) |

Degenerate denominators, predeclared: if a policy accepts **zero** answers in a group,
its `R` is unbounded and it cannot win that group on the primary metric; if the other
policy accepts at least one, the outcome is a win for the other policy flagged
*denominator-degenerate*; if both accept zero, the group is **inconclusive** (nothing to
price).

**A group with fewer than two paired cases cannot separate anything.** `variant-coverage`
has one pair after the §3.1 correction, so it is reported **descriptively** — its point
estimate and raw numbers, no interval — and it is **excluded from the overall
composition**, which is stated wherever the overall state appears. (Before the
correction it held two pairs; they were the same task, so it never had two independent
cases to separate with.)

**Acceptance-cost clause.** If a policy wins a group on `ΔR` while its paired
acceptance difference is significantly negative, the group is still recorded as a
primary win **and** annotated "win on the primary metric, with an acceptance deficit" —
it is not by itself a licence to prefer that policy.

**Overall state, composed from the three paired family states** (predeclared,
conservative; `variant-coverage` is descriptive only and takes no part):

* every paired family `no separation` ⇒ overall **no separation**;
* exactly one policy wins at least one paired family, no paired family is a win for the
  other policy, and no paired family is inconclusive ⇒ **that policy wins**;
* anything else ⇒ **inconclusive** (this includes any paired family that is inconclusive
  alongside a win, and wins for both policies).

**Pooled view is secondary.** The pooled 13-case `ΔR` and `RV` are reported with the
same rule, and the pooled acceptance counts with it, but **the headline decision is the
family composition above**; the pooled number never overrides a family state.

**Acceptance contrasts (secondary).** Per family, the paired differences in hidden and
public acceptance are reported as discordant-pair counts with an exact two-sided
McNemar (binomial) p, plus the paired bootstrap interval on the difference of
proportions. No alpha adjustment across the families; these are predeclared
descriptive states in M1's sense, and "inconclusive" is a result, not a failure to
decide.

**Sensitivity analyses, predeclared and always reported:** (i) the same rule on the
public-acceptance denominator; (ii) the same rule on input volume per accepted answer;
(iii) the same rule **re-including `variant-b`** (the duplicate of §3.1), to show what
the corrected case list avoids — reported as a defect-sensitivity and never as the
design; (iv) the "correct at kill" table of §6. None of the four replaces the primary.

---

## 10. Analysis discipline (M1's rules, kept)

1. **One participant at a time**, strictly serial, guarded by the runner's lock and
   `/proc` scan; no parallel sessions.
2. **Missing or invalid observations stay visible.** An unmatched session log is
   MISSING with no invented spend (never zero); a grader that did not run is a grader
   incident; an attempt that produced no record is listed. Nothing is imputed.
3. **A retry is a new attempt with a reason, and attempt 1 is preserved.** A retry
   never overwrites and never replaces; the analysis reports which cells were retried
   and why. (M1b's precedent: one retry, kept.)
4. **`spent` is per-call ground truth.** Spend comes from the per-call usage lines and
   is re-derived from the raw session log independently of the runner at audit time;
   each usage is counted once per call and calls are deduplicated by
   `(session, call index)`. The log carries each call's usage twice — once under
   `data.usage` and again in the trailing stream chunk — so an unguarded sum
   double-counts.
5. **Every cell is audited.** `--audit` re-derives the frozen prompt sha, the envelope
   arithmetic, the per-call sums, the stop classification, the sealed snapshot hash,
   the public acceptance and the selection's hidden acceptance, and re-derives the
   mechanism-failure list under the rule of the runner named in the record (v1 records
   stay auditable, and stay attributed to v1).
6. **Frozen artifacts are pinned by digest.** §1's digests are the run's identity; a
   record whose `runner_sha256` is not the frozen one is not an M2 observation.
7. **Nothing is written under `experiments/diagnostic-feedback/` or
   `experiments/cascade/`**; all scratch lives under
   `experiments/diagnostic-feedback-m2/.tmp/`.

---

## 11. What this design does not establish

* **Not a treatment effect of feedback.** The arm is `text` only; the M1b suggestion
  arms are not part of M2.
* **Not a pacing effect of disclosure.** Both policies see the same budget sentence, so
  a difference between them is not attributable to being told the cap — but nothing here
  measures what being told costs or saves (the M1b trajectories were unbudgeted).
* **Not a variance estimate.** One observation per (case, policy); the interval is a
  paired bootstrap over the 13 design cases. Thirteen of the corpus's 14 case
  directories are distinct tasks, and `variant-coverage` contributes a single pair
  (descriptive only). Budget spend is not replicated within a cell.
* **Not evidence about harder or longer sessions.** These cases are small single-file
  repairs; sessions in comparable evidence ran 5–12 calls and 14–28 s.
* **Not a general claim about envelopes.** It is a claim about these 13 cases at this
  cap with this harness, this model and this launcher.

---

## 12. Reproduction

```sh
cd /home/epentland/ai/canopy/mylang
PYTHONDONTWRITEBYTECODE=1 python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --selftest    # 19/19
PYTHONDONTWRITEBYTECODE=1 python3 experiments/diagnostic-feedback-m2/enforcing_runner.py --dry-run     # 19/19
PYTHONDONTWRITEBYTECODE=1 python3 experiments/diagnostic-feedback-m2/enforcing_runner.py \
    --reclassify experiments/diagnostic-feedback-m2/cohorts/overshoot-1000/dev-checked/repair/record.json
PYTHONDONTWRITEBYTECODE=1 python3 experiments/diagnostic-feedback-m2/enforcing_runner.py \
    --audit experiments/diagnostic-feedback-m2/cohorts/overshoot-1000/dev-checked/repair/record.json   # 12/12
```

An M2 cell would be run with (subject to §8's unresolved choice):

```sh
PYTHONDONTWRITEBYTECODE=1 python3 experiments/diagnostic-feedback-m2/enforcing_runner.py \
    --case checked-a --policy repair --cap 5000 --cohort-id m2 \
    --evidence-root .../cohorts/m2 --work-root .../work/m2 \
    --max-candidates 5 --sessions-allowed 5 --session-budget <approved>
```

`--session-budget` is the cohort-wide ceiling and must be the approved number; the
runner refuses to overrun it, and a second participant is refused while one is running.

---

## 13. Correction log

| date | what changed | evidence | cells affected |
| --- | --- | --- | --- |
| 2026-09-19 | **Design case list 14 → 13; 28 → 26 task-cells.** `variant-b` dropped as a byte-identical duplicate of `variant-a`. Corpus on disk and its digest left untouched. Effective paired n = 13. | `cases/test/variant-{a,b}/`: `project/`, `public/`, `hidden/`, `request.md` identical; `case.json` differs only in `id`; identical rendered prompts (`191564e5…`). M1b's frozen corpus carried the same duplicate. | none — corrected before any M2 session |
| 2026-09-19 | **Runner revision `5548c555…` → `f8b70c35…`**: `--cohort-id` flag added (default `pilot-5000`). No change to charging, policies, selection, stop semantics or evidence layout; one dry-run check added for the cohort id. | `--help`; `--selftest` 19/19; `--dry-run` 19/19; the probe's reclassification re-derived with identical content apart from provenance | none — no live session ran on either revision |
| 2026-09-19 | **Stop classification**: `killed_by_harness` (binary, signal-exit) → tri-state `stop`; `graceful-after-request` is a success. | probe §7.3; `dsh`'s SIGTERM handler; `--reclassify` 5/5 and `--audit` 12/12 on the probe, 13/13 on each of the 8 pilot records | none — corrected before any M2 session |

Earlier reports are not rewritten: the pilot's §4 dev-independence claim and the M1b
readout's held-out wording carry their own dated corrections. Records stay attributed to
the runner sha that produced them (v1 `52018fe9…` for the pilot and the probe; v2
`5548c555…` for the probe's reclassification).
