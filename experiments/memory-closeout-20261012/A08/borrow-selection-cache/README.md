# Pending borrowed-selection cache qualification

This fixture is prepared for A07's `myl_core_borrow_select_v1_` implementation.
It has not yet been executed. Expected stdout is `3 2\n1 3\n`.

The final compiler must qualify cold, warm, receipt/replay, source relocation,
and an earlier record/function discovery edit with the same output. Both owners
are changed after the borrowed calls complete. Separate negative cases must keep
a selection live while either input owner is invalidated, and must preserve the
same refusal with a populated cache.

Malformed stored-marker tests must exercise the common optimization-cache restore
boundary, including final/debug artifacts that bypass ownership on a hit. Snapshot
basic-index validation alone is insufficient: a type-correct wrong-root phi must
be rejected by the marker proof, classified as a cache miss, and followed by fresh
validation. A malformed fresh marker must explicitly refuse; it must never fall
back to an owning interpretation.

A07 owns the temporarily transferred narrow guard in
`optimization_cache.Context.restore`: validate after snapshot restoration and
before inline ancestry or body identity publication. No-op transform hits retain
the already validated live function and do not deserialize stored IR.

The registered A08 tests now exercise both debug and verified-release cache
replay, earlier physical-type discovery, and persistent debug-artifact rejection
followed by fresh repair. Their first run exposed a test-oracle mistake: literal
slots may reorder on restoration, so body comparisons now use canonical digests.
Those corrected cases pass. A third case swaps a valid selected phi's two incoming
operands while retaining predecessor order; it exposed missing dominance checks
in the local marker proof. The general verifier rejects the resulting wrong-edge
use. The failure is retained in `predecessor-proof-failure.log`; A07's separate
always-on marker wrapper is the required production fix. After integrating it, all four selected assertions passed but the backing allocator
reported 192 leaked compiler scratch allocations. A07 isolated the verifier tables
in a temporary arena; the follow-up suite passes without leaks. Both defects and
their intermediate logs remain in this record. Final commands and identities are
recorded in `results.json`.

`../borrowed_cache.py` prepares twelve additional native command rows with exact
compiler/source identities. Its Python help check passes; it has not executed a
compiler. A CLI receipt replay does not replace the malformed IR artifact tests.
