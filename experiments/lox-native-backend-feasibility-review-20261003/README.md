# Independent native backend policy feasibility review

The written proposal at author commit `29883d8a` is feasible with its producer
compatibility addendum. No implementation, compiler build, guest execution or
performance result is certified by this review.

Select the existing checked V2 ownership emitter only after resolving both the
backend and actual producer. Original is the public API default and the early
refusal occurs before any query, temporary, print or metadata change. Resolved
LLVM, including the legacy `qbe_llvm.py` spelling, uses original emission.
Checked self-produced QBE can select V2 while keeping its reviewed admission,
region, overlap, ownership and counting/GC refusals.

The review found one compatibility defect in the first proposal: adding an
internal flag to every `MYLANG_HOST_COMPILER` or foreign native-test producer
could break a previously successful older producer. The preserved addendum
corrects this: actual foreign/override producers retain original policy and
exact old argv. Decide this before selecting frontend replay/fragment, module
and test-session keys. If per-module self production and a whole-program
override cannot share a proven consistent policy, keep the invocation original.

All policy-dependent emission identities must be partitioned before cache
lookup, including selected native-test sessions and standard/imported modules.
External manifests, assemble and module-object/link APIs compile supplied IL
without new certificate admission. A hash or producer string supplies integrity,
rather than authority to skip ownership protocol. Test the actual old-producer
argv, opposite-policy cache reuse and complete original LLVM IL/metadata/IR and
allocated ELF equivalence before claiming the implemented route is qualified.

The read-only verifier binds all seven proposal files, 37 selected compiler
files to base `3b33df52`, all 37 selected port files, four selected artifacts and
the 12 frozen V2 files. The illustrative comment counts remain lexical models;
they do not count admitted or executed ownership sites.

```sh
taskset -c 16 python3 -B experiments/lox-native-backend-feasibility-review-20261003/verify.py
```

`review.json` and deterministic gzip input copies preserve the original note,
its superseding addendum and the source evidence. Root owns implementation
authorization and performance selection. The subsequent policy implementation
is outside this written-feasibility freeze.
