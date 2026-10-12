# P5 handoff

Source/tests commit: `0657eb28c` (normal Guardian: all 88 checks passed).
Seed: `094d2555bf68c04f563db4cc1b11d87d522b28e7`.
Compiler source: `8b7d59eba868775b1b8d7f64c54b07abdd23d470`.
Compiler SHA256: `2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.
Pinned installation: `/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install`.

Final application hashes:

- `kicad_sch_textbox.my`: `38529211673b70e61e7e96b7f9c11c0f5ce8b17792299a37b642a7299e110b2a`
- `kicad_sch_textbox_test.my`: `ed4d20195a44058986e2ce907010fc369f4c3eb7a84a63b5ccc448b3736cab89`

## Delivered behavior

`overlaps_of` scans candidates by integer index without constructing suffixes.
A stable integer permutation now sorts borrowed Item storage; managed Item and
text payloads never enter a sorting merge buffer. Exact strict ten-unit x/y
boundaries, early x break, ascending x/y ordering, stable ties, count and first
pair remain unchanged. Only retained Pair text has independent copies.
The existing `support_sort.sort_by_ctx` was sufficient; no shared sort edits.
Its index arrays have linear auxiliary storage. Dense comparison counts may
remain quadratic; this is not an asymptotic comparison-count improvement.

All textbox AST readers use scoped `Tag.list` matches and indexed child access.
The private owned `at_form` list became a scalar `at_pose` query; no child list or
AST view escapes a borrow. Selected text/output storage retains independent
copies. Public AST accessor/slice semantics and compiler/runtime are unchanged.

## Focused qualification

Six tests passed, uncached, with checked ownership, verified release and
`MYL_CORE_LEAKCHECK=1`. Frozen inputs and result are in
`final2-source-manifest.json` and `final2-focused-tests.log`. Existing orientation,
label and pin-policy regressions plus three new tests cover 0/1 items,
sparse/dense, stable ties, shuffled x/y order, exact x/y ten-unit boundaries,
negative coordinates, a retained 4096-byte report string after parser AST
destruction, and short/invalid first `(at ...)` selection.

Command (after sourcing `~/.config/mylang/dev-env.sh`, private TMPDIR):

```sh
scripts/build-slot.sh build "$PINNED_COMPILER" test \
  .tmp/lox-eda-improvements/P5/final2-source/kicad_sch_textbox_test.my \
  --release --verify-facts --experimental-zero-rc \
  --cache-dir .tmp/lox-eda-improvements/P5/final2-test-cache --json
```

The full EDA corpus, golden designs, ownership modes, integration/cache checks,
full benchmark timing/RSS and full gate remain coordinator-owned.

## Tiny bounded counter comparison

Eight labelled direct-overlap fixtures per invocation: 0/1 items, four fixed
boundary/tie cases, then sparse/dense at the indicated item count. Oracle
exhaustively computes all pairs and validates the first pair/coordinates.
Sources are isolated immutable phase copies with digests in each receipt.
`baseline` is the frozen source, `indexed` removes suffixes only, `indices`
is the final overlap implementation. These are not full benchmark inputs.

| Large fixture items | Phase | Managed allocation + reallocation bytes | Managed peak live bytes |
| --- | --- | ---: | ---: |
| 64 | baseline | 830304 | 21816 |
| 64 | indexed | 177296 | 21816 |
| 64 | indices | 47888 | 9576 |
| 128 | baseline | 2748352 | 43384 |
| 128 | indexed | 367856 | 43384 |
| 128 | indices | 82864 | 18888 |

All six invocations pass the oracle, retain zero managed bytes at exit, and have
zero RC/uniqueness events. At both sizes the final implementation makes exactly
six byte-buffer copies, the two report strings for each of three overlapping
fixtures. All sorting helpers make zero byte-buffer copies. The final
`overlaps_of` has zero list copies; only scalar index-sort arrays are copied.
Doubling large fixture size grows final managed traffic 1.73× and peak 1.97×,
consistent with linear storage plus the fixed small-fixture overhead.
There are no wall-time, process RSS or compilation-speed claims.
Raw counters, outputs and `counter-summary.json` retain allocation/reallocation
and function attribution separately.

Reproduction: `probe.py PHASE --source <textbox-source>` snapshots EDA modules,
builds `--release --experimental-zero-rc --counters` with a private cache through
shared admission, and runs under `timeout 30` with `MYLANG_COUNTERS` and leak
checking. Run `python3 P5/summarize.py` to verify the recorded counter assertions.
Private phase source/executable files remain under `.tmp/lox-eda-improvements/P5`.

## Retained failed attempts and corrections

- The preliminary `traversal` snapshot contained temporary `Some(at.x)` locals
  lacking an expected option type; compile refused `E_OPTION_INFERENCE`.
  Final source had already removed these wrappers before its admission.
- Initial focused/final test snapshots moved the long string into fixture
  construction and reused it; compiler refused `E_SINGLE_OWNER_MOVED`.
  The final test explicitly copies this retained fixture value and passes.
- Initial invocations labelled 128 supplied only one argument, while the tiny
  main checked `args[1]`; their printed configurations show actual 64 items.
  They are preserved as `*-128-argument-miss-*`, excluded from the summary.
  Corrected 128 runs use `timeout 30 <phase>/probe unused 128`, with exact
  commands in receipts and shared admission in `corrected128-runs.log`.
- Early receipt source hashes initially read the mutable working source after
  waiting. They were corrected against the actual immutable compiled phase
  snapshot; receipts also pin the full augmented probe and module manifests.

No compiler fix, nested worker, peer merge/push, historical evidence modification,
host/admission-budget change or Guardian FEEDBACK entry was made.
