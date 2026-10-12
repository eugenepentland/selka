# Current-format cache corruption fixture repair

Base `a084aa4bd46aeaf28b436512fd7ee2ccb90f1a46`. The full verification gate found
`MissingSemanticEntry` and `MissingSpecializationEntry` because the CLI tests
still searched `semantic-cache-v7` after the durable store moved to v9.

The coordinator-authored build option now exposes `semantic_store.format_version`
to the CLI test module. Both existing file-discovery helpers use that one value.
No compiler implementation, cache admission rule, or corruption assertion changes.
The semantic test still covers damaged, truncated, oversized and foreign-version
entries; the specialization test still covers damaged, truncated and foreign entries.

The registered `test-cli` command passed both named tests plus three unnamed blocks:
5 passed, 0 failed, 0 skipped. Exact command and source/compiler/test-binary hashes
are in `results.json`; `focused-01.log` retains the complete output. The wrapper
printed a failed-command transcript after the test PASS, although its enclosing
build exited zero; this is retained explicitly rather than suppressed.

This repairs the focused full-gate blockers. The complete verification gate must
still run on the coordinator's integrated revision. Scaling, performance policy,
default rollout and retirement work remain deferred under the revised endpoint.
