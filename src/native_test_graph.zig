//! Durable reduced preparation graphs for native tests.
//!
//! Full `emit-project-qbe` output carries per-function QBE IL, source locations
//! and runtime data. Native test selection only needs the checked schema and the
//! per-function dependency facts that compute a result receipt key. This module
//! separates that reduced graph from emission: a warm, unchanged project loads
//! the graph without lowering or emitting, validates the project through the
//! shared compiler caches, and looks up result receipts normally. A miss falls
//! back to full emission and stores the reduced graph for later invocations.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
/// Graph cache IO, JSON and malformed compiler output failures.
pub const Error = fs.Error || std.Io.Writer.Error || error{InvalidGraph};
/// Bumped when the reduced graph wire shape changes so stale files are ignored.
pub const version = "native-test-graph-v1";
/// Key domain string; a change invalidates every stored graph.
const key_domain = "native-test-graph-key-v1";
/// Exactly the fields `native_test_plan.plan` and the runner schema need.
const ReducedExport = struct { name: []const u8 = "" };
const ReducedDependency = struct { symbol: []const u8 = "", kind: []const u8 = "" };
const ReducedFacts = struct {
    implementation_hash: []const u8 = "",
    dependencies: []const ReducedDependency = &.{},
    cacheable: bool = false,
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
        if (v.text(v.get(facts, "implementation_hash")).len != 64) return error.InvalidGraph;
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
                .implementation_hash = v.text(v.get(facts, "implementation_hash")),
                .dependencies = dependencies,
                .cacheable = v.boolean(v.get(facts, "cacheable")),
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
    const payload = v.get(wrapper.value, "payload");
    if (payload != .string) return null;
    const digest = fs.hash(context.allocator, payload.string) catch return null;
    if (!std.mem.eql(u8, digest, v.text(v.get(wrapper.value, "sha256")))) return null;
    const graph = std.json.parseFromSlice(std.json.Value, context.allocator, payload.string, .{ .allocate = .alloc_always }) catch return null;
    if (!std.mem.eql(u8, v.text(v.get(graph.value, "version")), version)) return null;
    return graph.value;
}

/// Publish a reduced graph atomically. Callers pass the exact `reduce` bytes.
pub fn store(context: fs.Context, directory: []const u8, key_bytes: []const u8, payload: []const u8) Error!void {
    try context.mkdir(directory);
    const wrapper = try std.json.Stringify.valueAlloc(context.allocator, .{
        .version = version,
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
    const full = try std.json.parseFromSlice(std.json.Value, a,
        \\{"abi":"mylang-qbe-native-v4","schema":"{\"functions\":[],\"types\":[]}","entry":"e","functions":[
        \\{"name":"m.main::test_x","symbol":"sym","export":{"name":"m.main::test_x"},
        \\ "test_dependencies":{"implementation_hash":"0000000000000000000000000000000000000000000000000000000000000000","dependencies":[{"symbol":"s","kind":"call"}],"cacheable":true,"reasons":[]}}]}
    , .{ .allocate = .alloc_always });
    const reduced = try reduce(a, full.value);
    try std.testing.expect(std.mem.indexOf(u8, reduced, "\"implementation_hash\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, reduced, "\"il\"") == null);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, reduced, .{ .allocate = .alloc_always });
    try std.testing.expectEqual(@as(usize, 1), v.array(v.get(parsed.value, "functions")).len);
    try std.testing.expectError(error.InvalidGraph, reduce(a, .null));
}
