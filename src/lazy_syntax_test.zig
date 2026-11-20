//! The lazy merged program: modules read from the syntax store as far as their declarations, bodies filled when asked, the same tables as
//! the eager merge once every body is filled, and a damaged stored body found by its checksum and taken from a re-parse.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const codec = @import("persist_codec.zig");
const lazy_module = @import("lazy_module.zig");
const project_syntax = @import("project_syntax.zig");
const Cache = language.frontend_cache.Cache;

/// A project of the given module sources, each file read by name.
const Tree = struct {
    entries: []const struct { path: []const u8, bytes: []const u8 },
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Tree = @ptrCast(@alignCast(context.?));
        for (self.entries) |entry| if (std.mem.eql(u8, entry.path, path)) return allocator.dupe(u8, entry.bytes);
        return error.NotFound;
    }
};

const main_text =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    return lib.double(4) + lib.label("x") + lib.sum(3)
    \\
;
const lib_text =
    \\
    \\public func double(x: int) -> int:
    \\    return x * 2
    \\
    \\
    \\public func label(text: str) -> int:
    \\    const full = "label:" + text
    \\    return len(full)
    \\
    \\
    \\public func sum(n: int) -> int:
    \\    mut total = 0
    \\    for k in range(n):
    \\        total = total + k
    \\    return total
    \\
    \\
    \\const LIMIT: int = 40 + 2
    \\
;
fn standardTree() Tree {
    return .{ .entries = &.{ .{ .path = "main.selka", .bytes = main_text }, .{ .path = "lib.selka", .bytes = lib_text } } };
}

fn loadTree(project: *language.project.Project, tree: *Tree) !void {
    try project.load(.{ .context = tree, .read = Tree.read }, "main", .{});
}

/// The bytes the stored encoding gives `items`: two tables are equal when these are.
fn tableBytes(allocator: std.mem.Allocator, comptime T: type, items: []const T) ![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write([]const T, items);
    return writer.bytes.toOwnedSlice(allocator);
}

fn expectSameTables(allocator: std.mem.Allocator, left: ast.Program, right: ast.Program) !void {
    const left_nodes = try tableBytes(allocator, ast.Node, left.nodes.items);
    const right_nodes = try tableBytes(allocator, ast.Node, right.nodes.items);
    try t.expectEqualSlices(u8, left_nodes, right_nodes);
    const left_statements = try tableBytes(allocator, ast.Statement, left.statements.items);
    const right_statements = try tableBytes(allocator, ast.Statement, right.statements.items);
    try t.expectEqualSlices(u8, left_statements, right_statements);
    const left_functions = try tableBytes(allocator, ast.Function, left.functions);
    const right_functions = try tableBytes(allocator, ast.Function, right.functions);
    try t.expectEqualSlices(u8, left_functions, right_functions);
    try t.expectEqual(left.facts.extents.len, right.facts.extents.len);
    for (left.facts.extents, right.facts.extents) |a, b| try t.expectEqual(a, b);
    try t.expect(@import("ast_literals.zig").same(left.facts.literals.?, right.facts.literals.?));
    try t.expectEqual(left.facts.retired.?, right.facts.retired.?);
}

/// A project loaded from `tree` and indexed with the syntax stored in `cache` (read as `mode`); the caller owns `project`.
fn index(project: *language.project.Project, cache: *Cache, tree: *Tree, mode: lazy_module.Mode) !language.interfaces.Index {
    try loadTree(project, tree);
    return language.interfaces.buildWithMode(project, .{ .frontend = cache, .mode = mode });
}

/// A module of enough small functions to pass the 32 KiB first read of a stored entry.
fn bulkSource(arena: std.mem.Allocator) ![]const u8 {
    var big: std.ArrayList(u8) = .empty;
    for (0..700) |k| try big.print(arena, "\npublic func bulk_{d}(x: int) -> int:\n    const a = x + {d}\n    const b = a * 3 + {d}\n    return a + b\n\n", .{ k, k, k });
    return big.items;
}

fn tmpRoot(temporary: *t.TmpDir) ![:0]u8 {
    return temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
}

test "a module read lazily fills a body when asked and equals the eager merge once every body is filled" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try tmpRoot(&temporary);
    defer t.allocator.free(root);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var cache = Cache.init(t.allocator, t.io, root, "lazy-test-identity");
    defer cache.deinit();
    var tree = standardTree();
    // The cold build parses and stores every module; its merge is the eager program.
    var cold = language.project.Project.init(t.allocator);
    defer cold.deinit();
    var cold_index = try index(&cold, &cache, &tree, .eager);
    const eager = try project_syntax.build(&cold_index);
    var warm = language.project.Project.init(t.allocator);
    defer warm.deinit();
    var lazy_index = try index(&warm, &cache, &tree, .lazy_sentinel);
    try t.expect(lazy_index.units[0].lazy != null and lazy_index.units[1].lazy != null);
    const lazy = try project_syntax.build(&lazy_index);
    const loader = lazy.loader.?;
    // `main`, `double`, `label` and `sum` are lazy bodies; the constant keeps its tree with the declarations.
    try t.expectEqual(@as(usize, 4), loader.slots.len);
    try t.expectEqual(@as(usize, 0), loader.state.filled);
    // An unfilled body holds the sentinel.
    const slot = loader.slots[1];
    const reference = lazy_index.units[slot.module].lazy.?.declarations.bodies[slot.body];
    const first = loader.bases[slot.module].node + reference.nodes.start;
    const count = reference.nodes.end - reference.nodes.start;
    try t.expectEqual(@as(u8, lazy_module.sentinel), std.mem.asBytes(&lazy.syntax.nodes.items[first])[0]);
    // Asking for the body fills its interval and no other, and asking again does nothing.
    try ast.ensureBody(lazy.syntax, @fromBackingInt(slot.root));
    try t.expectEqual(@as(usize, 1), loader.state.filled);
    const wanted = try tableBytes(arena, ast.Node, eager.syntax.nodes.items[first .. first + count]);
    const got = try tableBytes(arena, ast.Node, lazy.syntax.nodes.items[first .. first + count]);
    try t.expectEqualSlices(u8, wanted, got);
    try ast.ensureBody(lazy.syntax, @fromBackingInt(slot.root));
    try t.expectEqual(@as(usize, 1), loader.state.filled);
    // A statement that is no body's root is not a body to fill.
    try ast.ensureBody(lazy.syntax, @fromBackingInt(0));
    try t.expectEqual(@as(usize, 1), loader.state.filled);
    try ast.ensureAll(lazy.syntax);
    try t.expectEqual(loader.slots.len, loader.state.filled);
    try expectSameTables(arena, eager.syntax, lazy.syntax);
}

test "a lazily read module whose stored body is damaged finds it by its checksum and takes the body from a re-parse" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try tmpRoot(&temporary);
    defer t.allocator.free(root);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var cache = Cache.init(t.allocator, t.io, root, "lazy-test-identity");
    defer cache.deinit();
    var tree = standardTree();
    var cold = language.project.Project.init(t.allocator);
    defer cold.deinit();
    var cold_index = try index(&cold, &cache, &tree, .eager);
    const eager = try project_syntax.build(&cold_index);
    // Damage the last body section of `lib`: inside the payload, before the trailing checksum of the whole.
    const module = cold.modules.items[1];
    const path = try cache.entryPath(cache.syntaxKey(module.src, module.header.body_start));
    defer t.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, arena, .limited(1 << 20));
    bytes[bytes.len - 12] ^= 0x55;
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
    // The whole-entry reader refuses the damaged entry; the lazy reader finds the declaration part intact and the section damaged.
    try t.expect(try cache.lookupSyntax(arena, module.src, module.header.body_start) == null);
    var warm = language.project.Project.init(t.allocator);
    defer warm.deinit();
    var lazy_index = try index(&warm, &cache, &tree, .lazy_sentinel);
    try t.expect(lazy_index.units[1].lazy != null);
    const lazy = try project_syntax.build(&lazy_index);
    try ast.ensureAll(lazy.syntax);
    try t.expectEqual(lazy.loader.?.slots.len, lazy.loader.?.state.filled);
    try expectSameTables(arena, eager.syntax, lazy.syntax);
}

test "a lazily read module larger than the first read is read in two parts and its bodies come from the rest of the file" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try tmpRoot(&temporary);
    defer t.allocator.free(root);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var cache = Cache.init(t.allocator, t.io, root, "lazy-test-identity");
    defer cache.deinit();
    const big = try bulkSource(arena);
    var tree: Tree = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main_text }, .{ .path = "lib.selka", .bytes = big } } };
    var cold = language.project.Project.init(t.allocator);
    defer cold.deinit();
    var cold_index = try index(&cold, &cache, &tree, .eager);
    const eager = try project_syntax.build(&cold_index);
    var warm = language.project.Project.init(t.allocator);
    defer warm.deinit();
    var lazy_index = try index(&warm, &cache, &tree, .lazy);
    const stored = lazy_index.units[1].lazy.?;
    // The entry is not in memory yet: the first body that is asked for reads the file.
    try t.expect(stored.whole == null);
    const lazy = try project_syntax.build(&lazy_index);
    const last = lazy.loader.?.slots[lazy.loader.?.slots.len - 1];
    try ast.ensureBody(lazy.syntax, @fromBackingInt(last.root));
    try t.expect(stored.whole != null);
    try ast.ensureAll(lazy.syntax);
    try expectSameTables(arena, eager.syntax, lazy.syntax);
}

const nested_main =
    \\import lib
    \\
    \\func kind(code: int) -> int:
    \\    match lib.read(code):
    \\        case Ok(value):
    \\            return value
    \\        case Err(Empty):
    \\            return 1
    \\        case Err(Broken(value=text)):
    \\            return len(text)
    \\
    \\
    \\func main() -> int:
    \\    return kind(3) + lib.double(4) + lib.sum(5)
    \\
;
const nested_lib =
    \\public enum Failure:
    \\    Empty
    \\    Broken(value: str)
    \\
    \\
    \\public func read(code: int) -> int fails Failure:
    \\    if code == 0:
    \\        fail Failure.Empty
    \\    return code
    \\
    \\
    \\public func double(x: int) -> int:
    \\    return x * 2
    \\
    \\
    \\public func sum(n: int) -> int:
    \\    mut total = 0
    \\    for k in range(n):
    \\        total = total + k
    \\    return total
    \\
;

/// The shape of the program `checked` makes of `merged`'s index: its typed node, statement and function counts.
const Shape = struct { nodes: usize, statements: usize, functions: usize };

fn checkedShape(merged: *language.interfaces.Index) !Shape {
    var compilation = try language.project_compile.Compilation.init(merged);
    try compilation.check();
    const program = compilation.program.?;
    return .{ .nodes = program.nodes.len, .statements = program.statements.len, .functions = program.functions.len };
}

test "a lazily read program whose first checked body copies the tables for a nested pattern still fills the bodies after it" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try tmpRoot(&temporary);
    defer t.allocator.free(root);
    var cache = Cache.init(t.allocator, t.io, root, "lazy-test-identity");
    defer cache.deinit();
    var tree: Tree = .{ .entries = &.{ .{ .path = "main.selka", .bytes = nested_main }, .{ .path = "lib.selka", .bytes = nested_lib } } };
    var cold = language.project.Project.init(t.allocator);
    defer cold.deinit();
    var cold_index = try index(&cold, &cache, &tree, .eager);
    const eager = try checkedShape(&cold_index);
    var warm = language.project.Project.init(t.allocator);
    defer warm.deinit();
    var lazy_index = try index(&warm, &cache, &tree, .lazy_sentinel);
    try t.expect(lazy_index.units[0].lazy != null and lazy_index.units[1].lazy != null);
    const lazy = try checkedShape(&lazy_index);
    try t.expectEqual(eager, lazy);
}
