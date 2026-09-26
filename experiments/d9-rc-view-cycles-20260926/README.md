# Stored live-view cycle evidence

`held_cycle.my` is the previously accepted source that inserts a view into its
own dictionary. Its two assertions check that both paths still observe the
entry. Source SHA-256:
`7586434f76ef78264b1d7816125edd24cfd0ce992c37b61186276b183df08a4c`.

- `gc-before-admission.json` records the accepted `f6bea5d9` Debug compiler,
  its binary hash, the complete command, and successful QBE guest execution.
- `held-qbe-before-admission.json` preserves the collections agent's experimental
  H-token QBE execution record before the type restriction. It exits zero but
  reports four allocations, zero retirements, and one unreleased hold. The
  command names the earlier temporary copy of the identical source; its existing
  `source_sha256` member names the driver's dictionary-view fixture, not this
  cycle source. The cycle source hash above identifies this repro explicitly.
- `new-admission.json` records the new Debug compiler's located rejection and
  successful `--legacy-sharing` compatibility check of this same source.

To reproduce with a selected Debug compiler, run `mylang check held_cycle.my`.
The current default must report `E_LIVE_VIEW_CYCLE`; adding `--legacy-sharing`
must accept it. To reproduce the historical runtime evidence, use the compiler
recorded in the corresponding JSON with `scripts/build-slot.sh build`, the QBE
backend, a private guest cache, and `--run` (or execute its output binary).

The admission tests, including snapshot migration and deep iterative traversal,
are in `src/view_cycles_test.zig`; run them through the build slot with
`zig build test-units -Dtest-filter='live view cycle admission'`.
