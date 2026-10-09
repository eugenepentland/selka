# D9 WP-4pre: cross-function physical return borrowing

WP-4pre was developed on accepted WP-3d tip `19144c19` while WP-3f was
still integrating, a scheduling deviation from the plan's nominal
`3f -> 4pre` order. The integration branch must merge this tip and repeat
its gate before WP-4 uses the fact. Arenas remain.

## Result and contract

`return_origin` remains the checker's **logical** alias fact. Under value
semantics, `sexpr::at(nodes) -> Node` returns an independent `Node` value, so
that fact is `fresh`. `Node` contains `bytes`; the returned value still holds
retained backing from `nodes`. A new, separate `borrow_origin` records this
**physical** provenance as `params[0]`. It travels through direct calls,
generic specializations, returned aggregates, typed-to-bytecode lowering,
semantic summaries, contract digests and native-test function hashes. Indirect
calls remain unknown. The return value is treated as borrowed only when
liveness and write analysis prove its source stays live and stable; otherwise
the transfer is owned. This changes no checker mutation verdict.

`check FILE.my --explain-ownership=OUT.jsonl` now writes the imported
functions' report when `FILE.my` is a project entry; a warm cached check
regenerates the same report. Each function exposes both origin facts.
`SPEC.md` registers RETURN-BORROW-1 and the extended OWNERSHIP-EXPLAIN-1;
`docs/tooling/ownership.md` describes the format and lifetime rule.

## Pinned schematic site measurement

The [evidence directory](evidence/d9-stage4pre/) contains compressed, full
JSONL reports for 113 functions and [compare.py](evidence/d9-stage4pre/compare.py),
which reproduces [summary.json](evidence/d9-stage4pre/summary.json) and the
per-function, per-PC [site ledger](evidence/d9-stage4pre/changed-sites.json).
Both
reports came from the same Debug compiler source and
`src/schematic/guest/main.my`, checked with `--value-semantics --no-cache`.
The **only** baseline difference was changing
`src/ownership_sources.zig::callSource` from
`switch (signature.inferred.borrow_origin)` to
`switch (signature.return_origin)`; the baseline compiler was rebuilt, its
report captured, and the file restored and rebuilt. Reproduction commands:

```sh
./zig-out/bin/mylang check src/schematic/guest/main.my --value-semantics --no-cache \
  --explain-ownership="$PWD/physical.jsonl"
# In a separate checkout, change only the callSource switch above and rebuild:
./zig-out/bin/mylang check src/schematic/guest/main.my --value-semantics --no-cache \
  --explain-ownership="$PWD/logical.jsonl"
python3 docs/audits/evidence/d9-stage4pre/compare.py
```

The physical fact changes **43 assignment + 28 argument** sites from
`move` to `borrow`, and one assignment from `copy` to `borrow`. It also
changes **6 returns, 4 constructors, 1 assignment and 1 field** from
`move` to `copy`, the necessary conservative decisions where the value
escapes or a source is not proven stable. In `sexpr::at`, logical origin is
`fresh`, physical origin is `params[0]`. These are static, per-call-site
RC-relevant transfer decisions, not dynamic execution counts. The existing
WP-3 copy-on-write `value_copy` decisions are unchanged on this program:
40 sites, 3 real copies before and after, because immutable `bytes` payloads
do not require a mutable-payload COW operation. WP-4 must show an actual
retained/released operation reduction in its generated RC code and counters;
WP-4pre does not claim a runtime traffic or speedup measurement.

## Verification

Focused tests cover logical-fresh/physical-parameter results, chaining
through a generic specialization, mutation and escape invalidation, cached
callee edits from parameter 0 to fresh to parameter 1, changed contract
hashes, native function fact hashes, and warm project explanation output.
The pinned reports and `summary.json` make the measured site ledger
reviewable without replaying a compiler edit.

The final Debug gate ran under the shared D9 lock after the cache-format
fixture update: `zig build test --summary all` succeeded (93/93 steps,
2,089 passed, 21,212 intentionally skipped by sharding),
`zig build test-qbe --summary all` succeeded (51/51 steps, 427/427 tests),
`zig build test-qbe-build --summary all` succeeded (29/29 steps), and
`zig build fmt-check` succeeded. `zig build` ran Guardian's 88 checks green.
The first `test` attempt had two C2/C3s corruption-test failures because
their fixture search used the old `semantic-cache-v2` directory after the
required store-format bump; the fixtures now use v3 and focused 2/2 plus
the final full gate pass.
