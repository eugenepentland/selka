# Preliminary combined ABI5 module composition review

Frozen compiler c76f443347eec255873c1fe16a5c17ed8c92da0896b49251c603f82c8d7bfc0a,
built from e789a32d42bd2f635e9e9f1e5da715f397b24517. Compiler/vendor/build inputs
are byte-identical to review worktree27b170076d1a21286857f7fc00583bded555497d.

Strict29 corpus: 29/29 equal,43 rows,62 modules,664 units,62 interfaces and
29 byte-identical executables; zero reference failures, fallback or link-time
guest function compilation. Lox uses an owned28-file snapshot extracted from the
verified durable B2 archive:18 modules,400 units, identical linked/whole bytes.
This byte corpus does not execute guests.

Runtime matrix rc/gc/stats/sites: each2/2 equal,9 modules,80 module units versus
79 whole units (one shared specialization),9 interfaces and2 byte-identical
executables; zero reference failures or link-time guest function compilation.
Both sides actually execute: module_compile main returns1 by its fixture
contract, module_rc returns0, with matching stdout/stderr.

All five commands exited0. Every heavy call used build-slot admission and
2workers; suite calls were sequential. No timing CPU claim, root worktree writes,
source edits or Guardian invocation. Frozen compiler SHA was rechecked at end.
No composition mismatch found within these preliminary checks. Final source
requires its own matrix after corrected release/isel composition and its complete
gate/fuzz/performance checks; these receipts make no final acceptance claim.
