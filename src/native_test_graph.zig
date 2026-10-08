//! Durable checked-facts graphs and their store envelope.
//!
//! `native-test-graph-v3` payloads carry the checked schema and per-function
//! semantic fingerprints/dependency edges without QBE IL or source locations.
//! A warm, unchanged project loads the graph without lowering or emitting,
//! validates the project through the shared compiler caches, and looks up result
//! receipts normally. `reduce` remains as a compatibility reducer for full
//! manifests; current producers write checked facts directly.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const build = @import("qbe_build.zig");
/// Graph cache IO, JSON and malformed compiler output failures.
pub const Error = fs.Error || std.Io.Writer.Error || error{InvalidGraph};
/// Bumped when the reduced graph wire shape changes so stale files are ignored.
pub const version = "native-test-graph-v3";
/// Key domain string; a change invalidates every stored graph.
const key_domain = "native-test-graph-key-v1";
/// Shared JSON key for the emitted implementation hash.
const hash_key = "implementation_hash";
/// Exactly the fields `native_test_plan.plan` and the runner schema need.
const ReducedExport = struct { name: []const u8 = "" };
const ReducedDependency = struct { symbol: []const u8 = "", kind: []const u8 = "" };
const ReducedFacts = struct {
    implementation_hash: []const u8 = "",
    dependencies: []const ReducedDependency = &.{},
    cacheable: bool = false,
    pure: bool = false,
    reasons: []const []const u8 = &.{},
};
const ReducedFunction = struct {
    name: []const u8 = "",
    symbol: []const u8 = "",
    @"export": ?ReducedExport = null,
    test_dependencies: ReducedFacts = .{},
};
const ReducedGraph = struct {
    version: []const u8 = version,
    abi: []const u8 = "",
    schema: []const u8 = "",
    entry: []const u8 = "",
    functions: []const ReducedFunction = &.{},
};

/// Every input that can change the reduced graph.
pub const KeyInputs = struct {
    compiler_identity: []const u8,
    zig_stamp: []const u8,
    qbe_stamp: []const u8,
    mode: []const u8,
    environment_hash: []const u8,
    source_identity: []const u8,
    provider_identity: []const u8,
};
/// Domain-separated key over every input that can change the reduced graph.
/// Source and provider identities are content hashes; tool stamps and the
/// compiler build identity pin the lowering/emission that produced the facts.
pub fn key(allocator: std.mem.Allocator, inputs: KeyInputs) Error![]const u8 {
    const bytes = try std.json.Stringify.valueAlloc(allocator, .{
        .domain = key_domain,
        .compiler = inputs.compiler_identity,
        .zig = inputs.zig_stamp,
        .qbe = inputs.qbe_stamp,
        .mode = inputs.mode,
        .environment = inputs.environment_hash,
        .source = inputs.source_identity,
        .provider = inputs.provider_identity,
    }, .{});
    defer allocator.free(bytes);
    return fs.hash(allocator, bytes);
}

/// Reduce one full `emit-project-qbe` manifest to the native-test graph shape.
/// The reduction copies only already-computed facts: it never lowers, emits or
/// reinterprets the checked program. `full` is a parsed manifest owned by the
/// caller's allocator; returned bytes are owned by the same allocator.
pub fn reduce(allocator: std.mem.Allocator, full: std.json.Value) Error![]u8 {
    const raw_functions = v.array(v.get(full, "functions"));
    if (raw_functions.len == 0) return error.InvalidGraph;
    const abi = v.text(v.get(full, "abi"));
    if (abi.len == 0) return error.InvalidGraph;
    if (v.get(full, "schema") != .string) return error.InvalidGraph;
    const functions = try allocator.alloc(ReducedFunction, raw_functions.len);
    for (raw_functions, 0..) |function, index| {
        const facts = v.get(function, "test_dependencies");
        if (facts != .object) return error.InvalidGraph;
        if (v.text(v.get(facts, hash_key)).len != 64) return error.InvalidGraph;
        const raw_dependencies = v.array(v.get(facts, "dependencies"));
        const dependencies = try allocator.alloc(ReducedDependency, raw_dependencies.len);
        for (raw_dependencies, 0..) |dependency, slot| {
            dependencies[slot] = .{
                .symbol = v.text(v.get(dependency, "symbol")),
                .kind = v.text(v.get(dependency, "kind")),
            };
        }
        const raw_reasons = v.array(v.get(facts, "reasons"));
        const reasons = try allocator.alloc([]const u8, raw_reasons.len);
        for (raw_reasons, 0..) |reason, slot| reasons[slot] = v.text(reason);
        const exported = v.get(function, "export");
        functions[index] = .{
            .name = v.text(v.get(function, "name")),
            .symbol = v.text(v.get(function, "symbol")),
            .@"export" = if (exported == .object) .{ .name = v.text(v.get(exported, "name")) } else null,
            .test_dependencies = .{
                .implementation_hash = v.text(v.get(facts, hash_key)),
                .dependencies = dependencies,
                .cacheable = v.boolean(v.get(facts, "cacheable")),
                .pure = v.boolean(v.get(facts, "pure")),
                .reasons = reasons,
            },
        };
    }
    return std.json.Stringify.valueAlloc(allocator, ReducedGraph{
        .abi = abi,
        .schema = v.text(v.get(full, "schema")),
        .entry = v.text(v.get(full, "entry")),
        .functions = functions,
    }, .{});
}

/// Read a stored reduced graph. Any missing, damaged or wrong-version entry is
/// a miss; a caller never admits an unverified file.
pub fn load(context: fs.Context, directory: []const u8, key_bytes: []const u8) ?std.json.Value {
    const path = pathFor(context, directory, key_bytes) catch return null;
    const bytes = context.read(path) catch return null;
    const wrapper = std.json.parseFromSlice(std.json.Value, context.allocator, bytes, .{ .allocate = .alloc_always }) catch return null;
    if (!std.mem.eql(u8, v.text(v.get(wrapper.value, "version")), version)) return null;
    // The filename is derived from the requested key, but a file can be moved
    // under another name. Bind the envelope to its requested input key so an
    // intact graph from another snapshot is a miss, not a stale success.
    if (!std.mem.eql(u8, v.text(v.get(wrapper.value, "key")), key_bytes)) return null;
    const payload = v.get(wrapper.value, "payload");
    if (payload != .string) return null;
    const digest = fs.hash(context.allocator, payload.string) catch return null;
    if (!std.mem.eql(u8, digest, v.text(v.get(wrapper.value, "sha256")))) return null;
    const graph = std.json.parseFromSlice(std.json.Value, context.allocator, payload.string, .{ .allocate = .alloc_always }) catch return null;
    if (!validGraph(graph.value)) return null;
    return graph.value;
}

/// Reject a structurally invalid reduced graph before its facts are trusted.
fn validGraph(value: std.json.Value) bool {
    if (value != .object) return false;
    if (!std.mem.eql(u8, v.text(v.get(value, "version")), version)) return false;
    if (v.text(v.get(value, "abi")).len == 0) return false;
    if (v.get(value, "schema") != .string) return false;
    if (v.get(value, "entry") != .string) return false;
    const functions = v.get(value, "functions");
    if (functions != .array) return false;
    for (functions.array.items) |function| {
        if (function != .object) return false;
        if (v.get(function, "name") != .string or v.get(function, "symbol") != .string) return false;
        const facts = v.get(function, "test_dependencies");
        if (facts != .object) return false;
        if (v.text(v.get(facts, hash_key)).len != 64) return false;
        if (v.get(facts, "dependencies") != .array or v.get(facts, "reasons") != .array) return false;
    }
    return true;
}

/// Publish a reduced graph atomically. Callers pass the exact `reduce` bytes.
pub fn store(context: fs.Context, directory: []const u8, key_bytes: []const u8, payload: []const u8) Error!void {
    try context.mkdir(directory);
    const wrapper = try std.json.Stringify.valueAlloc(context.allocator, .{
        .version = version,
        .key = key_bytes,
        .sha256 = try fs.hash(context.allocator, payload),
        .payload = payload,
    }, .{});
    try context.atomic(try pathFor(context, directory, key_bytes), wrapper);
}

fn pathFor(context: fs.Context, directory: []const u8, key_bytes: []const u8) Error![]const u8 {
    return std.fs.path.join(context.allocator, &.{ directory, try std.fmt.allocPrint(context.allocator, "{s}.json", .{key_bytes}) });
}

test "a reduced graph copies dependency facts and rejects malformed manifests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const full = try std.json.parseFromSlice(std.json.Value, a, "{\"abi\":\"" ++ build.native_abi ++ "\",\"schema\":\"{\\\"functions\\\":[],\\\"types\\\":[]}\",\"entry\":\"e\",\"functions\":[" ++
        "{\"name\":\"m.main::test_x\",\"symbol\":\"sym\",\"export\":{\"name\":\"m.main::test_x\"}," ++
        "\"test_dependencies\":{\"implementation_hash\":\"000000000000000000000000000000000000000000000000" ++
        "0000000000000000\",\"dependencies\":[{\"symbol\":\"s\",\"kind\":\"call\"}],\"cacheable\":true,\"reasons\":[]}}]}", .{ .allocate = .alloc_always });
    const reduced = try reduce(a, full.value);
    try std.testing.expect(std.mem.indexOf(u8, reduced, "\"implementation_hash\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, reduced, "\"il\"") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, reduced, .{ .allocate = .alloc_always });
    try std.testing.expectEqual(@as(usize, 1), v.array(v.get(parsed.value, "functions")).len);
    try std.testing.expectError(error.InvalidGraph, reduce(a, .null));
}

// spec: NATIVE-TEST-6
test "a stored reduced graph is bound to its requested input key" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const payload =
        "{\"version\":\"native-test-graph-v3\",\"abi\":\"a\",\"schema\":\"{}\",\"entry\":\"e\"," ++
        "\"functions\":[{\"name\":\"f\",\"symbol\":\"s\",\"export\":null," ++
        "\"test_dependencies\":{\"implementation_hash\":\"0000000000000000000000000000000000000000000000000000000000000000\"," ++
        "\"dependencies\":[],\"cacheable\":false,\"reasons\":[]}}]}";
    try store(context, root, "key-a", payload);
    try std.testing.expect(load(context, root, "key-a") != null);
    // A complete entry copied under another key must miss even when its checksum
    // and payload are intact.
    const copied = try context.read(try pathFor(context, root, "key-a"));
    try context.write(try pathFor(context, root, "key-b"), copied);
    try std.testing.expect(load(context, root, "key-b") == null);
}

// spec-case: NATIVE-TEST-6
test "resolved tool content stamps remain graph identity inputs" {
    const base: KeyInputs = .{
        .compiler_identity = "compiler",
        .zig_stamp = "zig-a",
        .qbe_stamp = "qbe-a",
        .mode = "Debug",
        .environment_hash = "compiler-env",
        .source_identity = "source",
        .provider_identity = "provider",
    };
    const first = try key(std.testing.allocator, base);
    defer std.testing.allocator.free(first);
    var changed = base;
    changed.qbe_stamp = "qbe-b";
    const second = try key(std.testing.allocator, changed);
    defer std.testing.allocator.free(second);
    try std.testing.expect(!std.mem.eql(u8, first, second));
}
