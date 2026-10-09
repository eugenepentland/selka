# Evidence storage

All paths in metadata refer to this package's original unpacked layout. Completed logs and samples are compressed to keep the package below the plan's 10,000,000-byte limit. No failed measurement is omitted. The archive ledger in `r3/evidence-archives.json` records identities and verified original-member hashes.

## Frozen fuzz matrices

`r3/fuzz-history.tar.xz` contains complete final `P1-final-02` command streams and sources, plus summaries and manifests for all ten completed matrices. The eight superseded matrices’ raw command streams and generated sources remain in the immutable ancestor archive identified below. Source files and summaries retain their original bytes. Command streams have a reversible representation, marked by the `.decoded` suffix: stdout/stderr base64 is decoded to byte strings represented using Latin-1, and elapsed seconds are stored as base64 of their exact IEEE-754 double. This avoids repeatedly compressing encoded output and decimal floating-point text. Every restored member was compared with its original SHA-256; see `r3/fuzz-encoding-verification.json` and `r3/fuzz-history-manifest.json.xz`.

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

That 5,239,092-byte historical archive has SHA-256 `d250c551b5d8c2e23124534bbe3f61e709bf4f0ecf370871bad68535a354faad` and uses ordinary tar members, without the decoder. It contains all eight historical matrices in full. The current archive contains 2,558 members in 1,378,596 bytes; the verification record also preserves the earlier proof that the complete ten-matrix encoding restored all 11,630 members byte for byte.

## Counters and timing

`raw/r3-counter-history.tar.xz` is an ordinary tar archive containing the original decoded counter JSON for the four revision-3 counted/plain sweeps through P1-final-01. The former individual gzip layers are removed; member hashes are in `raw/r3-counter-history-manifest.json.xz`. Final counted/plain summaries stay readable under `results/P1-final-01/`.

Tax datasets use `.json.xz`; `tools/layout_table.py` reads these directly. Each table preserves all three matching alignments, base/package times and ratios; the datasets additionally retain every warmup/run, load and binary hash. Compiler/checkpoint metadata remains ordinary JSON. Archives and their individual compression layers are storage changes only.

## Completed logs

`r3/loose-logs.tar.xz` consolidates completed build, correctness, qualification and measurement logs through the E/F sweep. It is an ordinary tar archive. Former `.log.gz` layers are decoded; the member path is the original path without `.gz`. `r3/loose-logs-manifest.json.xz` maps each original path to its member and preserves both the original stored-file hash and the decoded log hash. Metadata's original `.log` paths identify those members after extraction. Later logs may remain separate until the next consolidation.
