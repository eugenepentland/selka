# CE-B report: lists, copy-on-write, slices and appends (2026-10-08)

**Who wrote this file.** An opus-lane agent did the lane. Its tool refused report files,
so the coordinating Claude session wrote this file from the agent's final message. The
coordinator first checked:
- `qualify/summary.json` (qualified, source `f4f6eaea`);
- `qualify/full-conformance.log` (debug and release each 1518 matching, 0 mismatching);
- `logs/gate-tail.log` (88/88 steps);
- `logs/lox-conformance-final.log` (VM 246/246 and tree 241/241, in normal and gc-stress
  modes: 974 in all);
- `logs/lox-port-tests.log` (65 passed) and `logs/eda-tests.log` (310 passed);
- `fuzz50-summary/` (9 kinds, 0 mismatches).

**Where the work is.** Branch `claude/ce-lists` (tip `89d0aa742`), based on
`claude/copy-elim` `137d00ef`. Nothing was merged or pushed.

## Result: every exit target met

| target | before | after |
|---|---|---|
| nbody P3+P4 | 12,600 B per step | **0** (560 B in total, in `energy`) |
| Lox `instantiation`, tree, N/2 → N | ×2.00, P9 78.7 G | ×2.00, P9 7.6 M |
| Lox `instantiation`, VM, N/2 → N | **×3.60 (quadratic)**, P9 4.04 G | **×1.99 (linear)**, P9 0.42 M |
| EDA `overlaps_of`, all 34 designs | 2,768 MB | 125 MB (**−95.5%**) |
| `str_build` out-of-line appends | 16,000,000 | 25 (the growths) |

The only rise is P2 (+0.025% Lox, +0.03% EDA). It is a reclassification: at every site the
P2 rise equals the P8 fall. For example, `interpreter.my:472` is +90,654,400 / −90,654,400.

## Commits

| step | commit | what |
|---|---|---|
| 1 | `c2b1e20fa` | Element-field stores happen in place (`list_set_field`, `src/core/elements.zig`). Dead element reads are dropped. A whole-element store releases the old element's parts where they are. NEW-CORE-CE-LISTS-1, -2. |
| 2 | `eba79203a` | Copy-on-write narrowed (`own.zig`). A field read merges with an identical read in another block (dominance and post-dominance, refused when anything in between could block the take). Parts read out of a list or dict get their own counts instead of the collection. Parts over four words are counted in place (`countedAt`). NEW-CORE-CE-LISTS-3, -4. |
| 3 | `ddd266e85` | A slice used only as a loop source is iterated in place (`src/core/slices.zig`). The proof comes from the builder's clamp chains. There is no rewrite if anything updates, stores, returns, joins or passes the source. A slice that is still built gets exact capacity. NEW-CORE-CE-LISTS-5. |
| 4 | `f4f6eaeab` | Inline byte-buffer appends (`buffer_append`, `src/core/buffers.zig`, plus the fast path in `emit_bytes`); the runtime is called only to grow. NEW-CORE-CE-LISTS-6. |
| evidence | `89d0aa742` | Counts, receipts and tools. |

## Bytes moved per pattern (VP3's numbers are the "before")

**Lox** (24 cells):
- P4: 40.46 G → 27.47 G (−32%).
- P5: 27.47 G → 0.
- P8: 164.08 G → 148.95 G (−9.2%).
- P9: 112.14 G → 2.76 G (−97.5%).
- P13: 752 M → 23.7 M.
- **Total: 1276.7 G → 1111.0 G (−13.0%).**

P1, P3, P6 and P7 are unchanged; those are CE-A's patterns.

**EDA** (34 designs):
- P3: 1.746 G → 0.674 G (−61%).
- P5 → 0.
- P6: 1.549 G → 0.478 G (−69%).
- P8 −15.6%.
- P9: 302 M → 6.1 M.
- P13: 1.008 G → 0.090 G.
- **Total: 40.73 G → 35.89 G (−11.9%).**

**Parity:** P3 42.0 G → 560 B; P4 21.0 G → 0. Total 63.16 G → 154.9 M (−99.8%).

**46 rows:** unchanged (875,157,355 bytes).

## Gates (on `f4f6eaeab`)

| gate | result |
|---|---|
| `zig build` (Guardian) | 88/88 checks |
| `zig build test --summary all` | 88/88 steps |
| `zig build fmt-check` | exit 0 |
| `test-core` | 455 passed |
| `qualify_merge.py` (64 shards, leak and fact verification) | debug 1518/0/0, release 1518/0/0, qualified |
| frozen fuzz 9×50 | all 9 kinds pass |
| Lox conformance, both engines, normal and gc-stress | 974/974 (the base build also gives 974/974) |
| Lox port tests | 65/65 |
| EDA goldens | 34/34, counting and ordinary builds |
| EDA tests | 310/310 |
| parity `.expected` | 4/4 |
| counting on vs off | same output: Lox 48, EDA 34, parity 4, rows 46, at every step |

**New tests.** `src/core/ce_lists_test.zig`, with fixtures `test/core/ce_elements.my`,
`ce_cow.my`, `ce_slices.my` and `ce_appends.my`. Each runs in debug, release and release
`--verify-facts` with the leak check, against the base compiler's outputs. They cover:
- shared lists, counted fields, nested paths, and unions under and over four words;
- trap positions;
- write-back merges, including a record passed to a call between the two reads;
- promoted parts;
- slice loops with `break`, `continue` and `return`, and bad bounds;
- loops that write the source, pass it `mut` or rebind it;
- appends across growth, at the capacity boundary, from a shared snapshot, into itself,
  and with a memory-budget trap.

## Touches outside the lane's areas (for the merge)

- **`emit_llvm.zig`:**
  - **`countedMemory` (CE-A's):** its three part loads go through `countedAt`. This is the
    merge conflict.
  - `instruction()` dispatches `.list_set_field` and `.buffer_append`.
  - `callLocation` is `pub`.
  - `tag_load_line` and `case_test_line` replace repeated string literals; the emitted text
    is identical.
- **Elsewhere:**
  - `fuse.zig`: `inert` made `pub`;
  - `build.zig`: calls `slices.loops`;
  - `cost.zig`: `buffer_append` may allocate;
  - `print.zig`, `verify_ir.zig`, `ir.zig`: the two new ops;
  - `emit_bytes.zig`: the append emitter;
  - `own.zig`: `dominatesBlock` and `successors` made `pub`.

## Remaining limits

- **Lox VM frame write-back:** `rt.frames[k] = frame` still copies the 88-byte frame (P4,
  27 G), because the local `frame` is a separate value. Only the old-element copy is gone.
- **Field stores:** `list_set_field` covers record-field chains only.
  `xs[i].items.append(v)` still copies the element out and back.
- **Slices:** the rewrite needs the builder's clamp shape and a loop that reads only through
  its counter.
- **Appends:** each append keeps an inline count test when the buffer is not provably
  unique (16 M in `str_build`).
- **Count updates:** giving parts their own counts adds inline count updates in some
  functions. This costs count operations, not bytes.
- **A pre-existing bug:** `mylang dump-ir` overflows the stack printing EDA's recursive
  types (`print.typeName`).
- **A process note:** during the lane the agent ran `pkill -f "ce.py build"` and
  `pkill -f "ce.py run"`, patterns that could match other agents' processes. It found CE-A's
  runs still alive, and killed only by PID after that.
