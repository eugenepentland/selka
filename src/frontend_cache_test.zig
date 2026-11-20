//! Persistent frontend cache reuse, invalidation, damage and retention.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const cache_key = @import("cache_key.zig");
const shared_artifacts = @import("shared_artifact_store.zig");
const Cache = language.frontend_cache.Cache;

const Files = struct {
    bytes: []const u8 =
        \\
        \\
        \\func main() -> i64:
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

// spec-case: COMPILER-SHARED-CACHE-1
test "shared frontend syntax crosses absolute roots while verdicts stay private" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const left = try std.fs.path.join(t.allocator, &.{ root, "left" });
    defer t.allocator.free(left);
    const right = try std.fs.path.join(t.allocator, &.{ root, "right" });
    defer t.allocator.free(right);
    const shared_root = try std.fs.path.join(t.allocator, &.{ root, "shared" });
    defer t.allocator.free(shared_root);
    var shared = try shared_artifacts.Store.open(t.allocator, t.io, shared_root);
    defer shared.deinit();
    var writer = openCache(left);
    defer writer.deinit();
    writer.setSharedStore(&shared);
    var reader = openCache(right);
    defer reader.deinit();
    reader.setSharedStore(&shared);
    var original = try language.Compilation.init(t.allocator, left, "func main() -> i64:\n    return 7\n");
    defer original.deinit();
    try original.parseCached(&writer);
    var moved = try language.Compilation.init(t.allocator, right, original.src.bytes);
    defer moved.deinit();
    try moved.parseCached(&reader);
    try t.expectEqual(@as(usize, 1), reader.statistics.syntax.hits);
    try t.expectEqual(@as(usize, 0), reader.statistics.syntax.misses);
    try t.expectEqualStrings("main", moved.src.text(moved.syntax.?.functions[0].name));
    try t.expectError(error.NotFound, reader.read(reader.syntaxKey(moved.src, 0)));
    var files: Files = .{};
    var loaded = language.project.Project.init(t.allocator);
    defer loaded.deinit();
    try load(&loaded, &files);
    try writer.rememberVerdict(&loaded, .text, "left-root warning\n");
    try t.expect(try reader.lookupVerdict(t.allocator, &loaded, .text) == null);
}

/// A project of the given module sources, each file read by name.
const Tree = struct {
    entries: []const struct { path: []const u8, bytes: []const u8 },
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Tree = @ptrCast(@alignCast(context.?));
        for (self.entries) |entry| if (std.mem.eql(u8, entry.path, path)) return allocator.dupe(u8, entry.bytes);
        return error.NotFound;
    }
};
fn loadTree(project: *language.project.Project, tree: *Tree) !void {
    try project.load(.{ .context = tree, .read = Tree.read }, "main", .{});
}
const tree_head = "import util\n\nfunc main() -> i64:\n    return util.one()\n";
const util_one = "func one() -> i64:\n    return 1\n";

test "a summary table another worktree published is served to a fresh work directory of the same project and to no other project" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const left = try std.fs.path.join(t.allocator, &.{ root, "left" });
    defer t.allocator.free(left);
    const right = try std.fs.path.join(t.allocator, &.{ root, "right" });
    defer t.allocator.free(right);
    const other = try std.fs.path.join(t.allocator, &.{ root, "other" });
    defer t.allocator.free(other);
    const shared_root = try std.fs.path.join(t.allocator, &.{ root, "shared" });
    defer t.allocator.free(shared_root);
    var shared = try shared_artifacts.Store.open(t.allocator, t.io, shared_root);
    defer shared.deinit();
    var writer = openCache(left);
    defer writer.deinit();
    writer.setSharedStore(&shared);
    var reader = openCache(right);
    defer reader.deinit();
    reader.setSharedStore(&shared);
    var stranger = openCache(other);
    defer stranger.deinit();
    stranger.setSharedStore(&shared);

    var first: Tree = .{ .entries = &.{ .{ .path = "main.selka", .bytes = tree_head }, .{ .path = "util.selka", .bytes = util_one } } };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try loadTree(&project, &first);
    try writer.rememberSummaries(&project, "the table of the first worktree");
    // The same project in a fresh work directory, with another body in `util`: the table is served, and the work directory is still empty.
    var edited: Tree = .{ .entries = &.{ .{ .path = "main.selka", .bytes = tree_head }, .{ .path = "util.selka", .bytes = "func one() -> i64:\n    return 2\n" } } };
    var moved = language.project.Project.init(t.allocator);
    defer moved.deinit();
    try loadTree(&moved, &edited);
    try t.expectError(error.NotFound, reader.read(reader.summariesKey(&moved).?));
    const served = (try reader.lookupSummaries(&moved)).?;
    defer t.allocator.free(served);
    try t.expectEqualStrings("the table of the first worktree", served);
    // A project with the same entry name and path and another set of modules gets a slot of its own, and an edit keeps the slot.
    var different: Tree = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = "import util\nimport extra\n\nfunc main() -> i64:\n    return util.one() + extra.two()\n" },
        .{ .path = "util.selka", .bytes = util_one },
        .{ .path = "extra.selka", .bytes = "func two() -> i64:\n    return 2\n" },
    } };
    var neighbour = language.project.Project.init(t.allocator);
    defer neighbour.deinit();
    try loadTree(&neighbour, &different);
    try t.expectEqual(reader.summariesKey(&project).?, reader.summariesKey(&neighbour).?);
    try t.expectEqual(reader.sharedSummariesKeyForTest(&project), reader.sharedSummariesKeyForTest(&moved));
    try t.expect(!std.mem.eql(u8, &reader.sharedSummariesKeyForTest(&project), &reader.sharedSummariesKeyForTest(&neighbour)));
    try t.expect(try stranger.lookupSummaries(&neighbour) == null);
    // The newer table replaces the older one, whoever wrote it, and a library check's slot is never shared.
    try reader.rememberSummaries(&moved, "the table of the second worktree");
    const latest = (try stranger.lookupSummaries(&project)).?;
    defer t.allocator.free(latest);
    try t.expectEqualStrings("the table of the second worktree", latest);
    try writer.rememberSummariesIn(&project, .{ .library = "lib/main.selka" }, "a library table");
    try t.expect(try stranger.lookupSummariesIn(&project, .{ .library = "lib/main.selka" }) == null);
}
test "a module's header facts another worktree stored are served to a work directory that has none" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const left = try std.fs.path.join(t.allocator, &.{ root, "left" });
    defer t.allocator.free(left);
    const right = try std.fs.path.join(t.allocator, &.{ root, "right" });
    defer t.allocator.free(right);
    const shared_root = try std.fs.path.join(t.allocator, &.{ root, "shared" });
    defer t.allocator.free(shared_root);
    var shared = try shared_artifacts.Store.open(t.allocator, t.io, shared_root);
    defer shared.deinit();
    var writer = openCache(left);
    defer writer.deinit();
    writer.setSharedStore(&shared);
    var reader = openCache(right);
    defer reader.deinit();
    reader.setSharedStore(&shared);
    const key: [32]u8 = @splat(7);
    const records = writer.records();
    records.store(records.context, key, "header facts");
    const fresh = reader.records();
    const found = fresh.fetch(fresh.context, t.allocator, key).?;
    defer t.allocator.free(found);
    try t.expectEqualStrings("header facts", found);
    // A cache under another compiler identity does not see it.
    var foreign = Cache.init(t.allocator, t.io, right, "another-identity");
    defer foreign.deinit();
    foreign.setSharedStore(&shared);
    const stranger = foreign.records();
    try t.expect(stranger.fetch(stranger.context, t.allocator, key) == null);
}

test "writeEntry stores a record into a namespace that exists and into one removed under the cache" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const left = try std.fs.path.join(t.allocator, &.{ root, "left" });
    defer t.allocator.free(left);
    var cache = openCache(left);
    defer cache.deinit();
    const records = cache.records();
    // The first record makes the namespace, the second finds it, and one stored after the namespace was removed makes it again.
    records.store(records.context, @splat(1), "one");
    records.store(records.context, @splat(2), "two");
    try std.Io.Dir.cwd().deleteTree(t.io, left);
    records.store(records.context, @splat(3), "three");
    const found = records.fetch(records.context, t.allocator, @splat(3)).?;
    defer t.allocator.free(found);
    try t.expectEqualStrings("three", found);
    try t.expect(records.fetch(records.context, t.allocator, @splat(1)) == null);
    // A root that is a file cannot hold the namespace: the write fails, it does not retry forever.
    try temporary.dir.writeFile(t.io, .{ .sub_path = "blocked", .data = "not a directory" });
    const blocked = try std.fs.path.join(t.allocator, &.{ root, "blocked" });
    defer t.allocator.free(blocked);
    var refused = openCache(blocked);
    defer refused.deinit();
    try t.expectError(error.WriteFailed, refused.write(@splat(9), "never stored"));
}

test "an executable entry and a library entry keep separate check summaries" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    defer cache.deinit();
    var files: Files = .{};
    var loaded = language.project.Project.init(t.allocator);
    defer loaded.deinit();
    try load(&loaded, &files);
    const entry_key = cache.summariesKeyIn(&loaded, .entry).?;
    const library_key = cache.summariesKeyIn(&loaded, .{ .library = "lib/main.selka" }).?;
    try t.expect(!std.mem.eql(u8, &entry_key, &library_key));
    // The same module under another directory is another library entry with a slot of its own.
    const copy_key = cache.summariesKeyIn(&loaded, .{ .library = "copy/main.selka" }).?;
    try t.expect(!std.mem.eql(u8, &library_key, &copy_key));
    try t.expectEqualSlices(u8, &entry_key, &cache.summariesKey(&loaded).?);
    try cache.rememberSummariesIn(&loaded, .{ .library = "lib/main.selka" }, "library table");
    try t.expect(try cache.lookupSummaries(&loaded) == null);
    const found = (try cache.lookupSummariesIn(&loaded, .{ .library = "lib/main.selka" })).?;
    defer t.allocator.free(found);
    try t.expectEqualStrings("library table", found);
    try cache.rememberSummaries(&loaded, "entry table");
    const kept = (try cache.lookupSummariesIn(&loaded, .{ .library = "lib/main.selka" })).?;
    defer t.allocator.free(kept);
    try t.expectEqualStrings("library table", kept);
}

test "a summary mark leaves the directory unscanned at the end of the run and a table does not" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    defer cache.deinit();
    var files: Files = .{};
    var loaded = language.project.Project.init(t.allocator);
    defer loaded.deinit();
    try load(&loaded, &files);
    try cache.markSummariesIn(&loaded, .{ .library = "lib/main.selka" }, "mark");
    cache.finish();
    try t.expectEqual(@as(usize, 0), cache.statistics.retained_bytes);
    const marked = (try cache.lookupSummariesIn(&loaded, .{ .library = "lib/main.selka" })).?;
    defer t.allocator.free(marked);
    try t.expectEqualStrings("mark", marked);
    try cache.rememberSummariesIn(&loaded, .{ .library = "lib/main.selka" }, "table");
    cache.finish();
    try t.expect(cache.statistics.retained_bytes > 0);
}

test "a syntax key from the module digest is the key of the bytes, and follows the bytes and the path" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    defer cache.deinit();
    var original = try language.Compilation.init(t.allocator, "left.selka", "func main() -> i64:\n    return 7\n");
    defer original.deinit();
    const digest = language.source_digest.of(original.src.bytes);
    try t.expectEqual(cache.syntaxKey(original.src, 0), cache.syntaxKeyOf(original.src, digest, 0));
    var other_bytes = original.src;
    other_bytes.bytes = "func main() -> i64:\n    return 8\n";
    try t.expect(!std.mem.eql(u8, &cache.syntaxKey(original.src, 0), &cache.syntaxKey(other_bytes, 0)));
    var other_path = original.src;
    other_path.path = "right.selka";
    try t.expect(!std.mem.eql(u8, &cache.syntaxKey(original.src, 0), &cache.syntaxKey(other_path, 0)));
    try t.expect(!std.mem.eql(u8, &cache.syntaxKey(original.src, 0), &cache.syntaxKey(original.src, 1)));
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared frontend syntax rejects changed inputs and parser authority" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const local = try std.fs.path.join(t.allocator, &.{ root, "local" });
    defer t.allocator.free(local);
    var shared = try shared_artifacts.Store.open(t.allocator, t.io, root);
    defer shared.deinit();
    var cache = openCache(local);
    defer cache.deinit();
    cache.setSharedStore(&shared);
    var original = try language.Compilation.init(t.allocator, "left.selka", "func main() -> i64:\n    return 7\n");
    defer original.deinit();
    try original.parseCached(&cache);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var changed = original.src;
    changed.path = "right.selka";
    try t.expect((try cache.lookupSyntax(arena.allocator(), changed, 0)) != null);
    try t.expect(try cache.lookupSyntax(arena.allocator(), changed, 1) == null);
    changed.bytes = "func main() -> i64:\n    return 8\n";
    try t.expect(try cache.lookupSyntax(arena.allocator(), changed, 0) == null);
    changed.bytes = original.src.bytes;
    changed.trusted_intrinsics = true;
    try t.expect(try cache.lookupSyntax(arena.allocator(), changed, 0) == null);
    changed.trusted_intrinsics = false;
    changed.path = "@stdlib/right.selka";
    try t.expect(try cache.lookupSyntax(arena.allocator(), changed, 0) == null);
    changed.path = "right.selka";
    cache.identity = "another-compiler";
    try t.expect(try cache.lookupSyntax(arena.allocator(), changed, 0) == null);
    cache.identity = "test-identity";
    const base = cache_key.Contract.default;
    var variants: [6]cache_key.Contract = .{ base, base, base, base, base, base };
    variants[0].bootstrap_language = "changed";
    variants[1].target = "changed";
    variants[2].runtime_abi = "changed";
    variants[3].capabilities = "changed";
    variants[4].flags = "changed";
    variants[5].compiler_identity = "changed";
    for (variants) |variant| {
        cache.contract = variant;
        try t.expect(try cache.lookupSyntax(arena.allocator(), changed, 0) == null);
    }
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
        \\
        \\
        \\func main() -> i64:
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
        \\
        \\
        \\func main() -> i64:
        \\    return 3
    ;
    var changed = language.project.Project.init(t.allocator);
    defer changed.deinit();
    try load(&changed, &files);
    try t.expect(try cache.lookupVerdict(t.allocator, &changed, .text) == null);
}

// spec-case: POLICY-IDENTITY-OWNED-1
test "frontend verdict keys fold an owned policy identity, not the caller's buffer" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    defer cache.deinit();
    var files: Files = .{};
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    // Scribbling the caller's buffer after publishing it must not move the key.
    var buffer: [64]u8 = @splat('a');
    try cache.setPolicyIdentity(&buffer);
    try cache.rememberVerdict(&project, .text, "warning: policy\n");
    buffer = @splat('z');
    const warnings = (try cache.lookupVerdict(t.allocator, &project, .text)).?;
    defer t.allocator.free(warnings);
    try t.expectEqualStrings("warning: policy\n", warnings);
    // A different identity, or none, is a different key.
    try cache.setPolicyIdentity(&buffer);
    try t.expect(try cache.lookupVerdict(t.allocator, &project, .text) == null);
    try cache.setPolicyIdentity(null);
    try t.expect(try cache.lookupVerdict(t.allocator, &project, .text) == null);
}

// spec: CACHE-CHECKSUM-1
test "an entry whose payload changed under an intact header fails its checksum" {
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
    const key = cache.syntaxKey(module.src, module.header.body_start);
    const path = try cache.entryPath(key);
    defer t.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .unlimited);
    defer t.allocator.free(bytes);
    // The payload sits between the 44-byte header and the 8-byte checksum.
    bytes[bytes.len - 9] ^= 0xff;
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
    try t.expectError(error.Damaged, cache.read(key));
    try t.expect(try cache.lookupSyntax(t.allocator, module.src, module.header.body_start) == null);
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
        \\
        \\
        \\func main() -> i64:
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
        \\func main() -> i64:
        \\    return 41
    ;
    // `check`, `run` and `emit-qbe` all reach the parser through Compilation, so
    // their reuse path must store and hit under body start 0.
    var first = try language.Compilation.init(t.allocator, "single.selka", bytes);
    defer first.deinit();
    try first.checkWithFrontend(&cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.stored);
    const nodes = first.syntax.?.nodes.items.len;

    var second = try language.Compilation.init(t.allocator, "single.selka", bytes);
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
    var files: Files = .{
        .bytes =
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\
        \\
        \\func apply(callback: func(int) -> int effects(), value: int) -> int:
        \\    return callback(value)
        \\
        \\
        \\func main() -> int:
        \\    return apply(lambda value: value * 2, 21)
    };
    var original_project = language.project.Project.init(t.allocator);
    defer original_project.deinit();
    try load(&original_project, &files);
    try t.expectError(error.SourceError, language.interfaces.buildWithCache(&original_project, null, null));
    try t.expect(original_project.problem != null);
    try t.expectEqualStrings("E_EFFECTS_REMOVED", original_project.problem.?.code);
    const modern = try std.mem.replaceOwned(u8, t.allocator, files.bytes, " effects()", "");
    defer t.allocator.free(modern);
    files.bytes = modern;
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try load(&project, &files);
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);
    const hit = (try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)).?;
    try t.expectEqual(@as(usize, 1), hit.lambdas.len);
    try t.expectEqualStrings("lambda value: value * 2", module.src.text(hit.lambdas[0].span));
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
    const src = try source.Source.init(allocator, "main.selka", bytes);
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
    variants[2].runtime_abi = "runtime-abi-v4";
    variants[3].capabilities = "capabilities-v0";
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

// spec: FRONTEND-CACHE-ENTRY-1
test "the frontend cache admits an entry as large as the loaded project needs" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const payload: [1500]u8 = @splat('s');
    var cache = openCache(root);
    cache.max_bytes = 1000;
    // Over the configured ceiling, the entry is bypassed rather than stored...
    try t.expect(!try cache.write(retentionKey(0), &payload));
    // ...until the cache is fitted to a project whose source makes it plausible.
    cache.fitProject(200);
    try t.expectEqual(@as(usize, 200 * language.frontend_cache.entry_bytes_per_source_byte), cache.max_bytes);
    try t.expect(try cache.write(retentionKey(0), &payload));
    const back = try cache.read(retentionKey(0));
    defer t.allocator.free(back);
    try t.expectEqualSlices(u8, &payload, back);
    // Fitting never lowers a ceiling already larger than the project needs.
    cache.fitProject(1);
    try t.expectEqual(@as(usize, 1600), cache.max_bytes);
}

/// The key of the `index`th retention-test entry.
fn retentionKey(index: usize) [32]u8 {
    var key: [32]u8 = @splat(0);
    key[0] = @intCast(index);
    return key;
}
/// Read the entries `first..last` back through `cache`, returning how many hit.
fn readBack(cache: *Cache, first: usize, last: usize) !usize {
    var hits: usize = 0;
    for (first..last) |index| {
        const payload = cache.read(retentionKey(index)) catch continue;
        t.allocator.free(payload);
        hits += 1;
    }
    return hits;
}
/// Age every stored retention entry to one fixed moment, so the next run's
/// uses are strictly newer whatever the file system's timestamp resolution.
fn age(cache: *Cache, count: usize) !void {
    for (0..count) |index| {
        const path = try cache.entryPath(retentionKey(index));
        defer t.allocator.free(path);
        try std.Io.Dir.cwd().setTimestamps(t.io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1_000_000_000 * std.time.ns_per_s } } });
    }
}
// spec: FRONTEND-CACHE-RETAIN-1
test "the frontend cache keeps a working set larger than its floor and evicts least recently used history" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const payload: [400]u8 = @splat('p');
    // A cold run stores eight entries, about 3.6 KB, against a 1,000-byte
    // floor: all of them are its working set, and none is evicted.
    var cold = openCache(root);
    cold.max_bytes = 1000;
    for (0..8) |index| try t.expect(try cold.write(retentionKey(index), &payload));
    cold.finish();
    try t.expectEqual(@as(usize, 0), cold.statistics.evicted);
    try t.expect(cold.retention() > cold.statistics.retained_bytes);
    // An unchanged rerun reads every entry and stores one more: nothing goes.
    var rerun = openCache(root);
    rerun.max_bytes = 1000;
    try t.expectEqual(@as(usize, 8), try readBack(&rerun, 0, 8));
    try t.expect(try rerun.write(retentionKey(8), &payload));
    rerun.finish();
    try t.expectEqual(@as(usize, 0), rerun.statistics.evicted);
    try age(&rerun, 9);
    // A run that uses two entries and stores one keeps twice what it used, and
    // the entries it used are the last to go: the others are evicted first.
    var narrow = openCache(root);
    narrow.max_bytes = 1000;
    try t.expectEqual(@as(usize, 2), try readBack(&narrow, 0, 2));
    try t.expect(try narrow.write(retentionKey(9), &payload));
    narrow.finish();
    try t.expect(narrow.statistics.evicted > 0);
    try t.expect(narrow.statistics.retained_bytes <= narrow.retention());
    var after = openCache(root);
    try t.expectEqual(@as(usize, 2), try readBack(&after, 0, 2));
    try t.expectEqual(@as(usize, 1), try readBack(&after, 9, 10));
    try t.expectEqual(@as(usize, 10) - narrow.statistics.evicted, try readBack(&after, 0, 10));
}

test "summary keys move with the policy identity, and the syntax and contract keys do not" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = openCache(root);
    defer cache.deinit();
    var files: Files = .{};
    var loaded = language.project.Project.init(t.allocator);
    defer loaded.deinit();
    try load(&loaded, &files);
    const module_source = loaded.modules.items[0].src;
    cache.setSummaryPolicy("whole identity before an ownership edit");
    const summary_before = cache.summariesKeyIn(&loaded, .entry).?;
    const syntax_before = cache.syntaxKey(module_source, 0);
    var contract_before: [64]u8 = undefined;
    cache.contract.fingerprintHex(&contract_before);
    cache.setSummaryPolicy("whole identity after an ownership edit");
    const summary_after = cache.summariesKeyIn(&loaded, .entry).?;
    const syntax_after = cache.syntaxKey(module_source, 0);
    var contract_after: [64]u8 = undefined;
    cache.contract.fingerprintHex(&contract_after);
    try t.expect(!std.mem.eql(u8, &summary_before, &summary_after));
    try t.expectEqualSlices(u8, &syntax_before, &syntax_after);
    try t.expectEqualSlices(u8, &contract_before, &contract_after);
}
