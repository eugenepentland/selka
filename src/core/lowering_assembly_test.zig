//! A lowering assembled from the last one's record (`lowering_assembly.zig`) equals the lowering that replays every function, and a
//! build whose edit changes what the tables hold replays.
const std = @import("std");
const language = @import("selka");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const emit = @import("emit_llvm.zig");

const source_name = "cached.selka";

const program =
    \\func first(n: int) -> int:
    \\    return n + 1
    \\
    \\func second(n: int) -> int:
    \\    return n * 2
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "answer")
    \\    return first(second(20))
    \\
;

/// A program whose lowering defines functions of its own: the equality of a record is a function the builder makes.
const defining =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\func same(a: Point, b: Point) -> bool:
    \\    return a == b
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "point")
    \\    if same(Point(x=1, y=2), Point(x=1, y=2)):
    \\        return 1
    \\    return 0
    \\
;

fn firstLine(_: *const anyopaque, span: u32) emit.Location {
    return .{ .line = 1, .column = span + 1 };
}

fn sameModule(a: std.mem.Allocator, cached: *const ir.Module, fresh: *const ir.Module) !void {
    try support.verified(a, cached, &.{});
    try std.testing.expectEqual(fresh.entry, cached.entry);
    try std.testing.expectEqualDeep(fresh.compounds.items, cached.compounds.items);
    try std.testing.expectEqualDeep(fresh.strings.items, cached.strings.items);
    try std.testing.expectEqual(fresh.functions.items.len, cached.functions.items.len);
    for (fresh.functions.items, cached.functions.items) |expected, actual| {
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualDeep(expected.signature, actual.signature);
        try std.testing.expectEqual(expected.span, actual.span);
        try std.testing.expectEqualStrings(expected.module, actual.module);
        try std.testing.expectEqualDeep(expected.insts.items, actual.insts.items);
        try std.testing.expectEqualDeep(expected.extra.items, actual.extra.items);
        try std.testing.expectEqualDeep(expected.loops.items, actual.loops.items);
        try std.testing.expectEqual(expected.blocks.items.len, actual.blocks.items.len);
        for (expected.blocks.items, actual.blocks.items) |left, right| {
            try std.testing.expectEqualDeep(left.insts.items, right.insts.items);
            try std.testing.expectEqualDeep(left.preds.items, right.preds.items);
        }
    }
    const context: u8 = 0;
    const options: emit.Options = .{ .locator = .{ .context = &context, .locate = firstLine }, .source_path = source_name, .main = .{ .parameters = &.{"out"} } };
    try std.testing.expectEqualStrings(try emit.emitModule(a, fresh, options), try emit.emitModule(a, cached, options));
}

/// What one build through the cache did.
const Built = struct { assembled: bool, lowered: usize, reused: usize };

/// A stand-in for the engine's checked-body parts: the digest of a function is of its name and of the edition of the source, and the
/// number of times it was asked is counted.
const Parts = struct {
    edition: u8,
    asked: usize = 0,

    fn digest(context: *anyopaque, _: ?language.source.Source, function: language.typed.Function) ?stage.Digest {
        const self: *Parts = @ptrCast(@alignCast(context));
        self.asked += 1;
        var out: stage.Digest = undefined;
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update(function.name);
        hash.update(&.{self.edition});
        hash.final(&out);
        return out;
    }
};

/// A checked program and the source it came from.
const Checked = struct { program: language.typed.Program, src: language.source.Source };

/// The entry of a project program: `bytes` as `main.selka`, the standard modules left to the embedded loader.
const Entry = struct {
    text: []const u8,

    /// The reader of `language.embedded_project`: `main.selka` is `text`, and nothing else exists.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, (@as(*Entry, @ptrCast(@alignCast(context.?)))).text);
    }
};

/// Build `bytes` through the cache in `root` with deferred bodies and assembly on, load every body, and require the module to equal
/// the one the uncached builder makes.
fn buildThrough(gpa: std.mem.Allocator, root: []const u8, bytes: []const u8) !Built {
    return buildWith(gpa, root, bytes, null);
}

/// `buildThrough`, with `parts` standing for the engine's checked-body parts when it is given.
fn buildWith(gpa: std.mem.Allocator, root: []const u8, bytes: []const u8, parts: ?*Parts) !Built {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var single: ?language.Compilation = null;
    defer if (single) |*unit| unit.deinit();
    var project: language.embedded_project.Program = undefined;
    var entry: Entry = .{ .text = bytes };
    // A program that imports a standard module is loaded as a project; any other is one source.
    const checked = if (std.mem.startsWith(u8, bytes, "import ")) blk: {
        try project.init(a, .{ .context = &entry, .read = Entry.read });
        break :blk Checked{ .program = project.compilation.program.?, .src = project.compilation.src };
    } else blk: {
        single = try language.Compilation.init(a, source_name, bytes);
        try single.?.check();
        break :blk Checked{ .program = single.?.program.?, .src = single.?.src };
    };
    var store = try stage.Store.init(gpa, std.testing.io, root);
    defer store.deinit();
    var lazy: lowering.Deferred = .{ .arena = a, .store = &store };
    var cache = lowering.Cache.init(&store);
    cache.lazy = &lazy;
    cache.engine.assembly = true;
    if (parts) |held| cache.engine.parts = .{ .context = held, .digest = Parts.digest };
    var refusal: build.Refusal = .{};
    const input: build.Input = .{ .program = checked.program, .source = checked.src };
    var module = try build.buildExecutableCached(a, input, &refusal, &cache);
    try lazy.prepare(&module, checked.src);
    for (0..module.functions.items.len) |index| try lazy.context.ensure(@intCast(index));
    const fresh = try build.buildExecutable(a, input, &refusal);
    try sameModule(a, &module, &fresh);
    return .{ .assembled = cache.engine.assembled, .lowered = cache.counts.lowered, .reused = cache.counts.reused };
}

test "a build assembles its lowering from the record the last one left, and equals the replay" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cold = try buildThrough(std.testing.allocator, root, program);
    try std.testing.expect(!cold.assembled);
    try std.testing.expectEqual(@as(usize, 0), cold.reused);
    const same = try buildThrough(std.testing.allocator, root, program);
    try std.testing.expect(same.assembled);
    try std.testing.expectEqual(@as(usize, 0), same.lowered);
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, program, "return n + 1", "return n + 3");
    defer std.testing.allocator.free(edited);
    const body = try buildThrough(std.testing.allocator, root, edited);
    try std.testing.expect(body.assembled);
    try std.testing.expectEqual(@as(usize, 1), body.lowered);
    const again = try std.mem.replaceOwned(u8, std.testing.allocator, program, "return n + 1", "return n + 5");
    defer std.testing.allocator.free(again);
    const next = try buildThrough(std.testing.allocator, root, again);
    try std.testing.expect(next.assembled);
    const back = try buildThrough(std.testing.allocator, root, program);
    try std.testing.expect(back.assembled);
}

test "an edit that changes the strings the tables hold replays" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    _ = try buildThrough(std.testing.allocator, root, program);
    const settled = try buildThrough(std.testing.allocator, root, program);
    try std.testing.expect(settled.assembled);
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, program, "\"answer\"", "\"longer answer\"");
    defer std.testing.allocator.free(edited);
    const changed = try buildThrough(std.testing.allocator, root, edited);
    try std.testing.expect(!changed.assembled);
    const after = try buildThrough(std.testing.allocator, root, edited);
    try std.testing.expect(after.assembled);
}

test "a record that is declined hands the keys it made and the program's declarations to the replay, which asks the engine for no part again" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    var parts: Parts = .{ .edition = 1 };
    const cold = try buildWith(std.testing.allocator, root, program, &parts);
    try std.testing.expect(!cold.assembled);
    const keyed = parts.asked;
    try std.testing.expect(keyed > 0);
    // The same source: the record holds, every function is keyed once to see so.
    parts.asked = 0;
    const same = try buildWith(std.testing.allocator, root, program, &parts);
    try std.testing.expect(same.assembled);
    try std.testing.expectEqual(keyed, parts.asked);
    // Another edition and a string the tables hold: every key moved, the record is declined, and the replay that follows is the oracle
    // (the module equals the uncached builder's) and is handed the keys, so each function was asked about once in all.
    parts.edition = 2;
    parts.asked = 0;
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, program, "\"answer\"", "\"longer answer\"");
    defer std.testing.allocator.free(edited);
    const declined = try buildWith(std.testing.allocator, root, edited, &parts);
    try std.testing.expect(!declined.assembled);
    try std.testing.expectEqual(keyed, parts.asked);
    // The replay wrote the record for the source it lowered: the next build of it assembles.
    parts.asked = 0;
    const after = try buildWith(std.testing.allocator, root, edited, &parts);
    try std.testing.expect(after.assembled);
    try std.testing.expectEqual(keyed, parts.asked);
}

test "a lowering whose functions define functions of their own is assembled with those functions placed" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    _ = try buildThrough(std.testing.allocator, root, defining);
    const same = try buildThrough(std.testing.allocator, root, defining);
    try std.testing.expect(same.assembled);
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, defining, "return 1", "return 2");
    defer std.testing.allocator.free(edited);
    const body = try buildThrough(std.testing.allocator, root, edited);
    try std.testing.expect(body.assembled);
}

/// A program whose lowering defines a worker of `parallel.map` that reads a union element field by field (projection fusion).
const mapping =
    \\import parallel
    \\
    \\func result_size(value: Result[str, str]) -> int:
    \\    match value:
    \\        case Ok(text):
    \\            return len(text)
    \\        case Err(text):
    \\            return len(text) + 10
    \\
    \\func bump(n: int) -> int:
    \\    return n + 1
    \\
    \\func main(out: Stream) -> int:
    \\    mut values: Result[str, str][] = [Ok("ok-" + str(7)), Err("bad-" + str(8))]
    \\    const sizes = parallel.map(values, result_size)
    \\    print(out, "sizes", sizes[0] + bump(1))
    \\    return 0
    \\
;

test "a function the lowering of another defines is normalized when its creator is assembled from a record, as when it is lowered" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    _ = try buildThrough(std.testing.allocator, root, mapping);
    const same = try buildThrough(std.testing.allocator, root, mapping);
    try std.testing.expect(same.assembled);
    // Only `bump` is lowered again: the worker of `parallel.map` is placed from the record, and `buildThrough` requires the module to
    // equal the uncached one, whose workers projection fusion has rewritten (`list_get_field`).
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, mapping, "return n + 1", "return n + 2");
    defer std.testing.allocator.free(edited);
    const body = try buildThrough(std.testing.allocator, root, edited);
    try std.testing.expect(body.assembled);
}

/// How many functions of `module` name `expected` as their module, and require that no function names another.
fn namedModules(module: *const ir.Module, expected: []const u8) !usize {
    var named: usize = 0;
    for (module.functions.items) |function| {
        if (function.module.len == 0) continue;
        try std.testing.expectEqualStrings(expected, function.module);
        named += 1;
    }
    return named;
}

test "the module text of a lowered function is the module's own, whatever becomes of the source it was read from" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, source_name, program);
    defer unit.deinit();
    try unit.check();
    var refusal: build.Refusal = .{};
    const module = try build.buildExecutable(a, .{ .program = unit.program.?, .source = unit.src }, &refusal);
    @memset(@constCast(unit.src.path), 'x');
    @memset(@constCast(unit.src.key_path), 'x');
    try std.testing.expect(try namedModules(&module, source_name) >= 3);
}
