# Isolated C3 text-runtime patch

`core-text-C3.patch` is prepared against integration commit
`c749ad5a9d2dfef5d5c4d7b9de2a30f03029999f`. Only
`src/core/runtime/core_text.c` changes. The patch passes `git apply --check`
against a private copy of that exact committed file; `manifest.json` pins its
before/after hashes. Active production code remains unchanged. No retirement or
native qualification is claimed by preparing this patch.

The patch removes two legacy alternatives: the append-time reference-count
uniqueness test and encoding's retained text alias. Existing checked behavior
becomes unconditional: mutation copies static storage first, and encoding
returns independently owned bytes with the bytes kind. Two comments lose obsolete
shared/one-count wording. Text/UTF-8 lengths, scalar counts, capacity growth,
hash/cursor caches, allocation counters and owned allocation remain valid.

The shared cache predicate `core_text_can_cache`, static-storage layout and
`myl_core_owned_octets_copy` live in `core_rt.c`, owned by A02/coordinator. Their
selected count-free contracts must remain intact when surrounding RC helpers
are removed. This patch neither redefines them nor changes synchronization.
The `retain` wording near sliced bounds describes preservation of logical
length, not memory reference counting; the borrowed-span comment explicitly
states that it contains no reference count and remains accurate.

Apply only during coordinator-authorized C3 activation after default promotion
qualifies and the count-free runtime/header is selected. Requalify the A04 public
export matrix, text/bytes/static-append/encode independence and view negatives,
repetition/rendering/formatting, A06 applications, and final structural LLVM and
symbol audits. Full registered verification and Guardian are still required on
the actual retirement candidate. This isolated patch supersedes only the
`core_text.c` portion of the older multi-file retirement draft; that older draft
is preserved as historical preparation.
