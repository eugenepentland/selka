# Register-resident hot loops: plan and measured bounds — 2026-09-19

**Landed 2026-09-19; results in `hot-loops-landed-2026-09-19.md`.** Stages 0–4
and stage 1b's sticky-trap item shipped, and the census measures −29.7 % of
instructions and −21.9 % of cycles against `d14ea1a3`. Stage 1b's per-site
operand scratch was measured at +0.6 % of instructions and rejected. The stage
numbers below are the counterfactuals this plan was written against; the landing
report has the measured ladder.

The successor to the "what closing the remaining gap would actually take" section
of `runtime-performance-2026-09-18.md`. That section offered two paths: alias
information for the frame record inside QBE (option 1) and register-resident
lexer state in the lowering (option 2). Before planning option 2 this note
re-measured its premise, and the premise was wrong in a useful way: the field
traffic that option 2 targets is worth under 1 % of the program, while a
mechanism nobody had measured — GC root pushes pinning every local and operand
slot of the tokenizer's loop functions to memory — is worth about 10 % of cycles
on its own and is what has been making inlining a loss instead of a win.

Every number below is `perf stat` on this checkout, `taskset -c 6`, the 927,415
byte EDA input, minimum of seven runs, census program (`experiments/sexpr-port/
main.my`), byte-identical output checked against the baseline for every variant.
Counterfactual variants are IL rewrites of the `emit-project-qbe` manifest built
with `--manifest-file`, so they measure the generated code with no compiler
change; the scripts and hand-written IL are under
`experiments/sexpr-audit/evidence/hot-loops/`. The Zig reference is the frozen
`zig-bench` (22.9 M instructions, 8.0 M cycles on the census).

## 1. What the counterfactuals say

| census variant (all outputs identical) | instructions | cycles | Δ instr | Δ cycles |
| --- | ---: | ---: | ---: | ---: |
| baseline (`d14ea1a3`) | 228.6 M | 65.7 M | — | — |
| `advance` hand-written register-resident (option 2 on the hottest function) | 226.6 M | 63.9 M* | −0.8 % | ≈ 0 |
| every add/sub overflow check removed (77 sites) | 220.6 M | 63.4 M* | −3.4 % | −0.8 % |
| `advance` inlined (inliner cap 48 → 64), nothing else | 220.8 M | 71.7 M | −3.4 % | **+9.2 %** |
| **roots hold values, slots stay promotable** (§2) | 207.5 M | 59.3 M | −9.2 % | **−9.6 %** |
| value roots + `advance` inlined | 181.7 M | 56.1 M | −20.5 % | −14.6 % |
| value roots + inlined + QBE load elimination run twice (§4) | 177.5 M | 55.0 M | −22.3 % | −16.3 % |
| … + every hot-path position store removed (upper bound for `QBE-POSITION-2`) | 162.7 M | 53.1 M | −28.8 % | ≈ −19 % |

\* measured in an earlier batch against a 63.9 M baseline; the deltas are within
that batch.

Wall clock for the same binaries (minimum of 36 interleaved runs, `/bin/true`
0.712 ms under the harness, Zig 2.327 ms):

| variant | wall | reported ratio | compute-only ratio |
| --- | ---: | ---: | ---: |
| baseline | 15.911 ms | 6.84× | 9.4× |
| value roots | 15.132 ms | 6.50× | 8.9× |
| value roots + inlined + loadopt twice | 13.900 ms | 5.97× | 8.2× |

Absolute times drift between batches with machine state (the same baseline
measured 20.1 ms in a batch run beside a `zig build`); only ratios inside one
batch are comparable.

Three conclusions, each carried by a row above:

1. **Option 2 as originally stated is not the lever.** A hand-written `advance`
   that loads each lexer field once and stores each once, keeping every check,
   frame record and position store, saves 0.8 % of instructions and no cycles
   (`evidence/hot-loops/advance_register_resident.ssa` against
   `advance_current.ssa`). The field loads are not what the loop pays for.
2. **Inlining is a loss until the slots are unpinned, and a win after.** Raising
   the inliner cap so `advance` (52 bytecode instructions against the cap of 48)
   is inlined at its twelve call sites cut instructions 3.4 % but *raised* cycles
   9.2 % and wall 10 %: `read_string` grew from 423 to 1,057 machine
   instructions, `read_number` from 3,042 to 5,350, L1 instruction-cache misses
   rose 40 % (969 k → 1.36 M), and stack references in `read_string`'s body went
   from 133 to 321. With value roots landed first the same inlining is worth a
   further 5 % of cycles.
3. **The plateau argued in the previous audit was an artefact of the root
   protocol.** Two paragraphs there measured `advance` at ~30 instructions per
   call and attributed the rest of the per-byte cost to "loads and stores of the
   lexer's fields through a heap object". `advance` runs ~62 instructions on its
   common path (§3), and the callers' loops run their scalar operands through
   memory because a root push somewhere in the function takes the slot's
   address (§2). Neither is field traffic.

## 2. The mechanism: root pushes pin the slots that carry the loop

`Emitter.roots` (`src/qbe.zig:1342-1366`) pushes, at every safepoint, one
`myl_native_root {previous, address, type}` per traced local and per traced
operand, and `address` is **the slot itself**: `storel %l0, %v131` for local 0,
`storel %s0, …` for operand slot 0 (`pushRoot`, `qbe.zig:1370-1378`). QBE's
`promote` (`vendor/qbe/mem.c:9-50`) turns an `alloc8` into an SSA temporary only
if every use is a load or store of it; a slot whose address is stored anywhere
stays in memory for the whole function.

Operand slots are shared by stack height, so pinning `%s1` because a traced
value sits there at one safepoint pins it for every scalar expression in the
function. In `read_string`'s byte loop the assembly shows the consequence
(`evidence/hot-loops/` — the `-192(%rbp)` slot):

```
	movq -208(%rbp), %rsi        ; lx reloaded from its pinned local every iteration
	movq %rsi, -192(%rbp)        ; operand push: a real store
	movq 8(%rsi), %rcx
	movq %rcx, -192(%rbp)        ; and again
	…
	movq %rax, -192(%rbp)        ; ~14 stores to the same slot per byte, none reloaded
```

QBE has no dead-store elimination, so each push is a store even when the value
is also in a register. `advance` itself has no safepoint, so it has no roots and
runs entirely in registers — which is exactly why hand-optimising it bought
nothing, and why inlining it into a function whose slots *are* pinned doubled
its cost: every inlined operand became a memory operation.

**The fix is small and keeps the collector unchanged.** A root record grows to
`{previous, address, type, value}`; the push stores the slot's *value* into the
fourth word and points `address` at that word. `myl_native_heap_collect`
(`src/native_heap.c:131-132`) still does `trace(heap, root->type, root->address)`
and reads the pointer through `address`, so it sees the same pointer it saw
before. This is sound because the collector is non-moving mark-and-sweep, stop-
the-world at allocation (`native_heap.c:129-168`): nothing rewrites a guest
pointer during the helper call, so a copy taken at push time is exactly the slot's
content for the whole safepoint. The rewrite that measured −9.6 % is
`evidence/hot-loops/value_roots.py`; it also replaces the 8-byte
`call $memset(l %l{n}, w 0, l 8)` zero-fill of a traced local (`zero_local`,
`src/qbe_format.zig:7`) with `storel 0, %l{n}`, since a `memset` call takes the
address too.

The remaining address-takes after that rewrite are the `copy %s{n}` value
pointers handed to `myl_native_equal` (22 sites), `myl_native_list_append` (18),
record constructor helpers (6) and 15 others (`qbe_managed.zig:125, 148`;
`qbe_aggregate.zig:43-46`, where the pointer only feeds the arena barrier and is
dead in an arena-free build). None of them is in the tokenizer's hot functions,
so they did not affect this measurement, but they pin slots in the parser and
anywhere `==` on records or `append` is used, and each needs the same treatment:
a dedicated per-site `alloc8` scratch, or passing the value by value.

## 3. Why "3×" — the scan floors, in both units

The previous audit's "3.1× Zig" came from one row: the hand-written ideal IL for
the `scan` loop (`evidence/ideal-scan/scan_ideal.ssa`) at 25.1 M instructions
against Zig's 8.0 M. It was an instruction ratio, measured with the general
overflow test that has since been replaced, and it was never a limit of the
language. Re-measured on this checkout with the landed constant-operand overflow
form (`evidence/hot-loops/scan_ideal_constovf.ssa`) and with every check deleted
from the same IL (`scan_ideal_nochecks.ssa`):

| `scan` (927 KB, same output) | instructions | ÷ Zig | cycles | ÷ Zig |
| --- | ---: | ---: | ---: | ---: |
| Zig `ReleaseFast` (`zig-bench --scan`) | 8.0 M | 1.0× | 3.9 M | 1.0× |
| hand-written QBE IL, no checks at all | 13.8 M | 1.7× | 4.5 M | 1.16× |
| hand-written QBE IL, every mylang check kept (2 bounds, 2 overflow, frame record) | 22.2 M | 2.8× | 5.7 M | 1.5× |
| compiled today (`mylang build e_scan.my --mode ReleaseFast`) | 49.6 M | 6.2× | 16.6 M | 4.3× |

So the floor for this loop shape on QBE is **1.5× Zig in cycles with all checks
kept, 1.16× with none**. The instruction ratios overstate the gap because QBE's
extra instructions are cheap moves and compares that retire at high IPC. What
separates 1.7× from 1.0× is the backend — QBE keeps constants in the loop, jumps
back to the loop head unconditionally, and neither unrolls nor hoists — and the
scan-floor study already showed hand-written QBE and LLVM meeting at the process
floor on a SWAR-shaped loop, so even that is a shape question rather than a wall.
What separates 6.2× from 2.8× is the emitted IR, which is what this plan is
about.

## 4. Are there checks worth removing? No — here is each one's price

| check | what it guarantees | measured cost on the census | status |
| --- | --- | --- | --- |
| bounds check on inline `bytes[i]`/`list[i]` | trap instead of an out-of-range read | −2.8 % instructions (previous audit) | semantic; keep |
| add/sub overflow test | trap instead of wrap-around | −3.4 % instructions, −0.8 % cycles (this note) | semantic; keep |
| per-pc position store | exact trap traces and `assert` text | −3.1 % / −2.3 % cycles on the baseline; −8.3 % / −2.6 % on the best variant | observability; **movable to the cold path with no loss** (`QBE-POSITION-2`, stage 4) |
| frame record per call | exact frame in the trace, `--max-frames` | −15.2 % / −7.6 % cycles if deleted outright (previous audit) | observability; the one policy lever, at the price of backtraces |
| `--max-frames` and stack-floor tests | exact depth ceiling, no guard-page hit | already build policy / leaf-skipped (landed, −6.7 %) | done |
| step accounting | exact `--max-steps` | already build policy (landed, 1.2×) | done |
| sticky trap test after an inline `bytes` read (`loadl %trap; jnz`) | needed only after a `str` read that can allocate | 4 instructions of `advance`'s 62; not separately measured | dead code; peephole, stage 1b |
| GC root pushes | precise collection | already only at real safepoints | the *form* is the problem (§2), not the count |
| UTF-8 validation in `decode()` | `str` is always valid UTF-8 | 4.3 % of instructions (`myl_native_text_from_utf8_checked`) | keep; an ASCII fast path is the sound version |
| arena escape barrier | no reference outlives its arena | emitted only in functions with `begin_arena`; zero here | done |

Everything semantic together (bounds, overflow) is about 4 % of cycles.
Everything observational together (positions, frame records) is about 10 %.
Deleting all of it would take the cycle ratio from 8.2× to roughly 7×, and the
semantic half is the language's safety net, so the answer to "which checks
should go" is: none of them; move the position store to the cold path and leave
the rest.

The `advance` common path today, from `evidence/hot-loops/advance_current.s`,
shows where 62 instructions per byte go:

| part of `advance` | instructions |
| --- | ---: |
| prologue, epilogue and the 32-byte frame record | 19 |
| guard `lx.pos < len(lx.src)` (three loads, compare, branch) | 5 |
| `lx.src[lx.pos]`: three reloads, signed-index normalisation, bounds compare | 10 |
| byte load | 2 |
| dead sticky-trap test after the read | 4 |
| `== 10` compare and branch | 5 |
| two checked increments with their position stores | 17 |

## 5. Plan

Stages are ordered so every step is measured on its own and each unlocks the
next; stage 2 in particular must not land before stage 1 (it is a measured loss
on its own). Spec tags are proposals; each stage adds its `// spec:` test and
`SPEC.md` bullet.

### Stage 0 — measurement harness (½ day)

- A sanctioned symbolised build (`-Dprofile`, or a tagged `--keep-symbols` on
  `mylang build`) so `perf report` can attribute instructions per function
  again. Every binary in this note is stripped, so the profile of the best
  variant could not be read.
- Document the counterfactual route used here: `emit-project-qbe` manifest →
  `--manifest-file` build for IL-level questions; for compiler-level questions,
  the freshest `.zig-cache/o/<hash>/mylang` after a Guardian-failed `zig build`
  is the built compiler (Guardian blocks *install*, not compilation; the cap-64
  measurement was taken that way, with the source edit reverted afterwards).
  A `-Dcounterfactual` switch that installs to a side directory would make this
  honest instead of clever.

### Stage 1 — value-carrying roots, `QBE-ROOTS-2` (1 day)

- `RootSlot` gains a value word; `allocateStorage` sizes root slots at 32;
  `pushRoot` loads the slot, stores the value, and stores the value word's
  address as `address`. Aggregate operands (`%v{n}` from `%agg{pc}`) keep the
  address form — they are memory anyway.
- `zero_local` for an 8-byte traced local becomes `storel 0, %l{n}`; larger
  (aggregate) locals keep `memset`.
- Stage 1b: the `copy %s{n}` value pointers (`qbe_managed.zig:125, 148`,
  `qbe_aggregate.zig:43-46`) move to a per-site `alloc8` scratch declared with
  the other slots, and the barrier copy is not emitted when `!self.arenas`. The
  dead `loadl %trap; jnz` after an inline `bytes`/`list` read goes at the same
  time (it exists for the `str` variant, which allocates).
- Verification: full gate; `mylang test tests/lang --gc-stress`, the sexpr port
  and the goldens under `--gc-stress`; the type-size ratchet if `RootSlot`
  widens. A new stress test that collects while a traced operand is live in a
  slot that is also used for scalars later in the same function.
- Measured bound: −9.2 % instructions, −9.6 % cycles, −5 % wall.

### Stage 2 — inline the byte-loop helpers (½ day, after stage 1)

- Raise `max_instructions` in `bytecode_inline.zig` from 48 to 64 so `advance`
  (52) qualifies; `peek` and the `is_*` predicates already inline. Keep the
  existing `inline_frames` trace table and the `--max-frames` policy the inliner
  already follows.
- Then a size-aware policy rather than a flat cap: inline when the callee is a
  leaf under the cap *and* the call site is inside a loop, so `read_number`
  does not double again for cold sites.
- Measured bound with stage 1: a further −11 % instructions, −5 % cycles.
  Without stage 1: +9 % cycles — the gate for this stage is a cycle measurement,
  not an instruction count.

### Stage 3 — second load-elimination round in QBE (½ day)

QBE's `loadopt` is one pass over alias information computed once beforehand.
When it replaces a load with an earlier one, a later load whose *address* came
from the replaced load keeps its stale alias base and is never matched, so
`len(lx.src)` reloads after `lx.src` was already de-duplicated. Running
`fillalias; loadopt; filluse` twice (`evidence/hot-loops/qbe_loadopt_twice.patch`,
three lines in `vendor/qbe/main.c`) fixes the chain; measured −2 % cycles on the
inlined build, nothing on the baseline. It changes code generation for every
guest, so it needs the whole gate plus the differential trap check.

### Stage 4 — trap pc by argument, `QBE-POSITION-2` (1–2 days)

Move the position store off the hot path: an inline check that fails jumps to a
cold block that passes its pc to `myl_qbe_fail_*`, and the helper writes it into
`active_frame->position` before building the trace. Call sites keep their store
(a callee's trap reads the caller's position), so the landing is somewhat below
the counterfactual, which removed those too. The upper bound on top of stages
1–3 is −8.3 % instructions / −2.6 % cycles; it also removes the last may-alias
stores from the loops, which is what lets stage 3's load elimination work across
an inlined body. Traces and `assert` text must stay byte-identical: run the
differential trap check on bounds, overflow, division, assert and `--max-frames`.

### Stage 5 — re-measure, then decide on field caching

After stages 1–4 the census should sit near 53 M cycles (6.7× Zig in cycles,
about 5.9× reported wall). Take the symbolised profile from stage 0 *then*.
If field traffic through class pointers is what dominates the loops at that
point, the original option 2 is the next pass, and its design is now scoped:

- cache **scalar** fields only, in dedicated promotable slots per (local, field);
  traced fields stay in the object so the collector sees them
  (`native_heap.c:92-110` traces class payloads at safepoints);
- flush and invalidate at `.call`/`.invoke`, at any receiver write classified by
  `mutation.zig:113` through *another* reference of the same class (types are
  nominal and exact at every pc, `native_ir.zig:27-35`, so a write through a
  different class cannot alias), and at function exit; **never at a trap edge**,
  because `fail()` (`qbe_runtime.c:201-218`) reads only the frame chain;
- the base pointer is stable across a collection (non-moving), so a cached
  object pointer needs no reload;
- validity is a forward dataflow over `native_ir` states with a predecessor map
  the emitter does not yet have (`isBranchTarget`, `qbe.zig:683-693`, is a
  linear rescan and misses `switch_variant` arms).

Its measured floor is the 0.8 % from §1; its value after stages 1–4 is unknown
and is the reason to profile before building it.

### What this plan does not reach

Even the full ladder lands near 5.9× reported / 8.2× compute-only, not 5×. What
is left after it is per-token rather than per-byte: `lexeme` allocates twice and
validates UTF-8 (4.3 % of instructions in `myl_native_text_from_utf8_checked`),
every `Token`/`Span`/`Result` is a stack aggregate blitted through `%agg{pc}`
scratch, and each remaining call pays the frame record. Those are the next
audit, and they are visible only with the stage 0 profile.

## 6. Reproduce

```sh
# baseline and Zig
cd experiments/sexpr-port
../../zig-out/bin/mylang build main.my -o /tmp/census_base --mode ReleaseFast
taskset -c 6 perf stat -e instructions,cycles -- /tmp/census_base /tmp/sexpr-bench/input.sexp
taskset -c 6 perf stat -e instructions,cycles -- /tmp/zb-out/bin/zig-bench /tmp/sexpr-bench/input.sexp

# value roots (stage 1 upper bound)
../../zig-out/bin/mylang emit-project-qbe main.my --drop-step-checks > /tmp/main.json
python3 ../sexpr-audit/evidence/hot-loops/value_roots.py /tmp/main.json /tmp/main_vr.json
../../zig-out/bin/mylang build main.my --manifest-file=/tmp/main_vr.json -o /tmp/census_vr --mode ReleaseFast

# overflow / position counterfactuals
python3 ../sexpr-audit/evidence/hot-loops/strip_checks.py /tmp/main.json /tmp/main_noovf.json overflow
python3 ../sexpr-audit/evidence/hot-loops/strip_checks.py /tmp/main_vr.json /tmp/main_nopos.json position

# QBE with load elimination run twice (stage 3)
cp -r ../../vendor/qbe /tmp/qbe2 && cd /tmp/qbe2 && patch -p0 < .../evidence/hot-loops/qbe_loadopt_twice.patch
cc -std=c99 -O2 -fno-sanitize=undefined -o /tmp/qbe2/qbe *.c amd64/*.c arm64/*.c rv64/*.c
../../zig-out/bin/mylang build main.my --manifest-file=/tmp/main_vr.json -o /tmp/census_vr2 \
  --mode ReleaseFast --qbe=/tmp/qbe2/qbe --cache-dir=/tmp/cache-qbe2

# scan floors
cd experiments/sexpr-audit/evidence/hot-loops
for v in scan_ideal_constovf scan_ideal_nochecks; do
  ../../../../zig-out/bin/qbe -o /tmp/$v.s $v.ssa && cc -O2 -o /tmp/$v /tmp/$v.s ../ideal-scan/scan_ideal_rt.c
  taskset -c 6 perf stat -e instructions,cycles -- /tmp/$v /tmp/sexpr-bench/input.sexp
done
```
