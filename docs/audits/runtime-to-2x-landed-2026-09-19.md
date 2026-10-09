# Runtime toward 2×: what landed, what was priced, and what is left

19 September 2026. Landing report for the work
[runtime-to-2x-2026-09-19.md](runtime-to-2x-2026-09-19.md) ranked. Every number
below comes from a matched A/B measurement — both sides built by the same driver
and timed in one interleaved batch, so only ratios inside a batch are compared.
Raw samples, binary hashes and output digests:
[experiments/sexpr-audit/evidence/runtime-levers](../../experiments/sexpr-audit/evidence/runtime-levers/README.md).

## Decision

Three changes landed, each measured before and after, each with the full gate
green:

| landed | census 927 KB | render 927 KB | census 7.42 MB | render 7.42 MB |
|---|---:|---:|---:|---:|
| bulk raw-text output (`76c7e58f`) | −0.0% / +0.0% | **−8.2% / −4.1%** | +0.0% / −0.2% | **−7.9% / −3.6%** |
| coallocated `str` (`b3b01b50`) | −2.9% / −4.1% | −3.2% / −4.3% | −4.1% / −6.6% | −4.0% / −6.2% |
| no exit sweep in a final run (`caeb4227`) | −3.1% / −4.5% | −2.5% / −3.2% | −2.9% / −6.4% | −2.4% / −5.8% |

(instructions / cycles, per the sections below; the census columns are control
workloads for the bulk-output row, which cannot affect them.)

Together, over the same batch: census 927 KB **−6.0% instructions, −7.7%
cycles**, render 927 KB **−13.4% / −12.0%**, census 7.42 MB **−6.9% / −12.5%**,
render 7.42 MB **−13.6% / −14.7%**. Measured against the frozen Zig ReleaseFast
reference in that same batch, the port now runs at **5.79× / 5.47×** (census),
**7.46× / 6.65×** (render), **6.14× / 6.72×** (census 7.42 MB) and **7.77× /
7.96×** (render 7.42 MB) — Zig's instructions / cycles against mylang's.

Aggregate scalar replacement was **priced and rejected**: every aggregate copy in
the census executes 492,214 times at 8.8 instructions each, 3.74% of the run, and
that whole figure is the ceiling for a pass, most of it ABI copies value
semantics requires (§4). The next real lever is object count and collection
pacing, not copies (§5).

## 0. Wall clock against Zig, after the three landings

31 interleaved rounds per task, parent and children pinned to CPU 6, median wall
time, all eight tasks in one batch. The process-launch control was 0.52 ms for
`/bin/true`, quieter than the 0.66 ms the audit's batch saw.

| workload | mylang | Zig ReleaseFast | ratio | ratio of minima |
|---|---:|---:|---:|---:|
| census 927 KB | 8.80 ms | 2.05 ms | **4.30×** | 4.75× |
| render 927 KB | 13.70 ms | 2.60 ms | **5.26×** | 5.44× |
| census 7.42 MB | 79.49 ms | 13.64 ms | **5.83×** | 5.92× |
| render 7.42 MB | 121.65 ms | 18.98 ms | **6.41×** | 6.46× |

Wall is a friendlier ratio than the counters for this program: the counter batch
above reads 5.79×/7.46×/6.14×/7.77× on instructions and 5.47×/6.65×/6.72×/7.96×
on cycles, because mylang's extra work is largely memory traffic with poor IPC
while Zig's loops retire more per cycle.

**Do not read the audit's baseline ratios as a like-for-like improvement.** Its
batch had the same workload at 15.15 / 24.80 / 130.06 / 203.74 ms and 5.50× /
6.51× / 6.82× / 7.81×, but mylang's census fell from 15.15 ms to 8.80 ms, far more
than the 6% of instructions the landings removed: the machine differed. The
attributable result is the in-batch one — 6–15% fewer instructions and 8–15% fewer
cycles — and everything below is quoted from matched batches only.

Reaching ≤2× from here needs 53% less time on the 927 KB census, 62% on the 927 KB
render, and 66–69% on the two 7.42 MB workloads.

## 1. Bulk raw-text output — landed

`myl_print_text` walked a raw `str` one scalar at a time: a call to
`myl_print_raw`, a capacity test and a branch per character, so printing a 900 KB
rendering meant a million calls through the growable-buffer path. At depth zero
the value needs no quoting or escaping, so it is now sized once through
`myl_native_text_utf8`, reserved once through the same doubling grower
`myl_print_raw` uses, and filled directly. Nested text keeps the repr-quoting and
escaping loop, and the two callers that print raw text — `stream.print` and
`stream.write` — are unchanged.

This reproduces the audit's prototype (7.5% fewer instructions, 5.6% fewer cycles,
3.8% less wall) as production code with the pieces the prototype left out: one
shared reserve helper, an empty value writing nothing, and a line that cannot grow
setting the same failure the finish path turns into an allocation trap.

## 2. Coallocated text — landed

A run-time `str` cost two managed allocations: a 168-byte list object and a
backing array behind a 96-byte header of its own, 264 fixed bytes plus four per
scalar, and the collector traced the second through the list's `storage` field.
Text has no traced children — its payload is u32 scalars — so the header and the
scalars now share one block: `myl_native_heap_alloc_block` allocates `prefix +
extra` payload bytes under a PLAIN one-byte descriptor, which keeps the
collector's drain loop off the payload entirely, and `myl_native_text_new` lays a
`myl_native_list` header at the front and points `storage` at the tail.

A nonempty text is now 168 fixed bytes and one allocation instead of 264 and two.
`length`, `capacity`, `element`, `storage` and every offset generated code encodes
are unchanged, an append still grows an ordinary backing array because
`length == capacity`, and a static literal keeps the image shape it already had.
Peak RSS falls 12.5% on the 927 KB census and 8.4% on the 7.42 MB one. The gain
grows with input size, which is what a per-object representation change should do:
the larger run holds more live text, so the collector marks and sweeps fewer
objects. All eight text constructors funnel through the new entry point; the
`str` operations themselves did not change.

## 3. No exit sweep in a final run — landed

Every native process freed every object still live before returning from `main`.
Nothing can observe that walk, and on the larger input it was the largest
self-time entry after the collector's own marking (4.6% of cycles; 2.2% on the
927 KB census). A ReleaseFast executable's generated entry now declares that its
single run is the process's last, and the runner leaves the heap to the process.

The declaration is opt-in and explicit:

* a **Debug** executable keeps the sweep, which is where it earns its keep as a
  heap check that `free` performs at exit;
* a **library** entry never makes the claim, so a host that calls the guest
  repeatedly still reclaims each run's heap;
* the collector's own sweeps of unreachable objects, traps, exit statuses, output
  and `--gc-stress` are untouched — only the final walk over survivors is gone.

The saving is larger in cycles than in instructions (−2.4% to −3.1% instructions,
−3.2% to −6.4% cycles) because the sweep is a pointer-chasing walk over the whole
live set.

## 4. Aggregate copies — priced, not built

The audit's §3 asked for a counterfactual before any general pass. Every aggregate
copy was counted by temporarily emitting a counter call before each `blit`
([`blit-count.patch`](../../experiments/sexpr-audit/evidence/runtime-levers/blit-count.patch)),
then priced by emitting each copy **twice**: the second copy is idempotent, so the
instruction delta over the unmodified build is the exact cost of all of them.

| workload | executed copies | per copy | total | share of run |
|---|---:|---:|---:|---:|
| census 927 KB | 492,214 | 8.82 | 4,341,227 | **3.74%** |
| census 7.42 MB | 3,937,684 | 8.82 | 34,726,302 | **3.54%** |
| render 927 KB | 563,734 | 9.28 | 5,233,308 | **3.01%** |
| render 7.42 MB | 4,509,844 | 9.28 | 41,862,929 | **2.90%** |

Three things follow.

1. **3% is the ceiling, not the prize.** That is the cost of *every* copy in the
   program, including the parameter and return-storage copies value semantics
   requires at every call — 40-byte records and 24-byte spans moving across the
   ABI — which no scalar-replacement pass removes.
2. **The eliminable remainder is a fraction of it.** The parser functions that
   hold most of the static `blit`s (`parse_node` 29, `span_of` 26, `parse_list`
   23, `push_node` 17, `estimate_width` 17 of 283) account for 3.9–5.3% self time
   together, and that includes all their other work.
3. **QBE already removes some of them.** A reduced experiment that added extra
   record copies to a loop found them not all surviving: `copy3` cost more than
   `copy1`, but `copy5` came out *cheaper* than `copy1` because the extra
   bindings were folded away. Any pass would be competing with that.

So the recommendation stands that this is not the next thing to build.

## 5. Where the remaining gap is

`perf record` self time, both census sizes, after §1 and §2 and before §3
(symbolized through the build manifest; kernel frames unresolved):

| self time | 927 KB | 7.42 MB |
|---|---:|---:|
| tokenizer (`tokenize`, `read_string`, `is_atom_continue`, `read_atom`, `read_number`, `lexeme`) | ~46% | ~31% |
| collector (`trace`, `heap_collect`, `heap_alloc_at`, `cfree`, `fastMemset`) | ~14% | ~17% |
| parser (`parse_list`, `parse_node`) | ~10% | ~8% |
| teardown (`heap_destroy`) | 2.2% | 4.6% |
| text conversion (`text_from_utf8_checked`, `list_get`, `list_append`) | ~8% | ~8% |

The tokenizer is the single biggest block and is now mostly scanning; §4's earlier
work already removed the per-byte decoder and the per-token allocation it could.
What grows with input size is the **collector**: marking is 6.2% of the small
census and 16.1% of the large one, collection 2.4% and 9.5%. It is cache-miss
bound, so it scales with the number of live *objects*, not with the bytes they
hold — which is exactly why §2 paid off more on the large input and why the same
treatment applied to lists is the next priced idea.

Concrete next steps, in the order the evidence supports:

1. **Coallocate ordinary lists** (the memo's Design C): the same 96 bytes and one
   allocation per list, and the same reduction in marked objects. Lists are as
   numerous as strings here (`forms` alone is 4,050 on the small census and 32,400
   on the large one, each with a children list, plus the token list), and this
   needs the collector to learn one marker descriptor whose payload is a list
   header followed by its elements. It is a bigger change than §2 — the collector
   must trace the tail — and it should be measured the same way.
2. **Collection pacing**: the marking cost is `live set × collections`, and the
   trigger (`bytes*3 + 4 MiB`) collects about four times on the large census.
   Trading peak RSS for fewer marks is a policy change and needs measuring on both
   inputs before it is worth its budget consequences.
3. **An idiomatic streaming port**, which the audit already separates from the
   frozen benchmark: consuming tokens on demand and borrowing slices is an
   application change, not a compiler one, and it is the only lever that removes
   the token list and the token texts rather than making them cheaper.
4. **ASCII text storage**: still the largest representation idea, still gated on
   `myl_native_text_points`, whose raw `u32 *` generated code consumes directly
   (`qbe_text.zig`); it needs a new parse entry point or materialisation before it
   can be priced honestly.

## 6. Verification

Each landing ran the full gate before its commit — `zig build test` (58/58 steps),
`test-qbe` (36/36), `test-qbe-build` (22/22), `fmt-check` — with Guardian
whole-tree checks on the commits. Beyond the gate:

* census and render output byte-identical with and without `--gc-stress`, for
  every binary involved;
* all 17 rendering goldens pass with every binary involved;
* 214 guest tests under `mylang test tests/lang` (each built and run natively
  under `--gc-stress`) pass with the coallocated text, which is the test that
  would catch a descriptor still tracing `storage`: a wrong one corrupts or
  crashes there rather than leaking quietly;
* every measurement re-checks stdout on every timed round and aborts on a
  mismatch, and the census workloads move by 0.00% instructions, which is the
  resolution of the protocol.

Reported wall times are medians of nine interleaved samples and are only quoted
where they agree with the counters: the machine had other active processes, and a
control workload moving ±1.6% bounds what a wall column can prove here.

## 7. Reproduce

```sh
git checkout caeb4227            # the last landing
zig build                        # installs the compiler and its runtime archives
zig-out/bin/mylang build experiments/sexpr-port/main.my -o /tmp/rt2x/final
python3 experiments/sexpr-audit/evidence/runtime-levers/measure.py \
  --a /tmp/rt2x/block --b /tmp/rt2x/final --out /tmp/rt2x/teardown.json
```

`measure.py` builds nothing and compares two already-built executables inside one
batch; the README in the evidence directory gives the command for each landing and
for the aggregate-copy count. The byte-identical outputs and digests for every
run are in the JSON beside it.
