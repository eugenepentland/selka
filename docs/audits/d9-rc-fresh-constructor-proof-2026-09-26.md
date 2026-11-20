# Linear fresh-constructor transfer

The implemented candidate is a bounded constructor-field relocation. It uses the
cohesive ABI3 cumulative control `19e16e1d`; the earlier post-inert profile below
records the investigation that motivated it. This is performance evidence, not
WP-4 acceptance. No history or physical-loan event is skipped.

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

The certificate admits a deliberately small grammar and rejects on budget
exhaustion or any unsupported operation. Its purpose is to prove a
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

## Implemented boundary

`qbe_rc_fresh_constructor.certify` inspects at most 128 instructions. Each shape walk follows at most 128 unique types /
512 type edges using fixed local arrays. All local
bindings, including incoming parameters, must be integer, boolean or unit values.
The allowed bytecodes are scalar constants/checked arithmetic, scalar local
loads/stores, ordinary constructors, a direct self call, return, and forward
branches whose targets have empty operand stacks. Every reachable typed stack is
copyable and excludes unique content; the full recursive type graph excludes
collections, live views, resources and callbacks. Fallible Result variants refuse.
Entry functions, host/C ABI functions, heap frames, borrowed bodies, managed locals,
inlining, captures, uniqueness work, semantic shares, all physical ownership copies
and every non-move transfer refuse. Unknown/new bytecodes refuse automatically.

This grammar proves physical linearity in addition to the ownership analysis:
managed values have no local storage or load operation, no duplication opcode,
and no managed value crossing a join. Self calls receive only scalar inputs and
return only the same certified construction language. Successful recursive returns
are fresh by induction. Constructors consume each managed operand once; no
operation can observe, pin, retain, loan or alias the new graph before consumption.
There are no arena transitions or external callees, so child and parent inherit
the same current region. A caller may already be inside an arena.

Only `qbe_rc_aggregate.initialize` uses the certificate, and only for an ordinary
counted operand field of at most 256 bytes. It still tests the initialized flag and
rejects dynamic H/LOAN roles. The destination is the existing zero-initialized,
guarded partial aggregate or newly allocated managed body. The ordinary source is
its independent stable operand storage (or scalar operand word). A byte blit then
clears the source guard without any intervening call or failure point. Stale source
bits have no ownership obligation and cannot be used again in the certified
linear grammar. The unchanged `prepareOperand` path remains as the dynamic and
static fallback. The internal construction journal, final publication, failure
paths, frame accounting, region checks in fallback and runtime ABI are unchanged.

## Matched cumulative result

The immutable control Debug compiler is SHA-256
`1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe`.
Candidate identity, manifests, all three interleaved samples, exact commands,
source hash and counter snapshots are archived under
`experiments/d9-rc-fresh-constructor-20260926`.

| Backend | Before instructions | After instructions | After / before | After / accepted GC |
| --- | ---: | ---: | ---: | ---: |
| QBE | 599,762,396 | 524,564,349 | 0.874620 | 4.957918 |
| LLVM O3/full LTO | 329,568,532 | 296,064,457 | 0.898340 | 5.85892 |

Both arms produce the exact expected output. Each allocates and retires 669,060
objects, acquires 19 additional ordinary owners and releases 669,079; H traffic
and clones remain zero, and uniqueness checks remain 33. This is a 12.54% QBE and
10.17% LLVM retired-instruction reduction in this workload, not a corpus timing
or acceptance result. The accepted GC binaries and acceptance thresholds remain
unchanged.

## Validation

All 78 selected actual guest assertions pass on each backend. The five new
standalone assertions pass on both control and candidate in GC stress and RC
counting modes: 299 heap allocations/retirements, O 8/307, H 8/8, and 62 arena
allocations/escape clones. The 256 KiB refusal probe traps after 4,089 allocations
and retires all 4,089 on both compilers/backends. The frame-limit probe preserves
`R_FRAME_LIMIT` before allocation. Checked division after an earlier child traps
with `R_DIVISION_BY_ZERO` and retires that child immediately. Every before/after
counter vector matches. The SSA of this arithmetic probe contains eight admitted
handoffs, so it exercises the certified function rather than only a refusal.

The broad focused RC run passes 114 tests; the five final certificate cases pass
separately (16 with the project's unnamed blocks), including an unused managed
incoming parameter that must refuse. Whole-tree Guardian passes all 88 checks;
no limits or baselines were changed. The final Debug install is byte-identical
to the measured candidate, SHA-256
`1b85b2f80b4b229b7bed0c8a120457df28892501edbd0b4732ebb338cd334f8b`.
The parent independently reviewed the certificate and handoff and found no
blocker. Full integration gates remain parent-coordinated.
