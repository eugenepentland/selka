# RC scalar list stores

RC writes to nonzero scalar elements with no counted or unique edges now use
the existing typed native store. Index normalization, negative-index reporting,
bounds checks and physical uniqueness remain unchanged. Managed and unique
elements still use the fallible ownership helper.

The paired Debug compilers differ only by this optimization and its tests.
Before SHA256: `ccae333044577b6dae97c93c961d1d94c9e1e215b3a38bbefe02d3006e2ce69b`.
After SHA256: `567c2e3142503825e7c1bf87755b46b4b411d5cc52893640a87f984ef03f9bd2`.
Guests use ReleaseFast; LLVM uses O3/full LTO. Both actual backends pass 88
receiver, snapshot, aggregate and lifetime assertions, with balanced and
backend-identical counters. The structural selection passes 12 tests and
whole-tree Guardian passes 88 checks.

The matrix diagnostic changes only the mandated dimension from 500 to 12.
Median-of-three user instructions on CPU 10 fall from 2,138,770 to 1,969,773
on QBE (0.9210×) and from 1,449,022 to 1,337,498 on LLVM (0.9230×).
All counters remain identical: 1,831 owner acquisitions, 1,963 releases,
132 allocations/retirements, one clone, 482 uniqueness checks and no holds.
The exact output remains `41383` and `485891` on separate lines.

An out-of-bounds write at index -3 into a two-element list traps with the same
`R_LIST_BOUNDS` structured index and length, before and after on both backends;
all four trap runs retire their two allocations. Permanent tests also cover
byte-width integers, booleans, floats, negative indices and managed children.

[Raw evidence](evidence/d9-rc-plain-list-writes.json.gz) preserves commands,
compiler and binary identities, drivers, sources, samples and outputs. These
focused results do not establish the full 43-program RC performance acceptance;
root integration owns that measurement and the full gate.
