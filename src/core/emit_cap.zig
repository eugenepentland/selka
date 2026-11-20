//! Entry authority creation is explicit and effectful; no token is ambient guest data.
const std = @import("std");
/// Allocation and a located effect site that cannot be emitted.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };
/// Emit a granted capability handle for an entry parameter of a provider family (clock, entropy, filesystem, network,
/// environment, process), the real `Stop` or a device's `Registers`, or null for any other parameter. A handle is a scalar (5C): the runtime
/// keeps its provider state until the process ends, so `main` destroys nothing after it returns, whether it takes the
/// handle or not.
pub fn entry(c: anytype, out: *std.ArrayList(u8), index: usize) !?[]const u8 {
    if (index >= c.options.main.capabilities.len) return null;
    const kind = c.options.main.capabilities[index];
    if (kind == stop_family) {
        const handle = try stop(@TypeOf(c), c, out, index);
        return handle;
    }
    // A device's `Registers` (MCU-B1D): its reads and writes are volatile accesses at their addresses, which ignore the
    // handle, so it is a constant.
    if (kind == registers_family) return "i64 0";
    if (kind > 4 and kind != 7) return null;
    if (!declared(@TypeOf(c), c, "myl_core_cap_grant")) {
        try c.declared.append(c.allocator, "myl_core_cap_grant");
        try c.externs.appendSlice(c.allocator, "declare i64 @myl_core_cap_grant(i32) nounwind\n");
    }
    try out.print(c.allocator, "  %cap{d} = call i64 @myl_core_cap_grant(i32 {d})\n", .{ index, kind });
    const argument = try std.fmt.allocPrint(c.allocator, "i64 %cap{d}", .{index});
    return argument;
}
/// The capability family of a `Stop` parameter (`Type.capabilityIndex`).
const stop_family: u8 = 9;
/// The capability family of a `Registers` parameter (`Type.capabilityIndex`), which only a device target provides.
const registers_family: u8 = 10;
/// The flag `emit_llvm.optional_family` sets on the family of an entry parameter written `T?`.
const optional_family: u8 = 0x80;

/// Emit the `Option` an entry parameter written `T?` receives (CAP-OPT), or null for any other parameter:
/// `myl_core_cap_offer` answers the handle `myl_core_cap_grant` makes when the command line grants the family, else 0
/// (a handle is never 0), and the entry passes `Some(handle)` or `None`. It grants nothing a plain `T` would not.
pub fn offered(comptime Context: type, c: Context, out: *std.ArrayList(u8), index: usize, param: @import("ir.zig").Type) Error!?[]const u8 {
    if (index >= c.options.main.capabilities.len) return null;
    const kind = c.options.main.capabilities[index];
    if (kind == 255 or kind & optional_family == 0) return null;
    if (c.module.kind(param) != .@"union" or c.module.passedInMemory(param)) return error.UnsupportedEntry;
    const layout = c.module.unionLayout(param);
    if (layout.form != .scalar or layout.payload != .cap) return error.UnsupportedEntry;
    var some: ?usize = null;
    var none: ?usize = null;
    for (c.module.compound(c.module.storageType(param)).@"union", 0..) |case, tag| {
        if (case == .cap) some = tag else if (case == .void) none = tag;
    }
    if (some == null or none == null) return error.UnsupportedEntry;
    if (!declared(Context, c, "myl_core_cap_offer")) {
        try c.declared.append(c.allocator, "myl_core_cap_offer");
        try c.externs.appendSlice(c.allocator, "declare i64 @myl_core_cap_offer(i32) nounwind\n");
    }
    try out.print(c.allocator,
        \\  %offer{0d} = call i64 @myl_core_cap_offer(i32 {1d})
        \\  %offer{0d}.held = icmp ne i64 %offer{0d}, 0
        \\  %offer{0d}.tag = select i1 %offer{0d}.held, i8 {2d}, i8 {3d}
        \\  %offer{0d}.case = insertvalue {{ i8, i64 }} poison, i8 %offer{0d}.tag, 0
        \\  %offer{0d}.value = insertvalue {{ i8, i64 }} %offer{0d}.case, i64 %offer{0d}, 1
        \\
    , .{ index, kind & ~optional_family, some.?, none.? });
    const argument = try std.fmt.allocPrint(c.allocator, "{{ i8, i64 }} %offer{d}.value", .{index});
    return argument;
}

/// The real `Stop` (FR5b): the call installs the SIGTERM and SIGINT handler and opens the wake-up descriptor, before
/// main's first statement, and answers handle 0. A main without a `Stop` emits no such call, so its program has no
/// handler and no descriptor.
fn stop(comptime Context: type, c: Context, out: *std.ArrayList(u8), index: usize) ![]const u8 {
    if (!declared(Context, c, "myl_core_stop_listen")) {
        try c.declared.append(c.allocator, "myl_core_stop_listen");
        try c.externs.appendSlice(c.allocator, "declare i64 @myl_core_stop_listen() nounwind\n");
    }
    try out.print(c.allocator, "  %stop{d} = call i64 @myl_core_stop_listen()\n", .{index});
    const argument = try std.fmt.allocPrint(c.allocator, "i64 %stop{d}", .{index});
    return argument;
}
/// Emit the host token when main declares Host, retaining the stream-token case.
pub fn token(c: anytype, out: *std.ArrayList(u8), index: usize) !?[]const u8 {
    if (index >= c.options.main.capabilities.len or c.options.main.capabilities[index] != 6) return null;
    try hostGrant(c, out, try std.fmt.allocPrint(c.allocator, "%host{d}", .{index}));
    const argument = try std.fmt.allocPrint(c.allocator, "i64 %host{d}", .{index});
    return argument;
}

/// Emit `NAME = call i64 @myl_core_host_grant()`, the `Host` token the runtime's grant answers: what `main(host: Host)` receives, and
/// what a device hook that takes `host` receives from its C-ABI function (MCU-NOC4C).
pub fn hostGrant(c: anytype, out: *std.ArrayList(u8), name: []const u8) !void {
    if (!declared(@TypeOf(c), c, "myl_core_host_grant")) {
        try c.declared.append(c.allocator, "myl_core_host_grant");
        try c.externs.appendSlice(c.allocator, "declare i64 @myl_core_host_grant() nounwind\n");
    }
    try out.print(c.allocator, "  {s} = call i64 @myl_core_host_grant()\n", .{name});
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
    for ([_][]const u8{ "myl_core_cap_", "myl_core_file_", "myl_core_span_file_", "myl_core_resource_", "myl_core_environment_", "myl_core_host_", "myl_core_clock_", "myl_core_process_", "myl_core_span_process_" }) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) return true;
    }
    const exact = [_][]const u8{
        "myl_core_external_read",      "myl_core_stand_in",          "myl_core_stream_write",
        "myl_core_stream_write_bytes", "myl_core_span_stream_write", "myl_core_stream_write_buffer",
        "myl_core_stream_flush",       "myl_core_stream_memory",     "myl_core_stream_text",
        "myl_core_input_memory",       "myl_core_input_read",        "myl_core_input_read_exact",
        "myl_core_input_read_line",    "myl_core_input_read_into",   "myl_core_stop_listen",
        "myl_core_stop_simulated",     "myl_core_stop_control",
    };
    for (exact) |known| if (std.mem.eql(u8, name, known)) return true;
    return false;
}
