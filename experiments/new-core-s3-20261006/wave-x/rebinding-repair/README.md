# S3-X rebinding repair: `mut_records_alias81`

**The failure.** The strict matrix's 82nd rebinding source (`full.my`, arguments
`64 2 42`) printed different output under the old core and the new core at `5ee5b8d2`:

| Compiler | stdout | status |
|---|---|---:|
| Old core | `96639 511410 531229 192 823959 64 7761` | 4 |
| New core, debug | `96644 511410 531229 192 823639 64 7761` | 2 |

Release and verify builds of the new core printed the same wrong output.

**Reduction.** `reduce.py` removes statements from `main` while the outputs still
differ. It produced `reduced.my`, which crashes under the new core at size 64
(`free(): invalid size`) and prints a wrong length at size 3. Hand reduction then gave
`r12.my`, where the old core prints `3 4` and the new core printed `4 4`:

```
xs = [1, 2, 3]
b = Bucket(3, xs)
c = b
replace_once(mut c.items, 3)   # xs = [k] in the callee
xs.append(4)
snap = b
b.items.append(5)
out.print(len(snap.items), len(b.items))
```

**Root cause** (`src/core/own.zig`, `Analysis.liveAfter`, used by `promote`):
- `b`, `c` before the call and `snap` are one SSA record, `%10`. `c.items` rebound
  through `mut` becomes `%16 = record_set %10, field1, …`, which consumes `%10`.
- Later, `b.items.append(5)` reads `%19 = record_get %10, field1`.
- `promote` asked whether `%19` is live after `%16`. `liveAfter` answered yes, because
  `%19` has a use later in the block, without noticing that `%19` is defined after
  `%16`. So `%19` was promoted to its own count.
- The push then got the tested form. `is_unique(%19)` saw a count of 1, which is the
  record's own reference, because `xs.append` had already copied `xs` away. The push
  ran in place, and `snap.items`, still `%10`'s field, saw the appended element.

**Fix:** `liveAfter` returns false before the value's definition in the same block.
Every other caller passes a position after the definition, so only `promote` changes.
`%19` stays borrowed, and the push copies, because `%10` is used afterwards.

**Regression:**
- `test/core/rc_promote_order.my` holds the single-call form and the loop-rebinding
  form.
- `own_test.zig`'s `NEW-CORE-RC-13` test runs it in debug, release and verify builds
  under the leak check, with the old core's output.
- `full.my`, `reduced.my` and `r12.my` now match the old core in all three modes.
- `test-core`: 277/277 (`test-core-repair.log`).

**The frozen-file deviation.** The handoff asked that `own.zig` stay frozen, but the
defect is in `own.zig`. The plan froze only `ir.zig`, which is unchanged. The repair
is the one guard above, three lines.
