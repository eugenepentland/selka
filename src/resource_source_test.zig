//! Source-level resource ownership tests with fake providers that record acquisitions, cleanup order, and failures.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const external = @import("external_capabilities.zig");
const resources = @import("external_resources.zig");
const declarations = "resource File: filesystem; result Open { ok: File, err: i64 } struct Failure { code: i64, resource: File } result Finish { err: Failure, ok: bool } result Status { ok: bool, err: i64 } ";
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
const retry = declarations ++ "struct Authority { fs: filesystem_cap } fn open(auth: Authority) -> Open " ++
    "effects(filesystem) { return acquire_resource<Open>(auth.fs, new [1]u8 [42u8]); } fn " ++
    "retry(file: File) -> Finish { match complete_resource<Finish>(file) { " ++
    "Finish.ok(done) => { return new Finish.ok(done); }, Finish.err(failure) => { if " ++
    "read_field(failure, code) == 3 { return complete_resource<Finish>(failure.resource); " ++
    "} else { return new Finish.err(failure); } } } } fn main(fs: filesystem_cap) -> i64 " ++
    "noalloc { match open(new Authority { fs: fs }) { Open.ok(file) => { match " ++
    "retry(file) { Finish.ok(done) => { if done { return 7; } else { return 0; } }, " ++
    "Finish.err(failure) => { return failure.code; } } }, Open.err(e) => { return e; } } }";
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
const partial = declarations ++ "fn work(fs: filesystem_cap) -> Status { let a = try acquire_resource<Open>(fs, new " ++
    "[0]u8 []); let b = try acquire_resource<Open>(fs, new [0]u8 []); discard a; discard " ++
    "b; return new Status.ok(true); } fn main(fs: filesystem_cap) -> i64 { match work(fs) " ++
    "{ Status.ok(done) => { discard done; return 9; }, Status.err(e) => { return e; } } }";
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
test "source quotas and provider denials are recoverable and authority is not ambient" {
    var c = try language.Compilation.init(t.allocator, "resources.my", partial);
    defer c.deinit();
    var fake: Fake = .{};
    try t.expectError(error.CapabilityUnavailable, c.execute(t.allocator));
    try t.expectEqual(@as(i64, 4), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider(), .max_live_per_kind = 1 } })).value);
    try t.expectEqual(@as(usize, 1), fake.acquire_calls);
    try t.expectEqual(@as(usize, 0), fake.live);
    var denied = try language.Compilation.init(t.allocator, "denied.my", declarations ++ "fn main(fs: filesystem_cap) -> i64 { match acquire_resource<Open>(fs, new [1]u8 " ++
        "[9u8]) { Open.ok(file) => { discard file; return 0; }, Open.err(e) => { return e; } }" ++
        " }");
    defer denied.deinit();
    try t.expectEqual(@as(i64, 2), (try denied.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 0), fake.live);
}
test "resource schema request kind and ownership mistakes fail at checking" {
    try reject("resource File: clock; fn main() -> i64 { return 0; }", "E_RESOURCE_KIND");
    try reject(declarations ++ "fn main() -> i64 { discard new File {}; return 0; }", "E_TYPE");
    try reject(declarations ++ "fn bad(f: File) -> i64 { discard f; discard f; return 0; } fn main() -> i64 { return 0; }", "E_OWNED_CONSUMED");
    try reject(declarations ++ "fn main(net: network_cap) -> i64 { acknowledge acquire_resource<Open>(net, new [0]u8 []); return 0; }", "E_TYPE");
    try reject(declarations ++ "fn main(fs: filesystem_cap) -> i64 { acknowledge acquire_resource<Open>(fs, new [1]i64 [1]); return 0; }", "E_RESOURCE_REQUEST");
    try reject(declarations ++ "fn bad(f: File) -> Status { return complete_resource<Status>(f); } fn main() -> i64 { return 0; }", "E_COMPLETION_RESULT");
    try reject("fn main(a: filesystem_cap, b: filesystem_cap) -> i64 { return 0; }", "E_MAIN");
}
test "implicit resource cleanup and ownership forwarding are included in noio and explicit bounds" {
    try reject(declarations ++ "fn cleanup(file: File) -> i64 noio { return 1; } fn main() -> i64 { return 0; }", "E_EFFECT_BOUND");
    try reject(declarations ++ "struct Wrap { file: File } fn forward(input: Wrap) -> Wrap effects() { return input; } fn main() -> i64 { return 0; }", "E_EFFECT_BOUND");
    try reject(declarations ++ "fn open(fs: filesystem_cap) -> Open { return acquire_resource<Open>(fs, new [0]u8 []); } fn main(fs: filesystem_cap) -> i64 noio { acknowledge open(fs); return 0; }", "E_EFFECT_BOUND");
    var c = try language.Compilation.init(t.allocator, "empty.my", declarations ++ "fn empty(a: [0]File) -> i64 effects() { discard a; return 0; } fn main() -> i64 { return empty(new [0]File []); }");
    defer c.deinit();
    try t.expectEqual(@as(i64, 0), (try c.execute(t.allocator)).value);
}
test "network and filesystem providers have separate entry authority and cleanup effects" {
    var fake: Fake = .{};
    var c = try language.Compilation.init(t.allocator, "network.my", declarations ++ "resource Socket: network; result Connected { ok: Socket, err: i64 } fn main(net: " ++
        "network_cap, fs: filesystem_cap) -> i64 effects(filesystem, network) { acknowledge " ++
        "acquire_resource<Connected>(net, new [0]u8 []); acknowledge " ++
        "acquire_resource<Open>(fs, new [0]u8 []); return 5; }");
    defer c.deinit();
    try t.expectError(error.CapabilityUnavailable, c.executeWithOptions(t.allocator, .{ .resources = .{ .network = fake.provider() } }));
    try t.expectEqual(@as(usize, 0), fake.acquire_calls);
    try t.expectEqual(@as(i64, 5), (try c.executeWithOptions(t.allocator, .{ .resources = .{ .network = fake.provider(), .filesystem = fake.provider() } })).value);
    try t.expectEqual(@as(usize, 2), fake.released);
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
const wrappers = declarations ++ "struct Inner { file: File } struct Pair { first: Inner, second: File } result " ++
    "PairResult { ok: Pair, err: i64 } fn pair(fs: filesystem_cap) -> PairResult { return " ++
    "new PairResult.ok(new Pair { first: new Inner { file: try acquire_resource<Open>(fs, " ++
    "new [0]u8 []) }, second: try acquire_resource<Open>(fs, new [0]u8 []) }); } fn " ++
    "main(fs: filesystem_cap) -> i64 { match pair(fs) { PairResult.ok(value) => { discard " ++
    "value; return 0; }, PairResult.err(e) => { return e; } } }";
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
test "source resource acquisition and completion loops use bounded live storage" {
    var c = try language.Compilation.init(t.allocator, "loop.my", declarations ++ "fn main(fs: filesystem_cap) -> i64 { let mut n = 0; while n < 10000 { match " ++
        "acquire_resource<Open>(fs, new [0]u8 []) { Open.ok(file) => { acknowledge " ++
        "complete_resource<Finish>(file); }, Open.err(e) => { return e; } } n += 1; } return " ++
        "n; }");
    defer c.deinit();
    try c.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
    defer limited.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limited.allocator(), .{ .resources = .{ .filesystem = fake.provider(), .max_live_per_kind = 1 } })).value);
    try t.expectEqual(@as(usize, 0), fake.live);
    try t.expectEqual(@as(usize, 0), fake.released);
    try t.expectEqual(@as(usize, 0), limited.live);
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
    const source = declarations ++ "fn a(fs: filesystem_cap) -> Open effects(filesystem) { return " ++
        "acquire_resource<Open>(fs, new [1]u8 [42u8]); } fn b(dir: filesystem_cap) -> Open " ++
        "effects(filesystem) { return acquire_resource<Open>(dir, new [1]u8 [42u8]); } fn " ++
        "c(dir: filesystem_cap) -> Open effects(filesystem) { return " ++
        "acquire_resource<Open>(dir, new [1]u8 [43u8]); } fn main() -> i64 { return 0; }";
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
    var c = try language.Compilation.init(t.allocator, "recursive.my", declarations ++ "fn recurse(file: File) -> i64 { return recurse(file); } fn main(fs: filesystem_cap) " ++
        "-> i64 { match acquire_resource<Open>(fs, new [0]u8 []) { Open.ok(file) => { return " ++
        "recurse(file); }, Open.err(e) => { return e; } } }");
    defer c.deinit();
    var fake: Fake = .{};
    const result = try c.executeWithOptions(t.allocator, .{ .resources = .{ .filesystem = fake.provider() }, .max_frames = 3 });
    try t.expect(result == .trap);
    try t.expectEqual(@as(usize, 1), fake.released);
    try t.expectEqual(@as(usize, 0), fake.live);
}

fn partialFieldResourceScenario(allocator: std.mem.Allocator) !void {
    const text = declarations ++ "struct Pair { first: File, second: File, code: i64 } fn work(fs: filesystem_cap) -> " ++
        "Status { let pair = new Pair { first: try acquire_resource<Open>(fs, new [0]u8 []), " ++
        "second: try acquire_resource<Open>(fs, new [0]u8 []), code: 7 }; discard " ++
        "take_field(pair, first); let spare = try acquire_resource<Open>(fs, new [0]u8 []); " ++
        "return new Status.ok(read_field(pair, code) == 7); } fn main(fs: filesystem_cap) -> " ++
        "i64 { match work(fs) { Status.ok(done) => { if done { return 7; } return 0; }, " ++
        "Status.err(code) => { return -code; } } }";
    var fake: Fake = .{};
    defer std.debug.assert(fake.live == 0);
    var c = try language.Compilation.init(allocator, "partial-resource.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 7), (try c.executeWithOptions(allocator, .{ .resources = .{ .filesystem = fake.provider(), .max_live_per_kind = 2 } })).value);
    try t.expectEqualSlices(u64, &.{ 1, 3, 2 }, fake.order[0..fake.released]);
    try t.expectEqual(@as(usize, 3), fake.acquired);
    try t.expectEqual(@as(usize, 0), fake.complete_calls);
}
test "partial record extraction releases external owners immediately and preserves remaining cleanup order" {
    try partialFieldResourceScenario(t.allocator);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), partialFieldResourceScenario, .{});
}
