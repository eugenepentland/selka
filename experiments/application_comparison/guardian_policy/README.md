# Main-arm Zig policy

Both application baselines now put implementation under `src/`, the directory
Guardian scans. The root `main.zig` is a protected compile/test entry. This policy
uses strict mode, blocking build policy and disabled baseline freezing. No check
exemptions or threshold increases were added for these baselines.

`guardian_adapter.freeze(guardian_binary, zig_toolchain_directory)` builds the
trusted main-arm adapter. It pins the binary, compiler, this policy and the wrapper,
then executes Guardian all, Debug unit tests, ReleaseSafe compilation and the CLI.
Main-arm agent public checks and hidden grading require this exact command sequence
and the coordinator's wrapper/policy identities; a phase named `guardian` running
an arbitrary command is insufficient.

`guardian_runner.py` rejects modified `guardian.toml`/root entry, accepted-debt
metadata, participant Git metadata/attributes and Zig implementations outside
`src/`. It stages source into a fresh gate directory, discards participant Guardian
cache claims, and creates an empty Git base with all candidate files staged. The
gate therefore analyzes the whole candidate, including diff-backed checks.
This initial trial integration does not measure trusted cross-session Guardian
cache reuse; concurrent/cache trials need a separate coordinator-owned cache policy.

Both baselines pass all 88 Guardian checks, unit tests, compilation and 64 generated
behavioral cases through this isolated adapter. EDA has 17 report-only line-length
advisories. The six seeded mutation/repair variants still pass their separate
construction checks after refactoring. Guardian findings prompted maintainability
and coverage improvements; no application correctness bug was demonstrated.

These are construction checks, not scored sessions or independent review of the
complete study. The policy/tool receipts must still be frozen with the launch
cohort. Compile commands in standalone baseline READMEs are language-only commands;
the comparison's main arm must use the trusted adapter above.
