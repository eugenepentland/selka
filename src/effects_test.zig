const fixture_path = "effects.my";
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const sets = @import("effect_set.zig");
const declarations = @import("fixture_declarations_test.zig").allocator_results;
fn reject(source: []const u8, code: []const u8, text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, text) != null);
    if (std.mem.eql(u8, code, "E_EFFECT_BOUND")) try t.expect(c.diagnostics.items[0].related != null);
}
fn result(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectEqual(expected, (try c.execute(t.allocator)).value);
}

const accepted = declarations ++ "fn edit(input: B) -> R noalloc { let mut b = input; discard try " ++
    "append_buffer<Status>(b, 7); _ = resize_buffer<Status>(b, 2, 9)?; borrow mut " ++
    "b[0..2] as s { write_slice(s, 1, 11); } return new R.ok(b); } fn release(input: B) " ++
    "-> i64 effects() { _ = input; return 3; } fn main(alloc: allocator) -> i64 " ++
    "effects(allocation) { match acquire_buffer<R>(alloc, 2) { R.ok(b) => { match edit(b) " ++
    "{ R.ok(updated) => { let n = read_buffer(updated, 1); return n + release(updated); }," ++
    " R.err(e) => { return e; } } }, R.err(e) => { return e; } } }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, accepted);
    defer c.deinit();
    try t.expectEqual(@as(i64, 14), (try c.execute(allocator)).value);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    var found = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, fixture_path, declarations ++ "fn helper(alloc: allocator) -> R { return acquire_buffer<R>(alloc, 1); } fn " ++
        "main(alloc: allocator) -> i64 noalloc { _ = helper(alloc); return 0; }");
    defer c.deinit();
    c.check() catch |err| switch (err) {
        error.SourceError => {
            const rendered = try c.diagnostics.items[0].render(allocator, c.src);
            defer allocator.free(rendered);
            return;
        },
        else => return err,
    };
    return error.TestUnexpectedResult;
}
test "effect graph inference witnesses emission and rendering release every failed allocation" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    try t.checkAllAllocationFailures(no_resize.allocator(), rejectionScenario, .{});
}

test "duplicate discovery retains normalized declared effect contracts" {
    var c = try language.Compilation.init(t.allocator, fixture_path, "fn a(n: i64) -> i64 effects(clock, random) { return n + 1; } fn b(x: i64) -> i64 " ++
        "effects(random, clock) { return x + 1; } fn different(n: i64) -> i64 noalloc { " ++
        "return n + 1; } fn main() -> i64 { return 0; }");
    defer c.deinit();
    try c.check();
    var found = try language.duplicates.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer found.deinit();
    try t.expectEqual(@as(usize, 1), found.groups.len);
    try t.expectEqual(@as(usize, 2), found.groups[0].members.len);
}

test "effect rendering propagates a full writer failure" {
    var storage: [0]u8 = .{};
    var writer: std.Io.Writer = .fixed(&storage);
    try t.expectError(error.WriteFailed, sets.write(&writer, sets.bit(.managed_allocation)));
}
