# Checked list optimization oracles

The six registered `ce_lists_test` tests pass on the A09 continuation compiler
with the approved A07 safety and exact-slot dependencies. This is a focused test
result; the complete verification gate and final C1 qualification remain pending.
`results.json` pins compiler, test binary, production base and source hashes.

The structural helpers now check the source ownership contract, build the owned
ABI, verify Core IR and emit LLVM for every inspected module. They forbid retains
and uniqueness tests and require the emitted zero-RC boundary. Core `release`
is required direct destruction in this mode, not a memory reference count.
Whole-element replacement still asserts two old managed fields and three direct
cleanup calls; selected-child copying does not copy its containing table.

All four retained native fixtures run in unoptimized debug, release, verified
release, optimized debug and release without facts. Outputs and workload sizes
are unchanged. Tests preserve normal leak checks, field replacement, independent
snapshots, invalid/empty buffer ranges, the 100,000-byte growth case, exact bounds
traps and the two 1 MiB memory-budget traps. Fatal traps do not claim cleanup.
A06's ce_cow source is the owning commit `8c91c509147df46f512dc810c0fe8da3703059e0`;
the three removed whole-Runtime temporary copies are a separately measured source
migration, not a compiler-only speedup. No timing or RSS conclusion follows here.

The command compiles `core-test-binary -Dtest-filter=ce_lists_test`, then runs that
binary with exactly `--guardian-filter=ce_lists_test`, inside one shared build
lease. The coordinator's temporary build target avoids component provisioning;
`MYLANG_COMPONENT_DIR` explicitly selects staged Support5 components. This does
not qualify those legacy installed components as RC-free.

Preserved earlier failures are oracle/migration preparation evidence:

- The first run compiled six tests but used two narrower runtime filters; all six
  compiled tests ran, including four displayed as unnamed. No other cohort ran.
  It incorrectly forbade textual `release` and also caught an inline call that
  borrowed `xs` while passing `mut xs`. The source now evaluates the mutation into
  a local before borrowing the resulting list for printing.
- The second run caught a missing `mut` on that newly introduced local.
- The third run and single-test diagnostic used an incorrect expected trap line
  216. The original names store was line 215; two migration lines moved it to 217.
  `smalls` has three elements, so index 2 is valid; `names` has two and correctly
  traps at the second store. Both full debug/release LLVMs preserve ordered checks.
  The reduced equal-length control traps at its first store in both modes. No
  compiler defect was found, and no production fix was made for this diagnosis.

The final log reports all six tests passed. Archive files preserve these logs,
the diagnostic source, full/reduced LLVM, commands, output and hashes.
