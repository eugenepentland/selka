//! Entry authority creation is explicit and effectful; no token is ambient guest data.
const std = @import("std");
/// Allocation and a located effect site that cannot be emitted.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };
/// Emit a named capability argument and its one-count release after main.
pub fn entry(c: anytype, out: *std.ArrayList(u8), cleanup: *std.ArrayList(u8), index: usize) ![]const u8 {
    const kind = if (index < c.options.main.capabilities.len) c.options.main.capabilities[index] else return error.UnsupportedEntry;
    if (kind > 4) return error.UnsupportedEntry;
    if (!declared(@TypeOf(c), c, "myl_core_cap_grant")) {
        try c.declared.append(c.allocator, "myl_core_cap_grant");
        try c.externs.appendSlice(c.allocator, "declare ptr @myl_core_cap_grant(i32) nounwind\n");
    }
    try out.print(c.allocator, "  %cap{d} = call ptr @myl_core_cap_grant(i32 {d})\n", .{ index, kind });
    try cleanup.print(c.allocator, "  call void @myl_core_release(ptr %cap{d})\n", .{index});
    return std.fmt.allocPrint(c.allocator, "ptr %cap{d}", .{index});
}
/// Emit the host token when main declares Host, retaining the stream-token case.
pub fn token(c: anytype, out: *std.ArrayList(u8), index: usize) !?[]const u8 {
    if (index >= c.options.main.capabilities.len or c.options.main.capabilities[index] != 6) return null;
    if (!declared(@TypeOf(c), c, "myl_core_host_grant")) {
        try c.declared.append(c.allocator, "myl_core_host_grant");
        try c.externs.appendSlice(c.allocator, "declare i64 @myl_core_host_grant() nounwind\n");
    }
    try out.print(c.allocator, "  %host{d} = call i64 @myl_core_host_grant()\n", .{index});
    const argument = try std.fmt.allocPrint(c.allocator, "i64 %host{d}", .{index});
    return argument;
}

fn declared(comptime Context: type, c: Context, name: []const u8) bool {
    for (c.declared.items) |symbol| if (std.mem.eql(u8, symbol, name)) return true;
    return false;
}

/// Record the checked effect call site so an adapter failure keeps guest diagnostics.
pub fn beforeCall(comptime Context: type, c: Context, out: *std.ArrayList(u8), inst: @import("ir.zig").Inst) Error!void {
    const function = c.module().functions.items[inst.a.index()];
    if (function.signature.linkage != .runtime_c or !effectHelper(function.name)) return;
    if (!declared(@TypeOf(c.state), c.state, "myl_core_io_at")) {
        try c.state.declared.append(c.a(), "myl_core_io_at");
        try c.state.externs.appendSlice(c.a(), "declare void @myl_core_io_at(ptr) nounwind\n");
    }
    const site = try c.site(.trace, inst, "effect");
    try out.print(c.a(), "  call void @myl_core_io_at(ptr @myl.site.{d})\n", .{site});
}

fn effectHelper(name: []const u8) bool {
    for ([_][]const u8{ "myl_core_cap_", "myl_core_file_", "myl_core_resource_", "myl_core_environment_", "myl_core_host_", "myl_core_clock_" }) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    const exact = [_][]const u8{ "myl_core_external_read", "myl_core_stand_in", "myl_core_stream_write", "myl_core_stream_write_bytes", "myl_core_stream_write_buffer" };
    for (exact) |known| if (std.mem.eql(u8, name, known)) return true;
    return false;
}
