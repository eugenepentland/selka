//! Navigation evidence is checked against distinct same-spelling declarations.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const pc = @import("project_compile.zig");
const navigation = @import("navigation.zig");
const identity: @import("source_receipt.zig").Identity = .{ .compiler_sha256 = @splat(0), .zig_version = "test", .architecture = "test", .os = "test", .abi = "test", .optimize = "test" };
const Files = struct {
    main: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        const data_source =
            \\
            \\
            \\public record Box:
            \\    value: i64
            \\
            \\
            \\public func read(x: Box) -> i64:
            \\    return x.value
        ;
        const bytes = if (std.mem.eql(u8, path, "main.selka")) self.main else if (std.mem.eql(u8, path, "data.selka")) data_source else return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
};
const fixture =
    \\import data
    \\
    \\
    \\func read(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    mut b = data.Box(value=3)
    \\    return read(data.read(b))
;

test "O3 navigation publishes declared from positions above 63 without body checking" {
    const allocator = t.allocator;
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("public func pick(");
    for (0..70) |i| try text.writer.print("{s}p{d}: str", .{ if (i == 0) "" else ", ", i });
    try text.writer.writeAll(") -> str from p69,p0:\n    return missing()\nfunc main() -> int:\n    return 0\n");
    var files: Files = .{ .main = text.written() };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    const bytes = try navigation.render(allocator, &compilation, identity, .{});
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const symbol = try symbolById(parsed.value, "main::pick");
    try t.expectEqualStrings("pick", symbol.get("name").?.string);
    try t.expectEqualStrings("params", symbol.get("return_origin").?.string);
    const positions = symbol.get("borrow").?.object.get("positions").?.array.items;
    try t.expectEqual(@as(usize, 2), positions.len);
    try t.expectEqual(@as(i64, 0), positions[0].integer);
    try t.expectEqual(@as(i64, 69), positions[1].integer);
    try t.expect(std.mem.indexOf(u8, symbol.get("signature").?.string, "from p0, p69") != null);
    try t.expect(compilation.program == null);
}
fn symbolById(value: std.json.Value, id: []const u8) !std.json.ObjectMap {
    for (value.object.get("symbols").?.array.items) |item| {
        if (std.mem.eql(u8, item.object.get("id").?.string, id)) return item.object;
    }
    return error.TestUnexpectedResult;
}

fn emitted(allocator: std.mem.Allocator, compilation: *pc.Compilation) !void {
    const bytes = try navigation.render(allocator, compilation, identity, .{});
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const root = parsed.value.object;
    try t.expect(root.get("checked").?.bool);
    var field_seen = false;
    var local_call = false;
    var imported_call = false;
    for (root.get("references").?.array.items) |value| {
        const edge = value.object;
        const to = edge.get("to").?.string;
        const kind = edge.get("kind").?.string;
        if (std.mem.eql(u8, kind, "field_read") and std.mem.eql(u8, to, "data::Box.value")) field_seen = true;
        if (std.mem.eql(u8, kind, "call")) {
            if (std.mem.eql(u8, to, "main::read")) local_call = true;
            if (std.mem.eql(u8, to, "data::read")) imported_call = true;
        }
    }
    try t.expect(field_seen and local_call and imported_call);
}
// spec: NAVIGATION-1
test "navigation resolves qualified calls fields and source identities without execution" {
    var files: Files = .{ .main = fixture };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    try emitted(t.allocator, &compilation);
    try t.checkAllAllocationFailures(t.allocator, emitted, .{&compilation});
    try t.expectError(error.NavigationLimit, navigation.render(t.allocator, &compilation, identity, .{ .symbols = 1 }));
    try t.expectError(error.NavigationLimit, navigation.render(t.allocator, &compilation, identity, .{ .references = 1 }));
}
test "navigation exposes declarations but never checked references after a semantic failure" {
    var files: Files = .{ .main =
        \\
        \\
        \\func main() -> i64:
        \\    return missing()
    };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    const bytes = try navigation.render(t.allocator, &compilation, identity, .{});
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    try t.expect(!parsed.value.object.get("checked").?.bool);
    try t.expectEqual(@as(usize, 0), parsed.value.object.get("references").?.array.items.len);
    try t.expectEqualStrings("main::main", parsed.value.object.get("symbols").?.array.items[0].object.get("id").?.string);
}

test "navigation syntax failure retains lexical declarations without resolving comments or calls" {
    var files: Files = .{ .main =
        \\import data
        \\# func invented()
        \\func broken() -> i64:
        \\    return +
    };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    try t.expectError(error.SourceError, interfaces.build(&project));
    const bytes = try @import("navigation_partial.zig").render(t.allocator, &project, identity);
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    try t.expect(!parsed.value.object.get("checked").?.bool);
    try t.expectEqual(@as(usize, 0), parsed.value.object.get("references").?.array.items.len);
    try t.expect(std.mem.indexOf(u8, bytes, "main::broken") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "data::read") != null);
    try t.expect(std.mem.indexOf(u8, bytes, "invented") == null);
}
fn document(bytes: []const u8) !std.json.Parsed(std.json.Value) {
    var files: Files = .{ .main = bytes };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const rendered = try navigation.render(t.allocator, &compilation, identity, .{});
    defer t.allocator.free(rendered);
    return std.json.parseFromSlice(std.json.Value, t.allocator, rendered, .{ .allocate = .alloc_always });
}
fn uniqueSymbols(value: std.json.Value, name: []const u8, kind: []const u8) !void {
    var ids: std.StringHashMapUnmanaged(void) = .empty;
    defer ids.deinit(t.allocator);
    for (value.object.get("symbols").?.array.items) |item| {
        const symbol = item.object;
        if (!std.mem.eql(u8, symbol.get("name").?.string, name) or !std.mem.eql(u8, symbol.get("kind").?.string, kind)) continue;
        const slot = try ids.getOrPut(t.allocator, symbol.get("id").?.string);
        try t.expect(!slot.found_existing);
    }
    try t.expectEqual(@as(usize, 2), ids.count());
}
fn typeTargets(value: std.json.Value) !void {
    var kinds: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer kinds.deinit(t.allocator);
    for (value.object.get("symbols").?.array.items) |item| try kinds.put(t.allocator, item.object.get("id").?.string, item.object.get("kind").?.string);
    for (value.object.get("references").?.array.items) |item| {
        const edge = item.object;
        const kind = edge.get("kind").?.string;
        if (std.mem.eql(u8, kind, "uses_type") or std.mem.eql(u8, kind, "returns") or std.mem.eql(u8, kind, "accepts") or std.mem.eql(u8, kind, "contains_type")) {
            try t.expectEqualStrings("type", kinds.get(edge.get("to").?.string).?);
        }
    }
}
test "navigation synthesized array shapes never resolve to function local or field declarations" {
    const parsed = try document(
        \\
        \\
        \\record Box:
        \\    n: i64
        \\
        \\
        \\func repeat[T](v: T) -> FixedArray[T, 1]:
        \\    return FixedArray[T, 1]([v])
        \\
        \\
        \\func main() -> i64:
        \\    mut value = Box(n=3)
        \\    mut items = repeat[Box](value)
        \\    return items[0].n
    );
    defer parsed.deinit();
    try typeTargets(parsed.value);
}
// The standard library discovers this method reflectively; exercise its wire
// contract directly as well as through whole-index rendering. The symbol
// declares `analysis = .checked` because that is the wire shape this test pins:
// a symbol whose facts were not checked publishes `analysis` and `null` inferred
// fields instead (see `NAVIGATION-FACTS-1`).
test "navigation jsonStringify preserves flat wire facts and reports a full writer" {
    const symbol: navigation.Symbol = .{
        .id = "main::draw",
        .name = "draw",
        .kind = "function",
        .location = .{ .path = "main.selka", .start = 10, .end = 14, .line = 2, .column = 4 },
        .exported = true,
        .details = .{ .analysis = .checked, .signature = "draw() -> i64", .type_name = "i64" },
        .context = .{ .snippet = "draw() -> i64:\n    return 1", .snippet_truncated = true },
    };
    var output = std.Io.Writer.Allocating.init(t.allocator);
    defer output.deinit();
    var writer: std.json.Stringify = .{ .writer = &output.writer };
    try symbol.jsonStringify(&writer);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, output.written(), .{});
    defer parsed.deinit();
    const row = parsed.value.object;
    try t.expectEqualStrings("draw() -> i64", row.get("signature").?.string);
    try t.expect(row.get("effects") == null);
    try t.expect(row.get("snippet_truncated").?.bool);
    try t.expect(row.get("details") == null and row.get("context") == null);
    var full = std.Io.Writer.fixed(&.{});
    var rejected: std.json.Stringify = .{ .writer = &full };
    try t.expectError(error.WriteFailed, symbol.jsonStringify(&rejected));
}
// spec-case: NAVIGATION-1
test "navigation publishes declared mutation footprints and return origins" {
    const parsed = try document(
        \\
        \\
        \\func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func pick(values: int[]) -> int[]:
        \\    return copy(values)
        \\
        \\
        \\func total(values: int[]) -> int:
        \\    return len(values)
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1]
        \\    touch(mut values)
        \\    mut picked = pick(values)
        \\    picked[0] = 2
        \\    return total(picked)
    );
    defer parsed.deinit();
    var saw_touch = false;
    var saw_pick = false;
    var saw_total = false;
    for (parsed.value.object.get("symbols").?.array.items) |item| {
        const symbol = item.object;
        const name = symbol.get("name").?.string;
        if (std.mem.eql(u8, name, "touch")) {
            saw_touch = true;
            try t.expect(symbol.get("mutation_writes").?.bool);
            try t.expectEqual(@as(i64, 0), symbol.get("mutates").?.array.items[0].integer);
        }
        if (std.mem.eql(u8, name, "pick")) {
            saw_pick = true;
            try t.expectEqualStrings("fresh", symbol.get("return_origin").?.string);
            try t.expect(!symbol.get("mutation_writes").?.bool);
        }
        if (std.mem.eql(u8, name, "total")) {
            saw_total = true;
            try t.expectEqual(@as(usize, 0), symbol.get("mutates").?.array.items.len);
            try t.expectEqualStrings("fresh", symbol.get("return_origin").?.string);
            try t.expect(!symbol.get("mutation_writes").?.bool);
        }
    }
    try t.expect(saw_touch and saw_pick and saw_total);
}

test "navigation excerpts retain complete UTF8 at the size bound" {
    const prefix = "import data\n\n\nfunc main() -> i64:\n    # ";
    const name_start = std.mem.indexOf(u8, prefix, "main() -> i64").?;
    const padding = name_start + 16383 - prefix.len;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(t.allocator);
    try bytes.appendSlice(t.allocator, prefix);
    try bytes.appendNTimes(t.allocator, 'x', padding);
    try bytes.appendSlice(t.allocator, "é remaining comment\n    const b = data.Box(value=3)\n    return data.read(b)");
    const parsed = try document(bytes.items);
    defer parsed.deinit();
    var found = false;
    for (parsed.value.object.get("symbols").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("id").?.string, "main::main")) continue;
        found = true;
        const excerpt = item.object.get("snippet").?.string;
        try t.expectEqualStrings(bytes.items[name_start..][0..16383], excerpt);
        try t.expect(std.unicode.utf8ValidateSlice(excerpt));
        try t.expect(item.object.get("snippet_truncated").?.bool);
        try t.expectEqualStrings("main() -> i64", item.object.get("signature").?.string);
    }
    try t.expect(found);
}

test "navigation excerpts preserve original module qualified calls" {
    const linked = try document(fixture);
    defer linked.deinit();
    var linked_found = false;
    for (linked.value.object.get("symbols").?.array.items) |item| {
        if (!std.mem.eql(u8, item.object.get("id").?.string, "main::main")) continue;
        linked_found = true;
        try t.expectEqualStrings(
            \\main() -> i64:
            \\    mut b = data.Box(value=3)
            \\    return read(data.read(b))
        , item.object.get("snippet").?.string);
    }
    try t.expect(linked_found);
}

// spec: TESTS-FOR-1
test "renderTestsFor reports direct and transitive tests for a declaration" {
    var files: Files = .{ .main =
        \\
        \\
        \\func parse(value: i64) -> i64:
        \\    return helper(value)
        \\
        \\
        \\func helper(value: i64) -> i64:
        \\    return value
        \\
        \\
        \\func test_parse() -> bool:
        \\    return parse(1) == 1
        \\
        \\
        \\func test_end_to_end() -> bool:
        \\    return helper(2) == 2
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const rendered = (try navigation.renderTestsFor(t.allocator, &compilation, "main::helper")).?;
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "direct (1): main::test_end_to_end") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "reached-by (2): main::test_parse main::test_end_to_end") != null);
    try t.expectEqual(@as(?[]u8, null), try navigation.renderTestsFor(t.allocator, &compilation, "main::missing"));
}

/// Whether one parsed symbol carries `null` for every inferred fact field.
fn expectUnavailableFacts(symbol: std.json.ObjectMap) !void {
    try t.expect(symbol.get("effects") == null);
    if (symbol.get("signature").?.string.len == 0) {
        try t.expect(symbol.get("mutates").? == .null);
        try t.expect(symbol.get("return_origin").? == .null);
    } else {
        try t.expect(symbol.get("mutates").? == .array);
        try t.expectEqualStrings("fresh", symbol.get("return_origin").?.string);
    }
    try t.expect(symbol.get("mutation_writes").? == .null);
}

// spec: NAVIGATION-FACTS-1
test "navigation publishes null inferred facts and a status when bodies were not checked" {
    var files: Files = .{ .main =
        \\import data
        \\
        \\
        \\func double(x: i64) -> i64 effects(managed_allocation):
        \\    return x * 2
        \\
        \\
        \\func unfinished(x: i64) -> i64:
        \\    return todo[i64]()
        \\
        \\
        \\func main() -> i64:
        \\    return data.read(data.Box(value=double(2)))
    };
    // Keep the original negative source and independently exercise typed-hole navigation.
    {
        var retired_project = graph.Project.init(t.allocator);
        defer retired_project.deinit();
        try retired_project.load(.{ .context = &files, .read = Files.read }, "main", .{});
        try t.expectError(error.SourceError, interfaces.build(&retired_project));
        try t.expectEqualStrings("E_EFFECTS_REMOVED", retired_project.problem.?.code);
    }
    const modern_source = try std.mem.replaceOwned(u8, t.allocator, files.main, " effects(managed_allocation)", "");
    defer t.allocator.free(modern_source);
    files.main = modern_source;
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_TYPED_HOLE", compilation.diagnostics.items.items[0].code);
    const bytes = try navigation.render(t.allocator, &compilation, identity, .{});
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    try t.expect(!parsed.value.object.get("checked").?.bool);
    var saw_function = false;
    var saw_type = false;
    for (parsed.value.object.get("symbols").?.array.items) |item| {
        const symbol = item.object;
        const name = symbol.get("name").?.string;
        if (std.mem.eql(u8, name, "double")) {
            saw_function = true;
            try t.expectEqualStrings("declaration-only", symbol.get("analysis").?.string);
            try t.expect(symbol.get("mutates").? == .array);
            try t.expectEqualStrings("fresh", symbol.get("return_origin").?.string);
            try t.expect(symbol.get("mutation_writes").? == .null);
        }
        if (std.mem.eql(u8, name, "Box")) {
            saw_type = true;
            // A type declaration's own shape is declared, not missing.
            try t.expectEqualStrings("declared", symbol.get("analysis").?.string);
            try expectUnavailableFacts(symbol);
        }
    }
    try t.expect(saw_function and saw_type);
}
// spec-case: NAVIGATION-FACTS-1
test "navigation keeps a checked symbol's exact field set with no analysis clause" {
    const parsed = try document(fixture);
    defer parsed.deinit();
    var saw_checked = false;
    for (parsed.value.object.get("symbols").?.array.items) |item| {
        const symbol = item.object;
        if (!std.mem.eql(u8, symbol.get("name").?.string, "read")) continue;
        if (!std.mem.eql(u8, symbol.get("kind").?.string, "function")) continue;
        saw_checked = true;
        // Removed effect fields stay absent; retained checked mutation/origin
        // facts are available without an unavailable-analysis marker.
        try t.expect(symbol.get("analysis") == null);
        try t.expect(symbol.get("effects") == null);
        try t.expectEqual(@as(usize, 0), symbol.get("mutates").?.array.items.len);
        try t.expect(symbol.get("return_origin").? != .null);
    }
    try t.expect(saw_checked);
}

// spec: NAVIGATION-FACTS-2
test "navigation marks a generic no instantiation used as a template" {
    var files: Files = .{ .main =
        \\
        \\
        \\func build[T](x: T) -> i64:
        \\    mut items: i64[] = []
        \\    append(mut items, 1)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try pc.Compilation.init(&index);
    try compilation.check();
    const bytes = try navigation.render(t.allocator, &compilation, identity, .{});
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    try t.expect(parsed.value.object.get("checked").?.bool);
    var saw_template = false;
    for (parsed.value.object.get("symbols").?.array.items) |item| {
        const symbol = item.object;
        if (!std.mem.eql(u8, symbol.get("name").?.string, "build")) continue;
        saw_template = true;
        try t.expectEqualStrings("template", symbol.get("analysis").?.string);
        try expectUnavailableFacts(symbol);
    }
    try t.expect(saw_template);
}

// spec: NAVIGATION-FACTS-3
test "lexical-only navigation candidates publish a status and no inferred facts" {
    var files: Files = .{ .main =
        \\import data
        \\func broken() -> i64:
        \\    return +
    };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    try t.expectError(error.SourceError, interfaces.build(&project));
    const bytes = try @import("navigation_partial.zig").render(t.allocator, &project, identity);
    defer t.allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
    defer parsed.deinit();
    try t.expect(!parsed.value.object.get("checked").?.bool);
    var saw_lexical = false;
    for (parsed.value.object.get("symbols").?.array.items) |item| {
        const symbol = item.object;
        if (!std.mem.eql(u8, symbol.get("name").?.string, "broken")) continue;
        saw_lexical = true;
        try t.expectEqualStrings("lexical-only", symbol.get("analysis").?.string);
        try expectUnavailableFacts(symbol);
    }
    try t.expect(saw_lexical);
}
