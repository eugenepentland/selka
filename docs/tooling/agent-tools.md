# Agent-facing inspection

Named laws state a property of an application and are checked like ordinary
tests, so a program can be probed over a range of inputs rather than at one
point. The design record is [named executable laws](../experiments/guest-laws.md).

The bounded instruction trace and the recorded host transcript that used to sit
alongside it were interpreter facilities and were removed with it on 2026-09-14.
A natively built guest reports a source-mapped call stack at its trap instead;
see [runtime budgets](runtime-budgets.md#guest-memory-ceilings) for what a trap
prints.

## Named executable laws

A law is an exported `test_` function returning `bool` that states a property of
the application, and a JSON configuration gives each qualified law an integer
domain per parameter. `scripts/laws.py` samples those domains with an explicit
seed, runs every sample through the schema-pinned guest test runner as a fresh
native process, and writes a `guest-laws-v1` report retaining the seed, the
source snapshot identity, the inputs, the outcomes and the source locations. A failing sample is
reduced within its supplied domains while preserving the failure category, and a
repeated campaign on the same snapshot draws the same inputs. Passing samples are
evidence, not a proof; reductions are counterexample candidates, not guaranteed
minimal ones. This generator covers bounded integer inputs only, and a source or
compiler change invalidates a campaign rather than mixing evidence across
versions. `scripts/laws.py` is a Python prototype that drives `mylang test
--cases` from outside the compiler and needs Python 3 and a checkout of this
repository; a single law case needs neither, since `mylang test --cases FILE`
runs it natively ([guest tests](guest-tests.md)).

```console
$ cat laws.json
{"main::test_sum_is_commutative": {"left": [0, 1000], "right": [0, 1000]}}
$ python3 scripts/laws.py app/main.my --compiler zig-out/bin/mylang \
    --laws laws.json --seed 17 --samples 20 --output report.json
{"passed": true, "cases": 20, "output": "report.json"}
```
