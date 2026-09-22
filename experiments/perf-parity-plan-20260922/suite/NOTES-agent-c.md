# Agent C notes: knucleotide, raytrace, text_ops (SUITE.md sections 6, 10, 11)

## Setup and method

- mylang: `install-a3/bin/mylang build <file> -o … --cache-dir …`, default
  ReleaseFast (LLVM -O3 + LTO), no tuning flags. Zig 0.17.0-dev.1683
  `-O ReleaseFast`. rustc 1.98.1 `-C opt-level=3 -C codegen-units=1
  -C target-cpu=native -C panic=abort`.
- **All timings are rough, E-core, unpinned-load**: `taskset -c 12-19`,
  `/usr/bin/time -f '%e s %M KB'` (10 ms resolution), 3 runs per binary, run
  one at a time on a shared machine. Peak RSS is `%M`.
- Every port and variant prints bytes identical to `<bench>.expected`. Each
  `.expected` file was produced by an independent CPython transcription of
  SUITE.md (`work/agent-c/oracle/*.py`), not by one of the ports, so the three
  ports agree with each other and with the spec's text.
- No port contains FMA instructions (checked with objdump), so byte-identity
  follows from the specified operation order, not from luck.
- Ablations and diagnostic builds referenced below live in
  `.tmp/perf-plan-20260922/work/agent-c/{abl,diag}/`. None of them is a suite
  arm. The two `--unchecked` numbers are diagnostics only.

`common_c.zig` holds `writeStdout(bytes)`, a raw write-syscall loop. My Zig ports
format into one `std.ArrayList(u8)` with the list's own `print` and write once at
the end.

## Timing table (rough, E-core, unpinned-load)

| benchmark | port | run 1 | run 2 | run 3 | peak RSS |
| --- | --- | --- | --- | --- | --- |
| knucleotide | `knucleotide.my` | 0.94 s | 0.90 s | 0.87 s | 78 MB |
| knucleotide | `knucleotide_tuned.my` | 0.70 s | 0.61 s | 0.60 s | 28 MB |
| knucleotide | `knucleotide.zig` | 0.15 s | 0.14 s | 0.14 s | 9.6 MB |
| knucleotide | `knucleotide.rs` | 0.34 s | 0.23 s | 0.33 s | 16 MB |
| raytrace | `raytrace.my` | 0.61 s | 0.51 s | 0.50 s | 2.4 MB |
| raytrace | `raytrace_tuned.my` | 0.36 s | 0.35 s | 0.35 s | 2.4 MB |
| raytrace | `raytrace.zig` | 0.11 s | 0.10 s | 0.10 s | 0.4 MB |
| raytrace | `raytrace.rs` | 0.11 s | 0.10 s | 0.10 s | 2.2 MB |
| text_ops | `text_ops.my` | 0.29 s | 0.27 s | 0.27 s | 80 MB |
| text_ops | `text_ops_tuned.my` | 0.02 s | 0.02 s | 0.02 s | 10.6 MB |
| text_ops | `text_ops.zig` | 0.03 s | 0.03 s | 0.03 s | 8.0 MB |
| text_ops | `text_ops.rs` | 0.06 s | 0.06 s | 0.05 s | 17 MB |

For context, the CPython oracles took (single run, E-core) 1.27 s for
knucleotide, 12.85 s for raytrace and 0.20 s for text_ops. **`text_ops.my` is
slower than CPython.**

---

## 6. knucleotide

Files: `knucleotide.my`, `knucleotide.zig`, `knucleotide.rs`,
`knucleotide_tuned.my`, `knucleotide.expected`.

Expected output (25 lines, sha256 `85ef6171…08c0bb`):

```
G 250155
T 250058
C 249923
A 249864
GT 62591
CG 62559
GG 62557
TG 62543
GA 62535
TT 62521
TA 62509
CC 62498
AG 62496
TC 62484
AT 62480
GC 62472
AC 62468
CT 62466
AA 62420
CA 62400
15691	GGT
3912	GGTA
231	GGTATT
0	GGTATTTTAATT
0	GGTATTTTAATTTATAGT
```

### Spec note for the harness owner

**The k = 12 and k = 18 maps do not hold "about a million distinct keys".** The
`lcg` has full period 139968, so the generated sequence repeats every 139,968
bases and no k-mer map can exceed 139,968 keys. Measured distinct counts for
k = 1, 2, 3, 4, 6, 12, 18 are 4, 16, 64, 256, 4096, 138,716 and 139,948. That is
why Zig peaks at 9.6 MB. A million-key map needs a longer-period generator (the
suite's `xorshift`, for example). I kept the spec as written.

### Port choices

- mylang: the sequence is `"".join(parts)` of `"ACGT"[s * 4 // 139968]` one-scalar
  strings, and each `frequencies` call builds a fresh `dict[str, int]` with
  `counts[key] = counts.get(key, 0) + 1` over `seq[i:i + k]`.
- Rust: `HashMap<&[u8], u32>` with the default SipHash, updated through
  `entry().or_insert(0)`, and `sort_by` on (count desc, key asc).
- Zig: `std.StringHashMap(u32)` updated with `getOrPut`, then `std.mem.sort` with
  a lessThan on (count desc, `std.mem.order` asc).
- Sort order in mylang comes from two stable passes. The keys are sorted as a
  `list[str]` (which compares scalar values, the same as bytes for ASCII), then
  `Entry` records are sorted with `key=lambda entry: -entry.count`.

### Language friction

- **A sort key must be an `int`.** Python's `sorted(counts.items(), key=lambda
  kv: (-kv[1], kv[0]))` has no spelling:
  - a tuple key gives `E_TYPE: expected int, found tuple[int, str]`;
  - a `str` key gives `E_TYPE: expected int, found str`.

  Lambdas cannot capture locals, so `key=lambda k: -counts[k]` is out as well.
  A declared `record Entry` has to carry each count through the second pass.
- **`sorted(counts.items(), key=...)`** reports `E_PRELUDE_TYPE: sorted key
  requires a list input`, plus a cascading `E_LAMBDA_CONTEXT: lambda requires an
  expected callback type` on the same call. That second error is noise. The fix
  is `list(counts.items())`.
- **A two-name target inside a comprehension**, as in `[Entry(code, count) for
  code, count in counts.items()]`, reports `E_SYNTAX: unexpected token; expected
  in`. A `for` statement accepts the same target. I used `item.key` and
  `item.value` instead.

### Performance observations

**Overall:** mylang is ~6.3× Zig and ~3× Rust in time, and ~8× Zig in peak RSS.
`--unchecked` changes nothing (0.95 s), so the gap is in the runtime, not in the
compiled guest code.

**Ablations** (rough, E-core; sources in `work/agent-c/abl/kn_*.my`):

| ablation | time | what it shows |
| --- | --- | --- |
| generate the sequence only | 0.01 s | `"ACGT"[i]` returns the runtime's immortal one-scalar ASCII text, so it allocates nothing |
| 7 × 1M slices, no dict | 0.35 s | ~50 ns per GC-allocated copy |
| rolling 2-bit codes, no dict | 0.06 s | the key arithmetic is cheap |
| `dict[int, int]` counting, no strings | 0.64 s | ~83 ns per get+store |
| the same counting in a fixed-capacity open-addressing table over two `list[int]`s, written in mylang | 0.23 s | guest code beats the builtin dict ~2.8× |

About 1/3 of the idiomatic port is materializing slices and about 2/3 is the dict
itself.

**The builtin dict** (reading `src/native_dictionary.c`; with LTO these functions
are inlined into the guest loop, so call overhead is not the issue):

- Every get-then-store is two full probes for int keys. The "remembered entry"
  shortcut only applies to `str` keys.
- An 8-byte int key is hashed byte-at-a-time with FNV-1a plus an avalanche.
- The index holds only entry numbers, so every probe step loads the entry from a
  separate insertion-ordered list and compares the key.
- Values move with descriptor-sized `memmove`s.

**`knucleotide_tuned.my`** (keys packed 2 bits per base into an `int`, same
`dict`, same update spelling, same two stable sorts) runs in 0.60–0.70 s and
28 MB. That confirms the split above: dropping the `str` slices buys ~30% in time
and ~2.8× in peak memory. The dict remains the floor.

**Arenas make this program slower.** Wrapping each counting phase in
`with arena():` gives 2.3 s and 99 MB instead of 0.9 s and 78 MB. See the repro
section at the end.

**Where the 78 MB comes from:** the next collection is scheduled at 3× the live
bytes plus 4 MiB, and each phase allocates 1M short-lived slices, each with a GC
header.

---

## 10. raytrace

Files: `raytrace.my`, `raytrace.zig`, `raytrace.rs`, `raytrace_tuned.my`,
`raytrace.expected`.

Expected output: `203351956`. The CPython oracle agrees.

### Port choices

- **Scene data:** Zig and Rust build the scene at run time into an
  `ArrayList`/`Vec` and pass a slice to `shade`. This mirrors mylang's
  `list[Sphere]`, and it means no sphere data is comptime-known. With a global
  `const` scene the optimizer could fold the six spheres into the code.
- **`min`:** mylang uses the prelude two-value `min(c.x, 1.0)`. It lowers inline
  to `b if b < a else a`, which differs from the spec's `a if a < b else b` only
  for equal or NaN operands, and neither occurs here. Zig uses `@min` and Rust
  uses `f64::min`. The two-value form of `min` works but
  `docs/python-syntax.md` only documents the list form.
- **Hit index:** mylang uses the spec's `-1` sentinel. Zig and Rust use an
  optional index.

### Language friction

- **Module-level scene constants are not possible:**
  - `SPHERES = [...]` or `LIGHT = Vec3(...)` at module level gives `E_SYNTAX: a
    bare assignment declares no module-level binding`, with the alternative
    `const MAX: int = 42`;
  - `const LIGHT: Vec3 = Vec3(1.0, 1.0, 1.0)` gives `E_CONSTANT_NAME:
    compile-time call requires a visible source function`, which does not say
    that constants must be scalar literals.

  So `spheres` and `light` are threaded through `shade`'s parameters.
- Otherwise the port was straightforward: positional record construction
  `Vec3(a.x + b.x, …)`, `enumerate(spheres)`, prelude `sqrt`, and `break` in the
  shadow loop all worked on the first try.

### Performance observations

mylang is ~5× Zig and Rust. The diagnostic `--unchecked` build is 0.37 s, and the
tuned variant is 0.35 s (0.33 s unchecked).

In the disassembly of a `--keep-symbols` build, all float code is scalar in every
port. The differences are:

1. **Small helpers are not inlined.** `intersect`, `normalize` and `dot` stay out
   of line, and `dot` is inlined only under `--unchecked`. `main` and `shade` are
   inlined into the runtime's `entry_run`. Zig and Rust inline everything: 14
   `sqrtsd` sites against mylang's 2.
2. **`Vec3` goes through memory at those calls.** It is passed by pointer and
   returned through an sret slot. Sphere elements themselves are passed as
   pointers into list storage, with no copy.
3. **Frame protocol per call.** Every function pushes and pops a frame record on
   the context's frame chain (3 stores in, 1 load and 1 store out). Non-leaf
   functions also compare against the stack limit. **An inlined callee still
   pushes its own frame record**: `sub` inside `intersect` does.
4. **Source-position stores before each float op** (`movq $imm, pos(%rsp)`).
5. **A NaN check after every float operation.** Each op is followed by
   `vucomisd x,x; jp` to a cold call to `myl_qbe_float_canonical` (21 cold call
   sites in `intersect`). The canonical-NaN rule survives `--unchecked`. Because
   each op is a potential call site, the position store has to precede it.

**`raytrace_tuned.my`** writes the vector algebra out on float locals, keeping the
operation order so the checksum is bit-identical. It removes the record-returning
helper calls: ~40% faster, still ~3.4× Zig. What remains against Zig is the
out-of-line `intersect` (6–12 calls per pixel) plus per-operation code items 3–5.

---

## 11. text_ops

Files: `text_ops.my`, `text_ops.zig`, `text_ops.rs`, `text_ops_tuned.my`,
`text_ops.expected`.

Expected output:

```
10000066287 599994 20000
4066669 3666669 22228
```

### Spec note for the harness owner

**The Zig port runs 0.03 s on an E-core, below the 0.05–1.0 s target range.**
`lines = 1_000_000` would put it near 0.15 s. I kept the size as written.

### Port choices

- **mylang:** `"\n".join([f"item{i},{(i * 7919) % 100003},{pad(i % 7)}" for i in
  range(200000)])`, where `pad` wraps `strings.repeat`. Then `text.split("\n")`,
  `line.split(",")`, `int(...)` matched as an `Option`, `endswith`, `replace` and
  `count`.
- **Rust:** a `format!` per line, collected into a `Vec<String>` and joined with
  `join("\n")` (a direct transcription of the spec), then `split('\n')` and
  `split(',').collect::<Vec<&str>>()`, `parse::<i64>()`, `replace` and
  `matches(",1").count()`.
- **Zig:** lines are printed straight into one `ArrayList(u8)` with `"\n"`
  between them (how Zig builds joined text; no per-line allocation), then
  `splitScalar` iterators (no allocation), `parseInt`, `replaceOwned` and
  `std.mem.count`.
- The text is ASCII, so byte lengths equal scalar counts.

### Language friction

- **`'x' * n`** gives `E_TYPE: expected str, found int`. That reads as a
  wrong-operand error and does not say that repetition is unsupported.
  Repetition is `strings.repeat`, which returns `Result[str, strings.Error]`, so
  each call site needs a `match` (I used a helper).
- **`total += int(fields[1])`** gives `E_TYPE: expected int, found Option[int]`.
  Clear, and it forces a `match` per parse.
- **`"\n".join(f"…" for i in range(n))`** gives `E_SYNTAX: a generator
  expression is not provided`, with a helpful "materialize a list" alternative.
- **`bytes` has no `replace` or `count(sub)`,** and `find` takes no start
  offset:
  - `bytes.replace` and `bytes.count` give `E_COLLECTION_METHOD: this method
    requires str`;
  - `data.find(b",", 2)` gives `E_ARITY: bytes.find(needle: bytes) -> int takes
    1 argument`.

  The tuned variant hand-rolls both with `find_any(set, start)` and
  `append_range`.

### Performance observations

mylang is ~9–10× Zig and ~5× Rust in time, 10× Zig in peak RSS, and slower than
CPython. `--unchecked` changes nothing, so the cost is in the runtime.

**Phase ablations** (sources in `work/agent-c/abl/to_*.my`):

| phase | time | notes |
| --- | --- | --- |
| build (f-strings, `strings.repeat`, join) | 0.10 s | `strings.repeat` alone is ~0.03 s: it is guest code that concatenates one `"x"` at a time and returns a `Result` |
| `split("\n")` | 0.03 s | |
| per-line `split(",")`, `int()`, `endswith` | 0.08 s | 200k line objects plus 600k field objects |
| `replace` + `count` | 0.06 s | high for a 4 MB text |

**Runtime scanning** (`src/native_text_methods.c` and `native_text.c`): `count`,
`replace` and `split` advance one byte at a time and call `memcmp` at every
position. `replace` scans the input twice and copies unmatched bytes one at a
time. `memchr` or `memmem` bulk scans would fix all three.

**`text_ops_tuned.my`** runs in 0.02 s and 10.6 MB, on par with the Zig port.
It uses one `byte_buffer` built with `append_range`/`append_int`/`append_byte`, a
single `bytes(buffer)` snapshot, lines and fields located with `find_any` and
parsed in place with `parse_int_range`, and a rewrite into a second
`byte_buffer`. This shows that the compiler is not the problem here. The cost is
the allocating `str` surface (per-line and per-field objects, list
materialization, one `Option` per parse) and the per-byte runtime scans.

---

## Compiler bugs

No wrong output, crash or spurious trap in the 9 ports and 3 tuned variants.

### Performance pathology, with repro: `repro/arena_store_quadratic.my`

**Storing managed values into a container inside `with arena():` is quadratic.**
Appending 1M and then 2M fresh strings to a list inside an arena takes 0.30 s
and then 1.15 s. A `dict[str, int]` store behaves the same (0.5M 0.07 s, 1M
0.25 s, 2M 1.02 s). The same loops under the GC scale linearly (0.05, 0.09,
0.17 s), and allocating without storing inside the arena is linear too.

**Suspected cause:** each store runs the region barrier
(`myl_native_region_check` → `myl_native_object_region` for both the value and
the container). That lookup is `myl_native_arena_region` → `containing()`, a
linear walk of the arena's chunk list. Chunks cap at 1 MiB, and every arena
allocation also writes a 24-byte `Allocation` record, so a phase holding N small
objects has O(N) chunks. The header comment in `native_regions.c` says each
managed header carries its region depth, but the lookup walks the chunk list
instead.

**Effect on this suite:** an arena-wrapped knucleotide takes 2.3 s instead of
0.9 s.

## General friction

- **`mylang check` writes its cache into the working directory.** It creates a
  frontend/semantic `.mylang-cache/` there without being asked. The suite
  directory now has one, written by several agents including my first checks,
  and I left it in place because it is shared. `check --cache-dir=DIR` from
  another directory avoids it.
- **A `module main` header in a file not named `main.my`** gives
  `E_MODULE_NAME: declared module name does not match its requested path`. A
  headerless file with `import strings` works.
