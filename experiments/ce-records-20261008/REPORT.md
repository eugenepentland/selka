# CE-A report: records in the emitter (2026-10-08)

**Who wrote this file.** An opus-lane agent did the lane. Its tool refused report files,
so the coordinating Claude session wrote this file from the agent's final message. The
coordinator first checked:
- the commits;
- `logs/gate-full-2.log` (exit 0);
- `qualify/summary.json` (qualified, source `c25ebc98`);
- `qualify/full-conformance.log` (debug and release each 1518 matching, 0 mismatching);
- `fuzz50/matrix.json` (all nine kinds passed).

**Where the work is.** Branch `claude/ce-records`, based on `claude/copy-elim` `137d00ef`.
Nothing was merged or pushed.

## Result: exit met

P1+P2+P7+P8 bytes moved, base against final. The lane's base run reproduces VP3's P1–P9
numbers exactly.

| corpus | base | final | change |
|---|---:|---:|---:|
| Lox (24 cells) | 1.09 TB | 16.4 GB | **−98.5%** |
| EDA (34 designs) | 36.0 GB | 2.13 GB | **−94.1%** |
| parity | 0 | 0 | — |
| 46 rows | 363 MB | 363 MB | −0.0% (see limits) |

All patterns together: Lox 1.28 TB → 189 GB (−85%); EDA 40.7 GB → 6.86 GB (−83%).

## Commits

| step | commit | what it does |
|---|---|---|
| 1 (P1) | `6ba01c9c9` | Adds `src/core/emit_homes.zig`: per-function homes from SSA liveness and interference. It coalesces each phi with its incoming values and each `record_set` with the record it updates. Edge fills run as a parallel copy (a reader goes first; only a cycle uses a temporary). This replaces `writableInPlace`. |
| 2 (P8) | `5c1d3da7c` | Views: a memory field or payload is read where it lies. `retain`/`release` count nested memory values in place. A construction is built straight into a memory construction's field. |
| 3 (P2) | `951223eec` | Write-backs: `y` is built inside `p`'s field when `p` is updated in place. Liveness is field-precise. |
| 4 (P7) | `64318962b` | In-out ABI for `mut` records over four words. A returned value is built in the caller's `sret` destination when it can share it. |
| fix | `c25ebc983` | Signatures with 64 or more parameters pass nothing in-out. The full gate caught a shift overflow here; there is a 70-parameter regression test. |
| evidence | `48a7cb451`, `ae2140aae` | Harness, tables, receipts. |

**The in-out convention.**
- A `mut` record parameter over four words is a writable `noalias` pointer. The callee
  updates it in place and leaves the final value there.
- If the result is only that value, the function returns `void`. If the result record
  holds other values too, the caller reads the final value where it passed it, and copies
  it into the result record only when something reads that record whole.
- The caller passes the argument's own home when the argument dies at the call; otherwise
  it passes a copy. So a read-only argument that overlaps the `mut` record still sees the
  value from before the call.
- Direct calls, indirect calls and cross-unit declarations all follow one convention
  derived from the signature. `extern` and runtime calls are unchanged.

## Bytes moved per pattern

**Lox**

| pattern | base | step 1 | step 2 | step 3 | final | final vs base |
|---|---:|---:|---:|---:|---:|---:|
| P1 | 562.2 G | 7.05 G | 35.46 G | 35.46 G | 305 k | −100% |
| P2 | 263.1 G | 76.2 G | 122.3 G | 104.3 G | 7.73 G | −97.1% |
| P7 | 101.7 G | 101.7 G | 101.7 G | 101.7 G | 5.34 G | −94.8% |
| P8 | 164.1 G | 164.1 G | 3.30 G | 3.30 G | 3.30 G | −98.0% |
| **P1+P2+P7+P8** | 1.09 T | 349 G | 263 G | 245 G | 16.4 G | **−98.5%** |

P4 fell 32% (40.5 G → 27.5 G). P3, P5, P6 and P9 are unchanged. P13's −0.1% is noise.

**EDA**

| pattern | base | step 1 | step 2 | step 3 | final | final vs base |
|---|---:|---:|---:|---:|---:|---:|
| P1 | 11.48 G | 3.37 G | 3.90 G | 3.90 G | 3.1 M | −100% |
| P2 | 6.85 G | 3.99 G | 3.99 G | 3.99 G | 1.4 M | −100% |
| P7 | 8.38 G | 8.38 G | 8.38 G | 8.38 G | 2.11 G | −74.8% |
| P8 | 9.28 G | 9.28 G | 7.8 M | 7.8 M | 9.5 M | −99.9% |
| **P1+P2+P7+P8** | 36.0 G | 25.0 G | 16.3 G | 16.3 G | 2.13 G | **−94.1%** |

Other patterns are unchanged. P11 rose by 540 bytes, from the harness's output-directory
path length.

**The step 2 regression.** Step 2 raised P1/P2 above step 1, because views keep their
parent alive, which blocks some merges. Step 4 removes those copies.

**Parity and rows.** Parity is unchanged (all P3/P4, which are CE-B's). The rows went from
875.16 MB to 875.07 MB.

## Highlights

| | base | step 1 | step 2 | step 3 | final |
|---|---:|---:|---:|---:|---:|
| Lox VM fib(27): bytes moved per dispatch | 6,394 | 1,066 | 806 | 806 | **448** |
| … of which P1+P2+P7+P8 | 5,894 | 566 | 410 | 410 | **52** |
| Lox `vm::run` on fib(27) | 44.7 GB | 5.54 GB | 3.89 GB | 3.89 GB | 2.91 GB |
| EDA rds3+flat, all patterns | 3.67 GB | 3.01 GB | 2.54 GB | 2.54 GB | **1.75 GB** |
| EDA rds3+flat, P1+P2+P7+P8 | 2.04 GB | 1.37 GB | 899 MB | 899 MB | **115 MB** |

About 396 of the 448 bytes left per Lox VM dispatch are the frame write-back and read
(P3/P4/P5), which are CE-B's.

**EDA `sexpr_*` functions, all patterns, base → final:**

| function | base | final |
|---|---:|---:|
| `advance` | 13.57 GB | 0 |
| `skip_whitespace_and_comments` | 2.38 GB | 0 |
| `parse_list` | 5.48 GB | 476 MB (all P6) |
| `next` | 4.28 GB | 583 MB |
| `next_token` | 3.40 GB | 486 MB |
| `next_in` | 1.65 GB | 492 MB |
| `read_atom` | 1.27 GB | 137 MB |
| `parse_node` | 1.25 GB | 284 MB |
| `read_string` | 1.16 GB | 31 MB |
| `read_number` | 906 MB | 88 MB |

## Gates

All on `c25ebc983`, the final source.

| gate | result |
|---|---|
| `zig build` (Guardian) | 88/88 checks; the whole-tree Guardian also passed on every commit's hook |
| `zig build test --summary all` | 88/88 steps, 0 failures (`logs/gate-full-2.log`) |
| `zig build fmt-check` | exit 0 |
| conformance (`qualify_merge.py --shards 64 --compiler zig-out/bin/mylang --install install`) | qualified: test-core 457/0/0; full conformance **debug 1518/0/0, release 1518/0/0**, with leak and fact verification |
| frozen fuzz 9×50 | all nine kinds pass |
| Lox conformance, both engines, normal and gc-stress | **974/974**; the base compiler also gives 974/974 |
| Lox port tests | 65/65 |
| EDA goldens | 34/34 byte-identical, ordinary and counting builds |
| EDA `mylang test src …` | 310/310 |
| parity outputs | 4/4 |
| counting on/off | identical: Lox 48, EDA 34, parity 4, rows 46 |

**First full-gate run.** On `64318962b` the gate failed two items, `golden_parity` (a
129-parameter program) and `tests/value_semantics/packed_calls.my`. Both were the shift
overflow fixed in `c25ebc983`.

**Flake.** One flake appeared once in a busy `test-core` run: a general protection
exception in `facts.shape`, pre-existing code that runs before emission. It passed on rerun
and in both full gates.

## Tests

The tests carry `// spec: NEW-CORE-CE-RECORDS-1..5`, with matching `SPEC.md` bullets.
- **`src/core/ce_records_test.zig`:**
  - loops with `break` and `continue`;
  - views, and constructions built into a field;
  - in-place updates, snapshots and write-backs;
  - the in-out signature and overlapping read-only arguments;
  - the result-record completion path;
  - the 70-parameter function;
  - the fixture end to end with the leak check.
- **`test/core/ce_records.my`:**
  - phis in loops, swaps, and a field moved within one record;
  - list and text fields through `mut`;
  - unions over four words, and `Result` payloads with `?`;
  - recursion through `mut`;
  - overlapping `mut` and read-only arguments, and two `mut` records in one call;
  - results built in `%ret`;
  - a trap in the middle of an in-out update.
- **Existing tests updated:** NEW-CORE-LLVM-3 (`widen` copies once), NEW-CORE-LLVM-5 (the
  swap loop makes 4 copies and uses no temporaries), and an NEW-CORE-RC-11 case (no copy).

## Touches in CE-B's areas

None in `own.zig`, `listGet`, `listSet`, `listPush` or `listGetField`. Two shared helpers
changed:
- `loadValue` writes a value that has a home straight into that home;
- the `fused` analysis gained a construction stored into a memory construction's field.

## Remaining limits

- **P7 of a declared result next to `mut` values** (EDA 2.11 GB, Lox 5.3 GB). `return
  Ok(token)` still copies into `%ret` field 0; removing it needs homes inside `%ret`.
- **Updates to disjoint fields** (about 7 GB of Lox). `frame.ip += 1` copies while a view
  of `frame.function` is live, because interference is per value, not per field.
- **Write-backs that ownership releases after the store** (about 4.7 GB,
  `interpreter.my:667`). This is CE-B's write-back temporary.
- **rows `record_pass`.** `s = advance(s, x)` passes `s` by value, so its `sret` result
  cannot share the argument's home.
- **Planner cost:** about 0.7% of a Debug compiler's EDA build time.
