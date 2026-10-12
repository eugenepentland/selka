# Exact-sized counted C0 supplement: native builds blocked

Subsequent resolution: root approved A10's exact-source native replay adapter.
All 15 configurations now have separate passing counted observations in
`../size-aligned-C0-native-replay`. The failures recorded here remain unchanged;
the ordinary compiler command did not become successful.

All eight distinct source builds failed with native-link `FileNotFound`. These
are compiler/native build failures, not source ownership refusals. All 15
runtime input configurations remain in the report; zero counted guest executions
ran. The frozen compiler is C0 `fbfcaa7a923186a8e773c3760f81c10aa345a432`, binary
SHA-256 `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.

The experiment adds `--counters --emit-llvm` to Release checked builds of the
exact calibrated timing sources, retaining their source/helper hashes,
arguments, environment, worker count, affinity and expected outputs. The two
input manifests preserve all 15 uncounted counterparts. These cases are separate
from A03's original30/pinned81+6 corpus; no denominator changed.

`results.json` includes every full command and stderr. Each source directory
also contains compressed build/LLVM artifacts and exact source snapshots;
`archive.json` records their hashes. The first failure was:

```text
error: failed to open object .../cache/native-link-682e7849264a1481b59bc535d0e1b428/ae5cec2e220668d317669e52a665927510729048b855086779b285dd1a020e95.o: FileNotFound
```

This matches the previously diagnosed C0 uncacheable-native staging cleanup
defect after the host-link closure changed. A01's driver fix belongs to the
candidate; it was not applied to the immutable baseline. No baseline compiler,
seed, host trust entry or cached artifact was modified to make these builds pass.
All eight groups used ordinary admission separately: 22.760387215s of admitted
work and 40.820700139s waiting. Those are scheduling observations, not compiler
performance results.

The candidate's 15 exact-sized counted runs still wait for C1 and must use the
same approved native adapter as the subsequent baseline. Existing frozen
uncounted C0 binaries remain usable for runtime and corrected RSS pairing,
and A03's small-input census remains valid.
