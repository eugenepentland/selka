# RC adversarial review repros (2026-09-28)

Programs from the adversarial review of the RC ownership proofs and from lane
M. Run each under the GC (`--gc-runtime`), `--gc-stress`, the RC default,
`--rc-runtime=stats` (the `MYLANG_RC_COUNTS` line must balance) and
`--release`, and compare outputs.

- `fixed-*.my`: bugs fixed on `main` (each also has a `tests/lang` regression).
  They must keep matching the GC in every mode.
- `open-*.my`: still open; see "Correctness items" in
  `docs/audits/rc-future-performance-2026-09-28.md`.
  - `open-both-*`: language-level, both runtimes (collection arguments lent
    across later in-place changes; the `mut` collection form of the
    OWNERSHIP-MUT-RECORD-WRITE-2 window).
  - `open-alias-*`: two `mut` arguments naming one value break copies.
  - `open-gc-*`: collector-only (`--gc-stress` crashes, the scan-plan abort,
    a false iteration trap).
  - `open-laneJ-interval-anchor2-alias-uaf.my` is fixed by RC-INTERVAL-ANCHOR-4
    (kept under its original name).
