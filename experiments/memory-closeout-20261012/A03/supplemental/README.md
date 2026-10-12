# New API census supplement

`../supplemental.json` pins additional fixtures independently of the original
30 workloads and the 81-case main matrix. Each source is copied byte-for-byte
from its owner's pinned commit or qualified source hash and retains that provenance
in the manifest.
No original case is removed or renumbered.

Fresh C0 release observations use compiler SHA-256
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a` at source
`fbfcaa7a923186a8e773c3760f81c10aa345a432`:

| Additional case | C0 result | Evidence |
| --- | --- | --- |
| Owned list methods | Refused: nested-list methods unsupported | `../C0-supplemental-A02/` |
| Text/JSON/codec/path contracts | Passed: 1,339 whole-program allocations, 171,760 cumulative managed bytes, 8,424 peak bytes, RC0, exit-live0 | `../C0-supplemental-A04/` |
| Borrowed repetition | Refused: borrowed return | `../C0-supplemental-A04/` |
| Generic-resource lifecycle | Refused: unsupported expression | `../C0-supplemental-A07/` |
| Direct managed Result lists/maps | Refused: generic argument constraint | `../C0-supplemental-A01/` |
| Borrowed aggregate rendering | Refused: unaudited render helper | `../C0-supplemental-A04-render/` |

Refused programs did not execute and have no allocation or leak observation.
The one admitted executable passed output/exit, counter, emitted LLVM and linked
symbol checks. These observations are not RSS or runtime measurements.

The final integrated compiler must run all five configured modes: 30 builds and
40 executions for these six supplemental cases. A01's direct Result-list
fixture is pinned at `6c5ad78bda5b1908889e1a32956456bacbf615ecbc5d36b2fbc7100875865cf6`
with its qualified output and workers 1/2/8; the final compiler still must rerun it.
Final default/retirement artifacts must be measured freshly; C0 refusals cannot
be relabeled as successful new-compiler evidence.

Run the harness directly because it owns bounded shared admission:

```sh
python3 -B experiments/memory-closeout-20261012/A03/census.py \
  --manifest experiments/memory-closeout-20261012/A03/supplemental.json \
  --compiler /complete/install/bin/mylang --compiler-commit FULL_SHA \
  --zig "$ZIG" --output .tmp/memory-closeout/A03/FRESH_SUPPLEMENT
```

After promotion, add `--ownership default`. All new runs save exact manifest and
harness snapshots before compilation. The original `manifest.json` and earlier
reports remain unchanged.
