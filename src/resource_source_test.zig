//! Source-level resource ownership tests with fake providers that record acquisitions, cleanup order, and failures.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const resources = @import("external_resources.zig");
const declarations =
    \\resource File: filesystem
    \\
    \\
    \\result Open:
    \\    ok: File,
    \\    err: i64
    \\
    \\
    \\class Failure:
    \\    code: i64
    \\    resource: File
    \\
    \\
    \\result Finish:
    \\    err: Failure,
    \\    ok: bool
    \\
    \\
    \\result Status:
    \\    ok: bool,
    \\    err: i64
    \\
    \\
    \\
;
const Fake = struct {
    acquired: usize = 0,
    acquire_calls: usize = 0,
    live: usize = 0,
    complete_calls: usize = 0,
    released: usize = 0,
    fail_acquire_at: usize = std.math.maxInt(usize),
    acquire_error: external.CallError = error.Failed,
    fail_complete_count: usize = 0,
    complete_error: external.CallError = error.Failed,
    order: [16]u64 = @splat(0),
    fn acquire(context: *anyopaque, request: []const u8, _: resources.Permissions) external.CallError!u64 {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.acquire_calls += 1;
        if (self.acquire_calls == self.fail_acquire_at) return self.acquire_error;
        if (request.len != 0 and (request.len != 1 or request[0] != 42)) return error.Denied;
        self.acquired += 1;
        self.live += 1;
        return self.acquired;
    }
    fn complete(context: *anyopaque, _: u64) external.CallError!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.complete_calls += 1;
        if (self.fail_complete_count != 0) {
            self.fail_complete_count -= 1;
            return self.complete_error;
        }
        self.live -= 1;
    }
    fn release(context: *anyopaque, handle: u64) void {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.released < self.order.len) self.order[self.released] = handle;
        self.released += 1;
        self.live -= 1;
    }
    fn provider(self: *Fake) resources.Provider {
        return .{ .context = self, .acquire = acquire, .complete = complete, .release = release };
    }
};
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "resources.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const retry = declarations ++
    \\class Authority:
    \\    fs: filesystem_cap
    \\
    \\
    \\def open(auth: Authority) -> Open effects(filesystem):
    \\    request: [1]u8 = [42u8]
    \\    return acquire_resource[Open](auth.fs, request)
    \\
    \\
    \\def retry(file: File) -> Finish:
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            return Ok(done)
    \\        case Finish.err(failure):
    \\            return complete_resource[Finish](failure.resource)
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64 noalloc:
    \\    match open(Authority(fs=fs)):
    \\        case Open.ok(file):
    \\            match retry(file):
    \\                case Finish.ok(done):
    \\                    if done:
    \\                        return 7
    \\                    else:
    \\                        return 0
    \\                case Finish.err(failure):
    \\                    return failure.code
    \\        case Open.err(e):
    \\            return e
;
fn retryScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{ .fail_complete_count = 1 };
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "resources.my", retry);
    defer c.deinit();
    const result = try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } });
    try t.expectEqual(@as(i64, 7), result.value);
    try t.expectEqual(@as(usize, 2), fake.complete_calls);
    try t.expectEqual(@as(usize, 0), fake.released);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "COMPLETE_RESOURCE") != null);
    var discovery = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
}
test "source acquisition delegates authority and failed completion returns owned resource for retry" {
    try retryScenario(t.allocator);
}
const partial = declarations ++
    \\def work(fs: filesystem_cap) -> Status:
    \\    empty: [0]u8 = []
    \\    a = acquire_resource[Open](fs, empty)?
    \\    b = acquire_resource[Open](fs, empty)?
    \\    _ = a
    \\    _ = b
    \\    return Ok(True)
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64:
    \\    match work(fs):
    \\        case Status.ok(done):
    \\            _ = done
    \\            return 9
    \\        case Status.err(e):
    \\            return e
;
// spec: OWN-9
test "partial source acquisition propagates failure and releases acquired resources once" {
    var fake: Fake = .{ .fail_acquire_at = 2 };
    var c = try language.Compilation.init(t.allocator, "resources.my", partial);
    defer c.deinit();
    var stats: [2]resources.Statistics = undefined;
    try t.expectEqual(@as(i64, 3), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider(), .statistics = &stats } })).value);
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 1), fake.released);
    try t.expectEqual(@as(usize, 0), fake.complete_calls);
    try t.expectEqual(@as(u64, 1), stats[0].acquired);
    try t.expectEqual(stats[0].acquired, stats[0].released);
    try t.expectEqual(@as(usize, 0), stats[1].live);
}
test "completion errors release returned owner exactly once when caller chooses fallback" {
    for ([_]external.CallError{ error.Unavailable, error.Denied, error.Failed, error.OutOfMemory }, 1..) |err, code| {
        var fake: Fake = .{ .fail_complete_count = 3, .complete_error = err };
        var c = try language.Compilation.init(t.allocator, "resources.my", retry);
        defer c.deinit();
        const options: language.vm.Options = .{ .resources = .{ .filesystem = fake.provider() } };
        if (err == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, options));
        } else try t.expectEqual(@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, options)).value);
        try t.expectEqual(@as(usize, 0), fake.live);
        try t.expectEqual(@as(usize, 1), fake.released);
    }
}
test "ownExternal and source acquisition completion retry clean every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), retryScenario, .{});
}
const wrappers = declarations ++
    \\class Inner:
    \\    file: File
    \\
    \\
    \\class Pair:
    \\    first: Inner
    \\    second: File
    \\
    \\
    \\result PairResult:
    \\    ok: Pair,
    \\    err: i64
    \\
    \\
    \\def pair(fs: filesystem_cap) -> PairResult:
    \\    empty: [0]u8 = []
    \\    return Ok(Pair(first=Inner(file=acquire_resource[Open](fs, empty)?), second=acquire_resource[Open](fs, empty)?))
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64:
    \\    match pair(fs):
    \\        case PairResult.ok(value):
    \\            _ = value
    \\            return 0
    \\        case PairResult.err(e):
    \\            return e
;
test "nested resource wrappers release in reverse schema order and traps unwind every instruction" {
    var c = try language.Compilation.init(t.allocator, "wrappers.my", wrappers);
    defer c.deinit();
    var normal: Fake = .{};
    try t.expectEqual(@as(i64, 0), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = normal.provider() } })).value);
    try t.expectEqualSlices(u64, &.{ 2, 1 }, normal.order[0..2]);
    var completed = false;
    for (1..200) |budget| {
        var fake: Fake = .{};
        const result = try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() }, .max_steps = budget });
        try t.expectEqual(@as(usize, 0), fake.live);
        try t.expectEqual(fake.acquired, fake.released);
        if (result == .value) {
            completed = true;
            break;
        }
    }
    try t.expect(completed);
}
test "independent bytecode validation rejects suppressed cleanup effects and malformed resource results" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", retry);
    defer c.deinit();
    try c.emit();
    const functions = @constCast(c.code.?.functions);
    const effects = functions[1].policy.effects;
    functions[1].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    functions[1].policy.effects = effects;
    const instruction = try @import("instruction_test.zig").find(@constCast(functions[1].scope.instructions), .complete_resource);
    const original = instruction.*;
    instruction.op.complete_resource = .i64;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
}

test "resource acquisition identity and cleanup contracts survive exact duplicate discovery" {
    const source = declarations ++
        \\def a(fs: filesystem_cap) -> Open effects(filesystem):
        \\    request: [1]u8 = [42u8]
        \\    return acquire_resource[Open](fs, request)
        \\
        \\
        \\def b(dir: filesystem_cap) -> Open effects(filesystem):
        \\    request: [1]u8 = [42u8]
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\def c(dir: filesystem_cap) -> Open effects(filesystem):
        \\    request: [1]u8 = [43u8]
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(t.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try t.expectEqual(@as(usize, 1), analysis.groups.len);
    try t.expectEqual(@as(usize, 2), analysis.groups[0].members.len);
    try t.expect(compilation.code == null);
}
test "source frame traps release the resource moved through recursive calls" {
    var c = try language.Compilation.init(t.allocator, "recursive.my", declarations ++
        \\def recurse(file: File) -> i64:
        \\    return recurse(file)
        \\
        \\
        \\def main(fs: filesystem_cap) -> i64:
        \\    empty: [0]u8 = []
        \\    match acquire_resource[Open](fs, empty):
        \\        case Open.ok(file):
        \\            return recurse(file)
        \\        case Open.err(e):
        \\            return e
    );
    defer c.deinit();
    var fake: Fake = .{};
    const result = try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() }, .max_frames = 3 });
    try t.expect(result == .trap);
    try t.expectEqual(@as(usize, 1), fake.released);
    try t.expectEqual(@as(usize, 0), fake.live);
}

const generic_cleanup = declarations ++
    \\class Owned:
    \\    file: File
    \\    code: i64
    \\
    \\
    \\def forward[T](file: File) -> File effects(filesystem):
    \\    return file
    \\
    \\
    \\def drop[T](file: File) -> i64 effects(filesystem):
    \\    return 1
    \\
    \\
    \\def fields[T](value: Owned) -> i64 effects(filesystem):
    \\    _ = value
    \\    return 7
    \\
    \\
    \\def handle[T](r: Open) -> i64 effects(filesystem):
    \\    match r:
    \\        case Open.ok(file):
    \\            return fields[bool](Owned(file=forward[bool](file), code=7))
    \\        case Open.err(code):
    \\            return code
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64:
    \\    empty: [0]u8 = []
    \\    first = handle[bool](acquire_resource[Open](fs, empty))
    \\    match acquire_resource[Open](fs, empty):
    \\        case Open.ok(file):
    \\            return first + drop[bool](file)
    \\        case Open.err(code):
    \\            return code
;
fn genericCleanupScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "generic-cleanup.my", generic_cleanup);
    defer c.deinit();
    const outcome = try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } });
    try t.expectEqual(@as(i64, 8), outcome.value);
    try t.expectEqual(@as(usize, 2), fake.released);
    try t.expectEqual(@as(usize, 0), fake.complete_calls);
}
// spec: GENERIC-CLEANUP-1
test "generic owned resources clean up explicit and implicit drops under allocation failure" {
    try genericCleanupScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericCleanupScenario, .{});
}

const generic_retry = declarations ++
    \\def open[G](cap: filesystem_cap) -> Open effects(filesystem):
    \\    empty: [0]u8 = []
    \\    return acquire_resource[Open](cap, empty)
    \\
    \\
    \\def finish[G](file: File) -> Finish effects(filesystem):
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            return Ok(done)
    \\        case Finish.err(failure):
    \\            return complete_resource[Finish](failure.resource)
    \\
    \\
    \\def main(cap: filesystem_cap) -> i64:
    \\    match open[bool](cap):
    \\        case Open.ok(file):
    \\            match finish[bool](file):
    \\                case Finish.ok(_):
    \\                    return 7
    \\                case Finish.err(failure):
    \\                    return failure.code
    \\        case Open.err(e):
    \\            return e
;
fn genericRetryScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{ .fail_complete_count = 1 };
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "generic-retry.my", generic_retry);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 2), fake.complete_calls);
    try t.expectEqual(@as(usize, 0), fake.released);
}
test "generic resource acquisition and completion return ownership for retry under allocation failures" {
    try genericRetryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericRetryScenario, .{});
}
