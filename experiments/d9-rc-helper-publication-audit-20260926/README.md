# Read-only helper publication audit

This is a partial, explicit evidence snapshot for the
[helper audit](../../docs/audits/d9-rc-helper-publication-audit-2026-09-26.md).
`snapshot.json` gives captured versus planned rows. A missing row is pending,
not a pass. Each group has the exact source, runner and compressed raw result.
The raw result records every command, compiler SHA-256, source commit, source
text, status, stdout and stderr. RC records include actual counted runtime output.
The checker-aborted pinned dictionary source is a frontend failure, not a guest
abort or runtime semantic result.

The main compiler is the Debug build from `ce8e5d2f`; precompact uses the
identical-tree corrected source commit `c3166634`. Actual LLVM commands use
`--release` without any QBE override. Run the drivers from the repository root;
their private paths intentionally retain the frozen compiler/cache identities.
The archived append bytecode and two emitted manifests prove the fresh literal
has no semantic VALUE_COPY between construction and append.

The first pinned-list draft only read its `mut` parameter and was rejected by
`E_MUTATION_MARKER` before execution. The archived source writes the same scalar
value, keeping the receiver scope active while preserving the expected contents.
No rejected draft is counted as a runtime outcome.
