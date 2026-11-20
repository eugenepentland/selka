//! Value records: construction by field name, copy semantics, updated copies and
//! the diagnostics that reject unknown, missing and mistyped fields.
const fixture_path = "records.selka";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path,
        \\record Inner:
        \\    x: i64
        \\
        \\
        \\record Source:
        \\    inner: Inner
        \\    ignored: bool
        \\
        \\
        \\record Target:
        \\    value: i64
        \\
        \\
        \\conversion func convert(src: Source) -> Target:
        \\    _ = src.ignored
        \\    return Target(value=src.inner.x)
        \\
        \\
        \\func main() -> i64:
        \\    mut source = Source(ignored=True, inner=Inner(x=7))
        \\    mut next = source
        \\    next.inner = Inner(x=9)
        \\    return convert(next).value
    );
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "record schemas conversion checking construction assignment projection and dump clean up on allocation failure" {
    // Successful backing-heap resizes vary with address/heap state. Force the
    // allocation fallback so fail_index identifies the same operation each run.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

test "duplicate discovery retains nominal record and resolved field identities" {
    var compilation = try language.Compilation.init(testing.allocator, "identity.selka",
        \\record A:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\record B:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\func a(v: A) -> i64:
        \\    return v.x
        \\
        \\
        \\func b(v: B) -> i64:
        \\    return v.x
        \\
        \\
        \\func c(v: A) -> i64:
        \\    return v.y
        \\
        \\
        \\func d(renamed: A) -> i64:
        \\    return renamed.x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try testing.expectEqual(@as(usize, 1), analysis.groups.len);
    const members = analysis.groups[0].members;
    try testing.expectEqual(@as(usize, 2), members.len);
    try testing.expectEqualStrings("a", compilation.program.?.functions[@backingInt(members[0])].name);
    try testing.expectEqualStrings("d", compilation.program.?.functions[@backingInt(members[1])].name);
}

test "complete conversion accounts named source fields and requires complete destination" {
    try result(
        \\record Source:
        \\    x: i64
        \\    ignored: bool
        \\
        \\
        \\record Target:
        \\    y: i64
        \\
        \\
        \\conversion func convert(src: Source) -> Target:
        \\    _ = src.ignored
        \\    return Target(y=src.x * 2)
        \\
        \\
        \\func main() -> i64:
        \\    return convert(Source(x=4, ignored=True)).y
    , 8);
    try reject(
        \\record Source:
        \\    x: i64
        \\    added: bool
        \\
        \\
        \\record Target:
        \\    y: i64
        \\
        \\
        \\conversion func convert(src: Source) -> Target:
        \\    return Target(y=src.x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_CONVERSION");
    try reject(
        \\record Source:
        \\    x: i64
        \\
        \\
        \\record Target:
        \\    y: i64
        \\    added: bool
        \\
        \\
        \\conversion func convert(src: Source) -> Target:
        \\    return Target(y=src.x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_CONSTRUCTION");
    try result(
        \\record Source:
        \\    x: i64
        \\    added: bool
        \\
        \\
        \\func geometry(src: Source) -> i64:
        \\    return src.x
        \\
        \\
        \\func main() -> i64:
        \\    return geometry(Source(x=5, added=True))
    , 5);
    try reject(
        \\record Source:
        \\    x: i64
        \\
        \\
        \\record Target:
        \\    y: i64
        \\
        \\
        \\func helper(src: Source) -> i64:
        \\    return src.x
        \\
        \\
        \\conversion func convert(src: Source) -> Target:
        \\    return Target(y=helper(src))
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_INCOMPLETE_CONVERSION");
    try reject(
        \\record Source:
        \\    x: i64
        \\
        \\
        \\record Target:
        \\    y: i64
        \\
        \\
        \\conversion func convert(src: Source) -> Target:
        \\    mut unused = src.x
        \\    return Target(y=0)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_CONVERSION_BODY");
    try reject(
        \\record Source:
        \\    x: i64
        \\
        \\
        \\conversion func convert(src: Source) -> Source:
        \\    return src
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_CONVERSION_BODY");
}

test "record schemas conversion checking construction update projection and dump clean up on allocation failure" {
    // Successful backing-heap resizes vary with address/heap state. Force the
    // allocation fallback so fail_index identifies the same operation each run.
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
}

// spec: EQUALITY-CONTEXT-1
test "equality carries a field access type into a contextual constructor" {
    try result(
        \\enum Kind:
        \\    atom(value: str)
        \\    flag
        \\
        \\
        \\record Hold:
        \\    opt: str?
        \\    kind: Kind
        \\
        \\
        \\func check(hold: Hold) -> bool:
        \\    return hold.opt == Some("x") and hold.opt is not None and hold.kind == Kind.atom(value="x")
        \\
        \\
        \\func main() -> i64:
        \\    if check(Hold(opt=Some("x"), kind=Kind.atom(value="x"))):
        \\        return 7
        \\    return 1
    , 7);
    try reject(
        \\func main() -> i64:
        \\    mut value = Some("x") == Some("x")
        \\    return 1
    , "E_OPTION_INFERENCE");
}

// spec-case: EQUALITY-CONTEXT-2
test "equality does not invent an element type for two empty lists" {
    try reject(
        \\func main() -> int:
        \\    if [] == []:
        \\        return 0
        \\    return 1
    , "E_LIST_INFERENCE");
}

// spec: RECORD-DEFAULT-1
test "record field defaults fill omitted fields in positional and named construction" {
    try result(
        \\record Config:
        \\    retries: int = 3
        \\    verbose: bool = False
        \\    label: str = "auto"
        \\
        \\
        \\func main() -> i64:
        \\    mut positional = Config(retries=7)
        \\    mut named = Config(label="x")
        \\    return positional.retries + named.retries + 3
    , 13);
    // A required field may follow a defaulted one: a record is built by field name.
    try result(
        \\record Pair:
        \\    a: int = 1
        \\    b: int
        \\    c: str = "z"
        \\    d: int
        \\
        \\
        \\func main() -> i64:
        \\    const only = Pair(d=40, b=1)
        \\    const both = Pair(b=2, d=3, a=5)
        \\    return only.a + only.b + only.d + len(only.c) + both.a + both.b + both.d
    , 53);
    // A field left out that has no default is still refused at the construction.
    try reject(
        \\record Pair:
        \\    a: int = 1
        \\    b: int
        \\
        \\
        \\func main() -> i64:
        \\    return Pair(a=2).a
    , "E_INCOMPLETE_CONSTRUCTION");
}

test "an empty collection is a fresh field default, and a non-empty list or dictionary stays refused" {
    try result(
        \\record Box:
        \\    items: int[] = []
        \\    seen: set[str] = set()
        \\    raw: bytes = b""
        \\    names: dict[str, int] = {}
        \\
        \\
        \\func main() -> i64:
        \\    mut first = Box()
        \\    mut second = Box()
        \\    append(mut first.items, 7)
        \\    return len(first.items) * 100 + len(second.items) * 10 + len(second.seen) + len(second.raw) + len(second.names)
    , 100);
    try reject(
        \\record Box:
        \\    items: int[] = [1]
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\record Box:
        \\    names: dict[str, int] = {"a": 1}
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\func count(items: int[] = []) -> int:
        \\    return len(items)
        \\
        \\
        \\func main() -> int:
        \\    return count()
    , "E_DEFAULT_ARGUMENT");
}

test "a record field defaults to an enum case or a record value, built afresh by each construction" {
    try result(
        \\enum Kind:
        \\    ground
        \\    supply
        \\    tagged(code: int)
        \\
        \\
        \\record Turn:
        \\    angle: int = 0
        \\    names: str[] = []
        \\
        \\
        \\record Rail:
        \\    net: str
        \\    kind: Kind = Kind.ground
        \\    mark: Kind = Kind.tagged(code=7)
        \\    turn: Turn = Turn()
        \\    far: Turn = Turn(angle=90)
        \\
        \\
        \\func code(kind: Kind) -> int:
        \\    match kind:
        \\        case tagged(code=number):
        \\            return number
        \\        case _:
        \\            return 0
        \\
        \\
        \\func main() -> i64:
        \\    mut first = Rail(net="a")
        \\    mut second = Rail(net="b", kind=Kind.supply)
        \\    append(mut first.turn.names, "x")
        \\    if first.kind == Kind.ground and second.kind == Kind.supply:
        \\        return first.far.angle + code(first.mark) + len(first.turn.names) * 100 + len(second.turn.names) * 1000
        \\    return 1
    , 197);
}

test "a constructor default must be an enum case or a record constructor of plain values" {
    // A call of a function, at any depth, is no constructor.
    try reject(
        \\func pick(n: int) -> int:
        \\    return n
        \\
        \\
        \\record Turn:
        \\    angle: int = 0
        \\
        \\
        \\record Rail:
        \\    turn: Turn = Turn(angle=pick(2))
        \\
        \\
        \\func main() -> int:
        \\    return Rail().turn.angle
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\func pick(n: int) -> int:
        \\    return n
        \\
        \\
        \\record Rail:
        \\    angle: int = pick(2)
        \\
        \\
        \\func main() -> int:
        \\    return Rail().angle
    , "E_DEFAULT_ARGUMENT");
    // A case the enum does not declare.
    try reject(
        \\enum Kind:
        \\    ground
        \\
        \\
        \\record Rail:
        \\    kind: Kind = Kind.earth
        \\
        \\
        \\func main() -> int:
        \\    if Rail().kind == Kind.ground:
        \\        return 0
        \\    return 1
    , "E_UNKNOWN_VARIANT");
    // A constructor default of the wrong type is a type error.
    try reject(
        \\enum Kind:
        \\    ground
        \\
        \\
        \\record Rail:
        \\    count: int = Kind.ground
        \\
        \\
        \\func main() -> int:
        \\    return Rail().count
    , "E_TYPE");
}

test "a record field defaults to a non-empty bytes literal, a module constant, NaN or infinity" {
    try result(
        \\const LIMIT: int = 40
        \\const SHAPE: bytes = b"rect"
        \\const NAN: float = 0.0 / 0.0
        \\const INF: float = 1.0 / 0.0
        \\const HALF: float = 0.5
        \\
        \\
        \\record Geometry:
        \\    shape: bytes = b"round"
        \\    named: bytes = SHAPE
        \\    limit: int = LIMIT
        \\    below: int = -LIMIT
        \\    ratio: float = HALF
        \\    unset: float = NAN
        \\    top: float = INF
        \\    bottom: float = -INF
        \\
        \\
        \\func main() -> i64:
        \\    const g = Geometry()
        \\    const h = Geometry(shape=b"x", limit=1)
        \\    if g.unset == g.unset or not (g.top > float(g.limit)) or not (g.bottom < float(g.below)):
        \\        return 1
        \\    return len(g.shape) + len(g.named) + g.limit + g.below + int(g.ratio * 4.0) + len(h.shape) + h.limit
    , 5 + 4 + 40 - 40 + 2 + 1 + 1);
}

test "a field default that builds a record without a required field is refused at the declaration" {
    // Nothing constructs `Outer`: the declaration alone is refused, and the repair is to drop the default.
    try reject(
        \\record Inner:
        \\    net: bytes
        \\    gain: int = 1
        \\
        \\
        \\record Outer:
        \\    inner: Inner = Inner()
        \\    z: int = 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_INCOMPLETE_CONSTRUCTION");
    try reject(
        \\record Inner:
        \\    net: bytes
        \\
        \\
        \\record Middle:
        \\    inner: Inner
        \\
        \\
        \\record Outer:
        \\    middle: Middle = Middle(inner=Inner())
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_INCOMPLETE_CONSTRUCTION");
    // Naming the field in the default builds it.
    try result(
        \\record Inner:
        \\    net: bytes
        \\    gain: int = 1
        \\
        \\
        \\record Outer:
        \\    inner: Inner = Inner(net=b"GND")
        \\    z: int = 1
        \\
        \\
        \\func main() -> int:
        \\    return len(Outer().inner.net) + Outer().inner.gain
    , 4);
}

test "a field default that is no constant is refused with E_DEFAULT_ARGUMENT or the name's own error" {
    try reject(
        \\func helper(n: int) -> int:
        \\    return n
        \\
        \\
        \\record Rail:
        \\    pick: func(int) -> int = helper
        \\
        \\
        \\func main() -> int:
        \\    return Rail().pick(1)
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\func infinity() -> float:
        \\    return 1.0 / 0.0
        \\
        \\
        \\record Rail:
        \\    top: float = infinity()
        \\
        \\
        \\func main() -> int:
        \\    return int(Rail().top)
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\record Rail:
        \\    limit: int = LIMT
        \\
        \\
        \\func main() -> int:
        \\    return Rail().limit
    , "E_UNKNOWN_NAME");
    try reject(
        \\const SHAPE: bytes = b"rect"
        \\
        \\
        \\record Rail:
        \\    limit: int = SHAPE
        \\
        \\
        \\func main() -> int:
        \\    return Rail().limit
    , "E_TYPE");
    // A local of the constructing function is no constant: the default cannot see it.
    try reject(
        \\record Rail:
        \\    limit: int = width
        \\
        \\
        \\func main() -> int:
        \\    const width = 3
        \\    return Rail().limit
    , "E_UNKNOWN_NAME");
}

test "a type named like a builtin type is refused at its declaration, with the rename as the repair" {
    try reject(
        \\record Unit:
        \\    number: int
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_BUILTIN_TYPE_NAME");
    try reject(
        \\enum Unit:
        \\    none
        \\    farad
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_BUILTIN_TYPE_NAME");
    try reject(
        \\record int:
        \\    number: float
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_BUILTIN_TYPE_NAME");
    var compilation = try language.Compilation.init(testing.allocator, fixture_path,
        \\enum Unit:
        \\    none
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    const fix = compilation.diagnostics.items[0].provenance.fix.?;
    try testing.expectEqualStrings("RecordsUnit", fix.edit.text);
    try testing.expectEqual(@as(usize, 0), fix.more.len);
    // A name that only looks like one is a type like any other, and so is a prelude type's name.
    try result(
        \\record RecordsUnit:
        \\    number: int
        \\
        \\
        \\record Stream:
        \\    number: int
        \\
        \\
        \\func main() -> i64:
        \\    return RecordsUnit(number=1).number + Stream(number=2).number
    , 3);
}

test "function parameter and variant case field defaults stay scalar literals" {
    try reject(
        \\enum Kind:
        \\    ground
        \\
        \\
        \\func paint(kind: Kind = Kind.ground) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return paint()
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\record Turn:
        \\    angle: int = 0
        \\
        \\
        \\func spin(turn: Turn = Turn()) -> int:
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return spin()
    , "E_DEFAULT_ARGUMENT");
    try reject(
        \\enum Kind:
        \\    ground
        \\
        \\
        \\enum Shape:
        \\    dot(kind: Kind = Kind.ground)
        \\
        \\
        \\func main() -> int:
        \\    return 0
    , "E_DEFAULT_ARGUMENT");
}

// spec: RECORD-UPDATE-1
test "functional record update copies only named fields and leaves the base alone" {
    try result(
        \\record Config:
        \\    retries: int = 3
        \\    verbose: bool = False
        \\
        \\
        \\func main() -> i64:
        \\    mut base = Config(verbose=True)
        \\    mut changed = replace(base, retries=5)
        \\    if base.retries == 3 and changed.retries == 5 and changed.verbose:
        \\        return 9
        \\    return 0
    , 9);
    try result(
        \\func main() -> i64:
        \\    mut values: FixedArray[int, 3] = FixedArray[int, 3]([1, 2, 3])
        \\    mut changed = replace(values, 1, 9)
        \\    return changed[0] + changed[1] + changed[2]
    , 13);
    try result(
        \\func replace(a: int, b: int = 0) -> int:
        \\    return a + b
        \\
        \\
        \\func main() -> i64:
        \\    return replace(1, b=2)
    , 3);
    try reject(
        \\record P:
        \\    x: int
        \\
        \\
        \\func main() -> i64:
        \\    mut p = P(x=1)
        \\    mut q = replace(p, y=2)
        \\    return q.x
    , "E_UNKNOWN_FIELD");
    try reject(
        \\func main() -> i64:
        \\    mut n = 3
        \\    mut q = replace(n, x=2)
        \\    return q
    , "E_TYPE");
}
