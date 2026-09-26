# Empty RC frame entry experiment — deferred

The candidate initializes only valid clear guard pointers for empty operands,
work entries and plain locals. Full ownership metadata is published before a
guard becomes live. Owning locals keep their complete entry initialization.
The patch is preserved here and is **not applied to production source**.

Against frozen `a49441c1`, a private binary-tree fixture changes only max_depth
16 to 12. Both compilers are Debug; LLVM guests use O3/full LTO. Every result
matches the independently computed tree counts. Three interleaved CPU-2 retired
instruction samples give after/before medians 1.000597 on QBE and 1.000578 on
LLVM, with roughly 1–2% variation within some groups. This does not establish an
instruction improvement, so the candidate is deferred while larger measured
ownership costs are addressed. This is not D9 corpus acceptance.

The new IL regression and existing frame test selection each passed 12 tests
including imports. Five actual RC guest files passed uncached on both backends:
owned values 9, contract results 3, call lifetimes 3, dictionary views 6 and
temporary lifetimes 7 per backend. Whole-tree Guardian passed 88 checks.
Compiler/binary hashes, source, commands, all samples and guest verdicts are
retained alongside the candidate. No full gate is claimed for this experiment.
