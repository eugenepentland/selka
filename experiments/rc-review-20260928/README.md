# RC adversarial review repros (2026-09-28)

Programs from the adversarial review of the RC ownership proofs and from lane
M. Run each under the GC (`--gc-runtime`), `--gc-stress`, the RC default,
`--rc-runtime=stats` (the `MYLANG_RC_COUNTS` line must balance) and
`--release`, and compare outputs.

- `fixed-*.my`: bugs fixed on `main` (each also has a `tests/lang` regression).
  They must keep matching the GC in every mode.
  - `fixed-both-*`: language-level, both runtimes. A read-only operand now
    gets a snapshot when a later operand of the same expression writes its
    root (VALUE-SEMANTICS-14; `lst(xs, xs.pop())` is 303). A borrow read by a
    lent argument now sees the call's `mut` collection writes
    (OWNERSHIP-MUT-RECORD-WRITE-3; the window case prints 1 under both
    runtimes). Regressions: `tests/lang/operand_snapshots.my`,
    `tests/lang/mut_collection_call_window.my`.
- `rejected-*.my`: programs that pass two overlapping `mut` arguments to one
  call (`f(mut b, mut b)`, `f(mut a, mut a[0])`, `f(mut r, mut r.rows)`). They
  are now `E_MUTATION_OVERLAP` at compile time (MUT-EXCLUSIVE-1), so none of
  them runs. The `rejected-rc-alias-*` and `rejected-laneJ-*` programs once
  exercised the RC-INTERVAL-ANCHOR-3/4 alias refusals, which stay in the
  compiler as defense in depth.
- `open-gc-*.my`: still open, collector only (`--gc-stress` crashes, the
  scan-plan abort, a false iteration trap); see "Correctness items" in
  `docs/audits/rc-future-performance-2026-09-28.md`.
