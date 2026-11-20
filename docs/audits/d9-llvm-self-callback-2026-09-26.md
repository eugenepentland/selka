# LLVM callback referring to its containing function — 2026-09-26

Passing a function to a callback from within its own body used to emit both its LLVM definition and an external declaration for the same symbol. LLVM rejected that module as an invalid redefinition. Global-address assembly now recognizes the unit's own function and relies on its definition. Other function addresses still receive their ABI-correct declarations.

The translator regression passes (12 tests including imports), and the retired-adapter golden corpus remains byte-identical (12 tests including imports). A terminating recursive callback carrying a two-word record builds with the Debug compiler under LLVM O3/full LTO and prints `217`; the counting runtime reports no outstanding allocations or edges. Fixture and compiler/binary hashes: `experiments/d9-llvm-self-callback-20260926/`. Whole-tree Guardian passes 88 checks. Full gate follows integration.
