# Initial RC journal templates — deferred

This candidate replaces per-entry initial type/flag stores and the journal's
zeroing with a copy from an immutable content-addressed C array. Dynamic local,
operand, pending and internal addresses/guard pointers are still patched before
frame entry. Later publications use unchanged type/role updates. No runtime ABI,
State field or ownership contract changes. All lowered locals and analyzed
operand capacity contribute to the template identity. The candidate and its
focused tests are preserved in `candidate.patch`; **production source is restored**.

The frozen before tree is `c2f71292` (production source from `d57fef03` plus the
journal review document). Both compilers are Debug; the private diagnostic only
changes binary_trees max_depth from 16 to 12. Both actual guest backends use
ReleaseFast; LLVM additionally uses O3/full LTO and no `--qbe` override. All eight
uncounted/counted before/after binaries match the independently calculated output.
All four counted runs have identical counters: 669,060 allocations/retirements,
19 owner acquires, 669,079 owner releases, no holds/clones, 33 uniqueness checks.

Three interleaved CPU-3 retired-instruction samples give after/before medians
**0.997009 QBE / 1.023917 LLVM**. QBE's small reduction does not offset the lack of
an LLVM win. LLVM samples also vary by about 2.4% within each group, so the median
increase is not a claim of a stable 2.4% regression. This bounded experiment
establishes no useful cross-backend improvement and is deferred. The QBE
text/data/BSS total changes 192,064→192,072 bytes; LLVM changes
200,742→200,730 bytes. This is not D9 corpus acceptance.

Two focused template tests pass (13 tests including unconditional harness
blocks). The two actual QBE `rc_journal_types` assertions pass uncached, including
ordinary/held role reuse and arena escape. Debug install passes 12/12 and
Guardian all 88 checks. No broader guest selection or full gate was run for the
rejected candidate. `results.json.gz` contains exact compiler/binary hashes,
commands, full patch, counters, all samples and outputs. The preserved script
uses the isolated `.tmp/journal-template/{before,after}` installs; rebuilding a
candidate must use its archived patch on the stated before tree.
