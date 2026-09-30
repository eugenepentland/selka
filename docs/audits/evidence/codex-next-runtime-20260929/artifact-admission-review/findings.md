# Combined runtime review, 2026-09-30

Read-only combined production source reviewed at `91bb0769` (root's later
`61c` tip adds documentation only). Reproduction uses the fresh owned review
worktree, its own local/global Zig caches and TMPDIR, with every compile/run
through `scripts/build-slot.sh build`. No root production edits, broad gate,
corpus sampling or timing claim were made. Original B3 source/compiler and all
receipts remain frozen.

## Confirmed findings

1. **Reject `make_record` carrying both payload and blob.**
   `src/bytecode.zig:541` returns through packed-payload validation before the
   embed-family validation at 543. A list[int] record with zero operands, a
   valid eight-octet payload and a nonnull Blob is accepted by `validate`.
   `src/qbe_managed.zig:417` chooses Blob before the static-list path at 424,
   so accepted IR uses a different representation than the one validated.
   Reject simultaneous authority rather than silently picking one.

2. **Reject conflicting signature-only dependencies.**
   `src/module_physical_inputs.zig:114` skips a subsequent dependency when its
   first stand-in already has unknown physical metadata. Two archives naming
   lib.helper with int versus bool return types are accepted. The resulting
   signature depends on interface order, whereas contradictory physical
   records and body duplicates already refuse. Compare normalized symbolic
   signatures even when an original signature/body exists.

3. **Bind each decoded body ID to its archive name.**
   `src/module_physical_inputs.zig:137` reads a function named lib.first whose
   encoded symbolic ID resolves to lib.second, then stores it in lib.first's
   reserved slot at 144. `physical.read` checks the value's name but not that
   identity association. It must reject rather than granting wrong-ID body
   authority.

   The consequence is independently demonstrated: lib.first calls
   lib.second, and lib.second's actual body contains print. Correcting
   lib.first's ID to zero makes `rc_readonly_calls.certify` return null.
   Leaving the accepted forged ID at one returns a readonly certificate:
   `src/rc_readonly_calls.zig:109` treats the actual helper call as self
   recursion and bypasses the helper's closed-grammar refusal. This is a
   malformed-artifact proof failure, not a reproduced well-formed source
   program miscompile.

The first two fixes belong to root/B2 as assigned by the root agent; the body
association fix also belongs to B2. All reproductions are in
`src/review_runtime_contracts.zig`. The expected-rejection tests intentionally
fail on the reviewed source. The final case also asserts the corrected-ID
control returns null before checking the rejected wrong-ID result.

## Reproduction receipts

```
export TMPDIR="$PWD/.tmp/review"
export ZIG_GLOBAL_CACHE_DIR="$PWD/.tmp/review-global"
export ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/review-local"
scripts/build-slot.sh build zig test src/review_runtime_contracts.zig \
  --test-filter 'review:' --cache-dir .tmp/review-local
```

Initial `.tmp/review/contracts.log`: three expected-error failures because
the APIs accepted the contradictory inputs. Final
`.tmp/review/contracts-with-proof.log`: four failed, zero passed/skipped,
including the wrong-ID readonly authority demonstration. These are fault
reproductions, not acceptance results. The direct standalone Zig test did not
exercise a Guardian gate; no task-specific Guardian entry is needed here.

## Reviewed authority and ownership boundaries

- `qbe_rc_fresh_root.zig:90` refuses every nonempty packed payload, so an
  ordinary shared static list cannot be proved a sole-owned fresh root.
- `rc_immortal_certificate.zig` safe/construct admits the managed bytes/u8
  family only; `rc_borrow_certificate.zig` frozen construction admits bytes
  and str only. Packed lists cannot receive either alternate physical ABI,
  including evaluations that clone into an arena.
- Static-list ordinary heap evaluations keep the immutable shared image;
  arena/legacy evaluations clone into their creation region. First detach
  lazily registers the builtin list module before allocation/clone work.
  The retained RC/GC/stress/stats/release guests, older-root refusal and
  native refusal tests support this boundary.
- The new image emitter retains O versus H distinctions, sends live H views
  and unique/finalizing bodies to generic plans, and bounds optional flat
  inspection/depth/leaf/offset work with the same native refusal policy.
  Runtime admission stages per-heap bindings, index growth and walk frames
  before publication. Existing tests cover six host allocation and six
  budget refusals, two independent heaps, ID/hash fallback, temporary
  dynamic H imports, copied private bindings and unique inline drop depth.
- Primitive/domain list packing checks exact typed constant nodes and
  native stride. Text/bytes framing checks count, truncation, trailing
  octets and valid scalar UTF-8; source scalar domains retain exact bits.
- Child literals and parent list markers are emitted through canonical
  sorted pools and retained in stored-unit facts. Retained strict module
  oracles compare two modules/all twelve units and metadata; the additional
  combined guest reads an indexed immutable child after parent detachment.
- Tail sharing flattens the owner to one hop, keeps the 8/9-octet boundary
  and region/u32 guards, and leaves bounded slice/split policy separate.
  Static literal positions use an image-owned const member and a read-only
  lookup path; their immortal common prefix remains 16 bytes under ABI4.

No further actionable defect was found in those reviewed paths. This review
does not replace the pending frozen combined B3 acceptance. It did not add
new executable combinations beyond the malformed contracts or exhaustively
fault-inject every generated image topology and mixed projection. Large
descriptor offsets, nested conditional variants, live-view images, exported
templates and transitive artifact conflicts still rely on existing focused
receipts and the integrator's combined gates.
