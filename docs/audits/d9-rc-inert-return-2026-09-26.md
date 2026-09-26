# Bounded inert RC returns

This slice lets a proved null-edge early return finish before initializing its RC
journal. The independent control is `41e08854` (production source `b5ee54bc`),
after cached production allocation and before the pending compact journal,
disjoint-transfer and semantic-history slices. It changes no runtime layout or
ownership ABI. The immutable Debug compiler hashes, exact commands, source,
all measurements and output are retained in
`experiments/d9-rc-inert-return-20260926`.

## Proof and lowering

`qbe_rc_inert_return.certify` admits at most 32 instructions and integer/boolean
parameters only. Its closed predicate grammar consists of parameter loads,
integer/boolean literals, comparisons, boolean negation and one forward
conditional branch. The selected branch must return an inline value, at most
256 bytes, made only from zero literals, empty tag-zero variants and inline
records. Every resulting byte is zero, including every managed edge. The result
still satisfies the canonical owned-result ABI: the caller publishes the usual
result guard; there is no physical ownership obligation to release inside the
returning frame.

The proof refuses any incoming managed, H or unique obligation; mutable ABI
parameters; heap frames; entry adapters; borrowed-body lowering; alternate
entries/backedges; inline origins; active read captures; calls; allocations;
projections; value copies; scopes; loans; semantic SHARE and all unsupported or
future bytecode operations. Result variants are expressly refused because their
construction may record error provenance. Step-accounted builds retain ordinary
lowering entirely. Scalar native return layouts are excluded explicitly.

Native stack-floor and logical frame admission run first, with their original
failure behavior. The early return zeros its ordinary ABI result buffer and
performs the existing native-frame leave. It never reads or links RC guards,
changes arena depth, touches inherited receiver scopes, or calls runtime cleanup.
The false branch initializes the unchanged journal and resumes the original
conditional's empty-stack successor. The proved pure predicate is not evaluated
twice. Original instruction lowering remains present; a dedicated unreachable
block label survives label stripping, and backend dead-code elimination removes
that unused prefix. The normal branch retains the complete ownership protocol.

This helper relies only on the existing frame-state query and public emitter
methods, not journal index arithmetic or metadata layout. The compact-journal
owner confirmed that allocation declarations may precede its `enter`, whereas
metadata and guards become valid together at `enter`. The helper skips both on
its inert branch. New semantic-history or loan operations default to refusal;
the history owner was given the exact proof-query boundary for explicit veto.

## Results

Three interleaved samples per arm on CPU 2 use the identical private depth-12
binary-trees source. QBE uses normal optimization; actual LLVM uses O3 and full
LTO, verified in each native manifest. The accepted GC arm remains the immutable
`f6bea5d9` Debug compiler (SHA-256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`).

| Backend | Before instructions | After | After / before | After / accepted GC |
| --- | ---: | ---: | ---: | ---: |
| QBE | 907,414,130 | 683,032,866 | 0.752725 | 6.455683 |
| LLVM O3 / full LTO | 465,108,537 | 388,701,879 | 0.835723 | 7.692152 |

Every output byte matches. Both counting binaries retain exactly 669,060 heap
allocations/retirements, 19 O acquires, 669,079 O releases, 33 uniqueness checks,
and no H traffic, clones or refusals. These private ratios still fail WP-4 by a
large margin; neither its full-corpus criteria nor the accepted baseline changes.

## Validation

- Focused RC unit selection: 67/67 (including three new proof/lowering tests).
- Final Debug installation: 19/19 build steps; Guardian's 88 checks pass both
  diff-scoped installation and explicit whole-tree validation.
- An unaccounted standalone driver executes 54 public assertions across eight
  modules on both actual backends, before and after. It covers scalar/boolean
  guards, wide inline zero records, regular tagged unions, resources, arenas,
  partial constructors, holds and iteration. All four runs have identical
  counters: 1,466 allocations/retirements, 1,031 O acquires, 2,497 O releases,
  67 H acquires/releases, 103 arena allocations and 36 clones.
- Saved emitted IL confirms `make`, `boolean`, `wide` and `choice` take the new
  path; `shared`, `nonzero`, `consume` and `resource_check` refuse it. The new
  unit fixture additionally refuses calls, named publication, Result provenance,
  allocation and arena work before the branch. Frame-accounted lowering retains
  the path and its admission checks; step accounting and GC decline it.
- Twelve real trap runs cover native stack-floor failure, a four-frame ceiling
  and a 100-step ceiling, before/after on both actual backends. They preserve
  `R_FRAME_LIMIT`/`R_STEP_LIMIT` and retire both preexisting heap objects.
- A prior prototype passed 66 accounted guest tests per backend; those runs are
  explicitly fallback coverage, not evidence that the shortcut executed. The
  final eight new guests are also checked under accounted GC and RC on both
  backends, with their independent results retained.

The prototype first exposed a QBE syntax error when label stripping erased the
now-unreferenced original `i0` label. The dedicated block boundary fixes that
failure; direct unaccounted builds and saved assembly validate the actual path.
Guardian also caught the extra branch pushing the main lowering function above
its complexity limit. Extracting the boundary helper resolved it without changing
any Guardian rule or baseline. The trap harness initially passed runtime flags
as executable guest arguments; final trap probes correctly use `build --run`
with runtime controls, so the recorded ceilings are actually enforced.

No full regression gate or full acceptance corpus ran in this slice; the parent
coordinates both and the shared Guardian feedback log. Combined measurements
with the newer compact journal remain separate from these isolated results.
