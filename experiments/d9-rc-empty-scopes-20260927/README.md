# Receiver-scope scratch omission

`summary.json`, `full.json.gz` and `reduced.json.gz` preserve source/compiler and
binary identities, all commands, output checks, three-run instruction samples
and counted before/after runs. `advance.ssa.gz` and `after-il.json.gz` retain the
generated code. `guests.json.gz`, `standalone.json.gz` and the unit/Guardian logs
are the correctness receipts; executed scripts are archived alongside them.

From the repository root, use immutable Debug compiler prefixes:

```sh
python3 experiments/d9-rc-empty-scopes-20260927/compare.py \
  /path/to/before/bin/mylang /path/to/after/bin/mylang \
  /path/to/new-output --steps 5000000 --cpu 10
```

The archived full driver reused the previous slice's frozen before binaries;
the portable command rebuilds both arms from the same unchanged benchmark.
Use `--steps 10000` for the reduced control. No performance threshold is relaxed.
