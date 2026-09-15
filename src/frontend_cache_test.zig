//! Persistent frontend cache reuse, invalidation, damage and retention.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const cache_key = @import("cache_key.zig");
const Cache = language.frontend_cache.Cache;

const Files = struct {
    bytes: []const u8 =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, _: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return allocator.dupe(u8, self.bytes);
    }
};

fn load(project: *language.project.Project, files: *Files) !void {
    try project.load(.{ .context = files, .read = Files.read }, "main", .{});
}

fn openCache(root: []const u8) Cache {
    return Cache.init(t.allocator, t.io, root, "test-identity");
}

// spec-case: FRONTEND-CACHE-1
test "syntax entries round trip under exact bytes and invalidate on any change" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var caller = std.heap.ArenaAllocator.init(t.allocator);
    defer caller.deinit();
    var cache = openCache(root);
    var files: Files = .{};
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);

    const hit = (try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)).?;
    try t.expectEqual(index.units[0].syntax.nodes.items.len, hit.nodes.items.len);
    try t.expectEqualStrings("main", module.src.text(hit.functions[0].name));
    // A restored growable list must own exactly its items, so a later append
    // reallocates rather than writing into capacity it never allocated.
    try t.expectEqual(hit.nodes.items.len, hit.nodes.capacity);
    try t.expectEqual(hit.statements.items.len, hit.statements.capacity);

    // A changed body changes the key, so the old entry is never returned.
    files.bytes =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 7
    ;
    var changed = language.project.Project.init(t.allocator);
    defer changed.deinit();
    try load(&changed, &files);
    const changed_module = changed.modules.items[0];
    try t.expect(try cache.lookupSyntax(caller.allocator(), changed_module.src, changed_module.header.body_start) == null);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.hits);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.misses);
}

// spec-case: FRONTEND-CACHE-2
test "verdict entries require identical module bytes and reject damaged files" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    var files: Files = .{};
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    try cache.rememberVerdict(&project, .text, "warning: unused\n");
    const warnings = (try cache.lookupVerdict(t.allocator, &project, .text)).?;
    defer t.allocator.free(warnings);
    try t.expectEqualStrings("warning: unused\n", warnings);
    // A different warning format is a different key.
    try t.expect(try cache.lookupVerdict(t.allocator, &project, .json) == null);

    // A truncated entry is a plain miss with damaged accounting, never a partial
    // warning replay or a host failure.
    const key = cache.verdictKeyFor(&project, .text);
    const path = try cache.entryPath(key);
    defer t.allocator.free(path);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = "truncated" });
    try t.expectError(error.Damaged, cache.read(key));
    const damaged_before = cache.statistics.damaged;
    try t.expect(try cache.lookupVerdict(t.allocator, &project, .text) == null);
    try t.expectEqual(damaged_before + 1, cache.statistics.damaged);

    // Editing the only module invalidates the verdict.
    files.bytes =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 3
    ;
    var changed = language.project.Project.init(t.allocator);
    defer changed.deinit();
    try load(&changed, &files);
    try t.expect(try cache.lookupVerdict(t.allocator, &changed, .text) == null);
}

// spec-case: FRONTEND-CACHE-1
test "damaged entries are rejected and fall back to fresh work without failing" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    var files: Files = .{};
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);

    // A valid entry reads back, then a damaged body is a miss - not a failure and
    // not a partial parse.
    const key = cache.syntaxKey(module.src, module.header.body_start);
    const stored = try cache.read(key);
    t.allocator.free(stored);
    const path = try cache.entryPath(key);
    defer t.allocator.free(path);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = "not an entry at all" });
    try t.expectError(error.Damaged, cache.read(key));
    const misses_before = cache.statistics.syntax.misses;
    try t.expect(try cache.lookupSyntax(t.allocator, module.src, module.header.body_start) == null);
    try t.expectEqual(misses_before + 1, cache.statistics.syntax.misses);
    try t.expect(cache.statistics.syntax.hits == 0);

    // A long body whose magic does not match is rejected rather than trusted.
    var junk: [200]u8 = @splat('x');
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = &junk });
    try t.expect(try cache.lookupSyntax(t.allocator, module.src, module.header.body_start) == null);

    // An unknown key is a plain miss, not damage.
    files.bytes =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 5
    ;
    var changed = language.project.Project.init(t.allocator);
    defer changed.deinit();
    try load(&changed, &files);
    const changed_module = changed.modules.items[0];
    try t.expect(try cache.lookupSyntax(t.allocator, changed_module.src, changed_module.header.body_start) == null);
}

// spec-case: FRONTEND-CACHE-1
test "unreadable entries and unwritable directories degrade to misses" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    var files: Files = .{};
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);

    // Replace the stored entry file with a directory: opening it for reading fails,
    // which lookupSyntax reports as a miss rather than a host failure.
    const key = cache.syntaxKey(module.src, module.header.body_start);
    const path = try cache.entryPath(key);
    defer t.allocator.free(path);
    try std.Io.Dir.cwd().deleteFile(t.io, path);
    try std.Io.Dir.cwd().createDir(t.io, path, .default_dir);
    try t.expectError(error.ReadFailed, cache.read(key));
    try t.expect(try cache.lookupSyntax(t.allocator, module.src, module.header.body_start) == null);
    try t.expectEqual(@as(usize, 0), cache.statistics.syntax.hits);

    // A root below a parent that is a regular file cannot be created; the store
    // fails rather than publishing a partial entry.
    const plain_file = try std.fs.path.join(t.allocator, &.{ root, "plain-file" });
    defer t.allocator.free(plain_file);
    const missing_parent = try std.fs.path.join(t.allocator, &.{ plain_file, "nested" });
    defer t.allocator.free(missing_parent);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = plain_file, .data = "x" });
    var blocked = Cache.init(t.allocator, t.io, missing_parent, "test-identity");
    try t.expectError(error.WriteFailed, blocked.write(cache.syntaxKey(module.src, module.header.body_start), "payload"));
}

// spec-case: FRONTEND-CACHE-1
test "single-file check stores and reuses parsed syntax through the same cache" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    const bytes =
        \\def main() -> i64:
        \\    return 41
    ;
    // `check`, `run` and `emit-qbe` all reach the parser through Compilation, so
    // their reuse path must store and hit under body start 0.
    var first = try language.Compilation.init(t.allocator, "single.my", bytes);
    defer first.deinit();
    try first.checkWithFrontend(&cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.stored);
    const nodes = first.syntax.?.nodes.items.len;

    var second = try language.Compilation.init(t.allocator, "single.my", bytes);
    defer second.deinit();
    try second.checkWithFrontend(&cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.hits);
    // The cold lookup is the only miss; the second invocation parses nothing.
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.misses);
    try t.expectEqual(nodes, second.syntax.?.nodes.items.len);
}

// spec: FRONTEND-CACHE-3
test "cached syntax retains expression lambdas across a warm lookup" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var caller = std.heap.ArenaAllocator.init(t.allocator);
    defer caller.deinit();
    var cache = openCache(root);
    var files: Files = .{ .bytes =
        \\module main
        \\
        \\
        \\def apply(callback: def(int) -> int effects(), value: int) -> int:
        \\    return callback(value)
        \\
        \\
        \\def main() -> int:
        \\    return apply(lambda value: value * 2, 21)
    };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);
    const hit = (try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)).?;
    try t.expectEqual(@as(usize, 1), hit.lambdas.len);
}

fn syntaxSpan(bytes: []const u8, needle: []const u8) source.Span {
    const at = std.mem.indexOf(u8, bytes, needle) orelse return .{ .start = bytes.len, .end = bytes.len };
    return .{ .start = at, .end = at + needle.len };
}

// spec: NAMED-CONSTRAINT-CACHE-1
test "frontend cache retains named constraints across a syntax round trip" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var caller = std.heap.ArenaAllocator.init(t.allocator);
    defer caller.deinit();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var cache = openCache(root);
    const bytes = "constraint Prices[P] = copy;";
    const src = try source.Source.init(allocator, "main.my", bytes);
    const requirements = try allocator.dupe(source.Span, &.{syntaxSpan(bytes, "copy")});
    const constraints = try allocator.alloc(ast.Constraint, 1);
    constraints[0] = .{
        .name = syntaxSpan(bytes, "Prices"),
        .span = syntaxSpan(bytes, "constraint Prices[P] = copy"),
        .subject = .{
            .name = syntaxSpan(bytes, "P"),
            .requirements = requirements,
        },
    };
    const program: ast.Program = .{
        .types = .{ .constraints = constraints },
        .nodes = .empty,
        .statements = .empty,
        .functions = &.{},
        .lambdas = &.{},
    };
    try cache.rememberSyntax(src, 0, program);
    const hit = (try cache.lookupSyntax(caller.allocator(), src, 0)).?;
    try t.expectEqual(@as(usize, 1), hit.types.constraints.len);
    try t.expectEqualStrings("Prices", src.text(hit.types.constraints[0].name));
    try t.expectEqualStrings("P", src.text(hit.types.constraints[0].subject.name));
    try t.expectEqual(@as(usize, 1), hit.types.constraints[0].subject.requirements.len);
    try t.expectEqualStrings("copy", src.text(hit.types.constraints[0].subject.requirements[0]));
}

// spec-case: INCREMENTAL-KEYS-1
test "frontend cache contract dimensions invalidate syntax and verdict keys for identical sources" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var caller = std.heap.ArenaAllocator.init(t.allocator);
    defer caller.deinit();
    var files: Files = .{};
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];

    var cache = Cache.initWithContract(t.allocator, t.io, root, "test-identity", cache_key.Contract.default);
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);
    try cache.rememberVerdict(&project, .text, "warning\n");
    try t.expect((try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)) != null);
    const warnings = (try cache.lookupVerdict(t.allocator, &project, .text)).?;
    defer t.allocator.free(warnings);
    try t.expectEqualStrings("warning\n", warnings);

    const base = cache_key.Contract.default;
    var variants: [6]cache_key.Contract = .{ base, base, base, base, base, base };
    variants[0].bootstrap_language = "bootstrap-v2";
    variants[1].target = "wasm32";
    variants[2].runtime_abi = "runtime-abi-v1";
    variants[3].effects = "effects-v2";
    variants[4].flags = "--release";
    variants[5].compiler_identity = "sha256:deadbeef";
    const unchanged_key = cache.syntaxKey(module.src, module.header.body_start);
    for (variants) |variant| {
        var changed = Cache.initWithContract(t.allocator, t.io, root, "test-identity", variant);
        defer changed.deinit();
        try t.expect(try changed.lookupSyntax(caller.allocator(), module.src, module.header.body_start) == null);
        try t.expect(try changed.lookupVerdict(t.allocator, &project, .text) == null);
        const changed_key = changed.syntaxKey(module.src, module.header.body_start);
        try t.expect(!std.mem.eql(u8, &unchanged_key, &changed_key));
        try t.expect(!cache_key.Contract.eql(cache_key.Contract.default, variant));
    }

    // An identical contract in a fresh cache instance is still a hit.
    var same = Cache.initWithContract(t.allocator, t.io, root, "test-identity", cache_key.Contract.default);
    defer same.deinit();
    try t.expect((try same.lookupSyntax(caller.allocator(), module.src, module.header.body_start)) != null);
    const same_warnings = (try same.lookupVerdict(t.allocator, &project, .text)).?;
    defer t.allocator.free(same_warnings);
    try t.expectEqualStrings("warning\n", same_warnings);
}
