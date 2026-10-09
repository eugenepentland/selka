# Ported guest tests

Program-running tests ported from the retired QBE-era Zig tests (lane S5-D1).
They live outside `tests/lang` because the S5 conformance sweep compares every
`tests/lang` file with the frozen old-core references
(`experiments/new-core-s5-20261007/references/conformance-v1.json`), which
predate these tests. `zig build test-lang` runs this directory beside
`tests/lang` and `tests/value_semantics`, at debug and at release with the leak
and fact checks.
