//! The parts of a module's syntax (`module_parts.zig`): how a module's text is cut, that the cuts tile the text, and that an
//! edit changes exactly the parts that cover what it touched.
const std = @import("std");
const language = @import("selka");
const module_parts = @import("module_parts.zig");

const base =
    \\import model
    \\
    \\record Point:
    \\    x: i64
    \\    y: i64
    \\
    \\
    \\func first(p: Point) -> i64:
    \\    return p.x
    \\
    \\
    \\func second(p: Point) -> i64:
    \\    return p.y + model.answer()
    \\
;

const model_source =
    \\
    \\public func answer() -> i64:
    \\    return 42
    \\
;

const Files = struct { main: []const u8, model: []const u8 = model_source };

fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const files: *const Files = @ptrCast(@alignCast(context.?));
    if (std.mem.eql(u8, path, "main.selka")) return allocator.dupe(u8, files.main);
    if (std.mem.eql(u8, path, "model.selka")) return allocator.dupe(u8, files.model);
    return error.NotFound;
}

/// The parts of `main.selka` when it holds `text`, in `a`; the project and its index live in `a`'s arena too.
fn partsOf(a: std.mem.Allocator, text: []const u8) !module_parts.Parts {
    const files = try a.create(Files);
    files.* = .{ .main = text };
    const project = try a.create(language.project.Project);
    project.* = language.project.Project.init(a);
    try project.load(.{ .context = files, .read = read }, "main", .{});
    const index = try a.create(language.interfaces.Index);
    index.* = try language.interfaces.build(project);
    return module_parts.compute(a, project.modules.items[0], index.units[0].syntax);
}

/// The names of the parts whose digests differ between two tables, joined with a space.
fn changed(a: std.mem.Allocator, left: module_parts.Parts, right: module_parts.Parts) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (left.parts) |was| {
        for (right.parts) |is| {
            if (!std.mem.eql(u8, was.name, is.name) or std.mem.eql(u8, &was.digest, &is.digest)) continue;
            if (text.items.len != 0) try text.append(a, ' ');
            try text.appendSlice(a, was.name);
        }
    }
    return text.items;
}

fn replaced(a: std.mem.Allocator, from: []const u8, to: []const u8) ![]const u8 {
    const at = std.mem.indexOf(u8, base, from) orelse return error.TestUnexpectedResult;
    return std.mem.concat(a, u8, &.{ base[0..at], to, base[at + from.len ..] });
}

test "a module's parts: its header, each declaration's head, each function's body, and the three views" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parts = try partsOf(a, base);
    const wanted = [_][]const u8{ "body:function:first", "body:function:second", "decl:function:first", "decl:function:second", "decl:record:Point", "exports", "header", "heads", "imports", "module" };
    try std.testing.expectEqual(wanted.len, parts.parts.len);
    for (wanted, parts.parts) |name, part| try std.testing.expectEqualStrings(name, part.name);
    try std.testing.expect(std.mem.startsWith(u8, parts.payload, module_parts.payload_magic));
    try std.testing.expect(std.mem.endsWith(u8, parts.payload, "model as model\n"));
}

test "an edit inside one function's body changes that body's part and the whole text, and nothing else" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try partsOf(a, base);
    const after = try partsOf(a, try replaced(a, "return p.x\n", "return p.x + 1\n"));
    try std.testing.expectEqualStrings("body:function:first module", try changed(a, before, after));
}

test "an edit to a body leaves the heads part alone, an edit to a signature or a constant's value changes it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try partsOf(a, base);
    const body = try partsOf(a, try replaced(a, "return p.x\n", "return p.x + 1\n"));
    try std.testing.expect(std.mem.indexOf(u8, try changed(a, before, body), "heads") == null);
    const signature = try partsOf(a, try replaced(a, "func first(p: Point) -> i64:", "func first(q: Point) -> i64:"));
    try std.testing.expect(std.mem.indexOf(u8, try changed(a, before, signature), "heads") != null);
    const with_constant = try partsOf(a, "import model\n\nconst LIMIT: i64 = 3\n\n\nfunc one() -> i64:\n    return LIMIT\n");
    const other_value = try partsOf(a, "import model\n\nconst LIMIT: i64 = 4\n\n\nfunc one() -> i64:\n    return LIMIT\n");
    try std.testing.expect(std.mem.indexOf(u8, try changed(a, with_constant, other_value), "heads") != null);
}

test "an edit to a signature changes the declaration's head and not its body" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try partsOf(a, base);
    const after = try partsOf(a, try replaced(a, "func second(p: Point) -> i64:", "func second(q: Point) -> i64:"));
    try std.testing.expect(std.mem.indexOf(u8, try changed(a, before, after), "decl:function:second") != null);
    try std.testing.expect(std.mem.indexOf(u8, try changed(a, before, after), "body:function:first") == null);
}

test "a line added above the declarations moves them without changing their parts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try partsOf(a, base);
    const after = try partsOf(a, try replaced(a, "import model\n", "import model\n# a comment that moves everything down\n"));
    // Only the header (which holds the comment) and the whole text change: every declaration keeps its digests.
    try std.testing.expectEqualStrings("header module", try changed(a, before, after));
    try std.testing.expect(std.mem.eql(u8, &before.parts[7].digest, &after.parts[7].digest));
}

test "an edit to the import list changes the imports part and the header" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try partsOf(a, base);
    const after = try partsOf(a, try replaced(a, "import model\n", "import model as m\n"));
    // The alias changed the source of every `model.` use too, so the body that spells it may differ as well; the import
    // list and the header differ in any case.
    const names = try changed(a, before, after);
    try std.testing.expect(std.mem.indexOf(u8, names, "imports") != null);
    try std.testing.expect(std.mem.indexOf(u8, names, "header") != null);
}

test "the regions the parts cover tile the module's bytes, with no gap and no overlap" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const files = try a.create(Files);
    files.* = .{ .main = base };
    const project = try a.create(language.project.Project);
    project.* = language.project.Project.init(a);
    try project.load(.{ .context = files, .read = read }, "main", .{});
    const index = try a.create(language.interfaces.Index);
    index.* = try language.interfaces.build(project);
    const regions = try module_parts.regionsOf(a, project.modules.items[0], index.units[0].syntax);
    try std.testing.expect(regions.len >= 4);
    try std.testing.expectEqual(@as(usize, 0), regions[0].begin);
    for (regions[1..], regions[0 .. regions.len - 1]) |next, earlier| try std.testing.expectEqual(earlier.end, next.begin);
    try std.testing.expectEqual(base.len, regions[regions.len - 1].end);
}

test "a module that declares nothing is one header" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parts = try partsOf(a, "import model\n");
    try std.testing.expectEqual(@as(usize, 5), parts.parts.len);
    try std.testing.expectEqualStrings("exports", parts.parts[0].name);
    try std.testing.expectEqualStrings("header", parts.parts[1].name);
}
