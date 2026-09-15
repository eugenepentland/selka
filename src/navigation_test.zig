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
            \\module data
            \\export Box
            \\export read
            \\
            \\
            \\class Box:
            \\    value: i64
            \\
            \\
            \\def read(x: Box) -> i64 effects():
            \\    return x.value
        ;
        const bytes = if (std.mem.eql(u8, path, "main.my")) self.main else if (std.mem.eql(u8, path, "data.my")) data_source else return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }
};
const fixture =
    \\module main
    \\import data
    \\
    \\
    \\def read(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\def main() -> i64:
    \\    b = data.Box(value=3)
    \\    return read(data.read(b))
;
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
    try t.expect(compilation.code == null);
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
        \\module main
        \\
        \\
        \\def main() -> i64:
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
        \\module main
        \\import data
        \\# def invented()
        \\def broken() -> i64:
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
        \\module main
        \\
        \\
        \\class Box:
        \\    n: i64
        \\
        \\
        \\def repeat[T](v: T) -> [1]T:
        \\    return [v]
        \\
        \\
        \\def main() -> i64:
        \\    value = Box(n=3)
        \\    items = repeat[Box](value)
        \\    return items[0].n
    );
    defer parsed.deinit();
    try typeTargets(parsed.value);
}
// The standard library discovers this method reflectively; exercise its wire
// contract directly as well as through whole-index rendering.
test "navigation jsonStringify preserves flat wire facts and reports a full writer" {
    const symbol: navigation.Symbol = .{
        .id = "main::draw",
        .name = "draw",
        .kind = "function",
        .location = .{ .path = "main.my", .start = 10, .end = 14, .line = 2, .column = 4 },
        .exported = true,
        .details = .{ .signature = "draw() -> i64", .type_name = "i64", .effects = &.{"alloc"} },
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
    try t.expectEqualStrings("alloc", row.get("effects").?.array.items[0].string);
    try t.expect(row.get("snippet_truncated").?.bool);
    try t.expect(row.get("details") == null and row.get("context") == null);
    var full = std.Io.Writer.fixed(&.{});
    var rejected: std.json.Stringify = .{ .writer = &full };
    try t.expectError(error.WriteFailed, symbol.jsonStringify(&rejected));
}
// spec-case: NAVIGATION-1
test "navigation publishes declared mutation footprints and return origins" {
    const parsed = try document(
        \\module main
        \\
        \\
        \\def touch(values: list[int]) -> None effects(mutation) mutates(values):
        \\    values[0] = 1
        \\
        \\
        \\def pick(values: list[int]) -> list[int] effects():
        \\    return values
        \\
        \\
        \\def total(values: list[int]) -> int effects():
        \\    return len(values)
        \\
        \\
        \\def main() -> int:
        \\    values = [1]
        \\    touch(values)
        \\    picked = pick(values)
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
            try t.expectEqualStrings("params", symbol.get("return_origin").?.string);
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
    const prefix = "module main\nimport data\n\n\ndef main() -> i64:\n    # ";
    const name_start = std.mem.indexOf(u8, prefix, "main() -> i64").?;
    const padding = name_start + 16383 - prefix.len;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(t.allocator);
    try bytes.appendSlice(t.allocator, prefix);
    try bytes.appendNTimes(t.allocator, 'x', padding);
    try bytes.appendSlice(t.allocator, "é remaining comment\n    b = data.Box(value=3)\n    return data.read(b)");
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
            \\    b = data.Box(value=3)
            \\    return read(data.read(b))
        , item.object.get("snippet").?.string);
    }
    try t.expect(linked_found);
}
