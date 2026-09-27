# Direct completed-constructor publication

Private n12 instruction evidence, not WP-4 corpus acceptance. See the audit
report for ownership proof, exclusions and before/after measurements.

The scripts were copied from the isolated worktree scratch directory. The
measurement scripts expect installed Debug compilers named
`install-publish-before/bin/mylang` and `install-publish/bin/mylang`, built
through `scripts/build-slot.sh build` with separate cache and TMPDIR. Original
absolute build/measurement commands and compiler/binary hashes are in
`measure-publish.json`. QBE and LLVM O3/full-LTO guest modes are verified from
their manifests; no later `--qbe` switch overrides LLVM.

The trap driver includes all optional cases, including arena escape. It checks
exact success/assert-trap exits and balanced heap owner/hold counters, including
a 33-frame recursive aggregate trap. Guest source and compiler hashes are
recorded in its JSON reports.
