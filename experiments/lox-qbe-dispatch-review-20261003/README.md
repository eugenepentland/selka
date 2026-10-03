Independent review of the QBE-only scratch-chain dispatch proof, 2026-10-03

The frozen v3 six-file proof has no actionable semantic defect in the reviewed
admission and transformation. This reviews compiler proof and focused evidence;
it does not qualify a Lox guest, assert a performance improvement, or select the
compiler. The review is independent of the author and changes no compiler source.

The classifier enters the greatest-key original comparison leaf at or below the
signed selector, or the first leaf below the minimum key. Full-width equality
then matches the same key as the original chain. A missing value follows that
leaf's unchanged false suffix, ending with scratch0=0 and scratch1=the last key.
A match ends with scratch0=1 and scratch1=that key. The selector is unchanged.
The proof requires three distinct uniquely defined entry `alloc8 8` cells,
whole-function nonescaping addresses, at most eight single-use readonly copy
aliases, and five single-definition/single-use scalar results per leaf. Skipped
results cannot be live in a handler or phi. Managed journals and explicit root
operations remain intact; escaping a cell address refuses the certificate.

Each exact nine-operation leaf contains only full-width loads, stores, equality
and a branch. It contains no allocation, call, callback, cleanup, trap check,
accounting operation, phi or debug-position instruction. No unsafe access,
ownership check or user effect is removed. Valid emitted QBE is the boundary:
this is not an independent validator for arbitrary malformed or undefined IL.
V2 additionally refuses every interior jmp/jnz/ret/hlt, closing the v1 structural
gap before edge collection. Foreign entries, duplicate labels, wrong widths,
changed cells, ambiguous results, cycles, unordered or repeated keys, and address
escapes refuse. Unsupported units preserve their original bytes.

All original leaves and true/default suffixes remain byte-for-byte present.
The sole preceding false edge is retargeted to fresh classifier labels; true
handler predecessors and their phi labels remain original. Synthetic blocks
are appended after the original terminal block, avoiding accidental fallthrough.
The reserved namespace declines on any existing occurrence, including comments,
so generated temporaries and labels cannot collide. Signed `csltl` ordering is
compatible with bitwise `ceql` for every admitted i64 literal, including both
endpoints. Unknown selectors are not routed directly to a default or handler.

The downstream hook explicitly bypasses the pass for LLVM, after loading shared
frontend text and before QBE's existing size check and staging. Production
`qbe_build*` files participate in `bundled.driver_identity`; that identity names
generation and environment keys for object, batch, executable and receipt reuse.
The unchanged LLVM path reads original fragments. Actual LLVM allocated-section
equivalence and whole-guest RC/GC/trap behavior remain later qualification work.

The reviewer flagged that v2's actual native oracle checked a combined XOR
checksum. V3 keeps production bytes identical and independently asserts selector,
scratch0 and scratch1 for both control and candidate on 13 signed endpoint,
known-key and hole values. It also retains the original PHI predecessor check.
Exact author v3 focused execution passed 20 tests (8 named plus 12 mandatory),
and the whole-tree Guardian passed 88 checks, both outer status0. The focused
log's misleading `failed command` footer and unused `-U NDEBUG` warning are kept;
the actual process receipt and RESULT identify the outcome. These are bounded
probes rather than an exhaustive integer/CFG or collector qualification.

The standalone selected AST VM transformation preserves every original IL byte
except two false-edge targets and the appended 30 classifier blocks. The two
16-leaf chains compare 1..16 and 18,22..36; effects and arithmetic OR prefixes stay
unchanged. The pinned QBE assembly command passed. Raw path models exclude
identical prefixes and handlers and may regress early keys; they are not native
instruction counts or timing evidence. Broad units, release compiler completion,
whole Lox guest qualification and central performance were pending at this freeze.

Run `python3 -B experiments/lox-qbe-dispatch-review-20261003/verify.py` from this
worktree to rehash originals and saved copies, validate exact focused/Guardian
receipts, and restore the selected original VM IL from the transformed text.
The verifier executes no compiler or guest. `review.json` binds every input,
immutable proof descriptor, command log and independent conclusion. Historical
v1/v2 descriptors are retained; their evidence is not added to the v3 test count.
