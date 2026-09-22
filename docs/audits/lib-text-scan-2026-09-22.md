# Text scanning by `memchr`/`memmem` — wave 0 lane report, 2026-09-22

**Headline.** `str.count`, `str.replace`, `str.split` and `bytes.split`
compared the needle at every octet with a `memcmp` call. They now share one
bulk search and one counter:

- **`count` and `replace` beat Zig.** Over a 4 MB text, `count` goes from
  3.33× to **0.62×** Zig's `std.mem.count` and `replace` from 1.74× to
  **0.40×** Zig's `std.mem.replaceOwned`. The target was within 1.5×.
- **`split` misses its target.** It goes from 6.10× to **3.72×** Zig's
  `std.mem.splitSequence`, against a target of 1.5×. The scan is no longer the
  cost: each piece is still a freshly allocated `str`, and allocation plus
  collection is now the largest cost of the program.
- **`text_ops` goes from 7.27× to 4.97× Zig** (95% interval [4.32, 5.20]). That
  meets the plan's wave-0 target of ≤ 5× at the median. It misses the lane
  brief's ≤ 2×, for a measured reason. After the change, allocation and
  collection take 47% of `text_ops` samples. Building the text (f-strings,
  `strings.repeat`, `join`) takes about 3× Zig's time for the whole program.
  Neither cost is in the scanning code.

All numbers come from a loaded machine (other agents were building). The
coordinator re-measures at integration.

The same change fixes a quadratic cost in pieces of non-ASCII text. A split,
`splitlines` or whitespace split of a non-ASCII text walked the receiver from
its first octet twice for every piece. Each piece now counts only its own
octets.

Branch `perf/lib-text-scan` from `base/parity-20260922` (`bbabfc85`). Result
JSONs are in
[`results/wave0/`](../../experiments/perf-parity-plan-20260922/results/wave0/).
The micro benchmarks are in
[`lib/`](../../experiments/perf-parity-plan-20260922/lib/LIB.md).

## 1. The profile before the change

The SIGPROF profiles (`prof.py`, 10 runs, CPU 2) use the base compiler's
default ReleaseFast build with `--keep-symbols` (LLVM O3 + LTO). They are in
`results/wave0/profiles/text_ops.before.lto.json` and `…after.lto.json`.

| share of `text_ops` samples | before | after |
|---|---:|---:|
| `heap_alloc_at` + `heap_collect` + `trace` + `slot_take` | 37.4% | 47.0% |
| shared libraries (glibc `bcmp`, `memset`, `calloc`, `memcpy`, `memchr`) | 22.0% | 20.2% |
| `text_split` + `octets_find` | 9.2% | 7.5% |
| `text_replace` | 5.1% | 0.4% |
| `text_count` | 2.6% | not sampled |
| guest `main` (loop, f-strings, comprehension) | 7.7% | 11.2% |
| `text_join`, `concat`, int rendering, `from_utf8` | 7.6% | 10.8% |

Samples per run fell from 217 to 185. In absolute terms:

- **The scan costs went away.** `split`, `replace` and `count` fell from about
  37 ms to about 15 ms per run, and all of the per-offset `bcmp` calls inside
  the shared-library share are gone.
- **Allocation and collection did not change,** at about 81 ms before and
  87 ms after.

A non-LTO `--keep-symbols` build (`text_ops.before.o3.json`) gives the same
picture: allocation and collection take 41% of samples, and scanning takes
19.6% (`bcmp` 10.4%, `split` 3.4%, `replace` 4.1%, `count` 1.7%).

That build's `memcmp` resolves to `compiler_rt`'s bytewise `bcmp`, which is
statically linked. The LTO build calls glibc's instead. So non-LTO profiles
over-weight `memcmp`, and the LTO profile is the one to trust here.

The phase costs on the base compiler come from cumulative programs in
[`lib/phases/`](../../experiments/perf-parity-plan-20260922/lib/phases/):
build only, then adding lines, fields, replace and count.
Building the text took 78 ms. Splitting the lines added 27 ms, splitting the
fields 61 ms, and `replace` plus `count` 39 ms, for a total of 206 ms. Zig runs
the whole program in 26–34 ms.

## 2. What changed

All changes are in `src/native_text.c`, `src/native_text_methods.c`,
`src/native_bytes.c` and `src/native_text.h`. No compiler source changed.

- **One search, `myl_native_octets_find`.**
  - A one-octet needle uses `memchr`.
  - A longer needle uses `memchr` to find its first octet, then confirms the
    rest with an inline loop, because a `memcmp` call per candidate is the cost
    being removed.
  - After 8 candidates fail, the search hands the rest of the haystack to
    `memmem`. Otherwise a first octet that keeps recurring without a match
    (the needle `aab` in a run of `a`) would cost one `memchr` call per octet.
    `memmem`'s own scan stays linear, and a search that matches early never
    pays `memmem`'s per-call table setup.
  - `find` and `in` go through this search too; before, they called `memmem`
    directly.
- **One counter, `myl_native_octets_count`.**
  - A one-octet needle cannot overlap itself, so its count is a plain tally.
    The compiler vectorizes it, and a 32-bit sum per 64 KiB block keeps the
    lanes wide.
  - A longer needle repeats the search, advancing past each match.
  - `count` is this counter.
- **`replace`** makes one counting scan to size its result exactly, as it did
  before. The copying pass then finds the same matches again and copies each
  unchanged run with one `memcpy`. Before, it copied octet by octet with a
  `memcmp` at every offset.
- **`split(sep)`, for text and byte strings,** first counts its cuts with the
  counter. It then allocates the result list once, at its final length, and
  writes each piece into its reserved slot, exactly as an append that finds room
  would. The list never grows, so no piece needs a root between its allocation
  and its store, and no list backing is thrown away.
  - Measured in a C harness over the real runtime (200,000-line text,
    10 rounds, interleaved): presizing with in-place fill was about 5% faster on
    both split phases than the same search with append-and-grow. That is
    within the noise of this loaded machine, so the change is kept for the
    memory reason below rather than for speed.
  - Peak memory can only fall: the old growth path reserved up to twice the
    final length and left the smaller backings for the collector.
- **`substring`** counts the scalars of the piece's own octets, instead of
  walking the receiver from octet 0 to both ends of the piece. A piece whose
  every octet begins a scalar is flagged ASCII, so later indexing into it is by
  octet.

### Semantics

- **Matching.** Matches are non-overlapping and scanned left to right:
  `"aaa".count("aa") == 1`, `"aaa".replace("aa", "b") == "ba"` and
  `"aaa".split("aa") == ["", "a"]`.
- **Empty needles.** An empty needle still traps `R_EMPTY_SEPARATOR` before the
  runtime runs. Called directly, the runtime still answers `count` 0,
  `replace` NULL and `split` NULL.
- **No count argument.** `replace` takes no count argument: its method arity
  is two.
- **UTF-8.** A valid UTF-8 needle begins with a lead octet, so an octet match
  can only start where a scalar starts. It ends where one ends, so byte search
  is exact. `find` still converts the octet offset to a scalar index.
- **Memory budget.** A refused allocation still answers NULL, which surfaces
  as the budget trap. No path needs more memory than before.

The new guest tests pass on the base compiler as well as the branch. They
check answers, not implementation.

### Siblings checked

`str` has no `index`, `rfind` or `partition`; the method table has none, and
`index` is a list method. The rest were checked for a `memcmp` call per offset:

| routine | per-offset `memcmp`? | action |
|---|---|---|
| `startswith`, `endswith` | no: one `memcmp` per call | left unchanged |
| `strip` | no: a per-octet predicate over the trimmed ends only | left unchanged |
| `splitlines`, `split()` | no: per-octet predicate loops | their pieces get the `substring` fix |
| `bytes.find` | no: already `memchr`/`memmem` | left unchanged |
| `join` | no search | see below |

`join` makes two passes over its items and does no search. Two changes were
measured in the C harness and not kept:

- prefetching items 8 ahead gave no measurable change;
- inline fixed-width copies for short pieces instead of `memcpy` saved about
  10% of `join`, about 0.7 ms of `text_ops`, which is within the run-to-run
  noise.

## 3. Measurements

The batch ran `bench.py` for 11 rounds pinned to CPU 2, on a loaded machine
(load average 4–9). `before` is the base compiler
(`perf-audit-20260922/install-a3`). `my` is this branch built ReleaseFast. The
table gives the median paired ratio to `zig-fast`, with its 95% bootstrap
interval. The data is in `results/wave0/text-scan.json`.

| program | Zig ms | before | after (`my`) | `text_ops_tuned` | RSS after / Zig |
|---|---:|---:|---:|---:|---:|
| `text_ops` | 34.4 | 7.27 [6.31, 7.63] | **4.97 [4.32, 5.20]** | 0.68 [0.58, 0.80] | 80.8 / 8.0 MB |
| `scan_count` | 197.1 | 3.33 [3.13, 5.87] | **0.62 [0.55, 1.01]** | | 7.4 / 4.5 MB |
| `scan_replace` | 232.5 | 1.74 [1.61, 1.78] | **0.40 [0.37, 0.46]** | | 18.6 / 15.7 MB |
| `scan_split` | 53.4 | 6.10 [5.46, 7.25] | **3.72 [3.42, 4.42]** | | 164.0 / 4.5 MB |

CPU-time ratios agree to within 0.02.

The Zig reference for `text_ops` ran 34.4 ms here, against 26.0 ms in the
audit's batch. Every ratio above is paired within one round, so the load
cancels to first order.

The three `scan_*` programs are new, in
[`lib/`](../../experiments/perf-parity-plan-20260922/lib/LIB.md):

- a `.my`, `.zig` and `.expected` for each;
- the expected output is transcribed from CPython by `lib/expected.py`;
- each scans the same 4.03 MB text, built once by a join.

Scan cost alone (C, `-O3 -march=native`, glibc; milliseconds per pass over the
4 MB text):

| needle | per-offset `memcmp` | new | `memmem` loop |
|---|---:|---:|---:|
| `,1` (24,640 matches, 440,000 first-octet candidates) | 52.2 | 4.6 | 4.6 |
| `\n` (one octet, 220,000) | 20.2 | 0.5 | 2.1 |
| `item1` | 47.1 | 2.0 | 5.1 |
| `item` (220,000 matches) | 46.4 | 2.4 | 7.4 |
| `x\nitem` | 41.2 | 6.1 | 7.7 |
| `aab` in 4 MB of `a` | 50.4 | 25.5 | 25.1 |

The last row is the adversarial case, where the search falls back to `memmem`.
It is still twice as fast as before and never worse than `memmem`.

## 4. Why `split` and `text_ops` stay above target

`scan_split` after the change (`results/wave0/profiles/scan_split.after.lto.json`):

- allocation and collection (`heap_alloc_at`, `heap_collect`, `trace`,
  `slot_take`) take **39.5%**;
- shared libraries take **33.6%**, mostly `memset` zeroing of each reclaimed
  slot, `calloc` of fresh segments and `memcpy` of the pieces;
- `text_split` itself takes 12.7%, including the inlined piece construction;
- `octets_find` takes 9.2%.

Zig's `splitSequence` hands out slices of the input and allocates nothing. The
mylang program allocates 2.5 million `str` objects across its three rounds.
Its peak RSS is 164 MB against Zig's 4.5 MB.

The plan already names the fixes, and neither is a scanning change:

- shared `str` slices (§5.4, the `perf/str-views` lane);
- an inline allocation fast path (§6.5).

In `text_ops`, building the text alone (the comprehension of f-strings, `pad`
through `strings.repeat`, then `join`) took 78 ms on the base compiler. That is
about 3× Zig's time for the whole program. The field loop allocates five
objects per line: the list header, its storage, and three pieces. The ≤ 2×
brief target needs the allocation work of §5.4 and §6.5, and a cheaper text
build.

`text_ops_tuned.my` shows the language can already express the fast version: it
runs at 0.68×.

## 5. Found on the way, outside this lane

- **`strings.repeat` is quadratic.** In `src/stdlib/strings.my` it runs
  `out = out + text` once per copy, so `repeat("x", 100000)` copies about
  5 GB. `text_ops` only calls it with counts up to 6, where a single-allocation
  version saves nothing measurable. Large counts need a doubling or join-based
  implementation.
- **`bytes.find_any` with a two-octet set can go quadratic.** It calls `memchr`
  once per octet, and each call scans to the end of the input when that octet
  is absent. A loop of `find_any(b"\n,", at)` over input with no commas is
  therefore quadratic. A bounded second scan would fix it: search for the
  second octet only up to the first octet's hit.
- **The allocator zeroes every reclaimed slot** (`free_list_pop`'s `memset`),
  including text payloads that the caller overwrites immediately. That is part
  of the 20–34% shared-library share above; it belongs to the allocation lane.
- **Non-LTO `--keep-symbols` builds link `compiler_rt`'s bytewise `bcmp` and
  `memcpy`,** where LTO builds call glibc's. A profile of a non-LTO build
  over-weights every `memcmp` and `memcpy`.

## 6. Tests

- **Guest tests.** `tests/lang/text_scanning.my` has eight tests with spec
  tags `TEXT-SCAN-1` to `TEXT-SCAN-3`, bulleted at the end of `SPEC.md`'s
  surface-syntax section. They cover:
  - empty haystacks;
  - matches at the start and end;
  - overlapping candidates;
  - more than 8 failing first-octet candidates, which forces the `memmem`
    fallback;
  - multi-byte UTF-8 needles and haystacks, including `find`'s scalar index and
    `len` and indexing of the pieces;
  - no match, and a needle longer than the haystack;
  - 0.7–1 MB inputs;
  - byte-string splits.

  They pass under `--gc-stress` on this branch and on the base compiler.
- **C tests.** `tests/native_text_methods_test.c` (search, count, replace,
  split, presized capacity, ASCII flag on pieces) and `tests/native_bytes_test.c`
  (byte split) collect on every allocation. They pass under
  `scripts/test_native_memory.py`, with UBSan and with
  `MYLANG_TEST_ASAN=1`.

## 7. Gate

The runtime and test changes were committed as `2701b93b`. Each step ran
through the slot wrapper, and each log was compared with the base log by
`gate_diff.py`:

| step | result | against the base |
|---|---|---|
| `zig build test --summary all` | 53/73 steps, 1618/18549 tests passed, 46 failed | same summary as the base; `gate_diff`: 47 base failures, 47 lane failures, **0 new**, 0 cleared |
| `zig build test-qbe --summary all` | 43/48 steps, 270/272 tests passed | same as the base; **0 new**, 0 cleared |
| `zig build test-qbe-build --summary all` | 30/30 steps succeeded | green |
| `zig build fmt-check` | exit 0 | green |

Guardian passed all 88 checks in every step and in the pre-commit hook.
`test-lang` ran 259 tests with 0 failures, including the eight new ones.
`doc-coverage` reported 0 failures, and the native heap C harness passed.

## 8. What is left

- **`split`'s per-piece objects,** and with them `text_ops`'s allocation half,
  wait for §5.4 (shared `str` slices) and §6.5 (inline allocation).
- **The text-building phase** (f-string rendering, `concat` from
  `strings.repeat`, `join`) is now the largest single phase of `text_ops`.
- **`splitlines` and the whitespace split** still grow their result lists and
  root each piece. They could be presized the same way; neither is in the suite.
