//! Result-cache closure planning over fresh compiler-owned dependency manifests.
const std = @import("std");
const json = @import("qbe_build_value.zig");
const Sha = std.crypto.hash.sha2.Sha256;
/// Allocation failures or an incomplete/unrecognized semantic dependency manifest.
pub const Error = error{ OutOfMemory, InvalidManifest, UnknownFunction };
/// One entry's transitive semantic fingerprint; strings borrow the parsed manifest.
pub const Plan = struct {
    key: [64]u8,
    cacheable: bool,
    dependencies: []const []const u8,
    reasons: []const []const u8,
    /// Release the two result arrays before releasing the parsed manifest.
    pub fn deinit(self: Plan, allocator: std.mem.Allocator) void {
        allocator.free(self.dependencies);
        allocator.free(self.reasons);
    }
};

const Kind = enum { call, function_value, indirect, codec };
const Dependency = struct { symbol: []const u8, kind: Kind };
const Metadata = struct { implementation_hash: []const u8, dependencies: []const Dependency, cacheable: bool, reasons: []const []const u8 };
/// Compute a sorted transitive implementation closure, including cycles exactly once.
/// The caller supplies runtime/tool/input/settings fingerprints through context_key.
pub fn plan(allocator: std.mem.Allocator, manifest: std.json.Value, entry_symbol: []const u8, context_key: []const u8) Error!Plan {
    const units = json.array(json.get(manifest, "functions"));
    const abi = json.text(json.get(manifest, "abi"));
    if (units.len == 0 or abi.len == 0) return error.InvalidManifest;
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    defer index.deinit(allocator);
    for (units, 0..) |unit, i| {
        const symbol = json.text(json.get(unit, "symbol"));
        if (symbol.len == 0) return error.InvalidManifest;
        const entry = try index.getOrPut(allocator, symbol);
        if (entry.found_existing) return error.InvalidManifest;
        entry.value_ptr.* = i;
    }
    const entry = index.get(entry_symbol) orelse return error.UnknownFunction;
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(allocator);
    const seen = try allocator.alloc(bool, units.len);
    defer allocator.free(seen);
    @memset(seen, false);
    try queue.append(allocator, entry);
    seen[entry] = true;
    var closure: std.ArrayList([]const u8) = .empty;
    errdefer closure.deinit(allocator);
    var reasons: std.ArrayList([]const u8) = .empty;
    errdefer reasons.deinit(allocator);
    var cacheable = true;
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const unit = units[queue.items[cursor]];
        try closure.append(allocator, json.text(json.get(unit, "symbol")));
        const facts = json.get(unit, "test_dependencies");
        try validateFacts(facts);
        if (!json.boolean(json.get(facts, "cacheable"))) cacheable = false;
        for (json.array(json.get(facts, "reasons"))) |reason| try unique(allocator, &reasons, json.text(reason));
        for (json.array(json.get(facts, "dependencies"))) |dependency| {
            if (std.meta.stringToEnum(Kind, json.text(json.get(dependency, "kind"))) == null) return error.InvalidManifest;
            const next = index.get(json.text(json.get(dependency, "symbol"))) orelse return error.InvalidManifest;
            if (seen[next]) continue;
            seen[next] = true;
            try queue.append(allocator, next);
        }
    }
    std.mem.sort([]const u8, closure.items, {}, stringLess);
    std.mem.sort([]const u8, reasons.items, {}, stringLess);
    var hash = Sha.init(.{});
    part(&hash, "native-test-plan-v1");
    part(&hash, abi);
    part(&hash, context_key);
    part(&hash, entry_symbol);
    for (closure.items) |symbol| {
        part(&hash, symbol);
        part(&hash, json.text(json.get(json.get(units[index.get(symbol).?], "test_dependencies"), "implementation_hash")));
    }
    const dependencies = try closure.toOwnedSlice(allocator);
    errdefer allocator.free(dependencies);
    return .{ .key = std.fmt.bytesToHex(hash.finalResult(), .lower), .cacheable = cacheable, .dependencies = dependencies, .reasons = try reasons.toOwnedSlice(allocator) };
}
fn validateFacts(facts: std.json.Value) Error!void {
    const digest = json.text(json.get(facts, "implementation_hash"));
    if (digest.len != 64) return error.InvalidManifest;
    for (digest) |byte| if (!std.ascii.isHex(byte)) return error.InvalidManifest;
    if (json.get(facts, "cacheable") != .bool) return error.InvalidManifest;
    if (json.get(facts, "dependencies") != .array) return error.InvalidManifest;
    if (json.get(facts, "reasons") != .array) return error.InvalidManifest;
}
fn unique(allocator: std.mem.Allocator, values: *std.ArrayList([]const u8), value: []const u8) Error!void {
    for (values.items) |existing| if (std.mem.eql(u8, existing, value)) return;
    try values.append(allocator, value);
}
fn stringLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
fn part(hash: *Sha, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

const FixtureUnit = struct {
    symbol: []const u8,
    il: []const u8 = "ignored-by-planner",
    locations: []const u8 = "source coordinates excluded",
    test_dependencies: Metadata,
};
fn fixture(symbol: []const u8, body: u8, dependencies: []const Dependency) FixtureUnit {
    const bodies = [_][]const u8{ &(@as([64]u8, @splat('a'))), &(@as([64]u8, @splat('b'))) };
    return .{ .symbol = symbol, .test_dependencies = .{ .implementation_hash = bodies[body], .dependencies = dependencies, .cacheable = true, .reasons = &.{} } };
}
fn fixturePlan(allocator: std.mem.Allocator, units: []const FixtureUnit, entry: []const u8, context: []const u8) ![64]u8 {
    const bytes = try std.json.Stringify.valueAlloc(allocator, .{ .abi = "native-abi", .functions = units }, .{});
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const result = try plan(allocator, parsed.value, entry, context);
    defer result.deinit(allocator);
    return result.key;
}
// spec: NATIVE-TEST-2
test "plan follows transitive bodies through cycles without unrelated invalidation" {
    const a = std.testing.allocator;
    var units = [_]FixtureUnit{
        fixture("A", 0, &.{.{ .symbol = "helperA", .kind = .call }}),
        fixture("B", 0, &.{.{ .symbol = "helperB", .kind = .call }}),
        fixture("helperA", 0, &.{.{ .symbol = "A", .kind = .call }}),
        fixture("helperB", 0, &.{}),
    };
    const first_a = try fixturePlan(a, &units, "A", "runtime1");
    const first_b = try fixturePlan(a, &units, "B", "runtime1");
    units[2] = fixture("helperA", 1, units[2].test_dependencies.dependencies);
    try std.testing.expect(!std.mem.eql(u8, &first_a, &(try fixturePlan(a, &units, "A", "runtime1"))));
    try std.testing.expectEqualStrings(&first_b, &(try fixturePlan(a, &units, "B", "runtime1")));
    units[0].locations = "moved source lines";
    std.mem.reverse(FixtureUnit, &units);
    try std.testing.expectEqualStrings(&first_b, &(try fixturePlan(a, &units, "B", "runtime1")));
    try std.testing.expect(!std.mem.eql(u8, &first_b, &(try fixturePlan(a, &units, "B", "runtime2"))));
}
test "plan rejects InvalidManifest and UnknownFunction instead of reusing incomplete results" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.InvalidManifest, plan(a, .null, "A", "runtime"));
    var units = [_]FixtureUnit{fixture("A", 0, &.{.{ .symbol = "missing", .kind = .call }})};
    try std.testing.expectError(error.InvalidManifest, fixturePlan(a, &units, "A", "runtime"));
    try std.testing.expectError(error.UnknownFunction, fixturePlan(a, &units, "unknown", "runtime"));
    units[0].test_dependencies.dependencies = &.{};
    const duplicated = [_]FixtureUnit{ units[0], units[0] };
    try std.testing.expectError(error.InvalidManifest, fixturePlan(a, &duplicated, "A", "runtime"));
}
test "plan propagates external effects and conservative reasons transitively" {
    const a = std.testing.allocator;
    var units = [_]FixtureUnit{ fixture("A", 0, &.{.{ .symbol = "host", .kind = .indirect }}), fixture("host", 0, &.{}) };
    units[0].test_dependencies.reasons = &.{"conservative-indirect-target-set"};
    units[1].test_dependencies.cacheable = false;
    units[1].test_dependencies.reasons = &.{"host-call"};
    const bytes = try std.json.Stringify.valueAlloc(a, .{ .abi = "native-abi", .functions = units }, .{});
    defer a.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    defer parsed.deinit();
    const result = try plan(a, parsed.value, "A", "runtime");
    defer result.deinit(a);
    try std.testing.expect(!result.cacheable);
    try std.testing.expectEqual(@as(usize, 2), result.dependencies.len);
    try std.testing.expectEqual(@as(usize, 2), result.reasons.len);
}
test "plan allocation failures release every traversal buffer" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationPlan, .{});
}
fn allocationPlan(allocator: std.mem.Allocator) !void {
    const units = [_]FixtureUnit{ fixture("A", 0, &.{.{ .symbol = "B", .kind = .call }}), fixture("B", 1, &.{}) };
    _ = try fixturePlan(allocator, &units, "A", "runtime");
}
