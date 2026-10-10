# Packed stage cache: compression isolation and remaining work

This experiment compares the same compiler executable with
`MYLANG_STAGE_CACHE_COMPRESSION=zlib` (default) and `none`. Both variants retain
the frontend source-proof improvements, pack grouping, validation, cache keys,
and conservative dependency rules. Guest builds use optimized debug mode;
the runtime remains at O2. The new diagnostic policy affects new writes only:
either policy can read either existing encoding.

## Results

Incremental wall time: median of three fresh edits, with observed ranges in
parentheses. Disabling compression reduced the medians by 6.7–23.7%; individual
pairs were noisy on the shared host. Both policies performed identical work.

| Lines | Edit | Compressed, seconds | Uncompressed, seconds | Time change |
| --- | --- | ---: | ---: | ---: |
| 191,416 | Entry | 4.119 (4.113–4.659) | 3.725 (3.481–4.390) | −9.6% |
| 191,416 | Helper | 3.730 (2.988–3.883) | 3.133 (2.718–3.235) | −16.0% |
| 191,416 | Three files | 4.835 (4.624–5.454) | 4.457 (3.955–5.095) | −7.8% |
| 510,436 | Entry | 9.925 (8.228–12.012) | 7.572 (7.152–9.759) | −23.7% |
| 510,436 | Helper | 7.051 (6.914–8.046) | 6.581 (6.226–10.474) | −6.7% |
| 510,436 | Three files | 10.359 (9.804–13.666) | 8.998 (8.594–10.911) | −13.1% |

Every uncompressed edit sample stayed below 10.92 seconds. This is observed
behavior for the specified edits on reachable replicas, not a general bound
for every 500k-line application or edit.

Uncompressed incremental median peak RSS was 0.496–0.500 GiB at 191k lines and
1.295–1.300 GiB at 510k lines, essentially unchanged from compression. The helper
optimizer-stage median fell from 1.701 to 1.215 seconds at 191k lines. This stage
includes cache replay, so these savings do not imply less optimization work.

Allocated cache space after one build, before edits or revision history:

| Lines | Compressed | Uncompressed | Compression saving | Files, either policy |
| --- | ---: | ---: | ---: | ---: |
| 191,416 | 0.379 GiB | 1.011 GiB | 62.46% | 15,924 |
| 510,436 | 1.007 GiB | 2.692 GiB | 62.57% | 42,362 |

These are total project and native caches; the initial native seed contains
exactly the required validated units. Packing retains its file-count benefit
with either policy. Compression affects stored byte counts, not pack grouping
or compilation invalidation. See [summary.json](summary.json) for exact bytes,
component sizes, memory, stage times and work counters, and
[paired-raw.json.gz](paired-raw.json.gz) for all original measurements.

## Validation

- 40 builds passed execution, EDA golden-output and leak checks.
- All 20 paired executables were byte-for-byte identical. Native instruction,
  literal, debug, trap and executable-section audits also passed.
- All 20 pairs had identical frontend, lowering, optimizer and emission work
  counters. No eager fallback occurred during edited builds.
- [block-audit.json](block-audit.json) confirms zero compressed blocks in the
  uncompressed caches: 2,502 raw blocks at 191k lines and 6,606 at 510k lines
  after all edits. Record counts and unencoded byte totals match the compressed
  variants. These post-edit counts are separate from the one-build size table.
- 17 focused storage tests, one CLI configuration test, formatting checks and
  all 88 Guardian checks passed. Logs are archived here; their source hashes
  are listed in [validation-logs.json](validation-logs.json). The CLI test
  command exited zero despite Zig's stale `failed command` footer after PASS.

Both policies used compiler executable SHA-256
`9f35cb593fbd808861dc1526df6d5a041c33a53c4ab61908b5dfedc1cab3331c`.
The default remains compressed. Switching the policy does not rewrite existing
cache blocks; this comparison used separate fresh caches to isolate it.

## Method

- Reachable EDA replicas: 191,416 and 510,436 physical source lines.
- Separate fresh intermediate caches; identical source paths and edits.
- Native seeds contain exactly the validated objects required by the original
  source revision. Setup must reuse every seeded unit and compile zero units.
  Setup timing is therefore **not a fully cold build**.
- Cache allocation is measured after setup, before any edits. It includes the
  frontend, stage, build-replay, and native caches, including directory blocks;
  it excludes source files, output programs and measurement logs.
- Three fresh, length-changing edits per scenario, alternating policy order:
  an entry string, a helper body, and three files. Medians and all samples are
  retained. Four logical CPUs (2, 3, 10, 11) are reserved through timing locks.
  The host remains shared, so wall times are measurements, not precise bounds.
- Every build runs the program with leak checking, verifies EDA golden outputs,
  and compares paired native code/debug information and executable sections.
- Peak RSS is GNU time's maximum process RSS, not the sum of concurrent workers.
- `block_audit.py` independently inspects every pack's encoding markers after
  the edits. Compiler reads and focused tests validate checksums and payloads.

Reproduction (paths for this host):

```bash
flock /run/user/1000/mylang-slots/cpu2.lock \
flock /run/user/1000/mylang-slots/cpu10.lock \
taskset -c 2,3,10,11 \
python3 experiments/checkpoint-reuse-20261009/compare.py \
  --baseline /home/epentland/ai/canopy/mylang-frontend-packed-20261010/compiler-policy/bin/mylang \
  --candidate /home/epentland/ai/canopy/mylang-frontend-packed-20261010/compiler-policy/bin/mylang \
  --baseline-cache-compression zlib --candidate-cache-compression none \
  --capture-setup-cache \
  --native-seed /home/epentland/.cache/mylang-incremental-stages-20261009/scaling-complete \
  --output /home/epentland/ai/canopy/mylang-frontend-packed-20261010/paired-raw \
  --copies 12 32 --repeats 3
```

## Work audit

`frontend_audit.py` and `work_audit.py` reproduce the detailed work attribution
from the uncompressed candidate in this paired benchmark.
They distinguish fresh work from cached-body replay and function bodies from
source modules. Source/archive/object hashes and limitations are in their JSON
outputs. ELF paths point to retained host artifacts.

On a helper edit, fresh frontend checks total 649 bodies at 191k lines and 1,729
at 510k lines. One is deliberately edited; 648/1,728 are repeat checks associated
with record-identity and specialization reuse limitations. Existing guards are
necessary for correctness. These are opportunities for safe cache improvements,
not a proven minimal set that can simply be skipped. Distinct source-file counts
for these checked bodies are not currently instrumented.

Only the changed 1/1/3 syntax units are reparsed and 1/1/3 native units compiled.
Fresh raw lowering and final optimizer work also affect 1/1/3 functions, although
some prerequisite optimizer passes perform more work. Raw/final body
materialization (mostly cache restores) still totals 628/807/991 at 191k lines and 1,668/1,847/2,031 at
510k lines for entry/helper/three-file edits.

Native units group functions. A helper edit regenerates 14 emitted guest
functions: 12 retain identical instruction bytes and 2 change (the helper and
its inlined caller). The three-file edit regenerates 31 functions, 27 with
unchanged instruction bytes. Entry edits leave 3 function instruction ranges
unchanged but require changed string data. Byte equality alone is not proof of
full relocation/literal/debug equivalence or safe function-level object reuse.

All imported source files are still read, hashed and header-lexed; declaration
tables and global validations are also repeated. This overhead is distinct from
recompiling native code.
