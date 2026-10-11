# Selka comparison chains, 11 October 2026

The Selka body producer now checks and lowers parsed comparison chains through
its existing scalar, floating, collection, record and Option comparison lowering.
It checks operands once in native diagnostic order, reserves native temporary
locals, and builds the comparison blocks backwards. Runtime branches skip later
operands after a false comparison. Numeric hints, equality peer context, source
spans, import use and local metadata follow the native checker.

The strict installed schema9 selection passed all 31 fixtures and 219 operations
across reference, shadow and component modes, with zero failures or skips.
The 21 success cases additionally compare typed dumps and run generated release
programs with fact verification and leak checks. Complete canonical native
batch/catalog comparison in shadow mode remains the primary typed oracle.
The 10 diagnostic cases retain exact native precedence and repairs. Coverage
includes all eight integer widths, mixed floating comparisons, bytes/text,
list/dictionary/set relations, records, Option peer inference, imported functions
and records, and observable single evaluation and short circuit behavior.

The source base is `47f32534613adcc647718bd5c5541cc72a0c0045` in an isolated
worktree. The final schema9 package key is
`db537bd9017a73f47ded125b0dc5ba309636175ed0df0591fa852adf800613f0`, with artifact
SHA256 `b4b218f088272a185c55c72d08385f7211e00276b5442aaa2df37ec8bbc601ff`.
The native9 host SHA256 is
`02870ae6efcc13d8e7f5fcaaee712916ee9cc994688e3ffb860f52289f97fa18`.
The seed remains
`c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`;
the runner obtains and verifies its authentic coordinator receipt.

[Evidence](evidence/selka-body-chained-20261011/receipt.json) includes the complete
raw qualification, authentic package receipt, exact producer source snapshot,
and unmodified successful request/reply frames. The supplemental captured
component check passed once, with status 0 and empty stdout/stderr.

An earlier genuine 93-check run had 42 selected mismatches: all 21 success cases
in both selected modes failed `ComponentProtocol`. Native replay located the
failure at `parser_value.zig:188`: updating an existing logical node with a later
span row violated the required wire postorder. The implementation now appends a
fresh record. A full-engine regression checks every emitted child ID against its
parent row. The failed exchanges and verdicts remain archived. An earlier schema8
coordinator deployment was rejected before admission; its metadata is preserved.
One fixed-source install was terminated by earlyoom; the admitted retry built
successfully. No frame header or historical receipt was edited.

Qualified-seed pure tests passed 3 chain helper tests in each of Debug and release
with facts/leaks, and 12 body tests in each mode. The closed admission harness
passed 4 Python tests. Reachable formatting passed, and Guardian's 88 checks passed
in the preliminary diff-scoped run; the commit command runs the whole-tree gate.

To reproduce, use the pinned Zig and an authentic schema9 coordinator/package:

```sh
scripts/build-slot.sh build python3 selfhost/tests/run_body_chained_admission.py \
  --compiler NATIVE9_HOST --builder AUTHENTIC9_COORDINATOR \
  --component-dir INSTALLED9_COMPONENTS --source-root ISOLATED_SOURCE \
  --zig PINNED_ZIG --release --report PRIVATE_REPORT
```

Schema10 integration requires fresh genuine captures and requalification against
its installed host and producer. This bounded result does not establish compiler
bootstrap, whole-language closure, or the 1.5x performance objective.
