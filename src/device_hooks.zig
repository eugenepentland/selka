//! The platform hooks a device's `hooks` key can bind to Selka functions (MCU-NOC4A): their names, the runtime symbol each one
//! replaces, and the Selka signature each must have.
//!
//! A hook is a `@freestanding` function whose first parameter is `Registers`, so it holds no authority it was not handed. Its
//! second parameter may be `Host` (MCU-NOC4C), for a hook that must call C, as the board's exit hook calls the boot ROM through an
//! `@address extern func`. The compiler writes, beside `main`, one C-ABI function named as the runtime's hook symbol (strong, so it
//! replaces the runtime's weak default) that calls the Selka function with the `Registers` token, the `Host` token when it takes
//! one (the runtime's grant, as `main(host: Host)` gets it), and the C arguments widened to Selka's types.
const std = @import("std");

/// The type of a hook's parameter after `Registers`, or of its result: `int` (a status or a number), `u32` (an address or a
/// size on the 32-bit target) or `bool`.
pub const Type = enum { int, u32, bool };

/// One hook: its key in `hooks`, the runtime symbol it replaces, its Selka signature after the `Registers` parameter, and
/// whether the runtime calls it as a function that does not return.
pub const Hook = struct {
    name: []const u8,
    symbol: []const u8,
    params: []const Type,
    result: ?Type = null,
    noreturn: bool = false,
};

/// Every hook, in the order a refusal lists them. `core_register` answers the address that reads the calling core's number (0 on
/// a platform with one core); `core1_launch` takes the vector table's, the stack top's and the entry's addresses.
pub const all = [_]Hook{
    .{ .name = "start", .symbol = "myl_bare_platform_start", .params = &.{} },
    .{ .name = "write", .symbol = "myl_bare_write", .params = &.{ .int, .u32, .u32 } },
    .{ .name = "exit", .symbol = "myl_bare_exit", .params = &.{.int}, .noreturn = true },
    .{ .name = "core_register", .symbol = "myl_bare_core_register", .params = &.{}, .result = .u32 },
    .{ .name = "core1_launch", .symbol = "myl_bare_core1_launch", .params = &.{ .u32, .u32, .u32 }, .result = .bool },
    .{ .name = "core_stop", .symbol = "myl_bare_core_stop", .params = &.{.int} },
    .{ .name = "lock", .symbol = "myl_bare_lock", .params = &.{.int} },
    .{ .name = "unlock", .symbol = "myl_bare_unlock", .params = &.{.int} },
};

/// The names of the hooks, as a refusal lists them.
pub const names_text = blk: {
    var text: []const u8 = "";
    for (all, 0..) |hook, index| text = text ++ (if (index == 0) "" else ", ") ++ hook.name;
    break :blk text;
};

/// The hook named `name`, or null.
pub fn named(name: []const u8) ?*const Hook {
    for (&all) |*hook| if (std.mem.eql(u8, hook.name, name)) return hook;
    return null;
}

/// The Selka signatures of `hook` as a refusal prints them, both accepted forms: `func(reg: Registers, stream: int, ...) -> bool`, or
/// the same with `host: Host` after `reg`. `buffer` should hold 320 bytes.
pub fn signature(buffer: []u8, hook: *const Hook) []const u8 {
    const plain = form(buffer, hook, false);
    if (plain.len == 0) return "";
    const joiner = std.fmt.bufPrint(buffer[plain.len..], " or ", .{}) catch return "";
    const hosted = form(buffer[plain.len + joiner.len ..], hook, true);
    if (hosted.len == 0) return "";
    return buffer[0 .. plain.len + joiner.len + hosted.len];
}

/// One form of the signature: with `host: Host` after `reg` when `with_host`.
fn form(buffer: []u8, hook: *const Hook, with_host: bool) []const u8 {
    var length: usize = 0;
    const head = std.fmt.bufPrint(buffer, "func(reg: Registers{s}", .{if (with_host) ", host: Host" else ""}) catch return "";
    length += head.len;
    for (hook.params, 0..) |param, index| {
        const text = std.fmt.bufPrint(buffer[length..], ", {s}: {s}", .{ parameterName(hook, index), @tagName(param) }) catch return "";
        length += text.len;
    }
    const tail = if (hook.result) |result| std.fmt.bufPrint(buffer[length..], ") -> {s}", .{@tagName(result)}) else std.fmt.bufPrint(buffer[length..], ")", .{});
    length += (tail catch return "").len;
    return buffer[0..length];
}

/// What a checked type is, as a hook's signature check reads a parameter or the result: the `Registers` or the `Host` capability, a
/// type a hook takes (`Type`), no result, or any other type.
pub const Shape = enum { registers, host, int, u32, bool, unit, other };

/// The `Shape` of a hook's parameter or result type.
fn shapeOf(kind: Type) Shape {
    return switch (kind) {
        .int => .int,
        .u32 => .u32,
        .bool => .bool,
    };
}

/// Whether a function with parameters `params` and result `result` can be `hook`: `Registers` first, then `Host` or not, then the hook's
/// own parameters. A `Host` anywhere else, or a second one, does not fit.
pub fn fits(hook: *const Hook, params: []const Shape, result: Shape) bool {
    if (params.len == 0 or params[0] != .registers) return false;
    const rest = if (params.len > 1 and params[1] == .host) params[2..] else params[1..];
    if (rest.len != hook.params.len) return false;
    for (hook.params, rest) |want, got| if (got != shapeOf(want)) return false;
    return result == (if (hook.result) |kind| shapeOf(kind) else Shape.unit);
}

/// Whether a function of `count` parameters that `fits` `hook` takes the `Host`: the hook's own parameters, `Registers` and `Host`.
pub fn takesHost(hook: *const Hook, count: usize) bool {
    return count == hook.params.len + 2;
}

/// The parameter name a refusal shows for parameter `index` of `hook`.
fn parameterName(hook: *const Hook, index: usize) []const u8 {
    const named_parameters = [_]struct { hook: []const u8, names: []const []const u8 }{
        .{ .hook = "write", .names = &.{ "stream", "address", "length" } },
        .{ .hook = "exit", .names = &.{"status"} },
        .{ .hook = "core1_launch", .names = &.{ "vectors", "stack_top", "entry" } },
        .{ .hook = "core_stop", .names = &.{"core"} },
        .{ .hook = "lock", .names = &.{"lock"} },
        .{ .hook = "unlock", .names = &.{"lock"} },
    };
    for (named_parameters) |entry| if (std.mem.eql(u8, entry.hook, hook.name)) return entry.names[index];
    return "value";
}

/// Whether `text` is `MODULE.FUNCTION`: dotted names of letters, digits and `_` that do not start with a digit, at least two.
pub fn wellFormed(text: []const u8) bool {
    var parts = std.mem.splitScalar(u8, text, '.');
    var count: usize = 0;
    while (parts.next()) |part| : (count += 1) {
        if (part.len == 0 or std.ascii.isDigit(part[0])) return false;
        for (part) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return count >= 2;
}

test "every hook names a runtime symbol once, and the signatures print as a refusal shows them" {
    for (all, 0..) |hook, index| for (all[index + 1 ..]) |other| {
        try std.testing.expect(!std.mem.eql(u8, hook.name, other.name));
        try std.testing.expect(!std.mem.eql(u8, hook.symbol, other.symbol));
    };
    var buffer: [320]u8 = undefined;
    try std.testing.expectEqualStrings("func(reg: Registers, stream: int, address: u32, length: u32) or func(reg: Registers, host: Host, stream: int, address: u32, length: u32)", signature(&buffer, named("write").?));
    try std.testing.expectEqualStrings("func(reg: Registers) or func(reg: Registers, host: Host)", signature(&buffer, named("start").?));
    try std.testing.expectEqualStrings("func(reg: Registers, vectors: u32, stack_top: u32, entry: u32) -> bool or func(reg: Registers, host: Host, vectors: u32, stack_top: u32, entry: u32) -> bool", signature(&buffer, named("core1_launch").?));
    try std.testing.expectEqualStrings("start, write, exit, core_register, core1_launch, core_stop, lock, unlock", names_text);
    try std.testing.expect(wellFormed("board.log_write") and wellFormed("a.b.c") and !wellFormed("write") and !wellFormed("a..b") and !wellFormed("1a.b"));
}

test "the longest signature text of any hook fits the 320 bytes a refusal gives it" {
    var buffer: [320]u8 = undefined;
    for (&all) |*hook| try std.testing.expect(signature(&buffer, hook).len > 0);
}

test "a hook takes Registers, then Host or not, then its own parameters; Host anywhere else or twice is refused" {
    const write = named("write").?;
    try std.testing.expect(fits(write, &.{ .registers, .int, .u32, .u32 }, .unit));
    try std.testing.expect(fits(write, &.{ .registers, .host, .int, .u32, .u32 }, .unit));
    try std.testing.expect(!fits(write, &.{ .registers, .int, .host, .u32, .u32 }, .unit));
    try std.testing.expect(!fits(write, &.{ .registers, .int, .u32, .u32, .host }, .unit));
    try std.testing.expect(!fits(write, &.{ .host, .registers, .int, .u32, .u32 }, .unit));
    try std.testing.expect(!fits(write, &.{ .registers, .host, .host, .int, .u32, .u32 }, .unit));
    try std.testing.expect(!fits(write, &.{ .registers, .host, .host, .u32, .u32 }, .unit));
    try std.testing.expect(!fits(write, &.{ .registers, .int, .u32, .u32 }, .int));
    const launch = named("core1_launch").?;
    try std.testing.expect(fits(launch, &.{ .registers, .host, .u32, .u32, .u32 }, .bool));
    try std.testing.expect(!fits(launch, &.{ .registers, .host, .u32, .u32, .u32 }, .unit));
    const start = named("start").?;
    try std.testing.expect(fits(start, &.{.registers}, .unit) and fits(start, &.{ .registers, .host }, .unit));
    try std.testing.expect(!fits(start, &.{ .registers, .host, .host }, .unit) and !fits(start, &.{.host}, .unit) and !fits(start, &.{}, .unit));
    try std.testing.expect(!takesHost(start, 1) and takesHost(start, 2) and takesHost(write, 5) and !takesHost(write, 4));
}

test "every one of the eight hooks accepts Host as its second parameter" {
    for (&all) |*hook| {
        var hosted: [6]Shape = undefined;
        var plain: [6]Shape = undefined;
        hosted[0] = .registers;
        hosted[1] = .host;
        plain[0] = .registers;
        for (hook.params, 0..) |kind, at| {
            hosted[2 + at] = shapeOf(kind);
            plain[1 + at] = shapeOf(kind);
        }
        const result: Shape = if (hook.result) |kind| shapeOf(kind) else .unit;
        try std.testing.expect(fits(hook, hosted[0 .. 2 + hook.params.len], result));
        try std.testing.expect(fits(hook, plain[0 .. 1 + hook.params.len], result));
    }
}
