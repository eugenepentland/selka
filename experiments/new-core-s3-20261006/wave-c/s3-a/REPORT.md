# S3-A: application admission and measurement foundation

Source dependency: `f1319a774d638c664de9f02bb27098650a13249b` (qualified S3-C,
S3-T1 and S3-T2 integration). This checkpoint qualifies application admission,
literal split fidelity and strict native correctness. **It does not qualify
the application performance gate or S3 exit.** Profile-driven repairs follow.

`split_apps.py --check` verifies five saved fixtures against literal helper and
dispatch-body extraction from the unchanged expanded sources. Row selection and
unused setup/helpers are removed; timed algorithms, input distributions and
checksums remain the originals. Rust and Zig reference sources/binaries are
unchanged. `word_count` was built and measured first.

`measure_all40.py` retains the S2 API, registry and timing method, adds five
applications and records separate new/old and new/Zig ratios and misses. Every
native sample requires exit zero, exactly `checksum elapsed_ns\n`, one positive
finite user-cycle counter and consistent checksums across old/new/Rust/Zig.
Three one-iteration startup samples are subtracted from seven shuffled,
interleaved rounds. Both sizes are 4096/64 and each ratio limit is 1.10.
The original 35 row iteration counts, units and reference naming are unchanged.
Application counts for 4096/64 are word_count 400/25000, CSV 40/2500, JSON
20/1250, packet 400/25000 and Lox 40/2500, normalized per dataset element.

The protected old oracle and adjacent QBE were copied from the coordinator's
qualified corrected oracle, not the pre-D2 S2 baseline. Source commit
`65036fe792ef540392d0eb00c41c9ec71c7b2c82`; the corrected ENV-NAMES-GRANT-1 full
old gate qualified this pair. Compiler SHA-256
`d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`; QBE
`b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.
The new compiler was installed from this worktree's source. No copied new binary
or linked old runtime object is used.

All build-heavy runs hold the gate and build slots using the required preserving
shell wrapper. Timing/profile runs also hold
`/run/user/1000/mylang-s2-cpu10.lock`; native perf children use CPU 10 only.
Each command has a unique log. Runtime reference worktrees are preserved.

| Check | Command after slot wrappers | Result and retained evidence |
|---|---|---|
| Own-source installation | `python3 …/wave-a/exclusive_core.py -- /usr/bin/time -f '%e' -o …/logs/core-install-01.time zig build core --summary all` | 3/3 successful; 2.73 s uncontended command time, MaxRSS 374M; `logs/core-install-01.*` |
| Tool syntax and strict parser smoke | `python3 -m py_compile …/{split_apps,measure_all40,qualify_apps}.py`; `measure_all40.py --smoke-test`; `split_apps.py --check` | Registry40/S0 mapping/strict parser/signal-exit checks pass; all five fixtures match extraction |
| Original/split and import qualification | `qualify_apps.py --bin .mylang-cache/s3-a/qualification-01 --evidence …/qualification-01` | 137 native executions; five apps agree with unchanged original-old suites, split old, new debug/release/verify; strict leak/status/stdout checks pass. Unchanged full text entry also reaches strings.repeat and JSON in all three new modes. `qualification-01/summary.json`, per-build command/status logs, `logs/qualification-01.txt` |
| First word row | `flock -x …/mylang-s2-cpu10.lock python3 …/measure_all40.py --build --rows word_count --bin .mylang-cache/s3-a/word-count-01 --json …/word-count-01.json` | Valid and checksum matched, Zig miss at both sizes; `logs/word-count-01.txt` and `word-count-01.json` |
| Other four app rows | Same tool with `--rows csv_aggregate,json_transform,packet_decode,lox_eval --bin .mylang-cache/s3-a/apps-01 --json …/apps-01.json` | All builds/samples valid and checksum matched; Lox passes both gates; other three miss. `logs/apps-01.txt`, `apps-01.json` |
| Miss profiles | Locked CPU10 `perf record -F 997 -e cpu_core/cycles/u -g`; `perf report --stdio --no-children --call-graph none --sort symbol --percent-limit .5` | No lost samples. Compact hotspot reports and separate native record logs retained; binary perf data remains in private `.mylang-cache/s3-a` |

Qualification cases are `(size, iterations, seed)` = `(2,1,7)`, `(64,3,7)`,
`(65,1,17)`, `(4096,1,7)`, `(4100,3,17)`. Each new execution uses
`MYL_CORE_LEAKCHECK=1`. An abnormal status, unexpected stdout or any stderr fails
qualification. The full original text entry additionally runs string_equal and
json_transform at `(64,3,7)` in debug/release/verify mode. Programs use only the
benchmark's linked clock; no filesystem, entropy or network fixture is needed.

## Initial application table and required repairs

Every pair is 4096/64 in user cycles per dataset element.

| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig | Both gates |
|---|---:|---:|---:|---:|---:|---:|---|
| word_count | 291.503 / 376.509 | 98.356 / 112.269 | 59.308 / 66.142 | 47.299 / 51.341 | .337 / .298 | 2.079 / 2.187 | miss |
| csv_aggregate | 4891.612 / 4151.454 | 2006.595 / 1806.958 | 1169.335 / 1058.373 | 1043.786 / 985.930 | .410 / .435 | 1.922 / 1.833 | miss |
| json_transform | 13655.770 / 14018.850 | 3160.786 / 3378.116 | 1780.526 / 1976.507 | 2817.246 / 2846.019 | .231 / .241 | 1.122 / 1.187 | miss |
| packet_decode | 15.529 / 15.074 | 48.339 / 48.973 | 10.277 / 10.667 | 18.937 / 19.452 | 3.113 / 3.249 | 2.553 / 2.518 | miss |
| lox_eval | 629.947 / 659.469 | 206.056 / 214.010 | 165.150 / 171.446 | 504.490 / 521.745 | .327 / .325 | .408 / .410 | pass |

Word profile (741 samples): whitespace split 18.65%, block allocation 17.39%,
string hashing 17.74%, block cleanup 8.96% plus block free 3.27%. Emitted IR has
one dictionary probe per input word; materializing every split piece dominates.
The coordinator authorized generic whitespace cursor fusion, with borrowed
spans for lookup and owned materialization plus same-key reprobe only at insert.
No view may escape or travel through a phi; nonqualifying consumers retain the
materialized implementation.

CSV profile (2K samples): equality 18.76%, append 17.74%, allocation 10.01%,
character creation 8.61%, width 7.00%. Character values have multiple comparison
and append consumers; the existing single-use append fusion cannot cover them.
JSON (1K samples): allocation 15.31%, buffer push 14.08%, read_value 7.81%, block
cleanup 7.61%, read_string 7.50%, byte index offset 6.02%. Packet (4K samples):
byte index offset 55.56%, main 40.59%, error traces 3.85%. Owning-package repairs
are routed through the coordinator. No shared compiler source changed at this
foundation checkpoint.

Inherited compiler correctness at `f1319a77` is the coordinator's qualified
254/254 Core32 gate and full 1518/1518 debug/release strict conformance with zero
mismatch or unsupported test, including leak/fact verification. This checkpoint
adds no compiler or gate-list source, so does not rerun that unchanged proof.
The next compiler source change receives fresh required qualification. Frozen
`ir.zig`, record phi ownership, first-64 aggregate parameter masks and persisted
formats remain unchanged. No main merge or push occurred.

## Retained word fusion prototypes

Release-only private whitespace-split loops now use byte cursors and source-rooted
SSA views when every word use is a dictionary probe or insertion key. The
compiler's split declaration and new cursor helpers use authorized `runtime_c`
linkage, exact signatures, zero ownership/view argument masks. A source extern
lookalike cannot activate fusion. All loop-index/list/word uses are validated
before changing the IR; observable indices, escaped lists/words, ordinary calls
and word phis retain the materialized loop. Insertions explicitly materialize an
owned key and repeat `dict_find` against the same current dictionary/key before
`dict_insert`. No `own.zig` or frozen IR edit is needed.

A generated borrowed-key descriptor probe inlines the existing cached-hash
small-table scan only when the dictionary has no index or deletion bitmap.
Hashing calls the existing Core span hash and mixes its bits identically;
comparison checks byte length then `memcmp`. Indexed/deleted dictionaries retain
the existing runtime span probe and negative insertion-probe semantics. This
helper is emitted only for dictionary types with actual SSA-view probes.

| Prototype | New cycles 4096 / 64 | New/old | New/Zig | Status |
|---|---:|---:|---:|---|
| Cursor and owned-on-insert only | 64.785 / 76.779 | .222 / .203 | 1.368 / 1.512 | both Zig sizes miss |
| Cursor plus inline clean-small span probe | 53.051 / 66.381 | .182 / .176 | 1.118 / 1.302 | both Zig sizes miss |

Every timing uses seven interleaved rounds and three startup samples, strict
four-program output/status/checksum/cycle checks, CPU10 and its shared lock.
`word-count-prototype-01.json` and `word-count-span-03.json` retain raw samples.
The intermediate `word-count-span-02.json` is deliberately invalid: the LLVM
prototype used `%entry` both as a block label and value name. The build rejected
it before any measurement; it was corrected to `%number` and retained unchanged.

Own-source exclusive installation times were 2.86 s (cursor), 1.73 s (span), and
0.88 s (cached installation after the exact-signature authority hook); the latter
follows an actual source compilation performed by the preceding Core test build.
Each build and test has a unique log under `logs/`.

The semantic gate `split-tests-08.txt` passes 3/3 in 3.05 s test wall. Its native
fixture covers all six ASCII whitespace octets, UTF-8 and non-ASCII whitespace,
empty input, managed dictionary returns, an owned temporary input, source
rebinding, break/continue, captured dictionaries, growth beyond eight keys,
deletion fallback, and actual 32-bit hash collisions. The pair
`collision002553`/`collision005a0e` hashes to `ae700d18`; their counts stay distinct.
Five IR near misses and an identical-signature extern-authority near miss are
explicitly checked. `split-qualification-01/summary.json` additionally verifies
identical pinned output, zero exits and empty stderr against the corrected old
oracle and new debug/release/verify, with leakcheck in all new modes.

Failures are retained: the initial list-alias rewrite replaced a forwarding copy
among header phis with an `undef`, violating the phi prefix. The correction keeps
a copy of an out-of-block undef list constant, which stays dead and unowned.
`split-keys-failure-02.ir` preserves the rejected IR. Earlier syntax/prototype
logs remain evidence and are not counted as successful gates.

The post-span profiles retain 1247/1762 samples at sizes 4096/64, zero lost.
Remaining hotspots: scalar dictionary set 21.32%/19.38%, span hash 17.19%/13.64%,
end cursor 9.74%/7.55%, start cursor 6.02%/5.85%, main 28.21%/29.70%. The next
proposed owning-package repair is a typed store for scalar dictionary values;
managed-value release and copy behavior stays in the existing runtime path.
No next-step performance qualification is claimed here.

The generated split-key fuzz probe `fuzz-split-probe-02` passes three programs,
45 debug/release/verify comparisons and strict leak/status/stderr checks. The
first generated probe was rejected by the old checker because JSON's `\\f`
escape is outside mylang; the generator now emits the equivalent admitted
`\\x0c` octet, and retains that initial rejection without counting it as a
compiler mismatch. The required final 50-case run will use the final source.

## Qualified word package, before sibling application merges

The profile-driven scalar store is restricted to integer, bool, f64 and unit
dictionary values. Ownership still supplies the unique dictionary after COW;
the store uses the existing descriptor stride and value offset and returns the
same dictionary pointer. Managed values keep their runtime release/copy path.
`d_scalar_stores.my` verifies snapshots, indexed and tombstoned dictionaries,
bool/unit, narrow signed/unsigned values, NaN and signed zero in debug, release
and verify with leakcheck. Four focused Core tests pass in
`logs/split-store-tests-13.txt`. Earlier failures are retained.

`word-dict-store-04.json` qualifies the final word source and every affected
dictionary/set micro row at both sizes. Cycles below are per original row unit;
each cell is size 4096 / size 64. Every ratio is at most 1.10.

| Row | Old | New | Rust | Zig ReleaseSafe | New/old | New/Zig |
|---|---:|---:|---:|---:|---:|---:|
| word_count | 291.066 / 377.834 | 39.879 / 53.263 | 59.246 / 66.166 | 47.208 / 50.893 | .137 / .141 | .845 / 1.047 |
| dict_lookup | 30.941 / 16.939 | 15.371 / 15.258 | 42.207 / 41.651 | 52.337 / 31.121 | .497 / .901 | .294 / .490 |
| dict_lookup_str | 62.011 / 28.675 | 27.218 / 19.816 | 64.713 / 57.309 | 62.812 / 31.903 | .439 / .691 | .433 / .621 |
| dict_update | 827.239 / 731.503 | 191.838 / 182.705 | 415.239 / 398.886 | 549.963 / 309.679 | .232 / .250 | .349 / .590 |
| dict_update_str | 1025.832 / 882.514 | 276.833 / 250.257 | 920.686 / 861.430 | 731.204 / 404.517 | .270 / .284 | .379 / .619 |
| set_dedup | 175.502 / 168.279 | 24.643 / 28.799 | 62.455 / 62.519 | 81.055 / 37.572 | .140 / .171 | .304 / .767 |

The fresh 50-source split-key sweep, `fuzz-split-50-01/summary.json`, completes
750 exact old/new comparisons across debug/release/verify, five argument cases,
zero mismatches, zero nonempty stderr and zero leak reports in 149.99 s. Native
`split-qualification-02` also matches the corrected old oracle on seven pinned
output lines. It adds original-source lifetime coverage while heap list and
dictionary entries are overwritten inside the cursor loop. Each resulting
dictionary retains all original keys correctly.

Own-source Core32 passes 258/258 in 139.97 s, maximum shard 68.80 s. Full strict
conformance matches 1518/1518 in both debug and release, zero mismatches and zero
unsupported, with leakcheck and verify, in 184.60 s. See unique `word-test-core32`
and `word-full-conformance` logs. The final installed build took 0.64 s after the
focused Core test compiled the exact source; earlier fresh source installations
were 2.86 s and 1.73 s. No measured Core build or Core test exceeded its limit.

`word35-diffs-01` retains fresh full raw LLVM diffs and semantic-metadata/SSA
definition diffs for every original row against the accepted C baseline. Thirty-
one rows have identical normalized definitions. The four affected dictionary
functions contain exactly six approved scalar-set replacements, counts 1/1/2/2;
all other call counts are unchanged. `exact-store-review-02.json` establishes the
stronger instruction-by-instruction correspondence after expanding only those
six old i64 set calls into the exact stride-16, block-offset-40 typed store and
same-dictionary forwarding. It removes only the six proven-private spill slots,
then checks semantic metadata and bijective SSA/block names. Every remaining
instruction, operand, trap, branch and phi edge matches. Raw diffs remain intact.
The first review receipt is a retained tool failure from stale match offsets;
the corrected receipt qualifies, with no compiler change between them.

Frozen IR, ownership implementation, persisted formats, aggregate masks and all
reference workload algorithms remain unchanged. This is the word package proof;
the final all40 A gate awaits the qualified packet and character packages,
combined-source Core/conformance, and the final combined old gate required by
the sibling SPEC update. No full-A performance claim is made here.

The normal commit's whole-tree Guardian check found local test-tag and formatting
issues; `word-commit-02.txt` retains that rejection and `word-guardian-03.txt`
retains its follow-up. Supplemental tests now use `spec-case`, diagnostics use
the existing file-scope print alias, and boolean/line/literal formatting follows
the gate rules. These mechanical corrections leave the transformation and LLVM
store recipe unchanged. `word-guardian-04.txt` passes all 88 checks. The exact
corrected source is freshly installed in 1.78 s, then passes Core32 258/258 in
98.56 s, maximum shard 45.20 s, and full conformance 1518/1518 debug/release with
zero mismatch/unsupported and verify/leakcheck. The uniquely named
`word-style-test-core32-02` and `word-style-full-conformance-02` logs retain the
refresh. Final combined all40 timing will use a fresh compiler source build.
