# Independent checkpoint reconstruction review

The final `prepare.py` and observed fresh reconstruction pass with the limits
in `review.json`. Independent in-memory patch replay maps measured source80
to source84 exactly, and canonical replay matches all 37 files. The helper
reconstructs source84, reverses the new patch with zero fuzz to source80, and
rejects source drift or extra files. It uses a new private workspace, argv
commands and private caches rather than overwriting frozen measurements.

All seven final preparation commands completed successfully. Compiler, QBE,
runtime and build receipt identities match the four native RC guests; LLVM
uses O3/full LTO and QBE uses its recorded default build mode. The four fresh
mylang guests and fresh Rust guest match measured bytes. Fresh Go has a
distinct identity after `-buildvcs=false`; it is behavior-qualified and does
not replace the frozen Go binary used for timing. All 106 archived benchmark,
Rust and Go files match the measured references; 21 unused Zig files are
outside this helper's reference archive scope.

The final CPU0 smoke phase covers six arms, all 13 scripts on both engines
and one smoke-size round: **156 unique samples**. Status, output hash, exact
ASCII statistics and source identities pass. These are behavior checks, not
new timing results. The initial missing-Cargo failure remains recorded with
exit 127 and no accepted complete manifest. Its successful partial commands
do not turn it into a complete pass.

An intermediate relative `RUSTC` override could record one executable while
Cargo resolved another from its build directory. The final helper sets the
absolute recorded executable in Cargo's environment and records effective
TMPDIR, GOTMPDIR, PATH, RUSTC and reference-specific overrides. Cargo/rustc
shim hashes and actual sysroot executable hashes are captured separately.
This concern is resolved in final helper SHA256
`16c6698691054b6122cf82fae8e6d45cdfb78d9bb0d34d186cf6395b9b57ccc1`.

Complete standard-library/toolchain archives and exhaustive ambient build
flags are not claimed. Reference tool versions and hashes are post-build
observations; the observed source and guest identities, recorded commands
and smoke behavior define this qualification. The producer checks full raw
stdout and retains hashes; all retained statistics lines are exact ASCII.
This read-only review executed no builds, tests, reference tools, guests or
performance commands and made no root changes.

The receipt SHA256 is
`7f5f88c743fd543bb25a4ebc50b3b62af72064a478b261a0731e546db3b5f7d9`.
To reproduce the evidence audit while leaving earlier receipts unchanged:

```bash
python3 -B experiments/lox-callee-table-checkpoint-independent-review-20261003/audit.py \
  --root /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003 \
  --out .tmp-lox-callee-table-checkpoint-review-20261003/new-review.json
```

Root accepted checkpoint commit `44cd4307` is archived at
`/home/epentland/ai/canopy/evidence/lox-parity-20261003/callee-table`.
The archive `MANIFEST.sha256` file hashes to
`94d85a11474d68c281d6b0e9010046ed5ebc8dd7ded019d43761b5d7c63b7272`.
This later experiment-only review references the sealed archive without
mutating it. Rust/Go parity remains unfulfilled; this review does not claim
completion of the broader goal.
