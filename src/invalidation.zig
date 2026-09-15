//! Wave-3 invalidation observability: compare two `project-dependencies-v1`
//! receipts stage by stage and explain which input invalidated each query.
//!
//! The `incremental` object is deliberately treated as opaque JSON.  Receipts
//! produced by an older compiler (v1 identities) and a newer one (v2) both
//! compare through the same extraction rules: unknown additions are ignored,
//! absent fields are tolerated, and a missing or unreadable baseline degrades
//! to "everything missed" instead of failing the command that asked for the
//! explanation.
const std = @import("std");

/// Failure modes of the comparison layer.  A bad `current` receipt is the only
/// input that is allowed to fail the caller; a bad baseline never does.
pub const Error = error{ OutOfMemory, InvalidCurrent };

// Receipt field names shared by fingerprints, first-changed reports and
// toolchain extraction.  Keeping them here avoids ambiguous repeated literals.
const compiler_sha256_field = "compiler_sha256";
const architecture_field = "architecture";
const os_field = "os";
const abi_field = "abi";
const zig_version_field = "zig_version";
const optimize_field = "optimize";
const runtime_abi_field = "runtime_abi";
const target_field = "target";
const identity_field = "identity";
const function_kind = "function";
const specializations_field = "specializations";
const fragments_field = "fragments";
const compiler_label = "compiler";
const module_label = "module:";
const module_prefix = "module:{s}";

/// The nine query stages named in the Wave-3 plan, in canonical report order.
pub const Stage = enum {
    load_source,
    lex_parse,
    collect_declarations,
    resolve_interface,
    check_body,
    instantiate_specialization,
    lower_function,
    emit_fragment,
    link,
};

/// Stable display name for one stage; the enum tag is the contract.
pub fn stageName(stage: Stage) []const u8 {
    return @tagName(stage);
}

/// Whether a query was satisfied by the baseline or had to miss.
pub const Status = enum { hit, miss };

/// One stage's outcome.  `key` is a canonical shortened digest of the query
/// input; `first_changed` is owned only on a miss.
pub const Query = struct {
    stage: Stage,
    status: Status,
    key: []const u8,
    first_changed: ?[]const u8 = null,
};

/// Complete result of comparing a baseline receipt with the current receipt.
pub const Explanation = struct {
    queries: []const Query,
    hits: usize,
    misses: usize,

    /// Free every string and slice allocated by `explain`.
    pub fn deinit(self: Explanation, allocator: std.mem.Allocator) void {
        for (self.queries) |query| {
            allocator.free(query.key);
            if (query.first_changed) |name| allocator.free(name);
        }
        allocator.free(self.queries);
    }
};

/// Parse and compare two complete receipt documents.
///
/// `previous == null` makes every stage miss with `first_changed` equal to
/// `"no-baseline"`; an unparsable baseline makes every stage miss with
/// `"corrupt-baseline"`.  Only an unparsable `current` returns an error.
pub fn explain(allocator: std.mem.Allocator, previous: ?[]const u8, current: []const u8) Error!Explanation {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const current_value = std.json.parseFromSliceLeaky(std.json.Value, arena, current, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidCurrent,
    };

    if (previous == null) return allMiss(allocator, "no-baseline");

    const previous_value = std.json.parseFromSliceLeaky(std.json.Value, arena, previous.?, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return allMiss(allocator, "corrupt-baseline"),
    };

    const stages = std.meta.tags(Stage);
    const queries = try allocator.alloc(Query, stages.len);
    var filled: usize = 0;
    var hits: usize = 0;
    var misses: usize = 0;
    errdefer {
        for (queries[0..filled]) |query| {
            allocator.free(query.key);
            if (query.first_changed) |name| allocator.free(name);
        }
        allocator.free(queries);
    }

    for (stages, 0..) |stage, index| {
        const outcome = try compareStage(arena, stage, previous_value, current_value);
        const key = try allocator.dupe(u8, outcome.key);
        errdefer allocator.free(key);
        const first_changed = if (outcome.first_changed) |name| try allocator.dupe(u8, name) else null;
        if (outcome.status == .hit) {
            hits += 1;
        } else {
            misses += 1;
        }
        queries[index] = .{ .stage = stage, .status = outcome.status, .key = key, .first_changed = first_changed };
        filled = index + 1;
    }

    return .{ .queries = queries, .hits = hits, .misses = misses };
}

/// Render one `invalidation-report-v1` JSON object (no trailing newline).
pub fn render(allocator: std.mem.Allocator, explanation: Explanation) Error![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "invalidation-report-v1",
        .hits = explanation.hits,
        .misses = explanation.misses,
        .queries = explanation.queries,
    }, .{ .emit_null_optional_fields = false });
}

fn allMiss(allocator: std.mem.Allocator, reason: []const u8) Error!Explanation {
    const stages = std.meta.tags(Stage);
    const queries = try allocator.alloc(Query, stages.len);
    var filled: usize = 0;
    errdefer {
        for (queries[0..filled]) |query| {
            allocator.free(query.key);
            if (query.first_changed) |name| allocator.free(name);
        }
        allocator.free(queries);
    }
    for (stages, 0..) |stage, index| {
        const key = try allocator.dupe(u8, stageName(stage));
        errdefer allocator.free(key);
        const first_changed = try allocator.dupe(u8, reason);
        queries[index] = .{ .stage = stage, .status = .miss, .key = key, .first_changed = first_changed };
        filled = index + 1;
    }
    return .{ .queries = queries, .hits = 0, .misses = stages.len };
}

const Outcome = struct { status: Status, key: []const u8, first_changed: ?[]const u8 };
const Fingerprint = struct { key: []const u8, present: bool };
const Component = struct { name: []const u8, value: []const u8 };

fn compareStage(arena: std.mem.Allocator, stage: Stage, previous: std.json.Value, current: std.json.Value) !Outcome {
    return switch (stage) {
        .load_source => compareWith(arena, previous, current, loadSourceFingerprint, loadSourceFirstChanged),
        .lex_parse => compareWith(arena, previous, current, lexParseFingerprint, lexParseFirstChanged),
        .collect_declarations => compareWith(arena, previous, current, collectDeclarationsFingerprint, collectDeclarationsFirstChanged),
        .resolve_interface => compareWith(arena, previous, current, resolveInterfaceFingerprint, resolveInterfaceFirstChanged),
        .check_body => compareWith(arena, previous, current, checkBodyFingerprint, checkBodyFirstChanged),
        .instantiate_specialization => compareWith(arena, previous, current, specializationFingerprint, specializationFirstChanged),
        .lower_function => compareWith(arena, previous, current, lowerFunctionFingerprint, lowerFunctionFirstChanged),
        .emit_fragment => compareWith(arena, previous, current, fragmentFingerprint, fragmentFirstChanged),
        .link => compareWith(arena, previous, current, linkFingerprint, linkFirstChanged),
    };
}

fn compareWith(
    arena: std.mem.Allocator,
    previous: std.json.Value,
    current: std.json.Value,
    comptime fingerprint: anytype,
    comptime firstChanged: anytype,
) !Outcome {
    const prior = try fingerprint(arena, previous);
    const next = try fingerprint(arena, current);
    if (!prior.present and !next.present) return .{ .status = .hit, .key = "", .first_changed = null };
    if (prior.present and next.present and std.mem.eql(u8, prior.key, next.key)) return .{ .status = .hit, .key = next.key, .first_changed = null };
    if (!prior.present or !next.present) return .{ .status = .miss, .key = next.key, .first_changed = "absent" };
    const reason = try firstChanged(arena, previous, current);
    return .{ .status = .miss, .key = next.key, .first_changed = reason };
}

const FingerprintBuilder = struct {
    hash: std.crypto.hash.sha2.Sha256,
    present: bool = false,

    fn init() FingerprintBuilder {
        return .{ .hash = std.crypto.hash.sha2.Sha256.init(.{}) };
    }
    fn markPresent(self: *FingerprintBuilder) void {
        self.present = true;
    }
    fn field(self: *FingerprintBuilder, tag: []const u8, value: []const u8) void {
        updateField(&self.hash, tag, value);
    }
    fn finish(self: *FingerprintBuilder, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        if (!self.present) return "";
        var digest: [32]u8 = undefined;
        self.hash.final(&digest);
        return std.fmt.allocPrint(arena, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
    }
};

fn updateField(hash: *std.crypto.hash.sha2.Sha256, tag: []const u8, value: []const u8) void {
    hash.update(tag);
    hash.update(&.{0});
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, @intCast(value.len), .little);
    hash.update(&length);
    hash.update(value);
}

fn componentLess(_: void, a: Component, b: Component) bool {
    if (!std.mem.eql(u8, a.name, b.name)) return std.mem.lessThan(u8, a.name, b.name);
    return std.mem.lessThan(u8, a.value, b.value);
}

fn sortComponents(components: []Component) void {
    std.mem.sort(Component, components, {}, componentLess);
}

fn firstChangedComponent(previous: []const Component, current: []const Component) ?[]const u8 {
    var left: usize = 0;
    var right: usize = 0;
    while (left < previous.len and right < current.len) {
        const a = previous[left];
        const b = current[right];
        if (!std.mem.eql(u8, a.name, b.name)) {
            return if (std.mem.lessThan(u8, a.name, b.name)) a.name else b.name;
        }
        if (!std.mem.eql(u8, a.value, b.value)) return a.name;
        left += 1;
        right += 1;
    }
    if (left < previous.len) return previous[left].name;
    if (right < current.len) return current[right].name;
    return null;
}

fn member(value: std.json.Value, name: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(name),
        else => null,
    };
}

fn objectMember(object: std.json.ObjectMap, name: []const u8) ?std.json.Value {
    return object.get(name);
}

fn objectOf(value: ?std.json.Value) ?std.json.ObjectMap {
    const inner = value orelse return null;
    return switch (inner) {
        .object => |object| object,
        else => null,
    };
}

fn stringOf(value: ?std.json.Value) ?[]const u8 {
    const inner = value orelse return null;
    return switch (inner) {
        .string => |text| text,
        else => null,
    };
}

fn arrayOf(value: ?std.json.Value) []const std.json.Value {
    const inner = value orelse return &.{};
    return switch (inner) {
        .array => |array| array.items,
        else => &.{},
    };
}

fn implementationOf(root: std.json.Value) ?std.json.ObjectMap {
    return objectOf(member(root, "implementation"));
}

fn incrementalOf(root: std.json.Value) ?std.json.ObjectMap {
    return objectOf(member(root, "incremental"));
}

fn modulesOf(root: std.json.Value) []const std.json.Value {
    const incremental = incrementalOf(root) orelse return &.{};
    return arrayOf(objectMember(incremental, "modules"));
}

fn scalarText(arena: std.mem.Allocator, value: std.json.Value) std.mem.Allocator.Error![]const u8 {
    return switch (value) {
        .string => |text| text,
        .integer => |number| try std.fmt.allocPrint(arena, "{d}", .{number}),
        .float => |number| try std.fmt.allocPrint(arena, "{d}", .{number}),
        .bool => |flag| if (flag) "true" else "false",
        .null => "",
        .number_string => |text| text,
        .array, .object => try std.json.Stringify.valueAlloc(arena, value, .{}),
    };
}

fn scalarTextOrEmpty(arena: std.mem.Allocator, value: ?std.json.Value) std.mem.Allocator.Error![]const u8 {
    const inner = value orelse return "";
    return scalarText(arena, inner);
}

fn elementName(arena: std.mem.Allocator, value: std.json.Value) std.mem.Allocator.Error![]const u8 {
    switch (value) {
        .string => |text| return text,
        .object => |object| {
            if (object.get("name")) |name| switch (name) {
                .string => |text| return text,
                else => {},
            };
        },
        else => {},
    }
    const rendered = try std.json.Stringify.valueAlloc(arena, value, .{});
    return rendered;
}

fn inputShaComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    const inputs = arrayOf(member(root, "inputs"));
    const components = try arena.alloc(Component, inputs.len);
    for (inputs, 0..) |input, index| {
        components[index] = .{
            .name = stringOf(member(input, "module")) orelse "",
            .value = stringOf(member(input, "sha256")) orelse "",
        };
    }
    sortComponents(components);
    return components;
}

fn inputPathComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    const inputs = arrayOf(member(root, "inputs"));
    const components = try arena.alloc(Component, inputs.len);
    for (inputs, 0..) |input, index| {
        const path = stringOf(member(input, "path")) orelse "";
        const sha = stringOf(member(input, "sha256")) orelse "";
        components[index] = .{
            .name = stringOf(member(input, "module")) orelse "",
            .value = try std.fmt.allocPrint(arena, "{s}\x1f{s}", .{ path, sha }),
        };
    }
    sortComponents(components);
    return components;
}

fn moduleComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    const modules = modulesOf(root);
    const components = try arena.alloc(Component, modules.len);
    for (modules, 0..) |module, index| {
        components[index] = .{
            .name = stringOf(member(module, "name")) orelse "",
            .value = stringOf(member(module, identity_field)) orelse "",
        };
    }
    sortComponents(components);
    return components;
}

fn bodyComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    var components: std.ArrayList(Component) = .empty;
    for (modulesOf(root)) |module| {
        const module_name = stringOf(member(module, "name")) orelse "";
        for (arrayOf(member(module, "declarations"))) |declaration| {
            const body = member(declaration, "body_sha256") orelse continue;
            switch (body) {
                .null => continue,
                else => {},
            }
            const declaration_name = stringOf(member(declaration, "name")) orelse "";
            try components.append(arena, .{
                .name = try std.fmt.allocPrint(arena, "{s}::{s}", .{ module_name, declaration_name }),
                .value = try scalarText(arena, body),
            });
        }
    }
    const slice = try components.toOwnedSlice(arena);
    sortComponents(slice);
    return slice;
}

fn functionComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    var components: std.ArrayList(Component) = .empty;
    for (modulesOf(root)) |module| {
        const module_name = stringOf(member(module, "name")) orelse "";
        for (arrayOf(member(module, "declarations"))) |declaration| {
            const kind = stringOf(member(declaration, "kind")) orelse "";
            if (!std.mem.eql(u8, kind, function_kind)) continue;
            try components.append(arena, .{
                .name = stringOf(member(declaration, "name")) orelse "",
                .value = try std.fmt.allocPrint(arena, "{s}\x1f{s}", .{
                    module_name,
                    stringOf(member(declaration, identity_field)) orelse "",
                }),
            });
        }
    }
    const slice = try components.toOwnedSlice(arena);
    sortComponents(slice);
    return slice;
}

fn namedArrayComponents(arena: std.mem.Allocator, root: std.json.Value, comptime field_name: []const u8) std.mem.Allocator.Error![]const Component {
    const incremental = incrementalOf(root) orelse return &.{};
    const values = arrayOf(objectMember(incremental, field_name));
    var components: std.ArrayList(Component) = .empty;
    for (values) |value| {
        try components.append(arena, .{
            .name = try elementName(arena, value),
            .value = try std.json.Stringify.valueAlloc(arena, value, .{}),
        });
    }
    const slice = try components.toOwnedSlice(arena);
    sortComponents(slice);
    return slice;
}

fn loadSourceFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    if (implementationOf(root)) |implementation| {
        builder.markPresent();
        builder.field(compiler_sha256_field, try scalarTextOrEmpty(arena, objectMember(implementation, compiler_sha256_field)));
        builder.field(architecture_field, try scalarTextOrEmpty(arena, objectMember(implementation, architecture_field)));
        builder.field(os_field, try scalarTextOrEmpty(arena, objectMember(implementation, os_field)));
        builder.field(abi_field, try scalarTextOrEmpty(arena, objectMember(implementation, abi_field)));
    }
    const components = try inputShaComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("module", component.name);
        builder.field("sha256", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn loadSourceFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    if (!try sameCompilerIdentity(arena, previous, current)) return compiler_label;
    const changed = firstChangedComponent(try inputShaComponents(arena, previous), try inputShaComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return compiler_label;
}

fn lexParseFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try inputPathComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("module", component.name);
        builder.field("path_sha", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn lexParseFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try inputPathComponents(arena, previous), try inputPathComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return module_label;
}

fn collectDeclarationsFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try moduleComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("module", component.name);
        builder.field(identity_field, component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn collectDeclarationsFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try moduleComponents(arena, previous), try moduleComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return module_label;
}

fn resolveInterfaceFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    if (incrementalOf(root)) |incremental| {
        if (objectMember(incremental, "project_interface_sha256")) |value| {
            builder.markPresent();
            builder.field("interface", try scalarText(arena, value));
        }
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn resolveInterfaceFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    _ = arena;
    _ = previous;
    _ = current;
    return "interface";
}

fn checkBodyFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try bodyComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("declaration", component.name);
        builder.field("body", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn checkBodyFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try bodyComponents(arena, previous), try bodyComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return module_label;
}

fn specializationFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try namedArrayComponents(arena, root, specializations_field);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("specialization", component.name);
        builder.field("value", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn specializationFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try namedArrayComponents(arena, previous, specializations_field), try namedArrayComponents(arena, current, specializations_field));
    if (changed) |name| return name;
    return "specialization";
}

fn lowerFunctionFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try functionComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field(function_kind, component.name);
        builder.field(identity_field, component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn lowerFunctionFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try functionComponents(arena, previous), try functionComponents(arena, current));
    if (changed) |name| return name;
    return function_kind;
}

fn fragmentFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try namedArrayComponents(arena, root, fragments_field);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("fragment", component.name);
        builder.field("value", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn fragmentFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try namedArrayComponents(arena, previous, fragments_field), try namedArrayComponents(arena, current, fragments_field));
    if (changed) |name| return name;
    return "fragment";
}

const LinkField = struct { present: bool, text: []const u8 };

fn linkField(arena: std.mem.Allocator, root: std.json.Value, comptime name: []const u8) std.mem.Allocator.Error!LinkField {
    if (member(root, name)) |value| {
        switch (value) {
            .null => {},
            else => return .{ .present = true, .text = try scalarText(arena, value) },
        }
    }
    if (incrementalOf(root)) |incremental| {
        if (objectMember(incremental, name)) |value| {
            switch (value) {
                .null => {},
                else => return .{ .present = true, .text = try scalarText(arena, value) },
            }
        }
    }
    return .{ .present = false, .text = "" };
}

fn linkFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    if (implementationOf(root)) |implementation| {
        builder.markPresent();
        builder.field(compiler_sha256_field, try scalarTextOrEmpty(arena, objectMember(implementation, compiler_sha256_field)));
        builder.field(zig_version_field, try scalarTextOrEmpty(arena, objectMember(implementation, zig_version_field)));
        builder.field(architecture_field, try scalarTextOrEmpty(arena, objectMember(implementation, architecture_field)));
        builder.field(os_field, try scalarTextOrEmpty(arena, objectMember(implementation, os_field)));
        builder.field(abi_field, try scalarTextOrEmpty(arena, objectMember(implementation, abi_field)));
        builder.field(optimize_field, try scalarTextOrEmpty(arena, objectMember(implementation, optimize_field)));
    }
    const runtime_abi = try linkField(arena, root, runtime_abi_field);
    const target = try linkField(arena, root, target_field);
    if (runtime_abi.present or target.present) builder.markPresent();
    builder.field(runtime_abi_field, runtime_abi.text);
    builder.field(target_field, target.text);
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn linkFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const previous_implementation = implementationOf(previous);
    const current_implementation = implementationOf(current);
    const previous_compiler = try scalarTextOrEmpty(arena, if (previous_implementation) |implementation| objectMember(implementation, compiler_sha256_field) else null);
    const current_compiler = try scalarTextOrEmpty(arena, if (current_implementation) |implementation| objectMember(implementation, compiler_sha256_field) else null);
    if (!std.mem.eql(u8, previous_compiler, current_compiler)) return compiler_label;

    const previous_runtime = try linkField(arena, previous, runtime_abi_field);
    const current_runtime = try linkField(arena, current, runtime_abi_field);
    if (!std.mem.eql(u8, previous_runtime.text, current_runtime.text)) return "runtime-abi";

    const previous_target = try linkField(arena, previous, target_field);
    const current_target = try linkField(arena, current, target_field);
    if (!std.mem.eql(u8, previous_target.text, current_target.text)) return target_field;

    return "toolchain";
}

fn sameCompilerIdentity(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error!bool {
    const previous_implementation = implementationOf(previous);
    const current_implementation = implementationOf(current);
    inline for (.{ compiler_sha256_field, architecture_field, os_field, abi_field }) |name| {
        const prior = try scalarTextOrEmpty(arena, if (previous_implementation) |implementation| objectMember(implementation, name) else null);
        const next = try scalarTextOrEmpty(arena, if (current_implementation) |implementation| objectMember(implementation, name) else null);
        if (!std.mem.eql(u8, prior, next)) return false;
    }
    return true;
}
