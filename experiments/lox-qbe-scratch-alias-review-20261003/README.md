# Independent private scratch address review

No actionable correctness defect was found in frozen alias proof v1
`48707aa4`, or v2's documentation-only update. The shared whole-function
`Facts` module is byte-identical to the independently reviewed dispatch proof.
This receipt covers source proof and the author's focused native oracle;
broader compiler/Lox qualification and performance selection remain pending.

A qualifying root uniquely defines an eight-byte entry `alloc8`. Its address
never escapes and all copy aliases have one readonly use. A direct `l copy`
with one definition and one sole load use can therefore be replaced by the
same root address. Constant entry allocation is fixed frame storage in pinned
QBE's AMD64 lowering. Memory contents can change between copy and load: the
load keeps its position and reads those later contents, as the original did.

The pass comments the copy and replaces only the load's address token. It
preserves byte/word/float load opcode and result type, all stores, callbacks,
control flow, debug locations and accounting. It introduces no labels or
temporaries, so it needs no generated-name collision scheme. Parameters,
definitions, ordinary operands, phi operands and indirect targets participate
in the proof. Escaping or stored addresses, arithmetic, alias writes, ambiguous
definitions and extra uses decline. Analysis caps bound input, instructions,
aliases and patches. Proof scope is valid emitted QBE, rather than full
semantic validation of arbitrary malformed IL.

Resolved `cache.codegen.llvm` bypasses the transformation; LLVM continues to
read the original fragments. The pass and proof filenames match the existing
`qbe_build_*` driver-input rule, partitioning object identities when their
source changes. No certificate comments or manifest producer strings confer
ownership authority in this address-only rewrite.

The author's native oracle asserts four independent output words and return
value for both original and transformed code on 13 bit patterns, including
signed bytes, integer extremes and floating NaN bits. Corrected focus passed
17 (five named plus 12 mandatory), outer status zero. The initial tool-prefix
mismatch passed 16/17 and failed to start QBE; it is retained and excluded.
The reporter's `failed command` footer is not used as process status. V2 moved
only the SPEC bullet into a linked section after the earlier Guardian failure;
no production/test bytes or extra test run are inferred from that change.

`review.json` identifies source and raw receipt hashes. Deterministic gzip
copies retain both proof versions and the initial failure. Recheck bindings:

```sh
taskset -c 16 python3 -B experiments/lox-qbe-scratch-alias-review-20261003/verify.py
```

The reviewer ran only this read-only verifier. This review makes no speed,
promotion or parity claim and does not replace actual four-flavor qualification.
