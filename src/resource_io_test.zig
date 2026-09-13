//! Resource IO execution and metadata validation tests. Fake providers track exactly-once release and completion.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const resources = @import("external_resources.zig");
const declarations = "resource File: filesystem; result Open { ok: File, err: i64 } struct Chunk { eof: " ++
    "bool, bytes: [4]u8, length: u64 } result Read { ok: Chunk, err: i64 } result Written " ++
    "{ ok: u64, err: i64 } struct Failure { resource: File, code: i64 } result Finish { " ++
    "ok: bool, err: Failure } result Status { ok: i64, err: i64 } ";
const Fake = struct {
    live: usize = 0,
    releases: usize = 0,
    completions: usize = 0,
    reads: usize = 0,
    writes: usize = 0,
    cursor: usize = 0,
    data: []const u8 = "\x00\xff\x07",
    written: [8]u8 = @splat(0),
    failure: ?external.CallError = null,
    invalid_count: bool = false,
    fn acquire(context: *anyopaque, _: []const u8, _: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.live += 1;
        return 1;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.completions += 1;
        self.live -= 1;
    }
    fn release(context: *anyopaque, _: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.releases += 1;
        self.live -= 1;
    }
    fn read(context: *anyopaque, _: u64, output: []u8) external.CallError!resources.Read {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.reads += 1;
        if (self.failure) |err| return err;
        @memset(output, 99);
        if (self.invalid_count) return .{ .length = output.len + 1, .eof = false };
        const count = @min(2, @min(output.len, self.data.len - self.cursor));
        @memcpy(output[0..count], self.data[self.cursor..][0..count]);
        self.cursor += count;
        return .{ .length = count, .eof = self.cursor == self.data.len };
    }
    fn write(context: *anyopaque, _: u64, input: []const u8) external.CallError!usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.writes += 1;
        if (self.failure) |err| return err;
        if (self.invalid_count) return input.len + 1;
        const count = @min(2, input.len);
        @memcpy(self.written[0..count], input[0..count]);
        return count;
    }
    fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .complete = complete, .release = release, .read = read, .write = write };
    }
};
fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "io.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const source = declarations ++ "fn work(fs: filesystem_cap) -> Status { let mut file = acquire_resource<Open>(fs," ++
    " new [0]u8 [])?; let first = read_resource<Read>(file)?; let second = " ++
    "read_resource<Read>(file)?; let count = write_resource<Written>(file, new [3]u8 " ++
    "[7u8, 8u8, 9u8])?; match complete_resource<Finish>(file) { Finish.ok(done) => { " ++
    "_ = done; }, Finish.err(failure) => { return new Status.err(failure.code); } } " ++
    "if first.eof || !second.eof { return new Status.err(99); } return new " ++
    "Status.ok(cast<i64>(first.bytes[1]) + cast<i64>(second.bytes[0]) + " ++
    "cast<i64>(first.bytes[3]) + cast<i64>(count)); } fn main(fs: filesystem_cap) -> i64 " ++
    "noalloc { match work(fs) { Status.ok(value) => { return value; }, Status.err(code) " ++
    "=> { return -code; } } }";
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "io.my", source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 264), (try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 2), fake.reads);
    try t.expectEqual(@as(usize, 1), fake.writes);
    try t.expectEqual(@as(usize, 1), fake.completions);
    try t.expectEqual(@as(usize, 0), fake.releases);
    try t.expectEqualSlices(u8, &.{ 7, 8 }, fake.written[0..2]);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "RESOURCE_read") != null);
    var duplicates = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer duplicates.deinit();
}
test "source resource reads expose partial data EOF and padding while writes report actual progress" {
    try scenario(t.allocator);
}
test "resource IO failures retain owners until explicit completion or fallback" {
    var c = try language.Compilation.init(t.allocator, "io.my", source);
    defer c.deinit();
    for ([_]external.CallError{ error.Unavailable, error.Denied, error.Failed, error.OutOfMemory }, 1..) |failure, code| {
        var fake: Fake = .{ .failure = failure };
        if (failure == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } }));
        } else try t.expectEqual(-@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
        try t.expectEqual(@as(usize, 1), fake.releases);
        try t.expectEqual(@as(usize, 0), fake.completions);
        try t.expectEqual(@as(usize, 0), fake.live);
    }
}
test "backend validates counts identity unsupported operations and zero capacity without consuming owner" {
    var fake: Fake = .{};
    var store = try resources.Store.init(t.allocator, .network, fake.provider(), 1);
    defer store.deinit();
    const owner = try store.acquire(try store.grant(), "");
    var zero: [0]u8 = .{};
    try t.expectEqual(resources.Read{ .length = 0, .eof = false }, try store.read(owner, &zero));
    try t.expectEqual(@as(usize, 0), try store.write(owner, ""));
    fake.invalid_count = true;
    try t.expectError(error.InvalidProvider, store.read(owner, &zero));
    try t.expectError(error.InvalidProvider, store.write(owner, ""));
    try t.expectEqual(@as(usize, 1), fake.live);
    const moved = try store.transfer(owner);
    const reads = fake.reads;
    const writes = fake.writes;
    try t.expectError(error.InvalidOwner, store.read(owner, &zero));
    try t.expectError(error.InvalidOwner, store.write(owner, ""));
    try t.expectEqual(reads, fake.reads);
    try t.expectEqual(writes, fake.writes);
    store.provider.read = null;
    store.provider.write = null;
    try t.expectError(error.Unavailable, store.read(moved, &zero));
    try t.expectError(error.Unavailable, store.write(moved, ""));
    try store.complete(moved);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "all read write result and reporting allocation failures unwind provider owners" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "source IO traps at every instruction boundary release or complete exactly once" {
    var c = try language.Compilation.init(t.allocator, "traps.my", source);
    defer c.deinit();
    var completed = false;
    for (1..300) |budget| {
        var fake: Fake = .{};
        const result = try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() }, .max_steps = budget });
        try t.expectEqual(@as(usize, 0), fake.live);
        try t.expect(fake.releases + fake.completions <= 1);
        if (result == .value) {
            completed = true;
            break;
        }
    }
    try t.expect(completed);
}
test "invalid provider progress is a host failure with resource cleanup" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", source);
    defer c.deinit();
    var fake: Fake = .{ .invalid_count = true };
    try t.expectError(error.InvalidProvider, c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } }));
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 1), fake.releases);
}

test "emission rejects forged resource IO metadata before provider callbacks" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", source);
    defer c.deinit();
    try c.emit();
    const instruction = try @import("instruction_test.zig").find(@constCast(c.code.?.functions[0].scope.instructions), .resource_io);
    const original = instruction.*;
    instruction.op.resource_io.owner = @fromBackingInt(std.math.maxInt(usize));
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    instruction.op.resource_io.output = .i64;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
}
