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
        \\    return hold.opt == Some("x") and hold.opt != None and hold.kind == Kind.atom(value="x")
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
    try reject(
        \\record Bad:
        \\    a: int = 1
        \\    b: int
        \\
        \\
        \\def main() -> i64:
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
