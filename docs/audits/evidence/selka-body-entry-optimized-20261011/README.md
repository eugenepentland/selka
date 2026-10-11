# Optimized B7 full gate

The full `zig build test fmt-check --summary all` run at source
`653ae191dbd16505e2937402ce0e7e7c1781220d` exits 0: all 139 build steps pass.
The final Zig summary records 816/6458 tests passed and 5642 shard-filter skips;
the selected Guardian verdicts total 816 passes, zero failures and zero skips.
This supersedes the separately retained 600-second matrix timeout attempt.

Body qualification passes 286 pure tests in each mode, 443 normal/edit workflows
with 1772 comparisons, and 443 release workflows with 886 comparisons. Each
workflow matrix includes 92 forged replies, 30 warm-deployment checks and four
live-session checks. Actual library admission passes 213 operations and four
join forgeries. Each normal/release entry lane passes 349 operations, 35 captures
and 15 resource attacks. All seven component binaries are byte-identical between
the two source generations within each lane.

The frozen Debug host is
`ee9bc995df50cac1d29e6c3c8cfd16807862f0ce95e601e7dec57eeb4e62f0b5`;
the schema7 body artifact is
`337e7d27b241c8699d8d754adae801a7c230be1aacb2edb54cc042e923a60a5a`.
`summary.json` binds the full seven-package inventory and exact source commit.
The archive retains all 195 component source files and 194 exact exchange paths
using 51 compressed payloads. All reconstructed frames were verified against
their recorded size and SHA256; `retained-paths.json` provides the mappings.

These are component-source generations on the declared body profile. The
fixture inventory still includes 17 explicit unsupported cases. Complete
language body checking, native catalog and later semantic-pass replacement,
Core/LLVM backend and driver replacement, whole-compiler bootstrap and the
1.5× performance target remain unfinished. Performance results are retained
separately and do not pass that target.
