# Development-speed lane: cold build throughput and cheap relinking — 23–24 September 2026

Branch `devspeed/codegen-throughput`. It started from `base/devspeed-impl-20260923`
(`371dbd17`) and has `devspeed/integration` `5c150f02` merged in (`66db775f`). It implements the codegen half of
recommendation 1 of the [development-speed audit](development-speed-2026-09-23.md): IL →
objects → executable. The lane `devspeed/build-frontend-reuse` owns everything before the
IL reaches the object builder.

## Result

| 50k-line project, Debug/QBE, `--project` | before (`5c150f02`) | after |
| --- | --- | --- |
| cold build | 527.5 s | **8.5 s** |
| `mylang test` cold | 7.7 s | **2.7 s** |
| no-op build | 6.18 s | 4.54 s |
| edit → build | 5.95 s | 4.77 s |

The acceptance targets were a 50k cold build of 30 s or less and a 10k cold build of 5 s or
less. Both are met: 8.5 s and 1.75 s. No no-op or edit row regressed; each one improved.
At 200k the cold build still fails, in the **frontend**: `emit-project-qbe` reaches
5.6 GB resident at the compiler's 8 GiB address-space ceiling and reports `OutOfMemory`
6.6 s in. That is before any code in this lane runs, and the baseline fails the same way.
The no-op and edit rows at 50k are now about 90% frontend: a 50k edit build spends
4.29 s in the frontend, 0.42 s in codegen and 0.12 s in the link.

## What changed

Four commits: `59ff6957`, then the merge `66db775f`, then `4ee08c59` and `3ba6956a`.

1. **Tools start without `fork` (`src/qbe_build_spawn.zig`, QBE-SPAWN-1).** Most of the
   old ~110 ms per function came from `fork`, not from QBE or the assembler. At 50k the
   driver holds a 900 MB manifest, and `std.process` forks the whole process twice per
   function. A tool now starts with `clone(CLONE_VM | CLONE_VFORK)`, the way
   `posix_spawn` does:
   - the child runs on a private 64 KiB stack;
   - it resets every installed signal handler and restores the signal mask;
   - it points stdin and stdout at `/dev/null`, and stderr at the build's own stderr or
     at a private pipe;
   - it then calls `execve` on the tool (by path, or searched on `PATH`).

   `Context.command` uses this path, and so do the batch pool and the LLVM adapter waves.
   A request that names no environment inherits the process's own environment (read back
   from `/proc/self/environ`), exactly as `std.process.run` does.
2. **QBE codegen runs in batches (`src/qbe_build_batch.zig`, QBE-BATCH-1/2).**
   - **Grouping.** Units are ordered by module, then symbol. A batch never spans two
     modules. Inside a module, a symbol whose Wyhash falls on a boundary (one in 32)
     starts a new batch, and no batch holds more than 128 functions.
     `MYLANG_QBE_BATCH=N` sets the cap, and `MYLANG_QBE_BATCH=1` compiles each function
     alone. A unit whose IL defines `data` also compiles alone. Boundaries depend only on
     symbols, so a body edit rebuilds one batch, and adding a function changes one batch
     (two if the new symbol is itself a boundary).
   - **One QBE run per batch.** Each member is its own `.ssa` input file, and QBE forgets
     `type`s between files. The header line of each function is rewritten to
     `section ".text.<symbol>" "ax"`, so `--gc-sections` still drops dead functions.
   - **One assembler run per batch.** The output is frame-map annotated, then assembled by
     `zig clang -cc1as` directly. `zig cc` would add a host libc probe (two `cc` runs) and
     an `ld.lld -r` to every assembly.
3. **Per-batch function metadata (QBE-BATCH-3).** Each batch's `MylQbeFunction` records
   and their location, message and inline tables are now their own assembled object,
   keyed by its text (`outputs.metadataAssembly`). `qbe_runtime.h` asserts the record
   sizes (24/48/40 bytes). The program-wide C unit (`outputs.sharedMetadata`) keeps the
   runtime descriptors, host bridges, literals, `extern` declarations and frame-map roots.
   It used to be one 3.5 s compile at 50k that ran after all codegen.
4. **Concurrent pool.** Code batches, metadata batches and the shared metadata and entry C
   units all run in one pool. Its width is the CPUs this process may use, capped by
   MemAvailable at 256 MiB per tool.
   - It polls the captured stderr pipes and advances whichever job finishes first. It
     started in FIFO order, which blocked on the slowest job at the head of the queue;
     moving off FIFO cut 50k codegen from 5.9 s to 3.8 s.
   - After the first failure nothing new starts, every running tool is still reaped, and
     every scratch directory is removed.
   - Objects land in fixed slots, so the order tools finish in never changes the link.
5. **Warm-path planning costs.** Driver-only codegen on a 50k no-op fell from 0.76 s to
   0.30 s:
   - The object fingerprint is Wyhash (`mylang-object-v2`). The pinned Zig's
     `std.hash.XxHash3` hashes long inputs at about **20 MB/s** on this machine; Wyhash
     does 15 GB/s (`.tmp/xxbench.zig`).
   - Object keys hash their framed parts directly instead of JSON-encoding every unit's
     IL first. That encoding was 18% of the driver's no-op time.
   - `definesData`, the `# myl-lit` scan, `sectioned` and `usesFrameMap` search for their
     keywords instead of splitting every IL line. `usesFrameMap` looks only at the text
     before the first function body.
   - `Context.read` reads into one buffer of the file's stated length (QBE-BUILD-READ-1).
6. **Identity.** `qbe_frame_map.zig` joins the native driver identity
   (QBE-DRIVER-IDENTITY-1), because it rewrites every unit's assembly. `validate` checks
   for repeated symbols with a set instead of a quadratic scan. `--report` adds
   `function_objects` and `compiled_function_objects`, and every function record still
   names its own key.
7. **Docs.** `docs/tooling/native-build.md` has a new *QBE batches* section, and its
   object-cache and driver-identity text is updated.

## Measurements

Machine: the i7-12700H, pinned to the P-cores (`taskset -c 0-11`), shared with other
lanes. I used ReleaseFast compilers:
- **Baseline:** `/home/epentland/ai/trials/devspeed-20260923-private/compilers/integration-5c150f02/bin/mylang`.
- **Lane:** a ReleaseFast build of `3ba6956a`, installed to the session scratchpad.

The ladder is `run_scale.py TIER --langs mylang-debug --samples 3`, with `MYLANG` taken
from the environment (copies in the worktree's `.tmp/scale`). Edit rows are the minimum of
3 samples. Seconds:

| Step | 10k base | 10k lane | 50k base | 50k lane | 200k base | 200k lane |
| --- | --- | --- | --- | --- | --- | --- |
| cold build | 32.59 | **1.75** | 527.49 | **8.50** | frontend OOM | frontend OOM |
| no-op build | 0.99 | 0.89 | 6.18 | 4.54 | — | — |
| edit → check | 0.13 | 0.13 | 0.67 | 0.64 | — | — |
| edit → build | 1.12 | 0.99 | 5.95 | 4.77 | — | — |
| edit → test | 0.60 | 0.55 | 2.22 | 2.11 | — | — |
| interface → build | 1.67 | 1.00 | 8.79 | 4.79 | — | — |
| `mylang test main.my` cold | — | — | 7.7 / 7.8 | 2.8 / 2.7 | — | — |

Load averages (1-minute):

| Run | Load |
| --- | --- |
| Lane ladder (05:54–05:56 UTC) | 1.9–2.4 |
| Baseline 10k (05:55) | 2.4 |
| Baseline 50k (04:57–05:07) | 2.7 at start, 2.8 at end (the 5-minute average was 4.4–4.6) |
| Test-cold runs | about 2.1 |
| 200k runs | 2.1 (lane), 13.7 (baseline) |

The 200k cold build fails in `emit-project-qbe` on both compilers: 5,619 MB and 5,618 MB
peak resident, `mylang: host failure: OutOfMemory` (`.tmp/peak.py`). None of the other
200k rows can run.

Phase split of the lane at 50k (`build --report`):

| Build | frontend | codegen | link |
| --- | --- | --- | --- |
| cold | 4.53 s | 3.87 s | 0.14 s |
| edit (one 42-function batch rebuilt) | 4.29 s | 0.42 s | 0.12 s |

Running the driver alone on a captured 152 MB manifest (`build --manifest-file=`), with
no frontend:
- cold build: 4.5 s wall;
- no-op build: 1.04 s wall. Of that, 0.30 s is codegen, and the rest is reading and
  parsing the manifest JSON.

**The programs behave the same:**
- QBE-BATCH-2 (`src/qbe_build_test.zig`) builds a three-module program batched and with
  `MYLANG_QBE_BATCH=1`, in Debug and in QBE ReleaseFast (frame map). It asserts identical
  output, exit status and trap trace.
- The Lox port, built by the lane and by the baseline, gives byte-identical stdout,
  stderr and exit status on all 254 corpus scripts, in Debug and ReleaseFast
  (`.tmp/lox_compare.py`). The lane's binaries are 0.1–0.2% smaller because the metadata
  strings merge.

## Gate (at `3ba6956a`, merged over `5c150f02`)

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 90/90 steps, 1,834 tests run, 0 failed |
| `zig build test-qbe --summary all` | 51/51 steps, 351/351 tests |
| `zig build test-qbe-build --summary all` | 33/33 steps (its tests ran inside `test-qbe`; 95 tests when it ran alone earlier) |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |

## For the integrator and the frontend-reuse lane

**How a batch gets each unit's IL and object key** (`State.compileBatches` in
`src/qbe_build.zig`):

1. **Planning.** For every manifest unit, `il = v.text(v.get(unit, "il"))`. It is read once
   for `batch.definesData(il)`, which sets `Unit.alone`, and once for
   `key = self.cache.unitKey(il)`. The module comes from `batch.moduleOf(name)`. Units are
   sorted by (module, symbol), and `batch.plan(units, batch.policy(environ))` groups them.
2. **Code object.** For each batch, `batch.key(cache, member_keys)` computes
   `cache.derived("qbe-batch-v1", join("\n", member_keys))`, then calls
   `cache.cached(key)`.
   - On a hit, nothing else happens.
   - On a miss, `fitsQbe(unit)` reads the IL again and the IL texts go into
     `batch.Miss{ .input = .{ .il = [...] } }`. `batch.startJob` writes each one through
     `batch.sectioned(il)` to `<work>/<n>.ssa`.
3. **Metadata object.** `outputs.metadataAssembly(members)` reads `symbol`, `name`,
   `locations`, `messages` and `inlines`, but no IL. Its key is
   `cache.derived("qbe-batch-metadata-v1", assembly_text)`.
4. **Shared unit.** `outputs.sharedMetadata(manifest)` still reads **every unit's IL**:
   `literalDefinitions` looks for `# myl-lit` markers and `frameMapRoots` for `dbgfile`.
   On the LLVM full-LTO path, `State.usesFrameMap` does the same. This behaviour predates
   the lane.
5. **Report.** Each record's `key` is the unit key, and its `object` is the batch's object.

With a lean manifest (`il_digest`/`il_file`), reconciliation is mechanical:
- Key with `unitKey(digest)`. Any digest that names the IL text works.
- Read `il_file` only where IL text is needed: `Miss.input.il`, `fitsQbe`, and the two
  whole-program scans in step 4. Those scans want per-unit facts from the frontend (a
  frame-map flag and the literal lines).
- For `alone`, either carry a manifest flag or drop the check. The frontend emits no
  `data` in unit IL today, so `definesData` is only a safety net.

**`qbe_build_cache.zig` API on this branch** (all `Cache` methods):
- `pub fn unitKey(self: Cache, il: []const u8) Error![]const u8` returns the 64-hex key
  that a per-function object carries: `identity("function", il)`, the same value the LLVM
  arm's `stage("function", il, …)` computes.
- `pub fn derived(self: Cache, kind: []const u8, input: []const u8) Error![]const u8` is
  the same identity under another kind.
- `pub fn cached(self: Cache, key: []const u8) Error!?Object` returns `<generation>/<key>.o`
  with `.reused = true` when that file exists and its `<key>.digest` fingerprint matches;
  otherwise null.
- `pub fn keep(self: Cache, key: []const u8, candidate: []const u8) Error!Object` publishes
  a caller-built object and its fingerprint.
- `annotateAssembly` is public.
- `identity` itself changed. It is SHA-256 over `"mylang-object-key-v2"` plus the
  length-framed environment JSON, contract fingerprint, kind and input; it no longer
  JSON-encodes the input. This changes every object key on both arms, which is harmless
  because the driver identity moved anyway.

**Conflict risk** is highest in `State.compile` / `compileUnits` / `compileBatches`
(`src/qbe_build.zig`), `Cache.identity` / `unitKey` / `cached` (`src/qbe_build_cache.zig`)
and `Context.read` / `command` / `digest` (`src/qbe_build_io.zig`). The SPEC bullets sit
after QBE-DRIVER-IDENTITY-1: QBE-SPAWN-1, QBE-BATCH-1/2/3 and QBE-BUILD-READ-1, plus an
amended QBE-DRIVER-IDENTITY-1.

**Findings for other lanes:**
- `std.hash.XxHash3` in Zig `0.17.0-dev.1683` runs at about 20 MB/s on long inputs. The
  frontend uses it for payload checksums in `src/frontend_cache.zig` (lines 307, 396) and
  `src/semantic_store.zig` (lines 319, 482). It is probably a real part of the warm
  frontend time; Wyhash is a drop-in replacement.
- At 50k the driver spends about 0.7 s reading and parsing the 152 MB JSON manifest. The
  lean manifest removes most of that.
- 200k fails in the frontend at 5.6 GB resident under the 8 GiB ceiling.

## Known gaps and follow-ups

- **200k does not build.** The frontend runs out of memory before codegen starts; that is
  the other lane's work. The driver alone holds about 0.9 GB for the 50k manifest, so it
  would hold about 3.6 GB at 200k, under the ceiling.
- **The link is still `zig cc`** (0.12–0.14 s at 50k). It is cheap, and an unchanged
  build still skips it (BUILD-BACKEND-4). There is no incremental link.
- **Tool diagnostics now print in completion order**, not start order.
- **`mylang test` still uses `std.process.run`** for its per-graph `mylang build
  --library` child (`src/native_test_session.zig`). That parent is small, so it is not a
  bottleneck at 50k.
- **The measurements share the machine** with other lanes (load 2–3); the integrator
  should re-measure on a quiet machine.
