# Elegance metrics

A place to test, on this repository's own corpus, the metric family the research
note proposes: score a design by *change amplification* and *compression* rather
than by what an agent session happened to cost.

The first experiment is done and its answer is negative — see
[findings-2026-09-19](findings-2026-09-19.md). Propagation cost does not predict
what a change cost, and at the arm level it ranks the control design best while
being no more stable than the arbitrary choices in how the graph is built.

## `propagation.py`

```sh
python3 experiments/elegance-metrics/propagation.py --architecture
python3 experiments/elegance-metrics/propagation.py --runs --json experiments/elegance-metrics/propagation.json
```

It builds a design structure matrix from `mylang index-project`, which resolves
every reference in a project in about 0.14 s:

- **nodes** are declarations a change can be made to and a consumer can depend
  on — functions, types, fields and union cases, 123 in the baseline reader;
- **edges** `A -> B` mean A depends on B, taken from the reference kinds that
  cross a declaration boundary (`call`, `uses_type`, `accepts`, `returns`,
  `contains_type`, and the three field kinds) plus a field/case-to-owning-type
  edge, so a change to a type reaches everyone who touches any of its parts;
- **propagation cost** is MacCormack's: the mean share of the other nodes that
  can reach a node by following dependency edges backwards, i.e. the fraction of
  the system one change can affect;
- **blast radius** of a recorded run is the same measure restricted to the
  declarations its diff touched, found by intersecting the diff's new-side line
  ranges with the post-change symbol spans.

The `--runs` mode reads every verified record under `experiments/cascade/runs/`,
including the chained ones, so the experiment that is already paid for becomes
the validation set: 72 changes, each with a measured token cost, a diff, and an
`api-diff` classification.

## Reproduce the numbers

`propagation.json` holds the architecture table, the per-run rows and both
correlation tables. Measured on 19 September 2026 against the cascade run set at
commit range ending `d5f28204`, with `deepseek-v4-flash` at effort `max`.
