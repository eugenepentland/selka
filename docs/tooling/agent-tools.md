# Agent-facing inspection

The bounded instruction trace and the recorded host transcript that used to sit
alongside a guest run were interpreter facilities and were removed with it on
2026-09-14. A natively built guest reports a source-mapped call stack at its trap
instead; see [runtime budgets](runtime-budgets.md#guest-memory-ceilings) for what
a trap prints.

## Named executable laws

Sampled laws are an experiment, not part of selka. The law runner, which draws
seeded inputs from integer domains for an exported `test_` function returning
`bool`, reduces a failing sample within its domains and writes a `guest-laws-v1`
report, is a Python script under `experiments/guest-laws/`; the compiler has no
laws command, and nothing in building or using selka runs it. Its design record,
[named executable laws](../experiments/guest-laws.md), says how to run it.

What selka itself offers is one law case at a time: `selka test ENTRY --cases
FILE` runs an exported `test_` function natively with the arguments and the
expected value the cases file gives it ([guest tests](guest-tests.md#selka-test)).

```console
$ cat cases.json
{"main::test_sum_is_commutative": {"arguments": {"left": "3", "right": "4"}, "expected": true}}
$ selka test app/main.selka --cases cases.json
passed main::test_sum_is_commutative
1 passed, 0 cached, 0 failed, 0 skipped
```
