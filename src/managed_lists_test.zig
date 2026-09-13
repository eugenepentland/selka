//! Source-level managed aliases, VM rooting, effects, and storage boundaries.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");

fn execute(text: []const u8, statistics: *language.vm.GcStatistics) !language.vm.Result {
    var compilation = try language.Compilation.init(t.allocator, "managed.my", text);
    defer compilation.deinit();
    return compilation.executeWithOptions(t.allocator, .{
        .memory = .{ .provide_allocator = false, .gc = .{ .stress = true, .statistics = statistics } },
    }) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
}

fn reject(text: []const u8, expected: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-managed.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(expected, compilation.diagnostics.items[0].code);
}

fn rejectAll(sources: []const []const u8, code: []const u8) !void {
    for (sources) |source| try reject(source, code);
}

// spec: GC-SOURCE-9
test "bytecode rejects managed metadata on an ordinary aggregate" {
    var compilation = try language.Compilation.init(t.allocator, "forged-managed.my", "struct Record{value:i64}fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.emit();
    var program = compilation.code.?;
    const records = try t.allocator.dupe(@import("typed.zig").Record, program.records);
    defer t.allocator.free(records);
    records[0].managed = true;
    program.records = records;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
}

fn allocationFailure(allocator: std.mem.Allocator, program: language.bytecode.Program) !void {
    var statistics: language.vm.GcStatistics = .{};
    const result = language.vm.runWithOptions(allocator, program, .{
        .memory = .{ .provide_allocator = false, .gc = .{ .stress = true, .statistics = &statistics } },
    });
    try t.expectEqual(@as(i64, 42), (try result).value);
}
