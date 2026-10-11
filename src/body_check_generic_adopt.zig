//! Authenticate selected signatures against retained source/catalog authority.
//! No expression or statement checker is invoked by this adoption path.
const std = @import("std");
const typed = @import("typed.zig");
const value = @import("body_check_value.zig");
const logical = @import("parser_value.zig");
const instances = @import("generic_instances.zig");
const authority = @import("body_check_generic_validate.zig");
pub const Error = error{ ComponentProtocol, OutOfMemory };
fn same(left: instances.Key, right: instances.Key) bool {
    if (left.declaration != right.declaration or !std.mem.eql(typed.Type, left.arguments, right.arguments)) return false;
    for (left.arguments, 0..) |_, index| if (left.length(index) != right.length(index)) return false;
    return true;
}
fn encoded(a: std.mem.Allocator, item: anytype) Error![]u8 {
    return logical.encodeTreeProfile(a, @TypeOf(item), item, "SLKGAU01", .body) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ComponentProtocol,
    };
}
fn unchanged(a: std.mem.Allocator, before: []const u8, item: anytype) Error!void {
    const after = try encoded(a, item);
    defer a.free(after);
    if (!std.mem.eql(u8, before, after)) return error.ComponentProtocol;
}
fn authenticate(comptime Checker: type, checker: *Checker, input: value.Input, batch: value.Batch, plan: authority.Plan) Error!void {
    const diagnostic_count = checker.sink.items.items.len;
    defer checker.sink.items.shrinkRetainingCapacity(diagnostic_count);
    for (batch.functions, plan.keys, 0..) |function, key, index| {
        const raw = input.program.functions[@backingInt(key.declaration)];
        const id: typed.FunctionId = @fromBackingInt(index);
        if (function.signature.parameter_count != raw.signature.parameters.len or function.scope.locals.len < raw.signature.parameters.len) return error.ComponentProtocol;
        for (raw.signature.parameters, 0..) |parameter, position| {
            const expected = checker.functionType(id, parameter.ty) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.ComponentProtocol,
            };
            if (function.scope.locals[position].ty != expected) return error.ComponentProtocol;
        }
        var result = checker.functionType(id, raw.signature.return_type) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ComponentProtocol,
        };
        if (raw.signature.failure_type) |span| {
            const failure = checker.functionType(id, span) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.ComponentProtocol,
            };
            result = @import("frontend_failures.zig").resultType(&checker.catalog, checker.allocator, result, failure, raw.name, checker.sink) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.ComponentProtocol,
            };
        }
        if (result != function.signature.return_type) return error.ComponentProtocol;
    }
}
/// Recipes must already have been materialized and the complete batch validated.
/// Lookup caches may memoize retained facts; catalog definitions and nominal
/// graph/runtime identities must remain byte-identical during authentication.
pub fn restore(comptime Checker: type, checker: *Checker, input: value.Input, batch: value.Batch) Error!void {
    const a = checker.allocator;
    var expanded = input;
    expanded.catalog.records = checker.catalog.records;
    const plan = try authority.plan(a, expanded, batch);
    defer a.free(plan.keys);
    defer a.free(plan.ordinary);
    if (checker.ordinary_count != plan.ordinary_count or checker.instance_keys.items.len != plan.ordinary_count or checker.generic_registry.entries.items.len != 0) return error.ComponentProtocol;
    if (!std.mem.eql(?typed.FunctionId, checker.ordinary_ids, plan.ordinary)) return error.ComponentProtocol;
    for (checker.instance_keys.items, plan.keys[0..plan.ordinary_count]) |existing, selected| if (!same(existing, selected)) return error.ComponentProtocol;
    for (plan.keys[plan.ordinary_count..], plan.ordinary_count..) |key, id| {
        const ordinal = checker.generic_registry.intern(a, key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ComponentProtocol,
        };
        if (@backingInt(ordinal) + plan.ordinary_count != id) return error.ComponentProtocol;
        const owned = checker.generic_registry.get(ordinal) catch return error.ComponentProtocol;
        try checker.instance_keys.append(a, owned);
        // Selected bodies have no authenticated native specialization fingerprint.
        try checker.spec_fingerprints.append(a, null);
        try checker.spec_ranges.append(a, batch.ranges[id]);
    }
    if (checker.spec_ranges.items.len != batch.ranges.len or checker.spec_fingerprints.items.len != batch.functions.len) return error.ComponentProtocol;
    @memcpy(checker.spec_ranges.items, batch.ranges);
    const records = try encoded(a, @as([]const typed.Record, checker.catalog.records));
    defer a.free(records);
    const store = checker.catalog.templates.store orelse return error.ComponentProtocol;
    const graph = try encoded(a, store.graph.nodes.items);
    defer a.free(graph);
    const identities = try encoded(a, store.identities.items.items);
    defer a.free(identities);
    var names = try checker.catalog.names.clone(a);
    defer names.deinit(a);
    var by_type = try store.identities.by_type.clone(a);
    defer by_type.deinit(a);
    try authenticate(Checker, checker, expanded, batch, plan);
    try unchanged(a, records, @as([]const typed.Record, checker.catalog.records));
    try unchanged(a, graph, store.graph.nodes.items);
    try unchanged(a, identities, store.identities.items.items);
    if (names.count() != checker.catalog.names.count() or by_type.count() != store.identities.by_type.count()) return error.ComponentProtocol;
    var named = names.iterator();
    while (named.next()) |entry| if (checker.catalog.names.get(entry.key_ptr.*) != entry.value_ptr.*) return error.ComponentProtocol;
    var semantic = by_type.iterator();
    while (semantic.next()) |entry| if (store.identities.by_type.get(entry.key_ptr.*) != entry.value_ptr.*) return error.ComponentProtocol;
}

const SignatureChecker = struct {
    allocator: std.mem.Allocator,
    sink: *@import("diagnostic.zig").Sink,
    src: @import("source.zig").Source,
    parameters: []const @import("ast.zig").TypeParameter,
    key: instances.Key,
    catalog: @import("type_catalog.zig").Catalog = .{ .records = &.{}, .names = .empty },
    /// Resolve the test signature through the actual retained substitution path.
    pub fn functionType(self: *SignatureChecker, _: typed.FunctionId, span: @import("source.zig").Span) @import("diagnostic.zig").Error!typed.Type {
        return @import("generic_substitution.zig").resolve(self.allocator, &self.catalog, self.src, self.sink, .{
            .span = span,
            .parameters = self.parameters,
            .arguments = self.key.arguments,
            .lengths = self.key.lengths,
            .depth = 0,
        });
    }
};
// spec-case: GENERIC-INSTANCE-1
test "generic body signature authority rejects forged substituted parameter and result types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span: @import("source.zig").Span = .{ .start = 0, .end = 1 };
    const parameters = [_]@import("ast.zig").TypeParameter{.{ .name = span, .requirements = &.{} }};
    const key: instances.Key = .{ .declaration = @fromBackingInt(0), .arguments = &.{.i8}, .lengths = &.{null} };
    var sink: @import("diagnostic.zig").Sink = .{ .allocator = a };
    var checker: SignatureChecker = .{ .allocator = a, .sink = &sink, .src = try @import("source.zig").Source.init(a, "generic.my", "T"), .parameters = &parameters, .key = key };
    const raw = [_]@import("ast.zig").Function{.{ .name = span, .body = @fromBackingInt(0), .signature = .{
        .type_parameters = &parameters,
        .parameters = &.{.{ .name = span, .ty = span }},
        .return_type = span,
    } }};
    const input: value.Input = .{ .context = .{ .path = "generic.my", .source = "T", .trusted_intrinsics = false, .entry_required = false }, .program = .{ .nodes = .empty, .statements = .empty, .functions = &raw }, .modules = &.{} };
    var locals = [_]typed.Local{.{ .name = "value", .declaration = span, .ty = .i8, .mutable = false }};
    var functions = [_]typed.Function{.{ .id = @fromBackingInt(0), .name = "generic[i8]", .declaration = span, .scope = .{ .body = @fromBackingInt(0), .locals = &locals }, .signature = .{ .parameter_count = 1, .return_type = .i8 } }};
    const batch: value.Batch = .{ .nodes = &.{}, .statements = &.{}, .functions = &functions, .ranges = &.{} };
    var keys = [_]instances.Key{key};
    const plan: authority.Plan = .{ .keys = &keys, .ordinary = &.{}, .ordinary_count = 0 };
    try authenticate(SignatureChecker, &checker, input, batch, plan);
    functions[0].signature.return_type = .u8;
    try std.testing.expectError(error.ComponentProtocol, authenticate(SignatureChecker, &checker, input, batch, plan));
    functions[0].signature.return_type = .i8;
    locals[0].ty = .u8;
    try std.testing.expectError(error.ComponentProtocol, authenticate(SignatureChecker, &checker, input, batch, plan));
    try std.testing.expectEqual(@as(usize, 0), sink.items.items.len);
}
