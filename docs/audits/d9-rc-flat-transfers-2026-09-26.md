# D9 WP-4: bounded flat aggregate transfers

The production binary-tree metadata has a 16-byte record with ordinary RC
pointer leaves at offsets 0 and 8. Its boxed body wraps that record in one
field. Generic copy/take still interpreted both shapes after the pointer and
small-stack fast paths, so this slice caches their unconditional leaf offsets
once during registration.

The cache is private: every copied descriptor is the prefix of an immutable
binding containing at most eight offsets. The existing public descriptor,
shape/module ABI, native heap prefixes and generated-call ABI do not change.
Each binding reserves 72 additional bytes in the same checked/budgeted atomic
registration allocation. Index values still point to public descriptor prefixes;
no pointer into a resizable index is retained.

Admission checks both the full native type and the authoritative RC shape.
Plain/float leaves are empty, ordinary pointers are terminal, and records/arrays
match child layout and extent. Hold pointers, variants, raw resources, owned
buffers/pools, custom edge/clone/finalizer adapters, overlapping physical leaf
slots and more than eight leaves decline. Inspection itself is bounded to 16
inline frames and 128 steps; deeper/wider metadata keeps the existing unbounded
generic walker. The GC scan plan by itself would be insufficient because its
pointer entries do not distinguish ordinary owners from holds or raw resources.

Copy preflights all leaf payloads and includes repeated aliases when checking
available count space. It changes no owner count before every leaf is admitted.
Pins and younger-arena edges decline to the existing clone/region transaction.
On success each physical heap edge increments O once, with the same counting
hook; same/older arena edges keep the established shared mark. Count-limit
refusal clears the empty output and preserves source bytes/counts without
transient acquisition/rollback traffic. No callback or allocation separates
preflight from publication. Take uses the existing temporary destination,
preserving count-limit-independent token transfer, output refusal atomicity,
self-take and overlap semantics. Overlapping flat copy is declined. Generic
replace, drop and release traversal remain unchanged.

Validation passes all 37 focused RC tests and the production ASan/UBSan suites:
held edges 12, arenas 10, core contracts 19, collections 25, stats 4, and
execution success/trap/fast-exit 3. New cases cover eight repeated aliases at
both sides of the count limit, take at the limit, unchanged caller output on
refusal, scalar-byte preservation/clearing, self/overlapping take, shared pinned
clone memoization, explicit nine-leaf generic fallback, and H/variant/raw-unique
admission refusal. Existing registration-budget rollback and deep/reentrant
fixtures continue to pass. Guardian passes all 88 checks with no ratchet change.

The isolated depth-12 QBE pair uses Debug compilers, identical source/output,
default guest optimization and three interleaved instruction measurements:

| Runtime | Median user instructions |
| --- | ---: |
| Pointer plus small traversal stack | 8,160,503,827 |
| Plus cached flat aggregate transfers | 5,789,852,276 |

That is a 1.409x improvement. Both arms retain exactly 669,060 allocations and
retirements, 3,992,307 owner acquisitions, 4,661,367 releases, zero holds and
zero clones. The scaled GC control remains 105,808,932 instructions; this
isolated runtime change remains roughly 55x that control. It is not WP-4
acceptance. Raw counts, hashes and sampled profile are under
`experiments/d9-rc-flat-transfers-20260926/`. The independent read-only-body and
constructor-take compiler changes were then merged at `2aafa6b1` and measured
against a preserved compiler binary from the constructor-take reference.

| Backend | Read-only bodies + constructor take, before flat | Plus flat | Frozen GC |
| --- | ---: | ---: | ---: |
| QBE | 3,488,667,057 | 2,382,637,927 | 105,808,977 |
| LLVM | 2,467,965,407 | 1,517,873,558 | 50,540,745 |

These are three interleaved instruction medians per arm on the same private
CPU, with Debug compilers and identical depth-12 source. LLVM explicitly uses
`--backend=llvm --llvm-opt=3 --lto`, with no later QBE selection; artifact
manifests confirm the backend and optimization. The GC reference uses the
preserved compiler from the frozen `39f` experiment. The added flat path yields
1.464x QBE and 1.626x LLVM improvements after the compiler changes. Every arm's
stdout matches exactly. Both RC revisions and both backends have identical
complete counters: 669,060 allocations/retirements, 19 owner acquisitions,
669,079 releases, zero holds/clones, and 33 uniqueness checks.

The combined runtimes remain 22.52x QBE and 30.03x LLVM above this scaled GC
control. These results do not satisfy the WP-4 corpus gate. Joined focused RC
validation passes all 37 tests, and the Debug compiler build passes all 88
Guardian checks. `combined.json` preserves all commands, hashes, raw runs and
counters. `combined-profile.txt` is a short sampled QBE profile (about 150
samples); its proportions are directional, not exact per-operation costs.
