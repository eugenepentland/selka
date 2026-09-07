# Draft Python preparation fixture

`starter/` is the participant project. `solution/` is coordinator-only and must
never be copied into a participant workspace. Both use Python's standard
library and the local `helper.py` module. The contract is
`../../contracts/practice-v1.md`.

The starter differs from the solution in exactly three expressions: the helper
argument, the parser failure result, and the diagnostic identifier. Python's
unresolved name only fails when `d` executes; the other defects can be observed
without modifying the starter.

Run coordinator tests with:

```sh
python3 -m unittest discover -s experiments/application_comparison/practice/python -p 'test_*.py' -v
```

These fixtures are drafts pending independent review and calibration. Fixture
success is not evidence of participant performance.
