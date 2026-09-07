# Coordinator reference solutions

The four feature references are separate standard-library-only Python applications.
Two independent builders read the relevant contract, task brief and original Python
baseline, without reading grading code, generated cases or other language baselines.
They did not modify the original baselines. Each reference has its own tests.

The coordinator then ran every public and private draft-pack check through the
namespace executor with a public construction seed that must never be used for
scoring. All passed:

| Task | Builder tests | Isolated pack checks |
| --- | ---: | ---: |
| Planner priority | 5 | 9 |
| Planner cycle groups | 6 | 10 |
| EDA pin roles | 7 | 9 |
| EDA rotation | 5 | 9 |

Receipts are recorded in
[`planner-feature-reference-validation.json`](../evidence/planner-feature-reference-validation.json)
and [`eda-feature-reference-validation.json`](../evidence/eda-feature-reference-validation.json).
The summaries identify captured sources, pack contents, adapters and complete run
plans. Their raw-record paths are temporary local construction directories, not
durable cohort storage. Reproduce the checks before a cohort freeze; keep actual
scoring evidence in durable private storage.

`reference_validation.py` captures the reference source, executes all pack cases,
retains raw results and reports mismatches without stopping subsequent cases. Run:

```sh
python3 -m experiments.application_comparison.reference_validation \
  --pack /private/planner-priority-pack \
  --source experiments/application_comparison/references/planner-priority \
  --directory /private/planner-priority-validation
```

These references cross-check the expected behavior. They do not prove full contract
coverage, task difficulty in `.my` or Zig, or faster development in any language.
The two repair tasks use the original correct implementations as references;
their seeded mutations and exact repairs have separate isolated checks.

Never include this directory, expected hidden answers or reference tests in a
participant source snapshot or tool mount. These are coordinator construction
artifacts, not libraries available to an application or scored participant attempts.
