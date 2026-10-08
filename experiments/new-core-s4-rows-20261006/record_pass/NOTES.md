# record_pass (large records across calls)

Status: `rows.py build` + `verify` PASS for all five arms (old core `--release`, new core release, Rust,
Zig ReleaseSafe, Go) at all five probes, each checksum equal to `oracle.py`. Extra cross-check: 25 random
`(size 2..300, iterations 1..30, seed 1..1000000)` triples plus `(100000,2,999999)`, `(5,1500,1000000)`,
`(1009,3,1)`, `(1010,3,2)`, all arms equal to the oracle (no mismatch). The arms also agree with the oracle at the
saved `case.json` counts. Invalid arguments (size 1, iterations 0, seed 0 and 1000001, non-numeric, missing or
extra argument, a negative seed, a number past i64, and for the references a wrong case name) exit 2 with empty
stdout and stderr in every arm.

`case.json` iterations come from `rows.py calibrate` (three runs: 4096 -> 883, 932, 923; 64 -> 67328, 65088,
79854). The saved values are the 923 and 65088 runs (Zig 45.5 ms and 49.8 ms on CPU 12, while other agents were
building).

## Idioms

All four languages write the same thing: a record/struct of twelve `i64` fields, `mix` and `advance` as
separate top-level functions, `advance` taking the state by value and returning a new one, the loop reassigning
`s = advance(s, x)`, and the initial state and the final weighted sum written out field by field (no field
loops or arrays, since the point is a 12-field aggregate crossing a call).

| arm | state | call |
|---|---|---|
| mylang `test/core/row_record_pass.my` | `record State:` with `f0: int` ... `f11: int`; built with keyword construction `State(f0=..., ...)` | `def advance(s: State, x: int) -> State`; `f3 = mix(s.f4, x) if x % 3 == 0 else s.f4` |
| Rust | `struct State { f0: i64, ... f11: i64 }`, no `Copy`/`Clone` derive | `fn advance(s: State, x: i64) -> State`; `s = advance(s, ...)` moves it in and a new value out |
| Zig | `const State = struct { f0: i64, ... }` | `fn advance(s: State, x: i64) State`, returns an anonymous struct literal; `@mod` for `%` |
| Go | `type state struct { f0, ..., f11 int64 }` | `func advance(s state, x int64) state`, returns an unkeyed literal in field order |

Nothing is allocated in any arm: this row measures how each backend moves a 96-byte aggregate through a call
and a loop-carried variable.

## Decisions the contract left open

- `part` is not reduced modulo MOD (the contract only reduces `checksum`); it is at most 78 * 1008.
- The arms do not prevent inlining (the contract forbids `noinline`). What each toolchain did (checked by
  looking for symbols in the final binaries): Rust, Zig, the new core and the old core (`--release`, LTO) inline
  both `advance` and `mix` into the batch loop, so no call survives; Go keeps `main.advance` as a call (its
  inliner declines the 12-field function) and passes/returns the struct by copy. In the new-core IR
  (`new.ll`) `advance` is `void @advance(ptr sret([96 x i8]), ptr noalias readonly, i64)` before LLVM's
  inliner. The ratios are therefore a statement about optimizer behavior on this idiom, which is the purpose of
  the row, but expect Go to be far slower here (CPU 12, noisy, not a measurement, `4096 923 7`: new core ~19 ms,
  Rust ~18 ms, Zig ReleaseSafe ~27 ms, old core ~38 ms, Go ~72 ms).
- Zig ReleaseSafe is slower than Rust here (about 1.5x on the noisy run) because the ReleaseSafe arithmetic
  checks are active on every add/multiply; no `@setRuntimeSafety(false)`, as the contract requires.
- **Oracle.** `oracle.py` is the literal contract formula over a list of twelve ints. A batch depends on its number
  only through `(seed + batch) % 1009` (every initial field and every `x` is `(base + c) % 1009`), so each distinct
  residue is computed once and reused. A cache over the contract formula, not a different formula.
- **mylang header.** `module row_record_pass`. `test/core/row_record_pass.my` is not `mylang fmt --check` clean, and neither is the template
  `test/core/row_list_append.my`; the formatter would also collapse the keyword constructions onto one 200-column
  line each, which I kept expanded for readability (it parses the same).

## Findings

- New core: no refusal. `mylang-core coverage` reports every row function `ok` (`new-core-refusal.txt` is not
  written).
- No wrong answer in any arm.
- Old core: accepts `test/core/row_record_pass.my` unchanged (`mylang check` clean); a 12-field record, keyword construction, a
  conditional expression and a multi-line parenthesized return all work with no contortion.
- Rows.py: no bug blocked this case.
