//! Compare actual baseline/candidate discovery on an identical checked-program fixture.
const std = @import("std");
const baseline = @import("baseline");
const candidate = @import("candidate");
const typed = @import("typed");

const Fixture = struct {
    program: typed.Program,
    modules: []candidate.Module,
    baseline_modules: []baseline.Module,

    fn init(a: std.mem.Allocator, count: usize, declarations: usize) !Fixture {
        const modules = try a.alloc(candidate.Module, count);
        const peers = try a.alloc(baseline.Module, count);
        const functions = try a.alloc(typed.Function, count * declarations);
        for (modules, peers, 0..) |*module, *peer, index| {
            const name = try std.fmt.allocPrint(a, "module_{d}", .{index});
            var text: std.ArrayList(u8) = .empty;
            for (0..declarations) |position| {
                const own = try std.fmt.allocPrint(a, "test_{d}", .{position});
                try text.print(a, "public func {s}() -> bool:\n    return True\n", .{own});
                const id = index * declarations + position;
                functions[id] = .{
                    .name = try std.fmt.allocPrint(a, "{s}::{s}", .{ name, own }),
                    .id = @fromBackingInt(@intCast(id)),
                    .declaration = .{ .start = 0, .end = 0 },
                    .scope = .{ .body = @fromBackingInt(@intCast(0)) },
                    .signature = .{ .return_type = .bool },
                };
            }
            module.* = .{ .name = name, .text = text.items };
            peer.* = .{ .name = name, .text = text.items };
        }
        return .{ .program = .{ .nodes = &.{}, .statements = &.{}, .functions = functions, .main = @fromBackingInt(@intCast(0)) }, .modules = modules, .baseline_modules = peers };
    }
};

fn compare(count: usize, declarations: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try Fixture.init(arena.allocator(), count, declarations);
    var old_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer old_arena.deinit();
    var new_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer new_arena.deinit();
    const start = std.Io.Timestamp.now(std.testing.io, .awake);
    const before = try baseline.discover(old_arena.allocator(), fixture.program, "entry", fixture.baseline_modules);
    const middle = std.Io.Timestamp.now(std.testing.io, .awake);
    const after = try candidate.discover(new_arena.allocator(), fixture.program, "entry", fixture.modules);
    const end = std.Io.Timestamp.now(std.testing.io, .awake);
    try std.testing.expectEqual(count * declarations, before.len);
    try std.testing.expectEqual(before.len, after.len);
    for (before, after) |old, new| {
        try std.testing.expectEqualStrings(old.name, new.name);
        try std.testing.expectEqual(old.function, new.function);
        try std.testing.expectEqual(@backingInt(old.shape), @backingInt(new.shape));
        try std.testing.expectEqualSlices(u8, old.parameters, new.parameters);
    }
    std.debug.print("S06 modules={d} declarations_per_module={d} tests={d} old_ns={d} new_ns={d} old_module_comparisons={d} old_declaration_comparisons={d} new_hash_lookups={d}\n", .{
        count,              declarations,                                  before.len,    start.durationTo(middle).nanoseconds, middle.durationTo(end).nanoseconds,
        before.len * count, count * declarations * (declarations + 1) / 2, 2 * after.len,
    });
}

test "S06 discovery paired exact inventory profile" {
    try compare(1, 8);
    try compare(32, 32);
    try compare(128, 128);
    try shared(128, 16);
}

fn shared(count: usize, declarations: usize) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try Fixture.init(arena.allocator(), count, declarations);
    const start = std.Io.Timestamp.now(std.testing.io, .awake);
    for (0..count) |root| {
        var run = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer run.deinit();
        const own = fixture.baseline_modules[root .. root + 1];
        const cases = try baseline.within(run.allocator(), fixture.program, "entry", own, own);
        try std.testing.expectEqual(declarations, cases.len);
    }
    const middle = std.Io.Timestamp.now(std.testing.io, .awake);
    for (0..count) |root| {
        var run = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer run.deinit();
        const own = fixture.modules[root .. root + 1];
        const cases = try candidate.within(run.allocator(), fixture.program, "entry", own, own);
        try std.testing.expectEqual(declarations, cases.len);
    }
    const end = std.Io.Timestamp.now(std.testing.io, .awake);
    std.debug.print("S06 shared_roots={d} selected_per_root={d} program_functions={d} old_ns={d} new_ns={d}\n", .{ count, declarations, fixture.program.functions.len, start.durationTo(middle).nanoseconds, middle.durationTo(end).nanoseconds });
}
