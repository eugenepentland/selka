//! `match mut <place>:` refusals (C1): a temporary or unnamed scrutinee, a container access while an arm's exclusive
//! hold is live, a payload binding moved or stored, a mutable write through an immutable owner, and the plain-match write
//! that stays refused. Each refusal is checked through the compiler's own diagnostic codes.
const std = @import("std");
const transition = @import("ownership_transition_test_support.zig");

const records =
    \\record Inst:
    \\    count: int
    \\    fields: int[]
    \\
    \\
    \\enum Obj:
    \\    free
    \\    instance(value: Inst)
    \\
    \\
;

test "C1 a temporary scrutinee is refused: match mut needs a place to write into" {
    try transition.refuses(std.testing.allocator, records ++
        \\func make() -> Obj:
        \\    return Obj.free
        \\
        \\
        \\func main() -> int:
        \\    match mut make():
        \\        case free:
        \\            return 1
        \\    return 0
        \\
    , "E_MATCH_MUT");
}

test "C1 a container access before the arm's last use of a binding is refused" {
    try transition.refuses(std.testing.allocator, records ++
        \\func main(out: Stream) -> int:
        \\    mut objs = [Obj.instance(value=Inst(count=0, fields=[]))]
        \\    match mut objs[0]:
        \\        case instance(value=payload):
        \\            print(out, len(objs))
        \\            payload.count = 1
        \\            return 0
        \\        case free:
        \\            return 1
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}

test "C1 a payload binding cannot be given away with own" {
    try transition.refuses(std.testing.allocator, records ++
        \\func keep(own inst: Inst) -> int:
        \\    return inst.count
        \\
        \\
        \\func main() -> int:
        \\    mut objs = [Obj.instance(value=Inst(count=0, fields=[]))]
        \\    match mut objs[0]:
        \\        case instance(value=payload):
        \\            return keep(own payload)
        \\        case free:
        \\            return 1
        \\
    , "E_SINGLE_OWNER_BORROW");
}

test "C1 a payload binding cannot be stored elsewhere" {
    try transition.refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut objs = [Obj.instance(value=Inst(count=0, fields=[]))]
        \\    mut saved = Inst(count=0, fields=[])
        \\    match mut objs[0]:
        \\        case instance(value=payload):
        \\            saved = payload
        \\            return saved.count
        \\        case free:
        \\            return 1
        \\
    , "E_SINGLE_OWNER_BORROW");
}

test "C1 writing through an immutable owner is refused" {
    try transition.refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    const objs = [Obj.instance(value=Inst(count=0, fields=[]))]
        \\    match mut objs[0]:
        \\        case instance(value=payload):
        \\            payload.count = 1
        \\            return 0
        \\        case free:
        \\            return 1
        \\
    , "E_SINGLE_OWNER_BORROW");
}

test "C1 a plain match still refuses a write through its binding" {
    try transition.refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut objs = [Obj.instance(value=Inst(count=0, fields=[]))]
        \\    match objs[0]:
        \\        case instance(value=payload):
        \\            payload.count = 1
        \\            return 0
        \\        case free:
        \\            return 1
        \\    return 0
        \\
    , "E_IMMUTABLE");
}

test "C1 match mut on a dictionary element is refused until dictionary exchange is lowered" {
    try transition.refuses(std.testing.allocator, records ++
        \\func main() -> int:
        \\    mut d: dict[int, Obj] = {1: Obj.instance(value=Inst(count=0, fields=[]))}
        \\    match mut d[1]:
        \\        case instance(value=payload):
        \\            payload.count = 1
        \\            return 0
        \\        case free:
        \\            return 1
        \\
    , "E_MATCH_MUT");
}

const scalar_union =
    \\enum Sh:
    \\    empty
    \\    rad(value: int)
    \\
    \\
;

test "FX5 match mut on a const local of a union of scalar payloads is still refused: the local must be mut" {
    try transition.refuses(std.testing.allocator, scalar_union ++
        \\func main() -> int:
        \\    const s = Sh.rad(value=1)
        \\    match mut s:
        \\        case rad(value=v):
        \\            v = 5
        \\        case empty:
        \\            return 0
        \\    return 1
        \\
    , "declare it `mut`");
}

test "FX5 match mut on a plain parameter or a loop variable of a union of scalar payloads is still refused" {
    try transition.refuses(std.testing.allocator, scalar_union ++
        \\func main() -> int:
        \\    return bump(Sh.empty)
        \\
        \\
        \\func bump(s: Sh) -> int:
        \\    match mut s:
        \\        case rad(value=v):
        \\            v = 5
        \\        case empty:
        \\            return 0
        \\    return 1
        \\
    , "E_SINGLE_OWNER_BORROW");
    try transition.refuses(std.testing.allocator, scalar_union ++
        \\func main() -> int:
        \\    for s in [Sh.empty]:
        \\        match mut s:
        \\            case rad(value=v):
        \\                v = 5
        \\            case empty:
        \\                return 0
        \\    return 1
        \\
    , "E_SINGLE_OWNER_BORROW");
}

// FX7b: the generated check alone may read the container a running arm holds. The same read written by hand, before a
// later use of a binding of a managed payload, stays refused.
test "FX7b a hand-written read of a container held by a match mut arm stays refused" {
    try transition.refuses(std.testing.allocator,
        \\record Pair:
        \\    a: int
        \\    b: str
        \\
        \\
        \\enum Mode:
        \\    off
        \\    on(pair: Pair)
        \\
        \\
        \\func level(m: Mode) -> int:
        \\    match m:
        \\        case on(pair=p):
        \\            return p.a
        \\        case off:
        \\            return 0
        \\
        \\
        \\@invariant(level(self.mode) >= 0, "level is never negative")
        \\record Switch:
        \\    tag: int
        \\    mode: Mode = Mode.off
        \\
        \\
        \\func main(args: str[]) -> int:
        \\    mut s = Switch(tag=1, mode=Mode.on(pair=Pair(a=1, b="x")))
        \\    match mut s.mode:
        \\        case on(pair=p):
        \\            p.a = 5
        \\            assert level(s.mode) >= 0
        \\            p.a = p.a + len(args)
        \\        case off:
        \\            return 1
        \\    return level(s.mode)
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}

/// A union of scalar payloads and two records that hold one, for the hold's refusals of a replacing write (FX9).
const scalar_unions =
    \\enum Sh:
    \\    empty
    \\    rad(value: int)
    \\
    \\
    \\record Holder:
    \\    tag: int
    \\    shape: Sh
    \\
    \\
    \\record Wrap:
    \\    name: int
    \\    holder: Holder
    \\
    \\
    \\enum Outer:
    \\    nothing
    \\    boxed(inner: Sh)
    \\
    \\
    \\func reset(mut s: Sh):
    \\    s = Sh.empty
    \\
    \\
    \\func touch(mut h: Holder):
    \\    h.tag = h.tag + 1
    \\
    \\
;

// FX9 (the user's decision HOLD, 13 November): a write that replaces the matched place, or a container of it, while a
// payload binding of the arm is still used afterwards is refused for a union of scalar payloads as for a managed one.
// Before, each of these built and ran: `s = Sh.empty` then `v = v + 8` read the empty case's payload and wrote the old
// case back (lane FX7's `clobber6.selka` printed 8).
test "FX9 replacing a local scalar union inside its own match mut arm before a later use of the binding is refused" {
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut s = Sh.rad(value=1)
        \\    match mut s:
        \\        case rad(value=v):
        \\            s = Sh.empty
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return 0
        \\
    , "move this write after that use, or write through the binding");
}

test "FX9 replacing a scalar union through a mut parameter, a field or its record is refused" {
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func poke(mut s: Sh) -> int:
        \\    match mut s:
        \\        case rad(value=v):
        \\            s = Sh.empty
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return 0
        \\
    , "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut h = Holder(tag=1, shape=Sh.rad(value=1))
        \\    match mut h.shape:
        \\        case rad(value=v):
        \\            h.shape = Sh.empty
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return h.tag
        \\
    , "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut w = Wrap(name=1, holder=Holder(tag=1, shape=Sh.rad(value=1)))
        \\    match mut w.holder.shape:
        \\        case rad(value=v):
        \\            w.holder = Holder(tag=2, shape=Sh.empty)
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return w.name
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}

test "FX9 a mut argument or an exchange that names the matched place or its record is refused" {
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut h = Holder(tag=1, shape=Sh.rad(value=1))
        \\    match mut h.shape:
        \\        case rad(value=v):
        \\            reset(mut h.shape)
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return h.tag
        \\
    , "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut h = Holder(tag=1, shape=Sh.rad(value=1))
        \\    match mut h.shape:
        \\        case rad(value=v):
        \\            touch(mut h)
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return h.tag
        \\
    , "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut s = Sh.rad(value=1)
        \\    match mut s:
        \\        case rad(value=v):
        \\            const old = exchange(mut s, Sh.empty)
        \\            v = v + 8
        \\        case empty:
        \\            return 1
        \\    return 0
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}

// FX9: an inner `match mut` on an enclosing arm's binding holds that binding: replacing it before the inner binding's
// last use is refused, for a scalar payload (FX7's `clobber3.selka` trapped `R_CORE_FACT`) and for a managed one (accepted
// before; the case happened to stay the same).
test "FX9 replacing an enclosing arm's binding inside a nested match mut on it is refused" {
    try transition.refuses(std.testing.allocator, scalar_unions ++
        \\func main() -> int:
        \\    mut o = Outer.boxed(inner=Sh.rad(value=1))
        \\    match mut o:
        \\        case boxed(inner=sh):
        \\            match mut sh:
        \\                case rad(value=v):
        \\                    sh = Sh.empty
        \\                    v = v + 8
        \\                case empty:
        \\                    return 1
        \\        case nothing:
        \\            return 1
        \\    return 0
        \\
    , "E_SINGLE_OWNER_OVERLAP");
    try transition.refuses(std.testing.allocator, records ++
        \\enum Box:
        \\    none
        \\    full(slot: Obj)
        \\
        \\
        \\func main() -> int:
        \\    mut b = Box.full(slot=Obj.instance(value=Inst(count=0, fields=[])))
        \\    match mut b:
        \\        case full(slot=s):
        \\            match mut s:
        \\                case instance(value=payload):
        \\                    s = Obj.instance(value=Inst(count=5, fields=[1]))
        \\                    payload.count = 1
        \\                case free:
        \\                    return 1
        \\        case none:
        \\            return 1
        \\    return 0
        \\
    , "E_SINGLE_OWNER_OVERLAP");
}
