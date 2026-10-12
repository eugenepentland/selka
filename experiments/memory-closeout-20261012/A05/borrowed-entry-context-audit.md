# Borrowed entry provider context: bounded design request

This is a read-only audit and proposed contract, not an implementation or passing
qualification. Coordinator/A07 own production changes. The original A10 fixture
is `../A10/fixtures/borrowed_entry_context.my`, SHA256
`cb4471d34b70ed9fdd4a43a8d8c7f6ff7bcd27258b01587ae4c2cd38011c87b1`.
Its exact Support6 receipt is `../A10/rollout/borrowed-entry-context-support6.json`.
Ordinary checking passes; checked ownership rejects borrowed `fs` at line 14.

```text
func main(fs: Filesystem, env: Environment) -> int:
    mut ctx = Context(fs=fs, env=env)
    return read_note(ctx, "note.txt") + len(ctx.env.names())
```

The providers must remain the actual entry arguments, with their existing grants,
state and cleanup authority. Substituting local providers changes this contract.

## Concrete reason for refusal

`single_owner.checkStore` treats Context as an owning record. Its `recordFields`
path moves both provider operands, and `checkLocal` correctly refuses moving a
borrowed parameter. Merely allowing this source construction is unsafe:

- Core `record_make` normally consumes its managed operands and its owned result
  eventually destroys managed children.
- `own.Analysis.classify` and `collectUses` recognize only the existing special
  borrowed dictionary-entry pair; that exception has one parent. This context has
  two independent provider inputs and cannot use an arbitrary one as its parent.
- The coordinator's new owning `recordFieldValue` path clears a moved source's
  lexical provider pin. A borrowed construction must not clear `fs` or `env` or
  their bindings; both remain usable after calls through `ctx`.

## Proposed narrow source rule

Recognize a compiler-only borrowed provider context at a local record initializer,
without adding source syntax or a general storable view type. Initially require:

1. An ordinary record/tuple containing provider leaves and otherwise unmanaged
   scalar leaves. No owned text/list/bytes/resource children, boxed/variant/
   container shapes, or mixed borrowed and newly owned providers.
2. Every provider leaf is an ordinary immutable function parameter, or a field
   projection rooted in such a borrowed parameter. No mutable/consuming parameter,
   local owner, narrowed local scope, arbitrary call, ambiguous conditional or
   general origin inference. The original entry fixture meets this rule.
3. A direct local initialization only. `mut ctx` may retain its existing spelling,
   but it does not grant mutation of this borrowed context. Structural rebind,
   field replacement, mut arguments, partial extraction, copy, return, owning
   storage, closure capture and owning tuple unpack must refuse. Read-only helper
   calls, field methods and scoped file acquisition through its fields may work.

All parameter roots stay valid for the entire invocation; current Core already
pins provider parameters until lexical exit. This makes multiple provider inputs
safe without general multi-root lifetime inference or a whole-program analysis.
Owned provider records keep their existing move/drop behavior. The classification
must be per value, not a change making the Context type universally non-owning.

Source checking can mark the local as borrowed and non-writable after checking
each operand in read mode. It must still reject escapes at consuming uses. Use a
specific diagnostic for borrowed provider contexts instead of suggesting `.copy()`
as a remedy for noncopyable capabilities. Local borrowed aliases/rebinding and
more general local-root borrowing are optional later extensions, not required by
the original fixture and not silently admitted by this proposal.

## Core, ABI and cache agreement

Use one exact source predicate for the checker and builder. For the recognized
initializer, Core must use ordinary reads and skip owning source-pin clearing.
The physical Context record remains an inline value with the current field ABI;
no runtime allocation, retained count, new helper whitelist or alternate provider
is needed for the wrapper itself.

Ownership analysis needs an explicitly validated borrowed-record construction:
its fields are nonconsuming borrows and the wrapper has no child destruction.
The same validation must survive optimization and cache replay. Either carry an
audited compiler marker, or prove the complete provider-only construction from
immutable borrowed parameter/projection operands; do not infer it from record
type or the presence of a single borrowed operand. A verified parameter-only
construction can be borrowed with no single owned parent because all parameter
roots remain pinned for the call. Field reads still borrow from the wrapper.
The verifier must refuse any consuming use inconsistent with the source contract.

Do not reuse `borrowedItem` by choosing just `fs` or just `env` as the lifetime
parent. Avoid recursive re-traversal of arbitrary shared graphs: classify/cache
the bounded construction and parameter projections once per function. A08 must
cover persisted identity/marker validation if any representation is extended.

Existing direct-provider resource-return rules remain unchanged. An aggregate
parameter must not acquire new resource-return origin inference. A scoped file
opened through a local borrowed context stays within its context/parameter call.

## Required qualification before admission

- Preserve A10's exact source and execute it with actual entry providers and
  dedicated file/environment grants. Verify it observes those inputs, including
  denied/missing cases; do not replace them with factories inside the program.
- After context calls, use the original `fs` and `env` again. An owning caller or
  native provider harness must prove the guest did not destroy the borrowed
  providers and the actual owner destroys each exactly once afterward.
- Read-only helper calls, nested file scopes, early return and propagated errors
  must pass; repeat contexts and independent parameter roots must remain valid.
- Preserve owned Context construction/return/move and independent cleanup in the
  existing A05 provider-record and capability-field fixtures.
- Refuse context return/store/copy/field extraction, structural mutation, mutable
  or consuming parameter sources, mixed borrowed/owned managed fields and
  aggregate-parameter resource return. Keep original unsupported container/view
  boundaries and tuple ownership negatives.
- Qualify all five modes with counted cleanup, LLVM/preprocessed-runtime/symbol
  checks and cold/warm cache replay. A source-only waiver is insufficient.

No production file or runtime contract was changed by this audit.
