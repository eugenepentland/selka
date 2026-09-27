//! Byte fast copies guard real metadata and preserve their checked fallback.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const bytecode = @import("bytecode.zig");
const proof = @import("qbe_rc_byte_version.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def owned(out: Stream) -> int:
    \\    data = bytes([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
    \\    size = len(data)
    \\    total = 0
    \\    for i in range(size):
    \\        total += int(data[i])
    \\    out.print(total)
    \\    return total
    \\def mutable(out: Stream, data: byte_buffer) -> int:
    \\    total = 0
    \\    for i in range(len(data)):
    \\        total += int(data[i])
    \\    out.print(total)
    \\    return total
    \\def callback(out: Stream, data: bytes) -> int:
    \\    for i in range(len(data)):
    \\        out.print(data[i])
    \\    return 0
    \\def held(out: Stream, data: bytes) -> int:
    \\    total = 0
    \\    for i in range(len(data)):
    \\        total += int(data[i])
    \\    for value in data:
    \\        total += int(value)
    \\    out.print(total)
    \\    return total
    \\def main(out: Stream) -> int:
    \\    return owned(out)
;
fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_byte_version.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec: RC-READ-BYTES-VERSION-1
test "RC read bytes versions suppress only the guarded fast operand drop" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try emitted(false);
    defer output.deinit();
    const text = try named(output.value, "owned");
    const mark = std.mem.indexOf(u8, text, "# RC-READ-BYTES-VERSION-1") orelse return error.TestUnexpectedResult;
    const fast = std.mem.indexOfPos(u8, text, mark, "\n@fi") orelse return error.TestUnexpectedResult;
    const original = std.mem.indexOfPos(u8, text, fast, "\n@oi") orelse return error.TestUnexpectedResult;
    try t.expect(std.mem.indexOf(u8, text[mark..fast], "=w ceqw") != null);
    try t.expect(std.mem.indexOf(u8, text[mark..fast], ", 0\n") != null);
    try t.expect(std.mem.indexOf(u8, text[mark..fast], "storew") == null);
    try t.expect(std.mem.indexOf(u8, text[mark..fast], "@oi") != null);
    try t.expect(std.mem.indexOf(u8, text[fast..original], "myl_qbe_rc_slot_drop") == null);
    try t.expect(std.mem.indexOf(u8, text[fast..original], "myl_qbe_fail_index_bounds") == null);
    try t.expect(std.mem.indexOf(u8, text[original..], "myl_qbe_rc_slot_drop") != null);
    try t.expect(std.mem.indexOf(u8, text[original..], "myl_qbe_fail_index_bounds") != null);
}

// spec-case: RC-READ-BYTES-VERSION-1
test "RC read bytes versions refuse mutable bytes held loads callbacks and steps" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var output = try emitted(false);
    defer output.deinit();
    try t.expect(std.mem.indexOf(u8, try named(output.value, "mutable"), "RC-READ-BYTES-VERSION-1") == null);
    try t.expect(std.mem.indexOf(u8, try named(output.value, "held"), "RC-READ-BYTES-VERSION-1") == null);
    try t.expect(std.mem.indexOf(u8, try named(output.value, "callback"), "RC-READ-BYTES-VERSION-1") == null);
    var accounted = try emitted(true);
    defer accounted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(accounted.value, "owned"), "RC-READ-BYTES-VERSION-1") == null);
}

fn suffixAllowed(op: @FieldType(bytecode.Instruction, "op"), allowance: usize) bool {
    const code = [_]bytecode.Instruction{.{ .span = .{ .start = 0, .end = 0 }, .op = op }};
    var budget = allowance;
    return proof.suffixEntry(&code, 3, &budget);
}

// spec-case: RC-READ-BYTES-VERSION-1
test "RC read bytes suffix proof checks switch Result and exhausted branch work" {
    try t.expect(suffixAllowed(.{ .jump = 1 }, 1));
    try t.expect(!suffixAllowed(.{ .jump = 2 }, 1));
    try t.expect(!suffixAllowed(.{ .jump_if_false = 3 }, 1));
    try t.expect(!suffixAllowed(.{ .try_result = .{ .input = .i64, .output = .i64, .error_target = 2 } }, 1));
    try t.expect(!suffixAllowed(.{ .switch_variant = .{ .ty = .i64, .arms = &.{.{ .target = 3, .slot = null }} } }, 2));
    try t.expect(!suffixAllowed(.{ .switch_variant = .{ .ty = .i64, .arms = &.{.{ .target = 1, .slot = null }} } }, 1));
    try t.expect(suffixAllowed(.{ .switch_variant = .{ .ty = .i64, .arms = &.{.{ .target = 1, .slot = null }} } }, 2));
}

fn emptyAt(pc: usize, operand: usize, active: bool) bool {
    const Active = struct { read: ?struct { bytes: proof.Certificate } };
    const E = struct { version: ?*Active, pc: usize };
    var certificate: proof.Certificate = .{};
    certificate.reads[0] = .{ .pc = 5, .owner = 2, .operand = 0 };
    certificate.count = 1;
    var version: Active = .{ .read = .{ .bytes = certificate } };
    var emitter: E = .{ .version = if (active) &version else null, .pc = pc };
    return proof.emptyOperand(E, &emitter, operand);
}

// spec-case: RC-READ-BYTES-VERSION-1
test "RC read bytes drop query cannot escape its exact active copy instruction" {
    try t.expect(emptyAt(5, 0, true));
    try t.expect(!emptyAt(4, 0, true));
    try t.expect(!emptyAt(5, 1, true));
    try t.expect(!emptyAt(5, 0, false));
}

const GuardEmitter = struct {
    cow: ?struct { rc: ?*@import("qbe_rc_state.zig").State },
    function: struct { scope: struct { locals: []const u8 } },
    output: std.Io.Writer.Allocating,
    next: usize = 0,
    pc: usize = 3,

    /// Allocate a deterministic SSA name for the isolated guard.
    pub fn temp(self: *@This()) usize {
        self.next += 1;
        return self.next;
    }
    /// Preserve the production guard text for representation assertions.
    pub fn print(self: *@This(), comptime format: []const u8, args: anytype) !void {
        try self.output.writer.print(format, args);
    }
};
fn guardText(retained: bool) ![]u8 {
    var state: @import("qbe_rc_state.zig").State = undefined;
    state.active = true;
    state.plan.dictionary_tails = &.{};
    state.plan.journal = .{ .prefix = if (retained) &.{ 0, 1 } else &.{ 0, 0 } };
    var emitter: GuardEmitter = .{
        .cow = .{ .rc = &state },
        .function = .{ .scope = .{ .locals = &.{} } },
        .output = .init(t.allocator),
    };
    defer emitter.output.deinit();
    var certificate: proof.Certificate = .{};
    certificate.reads[0] = .{ .pc = 5, .owner = 2, .operand = 0 };
    certificate.count = 1;
    try proof.guard(GuardEmitter, &emitter, certificate, 3);
    return t.allocator.dupe(u8, emitter.output.writer.buffer[0..emitter.output.writer.end]);
}

// spec-case: RC-READ-BYTES-VERSION-1
test "RC read bytes require real operand guard without changing its contents" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const text = try guardText(true);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "=w ceqw %v1, 0") != null);
    try t.expect(std.mem.indexOf(u8, text, "@oi3") != null);
    try t.expect(std.mem.indexOf(u8, text, "store") == null);
    try t.expectError(error.InternalError, guardText(false));
}

fn holdBudget(matching: usize, allowance: usize) bool {
    var function: bytecode.Function = undefined;
    var locals: [256]@import("typed.zig").Local = undefined;
    for (&locals, 0..) |*local, index| local.ty = if (index < matching) .i64 else .bool;
    const code: [4096]bytecode.Instruction = undefined;
    function.scope.locals = &locals;
    function.scope.instructions = &code;
    var budget = allowance;
    return proof.chargeHolds(function, .i64, &budget);
}

// spec-case: RC-READ-BYTES-VERSION-1
test "RC read bytes held-role scans refuse cumulative large-local work" {
    try t.expect(holdBudget(63, 262144));
    try t.expect(!holdBudget(64, 262144));
    try t.expect(!holdBudget(256, 262144));
    try t.expect(holdBudget(0, 256));
    try t.expect(!holdBudget(0, 255));
}
