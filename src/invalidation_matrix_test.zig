//! Wave 3 clean-vs-warm invalidation matrix.
//!
//! Every case runs the edited program twice: once with fresh caches (clean) and
//! once after populating the semantic and syntax caches with the base program
//! (warm). Both runs must agree on acceptance, diagnostic JSON, the checked
//! interface manifest, normalized QBE, and the exact reuse/check counts.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const cache_key = @import("cache_key.zig");
const schema_graph = @import("schema_graph.zig");
const File = language.embedded_project.File;
const Cache = language.semantic_cache.Cache;
const SyntaxCache = language.syntax_cache.Cache;
const FrontendCache = language.frontend_cache.Cache;

const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

const Outcome = struct {
    accepted: bool,
    diagnostics: []const u8,
    manifest: ?[]const u8,
    manifest_error: ?anyerror,

    fn deinit(self: Outcome, allocator: std.mem.Allocator) void {
        allocator.free(self.diagnostics);
        if (self.manifest) |value| allocator.free(value);
    }
};

const Delta = struct { reused: usize, checked: usize };

/// One matrix row: the inputs plus the exact reuse/check deltas it must show.
const Case = struct {
    name: []const u8,
    base: []const File,
    edited: []const File,
    accepted: bool,
    reused: usize,
    checked: usize,
};

fn evaluate(
    allocator: std.mem.Allocator,
    entries: []const File,
    semantic: ?*Cache,
    syntax: ?*SyntaxCache,
    frontend: ?*FrontendCache,
) !Outcome {
    var files: Files = .{ .entries = entries };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.buildWithCache(&project, syntax, frontend);
    var compilation = try language.project_compile.Compilation.init(&index);
    var accepted = true;
    compilation.checkWithCache(semantic) catch |err| switch (err) {
        error.SourceError => accepted = false,
        else => return err,
    };
    var diagnostics: std.ArrayList(u8) = .empty;
    defer diagnostics.deinit(allocator);
    for (compilation.diagnostics.items.items) |diag| {
        const json = try language.diagnostic_output.render(allocator, diag, compilation.src, .json);
        defer allocator.free(json);
        try diagnostics.appendSlice(allocator, json);
        try diagnostics.append(allocator, '\n');
    }
    if (!accepted) {
        // A rejected program must fail the same exported manifest query on both sides.
        var manifest_error: ?anyerror = null;
        if (compilation.exportRoots(allocator)) |_| {} else |err| manifest_error = err;
        return .{ .accepted = false, .diagnostics = try diagnostics.toOwnedSlice(allocator), .manifest = null, .manifest_error = manifest_error };
    }
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    const manifest = try schema_graph.render(allocator, compilation.index, compilation.program.?, roots);
    return .{ .accepted = true, .diagnostics = try diagnostics.toOwnedSlice(allocator), .manifest = manifest, .manifest_error = null };
}

fn sameOptional(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}

const base_main =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const whitespace_outside =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const whitespace_inside =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return  n + 1
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const comment_outside =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\# a comment between declarations
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const comment_inside =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    # a comment inside the helper body
    \\    return n + 1
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const private_body =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 2
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const rejected_signature =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\public def api(n: bool) -> i64:
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const exported_signature =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\public def api(n: i64, scale: i64) -> i64 effects():
    \\    return helper(n) * scale
    \\
    \\
    \\def main() -> i64:
    \\    return api(41, 2)
;

const effect_bound =
    \\module main
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\public def api(clock: Clock, n: i64) -> i64 effects(clock):
    \\    _ = clock
    \\    return helper(n)
    \\
    \\
    \\def main(clock: Clock) -> i64:
    \\    return api(clock, 41)
;

const constant_base =
    \\module main
    \\
    \\
    \\const STEP: i64 = 1
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + STEP
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const constant_edited =
    \\module main
    \\
    \\
    \\const STEP: i64 = 2
    \\
    \\def helper(n: i64) -> i64:
    \\    return n + STEP
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const record_base =
    \\module main
    \\
    \\
    \\record Point:
    \\    x: i64
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    p = Point(x=n)
    \\    return p.x + 1
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const record_edited =
    \\module main
    \\
    \\
    \\record Point:
    \\    x: i64
    \\    y: i64
    \\
    \\
    \\def helper(n: i64) -> i64:
    \\    p = Point(x=n, y=n)
    \\    return p.x + p.y
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const union_base =
    \\module main
    \\
    \\
    \\public enum Choice:
    \\    first,
    \\    second
    \\
    \\
    \\def helper(c: Choice) -> i64:
    \\    match c:
    \\        case Choice.first:
    \\            return 1
    \\        case Choice.second:
    \\            return 2
    \\
    \\
    \\public def api(c: Choice) -> i64 effects():
    \\    return helper(c)
    \\
    \\
    \\def main() -> i64:
    \\    return api(Choice.first)
;

const union_edited =
    \\module main
    \\
    \\
    \\public enum Choice:
    \\    first,
    \\    second,
    \\    third
    \\
    \\
    \\def helper(c: Choice) -> i64:
    \\    match c:
    \\        case Choice.first:
    \\            return 1
    \\        case Choice.second:
    \\            return 2
    \\        case Choice.third:
    \\            return 3
    \\
    \\
    \\public def api(c: Choice) -> i64 effects():
    \\    return helper(c)
    \\
    \\
    \\def main() -> i64:
    \\    return api(Choice.first)
;

const import_base_data =
    \\module data
    \\
    \\
    \\public def value() -> i64 effects():
    \\    return 42
;

const import_base_main =
    \\module main
    \\import data
    \\
    \\
    \\def main() -> i64:
    \\    return data.value()
;

const import_extra =
    \\module extra
    \\
    \\
    \\public def one() -> i64 effects():
    \\    return 1
;

const import_edited_main =
    \\module main
    \\import data
    \\import extra
    \\
    \\
    \\def main() -> i64:
    \\    return data.value() + extra.one()
;

const generic_base =
    \\module main
    \\
    \\
    \\def id[T](n: T) -> T:
    \\    return n
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return id[i64](n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const generic_edited =
    \\module main
    \\
    \\
    \\def id[T](n: T) -> T:
    \\    value = n
    \\    return value
    \\
    \\
    \\public def api(n: i64) -> i64 effects():
    \\    return id[i64](n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

const specialization_base =
    \\module main
    \\
    \\
    \\def size[const N: u64]() -> u64:
    \\    return N
    \\
    \\
    \\public def api() -> i64 effects():
    \\    return i64(size[2]())
    \\
    \\
    \\def main() -> i64:
    \\    return api()
;

const specialization_edited =
    \\module main
    \\
    \\
    \\def size[const N: u64]() -> u64:
    \\    return N
    \\
    \\
    \\public def api() -> i64 effects():
    \\    return i64(size[3]())
    \\
    \\
    \\def main() -> i64:
    \\    return api()
;

fn single(bytes: []const u8) [1]File {
    return .{.{ .path = "main.my", .bytes = bytes }};
}

fn expectCase(allocator: std.mem.Allocator, case: Case) !void {
    var semantic = Cache.init(allocator, 8 * 1024 * 1024);
    defer semantic.deinit();
    var syntax = SyntaxCache.init(allocator, .{});
    defer syntax.deinit();

    var base_out = try evaluate(allocator, case.base, &semantic, &syntax, null);
    defer base_out.deinit(allocator);
    try t.expect(base_out.accepted);

    var clean = try evaluate(allocator, case.edited, null, null, null);
    defer clean.deinit(allocator);
    const reused_before = semantic.statistics.reused;
    const checked_before = semantic.statistics.checked;
    var warm = try evaluate(allocator, case.edited, &semantic, &syntax, null);
    defer warm.deinit(allocator);
    const observed = Delta{
        .reused = semantic.statistics.reused - reused_before,
        .checked = semantic.statistics.checked - checked_before,
    };

    try t.expectEqual(clean.accepted, warm.accepted);
    try t.expectEqual(case.accepted, warm.accepted);
    try t.expectEqualStrings(clean.diagnostics, warm.diagnostics);
    try t.expect(sameOptional(clean.manifest, warm.manifest));
    try t.expectEqual(clean.manifest_error, warm.manifest_error);
    if (warm.accepted) {}
    try t.expectEqual(case.reused, observed.reused);
    try t.expectEqual(case.checked, observed.checked);
}

fn runMatrix() !void {
    const base = single(base_main);
    const ws_out = single(whitespace_outside);
    const ws_in = single(whitespace_inside);
    const comment_out = single(comment_outside);
    const comment_in = single(comment_inside);
    const private_body_file = single(private_body);
    const signature = single(exported_signature);
    const rejected = single(rejected_signature);
    const effects = single(effect_bound);
    const constant_b = single(constant_base);
    const constant_e = single(constant_edited);
    const record_b = single(record_base);
    const record_e = single(record_edited);
    const union_b = single(union_base);
    const union_e = single(union_edited);
    const generic_b = single(generic_base);
    const generic_e = single(generic_edited);
    const spec_b = single(specialization_base);
    const spec_e = single(specialization_edited);
    const import_b = [2]File{
        .{ .path = "main.my", .bytes = import_base_main },
        .{ .path = "data.my", .bytes = import_base_data },
    };
    const import_e = [3]File{
        .{ .path = "main.my", .bytes = import_edited_main },
        .{ .path = "data.my", .bytes = import_base_data },
        .{ .path = "extra.my", .bytes = import_extra },
    };

    const cases = [_]Case{
        .{ .name = "whitespace outside", .base = &base, .edited = &ws_out, .accepted = true, .reused = 3, .checked = 0 },
        .{ .name = "whitespace inside", .base = &base, .edited = &ws_in, .accepted = true, .reused = 2, .checked = 1 },
        .{ .name = "comment outside", .base = &base, .edited = &comment_out, .accepted = true, .reused = 3, .checked = 0 },
        .{ .name = "comment inside", .base = &base, .edited = &comment_in, .accepted = true, .reused = 2, .checked = 1 },
        .{ .name = "private body", .base = &base, .edited = &private_body_file, .accepted = true, .reused = 2, .checked = 1 },
        .{ .name = "exported signature", .base = &base, .edited = &signature, .accepted = true, .reused = 1, .checked = 2 },
        .{ .name = "rejected exported signature", .base = &base, .edited = &rejected, .accepted = false, .reused = 1, .checked = 2 },
        .{ .name = "effect bound", .base = &base, .edited = &effects, .accepted = true, .reused = 1, .checked = 2 },
        .{ .name = "constant value", .base = &constant_b, .edited = &constant_e, .accepted = true, .reused = 2, .checked = 2 },
        .{ .name = "record field shape", .base = &record_b, .edited = &record_e, .accepted = true, .reused = 2, .checked = 1 },
        .{ .name = "union shape", .base = &union_b, .edited = &union_e, .accepted = true, .reused = 0, .checked = 3 },
        .{ .name = "import list", .base = &import_b, .edited = &import_e, .accepted = true, .reused = 1, .checked = 2 },
        .{ .name = "generic template body", .base = &generic_b, .edited = &generic_e, .accepted = true, .reused = 1, .checked = 2 },
        .{ .name = "specialization argument", .base = &spec_b, .edited = &spec_e, .accepted = true, .reused = 1, .checked = 2 },
    };
    for (cases) |case| try expectCase(t.allocator, case);
}

// spec: INVALIDATION-MATRIX-1
test "invalidation matrix clean and warm results agree with exact reuse deltas" {
    try runMatrix();
}

const single_source =
    \\def helper(n: i64) -> i64:
    \\    return n + 1
    \\
    \\
    \\def api(n: i64) -> i64:
    \\    return helper(n)
    \\
    \\
    \\def main() -> i64:
    \\    return api(41)
;

fn checkSingle(allocator: std.mem.Allocator, cache: *Cache, bytes: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "matrix.my", bytes);
    defer compilation.deinit();
    try compilation.checkWithCache(cache);
}

// The runtime ABI and compiler-version proof: identical source, identical
// `semantic_cache` instance, only the contract fingerprint changes.
// spec-case: INVALIDATION-MATRIX-1
test "invalidation matrix runtime abi and compiler identity are required cache keys" {
    var cache = Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    const abi_fp = try cache_key.Contract.default.fingerprint(t.allocator);
    defer t.allocator.free(abi_fp);
    cache.context.contract = abi_fp;
    try checkSingle(t.allocator, &cache, single_source);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);
    try checkSingle(t.allocator, &cache, single_source);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(@as(usize, 3), cache.statistics.checked);

    var abi_changed = cache_key.Contract.default;
    abi_changed.runtime_abi = "runtime-abi-v4";
    const changed_abi_fp = try abi_changed.fingerprint(t.allocator);
    defer t.allocator.free(changed_abi_fp);
    cache.context.contract = changed_abi_fp;
    try checkSingle(t.allocator, &cache, single_source);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(@as(usize, 6), cache.statistics.checked);

    var compiler_changed = cache_key.Contract.default;
    compiler_changed.compiler_identity = "sha256:changed";
    const changed_compiler_fp = try compiler_changed.fingerprint(t.allocator);
    defer t.allocator.free(changed_compiler_fp);
    cache.context.contract = changed_compiler_fp;
    try checkSingle(t.allocator, &cache, single_source);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(@as(usize, 9), cache.statistics.checked);

    // Returning to the ABI contract is still a miss until its entry is published,
    // then identical work is reused again.
    cache.context.contract = changed_abi_fp;
    try checkSingle(t.allocator, &cache, single_source);
    try t.expectEqual(@as(usize, 3), cache.statistics.reused);
    try t.expectEqual(@as(usize, 12), cache.statistics.checked);
    try checkSingle(t.allocator, &cache, single_source);
    try t.expectEqual(@as(usize, 6), cache.statistics.reused);
    try t.expectEqual(@as(usize, 12), cache.statistics.checked);
}

// The frontend cache's compiler-identity dimension is proven in
// frontend_cache_test.zig; here the damaged-entry fallback is checked end to end.
// spec-case: INVALIDATION-MATRIX-1
test "invalidation matrix damaged frontend entries recompute the clean program" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var cache = FrontendCache.init(t.allocator, t.io, root, "matrix-identity");
    var first = try language.Compilation.init(t.allocator, "matrix.my", single_source);
    defer first.deinit();
    try first.checkWithFrontend(&cache);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.stored);

    const key = cache.syntaxKey(first.src, 0);
    const path = try cache.entryPath(key);
    defer t.allocator.free(path);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = "damaged entry" });
    const damaged_before = cache.statistics.damaged;

    var warm = try language.Compilation.init(t.allocator, "matrix.my", single_source);
    defer warm.deinit();
    try warm.checkWithFrontend(&cache);
    try t.expectEqual(damaged_before + 1, cache.statistics.damaged);

    var fresh = try language.Compilation.init(t.allocator, "matrix.my", single_source);
    defer fresh.deinit();
    try fresh.check();
    try t.expectEqual(fresh.diagnostics.items.len, warm.diagnostics.items.len);
    for (fresh.diagnostics.items, warm.diagnostics.items) |a, b| {
        const left = try language.diagnostic_output.render(t.allocator, a, fresh.src, .json);
        defer t.allocator.free(left);
        const right = try language.diagnostic_output.render(t.allocator, b, warm.src, .json);
        defer t.allocator.free(right);
        try t.expectEqualStrings(left, right);
    }
}
