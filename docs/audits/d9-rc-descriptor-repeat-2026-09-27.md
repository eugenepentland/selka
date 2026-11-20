# Stage 4: repeated scalar descriptor identity

The final change caches one successful descriptor identity for scalar append
readiness. General `myl_rc_descriptor_find`, native loan/retain bridges and
release walkers retain their original lookup path. The earlier experiment that
cached every descriptor lookup is rejected: it sped up append and sieve but
regressed schematic by 2.3–4.0% and LLVM allocation churn by 1.9%.

## Proof and final scope

The parent and collections worker reviewed the
[initial design](d9-rc-descriptor-repeat-plan-2026-09-27.md), its concrete global
diff, and the narrowed version. The final production changes are confined to
`native_rc_shapes.c`, `native_rc_internal.h`, and one call in
`myl_rc_list_plain_ready`. No public ABI, compiler emission, type admission,
allocator policy, counter event or budget changes are introduced.

The 40-byte private index entry had four padding bytes at offset 36. Only entry
zero uses their named word as descriptor-slot-plus-one. Every hit first checks
current capacity, then the exact key and descriptor kind. A miss uses the
original hash index; only successful, fully published identities are cached.
Unencodable indexes keep the general path. Growth clears each copied hint;
failed growth preserves the old table. Inserting at slot zero can harmlessly
evict the hint. Bindings stay immutable until heap destruction, and the cache
is freed with the index. There is no global state or cache surviving heap reuse.

This memoizes identity only. Scalar kind/size, actual flat zero-edge admission,
and the live dead queue are checked on every append. Region, generation,
capacity, cold registration, alias staging and generic fallback remain intact.
The general lookup neither pays for nor evicts this optional hint. The helper
is serial private runtime state; it makes no concurrency guarantee.

Compile-time assertions and before/after layout probes preserve index 40,
state 128 (counting 224), binding 128 and heap 5648 bytes. No metadata reservation
size changes. A source-wide audit found no hash, equality or serialization that
uses the former padding as semantic entry data.

## Matched experiments

Both experiments use frozen joined source
`d1d8b3c46ac41e832410a03aad49a5a6a1a54b07`, Debug compiler SHA256
`12a3693929913d50385248a5938fcf57694de8a3538e65f150432c998936d268`.
The rejected global compiler is
`2643cd1f7531cd878756a1d92707d19bed6cf97d53c233388d71874097ddc8ab`;
final private-readiness compiler is
`5feaa5e0d45f60345dc97bf3e17d8c45e2e2ab73e851ea8558646522570a223f`.
All are immutable separate Debug installations. The final experiment reuses the
identical control binaries from the first experiment and takes fresh interleaved
before/after median-three samples on CPU 2. Actual manifests identify QBE and
LLVM O3/full LTO. Inputs are unchanged full-size parity programs and the three
existing schematic fixtures; no workload reduction or presizing is used.

| Workload | Backend | Control instructions | Final instructions | Final/control | Rejected global/control |
| --- | --- | ---: | ---: | ---: | ---: |
| parity/suite/sieve | QBE | 6,370,939,561 | 6,170,940,090 | 0.968608 | 0.968608 |
| parity/suite/sieve | LLVM | 3,409,447,180 | 3,069,447,191 | 0.900277 | 0.900277 |
| parity/micro/alloc_churn | QBE | 8,144,232,357 | 8,014,232,441 | 0.984038 | 0.997300 |
| parity/micro/alloc_churn | LLVM | 5,356,233,159 | 5,296,233,252 | 0.988798 | 1.019417 |
| parity/micro/list_append_sum | QBE | 2,678,577,650 | 2,518,577,537 | 0.940267 | 0.940267 |
| parity/micro/list_append_sum | LLVM | 1,350,706,762 | 1,222,706,813 | 0.905235 | 0.905235 |
| schematic/fixture | QBE | 337,369,995 | 334,082,950 | 0.990257 | 1.023991 |
| schematic/fixture | LLVM | 245,913,173 | 247,915,988 | 1.008144 | 1.040403 |
| schematic/changed-net | QBE | 337,009,876 | 335,832,313 | 0.996506 | 1.025734 |
| schematic/changed-net | LLVM | 245,713,563 | 245,670,072 | 0.999823 | 1.022943 |
| schematic/changed-value | QBE | 336,114,526 | 334,781,337 | 0.996034 | 1.025785 |
| schematic/changed-value | LLVM | 247,337,949 | 245,639,113 | 0.993132 | 1.032126 |

The retained candidate reduces append instructions by 6.0% QBE / 9.5% LLVM,
sieve by 3.1% / 10.0%, and allocation churn by 1.6% / 1.1%. Schematic is near
neutral, including a 0.8% LLVM fixture regression; no schematic gain is claimed.
The global variant's negative results are retained, not blended into the final
medians. These measurements do not establish Stage 4 acceptance or change its
thresholds. Broader native-bridge cache reuse is deferred.

Each experiment contains 32 binary records, 72 production samples and 24
separate counted executions. The final experiment builds 16 candidate binaries
and reuses 16 authenticated control binaries. All relevant CPU-core instruction
events ran 100%; the inactive hybrid CPU-atom PMU reports `<not counted>` and is
not a measured sample. Complete counter records match before/after, including
allocation/retirement, O/H traffic, limits, clones and uniqueness. Every run
checks exact text or expected schematic SVG. Complete emitted JSON is identical
before/after for every build key. Slight non-target changes are reported as
observations, not attributed to any untraced hashing or layout effect.

## Correctness controls

Both old and new registries pass the same ASan/UBSan/counting controls: 25 core,
42 history, 14 loan, 42 collections, 10 arena and 12 held-view scenarios. New tests
cover slot zero, deliberate collision chains, same-key wrong-kind hints,
maximum-width out-of-range hints, empty tables, negative/null lookup, repeated
exact growth refusal followed by retry, stable binding addresses, two heaps
using the same native type with different finalizers, and same-address heap
reinitialization. Existing registering finalizer/retirement controls exercise
reentry and index relocation. The final tests exercise the private query; the
old-runtime build maps it to the original authoritative lookup.

The pending-death append fixture now warms scalar identity before queueing its
finalizer. The generic path still lets the callback observe old length and alter
an aliased scalar source only after staging. Existing unique/finalized metadata,
region, cold/budget and dynamic count-limit controls remain unchanged.

Each experiment also passes 188 uncached actual guest assertions: 47 per compiler
and backend across append, semantic history, dictionary views, aggregate values
and iteration identity. The final focused Debug wrapper passes 12/12 (one named
contract case plus 11 mandatory unnamed blocks). Guardian 88 passes the Debug
build without ratchet edits. The focused runner exits 0 and reports PASS but
also prints Zig's misleading `failed command` diagnostic; the full raw log is
retained rather than hiding it.

## Evidence

[The archive](../../experiments/d9-rc-descriptor-repeat-20260927/README.md)
contains both source patches, exact executed drivers, complete manifests,
compiler/binary/input hashes, all raw counter observations, paired guest results,
layout and sanitizer logs, and final SVG identity checks. An initial archive
verifier incorrectly required the inactive atom PMU to count; its failure log
is preserved, and the corrected verifier checks the pinned CPU-core event.
No compiler/runtime defect or invalid measurement was hidden by that correction.
