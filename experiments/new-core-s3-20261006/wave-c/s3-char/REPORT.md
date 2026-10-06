# S3-A scalar character consumers

Worktree: `codex/new-core-s3-char-performance`, based on
`ac81831bd9e6100bf8d31cc07ca97bcff9f82d6c`. This package adds generic character
consumer fusion; it does not change benchmark/reference sources or frozen IR.
Compiler/runtime source is `3f47456ce70a4d2365fe1107123bf59a894fd859`;
`c7673da2fd7819242e4c86fe973f05c8a1d18486` only balances the unchanged native test
matrix across shards. CSV and all five affected original T1 micro rows pass both
speed gates. Correctness qualifies. Standalone JSON retains its byte-parser
performance miss; A's separately qualified packet dependency closes JSON before
the required final combined measurement.

A checked `str_char` becomes one checked `str_code` at the same instruction and
source span only when all uses (including forwarding copies) are authorized
runtime text equality against a valid, single Unicode scalar constant, or
character appends. Comparisons become integer equality and append operations
retain the original receiver/offset. The runtime append helper snapshots the
bytes before destination growth/COW. Stored, returned, ordinary-call, phi,
self-destination and multi-scalar comparison uses preserve materialized strings.
No interval facts, ownership rules, IR fields or runtime helper are added by the
fusion. Builtin text equality and the two builtin text-offset helpers use the
existing `runtime_c` authority; ordinary extern lookalikes cannot opt in.

Focused validation uncovered two inherited failures, retained under
`retained-diagnostics-01`: extreme Unicode indices lost the original scalar
index/length, and no-detail text scalar traps omitted the marker required by the
Core trial batch. Text bounds now recover original indices only from an exact
authorized offset declaration, with scalar counting/recovery inside the cold
failure branch. The existing conditional trap emitter delegates to shared
begin/end helpers with identical ordinary output. No-detail runtime traps now
carry the existing version-1 operation marker; its JSON escaping is shared with
assertion/contract messages. Human diagnostics and the marker schema remain
unchanged. The marker repair includes separator, byte-range and list-value
regressions as well as scalar construction.

`qualify_scalar.py` accepts explicit old/new paths and requires fresh evidence
and cache directories. It preserves every compiler/native stdout, stderr and
exit status. All 17 test verdicts compare name, status, complete
located reason and captured output against the old oracle, without trap/detail,
path or guest-frame normalization. A separate program places printing before
and after the checked read; 24 native runs compare complete status/stdout/stderr
for empty, ASCII, non-ASCII, NUL and supplementary-plane inputs across old and
new debug/release/fact-verifying modes. New success runs enable strict leaks.
The established Core zero-argument report omits old-only actual/expected fields;
the tool validates the old fixture's true predicates/null trap values explicitly
and compares the shared verdict fields without changing either report schema.

The protected corrected old oracle SHA-256 is
`d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79` and adjacent
QBE is `b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c`.
They are private copies of M's qualified corrected pair. The new compiler is
built from this worktree; no copied new binary or linked old runtime is used.
Frozen `ir.zig` and `own.zig` Git blob IDs match `e50e508a4` exactly:
`f732206c9dcd2a300719aef8d33d0ad283b3d135` and
`3d9a0152b428db6d6b7233a9dced193153b9a9c1` respectively.

Required wrapper for Core gates/exclusive builds:

```sh
scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- \
  scripts/build-slot.sh build -- COMMAND
```

Package guest qualification, fuzz, audits and timing hold build slots. Exclusive
Core timing additionally acquires every build slot before starting its clock;
admission waits and diagnostic contended compilations are excluded. Performance
runs acquire `/run/user/1000/mylang-s2-cpu10.lock` and pin native samples to CPU10.
The accepted seven-round interleaved measurement tool and unchanged reference
binaries retain strict status, stdout, positive/finite cycles and checksum checks
at sizes 4096/64; both new/old and new/Zig ReleaseSafe limits are 1.10.

The runtime now shares append allocation/publication through a byte-input helper.
Character append captures exactly 1–4 bytes before cursor reset, destination
growth or freeing an aliased source. Bounded endpoint copies read/write no bytes
beyond the chosen width (including width 3), while larger ordinary appends retain
their existing overlap-safe path. Uniqueness, capacity growth, cached hash/scalar
invalidation, ASCII flags and NUL termination keep the previous behavior.

LLVM width/code lowering explicitly checks unsigned byte offset against byte
length before addressing or reading the first byte. ASCII returns width 1 or
the zero-extended byte; Unicode and invalid offsets call the original helper
with the original operands. Checked code still executes its original located
check before this branch. The emitter records the join label for successor phis.
Hand IR covers ASCII/NUL/all UTF-8 widths plus empty, end and U64-max offsets at
debug/release/verify: the same 21 native checks run across three tests.

| Final check | Evidence and result |
|---|---|
| Exclusive Core build | `core-install-09`: 1.72 s, all three build slots, zero admission wait |
| Core32 | `full-test-core32-02`: 261/261, 124.82 s, max shard 65.42 s |
| Core RSS/protocol | Inherited strengthened `full_old_gate.inspect`: one successful Build Summary, 32 exact native verdicts, no overrun notices, max test-run RSS 264,241,152 bytes |
| Full conformance | `full-conformance-01`: 1518 debug + 1518 release, 0 mismatch/refusal, verify/leak enabled, 153.89 s while text fuzz ran concurrently |
| Located reports/order | `qualification-06`: 17 complete shared verdicts, 24 exact raw native runs, 32 retained commands, strict leaks in all new modes |
| Extended text fuzz | `text50-01`: 50 accepted, 750 comparisons, 1000 native outcomes, 1200 journaled commands, 0 mismatch/fact/leak/refusal; 241.31 s |
| Original 35 definitions | `identity35-01`: all full function definitions byte-identical to qualified C `9637eb9a1aa4af8ee0ecd88838ceed09b228d812`; no ASCII labels or normalization |
| Baseline provenance | Raw 92590700 diffs retained; existing narrow C authority/site/debug audit reports 0 residual changes in all 35 rows |

The final installed compiler SHA-256 is
`751087df7f064dd9a759e724ddff1edd1512d56e722beb4ef1c606d38b9ca924`, verified
before and after the test-only split. Compiler/runtime inputs, IR, ownership and
persisted schema versions stayed fixed through these qualifying commands. Source extern declarations
remain ordinary externs; exact runtime signatures authorize helper recognition.

`measure-04.json` contains every accepted interleaved native status/stdout/stderr,
checksum and cycle sample. Ratios below are sizes 4096 / 64, respectively.

| Row | New / old | New / Zig ReleaseSafe |
|---|---:|---:|
| CSV aggregate | 0.225636 / 0.253595 | 1.061938 / 1.069275 |
| Byte scan | 0.615851 / 1.021771 | 0.036948 / 0.138668 |
| String equality | 0.945630 / 0.941892 | 0.181640 / 0.925109 |
| String search | 1.028015 / 0.850144 | 0.033561 / 0.175145 |
| String split | 0.303612 / 0.308066 | 0.935119 / 0.935559 |
| String join | 0.720232 / 0.548002 | 0.253618 / 0.270780 |
| Standalone JSON (retained miss) | 0.234998 / 0.242066 | 1.132103 / 1.188012 |

CSV initially measured 1.922/1.833 versus Zig. Fusion alone reached 1.650/1.582;
short append copies reached 1.249/1.221; guarded ASCII reads reached the passing
final ratios above. Initial profiles in `wave-c/s3-a/profile-*.txt`, intermediate
`profile-csv-01.txt` and final `profile-02` remain available. The intermediate CSV
profile found append-char/general-append at 19.27%/19.14%, width/code at
6.84%/4.72%. Final CSV instead spends 28.36% in the shared append helper, 28.32%
in main and 17.39% in allocation. Final JSON remains allocation/byte-buffer work
(16.57% allocation, 12.26% buffer push). Both final profiles have zero lost
samples and their exact native statuses/checksums match explicit old guests.

A's fresh combined word+packet source `9bebd05b` JSON receipt (seven rounds,
CPU10, all four implementations) passes: new/old 0.203925/0.211200 and new/Zig
0.985734/1.036705. It is copied under `dependencies/packet-combined-json-05.json`
with its source/evidence provenance. This is a dependency result, not a claimed
measurement of the final scalar+packet merge. A owns the fresh merged Core,
conformance, all-40 timing/native audit and full old gate; final X owns 9×200
plus supplementary split-key200. No final exit matrix is claimed here.

`fuzz_char.py` imports the original extended S3 T1 text generator/transport and
retains its original reconstruction and checksum literally. It adds independent
NUL/all-width reconstruction with randomized one-scalar comparisons, distinct
branch appends to two outputs and an observable saved snapshot. Its strict
package run uses the S3 qualification wrapper, explicit protected oracles and
fresh cache/evidence directories. The same generator is ready for final text200.

Retained failures are labeled separately. Initial Unicode extreme-index reports
and no-detail scalar traps exposed real emitter/runtime defects and are repaired.
`qualification-02` retains the driver-accounting failure from comparing old-only
actual/expected fields; `qualification-03` retains the missing on-demand scalar
helper declaration. `full-test-core32-01` passed all 259 tests in 122.83 s but
failed timing with a 120.64 s shard; balancing kept all 21 hand-IR native cases
and produced the qualifying run02. Guardian blocked condition/test organization,
generic/template limits and allocator threading before the normal green retries;
every original log is retained under `logs`.
