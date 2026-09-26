# Proposed linear fresh-constructor transfer

This is a bounded follow-up design, not an implemented optimization or acceptance
claim. Its control is the immutable post-inert compiler described in
`d9-rc-inert-return-2026-09-26.md`. ABI3 semantic history is a required integration
boundary; no history or physical-loan event may be silently skipped.

## Evidence and narrow target

The depth-12 workload still retires approximately 683 million QBE instructions or
389 million LLVM instructions after the inert-return slice. It allocates/retires
669,060 heap objects, with only 19 additional ordinary-owner acquires. More count
elision alone cannot explain or remove the remaining cost.

The generated nonzero `make` body retains eight generic TAKE sites and one COPY
fallback despite building its result entirely from scalar inputs, null leaves,
fresh recursive results and constructors. Transfers stage through operand storage,
`rcwork`, and the already-guarded aggregate or box body. Those paths include
nullable/header/region/overlap tests and pending-journal descriptor/guard writes.
The actual ownership explanation classifies all ten constructor/return transfers
in this function as `move` from `fresh`, with no COW sites. This is useful input
to a proof, not sufficient proof by itself.

Independent fresh instruction samples collected by the collections agent on the
immutable compiler attribute about 30.79% of QBE instructions and 45.93% of LLVM
instructions to generated `make` itself, excluding runtime helpers. The QBE
memset helper adds about 10.89% globally. Their repeated-240 profiles have no lost
samples but report throttling; these percentages are diagnostic estimates and do
not predict a speedup. The raw profiles and binary identities belong to
`experiments/d9-rc-flat-destruction-20260926`. No duplicate measurement was run.

## Certificate conditions

An initial certificate should admit a deliberately small grammar and reject on
budget exhaustion or any unsupported operation. Its purpose is to prove a
physical single-owner bundle that can relocate into an empty destination.

- Parameters are scalar values only. There is no incoming ordinary owner, held
  identity, loan, unique resource, managed by-reference input, or mutable input.
- Managed values arise only from empty zero constructors, fresh aggregate/box
  constructors, or a statically resolved call in the independently certified
  closed recursion family. Initial self recursion is enough; unknown/dynamic
  calls and unproved callees refuse.
- Physical managed use is linear. Every relevant ownership transfer must be a
  move; every actual `ownership.copies` entry refuses even if mutable-history
  `needsCopy` would be false. Immutable box pointer duplication can add ordinary
  owners without a mutable SHARE event and is expressly not fresh single ownership.
- No managed projection, field load, buffer operation, user-resource operation,
  aliasing managed local load, capture, hidden pending receiver, semantic SHARE,
  H conversion, physical loan, address-taking or callback is admitted.
- No arena transition occurs. Fresh callees inherit the same region, so a fresh
  return and a new constructor destination can have equal proven regions even
  inside a caller's arena. The first implementation may conservatively retain a
  runtime region fallback instead of relying on this equality.
- Forward scalar branches and early returns may be allowed only with explicit
  operand-state validation. Initially refuse backward edges and managed branch
  joins that could select a borrowed, aliased or unknown alternative. Constructors
  and return operands still have exactly one live cleanup obligation on every
  admitted edge.
- Types have only ordinary owner edges or plain bits; no H fields, unique drops,
  finalizers, resource-containing bodies or opaque producer descriptors. Any
  traversed type/call/flow graph has an explicit iterative work budget.
- Existing borrowed-body lowering, heap-frame special cases, adapters and any
  unknown compiler publication hook default to the ordinary path. Certification
  is based on finalized ownership/physical plans, not source spelling, type names,
  return-origin summaries or an initialized guard alone.

A successful finite recursive return is justified inductively: the empty branch
has no owned leaves; each completed recursive call returns a single-owner fresh
bundle; constructors consume those bundles exactly once into a distinct fresh
body. Nontermination or an allocation/overflow trap does not produce a return and
continues to use the normal frame and partial-body unwind machinery.

## Publication and failure proof

The proposed first use is one narrow branch in aggregate field initialization.
The destination aggregate is already zeroed and registered under its construction
or typed internal guard. The source is a complete, guarded ordinary operand with
the certificate above. Its physical frame buffer is distinct from a new heap body
or the compiler's independent aggregate scratch buffer.

Relocate the source bytes directly into the destination field, then clear the
source's initialized guard. No helper call, guest callback, allocation, trap check
or observation may intervene. There is never a fallible transfer after publishing
one edge. A subsequent field allocation failure sees the initialized child through
the original partial-body journal and sees the source guard cleared. An allocation
failure before this handoff still sees the source guarded and the destination
unpublished. Keep all native stack-floor/frame admission, allocation status,
constructor initialization, descriptor registration and failure guards unchanged.

The ordinary typed preparation path remains for every refusal; there is no runtime
ABI change. The optimization must not release an owner, clear a guard early, skip a
semantic event, adopt an H token as O, or elide cleanup just because a value looks
fresh syntactically. It also must not rely on generic slow-path success to make a
partial direct handoff safe.

## Required evidence before keeping a candidate

Positive tests should cover recursive fresh records/boxes, null children, multiple
fields and inherited arena regions. Refusals must include duplicated immutable
box owners, named aliases, unknown/indirect callees, managed parameters, loan/read
captures, explicit semantic copies, mixed branch provenance, unique/H fields and
arena transitions. Keep low-budget allocation failure, stack admission and
partially initialized parent cleanup probes on both actual backends.

Measure an immutable before/after Debug compiler pair on the same private n12
source with actual QBE and LLVM O3/full LTO, preserving output and exact counters.
Retain emitted-path evidence that the certificate fired, full samples and the
frozen accepted GC arm. Reassess on the cohesive ABI3 compiler rather than claiming
old ABI2 assembly predicts its code shape. Full gates and the acceptance corpus
remain parent-coordinated.
