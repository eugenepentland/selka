# Actual coordinator qualification

All ten coordinator invocations passed the acceptance assertions in `../qualify_campaigns.py`. This uses the installed candidate compiler and a real LLVM 19 libFuzzer executable. It is correctness evidence; wall, CPU, RSS and admission values are operational observations, with no performance comparison.

- Differential cold covered all four targets: four shards and eight cases. Warm reused all four shards with zero admission and zero executed cases. Extension retained those keys and ran four additional shards/eight cases.
- Coverage cold ran 32 units. Warm requested zero admission and executed zero units. Extension reused the old shard and ran 32 additional units.
- Appending one harmless ELF trailer byte changed the copied engine identity. The coordinator replayed two retained bundles/eight inputs before two fresh shards/64 units.
- SIGTERM after the first completed incremental shard exited 143 and saved an incomplete report. Resumption reused that shard and executed only the second shard/two cases. The final unchanged run reused both shards without admission or case execution.

`results.json` preserves the harness summary, case commands, report/log hashes, process-tree observations and admission records. `cases/` contains the raw coordinator reports and transcripts; `workers/` contains the corresponding raw worker requests, results and small logs. `retention.json` identifies original artifact paths and hashes; no retained file was truncated. `input-hashes.json` records source, fixture, compiler and component identities. No executable, archive or compiler cache is tracked.

Run directly, without an outer build-slot wrapper; each coordinator owns admission:

```bash
TMPDIR="$PWD/.mylang-cache/cache-wave4b/tmp" \
ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache" \
ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache \
PYTHONPYCACHEPREFIX=/dev/null PYTHONDONTWRITEBYTECODE=1 \
python3 experiments/cache-wave4b-20261010/qualify_campaigns.py \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --output .mylang-cache/cache-wave4b/coordinator-native
```

Use a fresh output directory when repeating. Reports retain original ignored-cache artifact paths. GNU time surrounds each coordinator command and survives the targeted coordinator cancellation to save its final process-tree record. Completed admission events are recorded individually; the interrupted invocation may also have a pending admission absent from that event list. Its transcript and process-tree record preserve the wider invocation. This fixture establishes a real native engine lane, not coverage-instrumented Selka compiler fuzzing.
