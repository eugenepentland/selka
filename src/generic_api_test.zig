//! Checked public template schemas preserve symbolic contracts and private boundaries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const File = @import("embedded_project.zig").File;
const library =
    \\
    \\
    \\public record Box[T]:
    \\    value: T
    \\
    \\
    \\public result Answer[T]:
    \\    ok: T,
    \\    err: i64
    \\
    \\
    \\public func echo[T: equality](x: FixedArray[T, 2]) -> FixedArray[T, 2] effects():
    \\    return x
    \\
    \\
    \\func hidden[T](x: T) -> T:
    \\    return x
;
const entry =
    \\import lib as api
    \\
    \\
    \\public func run(x: i64) -> i64 effects():
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
const Files = struct {
    library: []const u8 = library,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, &.{
            File{ .path = "main.my", .bytes = entry },
            File{ .path = "lib.my", .bytes = self.library },
        }, path, limit);
    }
};
fn inspect(allocator: std.mem.Allocator, library_source: []const u8) ![]u8 {
    var files: Files = .{ .library = library_source };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    return language.schema_report.render(allocator, &compilation, .{
        .compiler_sha256 = @splat(42),
        .zig_version = "test",
        .architecture = "x86_64",
        .os = "linux",
        .abi = "gnu",
        .optimize = "Debug",
    });
}
fn scenario(allocator: std.mem.Allocator) !void {
    const bytes = try inspect(allocator, library);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const schema = parsed.value.object.get("schema").?.object;
    const templates = schema.get("generic_templates").?.array.items;
    try t.expectEqual(@as(usize, 3), templates.len);
    try t.expectEqualStrings("lib::Answer", templates[0].object.get("name").?.string);
    try t.expectEqualStrings("lib::Box", templates[1].object.get("name").?.string);
    const echo = templates[2].object;
    const contract = echo.get("contract").?.object;
    const signature = contract.get("signature").?.object;
    try t.expectEqualStrings("lib::echo", echo.get("name").?.string);
    try t.expect(!contract.get("callable").?.bool);
    try t.expect(contract.get("requires_explicit_instantiation").?.bool);
    try t.expectEqualStrings("FixedArray[T, 2]", signature.get("result").?.string);
    try t.expectEqualStrings("equality", contract.get("type_parameters").?.array.items[0].object.get("requirements").?.array.items[0].string);
    try t.expectEqual(@as(usize, 0), signature.get("declared_effects").?.array.items.len);
    try t.expectEqualStrings("lib.my", echo.get("source").?.object.get("path").?.string);
    try t.expectEqual(@as(usize, 64), echo.get("source").?.object.get("sha256").?.string.len);
    try t.expectEqual(@as(usize, 0), schema.get("exports").?.array.items.len);
    const functions = schema.get("functions").?.array.items;
    try t.expectEqual(@as(usize, 1), functions.len);
    try t.expectEqualStrings("main::run", functions[0].object.get("name").?.string);
}
// spec: GENERIC-API-1
test "public generic schema separates checked templates from calls and releases allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
test "public generic identities survive whitespace while source receipts change" {
    const a = try inspect(t.allocator, library);
    defer t.allocator.free(a);
    const b = try inspect(t.allocator, "\n" ++ library);
    defer t.allocator.free(b);
    const first = try std.json.parseFromSlice(std.json.Value, t.allocator, a, .{});
    defer first.deinit();
    const second = try std.json.parseFromSlice(std.json.Value, t.allocator, b, .{});
    defer second.deinit();
    try t.expect(!std.mem.eql(u8, first.value.object.get("source_sha256").?.string, second.value.object.get("source_sha256").?.string));
    const left = first.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    const right = second.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    for (left, right) |before, after| {
        try t.expectEqualStrings(before.object.get("name").?.string, after.object.get("name").?.string);
        try t.expectEqual(before.object.get("source").?.object.get("line").?.integer + 1, after.object.get("source").?.object.get("line").?.integer);
    }
}
test "public generic schema refuses invalid uncalled bodies" {
    try t.expectError(error.SourceError, inspect(t.allocator,
        \\
        \\
        \\public func bad[T](x: T) -> bool:
        \\    return x == x
    ));
}

test "public generic schemas retain structural field operation and codec constraints" {
    const bytes = try inspect(t.allocator,
        \\
        \\
        \\public func field[T: copy + field(value: i64)](x: T) -> i64 effects():
        \\    return x.value
        \\
        \\
        \\public func action[T: copy + op(score(value: T) -> i64 effects())](x: T) -> i64 effects():
        \\    return T.score(x)
        \\
        \\
        \\public func coded[T: copy + codec](x: T) -> T effects():
        \\    return x
    );
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const templates = parsed.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    const action = templates[0].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    const operation = action.get("operation_requirements").?.array.items[0].object;
    try t.expectEqualStrings("score", operation.get("name").?.string);
    try t.expectEqualStrings("i64", operation.get("result").?.string);
    try t.expectEqual(@as(usize, 0), operation.get("declared_effects").?.array.items.len);
    const coded = templates[1].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("codec", coded.get("requirements").?.array.items[1].string);
    const field = templates[2].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("value", field.get("field_requirements").?.array.items[0].object.get("name").?.string);
    try t.expectError(error.SourceError, inspect(t.allocator,
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\
        \\
        \\public func f[T: copy + field(value: Secret)](x: T) -> i64:
        \\    return 0
    ));
}

const named_contracts =
    \\
    \\
    \\public constraint Prices[Provider] = copy + op(price(policy: Provider, subtotal: i64) -> i64 effects())
    \\
    \\
    \\public constraint HasValue[T] = copy + field(value: i64)
    \\
    \\
    \\constraint Hidden[H] = copy + op(secret(item: H) -> i64 effects())
;
const named_library =
    \\import contracts
    \\
    \\
    \\public func total[P: contracts.Prices](policy: P, subtotal: i64) -> i64 effects():
    \\    return P.price(policy, subtotal)
    \\
    \\
    \\public func value_of[T: contracts.HasValue](item: T) -> i64 effects():
    \\    return item.value
;
const named_entry =
    \\import lib as api
    \\
    \\
    \\public func run(x: i64) -> i64 effects():
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
const NamedFiles = struct {
    contracts: []const u8,
    library: []const u8 = named_library,
    types: []const u8 = "",
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *NamedFiles = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, &.{
            File{ .path = "main.my", .bytes = named_entry },
            File{ .path = "lib.my", .bytes = self.library },
            File{ .path = "contracts.my", .bytes = self.contracts },
            File{ .path = "types.my", .bytes = self.types },
        }, path, limit);
    }
};
fn inspectNamed(allocator: std.mem.Allocator, contracts_source: []const u8) ![]u8 {
    var files: NamedFiles = .{ .contracts = contracts_source };
    return inspectNamedFiles(allocator, &files);
}
fn inspectNamedFiles(allocator: std.mem.Allocator, files: *NamedFiles) ![]u8 {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = NamedFiles.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    return language.schema_report.render(allocator, &compilation, .{
        .compiler_sha256 = @splat(42),
        .zig_version = "test",
        .architecture = "x86_64",
        .os = "linux",
        .abi = "gnu",
        .optimize = "Debug",
    });
}
// spec-case: GENERIC-API-1
test "public schema publishes exported constraints and expands named bounds without leaking private ones" {
    const bytes = try inspectNamed(t.allocator, named_contracts);
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const schema = parsed.value.object.get("schema").?.object;
    try t.expectEqualStrings("generic-templates-v2", schema.get("generic_templates_version").?.string);
    const templates = schema.get("generic_templates").?.array.items;
    try t.expectEqual(@as(usize, 4), templates.len);

    // Exported constraint: distinct non-callable kind with its own expanded operation.
    const has_value = templates[0].object;
    try t.expectEqualStrings("contracts::HasValue", has_value.get("name").?.string);
    try t.expectEqualStrings("constraint", has_value.get("kind").?.string);
    try t.expect(!has_value.get("contract").?.object.get("callable").?.bool);
    const has_value_expanded = has_value.get("contract").?.object.get("constraint").?.object.get("expanded").?.object;
    try t.expectEqualStrings("value", has_value_expanded.get("field_requirements").?.array.items[0].object.get("name").?.string);
    try t.expectEqualStrings("i64", has_value_expanded.get("field_requirements").?.array.items[0].object.get("type").?.string);

    const prices = templates[1].object;
    try t.expectEqualStrings("contracts::Prices", prices.get("name").?.string);
    try t.expectEqualStrings("constraint", prices.get("kind").?.string);
    const constraint = prices.get("contract").?.object.get("constraint").?.object;
    try t.expectEqualStrings("Provider", constraint.get("subject").?.string);
    const expanded = constraint.get("expanded").?.object;
    try t.expectEqualStrings("copy", expanded.get("requirements").?.array.items[0].string);
    const price = expanded.get("operation_requirements").?.array.items[0].object;
    try t.expectEqualStrings("price", price.get("name").?.string);
    // The declaration's own subject spelling is retained in its template.
    try t.expectEqualStrings("Provider", price.get("parameters").?.array.items[0].object.get("type").?.string);
    try t.expectEqualStrings("i64", price.get("result").?.string);

    const total = templates[2].object;
    try t.expectEqualStrings("lib::total", total.get("name").?.string);
    try t.expectEqualStrings("function", total.get("kind").?.string);
    const parameter = total.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("copy", parameter.get("requirements").?.array.items[0].string);
    const top_operation = parameter.get("operation_requirements").?.array.items[0].object;
    try t.expectEqualStrings("price", top_operation.get("name").?.string);
    // The consuming parameter spelling substitutes for the bound's subject.
    try t.expectEqualStrings("P", top_operation.get("parameters").?.array.items[0].object.get("type").?.string);
    const named = parameter.get("named_requirements").?.array.items;
    try t.expectEqual(@as(usize, 1), named.len);
    try t.expectEqualStrings("contracts.Prices", named[0].object.get("name").?.string);
    try t.expectEqualStrings("contracts", named[0].object.get("module").?.string);
    const bound = named[0].object.get("expanded").?.object;
    try t.expectEqualStrings("copy", bound.get("requirements").?.array.items[0].string);
    try t.expectEqualStrings("price", bound.get("operation_requirements").?.array.items[0].object.get("name").?.string);
    try t.expectEqualStrings("P", bound.get("operation_requirements").?.array.items[0].object.get("parameters").?.array.items[0].object.get("type").?.string);

    // Field-bound generic exposes the expanded field promise too.
    const value_of = templates[3].object;
    try t.expectEqualStrings("lib::value_of", value_of.get("name").?.string);
    const value_parameter = value_of.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("value", value_parameter.get("field_requirements").?.array.items[0].object.get("name").?.string);
    const value_named = value_parameter.get("named_requirements").?.array.items[0].object;
    try t.expectEqualStrings("contracts.HasValue", value_named.get("name").?.string);
    try t.expectEqualStrings("value", value_named.get("expanded").?.object.get("field_requirements").?.array.items[0].object.get("name").?.string);

    for (templates) |template| try t.expect(!std.mem.eql(u8, template.object.get("name").?.string, "contracts::Hidden"));
}

fn templateParameter(parsed: std.json.Value, name: []const u8) !std.json.ObjectMap {
    const templates = parsed.object.get("schema").?.object.get("generic_templates").?.array.items;
    for (templates) |template| {
        if (std.mem.eql(u8, template.object.get("name").?.string, name))
            return template.object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    }
    return error.TestUnexpectedResult;
}

// spec: GENERIC-API-DEFAULT-COPY-1
test "public generic schema retains default copy for functions and nominal templates" {
    const bytes = try inspect(t.allocator,
        \\public record Box[T]:
        \\    value: T
        \\public func identity[T](value: T) -> T effects():
        \\    return value
        \\public func stored[T: storable]() -> int effects():
        \\    return 0
        \\public func coded[T: codec]() -> int effects():
        \\    return 0
    );
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const identity = (try templateParameter(parsed.value, "lib::identity")).get("requirements").?.array.items;
    const box = (try templateParameter(parsed.value, "lib::Box")).get("requirements").?.array.items;
    const stored = (try templateParameter(parsed.value, "lib::stored")).get("requirements").?.array.items;
    const coded = (try templateParameter(parsed.value, "lib::coded")).get("requirements").?.array.items;
    try t.expectEqual(@as(usize, 1), identity.len);
    try t.expectEqualStrings("copy", identity[0].string);
    try t.expectEqual(@as(usize, 1), box.len);
    try t.expectEqualStrings("copy", box[0].string);
    try t.expectEqual(@as(usize, 1), stored.len);
    try t.expectEqualStrings("storable", stored[0].string);
    try t.expectEqual(@as(usize, 1), coded.len);
    try t.expectEqualStrings("codec", coded[0].string);
}

fn expectSubjectTypes(expanded: std.json.ObjectMap) !void {
    const operation = expanded.get("operation_requirements").?.array.items[0].object;
    const inputs = operation.get("parameters").?.array.items;
    try t.expectEqualStrings("P", inputs[0].object.get("type").?.string);
    try t.expectEqualStrings("types.T", inputs[1].object.get("type").?.string);
    try t.expectEqualStrings("func(P, types.T) -> FixedArray[P, 2] effects()[]", inputs[2].object.get("type").?.string);
    try t.expectEqualStrings("func(P) -> types.T effects()", operation.get("result").?.string);
}

fn subjectSchemaScenario(allocator: std.mem.Allocator) !void {
    var files: NamedFiles = .{
        .types =
        \\public record T:
        \\    value: int
        ,
        .contracts =
        \\import types
        \\public constraint Mixed[T] = copy + op(use(subject: T, concrete: types.T, nested: func(T, types.T) -> FixedArray[T, 2] effects()[]) -> func(T) -> types.T effects() effects())
        ,
        .library =
        \\import contracts
        \\public func use[P: contracts.Mixed](p: P) -> int effects():
        \\    return 0
        ,
    };
    const bytes = try inspectNamedFiles(allocator, &files);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const parameter = try templateParameter(parsed.value, "lib::use");
    try expectSubjectTypes(parameter);
    const named = parameter.get("named_requirements").?.array.items[0].object;
    try t.expectEqualStrings("contracts", named.get("module").?.string);
    try expectSubjectTypes(named.get("expanded").?.object);
}

// spec: GENERIC-API-SUBJECT-1
test "public generic schema typeText writeType and typeChildren preserve subjects and release allocation failures" {
    try subjectSchemaScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), subjectSchemaScenario, .{});
}
