# G13. A contract is never skipped: pinned examples

## Holds

**G13-H1 (a write through a `match mut` binding is checked against the record's invariant; FX7b).** The write `v = -5`
goes through the binding into `s.mode`, and `Switch`'s invariant is checked right after it, as after the direct write
`s.mode = Mode.on(level=-5)`: the program traps `R_INVARIANT` at that line. Before 13 November no check followed such a
write and the program printed -5 (lane W11's probe). `src/contracts_test.zig` pins the trap for every way of leaving
the arm after the write and for each write form.

```selka
# doc: expect-trap R_INVARIANT
enum Mode:
    off
    on(level: int)


func level(m: Mode) -> int:
    match m:
        case on(level=v):
            return v
        case off:
            return 0


@invariant(level(self.mode) >= 0, "level is never negative")
record Switch:
    tag: int
    mode: Mode = Mode.off


func main(out: Stream) -> int:
    mut s = Switch(tag=1, mode=Mode.on(level=1))
    match mut s.mode:
        case on(level=v):
            v = -5
        case off:
            return 1
    print(out, level(s.mode))
    return 0
```
