//! Environment capability contracts, bounded provider output and generic execution tests.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const env = @import("environment.zig");
const declarations = "struct Entry { present: bool, bytes: [4]u8, length: u64 } result Lookup { err: i64, ok: Entry } ";
const Fake = struct {
    calls: usize = 0,
    value: ?[]const u8 = "\x00\xff",
    failure: ?env.CallError = null,
    invalid_length: bool = false,
    fn get(context: *anyopaque, name: []const u8, output: []u8) env.CallError!?usize {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (!std.mem.eql(u8, name, "K")) return error.Denied;
        if (self.failure) |err| return err;
        @memset(output, 99); // Runtime must clear all unspecified tail/missing bytes.
        if (self.invalid_length) return output.len + 1;
        const value = self.value orelse return null;
        if (value.len > output.len) return error.NoCapacity;
        @memcpy(output[0..value.len], value);
        return value.len;
    }
    fn provider(self: *Fake) env.Provider {
        return .{ .context = self, .get = get };
    }
};
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "environment.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const forwarded = declarations ++ "struct Authority { env: environment_cap } fn lookup(auth: Authority) -> Lookup " ++
    "effects(environment) { return environment_get<Lookup>(auth.env, new [1]u8 [75u8]); } " ++
    "fn main(environment: environment_cap) -> i64 noio { match lookup(new Authority { " ++
    "env: environment }) { Lookup.ok(entry) => { if entry.present { return 10 + " ++
    "cast<i64>(entry.length) + cast<i64>(entry.bytes[3]); } else { return " ++
    "cast<i64>(entry.length) + cast<i64>(entry.bytes[0]); } }, Lookup.err(code) => { " ++
    "return -code; } } }";
fn scenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var c = try language.Compilation.init(allocator, "environment.my", forwarded);
    defer c.deinit();
    try t.expectEqual(@as(i64, 12), (try c.executeWithOptions(allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 1), fake.calls);
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "ENVIRONMENT_GET") != null);
    var duplicates = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer duplicates.deinit();
}
// spec: OWN-10
test "environment grants delegate explicitly and missing empty and present values remain distinct" {
    try scenario(t.allocator);
    var c = try language.Compilation.init(t.allocator, "environment.my", forwarded);
    defer c.deinit();
    var fake: Fake = .{ .value = null };
    try t.expectEqual(@as(i64, 0), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "";
    try t.expectEqual(@as(i64, 10), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "12345";
    try t.expectEqual(@as(i64, -4), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 3), fake.calls);
}
test "environment returns raw bytes and canonical zero padding" {
    var c = try language.Compilation.init(t.allocator, "bytes.my", declarations ++ "fn main(env: environment_cap) -> i64 { match environment_get<Lookup>(env, new [1]u8 " ++
        "[75u8]) { Lookup.ok(entry) => { return cast<i64>(entry.bytes[0]) + " ++
        "cast<i64>(entry.bytes[1]) + cast<i64>(entry.bytes[2]) + cast<i64>(entry.bytes[3]); }," ++
        " Lookup.err(code) => { return -code; } } }");
    defer c.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 255), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
}
test "absent environment provider denies entry before reads and unused authority performs no lookup" {
    var c = try language.Compilation.init(t.allocator, "environment.my", forwarded);
    defer c.deinit();
    try t.expectError(error.CapabilityUnavailable, c.execute(t.allocator));
    var unused = try language.Compilation.init(t.allocator, "unused.my", "fn main(env: environment_cap) -> i64 effects() { discard env; return 7; }");
    defer unused.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 7), (try unused.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 0), fake.calls);
}
test "environment authority names and result schemas are checked" {
    try reject(declarations ++ "fn main(c: clock_cap) -> i64 { acknowledge environment_get<Lookup>(c, new [1]u8 [75u8]); return 0; }", "E_TYPE");
    try reject(declarations ++ "fn main(env: environment_cap) -> i64 { acknowledge environment_get<Lookup>(env, new [1]i64 [75]); return 0; }", "E_ENVIRONMENT_NAME");
    try reject("result Lookup { ok: i64, err: i64 } fn main(env: environment_cap) -> i64 { acknowledge environment_get<Lookup>(env, new [0]u8 []); return 0; }", "E_ENVIRONMENT_RESULT");
    try reject("fn main(a: environment_cap, b: environment_cap) -> i64 { return 0; }", "E_MAIN");
    try reject("fn forge() -> environment_cap { return cast<environment_cap>(0); } fn main() -> i64 { return 0; }", "E_TYPE");
}
test "environment effect is transitive and independently validated while noalloc permits lookup" {
    try reject(declarations ++ "fn lookup(env: environment_cap) -> Lookup { return environment_get<Lookup>(env, new " ++
        "[1]u8 [75u8]); } fn main(env: environment_cap) -> i64 effects(clock, random) { " ++
        "acknowledge lookup(env); return 0; }", "E_EFFECT_BOUND");
    var c = try language.Compilation.init(t.allocator, "environment.my", declarations ++ "fn main(env: environment_cap) -> i64 noalloc { acknowledge environment_get<Lookup>(env, new [1]u8 [75u8]); return 0; }");
    defer c.deinit();
    var fake: Fake = .{};
    _ = try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() });
    @constCast(c.code.?.functions)[0].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
}
test "readValue maps environment provider failures while propagating host OOM and invalid counts" {
    var c = try language.Compilation.init(t.allocator, "environment.my", forwarded);
    defer c.deinit();
    for ([_]env.CallError{ error.Unavailable, error.Denied, error.Failed, error.NoCapacity, error.OutOfMemory }, 1..) |failure, code| {
        var fake: Fake = .{ .failure = failure };
        if (failure == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, .{ .environment = fake.provider() }));
        } else try t.expectEqual(-@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
        try t.expectEqual(@as(usize, 1), fake.calls);
    }
    var invalid: Fake = .{ .invalid_length = true };
    try t.expectError(error.InvalidProvider, c.executeWithOptions(t.allocator, .{ .environment = invalid.provider() }));
}
test "environment identities reject foreign and closed grants before provider invocation" {
    var fake: Fake = .{};
    var first = env.Runtime.init(1, fake.provider());
    var second = env.Runtime.init(2, fake.provider());
    const cap = try first.grant();
    var output: [4]u8 = undefined;
    try t.expectError(error.InvalidCapability, second.get(cap, "K", &output));
    first.close();
    try t.expectError(error.InvalidCapability, first.get(cap, "K", &output));
    try t.expectError(error.InvalidCapability, first.grant());
    try t.expectEqual(@as(usize, 0), fake.calls);
}
test "environment execution reporting and byte conversions release all failed allocations" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), scenario, .{});
}
test "environment lookup loops retain bounded live storage" {
    var c = try language.Compilation.init(t.allocator, "loop.my", declarations ++ "fn main(env: environment_cap) -> i64 { let mut n = 0; while n < 10000 { acknowledge environment_get<Lookup>(env, new [1]u8 [75u8]); n += 1; } return n; }");
    defer c.deinit();
    try c.emit();
    var limited: @import("test_support.zig").LimitedLiveAllocator = .{ .parent = t.allocator, .limit = 16 * 1024 };
    defer limited.deinit();
    var fake: Fake = .{};
    try t.expectEqual(@as(i64, 10000), (try c.executeWithOptions(limited.allocator(), .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 10000), fake.calls);
    try t.expectEqual(@as(usize, 0), limited.live);
}

test "zero capacity environment values distinguish absent empty and too large" {
    var c = try language.Compilation.init(t.allocator, "zero.my", "struct Entry { bytes: [0]u8, length: u64, present: bool } result Lookup { ok: Entry, " ++
        "err: i64 } fn main(env: environment_cap) -> i64 { match environment_get<Lookup>(env, " ++
        "new [1]u8 [75u8]) { Lookup.ok(entry) => { if entry.present { return 1; } else { " ++
        "return 0; } }, Lookup.err(code) => { return -code; } } }");
    defer c.deinit();
    var fake: Fake = .{ .value = null };
    try t.expectEqual(@as(i64, 0), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "";
    try t.expectEqual(@as(i64, 1), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
    fake.value = "x";
    try t.expectEqual(@as(i64, -4), (try c.executeWithOptions(t.allocator, .{ .environment = fake.provider() })).value);
}
test "environment failure propagation ends borrows and releases owned buffers" {
    const source = declarations ++ "buffer B: i64; result Open { ok: B, err: i64 } fn work(heap: allocator, env: " ++
        "environment_cap) -> Lookup { let b = try acquire_buffer<Open>(heap, 1); borrow " ++
        "b[0..0] as view { discard len_slice(view); return new Lookup.ok(try " ++
        "environment_get<Lookup>(env, new [1]u8 [75u8])); } } fn main(heap: allocator, env: " ++
        "environment_cap) -> i64 { match work(heap, env) { Lookup.ok(entry) => { return " ++
        "cast<i64>(entry.length); }, Lookup.err(code) => { return -code; } } }";
    var c = try language.Compilation.init(t.allocator, "cleanup.my", source);
    defer c.deinit();
    for ([_]env.CallError{ error.Unavailable, error.Denied, error.Failed, error.NoCapacity, error.OutOfMemory }, 1..) |failure, code| {
        var fake: Fake = .{ .failure = failure };
        var stats: @import("memory.zig").Statistics = .{};
        const options: language.vm.Options = .{
            .environment = fake.provider(),
            .memory = .{ .statistics = &stats },
        };
        if (failure == error.OutOfMemory) {
            try t.expectError(error.OutOfMemory, c.executeWithOptions(t.allocator, options));
        } else try t.expectEqual(-@as(i64, @intCast(code)), (try c.executeWithOptions(t.allocator, options)).value);
        try t.expectEqual(@as(u64, 1), stats.created);
        try t.expectEqual(stats.created, stats.released);
        try t.expectEqual(@as(usize, 0), stats.live_allocations);
    }
}
test "environment emission rejects malformed output shapes and VM checks capability operands" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", declarations ++ "fn main(env: environment_cap) -> i64 { acknowledge environment_get<Lookup>(env, new [1]u8 [75u8]); return 0; }");
    defer c.deinit();
    try c.emit();
    var fake: Fake = .{};
    for (@constCast(c.code.?.functions[0].scope.instructions)) |*instruction| {
        const original = instruction.*;
        if (instruction.op == .environment_get) {
            instruction.op.environment_get.output = .i64;
            try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
        } else if (instruction.op == .load_local) {
            instruction.op = .{ .push_i64 = 0 };
            try t.expectError(error.InternalError, language.vm.runWithOptions(t.allocator, c.code.?, .{ .environment = fake.provider() }));
        }
        instruction.* = original;
    }
    try t.expectEqual(@as(usize, 0), fake.calls);
}

const generic_environment = declarations ++
    "fn lookup<G:copy>(cap:environment_cap)->Lookup effects(environment){return environment_get<Lookup>(cap,new [1]u8[75u8]);}" ++
    "fn main(cap:environment_cap)->i64{match lookup::<bool>(cap){Lookup.ok(e)=>{return cast<i64>(e.length)+cast<i64>(e.bytes[0])+cast<i64>(e.bytes[1]);},Lookup.err(e)=>{return e;}}}";
fn genericEnvironmentScenario(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var c = try language.Compilation.init(allocator, "generic-environment.my", generic_environment);
    defer c.deinit();
    try t.expectEqual(@as(i64, 257), (try c.executeWithOptions(allocator, .{ .environment = fake.provider() })).value);
    try t.expectEqual(@as(usize, 1), fake.calls);
}
test "generic environment lookup preserves bounded bytes and callback allocation failures" {
    try genericEnvironmentScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericEnvironmentScenario, .{});
}
