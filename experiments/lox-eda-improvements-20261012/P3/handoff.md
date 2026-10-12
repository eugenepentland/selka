# P3 scoped object queries

Working branch: `codex/lox-eda-improve-20261012-p3`.
Frozen compiler: common-002 full installation, executable SHA256
`2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.
This is an application change, not a compiler/runtime change.

## Implementation

`heap.my` preserves all existing owned payload snapshot APIs. New scoped queries
return only selected scalars, scalar records, `Value`, existing `ObjRef`, or an
explicitly independent selected string owner. `string_hash` now reads directly.
Function queries cover arity, name, upvalue count, instruction, line and constant;
closure queries cover function and indexed upvalue; environment queries cover
parent and indexed slot; class/instance queries cover name/class and selected
method/field. Tree function, native and bound method records contain only scalar
fields and have selected record accessors.

`lox_strings.my` probes the borrowed intern table directly and compares borrowed
string bytes. Concatenation borrows both string payloads while constructing the
joined owner, then ends those borrows before interning can allocate or collect.
`output.my` renders functions/classes through selected handles instead of complete
function code or method-table snapshots. Returned rendering text remains owned.

Runtime frames and frame initialization remain reserved for P1. Interpreter
callers remain reserved for P2; `/tmp/lox-p3-helpers.patch` was distributed early.
No borrowed address escapes a helper or survives allocation/collection.
Mutations continue to publish independent snapshots through stable object slots
after the bounded mutation probe refused nested writeback; no partial moves or new RC exist.

## Focused validation

Four `p3_queries_test.my` tests cover environment snapshots and alias-visible
writes; missing keys, table growth, inheritance and identity; function/closure
selected fields; independent string snapshots, stress collection and reused slots.
Existing heap/string/table and other Lox unit tests are included in the directory
suite. Complete conformance and mode matrix belong to the integration coordinator.

`P3/query-probe.my` (built from a private source/import snapshot) compares the original snapshot reads and selected queries for
100 iterations at widths 1 and 1024. It reads hash, environment parent/slot,
function arity/instruction, closure function/upvalue, class name/method and
instance class/field. Construction is identical between arms. This is a bounded
allocation probe, not a replacement for any full benchmark or runtime result.

Commands (run in this worktree):

```sh
source /home/epentland/.config/mylang/dev-env.sh
export TMPDIR="$PWD/.tmp/lox-eda-improvements/P3/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.tmp/lox-eda-improvements/P3/zig-cache"
# The initial queued commands use .mylang-cache symlinked to the private P3 cache.
# For later reproduction, pass --cache-dir .tmp/lox-eda-improvements/P3/mylang-cache/core.
compiler=/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang
scripts/build-slot.sh build "$compiler" test experiments/lox-eda-improvements-20261012/source/lox --experimental-zero-rc --release --force --cache-dir .tmp/lox-eda-improvements/P3/mylang-cache/core
mkdir -p .tmp/lox-eda-improvements/P3/probe-source
cp experiments/lox-eda-improvements-20261012/source/lox/*.my .tmp/lox-eda-improvements/P3/probe-source/
cp experiments/lox-eda-improvements-20261012/P3/query-probe.my .tmp/lox-eda-improvements/P3/probe-source/p3_query_probe.my
scripts/build-slot.sh build "$compiler" build .tmp/lox-eda-improvements/P3/probe-source/p3_query_probe.my -o .tmp/lox-eda-improvements/P3/query-probe --release --experimental-zero-rc --counters --cache-dir .tmp/lox-eda-improvements/P3/mylang-cache/counted
scripts/build-slot.sh build python3 experiments/lox-eda-improvements-20261012/P3/run-counter-probe.py .tmp/lox-eda-improvements/P3/query-probe
python3 experiments/lox-eda-improvements-20261012/P3/analyze-counter-probe.py
scripts/build-slot.sh build "$compiler" build experiments/lox-eda-improvements-20261012/P3/mutation-probe.my -o .tmp/lox-eda-improvements/P3/mutation-probe --release --experimental-zero-rc
```

Status: complete in the assigned P3 scope. Final forced suite: **69 passed,
0 cached, 0 failed, 0 skipped**. Scalar record query returns compiled successfully.
Both implementation commits passed the normal Guardian hook: **88 checks** each.
Implementation commits:

- `6ab8449ab69d8b8fb71767385f52bf62827ca2cb`: scoped heap helpers.
- `9b703a423e4668b7b454e629990c6ed6b83e2c58`: scoped intern/concat and output reads, focused tests.

The first directory attempt passed all 69 real tests but failed compiling the
then colocated probe: it attempted to move `class.methods` from a temporary
snapshot. The probe was corrected to pass that selected field into `table.get`
and moved out of application test discovery. Final green tests use the unchanged
production helpers and the final input manifest.

Mutation probe: **semantic refusal `E_IMMUTABLE`**, specifically the immutable
union-match binding's nested data. This is not a syntax/setup failure. Typed
record/enum construction and match were accepted; in-place nested writeback was
not admitted. Original snapshot setters remain in production.

## Allocation evidence

These are paired arms in one frozen candidate binary: the unchanged independent
snapshot accessors versus new scoped queries, not a full baseline/candidate
application benchmark. Both widths execute 100 selected-read iterations and
produce identical paired output. `counter-analysis.json` sums read-function and
snapshot-getter allocation plus reallocation-added bytes; separate whole-process
metrics include construction and rendering.

| Width | Snapshot read traffic bytes | Scoped query read traffic bytes |
| ---: | ---: | ---: |
| 1 | 153600 | 0 |
| 1024 | 28860800 | 0 |

All scoped read buckets have zero payload-copy events. All four profiles have
zero runtime/shared RC, retain/release/uniqueness events, share marks/bytes and
managed exit-live bytes. Raw profiles, paired output and analyzer are retained.
The independently reported managed peaks are 286688/286784 bytes at width1 and
788000/788096 bytes at width1024 (query/snapshot). Peak is not allocation traffic.
No runtime/RSS measurement or foreign comparison was performed in P3.

`final-build-input-sha256.json` records final application/test inputs;
`probe-build-input-sha256.json` records the actual private import snapshot;
`build-input-sha256.json` records the earlier rejected probe attempt.
`validation-identity.json` records executable/compiler hashes and commits.
Complete conformance, integrated ownership modes, cache verification, full
measurements and final integration gate remain with the coordinator.
No Guardian feedback log entry is authorized or added.
