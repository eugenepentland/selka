# Invocation arena and unchecked LLVM experiment

This directory builds explicitly opt-in benchmark executables from a frozen
native-v5 QBE closure. It does not change production defaults. The contract is
successful execution of this benchmark on valid inputs with sufficient memory.
Invalid indices, overflow, allocation failure, and excessive recursion do not
retain production behavior.

| Arm | Allocation | Guest lowering | Optimization |
|---|---|---|---|
| `control` | Production GC | Normal adapter | Separate units, O2 |
| `arena` | Invocation bump arena, original object headers | GC roots removed | Separate units, O2 |
| `unchecked` | Same arena | Roots, safety failure edges, diagnostic frames removed; unchecked C wrappers | Separate units, O2 |
| `whole-o3` | Same arena | Same unchecked lowering | One guest module, O3, inlining permitted |
| `compact-o3` | Headerless invocation bump arena | Same unchecked lowering | One guest module, O3, inlining permitted |

Both arenas use zeroed chunks, preserve allocation alignment, and free chunks
when the heap is destroyed. This CLI's existing final-execution entry skips heap
destruction and relies on process exit; all arms share that policy. Nested arena
storage is retained for the whole invocation. There is no collector, memory
budget enforcement, or per-object reclamation. Compact mode also removes the
96-byte object header, object list, runtime root operations, region distinctions,
and per-allocation descriptor/size-overflow checks. It retains small per-heap and
per-chunk metadata and accounting counters.

`unchecked.py` operates on parsed QBE instructions. It recognizes the native-v5
root protocol and safety failure successors, records its changes, and preserves
ordinary Result/Option and parser branches. Root elimination requires an explicit
arena proof flag; never link that lowering to a collecting heap. Recognized
arithmetic, cast, bounds, allocation, capacity, iterator, sticky-trap, and physical
frame guards are removed only in unchecked mode, along with diagnostic active
frame loads/stores. Step and logical frame budgets were already disabled in the
frozen ReleaseFast input.

The runtime shim removes duplicate list access checks, common list-generation
overflow checks, text endpoint checks, and integer checks. Seven symbols are
wrapped; the build derives exact flags from `unchecked_runtime.c`. The shim
applies to guest references. Calls already resolved inside the merged runtime
object retain the original implementations. Saturating arithmetic delegates to
production. UTF-8 decoding/validation, text copying, zero initialization, capacity
growth, resource/I/O cleanup, strict floating-point semantics, and chunk
allocation failure handling remain. See [ASSUMPTIONS.md](ASSUMPTIONS.md): unchecked
text slicing requires in-range endpoints even though ordinary slices clamp them.

## Reproduce

The build needs a native-v5 `qbe-units-v1` manifest, its completed safe LLVM build
receipt, that build's formatter object, and its materialized runtime sources.
For the frozen 2026-09-19 experiment, run from the repository root:

```sh
python3 experiments/llvm-backend/maxperf/build.py \
  --manifest .tmp/llvm-fixes-20260919/manifest.json \
  --receipt .tmp/llvm-fixes-20260919/llvm-o2.qbe-manifest.json \
  --formatter zig-out/lib/mylang-runtime/458456acf5a75b28c83e224c387254f1a16cb404bbf37f390e7e4fa9b0f1583e.o \
  --runtime-sources .tmp/llvm-fixes-20260919/cache-llvm-qualified/runtime/d0534049d18d77f4579a8f6b429ee233a5d9eff216f04e00e1c9b6cb40845952 \
  --work .tmp/llvm-maxperf-20260919

python3 experiments/llvm-backend/maxperf/qualify.py \
  --reference .tmp/llvm-fixes-20260919/llvm-o2 \
  --binary control=.tmp/llvm-maxperf-20260919/control.bin \
  --binary arena=.tmp/llvm-maxperf-20260919/arena.bin \
  --binary unchecked=.tmp/llvm-maxperf-20260919/unchecked.bin \
  --binary whole-o3=.tmp/llvm-maxperf-20260919/whole-o3.bin \
  --binary compact-o3=.tmp/llvm-maxperf-20260919/compact-o3.bin \
  --work .tmp/llvm-maxperf-20260919/valid-inputs \
  --json .tmp/llvm-maxperf-20260919/qualification.json

python3 experiments/llvm-backend/measure.py \
  --work .tmp/llvm-maxperf-20260919/measure-final --input /tmp/rt2x \
  --rounds 31 --warmups 3 --cpu 6 --sink null \
  --binary safe=.tmp/llvm-fixes-20260919/llvm-o2 \
  --binary control=.tmp/llvm-maxperf-20260919/control.bin \
  --binary arena=.tmp/llvm-maxperf-20260919/arena.bin \
  --binary unchecked=.tmp/llvm-maxperf-20260919/unchecked.bin \
  --binary whole-o3=.tmp/llvm-maxperf-20260919/whole-o3.bin \
  --binary compact-o3=.tmp/llvm-maxperf-20260919/compact-o3.bin \
  --binary zig=.tmp/llvm-fixes-20260919/before/zig \
  --reference safe --json .tmp/llvm-maxperf-20260919/measure-null.json
```

Use `--sink capture --no-counters` for a separate byte-capture wall batch.
Outputs are checked before/after null-output timing and on every captured run.
Qualification covers 17 goldens, 50 deterministic generated inputs, four special
valid inputs, and both benchmark sizes, in census and render modes: 730
comparisons across five experimental arms.

The Zig snapshot's linker rejects `--wrap`, so every experimental arm uses the
same system `cc -no-pie` linker recipe, including the GC control. The frozen safe
executable is also timed to expose rebuild/link-layout effects. Runtime C retains
production O2 compilation flags. Whole O3 applies to guest code, not runtime C or
cross-language LTO. Build receipts record source/object/binary hashes.

## Diagnostics and tests

Each arm also gets a `.stats.bin`. A diagnostic-only source hook runs immediately
after guest execution, because wrapping cannot intercept the call inside the
merged runtime object. Set `MYLANG_MAXPERF_HEAP_STATS=1` to emit one JSON record on
stderr. Timed `.bin` executables contain no stats hook. `collections=0` and chunk
counts confirm the arena path. GC `live_bytes` counts surviving object bytes;
compact arena `live_bytes` counts cumulative payload bytes and excludes removed
headers. Those fields have different meanings; compare peak RSS for process
memory use.

```sh
python3 -m unittest discover -s experiments/llvm-backend/maxperf -p 'test_*.py' -v
cc -std=c11 -O2 -Wall -Wextra -Werror -Isrc \
  experiments/llvm-backend/maxperf/arena_heap.c \
  experiments/llvm-backend/maxperf/test_arena_heap.c -o /tmp/mylang-arena-test
/tmp/mylang-arena-test
```

Repeat the allocator test with `-DMYL_MAXPERF_ARENA_COMPACT`; both variants also
have sanitizer coverage. `test_unchecked_runtime.c` checks runtime wrappers;
`test_unchecked_integer_diff.c` compares them against production for widths 1–64,
both signs, and all 26 operations. It uses a real context and excludes oracle
operations that trap, requiring successful comparisons in every width/sign/op
category. This caught and fixed the valid `INT64_MIN % -1 == 0` boundary case.
