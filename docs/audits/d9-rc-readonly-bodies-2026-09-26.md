# Canonical scalar-result readers without RC traffic

The compiler now proves a closed class of complete function bodies that can
borrow their managed values from read-only caller parameters. The canonical ABI
and native frame admission remain unchanged. These bodies omit the RC ownership
journal and temporary acquisitions because they cannot create, mutate, publish
or return an owning value. Recursive calls may target only the same function;
unknown callees and callbacks decline the optimization. The proof is one linear
instruction scan, with no recursive certificate query or transitive dependency.

`rc_readonly_body.zig` checks the physical return and every local for unique
obligations, rejects mutable parameters and managed constructors, and accepts
only explicitly listed scalar operations, private inline constructors, borrowed
projections, control flow and self calls. A refused body retains ordinary RC
lowering. Function bytecode and physical layout already participate in the native
fragment key; this proof has no external callee dependency. GC lowering is unchanged.

Native execution exposed a preexisting raw borrowed-local store defect: boolean
values used packed byte stores although local loads read a full machine word.
The hook now writes every scalar local as a complete word. The first QBE failure
is preserved in the evidence; the corrected binary passes both backends.

Validation used Debug compilers and actual QBE and LLVM guests, with the LLVM
selector followed only by `--llvm-opt 3 --lto` (no overriding `--qbe` option):

- Focused whole-body proof tests: 13/13, including mutation, allocation, callback
  and owning-return refusals and preservation of native frame failure checks.
- Existing borrowed-entry and certificate-cache tests: 21/21.
- Guardian whole-tree checks: 88/88.
- The new two-case guest passes both ReleaseFast backends. A separate Debug run
  per backend with `--max-frames=16` retains the expected recursive
  `R_FRAME_LIMIT` and releases all live caller-owned allocations.
- Eight paired guest executions (success and frame refusal, before and after,
  two backends) pass. Successful runs reduce owner acquisitions 3,846 to 399 and
  releases 3,979 to 532; allocations and retirements remain 133 each. The fixed
  QBE and LLVM traffic records are identical.
- A depth-12 diagnostic derived only by changing `max_depth` in the parity
  binary-tree source passes exact output comparison on both backends. Owner
  acquisitions fall 3,992,307 to 1,996,163 and releases 4,661,367 to 2,665,223;
  allocations and retirements remain 669,060 each, with zero clones or holds.

The preceding frozen compiler is `1962f4e9019fd75d2f4248a12bbfbe928d4d25ef7446c5a1e495bc50bf34a88e`;
the corrected compiler identity and every guest binary hash, command, result and
counter record are in [compressed evidence](evidence/d9-rc-readonly-bodies.json.gz).
The preceding compiler predates the independently validated receiver-anchor
cleanup correction; these diagnostics do not isolate that unrelated change.
No formal RC performance acceptance is claimed. The root integration owns the
full combined gate and the required matched corpus.
