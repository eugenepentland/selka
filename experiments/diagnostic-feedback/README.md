# Diagnostic feedback

Experiment 1 of the review in
[research-testing-review-2026-09-19](../../docs/audits/research-testing-review-2026-09-19.md):
does the checker's feedback change how fast and how reliably a fresh agent
repairs a seeded fault? The result is in
[findings-2026-09-19](findings-2026-09-19.md).

## Layout

| path | what it is |
| --- | --- |
| `faults/generate.py` | materialises the corpus: 8 diagnostic families × `dev`/`test` variants, each a tiny project that fails exactly one way, with a pinned expected stdout |
| `faults/{dev,test}/<fault>/` | the fault: `project/`, `request.md`, `hidden/verify.json`, `hidden/fault.json` |
| `conditions.py` | the four treatments as a `bin/mylang` wrapper — text, structured JSON, structured + `suggested_fix`, and the one-shot control (text output, single-attempt prompt) |
| `run.py` | one session: working copy, wrapper, launch, hidden verification, repair rounds and diagnostics from the log |
| `sweep.py` | the study: every cell, shuffled with a fixed seed, a few at a time |
| `score.py` | the tables; `--include-dev` adds the faults the fix wording was authored on |
| `runs/` | per-session records and transcripts |
| `sweep.log` | progress, with the cell order a run actually took |

## Reproduce

```sh
python3 experiments/diagnostic-feedback/faults/generate.py --check     # every fault produces its code
python3 experiments/diagnostic-feedback/run.py --condition fix --fault bool-int --split test --n 1
python3 experiments/diagnostic-feedback/sweep.py --runs 3 --jobs 3 --seed 20260919
python3 experiments/diagnostic-feedback/score.py
```

The corpus is the unit of reuse: a new family is one entry in `FAULTS` with a
`dev` and a `test` variant, and `--check` refuses one that does not fail exactly
as declared. `--faults a,b` reruns a subset after a corpus fix, which is what the
12 repaired cells in the findings were.
