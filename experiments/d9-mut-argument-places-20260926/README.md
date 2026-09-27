# Indexed mutable argument place evidence

See `docs/audits/d9-mut-argument-places-2026-09-26.md` for the specification,
implementation boundary, exact sharing-history trace and validation limits.

`run.py --compiler PATH --output receipt.json` records the original printing
reproducer, a standalone driver for the language regressions, and two arena trap
probes on actual QBE/LLVM, GC stress/RC counting. It checks located trap identity
and balanced owners, holds and heap retirement. `--baseline` runs only the
original printing source and checks the preserved old outputs.

`history.py --compiler PATH --output receipt.json` records the separate live-view
history observation and its ordinary shallow-copy oracle. It deliberately does
not declare ABI2 equality acceptable. The corrected checker history expectation depends on the cohesive ABI3
implementation before the integration gate.

Compressed receipts preserve all commands, compiler/source identities and output.
The standalone driver is generated from the 15-test language fixture by `run.py`.

`paired-abi3-{oracles,fixture,direct}.json.gz` records the final private ABI3
pairing: both history probes, the corrected permanent assertion, all 15 standalone
assertions and both trap paths pass in every GC/RC and actual backend combination.
The compiler binary identity and exact counter totals appear in the audit supplement.
