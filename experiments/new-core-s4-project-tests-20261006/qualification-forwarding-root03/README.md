Root reproduces the conformance forwarding failure before changing the helper;
the exact original source, real parser AST audit and four controlled combinations
are retained in `qualification-forwarding-root02`. The repaired adapter uses
`arguments(argv=None)` in `main`, disables abbreviation, and preserves the exact
historical `--core` tokens and separate compiler source revision in both option
orders and separate/equals forms. Project/fuzz wrappers already declare exact
`--core` and do not need this repair. The historical harness and Capture stay
unchanged.

This fresh replay passes all 12 pure tests in 1.811 seconds, retaining raw
outputs, command/status/wall, full five-helper hashes, source/corpus validation
and bounded Python orphan/timeout controls. No compiler/native/fuzz execution
or performance qualification occurs. Actual final compiler package gates
remain pending.
