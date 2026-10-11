# Scalar stream output — 2026-10-11

The selected schema 10 body checker now prints every integer width and the
retained floating type through the existing native output contract. The harness
pins exact stdout for signed minima, unsigned maxima, finite and special floats,
and mixed arguments with explicit separators and terminators. Capability and
keyword type diagnostics remain native-equivalent. Aggregate output still has
an explicit profile-refusal control in this slice.

The installed producer passed 481 workflows and 962 comparisons in each of the
normal and release/facts/leak modes, with zero failures or skips. Each mode also
passed 30 warm deployment checks, four live session checks, 92 forged-reply
refusals, the valid/malformed transport suite, and both publication controls.
The 21 focused producer tests passed in both modes; all 103 body harness
self-tests and all 88 whole-tree Guardian checks passed.

The [receipt](evidence/selka-stream-scalars-20261011/receipt.json) binds the source,
all 177 fixtures, seven installed packages, unchanged qualified seed, and native
host. It retains an earlyoom-terminated first release attempt, the successful
retry, and both incorrect preliminary mixed-output fixtures (an overflowing
untyped constructor argument and a context-free None). The final mixed fixture
uses an explicitly typed u64 and a Unit-returning helper.

Dedicated qualification omits coordinator edit verification; the full repository
gate owns that check and remains outstanding for final integration. This slice
claims neither full compiler bootstrap nor the 1.5× performance acceptance.
