//! Resource IO through slices tests for bounds, permission and result metadata, provider callbacks, and cleanup.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const resources = @import("external_resources.zig");
const external = @import("external_capabilities.zig");
const memory = @import("memory.zig");
const declarations = "resource File: filesystem; result Open { ok: File, err: i64 } struct Progress { " ++
    "length: u64, eof: bool } result Read { ok: Progress, err: i64 } result Written { ok: " ++
    "u64, err: i64 } result Status { ok: i64, err: i64 } ";
const Fake = struct {
    live: usize = 0,
    reads: usize = 0,
    writes: usize = 0,
    releases: usize = 0,
    input: [8]u8 = @splat(0),
    input_length: usize = 0,
    failure: ?external.CallError = null,
    fn acquire(context: *anyopaque, _: []const u8, _: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.live += 1;
        return 1;
    }
    fn read(context: *anyopaque, _: u64, output: []u8) external.CallError!resources.Read {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.reads += 1;
        @memset(output, 99);
        if (self.failure) |err| return err;
        const length = @min(2, output.len);
        for (output[0..length], 0..) |*byte, index| byte.* = @intCast(7 + index);
        return .{ .length = length, .eof = true };
    }
    fn write(context: *anyopaque, _: u64, input: []const u8) external.CallError!usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.writes += 1;
        if (self.failure) |err| return err;
        self.input_length = input.len;
        @memcpy(self.input[0..@min(input.len, self.input.len)], input[0..@min(input.len, self.input.len)]);
        return input.len;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.live -= 1;
    }
    fn release(context: *anyopaque, _: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.live -= 1;
        self.releases += 1;
    }
    fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .read = read, .write = write, .complete = complete, .release = release };
    }
};
const fixed = declarations ++ "fn work(fs: filesystem_cap) -> Status { let mut file = try acquire_resource<Open>(fs," ++
    " new [0]u8 []); let mut bytes = new [5]u8 [10u8, 11u8, 12u8, 13u8, 14u8]; let before " ++
    "= bytes; let mut count = 0u64; borrow mut bytes[1..4] as destination { let progress " ++
    "= try read_resource_slice<Read>(file, destination); count = progress.length; } " ++
    "borrow bytes[1..1u64 + count] as input { discard try " ++
    "write_resource_slice<Written>(file, input); } return new " ++
    "Status.ok(cast<i64>(bytes[0]) + cast<i64>(bytes[1]) + cast<i64>(bytes[2]) + " ++
    "cast<i64>(bytes[3]) + cast<i64>(bytes[4]) + cast<i64>(before[1]) + cast<i64>(count));" ++
    " } fn main(fs: filesystem_cap) -> i64 { match work(fs) { Status.ok(value) => { " ++
    "return value; }, Status.err(code) => { return -code; } } }";
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "slices.my", fixed);
    defer c.deinit();
    try t.expectEqual(@as(i64, 65), (try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqualSlices(u8, &.{ 7, 8 }, fake.input[0..fake.input_length]);
    try t.expectEqual(@as(usize, 1), fake.releases);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "RESOURCE_read_slice") != null);
    var discovery = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
}
test "resource slice IO updates only read prefix preserves snapshots and writes exact populated range" {
    try scenario(t.allocator);
}
const buffer = declarations ++ "buffer Bytes: u8; result Buffer { ok: Bytes, err: i64 } result Mutation { ok: bool, " ++
    "err: i64 } fn work(heap: allocator, fs: filesystem_cap) -> Status { let mut file = " ++
    "try acquire_resource<Open>(fs, new [0]u8 []); let mut bytes = try " ++
    "acquire_buffer<Buffer>(heap, 5); discard try resize_buffer<Mutation>(bytes, 5, 42u8);" ++
    " borrow mut bytes[1..4] as destination { acknowledge read_resource_slice<Read>(file, " ++
    "destination); } borrow bytes[1..3] as input { acknowledge " ++
    "write_resource_slice<Written>(file, input); } return new " ++
    "Status.ok(cast<i64>(read_buffer(bytes, 0)) + cast<i64>(read_buffer(bytes, 1)) + " ++
    "cast<i64>(read_buffer(bytes, 2)) + cast<i64>(read_buffer(bytes, 3)) + " ++
    "cast<i64>(read_buffer(bytes, 4))); } fn main(heap: allocator, fs: filesystem_cap) -> " ++
    "i64 { match work(heap, fs) { Status.ok(value) => { return value; }, Status.err(code) " ++
    "=> { return -code; } } }";
test "owned buffer slices use the same resource IO interface without changing capacity or untouched suffix" {
    var c = try language.Compilation.init(t.allocator, "buffer.my", buffer);
    defer c.deinit();
    var fake: Fake = .{};
    var stats: memory.Statistics = .{};
    try t.expectEqual(@as(i64, 141), (try c.executeWithOptions(t.allocator, .{
        .resources = .{ .filesystem = fake.provider() },
        .memory = .{ .statistics = &stats, .limits = .{ .max_allocations = 1 } },
    })).value);
    try t.expectEqualSlices(u8, &.{ 7, 8 }, fake.input[0..fake.input_length]);
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(stats.created, stats.released);
}
fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "resource slice checks enforce active byte slices and exclusive read destinations" {
    try reject(declarations ++ "fn f(input: File, destination: &[]u8) -> i64 { let mut file = input; acknowledge read_resource_slice<Read>(file, destination); return 0; } fn main() -> i64 { return 0; }", "E_REFERENCE_READ_ONLY");
    try reject(declarations ++ "fn f(input: File, destination: &mut []i64) -> i64 { let mut file = input; acknowledge read_resource_slice<Read>(file, destination); return 0; } fn main() -> i64 { return 0; }", "E_TYPE");
    try reject(declarations ++ "fn f(input: File) -> i64 { let mut file = input; acknowledge write_resource_slice<Written>(file, absent); return 0; } fn main() -> i64 { return 0; }", "E_REFERENCE_SCOPE");
    try reject(declarations ++ "fn f(input: File, destination: &mut []u8) -> i64 { let mut file = input; borrow mut " ++
        "destination[0..0] as child { acknowledge read_resource_slice<Read>(file, " ++
        "destination); } return 0; } fn main() -> i64 { return 0; }", "E_BORROW_SUSPENDED");
}
test "provider errors do not modify destination even when scratch output was written" {
    const text = declarations ++ "fn work(fs: filesystem_cap) -> Status { let mut file = try acquire_resource<Open>(fs," ++
        " new [0]u8 []); let mut bytes = new [3]u8 [1u8, 2u8, 3u8]; borrow mut bytes[0..3] as " ++
        "destination { acknowledge read_resource_slice<Read>(file, destination); } return new " ++
        "Status.ok(cast<i64>(bytes[0]) + cast<i64>(bytes[1]) + cast<i64>(bytes[2])); } fn " ++
        "main(fs: filesystem_cap) -> i64 { match work(fs) { Status.ok(value) => { return " ++
        "value; }, Status.err(code) => { return -code; } } }";
    var c = try language.Compilation.init(t.allocator, "failure.my", text);
    defer c.deinit();
    var fake: Fake = .{ .failure = error.Failed };
    try t.expectEqual(@as(i64, 6), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 1), fake.releases);
}
test "all slice preparation result and reporting allocation failures unwind owners and borrows" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "resource slice traps clean up every instruction boundary for fixed arrays and owned buffers" {
    for ([_][]const u8{ fixed, buffer }) |text| {
        var c = try language.Compilation.init(t.allocator, "traps.my", text);
        defer c.deinit();
        var budget: u64 = 1;
        while (budget < 300) : (budget += 1) {
            var fake: Fake = .{};
            const result = try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() }, .max_steps = budget });
            try t.expectEqual(@as(usize, 0), fake.live);
            if (result == .value) break;
        }
        try t.expect(budget < 300);
    }
}
test "slice staging rejects read-only suspended and invalid direct ranges before IO" {
    var store = try memory.Store.init(t.allocator);
    defer store.deinit();
    const owner = try store.create(.u8, &.{@import("value.zig").Value.number(.u8, 1)});
    const shared = try store.borrow(owner, 0, 1, .shared);
    const Prepared = @import("byte_slices.zig").Prepared;
    try t.expectError(error.ReadOnly, Prepared.init(t.allocator, &store, .{ .lease = shared, .start = 0, .length = 1, .direct = true }, true, &.{}));
    try t.expectError(error.Bounds, Prepared.init(t.allocator, &store, .{ .lease = shared, .start = 1, .length = 1, .direct = true }, false, &.{}));
    try store.end(shared);
    const parent = try store.borrow(owner, 0, 1, .exclusive);
    const child = try store.reborrow(parent, 0, 1, .exclusive);
    try t.expectError(error.BorrowSuspended, Prepared.init(t.allocator, &store, .{ .lease = parent, .start = 0, .length = 0, .direct = true }, true, &.{}));
    try store.end(child);
    try store.end(parent);
}

test "resource IO accepts returned narrowed views through reference parameters" {
    const text = declarations ++ "fn middle(values: &mut []u8) -> &mut []u8 from values { borrow mut " ++
        "values[1..len_slice(values) - 1u64] as selected { return selected; } } fn " ++
        "receive(fs: filesystem_cap, destination: &mut []u8) -> Read { let mut file = try " ++
        "acquire_resource<Open>(fs, new [0]u8 []); return read_resource_slice<Read>(file, " ++
        "destination); } fn main(fs: filesystem_cap) -> i64 { let mut bytes = new [5]u8 [1u8, " ++
        "2u8, 3u8, 4u8, 5u8]; borrow mut bytes[0..5] as all { borrow mut middle(all) as " ++
        "selected { acknowledge receive(fs, selected); } } return cast<i64>(bytes[0]) + " ++
        "cast<i64>(bytes[1]) + cast<i64>(bytes[2]) + cast<i64>(bytes[3]) + " ++
        "cast<i64>(bytes[4]); }";
    var c = try language.Compilation.init(t.allocator, "returned.my", text);
    defer c.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 25), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "empty resource IO slices retain explicit EOF without modifying surrounding data" {
    const text = declarations ++ "fn work(fs: filesystem_cap) -> Status { let mut file = try acquire_resource<Open>(fs," ++
        " new [0]u8 []); let mut bytes = new [3]u8 [1u8, 2u8, 3u8]; borrow mut bytes[2..2] as " ++
        "destination { let progress = try read_resource_slice<Read>(file, destination); if " ++
        "!progress.eof || progress.length != 0u64 { return new Status.err(99); } } borrow " ++
        "bytes[1..1] as input { let count = try write_resource_slice<Written>(file, input); " ++
        "if count != 0u64 { return new Status.err(98); } } return new " ++
        "Status.ok(cast<i64>(bytes[0]) + cast<i64>(bytes[1]) + cast<i64>(bytes[2])); } fn " ++
        "main(fs: filesystem_cap) -> i64 { match work(fs) { Status.ok(value) => { return " ++
        "value; }, Status.err(code) => { return -code; } } }";
    var c = try language.Compilation.init(t.allocator, "empty.my", text);
    defer c.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 6), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 1), fake.reads);
    try t.expectEqual(@as(usize, 1), fake.writes);
    try t.expectEqual(@as(usize, 0), fake.input_length);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "repeated resource slice IO stays within bounded live storage" {
    const text = declarations ++ "fn work(fs: filesystem_cap) -> Status { let mut file = try acquire_resource<Open>(fs," ++
        " new [0]u8 []); let mut bytes = new [5]u8 [0u8, 0u8, 0u8, 0u8, 0u8]; let mut n = 0; " ++
        "while n < 10000 { borrow mut bytes[1..4] as destination { acknowledge " ++
        "read_resource_slice<Read>(file, destination); } borrow bytes[1..3] as input { " ++
        "acknowledge write_resource_slice<Written>(file, input); } n += 1; } return new " ++
        "Status.ok(n); } fn main(fs: filesystem_cap) -> i64 { match work(fs) { " ++
        "Status.ok(value) => { return value; }, Status.err(code) => { return -code; } } }";
    var c = try language.Compilation.init(t.allocator, "loop.my", text);
    defer c.deinit();
    try c.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
    defer limited.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limited.allocator(), .{ .resources = .{ .filesystem = fake.provider(), .max_live_per_kind = 1 } })).value);
    try t.expectEqual(@as(usize, 10000), fake.reads);
    try t.expectEqual(@as(usize, 10000), fake.writes);
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 0), limited.live);
}
test "emission rejects resource slice reference and result metadata corruption" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", fixed);
    defer c.deinit();
    try c.emit();
    const instruction = try @import("instruction_test.zig").find(@constCast(c.code.?.functions[0].scope.instructions), .resource_io);
    const original = instruction.*;
    instruction.op.resource_io.reference = @fromBackingInt(std.math.maxInt(usize));
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    instruction.op.resource_io.input = .u8;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
}

test "arena execution preserves resource slice snapshots partial IO and external cleanup" {
    for ([_][]const u8{ fixed, buffer }, [_]i64{ 65, 141 }) |text, expected| {
        var c = try language.Compilation.init(t.allocator, "arena-io.my", text);
        defer c.deinit();
        var fake: Fake = .{};
        var stats: memory.Statistics = .{};
        try t.expectEqual(expected, (try c.executeWithOptions(t.allocator, .{
            .memory = .{ .backing = .arena, .statistics = &stats },
            .resources = .{ .filesystem = fake.provider() },
        })).value);
        try t.expectEqualSlices(u8, &.{ 7, 8 }, fake.input[0..fake.input_length]);
        try t.expectEqual(@as(usize, 0), fake.live);
        try t.expectEqual(@as(usize, 1), fake.releases);
        try t.expectEqual(stats.created, stats.released);
        try t.expectEqual(@as(usize, 0), stats.live_allocations);
    }
}

const generic_slice = declarations ++
    "fn transfer<G:copy>(input:File,view:&mut[]u8)->Status{let mut file=input;let read=try read_resource_slice<Read>(file," ++
    "view);let written=try write_resource_slice<Written>(file,view);return new Status.ok(cast<i64>(read.length)+cast<i64>(" ++
    "written));}" ++
    "fn main(cap:filesystem_cap)->i64{match acquire_resource<Open>(cap,new [0]u8[]){Open.ok(" ++
    "file)=>{let mut bytes=new [3]u8[0u8,0u8,0u8];borrow mut bytes[0..3] as view{match transfer::<bool>(file,view){Status.ok(" ++
    "n)=>{return n;},Status.err(e)=>{return e;}}}},Open.err(e)=>{return e;}}}";
fn genericSliceScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "generic-resource-slice.my", generic_slice);
    defer c.deinit();
    try t.expectEqual(@as(i64, 5), (try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 1), fake.reads);
    try t.expectEqual(@as(usize, 1), fake.writes);
    try t.expectEqualSlices(u8, &.{ 7, 8, 0 }, fake.input[0..fake.input_length]);
}
test "generic slice provider IO preserves exclusive views counts and cleanup under allocation failure" {
    try genericSliceScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericSliceScenario, .{});
}
