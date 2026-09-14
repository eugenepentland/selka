//! Shared project runner for standard-library fixtures written in Python syntax.
const std = @import("std");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// Everything a fixture run can report: loading, checking, execution and assertions.
pub const Error = language.embedded_project.InitError || native.Error ||
    error{ TestExpectedEqual, TestUnexpectedResult, TestExpectedError };

/// Source provider that serves one in-memory entry module to the project loader.
pub const Entry = struct {
    text: []const u8,
    /// Serve `main.my` from the fixture text; every other path is a standard module.
    pub fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Entry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};

/// Compile a fixture against the embedded standard modules and run it natively.
pub fn expect(allocator: std.mem.Allocator, text: []const u8, options: native.Options, wanted: i64) Error!void {
    var entry: Entry = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(allocator, .{ .context = &entry, .read = Entry.read });
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, options);
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(wanted, outcome.value);
}

/// Compile a fixture and report the native trap that ended its run.
pub fn trap(allocator: std.mem.Allocator, text: []const u8, options: native.Options, code: []const u8) Error!void {
    var entry: Entry = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(allocator, .{ .context = &entry, .read = Entry.read });
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, options);
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings(code, outcome.trap.code);
}

/// Run a fixture with the native runtime's default budgets and grants.
pub fn run(allocator: std.mem.Allocator, text: []const u8, wanted: i64) Error!void {
    try expect(allocator, text, .{}, wanted);
}

/// Run a fixture while the collector runs at every managed allocation.
pub fn stress(allocator: std.mem.Allocator, text: []const u8, wanted: i64) Error!void {
    try expect(allocator, text, .{ .gc_stress = true }, wanted);
}

/// Check that a program using the standard modules fails to compile.
pub fn reject(allocator: std.mem.Allocator, text: []const u8) Error!void {
    var entry: Entry = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    program.init(allocator, .{ .context = &entry, .read = Entry.read }) catch |failure| {
        if (failure == error.SourceError) return;
        return failure;
    };
    program.deinit();
    return error.TestExpectedError;
}
