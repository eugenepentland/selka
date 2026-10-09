# Named executable laws

Status: an experiment, not part of selka. The law runner is a Python script,
`experiments/guest-laws/laws.py` (with its helper `test_project.py` and its own
check `test_laws.py` beside it); the compiler has no laws command, and nothing
in building or using selka runs it. Until 2026-09-24 it lived at
`scripts/laws.py` and was listed as a tooling feature. Its check had been
failing: `selka test` runs only exported (`public`) `test_` functions and the
check's fixture law was not public, so every sample stopped with
`UnknownTestCase`. The fixture now declares its law public and the check passes. To try one law case without
Python, `selka test ENTRY --cases FILE` runs it natively with the arguments and
expected value you give it ([guest tests](../tooling/guest-tests.md)).

Write exported Boolean `test_` functions expressing ordinary application laws.
A JSON configuration maps each qualified function to integer argument domains:

```json
{"checks::test_roundtrip":{"seed":[0,1000],"count":[0,64]}}
```

Laws must be `public`, since `selka test` runs only public `test_` functions.
Run the experiment from a checkout of this repository, with Python 3:

```console
$ cat laws.json
{"main::test_sum_is_commutative": {"left": [0, 1000], "right": [0, 1000]}}
$ python3 experiments/guest-laws/laws.py app/main.selka --compiler zig-out/bin/selka \
    --laws laws.json --seed 17 --samples 20 --output report.json
{"passed": true, "cases": 20, "output": "report.json"}
$ python3 experiments/guest-laws/test_laws.py --compiler zig-out/bin/selka
guest laws: repeatable sampled failures, bounded reduction, repaired law pass
```

Every sample runs through `selka test --cases` as a fresh native process.
Reports retain the seed, snapshot identity, inputs, actual outcomes and source
locations. Failed assertions/traps receive bounded
integer reductions that stay inside the supplied domains and preserve the failure
category. Repeating a campaign on the same snapshot yields the same inputs.

Passing sampled cases is not a proof. Reductions are counterexample candidates,
not a guarantee of global minimality. This first generator covers bounded integer
inputs; custom host providers, aggregate generators and matched productivity
measurements remain separate experiments. Source or compiler changes invalidate
a campaign rather than mixing evidence across versions.
