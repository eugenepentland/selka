# Named executable laws

Write exported Boolean `test_` functions expressing ordinary application laws.
A JSON configuration maps each qualified function to integer argument domains:

```json
{"checks::test_roundtrip":{"seed":[0,1000],"count":[0,64]}}
```

Run `python3 scripts/laws.py main.my --laws laws.json --seed 17 --samples 20
--output report.json` (one shell line). Every sample uses the schema-pinned guest
test runner and a fresh VM. Reports retain the seed, snapshot identity, inputs,
actual outcomes and source locations. Failed assertions/traps receive bounded
integer reductions that stay inside the supplied domains and preserve the failure
category. Repeating a campaign on the same snapshot yields the same inputs.

Passing sampled cases is not a proof. Reductions are counterexample candidates,
not a guarantee of global minimality. This first generator covers bounded integer
inputs; custom host providers, aggregate generators and matched productivity
measurements remain separate experiments. Source or compiler changes invalidate
a campaign rather than mixing evidence across versions.
