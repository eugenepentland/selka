# D9 WP-4: direct completed-constructor publication

Copyable record and variant constructors now publish their completed value
directly into the vacated stable operand slot. The internal partial-body guard
remains live until the complete result's typed operand guard is initialized.
This removes the completed result's intermediate pending-work copy and journal
publication, and the repeated drops of already-consumed constructor operands.
It changes neither the public runtime ABI nor the frame layout.

Every field still uses the existing pin-aware, region-aware transfer. An owned
input clears its source guard only after success; a borrowed input starts with
a clear guard; an H input converts through the existing typed operation and
releases its former hold after success. Field initialization then clears the
pending guard after publishing into the protected partial body. Therefore all
consumed input guards are clear at the final handoff, including reordered
fields and aliased payloads. Aggregate scratch and fresh heap bodies are
distinct from the stable operand slots that receive their completed values.

The final handoff contains only value and journal stores: it publishes the
complete typed operand before clearing the internal guard and cannot call out
or fail. A payload-less copyable variant has no partial owning fields to
protect, so it skips the partial-body journal but still publishes an initialized
typed operand, preserving the producer-ownership proof even for null pointers.
Move-only constructors retain the prior finalization path. Live-view
constructors retain their separate H-producing lowering. Partial failure,
unique finalizers, pin cloning, arena escape, and error-trace recording retain
their existing operations.

The change is deliberately limited to completed constructors. Fields still
stage through pending storage, and updates still prepare replacement ownership
before releasing the old value. Further coalescing needs its own proof.

## Private instruction measurement

The before source is `6f7a3a94`, which includes `ec81fe6f` region caching,
stable journal metadata and plain list writes. Both compilers are Debug. The
same n12 source is built with default QBE and LLVM O3/full LTO; manifests are
checked. Three interleaved CPU-0 retired-user-instruction measurements yield:

| Backend | Before | Direct publication | Before / after |
| --- | ---: | ---: | ---: |
| QBE | 1,142,675,865 | 1,131,453,274 | 1.00992 |
| LLVM | 673,069,058 | 656,211,070 | 1.02569 |

Output and the complete counter record are unchanged on both backends:
669,060 allocations/retirements, 19 owner acquisitions, 669,079 releases,
zero holds/clones, and 33 uniqueness checks. The improvement is modest; it does
not close the previously measured order-of-magnitude gap and is not WP-4
corpus acceptance. Raw measurements, commands and hashes are retained under
`experiments/d9-rc-constructor-publication-20260926`.

## Validation and separate parity finding

The initial candidate passed 102 actual RC guest cases per backend across 15
files, 44 focused RC Zig/C tests, and Guardian's 88 checks. Production counting
drivers also passed 15 aggregate cases and all 16 optional-layout cases per
backend, including the formerly excluded escaped optional graph. A real
33-frame assertion trap retired all 132 allocations on each backend; all these
drivers checked owner and hold balance.

A new direct `view.mapping`-into-record fixture exposes a separate GC/RC
snapshot discrepancy that predates this slice. The accepted `f6bea5d9` GC
compiler and the before compiler both let the projected record dictionary
field change along with its original dictionary; RC preserves that ordinary
snapshot. This is unresolved parity triage, not an accepted difference or a
failure caused by direct completed-result publication. The exact source,
accepted compiler hash and observed values are preserved separately. The
isolated constructor regression retains an explicit named ordinary snapshot,
so it tests nested H fields and H-to-O input conversion without depending on
the unresolved GC marking behavior.

Guardian caught a third repeated import string during implementation; it was
replaced by a shared import constant. No rules, ratchets or gate requirements
changed. The parent owns final joined validation and the serialized Guardian
feedback entry.
