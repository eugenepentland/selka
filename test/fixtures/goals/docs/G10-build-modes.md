# G10. One meaning in every build mode: pinned examples

The example runner builds and runs one mode. These examples give the same result in every mode; the gate does not run them
in each one (that comparison is work item W5b, which waits for release builds to return to the gate). The mode-by-mode
runs are in `experiments/audit-work-20261111/W5.md`.

## Holds

**G10-H1 (`debug(...)` evaluates its argument in every build, a release binary included; W5).** `selka run`, a debug
build and a `build --release` binary all print 1: the call in the argument runs and writes `counter`. Before 12 November a
release binary printed 0, because it dropped the whole line with its arguments unevaluated.

```selka
# doc: expect 1
func bump(mut n: int) -> int:
    n += 1
    return n

func main(out: Stream) -> int:
    mut counter = 0
    debug(bump(mut counter))
    print(out, counter)
    return 0
```

**G10-H2 (a bad index inside `debug` traps in every build; W5).** `selka run`, a debug binary and a `--release` binary
all trap `R_LIST_BOUNDS`. Before 12 November a release binary exited 0. The example runner runs it with `selka run` and
expects the trap (`# doc: expect-trap`); the Core test `a bad index inside a dropped debug line traps as it does when the
line is written` (`src/core/debug_arguments_test.zig`) runs it in the gate, and the release half of
`src/core/cli_flags_test.zig` builds it with `--release` under `-Dtest-release=true`.

```selka
# doc: expect-trap R_LIST_BOUNDS
func main(args: str[]) -> int:
    const xs = [1, 2, 3]
    debug(xs[len(args) + 4])
    return 0
```

**G10-H3 (the arguments of one `debug` line are evaluated once each, left to right; W5).** Each call prints its label to
standard output, so the order shows there.

```selka
# doc: expect first
# doc: expect second
func note(out: Stream, label: str) -> int:
    print(out, label)
    return 1

func main(out: Stream) -> int:
    debug(note(out, "first"), note(out, "second"))
    return 0
```

**G10-H4 (a list element that always overflows traps in every mode; FX3).** `selka run`, a `--release` build and
`selka test` all trap `R_OVERFLOW` at the addition. Before 12 November a `--release` build and `selka test` refused the
program with the internal error `E_FACT_VALIDATION`: the fact pass stated the list's elements from the empty interval of
an addition that never completes. The Core tests of `src/core/trapping_elements_test.zig` check the certificate of 26
shapes of it in the gate, run them through the release passes and run `selka test` on them.

```selka
# doc: expect-trap R_OVERFLOW
func main(out: Stream) -> int:
    const xs: int[] = [1, 9223372036854775807 + 1]
    print(out, len(xs))
    return 0
```

**G10-H5 (an operation on a value that always overflows traps in every mode; FX5).** `selka run`, a `--release` build,
`--debug-o0` and `selka test` all trap `R_OVERFLOW` at the subtraction. Before 12 November every build that runs the fact
pass crashed the compiler (`integer does not fit in destination type`): the shift's rule read the count's empty interval as
a shift amount. The Core tests of `src/core/trapping_operands_test.zig` check the certificate of 24 shapes of it in the
gate, run them through the release passes and run `selka test` on them.

```selka
# doc: expect-trap R_OVERFLOW
func main(out: Stream) -> int:
    const c: u32 = 14u32 - 31u32
    print(out, shift_right(7u32, c))
    return 0
```

**G10-H6 (a vector loop with a loop-invariant byte operand builds in every mode; FX7).** `selka run`, a `--release` build,
`--debug-o0` and `--unoptimized` all print 47935. Before 12 November every build that vectorizes, the plain build
included, failed with `ToolFailed`: the vector lowering splatted the invariant `u8` as if it were an `i64`
(`trunc i64 %v44 to i16`), which clang refused. `src/core/vector_test.zig` builds and runs an invariant of each width,
narrower than, as wide as and wider than the lanes.

```selka
# doc: expect 47935
func main(args: str[], out: Stream) -> int:
    mut values: int[] = []
    for j in range(len(args) + 100):
        append(mut values, (j * 37 + 5) % 1009)
    const c: u8 = u8(len(args) % 8) + 40u8
    mut total = 0
    for j in range(len(values)):
        total += values[j] % 1009 + int(c // 7u8)
    print(out, total)
    return 0
```
