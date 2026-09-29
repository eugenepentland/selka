//! Result-cache closure planning over fresh compiler-owned dependency manifests.
const std = @import("std");
const json = @import("qbe_build_value.zig");
/// The plan key hash. BLAKE3, because a key frames the symbol and implementation
/// hash of every function in a test's closure, and the closures of a large
/// project's tests sum to megabytes per run, where `std`'s SHA-256 runs at
/// about 14 MB/s on some of the build machines' cores.
const Hash = std.crypto.hash.Blake3;
/// Plan key domain; `v2` moved the key to BLAKE3, so every older receipt misses once.
const key_version = "native-test-plan-v2";
/// Allocation failures or an incomplete/unrecognized semantic dependency manifest.
pub const Error = error{ OutOfMemory, InvalidManifest, UnknownFunction };
/// One entry's transitive semantic fingerprint; strings borrow the parsed manifest.
pub const Plan = struct {
    key: [64]u8,
    cacheable: bool,
    /// The entry test declares no capability parameter and no `mutates`
    /// footprint; combined with `cacheable` this is the opt-in replay condition.
    pure: bool,
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
const Metadata = struct { implementation_hash: []const u8, dependencies: []const Dependency, cacheable: bool, pure: bool = true, reasons: []const []const u8 };
/// Manifest key for a unit's checked dependency facts.
const facts_key = "test_dependencies";
/// Manifest key for one unit's dependency edges inside its facts.
const dependencies_key = "dependencies";
/// Manifest key for the list of compiled units.
const functions_key = @import("native_test_contracts.zig").functions_key;
/// One unit's facts, read once when its graph is indexed: its symbol and
/// implementation hash, its dependencies as unit positions, its reasons, and
/// whether all of that was well formed.
const Node = struct {
    symbol: []const u8,
    implementation: []const u8,
    edges: []const usize,
    reasons: []const std.json.Value,
    flags: packed struct { valid: bool, cacheable: bool, pure: bool },
};
/// Symbol positions and resolved facts of one parsed graph, built once so
/// planning each selected test costs that test's closure alone rather than a
/// pass over the whole graph or a JSON lookup per visited function.
pub const Index = struct {
    abi: []const u8,
    positions: std.StringHashMapUnmanaged(usize) = .empty,
    nodes: []const Node = &.{},

    /// Index every unit by its symbol and resolve its facts; an empty graph, a
    /// unit without a symbol or a repeated symbol is an invalid manifest. A
    /// unit whose facts are malformed is an invalid manifest only for a plan
    /// that reaches it.
    pub fn init(allocator: std.mem.Allocator, manifest: std.json.Value) Error!Index {
        const units = json.array(json.get(manifest, functions_key));
        const abi = json.text(json.get(manifest, "abi"));
        if (units.len == 0 or abi.len == 0) return error.InvalidManifest;
        var index: Index = .{ .abi = abi };
        errdefer index.deinit(allocator);
        try index.positions.ensureTotalCapacity(allocator, @intCast(units.len));
        for (units, 0..) |unit, position| {
            const symbol = json.text(json.get(unit, "symbol"));
            if (symbol.len == 0) return error.InvalidManifest;
            const entry = index.positions.getOrPutAssumeCapacity(symbol);
            if (entry.found_existing) return error.InvalidManifest;
            entry.value_ptr.* = position;
        }
        const nodes = try allocator.alloc(Node, units.len);
        @memset(nodes, .{ .symbol = "", .implementation = "", .edges = &.{}, .reasons = &.{}, .flags = .{ .valid = false, .cacheable = false, .pure = false } });
        index.nodes = nodes;
        for (units, nodes) |unit, *node| try index.resolve(allocator, unit, node);
        return index;
    }
    /// Read one unit's facts into its node, leaving it invalid when they are malformed.
    fn resolve(self: *const Index, allocator: std.mem.Allocator, unit: std.json.Value, node: *Node) Error!void {
        const facts = json.get(unit, facts_key);
        node.symbol = json.text(json.get(unit, "symbol"));
        validateFacts(facts) catch return;
        const dependencies = json.array(json.get(facts, "dependencies"));
        const edges = try allocator.alloc(usize, dependencies.len);
        node.edges = edges;
        for (dependencies, edges) |dependency, *edge| {
            if (std.meta.stringToEnum(Kind, json.text(json.get(dependency, "kind"))) == null) return;
            edge.* = self.positions.get(json.text(json.get(dependency, "symbol"))) orelse return;
        }
        node.implementation = json.text(json.get(facts, "implementation_hash"));
        node.reasons = json.array(json.get(facts, "reasons"));
        node.flags = .{ .valid = true, .cacheable = json.boolean(json.get(facts, "cacheable")), .pure = json.boolean(json.get(facts, "pure")) };
    }
    /// Release the symbol table and resolved facts; the strings still belong to the manifest.
    pub fn deinit(self: *Index, allocator: std.mem.Allocator) void {
        for (self.nodes) |node| allocator.free(node.edges);
        allocator.free(self.nodes);
        self.positions.deinit(allocator);
    }
    /// Compute one entry's sorted transitive implementation closure, including
    /// cycles exactly once, and its key. The caller supplies runtime, tool,
    /// input and settings fingerprints through `context_key`.
    pub fn plan(self: *const Index, allocator: std.mem.Allocator, entry_symbol: []const u8, context_key: []const u8) Error!Plan {
        const entry = self.positions.get(entry_symbol) orelse return error.UnknownFunction;
        var queue: std.ArrayList(usize) = .empty;
        defer queue.deinit(allocator);
        var seen = try std.DynamicBitSetUnmanaged.initEmpty(allocator, self.nodes.len);
        defer seen.deinit(allocator);
        try queue.append(allocator, entry);
        seen.set(entry);
        var reasons: std.ArrayList([]const u8) = .empty;
        errdefer reasons.deinit(allocator);
        var cacheable = true;
        var cursor: usize = 0;
        while (cursor < queue.items.len) : (cursor += 1) {
            const node = self.nodes[queue.items[cursor]];
            if (!node.flags.valid) return error.InvalidManifest;
            if (!node.flags.cacheable) cacheable = false;
            for (node.reasons) |reason| try unique(allocator, &reasons, json.text(reason));
            for (node.edges) |next| {
                if (seen.isSet(next)) continue;
                seen.set(next);
                try queue.append(allocator, next);
            }
        }
        std.mem.sort(usize, queue.items, self, symbolLess);
        std.mem.sort([]const u8, reasons.items, {}, stringLess);
        var hash = Hash.init(.{});
        part(&hash, key_version);
        part(&hash, self.abi);
        part(&hash, context_key);
        part(&hash, entry_symbol);
        const dependencies = try allocator.alloc([]const u8, queue.items.len);
        errdefer allocator.free(dependencies);
        for (queue.items, dependencies) |position, *symbol| {
            symbol.* = self.nodes[position].symbol;
            part(&hash, self.nodes[position].symbol);
            part(&hash, self.nodes[position].implementation);
        }
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        // Purity is a property of the test's own signature: a capability parameter
        // or a declared `mutates` footprint keeps it off the opt-in replay path even
        // though the whole closure may still be cacheable.
        return .{ .key = std.fmt.bytesToHex(digest, .lower), .cacheable = cacheable, .pure = self.nodes[entry].flags.pure, .dependencies = dependencies, .reasons = try reasons.toOwnedSlice(allocator) };
    }
    fn symbolLess(self: *const Index, left: usize, right: usize) bool {
        return std.mem.lessThan(u8, self.nodes[left].symbol, self.nodes[right].symbol);
    }
};
/// Plan one entry against a manifest indexed for this call alone. A caller
/// that plans many entries of one graph builds one `Index` instead.
pub fn plan(allocator: std.mem.Allocator, manifest: std.json.Value, entry_symbol: []const u8, context_key: []const u8) Error!Plan {
    var index = try Index.init(allocator, manifest);
    defer index.deinit(allocator);
    return index.plan(allocator, entry_symbol, context_key);
}
/// Every function symbol whose dependency closure reaches a changed function,
/// the changed functions included: one reverse walk over the manifest's
/// dependency edges from every unit whose qualified name `changes.reaches`.
/// A test is affected exactly when its own symbol is in the set, which is the
/// closure its receipt is keyed on, so no second call graph is built.
pub fn reaching(allocator: std.mem.Allocator, manifest: std.json.Value, changes: anytype) Error!std.StringHashMapUnmanaged(void) {
    const units = json.array(json.get(manifest, functions_key));
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    defer index.deinit(allocator);
    for (units, 0..) |unit, i| try index.put(allocator, json.text(json.get(unit, "symbol")), i);
    const callers = try allocator.alloc(std.ArrayList(usize), units.len);
    @memset(callers, .empty);
    defer {
        for (callers) |*list| list.deinit(allocator);
        allocator.free(callers);
    }
    for (units, 0..) |unit, caller| for (json.array(json.get(json.get(unit, facts_key), dependencies_key))) |dependency| {
        const callee = index.get(json.text(json.get(dependency, "symbol"))) orelse continue;
        try callers[callee].append(allocator, caller);
    };
    const seen = try allocator.alloc(bool, units.len);
    defer allocator.free(seen);
    @memset(seen, false);
    var queue: std.ArrayList(usize) = .empty;
    defer queue.deinit(allocator);
    for (units, 0..) |unit, i| if (changes.reaches(json.text(json.get(unit, "name")))) {
        seen[i] = true;
        try queue.append(allocator, i);
    };
    var reached: std.StringHashMapUnmanaged(void) = .empty;
    errdefer reached.deinit(allocator);
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const unit = queue.items[cursor];
        try reached.put(allocator, json.text(json.get(units[unit], "symbol")), {});
        for (callers[unit].items) |caller| {
            if (seen[caller]) continue;
            seen[caller] = true;
            try queue.append(allocator, caller);
        }
    }
    return reached;
}
fn validateFacts(facts: std.json.Value) Error!void {
    const digest = json.text(json.get(facts, "implementation_hash"));
    if (digest.len != 64) return error.InvalidManifest;
    for (digest) |byte| if (!std.ascii.isHex(byte)) return error.InvalidManifest;
    if (json.get(facts, "cacheable") != .bool) return error.InvalidManifest;
    if (json.get(facts, dependencies_key) != .array) return error.InvalidManifest;
    if (json.get(facts, "reasons") != .array) return error.InvalidManifest;
}
fn unique(allocator: std.mem.Allocator, values: *std.ArrayList([]const u8), value: []const u8) Error!void {
    for (values.items) |existing| if (std.mem.eql(u8, existing, value)) return;
    try values.append(allocator, value);
}
fn stringLess(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
fn part(hash: *Hash, bytes: []const u8) void {
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

// spec-case: PURE-SKIP-1
test "plan exposes entry signature purity and treats an absent field as impure" {
    const a = std.testing.allocator;
    var units = [_]FixtureUnit{fixture("A", 0, &.{})};
    const pure_bytes = try std.json.Stringify.valueAlloc(a, .{ .abi = "native-abi", .functions = units }, .{});
    defer a.free(pure_bytes);
    const pure_parsed = try std.json.parseFromSlice(std.json.Value, a, pure_bytes, .{});
    defer pure_parsed.deinit();
    const pure_plan = try plan(a, pure_parsed.value, "A", "runtime");
    defer pure_plan.deinit(a);
    try std.testing.expect(pure_plan.pure);

    units[0].test_dependencies.pure = false;
    const impure_bytes = try std.json.Stringify.valueAlloc(a, .{ .abi = "native-abi", .functions = units }, .{});
    defer a.free(impure_bytes);
    const impure_parsed = try std.json.parseFromSlice(std.json.Value, a, impure_bytes, .{});
    defer impure_parsed.deinit();
    const impure_plan = try plan(a, impure_parsed.value, "A", "runtime");
    defer impure_plan.deinit(a);
    try std.testing.expect(!impure_plan.pure);

    const legacy = try std.json.parseFromSlice(std.json.Value, a,
        \\{"abi":"native-abi","functions":[{"symbol":"A","test_dependencies":{"implementation_hash":"0000000000000000000000000000000000000000000000000000000000000000","dependencies":[],"cacheable":true,"reasons":[]}}]}
    , .{ .allocate = .alloc_always });
    defer legacy.deinit();
    const legacy_plan = try plan(a, legacy.value, "A", "runtime");
    defer legacy_plan.deinit(a);
    try std.testing.expect(!legacy_plan.pure);
}

/// Plan `entry` against a graph of `units` through one shared index.
fn indexedKey(allocator: std.mem.Allocator, index: *const Index, entry: []const u8) ![64]u8 {
    const result = try index.plan(allocator, entry, "runtime");
    defer result.deinit(allocator);
    return result.key;
}
// spec: NATIVE-TEST-PLAN-2
test "one index plans every entry of a graph as a fresh plan does and fails only the plans that reach a malformed unit" {
    const a = std.testing.allocator;
    const units = [_]FixtureUnit{
        fixture("A", 0, &.{.{ .symbol = "shared", .kind = .call }}),
        fixture("B", 1, &.{ .{ .symbol = "shared", .kind = .call }, .{ .symbol = "A", .kind = .function_value } }),
        fixture("shared", 0, &.{.{ .symbol = "B", .kind = .call }}),
        fixture("broken", 0, &.{.{ .symbol = "missing", .kind = .call }}),
        fixture("C", 1, &.{.{ .symbol = "broken", .kind = .call }}),
    };
    const bytes = try std.json.Stringify.valueAlloc(a, .{ .abi = "native-abi", .functions = units }, .{});
    defer a.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    defer parsed.deinit();
    var index = try Index.init(a, parsed.value);
    defer index.deinit(a);
    const planned = try index.plan(a, "B", "runtime");
    defer planned.deinit(a);
    // The same key and the same sorted closure a one-off plan computes.
    try std.testing.expectEqualStrings(&(try fixturePlan(a, &units, "B", "runtime")), &planned.key);
    try std.testing.expectEqual(@as(usize, 3), planned.dependencies.len);
    try std.testing.expectEqualStrings("A", planned.dependencies[0]);
    try std.testing.expectEqualStrings("shared", planned.dependencies[2]);
    try std.testing.expectEqualStrings(&(try fixturePlan(a, &units, "A", "runtime")), &(try indexedKey(a, &index, "A")));
    // A dangling edge is an invalid manifest only for the entry that reaches it.
    try std.testing.expectError(error.InvalidManifest, index.plan(a, "C", "runtime"));
    try std.testing.expectError(error.UnknownFunction, index.plan(a, "nobody", "runtime"));
}
test "index construction releases every table on each allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationIndex, .{});
}
fn allocationIndex(allocator: std.mem.Allocator) !void {
    const units = [_]FixtureUnit{ fixture("A", 0, &.{.{ .symbol = "B", .kind = .call }}), fixture("B", 1, &.{}) };
    const bytes = try std.json.Stringify.valueAlloc(allocator, .{ .abi = "native-abi", .functions = units }, .{});
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    var index = try Index.init(allocator, parsed.value);
    defer index.deinit(allocator);
    _ = try indexedKey(allocator, &index, "A");
}
