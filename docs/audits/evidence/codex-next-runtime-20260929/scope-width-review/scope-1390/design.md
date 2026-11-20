# ABI5 scope executable review design

Owned review worktree starts at c435008b30d719331be6fd0998c3bec8aab2c427. No builds/execution before tooling commits/finalizes ABI5 source; source will then be pinned to that exact checkpoint. Module-admission original/intermediate/final receipts remain in the separate untouched runtime-review worktree.

`src/review_scope_emit.zig` invokes production `qbe_rc_scope_inline.begin`, `pin`, and `end` directly with a minimal writer and `.rc` mode. It writes two executable QBE functions; no hand-transcribed count instructions. Frozen QBE assembles those functions and the C driver links frozen runtime sources. Link wrapping counts the native scope fallbacks, so successful cases must prove fast emitted pin/end actually ran.

Seven success cases: H crosses UINT32_MAX; O/H above UINT32_MAX; O exactly2^32 with H0 (low-word-zero end guard); O0/H2^32 (nonfinal hold-only); O=UINT64_MAX/H=UINT64_MAX-1; wide backing counts; near-max backing counts with prior pin. Each checks exact O/H values after pin and end, preservation of pin and journal bits, +40/-40 journal accounting, spare return, scope linkage/region and absence of native fallback. Artificial token states are normalized before ordinary cleanup.

Three refusal cases: payload H=UINT64_MAX, backing H=UINT64_MAX, and backing maximum while payload was already pinned. Native slow path must map to R_REFERENCE_COUNT_LIMIT, preserve count/header bytes, prior pins, journal, spare count and budget; emitted scope end must unlink the empty scope cleanly. A real O1/H0 owner-to-hold transition then exercises O0/H1 final retirement through native end, with actual live header/backing retirement. An ABI4 module registration verifies structured rejection before metadata mutation.

Static review will enumerate ABI propagation/rejection and verify the 16-byte immortal/GC/arena common prefix, 32-byte counted prefix, full-width O/H union and retired pointer use only after DYING. It will distinguish boolean/region/journal fields that remain w/32 from actual count instructions. No broad gates or timing.
