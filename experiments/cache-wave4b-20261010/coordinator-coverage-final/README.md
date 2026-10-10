# Final coverage qualification

All four actual coordinator cases passed after manifest input loading was changed to enforce the aggregate corpus bound while streaming. These results supersede the coverage portion of `../coordinator-native/`; the prior differential and cancellation qualification remains valid.

Cold exploration executed 32 units. The unchanged run requested no admission and executed no inputs. Extension reused the original shard and executed 32 new units. Appending one harmless ELF trailer byte changed the copied engine identity: the coordinator replayed two retained bundles/eight raw inputs before two fresh exploration shards/64 units.

The target uses actual LLVM 19 libFuzzer instrumentation, with the executable and package provenance in `../coverage-native/`. This establishes coordinator and native adapter behavior, not coverage-instrumented Selka compiler fuzzing. No executable, archive or cache is tracked here. Process-tree and admission durations are operational observations; there is no performance comparison.

`results.json`, `cases/`, `workers/` and `retention.json` retain the raw summaries, reports, commands, worker requests/results, portable corpus bundles and logs. `input-hashes.json` binds the final sources. Artifact paths inside raw reports refer to their original ignored-cache directories. Every retained file is complete.

Run directly, without an outer admission wrapper, using a fresh output directory:

```bash
TMPDIR="$PWD/.mylang-cache/cache-wave4b/tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache" \
ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache \
PYTHONPYCACHEPREFIX=/dev/null PYTHONDONTWRITEBYTECODE=1 \
python3 experiments/cache-wave4b-20261010/qualify_campaigns.py --kind=coverage \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --output .mylang-cache/cache-wave4b/coordinator-coverage-final
```
