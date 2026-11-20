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
    \\public func echo[T: equality](x: FixedArray[T, 2]) -> FixedArray[T, 2]:
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
    \\public func run(x: i64) -> i64:
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
            File{ .path = "main.selka", .bytes = entry },
            File{ .path = "lib.selka", .bytes = self.library },
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

test "O3 generic API reports declared from positions" {
    const allocator = t.allocator;
    const bytes = try inspect(allocator, "public func pick[T](items: T[]) -> T[] from items:\n    return items\n");
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const templates = parsed.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    try t.expectEqual(@as(usize, 1), templates.len);
    const signature = templates[0].object.get("contract").?.object.get("signature").?.object;
    try t.expectEqualStrings("params", signature.get("return_origin").?.string);
    const positions = signature.get("borrows").?.array.items;
    try t.expectEqual(@as(usize, 1), positions.len);
    try t.expectEqual(@as(i64, 0), positions[0].integer);
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
    try t.expect(signature.get("declared_effects") == null);
    try t.expectEqualStrings("lib.selka", echo.get("source").?.object.get("path").?.string);
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

test "public generic schemas retain structural fields explicit callbacks and codec constraints" {
    const bytes = try inspect(t.allocator,
        \\
        \\
        \\public func field[T: copy + field(value: i64)](x: T) -> i64:
        \\    return x.value
        \\
        \\
        \\public func action[T: copy](x: T, score: func(T) -> i64) -> i64:
        \\    return score(x)
        \\
        \\
        \\public func coded[T: copy + codec](x: T) -> T:
        \\    return x
    );
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const templates = parsed.value.object.get("schema").?.object.get("generic_templates").?.array.items;
    const action = templates[0].object.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqual(@as(usize, 0), action.get("operation_requirements").?.array.items.len);
    try t.expectEqual(@as(usize, 0), action.get("named_requirements").?.array.items.len);
    const action_signature = templates[0].object.get("contract").?.object.get("signature").?.object;
    const callback = action_signature.get("parameters").?.array.items[1].object;
    try t.expectEqualStrings("score", callback.get("name").?.string);
    try t.expectEqualStrings("func(T) -> i64", callback.get("type").?.string);
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

const retired_named_contracts =
    // migrate-embedded: skip intentional retired contract parser/catalog and E_DOMAIN_REMOVED witness
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
    \\public func total[P: copy](policy: P, subtotal: i64, price: func(P, i64) -> i64) -> i64:
    \\    return price(policy, subtotal)
    \\
    \\
    \\public func value_of[T: copy + field(value: i64)](item: T) -> i64:
    \\    return item.value
;
const named_entry =
    \\import lib as api
    \\
    \\
    \\public func run(x: i64) -> i64:
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
            File{ .path = "main.selka", .bytes = named_entry },
            File{ .path = "lib.selka", .bytes = self.library },
            File{ .path = "contracts.selka", .bytes = self.contracts },
            File{ .path = "types.selka", .bytes = self.types },
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
test "public schema exposes inline bounds without publishing retired constraints" {
    const bytes = try inspectNamed(t.allocator, "");
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    const schema = parsed.value.object.get("schema").?.object;
    try t.expectEqualStrings("generic-templates-v2", schema.get("generic_templates_version").?.string);
    const templates = schema.get("generic_templates").?.array.items;
    try t.expectEqual(@as(usize, 2), templates.len);

    const total = templates[0].object;
    try t.expectEqualStrings("lib::total", total.get("name").?.string);
    try t.expectEqualStrings("function", total.get("kind").?.string);
    const parameter = total.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    try t.expectEqualStrings("copy", parameter.get("requirements").?.array.items[0].string);
    try t.expectEqual(@as(usize, 0), parameter.get("operation_requirements").?.array.items.len);
    try t.expectEqual(@as(usize, 0), parameter.get("named_requirements").?.array.items.len);
    const signature = total.get("contract").?.object.get("signature").?.object;
    const callback = signature.get("parameters").?.array.items[2].object;
    try t.expectEqualStrings("price", callback.get("name").?.string);
    try t.expectEqualStrings("func(P, i64) -> i64", callback.get("type").?.string);

    const value_of = templates[1].object;
    try t.expectEqualStrings("lib::value_of", value_of.get("name").?.string);
    const value_parameter = value_of.get("contract").?.object.get("type_parameters").?.array.items[0].object;
    const fields = value_parameter.get("field_requirements").?.array.items;
    try t.expectEqual(@as(usize, 1), fields.len);
    try t.expectEqualStrings("value", fields[0].object.get("name").?.string);
    try t.expectEqualStrings("i64", fields[0].object.get("type").?.string);
    try t.expectEqual(@as(usize, 0), value_parameter.get("named_requirements").?.array.items.len);
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
        \\public func identity[T](value: T) -> T:
        \\    return value
        \\public func stored[T: storable]() -> int:
        \\    return 0
        \\public func coded[T: codec]() -> int:
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
    const fields = expanded.get("field_requirements").?.array.items;
    try t.expectEqual(@as(usize, 4), fields.len);
    try t.expectEqualStrings("P", fields[0].object.get("type").?.string);
    try t.expectEqualStrings("types.T", fields[1].object.get("type").?.string);
    try t.expectEqualStrings("func(P, types.T) -> FixedArray[P, 2][]", fields[2].object.get("type").?.string);
    try t.expectEqualStrings("func(P) -> types.T", fields[3].object.get("type").?.string);
}

fn subjectSchemaScenario(allocator: std.mem.Allocator) !void {
    var files: NamedFiles = .{
        .types =
        \\public record T:
        \\    value: int
        ,
        .contracts = "",
        .library =
        \\import contracts
        \\import types
        \\public func use[P: copy + field(subject: P) + field(concrete: types.T) + field(nested: func(P, types.T) -> FixedArray[P, 2][]) + field(factory: func(P) -> types.T)](p: P) -> int:
        \\    return 0
        ,
    };
    const bytes = try inspectNamedFiles(allocator, &files);
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const parameter = try templateParameter(parsed.value, "lib::use");
    try expectSubjectTypes(parameter);
    try t.expectEqual(@as(usize, 0), parameter.get("named_requirements").?.array.items.len);
    try t.expectEqual(@as(usize, 0), parameter.get("operation_requirements").?.array.items.len);
}

// spec: GENERIC-API-SUBJECT-1
test "public generic schema typeText writeType and typeChildren preserve subjects and release allocation failures" {
    try subjectSchemaScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), subjectSchemaScenario, .{});
}

const retired_inline_contracts =
    // migrate-embedded: skip intentional retired contract parser/catalog and E_DOMAIN_REMOVED witness
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
;

const retired_mixed_contract =
    // migrate-embedded: skip intentional retired contract parser/catalog and E_DOMAIN_REMOVED witness
    \\import types
    \\public constraint Mixed[T] = copy + op(use(subject: T, concrete: types.T, nested: func(T, types.T) -> FixedArray[T, 2] effects()[]) -> func(T) -> types.T effects() effects())
;

const RetiredContractPhase = enum { effects_parse, domain_check };

fn expectRetiredContract(files: *NamedFiles, phase: RetiredContractPhase) !void {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = files, .read = NamedFiles.read }, "main", .{});
    if (phase == .effects_parse) {
        try t.expectError(error.SourceError, language.interfaces.build(&project));
        try t.expectEqualStrings("E_EFFECTS_REMOVED", project.problem.?.code);
        return;
    }
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    var removed = false;
    for (compilation.diagnostics.items.items) |item| {
        if (std.mem.eql(u8, item.code, "E_DOMAIN_REMOVED")) removed = true;
    }
    try t.expect(removed);
}

// spec-case: GENERIC-API-1
test "public generic schemas reject retired named and operation contracts" {
    var cases = [_]NamedFiles{
        .{ .contracts = "", .library = retired_inline_contracts },
        .{ .contracts = retired_named_contracts },
        .{ .contracts = retired_mixed_contract, .types = "public record T:\n    value: int\n" },
    };
    for (&cases) |*files| {
        // Keep the original mixed-retirement guests byte-exact: their source
        // effect clauses reject during interface parsing, before domain checks.
        try expectRetiredContract(files, .effects_parse);
        const contracts = try std.mem.replaceOwned(u8, t.allocator, files.contracts, " effects()", "");
        defer t.allocator.free(contracts);
        const current_library = try std.mem.replaceOwned(u8, t.allocator, files.library, " effects()", "");
        defer t.allocator.free(current_library);
        var effect_erased = files.*;
        effect_erased.contracts = contracts;
        effect_erased.library = current_library;
        try expectRetiredContract(&effect_erased, .domain_check);
    }
}
