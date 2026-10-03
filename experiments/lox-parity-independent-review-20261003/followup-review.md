# Follow-up: positive-index CFG refusal repair

The exact candidate in `followup-review.json` resolves the original finding in
`review.md`. This independent review inspected the patch, synthetic regression,
current opcode model and edge enumerations. It made no compiler/source edits,
ran no tests or performance measurements, and preserves the initial review as
historical. Final author commit identity is recorded separately once available;
the reviewed source content is identified by SHA256 rather than a moving
worktree HEAD.

**Result: pass**, with the validated-bytecode/native-layout and existing
ownership-proof limits from the original review. No further current explicit
CFG edge omission was found.

## Fix and regression

`qbe_positive_index.extraEntry` now uses
`ownership_sources.branchTargets` for ordinary jumps, conditional jumps and
`try_result.error_target`. Variant arms remain explicitly scanned. The only
allowed incoming edge to `start + 9` is from PC `start + 3`; the preceding
`normalizer` check already requires that PC to be the canonical
`jump_if_false` with precisely that target. The helper is exposed for direct
proof regression testing, without any new guest behavior or accepted syntax.

The synthetic regression tests a canonical-only control, forward and backward
`try_result` edges into the exempt join, ordinary/conditional jump entries,
and a nonfirst switch arm entering the join. Negative controls place the
propagation/switch targets outside that join. The `try_result` fixtures carry
artificial types because they isolate the edge helper rather than claim a
well-typed runnable program; this is appropriate to the original generic
refusal omission. Existing emission/native tests continue to check the whole
certificate and normalizer behavior. The change does not alter the signed
proof, payload operation, ownership protocol, canonical fallback, or field
inout implementation.

## Complete current edge inventory

The instruction union in `bytecode_model.zig`, `bytecode.validateFlow`,
`qbe.collectBranchTargets`, and `ownership_sources.branchTargets` agree on
these explicit same-function PC destinations:

| Opcode | Explicit destinations | Certificate treatment |
| --- | --- | --- |
| `jump` | one target | shared helper; only canonical source PC exempt |
| `jump_if_false` | one target and ordinary fallthrough | shared helper; only canonical source PC exempt |
| `try_result` | error target and success fallthrough | shared helper; extra join entry refused |
| `switch_variant` | every arm target | explicit arm scan; every extra join entry refused |

Every other interior PC retains the original `isBranchTarget` refusal.
Fallthrough can enter the final join only from the normalizer's own preceding
instruction, whose opcode is fixed by the pattern. External entries at the
normalizer's beginning use the original body and are not interior entries.
Calls return to their ordinary continuation; `ret` and native failure/unwind
paths do not add an instruction target inside the normalizer. In particular,
`try_result` covers both Result and Option propagation at the opcode level.

Generated COW entries are a separate mechanism, refused by the existing
`quiet` checks for loop entries, scopes, fill/share/unique work and actual
release edges. Versioned/check-free loop bodies retain the original
`version`/`original` refusal. The closed-field interval checker already uses
shared branch destinations plus variant arms and explicitly refuses
`try_result` inside the interval; the field-inout refinement further requires
a straight interval. It needs no analogous repair.

## Qualification provenance

`followup-author-checks.json` is an immutable copy of the author's receipt,
SHA256 `e2f259fe50a78a5c690449ff8e2cbd43f5969ddf0fd0d46b3bdefd75a487a7bc`.
It reports focused process exit **0**, **27 passed / 0 failed**, including
positive-index and native field lifecycle tests, and a separate whole-tree
Guardian run with **88 checks** and exit **0**. The reported test count is 15
named plus 12 mandatory unnamed blocks.

The inspected log contains a misleading `failed command` footer following its
passing test result. The author supplied the completed tool session's exit
status and documented the reporter footer in that receipt. The earlier
`followup-candidate.json` observation retains this initial status uncertainty;
the final follow-up resolves it without editing the log or historical review.
The log hash is unchanged. These are reviewed author qualification records,
not tests independently rerun by this reviewer. Release compiler builds and
guest identity replay belong to the author/coordinator, and are outside this
source-review result.
