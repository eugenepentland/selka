# Evidence storage

All paths in metadata refer to this package's original unpacked layout. Completed logs and samples are compressed to keep the package below the plan's 10,000,000-byte limit. No failed measurement is omitted. The archive ledger in `r3/evidence-archives.json` records identities and verified original-member hashes.

## Frozen fuzz matrices

`r3/fuzz-history.tar.xz` contains complete `P1-final-02` and final merged `P1-final-03` command streams and sources, plus summaries and manifests for all twelve completed matrices. The eight superseded matrices’ raw command streams and generated sources remain in the immutable ancestor archive identified below. Source files and summaries retain their original bytes. Command streams have a reversible representation, marked by the `.decoded` suffix: stdout/stderr base64 is decoded to byte strings represented using Latin-1, and elapsed seconds are stored as base64 of their exact IEEE-754 double. This avoids repeatedly compressing encoded output and decimal floating-point text. Every restored member was compared with its original SHA-256; see `r3/fuzz-encoding-verification.json` and `r3/fuzz-history-manifest.json.xz`.

Use the supplied decoder, from the repository root, to restore the original files into a fresh disk-backed directory:

```sh
evidence=experiments/concurrency-p1-2026-10-08
python3 "$evidence/tools/fuzz_archive.py" "$evidence/r3/fuzz-history.tar.xz" \
  "$PWD/.tmp/p1-restored-fuzz" > "$PWD/.tmp/p1-restored-fuzz-sha256.json"
```

The JSON written to stdout maps original member paths to SHA-256. It equals the decoded `r3/fuzz-history-manifest.json.xz` object. The decoder refuses overwrites and paths outside the destination. Plain `tar` extraction alone leaves the marked command streams encoded; use the decoder when reproducing original evidence. This representation changes no result, time value, command, source, output or failure.

The eight historical matrices’ raw members are recoverable from commit `98cb3a49fff3ba4ad438cb9087f86aa517a32760`, already an ancestor of this branch. `r3/historical-fuzz-reference.json` gives the archive identity; `r3/historical-fuzz-members.json.xz` gives all 9,072 referenced member hashes. Every referenced member was checked against that Git object. This avoids storing the same successful raw history twice within the current package’s size budget; all historical summaries and every failed timing result remain here.

```sh
git show 98cb3a49fff3ba4ad438cb9087f86aa517a32760:experiments/concurrency-p1-2026-10-08/r3/fuzz-history.tar.xz > "$PWD/.tmp/p1-historical-fuzz.tar.xz"
```

That 5,239,092-byte historical archive has SHA-256 `d250c551b5d8c2e23124534bbe3f61e709bf4f0ecf370871bad68535a354faad` and uses ordinary tar members, without the decoder. It contains all eight historical matrices in full. The current archive contains 4,884 members in 2,074,768 bytes; the verification record also preserves the earlier proof that the complete ten-matrix encoding restored all 11,630 members byte for byte.

## Counters and timing

`raw/r3-counter-history.tar.xz` is an ordinary tar archive containing the original decoded counter JSON for eight revision-3 counted/plain sweeps: four historical sweeps through P1-final-01, final P1-final-03, main P1-proxy-base-35df, and the two identical-path P1-proxy-identical-base/P1-proxy-identical-p1 snapshots. The former individual gzip layers are removed; member hashes are in `raw/r3-counter-history-manifest.json.xz`. All counted/plain summaries stay readable under their `results/<tag>/` directories. The archive contains 1,056 original JSON documents in 1,281,476 bytes.

Tax datasets use `.json.xz`; `tools/layout_table.py` reads these directly. Each table preserves all three matching alignments, base/package times and ratios; the datasets additionally retain every warmup/run, load and binary hash. Compiler/checkpoint metadata remains ordinary JSON. Archives and their individual compression layers are storage changes only.

## Completed logs

`r3/loose-logs.tar.xz` consolidates completed build, correctness, qualification and measurement logs through the final merged-source qualification, counters, corpus checks and TSan runs. It is an ordinary tar archive. Former `.log.gz` layers are decoded; the member path is the original path without `.gz`. `r3/loose-logs-manifest.json.xz` maps each original path to its member and preserves both the original stored-file hash and the decoded log hash. Metadata's original `.log` paths identify those members after extraction. The final archive contains 2,619 logs in 181,916 bytes; all logs were closed before consolidation. Failed Guardian installs, the initial fuzz preflight rejection and the interrupted G timing run are retained.

## Final source, scope and proxy identities

- `r3/results/final-selected-source-equivalence.json` records the final ReleaseFast compiler hash and every committed source-file hash at `c26c95de7`; `r3/P1-final-03/summary.json` pins the Debug compiler and correctness commands.
- `r3/results/final-scope-proof.json` proves both parents of real merge `1844fcc33`, byte equality with main `35df839be` for every frozen file and core_host.c, and exact equality of the selected runtime with historical candidate C.
- `r3/results/proxy-base-35df-build.json` records the exact main archive/compiler; its earlier failed Guardian selfcheck remains in `proxy-base-35df-build-failed-01.json`.
- `r3/results/final-identical-deterministic-proxy.json.xz` retains every paired counter delta and all 52 plain ELF identities/sizes. `identical-counter-runs.json` maps immutable source tags to the shared invocation namespace and the two raw snapshots. The initial path-confounded `final-deterministic-proxy.json.xz` is retained separately. These compressed JSON files restore byte for byte with `xz -dc`.
- `r3/results/P1-final-03-corpus-correctness.json` records all 45 parity and 26 Lox exact-output executions. No timing ratios or timing lock were used.
- `r3/P1-final-03-tsan/summary.json` and `repetitions.jsonl.gz` pin the three actual instrumented binaries and all 300 executions.

To reproduce the identical-path diagnostic from existing `ce.py build all` tags, choose fresh namespace and snapshot names:

```sh
evidence=experiments/concurrency-p1-2026-10-08
python3 "$evidence/tools/controlled_counters.py" \
  --base BASE_TAG --package PACKAGE_TAG --namespace FRESH_COMMON_TAG \
  --base-snapshot FRESH_BASE_SNAPSHOT --package-snapshot FRESH_PACKAGE_SNAPSHOT
python3 "$evidence/tools/deterministic_proxy.py" \
  --base FRESH_BASE_SNAPSHOT --package FRESH_PACKAGE_SNAPSHOT \
  --output "$PWD/.tmp/reproduced-proxy.json"
```

`deterministic_proxy.py` reads both loose and archived raw counters. Rebuilding requires the pinned compiler source and the unchanged corpus sources/inputs; `ce.py` supplies the recorded build/run commands. `corpus_correctness.py` runs the full parity/Lox expected-output check once per cell. None of these tools certifies runtime overhead. Historical wall-time tables remain in HISTORY.md; merged-source timing was waived explicitly by the user.
