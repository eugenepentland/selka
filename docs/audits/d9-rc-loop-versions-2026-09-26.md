# RC loops with stable physical storage

The existing guarded loop lowering is available in RC only inside an interval
accepted by the physical uniqueness proof. Entry detachment precedes guard
storage reads. Remaining COW checks reject the version, and the existing emitted
allocation-call audit still rejects any helper outside its established pure set.
No RC release helper has been declared pure. A failed range guard executes the
original loop; step-counted builds retain their single original copy.

The remaining empty cleanup branches prevented otherwise inert loops from
passing that emitted-call audit. Cleanup now omits a receiver local only when
it has one proved inert definition and no possible O/H publisher: formal or
address-borrowed slots, held-role types, pattern bindings, reference exposure,
additional stores, local/alias uniqueness targets and later mutable aliases
all decline the optimization. It separately certifies the incoming operand:
an immediately preceding raw load or exact inert list projection, no alternate
entry, no intervening copy and no planned read-capture snapshot. Those producers
leave the operand guard empty. Projection fill may refresh its pointer, but the
parent owns the resulting child. Ordinary and H-bearing slots retain cleanup.

The matched Debug compiler base is joined `c0896776`, including the iteration
identity correction. The reviewed candidate compiler SHA256 is
`3d95fa3caf1ceae5c1d8f19b0beaef99c876aa7522015ae345567e0c83b6178b`.
Actual QBE and LLVM O3/full-LTO guests pass 103 assertions per backend, covering
held iterations, snapshots, mutable-parameter rebinding, pending callbacks,
three-level projections, aggregate ownership and temporary lifetimes. Their
counter dictionaries agree, heap allocations retire and holds balance. The
focused selection passes 12 tests, including a positive fast loop, a held-iterator negative,
callback refusal, no-entry refusal and step-accounting refusal. Pattern/reference
checks are defensive structural exclusions; no malformed bytecode is executed.
Whole-tree Guardian passes 88 checks.

Paired bounds and overflow probes retain their fast and original loop copies.
Their failing guards preserve the exact structured traps on both backends:
index 2 into length 2, and addition of 9,223,372,036,854,775,806 and 2 at width 64.
Every before/after trap run retires its two allocations. An initial diagnostic
driver incorrectly expected `R_INTEGER_OVERFLOW`; its preserved output already
reported the correct `R_OVERFLOW`. The final driver uses the actual code and
reruns the complete comparison.

The n12 matrix diagnostic retains every counter: 103 owner acquisitions,
235 releases, 132 allocations/retirements, one clone, 482 uniqueness checks and
no holds. Median-of-three user instructions on CPU 10 fall from 1,020,560 to
984,726 on QBE (0.9649×), and from 736,929 to 675,981 on LLVM (0.9173×).
All runs print exactly `41383` and `485891` on separate lines. This small source
changes only the mandated matrix dimension from 500 to 12; full RC performance
acceptance remains a separate root-integration measurement.

[Raw evidence](evidence/d9-rc-loop-versions.json.gz) includes final commands,
compiler/binary identities, sources, drivers, samples, manifests and outputs,
plus the preliminary diagnostic records and correction. Root integration owns
the complete gate.
