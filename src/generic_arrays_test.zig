//! Generic fixed arrays preserve shape, nominal identity, borrowing, and universal checking.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const type_catalog = @import("type_catalog.zig");
const factories =
    \\domain Component: u64:
    \\    def make(n: u64) -> Component:
    \\        return wrap[Component](n)
    \\
    \\
    \\domain Net: u64:
    \\    def make(n: u64) -> Net:
    \\        return wrap[Net](n)
    \\
    \\
    \\
;
const helpers =
    \\public def pair[T](a: T, b: T) -> [2]T effects():
    \\    return [a, b]
    \\
    \\
    \\public def contains[T: equality](a: [2]T, n: T) -> bool effects():
    \\    i = 0
    \\    while i < len(a):
    \\        if a[i] == n:
    \\            return True
    \\        i = i + 1
    \\    return False
    \\
    \\
    \\
;
fn value(allocator: std.mem.Allocator, source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(allocator, "arrays.my", source);
    defer compilation.deinit();
    try t.expectEqual(expected, (try native.run(&compilation)).value);
}
fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-arrays.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}
const membership = factories ++ helpers ++
    \\def main() -> i64:
    \\    components = pair[Component](Component.make(1u64), Component.make(2u64))
    \\    nets = pair[Net](Net.make(8u64), Net.make(9u64))
    \\    if contains[Component](components, Component.make(2u64)) and not contains[Component](components, Component.make(8u64)) and contains[Net](nets, Net.make(9u64)):
    \\        return 1
    \\    return 0
;
test "generic array templates reject invalid uncalled bodies and invalid lengths" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source =
        \\def f[T, U](a: [2]T) -> [2]U:
        \\    return a
        , .code = "E_GENERIC_TYPE" },
        .{ .source =
        \\def f[T](a: T) -> [2]T:
        \\    return [a]
        , .code = "E_ARRAY_LENGTH" },
        .{ .source =
        \\def f[T](a: [2]T) -> T:
        \\    return a[0] + a[1]
        , .code = "E_GENERIC_OPERATION" },
        .{ .source =
        \\def f[T](a: [2]T) -> bool:
        \\    return a[0] == a[1]
        , .code = "E_GENERIC_OPERATION" },
        .{ .source =
        \\def f[T: equality](a: [2]T) -> bool:
        \\    return a == a
        , .code = "E_GENERIC_OPERATION" },
        .{ .source =
        \\def f[T](a: [2]T) -> [3]T:
        \\    return a
        , .code = "E_GENERIC_TYPE" },
        .{ .source =
        \\def f[T](a: [2]T) -> T:
        \\    return a[True]
        , .code = "E_GENERIC_OPERATION" },
        .{ .source =
        \\def f[T](a: T) -> [2]T:
        \\    return [a, True]
        , .code = "E_GENERIC_TYPE" },
        .{ .source =
        \\def f[T](a: [2]Missing) -> i64:
        \\    return 0
        , .code = "E_UNKNOWN_TYPE" },
        .{ .source =
        \\def f[T](a: [1u64]T) -> i64:
        \\    return 0
        , .code = "E_ARRAY_LENGTH" },
        .{ .source =
        \\def f[T](a: [18446744073709551615]T) -> i64:
        \\    return 0
        , .code = "E_ARRAY_LENGTH" },
        .{ .source =
        \\def f[T](a: [T]i64) -> i64:
        \\    return 0
        , .code = "E_GENERIC_ARRAY_KEY" },
        .{ .source =
        \\enum Key:
        \\    a,
        \\    b
        \\
        \\
        \\def f[T](a: [Key]T) -> i64:
        \\    return 0
        , .code = "E_GENERIC_ARRAY_KEY" },
    };
    for (cases) |case| {
        const source = try std.mem.concat(t.allocator, u8, &.{
            case.source, "\n\n\n",
            \\def main() -> i64:
            \\    return 0
        });
        defer t.allocator.free(source);
        try reject(source, case.code);
    }
}

const views =
    \\def window[T](a: [2]T) -> [2]T:
    \\    return a
    \\
    \\
    \\def edit[T](x: T, y: T) -> T:
    \\    a: [2]T = [x, y]
    \\    original = a
    \\    a = replace(a, 0, y)
    \\    a = replace(a, 1, x)
    \\    part = window[T](a)
    \\    _ = part[0]
    \\    return original[0]
    \\
    \\
    \\
;
fn allocations(allocator: std.mem.Allocator) !void {
    try value(allocator, membership, 1);
    try value(allocator, views ++
        \\def main() -> i64:
        \\    return edit[i64](7, 9)
    , 7);
}
test "generic array specialization and execution clean up under allocation failure" {
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocations, .{});
}

test "generic array runtime indexing retains traps and source locations" {
    var compilation = try language.Compilation.init(t.allocator, "bounds.my", helpers ++
        \\def at[T](a: [2]T, i: u64) -> T:
        \\    return a[i]
        \\
        \\
        \\def main() -> i64:
        \\    return at[i64](pair[i64](1, 2), 2u64)
    );
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try t.expectEqualStrings("R_LIST_BOUNDS", result.trap.code);
    try t.expectEqualStrings("bounds.my", result.trap.path);
    try t.expectEqual(@as(u64, 15), result.trap.line);
    try t.expectEqualStrings("at[i64]", result.trap.frames[0].function);
}

const Modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import collection as c
            \\import model as m
            \\
            \\
            \\def main() -> i64:
            \\    if c.contains[m.Id](c.pair[m.Id](m.Id.make(3), m.Id.make(5)), m.Id.make(5)):
            \\        return 1
            \\    return 0
        );
        if (std.mem.eql(u8, path, "collection.my")) return allocator.dupe(u8, "module collection;" ++ helpers);
        if (std.mem.eql(u8, path, "model.my")) return allocator.dupe(u8,
            \\module model
            \\
            \\
            \\public domain Id: i64:
            \\    def make(n: i64) -> Id effects():
            \\        return wrap[Id](n)
        );
        return error.NotFound;
    }
};
fn moduleScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Modules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 1), (try native.run(&compilation)).value);
}
test "exported generic arrays resolve imported nominal arguments across source relocation" {
    try moduleScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), moduleScenario, .{});
}

test "generic arrays retain concrete identity reuse and formatter round trips" {
    var compilation = try language.Compilation.init(t.allocator, "format.my", helpers ++
        \\def main() -> i64:
        \\    a: [2]i64 = pair[i64](1, 2)
        \\    b = pair[i64](3, 4)
        \\    return a[0] + b[1]
    );
    defer compilation.deinit();
    try compilation.check();
    var count: usize = 0;
    for (compilation.program.?.records) |record| {
        if (record.shape.array) |shape| if (shape.element == .i64 and shape.length == 2) {
            count += 1;
        };
    }
    try t.expectEqual(@as(usize, 1), count);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try value(t.allocator, formatted, 5);
    var again = try language.Compilation.init(t.allocator, "again.my", formatted);
    defer again.deinit();
    const stable = try again.format(t.allocator);
    defer t.allocator.free(stable);
    try t.expectEqualStrings(formatted, stable);
}

// spec: GENERIC-ARRAY-1
test "generic array membership reuses code across nominal IDs without mixing domains" {
    try value(t.allocator, membership, 1);
    try reject(factories ++ helpers ++
        \\def main() -> i64:
        \\    _ = contains[Component](pair[Net](Net.make(1u64), Net.make(2u64)), Component.make(1u64))
        \\    return 0
    , "E_TYPE");
}

test "expanding generic array recursion stops at the specialization budget" {
    try reject(
        \\def grow[T](x: T) -> i64:
        \\    return grow[[1]T]([x])
        \\
        \\
        \\def main() -> i64:
        \\    return grow[i64](1)
    , "E_GENERIC_LIMIT");
    var compilation = try language.Compilation.init(t.allocator, "shape-budget.my",
        \\def grow[T](x: T) -> i64:
        \\    pair: [2]T = [x, x]
        \\    _ = pair
        \\    return grow[[1]T]([x])
        \\
        \\
        \\def main() -> i64:
        \\    return grow[i64](1)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    // One instance makes one shape per spelling, so the recursion meets its
    // declaration's instance budget (GENERIC-INSTANCE-BUDGET-1) first.
    try t.expectEqualStrings("generic specialization exceeds instance or type argument budget", compilation.diagnostics.items[0].message);
}
/// One family of specialization at one spelling.
const Charge = struct { kind: type_catalog.SiteKind, span: language.source.Span };
/// Charge `site` its whole budget of distinct specializations.
fn fillSite(catalog: *type_catalog.Catalog, allocator: std.mem.Allocator, site: Charge, sink: *language.diagnostic.Sink) !void {
    for (0..type_catalog.max_site_specializations) |_| try catalog.chargeSite(allocator, site.kind, site.span, sink);
}
// spec: GENERIC-SITE-BUDGET-1
test "array shapes and callback signatures are budgeted per spelling, not per program" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var none: [0]@import("typed.zig").Record = .{};
    var catalog: type_catalog.Catalog = .{ .records = &none, .names = .empty };
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    const first: language.source.Span = .{ .start = 10, .end = 14 };
    const second: language.source.Span = .{ .start = 20, .end = 24 };
    // One spelling takes its whole budget; another spelling, and the other
    // family at the same spelling, still have their own.
    const sites = [_]Charge{ .{ .kind = .array, .span = first }, .{ .kind = .array, .span = second }, .{ .kind = .callback, .span = first } };
    for (sites) |site| try fillSite(&catalog, a, site, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    try t.expectError(error.SourceError, catalog.chargeSite(a, .array, first, &sink));
    try t.expectEqualStrings("E_GENERIC_LIMIT", sink.items.items[0].code);
    try t.expectEqual(first.start, sink.items.items[0].span.start);
    try t.expectError(error.SourceError, catalog.chargeSite(a, .callback, first, &sink));
    try t.expectEqualStrings("callback specialization at this spelling exceeds 4096 distinct signatures", sink.items.items[1].message);
}
