# Track 3 handoff: owned keyed sorting

Implemented in `src/core/runtime/core_sort.c`, based on
`399013af36d41b78610e5ede22a9102ec5b17ffe`. The commit identity is supplied in the
parent handoff message. No shared lowering, ownership passes, headers, build
registrations or canonical benchmark sources were changed.

Owned keyed elements wider than eight bytes and lists longer than one element
now gather into raw temporary storage, then move their bytes back into the same
managed allocation. Scalars keep permutation cycles. The source-supported
hypothesis is that sequential traversal and fewer record copies improve the
checked record-sort path. There is no sampled CPU attribution or timing result
in this track; adoption remains conditional on the parent's combined paired
runtime and RSS measurements.

Stable duplicate ordering, reverse, numeric/string/tuple/float keys and all
existing shape engines are preserved. Compiler key evaluation remains unchanged:
once per input element, in input order, before the runtime helper. The list's
identity, capacity and child-reference multiset are preserved. Temporary raw
bytes are never a managed owner and are freed without dropping children.
Managed keys are dropped once after moving records back. Optional scratch
allocation failure uses the existing direct-owned permutation engine. An
impossible byte product rejects invalid metadata before scanning it. Sort-engine
failure frees raw scratch before dropping keys and applying the existing fatal
failure policy. No RC/COW fallback or lifetime syntax was introduced.

## Validation and artifacts

- Guardian: **88 checks passed**, diff scoped against
  `fbfcaa7a923186a8e773c3760f81c10aa345a432`; not a full-tree gate.
- Registered selected core tests: **3/3 passed**. Existing A08 keyed ownership
  coverage plus the new wide managed fixture and native allocation injection.
- New guest regression passed all five modes: unoptimized, release, verified
  release, optimized debug, release without facts. It checks 97 independently
  owned records carrying text/bytes/nested-list children, stable duplicates,
  ascending/reverse numeric/text/tuple/float keys, independent sorted outputs,
  empty/singleton, emitted zero-RC code, zero exit-live bytes and zero RC events.
- Native injection checks exactly one scratch malloc request per wide sort,
  success/refusal ascending and reverse, stable child identity, original list
  identity/capacity, final `live_count()==0`, and fatal rejection of an impossible
  storage product before reading fabricated metadata.
- Canonical qualification: **8/8 passed** (both sorts, both sizes, runtime/count
  builds), independent Python checksums, owned helper in LLVM, known forbidden RC
  symbols absent in native definitions, zero counted RC and exit-live bytes.
- Frozen before/candidate after: all four complete managed counter-total vectors
  are **exactly equal** for identical three-iteration workloads. Clocks from these
  qualification runs were discarded.

| Case | Size | Iterations | Checksum | Managed allocations | Cumulative managed bytes | Managed peak bytes | Additional raw malloc/free pairs | Additional raw bytes per sort |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| sort_int | 64 | 3 | 3675360 | 14 | 3040 | 1792 | 0 | 0 |
| sort_int | 4096 | 3 | 879804490 | 14 | 132096 | 66320 | 0 | 0 |
| sort_records | 64 | 3 | 49543968 | 23 | 14320 | 4976 | 3 | 1536 |
| sort_records | 4096 | 3 | 173812878 | 23 | 820776 | 263040 | 3 | 98304 |

Raw scratch counts/byte requests are source-derived and supported by the native
one-request injection assertion. Managed counters exclude them. Record scratch
requests total 4608/294912 bytes over the three small/large qualification
iterations, with one buffer live per sort, excluding allocator overhead. No
result capacity is shrunk. Process RSS and runtime remain unmeasured here.

Complete candidate package:
`/home/epentland/ai/canopy/mylang-micro-gaps-20261012-sort/.tmp/micro-gaps/sort/candidate-install`.
Host SHA256:
`748e378a3e4003410d1d65f5eff1cfad68513bbd39a0c7bbaec54209d6e0aaf4`.
The host and core-test binary embed the exact final `core_sort.c` bytes
(SHA256 `296372f21bd56e5b537fbe183e048a6142fd07ad8b57e3be6f1b7905ee958712`).
Build: pinned Zig, `seed-compiler core-test-binary -j4 -Doptimize=Debug`, filter
`keyed sorting`, shared admission, private outputs. Guest builds use release,
checked zero-RC, `MYLANG_JOBS=4`, and the canonical native clock.

The complete frozen qualified installation was copied, and only its copied host
was replaced; every libexec/tools file is byte-identical and individually pinned
in `evidence/install-identity.json`. Fresh component provisioning encountered
missing native-link object files; no seed source or pin was changed. Frozen host
SHA256 remains
`8e58720cd72de8632aa48df373d18fc8238d46ec27010f8b182820a0eaaf10fa`.
Initial duplicate spec tags, a borrowed-element fixture local and macro warnings
were corrected before the final green run. Failed logs remain under private
`.tmp/micro-gaps/sort/`; frozen evidence was not overwritten.

Qualified runtime binary:
`.tmp/micro-gaps/sort/qualified/collections`, SHA256
`e945ee88cb0b15088e1218718557014ccca490f644eef50a393afd5bbf8f9d78`.
Counted binary:
`.tmp/micro-gaps/sort/qualified/collections-counted`, SHA256
`eb037620fcd30bee72dd0cab3110d34ad255baa4749aa33e1e9f836651901ad3`.
The frozen counted guest is independently pinned in
`evidence/counter-comparison.json`. Evidence includes all eight raw before/after
counter JSON files, exact qualification commands, native/LLVM/source hashes,
Guardian/test logs and a SHA256 index. No timing samples were generated, and
stored micro-ownership baselines retain their original identities.

Owned code files: runtime helper, `s3_list_methods_test.zig`,
`gap_sort_fixture.my`, `gap_sort_failure_fixture.c`. Experiment-only files:
README, qualifier, handoff and evidence. The parent owns integrated gate,
paired timings/RSS and the final performance decision. Guardian feedback was not
appended, as requested by the global AGENTS instruction.
