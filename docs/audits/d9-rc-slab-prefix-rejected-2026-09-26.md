# Rejected RC slab-prefix reset experiment

The candidate skips zeroing the 32-byte prefix in `slab_take`, retaining complete
payload and class-padding zeroing. Both private callers immediately initialize
every owner/hold/common-header field, without callbacks, fallible work or
publication in between. The consumed free-list link occupies the owner word.
Additional layout assertions verify every prefix byte is overwritten.

This experiment is independent of the drain cache. Its base is `d95621a7`,
including frozen cumulative integration `19e16e1d`; the before executables are
the shared immutable cumulative19e builds. No accepted GC artifact changed.
The runtime candidate and its tests are preserved in
`experiments/d9-rc-slab-prefix-rejected-20260926/candidate.patch`, not applied
to production source.

## Decision and measurement

Reject the change. Five interleaved samples per arm on CPU 3 show no instruction
gain on either actual backend:

| Backend | Before instructions | Candidate instructions | Candidate / before |
| --- | ---: | ---: | ---: |
| QBE | 600,024,527 | 600,478,384 | 1.000756 |
| LLVM O3/full LTO | 329,526,400 | 331,488,669 | 1.005955 |

Removing source-level stores does not guarantee fewer generated instructions.
The small QBE change is near run-to-run variation; neither backend supports
keeping this candidate. No allocation or RSS reduction was expected or claimed.

Every output byte and counted event matches the before arm. Both n12 counting
binaries retain 669,060 allocations/retirements, O 19/669,079, H 0/0,
33 uniqueness checks and zero clones/refusals.

## Safety controls and evidence

The added production-allocator fixture preserves a slab with an anchor,
retires another object and poisons every retired byte except its live free-list
link. Reallocation changes the type, verifies exact O1/H0/type/count/flags,
and checks all payload and class padding are zero. It covers both private
allocation callers, zero-sized bodies and 48/64/256/8192-byte slots.

The candidate passes ASan/UBSan collections 33, contract 21, loans 9,
semantic history 27, held views 12 and arenas 10, plus execution/statistics
harnesses. The focused production wrapper passes 12/12. The actual standalone
54-assertion driver passes before/after on QBE and LLVM with identical balanced
counts: 1,464 heap allocations/retirements, O 906/2,370, H 208/208,
96 arena allocations and 31 clones. The Debug build passes Guardian 88.

The first measurement-driver adaptation accidentally renamed `--cache-dir` and
was refused before building a guest. Its traceback is preserved separately;
the corrected driver's complete successful run supplies all reported results.

Commands, compiler/binary/source hashes, native backend manifests, raw samples,
counter records and validation logs are archived beside the candidate patch.
The isolated compiler/binaries under `.tmp-prefix` retain the rejected source
identity for review. Tracked production source is restored to the base.
