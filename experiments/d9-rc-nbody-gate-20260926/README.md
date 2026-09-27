# Failed combined gate receipts

The JSON identity, exact scripts and compressed raw logs describe immutable
`685e2631`. The gate ran under `flock ../.d9-closeout-gate.lock`; the scripts
verify the source commit before and after their commands. The main guest-driver
step and both RC sweeps fail because one test file cannot load. The other three
gate commands pass. Both RC JSON reports explicitly retain `dropped: 1` alongside
865 successful assertions; those totals do not establish a passing sweep.

See the [failure report](../../docs/audits/d9-rc-nbody-gate-2026-09-26.md).
