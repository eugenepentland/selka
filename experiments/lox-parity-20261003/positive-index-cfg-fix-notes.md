# Positive-index join-entry proof correction

Independent review found that the positive-index certificate's final index-load
join was exempt from `isBranchTarget`, while `extraEntry` enumerated jumps and
variant switches but omitted `try_result.error_target`. The frontend normally
targets propagation blocks; no source-generated miscompile was demonstrated.
The omission nevertheless failed the advertised no-extra-interior-entry proof.

The correction uses shared `ownership_sources.branchTargets`, which includes
jump, conditional jump and Result propagation, plus the existing explicit switch
arms. Only the canonical normalizer's own conditional edge at `start + 3` can
enter its `start + 9` join. `normalizer` validates that exact opcode/target before
the exception is used. All other interior positions still use the ordinary
branch-target refusal. Checked fallback, receiver/COW/lifecycle protocols,
versioned-loop refusal, guest bytecode and runtime code remain unchanged.

The new synthetic proof regression tests forward and backward Result error
edges to the join, both jump kinds, and a switch whose later arm enters it.
Control cases retain the canonical edge and unrelated outside-join targets.
This exercises the proof component on artificial bytecode edges; it does not
claim a frontend source reproducer. The compiler SPEC now states the complete
edge set and exact canonical exception.

## Checks

All work took place in `codex-lox-parity-lowering-20261003`, after carrier commit
`da2bec38ea0bd9e7f5f4f523a81083a796fd6565`. Builds/tests use private cache,
output and TMPDIR paths and build-slot admission, excluding CPUs 2, 3, 10 and 11.
No performance workload ran and no frozen artifact was modified.

`scripts/build-slot.sh build zig build test-units
-Dtest-filter='positive index' -Dtest-filter='RC field inout'
-Dtest-filter='RC closed field' -Dtest-filter='GC closed field'
-Dtest-filter='GC lowering of generalized closed'
-Dtest-filter='native RC record field transfers'
--cache-dir .tmp-lox-lowering/zig-cache -p .tmp-lox-lowering/compiler -j2`
completed with process exit zero: **27/27 passed**, 15 named tests and 12 mandatory
blocks. This includes the new CFG refusal, unaccounted exact traps/extreme/empty
indexes, native snapshots/replacement under collector stress, and field-inout
owned/caller traps, arenas, budgets and owner/hold balancing.

`scripts/build-slot.sh gate
/home/epentland/ai/canopy/guardian-zig/zig-out/bin/guardian-check all . --full --gate`
completed with process exit zero and **88/88 checks passed**. Build-triggered
Guardian also passed its diff-scoped checks. The committed
`positive-index-cfg-fix-checks.json` records exact commands, logs, hashes and
author-observed process exit status. The test reporter's misleading
`failed command` footer is retained in the log despite PASS and process exit
zero; it is not counted as a failure.

The earlier full qualification of the positive/carrier compiler remains in
`field-inout-notes.md`: final 2,479 root tests plus 515 QBE/driver/host tests.
This correction reruns the targeted proof/lifecycle suite and whole-tree
Guardian, not that complete broad suite.

## Artifact replay

A separate ReleaseFast combined compiler build passed with process exit zero:
`scripts/build-slot.sh build zig build -Doptimize=ReleaseFast -Dcompiler-only
--cache-dir .tmp-lox-lowering/zig-cache-cfg-fix-release
-p .tmp-lox-lowering/cfg-fix-compiler-release -j2`. The immutable copy is
`.tmp-lox-lowering/cfg-fix-release/bin/mylang`, SHA256
`d14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040`.
Its adjacent QBE retains the hash below. The original positive-only compiler
`da94c579e03ffaab2e9d43a6d9119b529bbb01dab5085e7a3986a6ecd98912c6` and combined
compiler `9007d0532fe0ed8e0a17568c2e7e796023ddd59e76137efa0181fefca3685288` stay
immutable with adjacent QBE
`99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63`.

`positive-index-cfg-fix-replay.py` rebuilt the exact qualified final-sweep source
with that combined fixed compiler, preserving all flags from the root's
`carrier-final-sweep-build.json`: LLVM optimization 3/full LTO/RC/keep-symbols;
QBE/RC/keep-symbols. Every build enters build-slot, with separate caches and
outputs in `.tmp-lox-lowering/cfg-fix-guests`. Both process statuses are zero.
The post-verified `positive-index-cfg-fix-guest-replay.json` records all 37
source/metadata hashes before/after and verifies compiler, QBE, control receipt
and old binary identities. Both guests are **byte-identical** to the parent’s
carrier-final-sweep and measured final-sweep binaries:

* LLVM: `29a48f65df32df53d80a51a70e4d072d8c85eb77953606a2bbbc71b4ba892764`.
* QBE: `6217e8fb5308702efcbdfdf2128ffd98cda8bafafc75e183d9130c0b1b402300`.

No additional wall run is needed for these selected guest artifacts, and the
previous measured binaries remain untouched. This does not establish a general
compiler performance claim or Rust/Go parity.

The independent lookup reviewer checked the correction and regression and
found no other current explicit guest PC-edge omission. Parent task owns the
consolidated Guardian feedback entry, performance selection and parity claims.
