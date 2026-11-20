Corrected source `730a86e62b47c922dc1411d24b5868c3bd2132f3` passes all
240 ordinary frozen MyLang edge cells (40 cases × three inputs × two backends).
The Debug host compiler has a separate immutable source/build/assets receipt;
guests are ReleaseFast. All eight emitted backend manifests were checked before
and after: LLVM O3/full LTO and QBE non-LTO, including native archive hashes.

Every guest invocation uses CPU2 and the global timing flock. Exact checksums,
zero exit status, empty ordinary stderr and positive integer clock protocol
were validated. Elapsed values were removed from the qualification receipt;
this is correctness evidence, not acceptance timing. Coverage uniqueness,
compiler/source/assets/binary/clock/helper hashes and manifest stability were
checked before and after capture.

This qualifies the incoming-edge repair after rejected188da416 failed all six
predictable-branch edge cells. The corrected predictable and mixed cases both
pass. Full ReleaseFast-host measurements, holdouts and independent confirmation
are separately identified; this Debug-host qualification does not substitute
for those captures or establish RF/Debug guest byte equivalence.

The archive contains the exact capture helper and receipt, compiler receipt/log,
and all24 guest build/source/binary receipts/logs (eight new MyLang guests and
sixteen verified reference copies). Frozen ports and their checksums remain
unchanged. Limitations include ordinary generator shapes and finite edge inputs;
Unicode/error/alias and resource failures require focused semantic tests.

Qualification JSON SHA256: `1124bb553a31d0b2ebcd1f0d4a98f0316795b0e2bec5478ca543dc18f7bf8c18`.
Archive SHA256: `a891c1a8701fa08ff520d774aa5a55cc7955ea8f2c1fcd797f0db8a5677f677b`.
