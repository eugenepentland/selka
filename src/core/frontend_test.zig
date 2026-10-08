//! Front-end adapter tests.
const std = @import("std");
const frontend = @import("frontend.zig");
const language = @import("mylang");
const typed_dump = @import("typed_dump.zig");

// spec: NEW-CORE-FRONTEND-1
test "an entry path splits into the loader root and module name, and offsets map to lines and columns" {
    const entry = frontend.entryOf("bench/kernels/int_math.my");
    try std.testing.expectEqualStrings("bench/kernels", entry.root);
    try std.testing.expectEqualStrings("int_math", entry.module);
    const bare = frontend.entryOf("main.my");
    try std.testing.expectEqualStrings(".", bare.root);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "p.my", "a = 1\nbb = 22\n");
    const at = frontend.position(src, .{ .start = 9, .end = 10 });
    try std.testing.expectEqual(@as(u32, 2), at.line);
    try std.testing.expectEqual(@as(u32, 4), at.column);
    try std.testing.expectEqualStrings("p.my", at.path);
}

const main_source =
    \\module main
    \\import lib
    \\
    \\def main() -> int:
    \\    return lib.change(4) + lib.keep(5)
    \\
;
const lib_source =
    \\module lib
    \\
    \\public def change(x: int) -> int:
    \\    return x + 1
    \\
    \\public def keep(x: int) -> int:
    \\    return x * 2
    \\
;
const edited_source =
    \\module lib
    \\
    \\public def change(x: int) -> int:
    \\    return x + 9
    \\
    \\public def keep(x: int) -> int:
    \\    return x * 2
    \\
;
const CheckOutcome = struct {
    text: []u8,
    work: frontend.Statistics,
    fn deinit(self: CheckOutcome, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
    }
};

fn checkProject(allocator: std.mem.Allocator, root: []const u8, cache: ?[]const u8, validation: bool) !CheckOutcome {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var session = frontend.Session.init(allocator, std.testing.io, root);
    defer session.deinit();
    if (cache) |directory| try session.enableCache(allocator, directory);
    if (validation) session.validationOnly();
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = try session.check(arena.allocator(), "main", &diagnostics);
    return .{
        .text = try typed_dump.render(allocator, checked.program, null),
        .work = session.statistics(),
    };
}

fn rejectedProject(allocator: std.mem.Allocator, root: []const u8, cache: ?[]const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var session = frontend.Session.init(allocator, std.testing.io, root);
    defer session.deinit();
    if (cache) |directory| try session.enableCache(allocator, directory);
    var diagnostics: std.ArrayList(u8) = .empty;
    _ = session.check(arena.allocator(), "main", &diagnostics) catch |err| switch (err) {
        error.SourceError => return allocator.dupe(u8, diagnostics.items),
        else => return err,
    };
    return error.ExpectedSourceError;
}

// spec: NEW-CORE-FRONTEND-CACHE-1
test "frontend durable typed body reuse with fact summaries preserves trees after one edit" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = lib_source });
    const cold = try checkProject(std.testing.allocator, root, cache, false);
    defer cold.deinit(std.testing.allocator);
    const warm = try checkProject(std.testing.allocator, root, cache, false);
    defer warm.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(cold.text, warm.text);
    try std.testing.expect(warm.work.reused > 0);
    try std.testing.expect(warm.work.syntax_hits == 2);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = edited_source });
    const edited = try checkProject(std.testing.allocator, root, cache, false);
    defer edited.deinit(std.testing.allocator);
    const fresh = try checkProject(std.testing.allocator, root, null, false);
    defer fresh.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(fresh.text, edited.text);
    try std.testing.expect(!std.mem.eql(u8, cold.text, edited.text));
    try std.testing.expect(edited.work.checked > 0);
    try std.testing.expect(edited.work.reused > 0);
}

// spec-case: NEW-CORE-FRONTEND-CACHE-1
test "frontend validation stands in summaries without hydrating trees needed by later builds" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = lib_source });
    const cold = try checkProject(std.testing.allocator, root, cache, false);
    defer cold.deinit(std.testing.allocator);
    const warm = try checkProject(std.testing.allocator, root, cache, true);
    defer warm.deinit(std.testing.allocator);
    const build = try checkProject(std.testing.allocator, root, cache, false);
    defer build.deinit(std.testing.allocator);
    try std.testing.expect(warm.work.summaries > 0);
    try std.testing.expect(build.work.reused > 0);
    try std.testing.expectEqualStrings(cold.text, build.text);
}

// spec-case: NEW-CORE-FRONTEND-CACHE-1
test "frontend reuse still diagnoses a changed imported signature exactly as fresh checking" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.my", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data = lib_source });
    const seed = try checkProject(std.testing.allocator, root, cache, false);
    defer seed.deinit(std.testing.allocator);
    try std.testing.expectError(error.ExpectedSourceError, rejectedProject(std.testing.allocator, root, null));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.my", .data =
        \\module lib
        \\
        \\public def change(x: str) -> int:
        \\    return len(x)
        \\
        \\public def keep(x: int) -> int:
        \\    return x * 2
        \\
    });
    const warm = try rejectedProject(std.testing.allocator, root, cache);
    defer std.testing.allocator.free(warm);
    const cold = try rejectedProject(std.testing.allocator, root, null);
    defer std.testing.allocator.free(cold);
    try std.testing.expectEqualStrings(cold, warm);
    try std.testing.expect(std.mem.indexOf(u8, warm, "change") != null);
}

// spec: NEW-CORE-PROJECT-FRONTEND-1
test "frontend nested project entry and source providers enforce fresh loader budgets" {
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, ".");
    defer session.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    session.configureProject(.{}, "pkg.entry");
    session.entry_suffix = "\n\ndef main() -> int:\n    return helper(3)\n";
    session.setProviders(&.{.{ .path = "pkg/entry.my", .text = "module pkg.entry\n\npublic def helper(x: int) -> int:\n    return x + 1\n" }});
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = try session.check(arena.allocator(), "pkg.entry", &diagnostics);
    try std.testing.expectEqualStrings("pkg/entry.my", session.entry_file);
    try std.testing.expectEqual(@as(usize, 1), session.interfaceIndex().units.len);
    try std.testing.expectEqual(@as(usize, 2), checked.program.functions.len);
    try std.testing.expectEqual(@as(usize, 64), frontend.compiler_identity.len);
    var limited = frontend.Session.init(std.testing.allocator, std.testing.io, ".");
    defer limited.deinit();
    limited.configureProject(.{ .max_file_bytes = 8 }, null);
    limited.setProviders(&.{.{ .path = "main.my", .text = main_source }});
    var rejected: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.SourceError, limited.check(arena.allocator(), "main", &rejected));
    try std.testing.expect(std.mem.indexOf(u8, rejected.items, "E_PROJECT_BYTES") != null);
}
