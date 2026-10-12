# P4 — EDA borrowed traversal and fresh parser construction

Implementation and local qualification are complete. Production commits are
`8e85f5a09` (fresh parser construction and four regressions), `7b2187eaf`
(model/schematic/symbol readers), `3dc0bc598` (footprint/geometry readers), and
`91cb4a289` (environment/pin metadata readers). Each passed all 88 Guardian
checks. The coordinator integrated them into candidate
`fcca1c13f92b4ef02b8ad2dcd7349cc45ec273eb`; production sources are frozen.

The read-only pinned compiler is
`/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/text-gaps/coordinator/common-002/install/bin/mylang`.
Compiler source is `8b7d59eba868775b1b8d7f64c54b07abdd23d470`; executable SHA256 is
`2dcba1cb1a98846bb8c1319575da1b3564e60af70162e195c2fbb6ec3af0f329`.
The seed commit is `094d2555bf68c04f563db4cc1b11d87d522b28e7`.
No compiler/runtime changes were required.

## Ownership and scope

Production readers outside P5's textbox use scoped `Tag.list` matches and
indexed original-child references. Scalar helpers return a boolean, numeric
value, point, or index. No borrowed child lists or node views escape a call.
`design_model.form` validates without returning a copied child tree; its error
helper consumes only a `Span`, preserving diagnostic locations/messages.
Symbol point/style/graphic selection returns indices into still-live children
instead of owned `find_form` snapshots. Footprint polygon selection retains an
index until emission, and courtyard dispatch reads its original child.

`sexpr_parser.parse_list` transfers its fresh local children directly into
`Node(Tag.list(...))`. Public `node_list` and `as_list` keep independent-copy
contracts. Two private loaders (`kicad_sch_shape.load_form` and
`placement_pin_roles.load_list`) retain `as_list`: their returned children must
survive destruction of the parser AST. Static production call sites outside
textbox fall from 93 to 2 (`source-audit.json`); this is a source census.

## Local qualification

- All 14 existing parser tests passed checked verified release.
- All 314 EDA tests passed checked verified release: 310 existing and four new,
  with zero failed/skipped/unsupported tests. This initial run did not explicitly
  enable leak checking; the coordinator owns the full integrated leak rerun.
- All four new tests passed again with `MYL_CORE_LEAKCHECK=1`, covering
  constructor/accessor independence, width/depth/empty/malformed trees, source
  replacement, AST destruction, and retained selected text/symbol output.
- All 18 bounded allocation probes passed with identical expected output, zero
  exit-live managed bytes, and zero retain/release/share/uniqueness events.
  All three probe LLVMs/binaries have zero guest RC calls/defined symbols.
- LLVM audit confirms the full parser has zero owned-copy and `node_list` calls;
  the full symbol reader emits neither `as_list` nor `find_form` snapshot helpers.

`initial-source-hashes.json` pins all application files actually used for the
initial runs. `qualification.json` records the immutable focused-test snapshot,
exact command, compiler hash, source hashes and leak-check environment.
`probe-builds.json` records three immutable build snapshots, exact commands,
binary/LLVM/source hashes and RC audit. Baseline probe sources come from the
unchanged historical `eda/source/src` and are checked against `source-baseline.json`.
Raw counter profiles/output, `probe-summary.json`, `probe-comparison.json` and
`llvm-copy-audit.json` preserve the measured evidence.

## Bounded allocation differences

These are reduced synthetic counter inputs. The symbol rows call the actual
`kicad_sym_reader.parse_library`; width/depth rows isolate parser construction.
Traversal-only uses candidate readers with the unchanged baseline parser.
Traffic is allocated bytes plus reallocation-added bytes; copy events are separate.

| Probe | Size | Baseline traffic B | Traversal-only B | Full B | Baseline → full list copies |
| --- | ---: | ---: | ---: | ---: | ---: |
| Width | 16 | 24,480 | 24,480 | 17,536 | 33 → 0 |
| Width | 64 | 93,848 | 93,848 | 66,160 | 129 → 0 |
| Depth | 8 | 9,728 | 9,728 | 5,760 | 36 → 0 |
| Depth | 24 | 45,472 | 45,472 | 15,136 | 300 → 0 |
| Symbols/pins | 4 | 121,952 | 60,768 | 29,536 | 296 → 5 |
| Symbols/pins | 16 | 459,104 | 224,896 | 104,768 | 1,124 → 5 |

The remaining five symbol-probe copies hold independently owned output lists.
Depth-24 traffic falls 66.71%; symbol/pins-16 traffic falls 77.18%. Runtime,
process RSS and full-corpus ratios are coordinator measurements.

Fresh transfer preserves append-buffer capacity. Managed peak rises in the
parser-only probes: width-64 is 32,368 → 35,752 B and depth-24 is
5,536 → 10,880 B. Symbol/pins-16 peak falls 107,112 → 53,648 B. The allocation
tradeoff is supported by unchanged runtime code: descriptor deep copy allocates
list capacity equal to `source->len` (`core_owned_copy.c:42–43`), while append
starts growth at capacity 8 (`core_rt.c:674–679`). Transfer retains that spare
capacity. All exit-live values are zero. Further capacity tuning is deferred.

Capacity-source SHA256s:

- `src/core/runtime/core_owned_copy.c`:
  `9f0fc3f83cd0a06f8171edb2f23867ef4a1f9213a5554625078df58dda86d450`
- `src/core/runtime/core_rt.c`:
  `940e245170a99bb46db08c8e3d49edb9e6528329f0a9c54e38918be0c1b11032`

## Reproduction and integrated gates

From this worktree, source `~/.config/mylang/dev-env.sh`; keep the existing
`MYLANG_SLOT_DIR=/home/epentland/.cache/mylang/slots`. Set `TMPDIR` under
`.tmp/lox-eda-improvements/P4`. Every native command uses normal shared build
admission. Exact test commands are retained in `qualification.json`; initial
runs used the same budgets and flags shown below.

```sh
scripts/build-slot.sh build "$compiler" test "$source/sexpr_parser_test.my" \
  --experimental-zero-rc --release --verify-facts --jobs 1 \
  --max-steps 1000000000 --max-frames 40000 --max-memory 2G \
  --timeout-ms 120000 --cache-dir "$private/cache" --json
scripts/build-slot.sh build "$compiler" test "$source" \
  --experimental-zero-rc --release --verify-facts --jobs 4 \
  --max-steps 1000000000 --max-frames 40000 --max-memory 2G \
  --timeout-ms 120000 --cache-dir "$private/cache" --json
python3 -B experiments/lox-eda-improvements-20261012/P4/qualify-local.py
python3 -B experiments/lox-eda-improvements-20261012/P4/probe.py
```

The two Python drivers own normal shared admission; probe executions use a
separately labelled 30-second bound. Native snapshots, LLVM, binaries, caches and
logs remain private under `.tmp/lox-eda-improvements/P4`.

At coordinator steering, an unadmitted duplicate all-314 leak replay was
cancelled, and the local driver was narrowed to the four focused cases. The
coordinator owns the full five-mode matrix, all 34 designs × three application
arms, nine CLI/error cases, cache verification and all calibrated full benchmarks.
The adapted `check-error-paths.py` recipe is retained but was not run locally.
No host-budget changes, timing leases, feedback-log writes, peer merges, pushes,
or historical-source/evidence changes were made. Optional optimization stopped
at the green local gate.
