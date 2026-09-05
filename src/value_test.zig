//! Storage experiments precede record syntax so lifetime failures stay isolated.
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const values = @import("value.zig");
const Value = values.Value;
const record_type: values.Type = @fromBackingInt(2);
const span: language.source.Span = .{ .start = 0, .end = 0 };
const Op = @FieldType(language.bytecode.Instruction, "op");
fn instruction(op: Op) language.bytecode.Instruction {
    return .{ .span = span, .op = op };
}

// Build, copy into a callee, return, overwrite a local, project a field, discard.
// The returned main value must survive all of those ownership boundaries.
const code = [_]language.bytecode.Instruction{
    instruction(.{ .push_i64 = 42 }),
    instruction(.{ .make_record = .{ .ty = record_type, .fields = 1 } }),
    instruction(.{ .store_local = @fromBackingInt(0) }),
    instruction(.{ .load_local = @fromBackingInt(0) }),
    instruction(.{ .call = @fromBackingInt(1) }),
    instruction(.{ .push_i64 = 9 }),
    instruction(.{ .make_record = .{ .ty = record_type, .fields = 1 } }),
    instruction(.{ .store_local = @fromBackingInt(0) }),
    instruction(.{ .get_field = 0 }),
    instruction(.{ .load_local = @fromBackingInt(0) }),
    instruction(.pop),
    instruction(.ret),
};
const program: language.bytecode.Program = .{ .functions = &.{
    .{ .id = @fromBackingInt(0), .name = "main", .locals = &.{.{ .name = "record", .declaration = span, .ty = record_type, .mutable = true }}, .instructions = &code },
    .{ .id = @fromBackingInt(1), .name = "identity", .parameter_count = 1, .return_type = record_type, .locals = &.{.{ .name = "argument", .declaration = span, .ty = record_type, .mutable = false }}, .instructions = &.{ instruction(.{ .load_local = @fromBackingInt(0) }), instruction(.ret) } },
} };

test "aggregate copies survive overwritten locals calls returns projection and discard" {
    try testing.expectEqual(@as(i64, 42), (try language.vm.run(testing.allocator, program)).value);
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    try testing.expectEqual(@as(i64, 42), (try language.vm.run(allocator, program)).value);
}

test "aggregate VM ownership releases on every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationScenario, .{});
}

test "step traps at each ownership boundary release aggregate storage" {
    // Also covers traps with both stack and locals referencing the same value.
    for (1..14) |budget| {
        const outcome = try language.vm.runWithOptions(testing.allocator, program, .{ .max_steps = budget });
        try testing.expectEqualStrings("R_STEP_LIMIT", outcome.trap.code);
    }
}

test "nested immutable fields remain alive independently of their containing value" {
    const inner = try Value.create(testing.allocator, record_type, &.{.{ .i64 = 7 }});
    defer inner.release(testing.allocator);
    const outer = try Value.create(testing.allocator, @fromBackingInt(3), &.{ inner, inner, .{ .bool = true } });
    const copy = try outer.getField(1);
    defer copy.release(testing.allocator);
    outer.release(testing.allocator);
    try testing.expectEqual(@as(i64, 7), (try copy.getField(0)).i64);
    try testing.expectEqual(record_type, copy.typeOf());
}

test "deep aggregate release is iterative and needs no additional allocations" {
    var root: Value = .{ .i64 = 7 };
    defer root.release(testing.allocator);
    for (0..20_000) |_| {
        const next = try Value.create(testing.allocator, record_type, &.{root});
        root.release(testing.allocator);
        root = next;
    }
    // The final defer frees the entire chain; guest depth does not recurse here.
}

test "internal field and scalar type errors release popped aggregate operands" {
    const variants = [_]Op{ .{ .get_field = 4 }, .neg_i64_checked, .not_bool };
    for (variants) |op| {
        const bad: language.bytecode.Program = .{ .functions = &.{.{
            .id = @fromBackingInt(0),
            .name = "main",
            .instructions = &.{ instruction(.{ .push_i64 = 7 }), instruction(.{ .make_record = .{ .ty = record_type, .fields = 1 } }), instruction(op), instruction(.ret) },
        }} };
        try testing.expectError(error.InternalError, language.vm.run(testing.allocator, bad));
    }
}

test "repeated record allocation retains bounded live storage" {
    // 10,000 overwrites at one local slot. A fixed live-memory allocator would
    // be obscured by allocation strategy, so cap outstanding bytes directly.
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    var live: Value = .{ .i64 = 0 };
    defer live.release(limiter.allocator());
    for (0..10_000) |i| {
        const next = try Value.create(limiter.allocator(), record_type, &.{.{ .i64 = @intCast(i) }});
        live.release(limiter.allocator());
        live = next;
    }
    try testing.expectEqual(@as(i64, 9999), (try live.getField(0)).i64);
}

const LimitedLiveAllocator = struct {
    parent: std.mem.Allocator,
    limit: usize,
    live: usize = 0,
    fn allocator(self: *LimitedLiveAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *LimitedLiveAllocator = @ptrCast(@alignCast(context));
        if (len > self.limit - self.live) return null;
        const result = self.parent.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.live += len;
        return result;
    }
    fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
        return false;
    }
    fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
        return null;
    }
    fn free(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *LimitedLiveAllocator = @ptrCast(@alignCast(context));
        self.live -= memory.len;
        self.parent.rawFree(memory, alignment, ret_addr);
    }
};

test "VM loop construction and overwrite fit a fixed live byte budget" {
    const loop: language.bytecode.Program = .{ .functions = &.{.{
        .id = @fromBackingInt(0),
        .name = "main",
        .locals = &.{ .{ .name = "i", .declaration = span, .ty = .i64, .mutable = true }, .{ .name = "record", .declaration = span, .ty = record_type, .mutable = true } },
        .instructions = &.{
            instruction(.{ .push_i64 = 0 }),
            instruction(.{ .store_local = @fromBackingInt(0) }),
            instruction(.{ .push_i64 = 0 }),
            instruction(.{ .make_record = .{ .ty = record_type, .fields = 1 } }),
            instruction(.{ .store_local = @fromBackingInt(1) }),
            instruction(.{ .load_local = @fromBackingInt(0) }),
            instruction(.{ .push_i64 = 10_000 }),
            instruction(.{ .cmp_i64 = .lt }),
            instruction(.{ .jump_if_false = 17 }),
            instruction(.{ .load_local = @fromBackingInt(0) }),
            instruction(.{ .make_record = .{ .ty = record_type, .fields = 1 } }),
            instruction(.{ .store_local = @fromBackingInt(1) }),
            instruction(.{ .load_local = @fromBackingInt(0) }),
            instruction(.{ .push_i64 = 1 }),
            instruction(.add_i64_checked),
            instruction(.{ .store_local = @fromBackingInt(0) }),
            instruction(.{ .jump = 5 }),
            instruction(.{ .load_local = @fromBackingInt(1) }),
            instruction(.{ .get_field = 0 }),
            instruction(.ret),
        },
    }} };
    var limiter = LimitedLiveAllocator{ .parent = testing.allocator, .limit = 4096 };
    try testing.expectEqual(@as(i64, 9999), (try language.vm.run(limiter.allocator(), loop)).value);
    try testing.expectEqual(@as(usize, 0), limiter.live);
}
