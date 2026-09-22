# M1 pilot verdict (16 sessions, 4 dev cases × 4 arms × 1 repetition)

**Measurement: sound, after one repair.** Every attempt first graded hidden-NO
while public-OK. That was not sixteen agent failures: the hidden manifests carry
an `args` field this study invented, `scripts/verify.py` rejects unknown step
fields, and every hidden run therefore failed to start. Grading is coordinator-side
and the sealed snapshots are immutable, so the honest repair was to re-run the
grader over the snapshots (`regrade.py`) rather than to buy sixteen new sessions;
all sixteen then graded hidden-OK. The regression that would have caught it is now
in `tests/diagnostic_feedback/selftest.py` (the grader must accept a reference
repair and reject the faulty source), because the case preflight had validated the
oracle but not the path the runner actually grades through.

**Workload: uninformative for the primary outcome.** All 16 attempts reached
hidden acceptance, so the primary comparison is at the ceiling; only the secondary
metric varies (median failed checks on changed source 0, with a per-cell range of
0–6). Paired effects over 4 blocks are therefore noise:

| contrast | pairs | mean difference | 95% CI |
| --- | ---: | --- | --- |
| suggestion in text | 4 | 0.0 | [−0.75, 0.75] |
| suggestion in JSON | 4 | 1.75 | [0.0, 4.5] |
| format without suggestion | 4 | −0.25 | [−0.75, 0.0] |
| format with suggestion | 4 | 1.5 | [0.0, 3.75] |

Per the plan's own rule — revise an uninformative workload before freezing the
main manifest — the 112-cell `m1` cohort is frozen but **not launched**. The
revision to make first: cases whose repair spans two functions or a signature and
its call site, so acceptance itself can vary, plus a check that a case's public
examples do not already reveal every hidden input.

Everything else the pilot exercised is working: block-randomized schedule from the
manifest, per-attempt event logs with 7–18 invocations and 1–7 failures recorded
from the wrapper, sealed snapshots, independent grading with the frozen compiler,
and JSON/Markdown tables from one aggregation.
