//! Frontend adapter regressions for loaded sources, durable body reuse and
//! allocation contracts across cold, warm and edited validation sessions.
const std = @import("std");
const frontend = @import("frontend.zig");
const language = @import("selka");
const typed_dump = @import("typed_dump.zig");
const options = @import("core_test_options");

// spec-case: NEW-CORE-FRONTEND-1
test "an invalid module name reports the name and the accepted rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, ".");
    defer session.deinit();
    var diagnostics: std.ArrayList(u8) = .empty;
    defer diagnostics.deinit(arena.allocator());
    try std.testing.expectError(error.SourceError, session.check(arena.allocator(), "bad-name", &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items, "bad-name") != null);
    try std.testing.expect(std.mem.indexOf(u8, diagnostics.items, "invalid module name") != null);
}

// spec: NEW-CORE-FRONTEND-1
test "an entry path splits into the loader root and module name, and offsets map to lines and columns" {
    const entry = frontend.entryOf("bench/kernels/int_math.selka");
    try std.testing.expectEqualStrings("bench/kernels", entry.root);
    try std.testing.expectEqualStrings("int_math", entry.module);
    const bare = frontend.entryOf("main.selka");
    try std.testing.expectEqualStrings(".", bare.root);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const src = try language.source.Source.init(arena.allocator(), "p.selka", "a = 1\nbb = 22\n");
    const at = frontend.position(src, .{ .start = 9, .end = 10 });
    try std.testing.expectEqual(@as(u32, 2), at.line);
    try std.testing.expectEqual(@as(u32, 4), at.column);
    try std.testing.expectEqualStrings("p.selka", at.path);
}

const main_source =
    \\import lib
    \\
    \\func main() -> int:
    \\    return lib.change(4) + lib.keep(5)
    \\
;
const lib_source =
    \\
    \\public func change(x: int) -> int:
    \\    return x + 1
    \\
    \\public func keep(x: int) -> int:
    \\    return x * 2
    \\
;
const edited_source =
    \\
    \\public func change(x: int) -> int:
    \\    return x + 9
    \\
    \\public func keep(x: int) -> int:
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    const cold = try checkProject(std.testing.allocator, root, cache, false);
    defer cold.deinit(std.testing.allocator);
    const warm = try checkProject(std.testing.allocator, root, cache, false);
    defer warm.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(cold.text, warm.text);
    try std.testing.expect(warm.work.reused > 0);
    try std.testing.expect(warm.work.syntax_hits == 2);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = edited_source });
    const edited = try checkProject(std.testing.allocator, root, cache, false);
    defer edited.deinit(std.testing.allocator);
    const fresh = try checkProject(std.testing.allocator, root, null, false);
    defer fresh.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings(fresh.text, edited.text);
    try std.testing.expect(!std.mem.eql(u8, cold.text, edited.text));
    try std.testing.expect(edited.work.checked > 0);
    try std.testing.expect(edited.work.reused > 0);
}

/// `checkProject` with the stored syntax read as far as the declarations: the bodies of the modules that did not change are filled when the check reads them.
fn checkProjectLazily(allocator: std.mem.Allocator, root: []const u8, cache: []const u8) !CheckOutcome {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var session = frontend.Session.init(allocator, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(allocator, cache);
    session.graph.syntax_mode = .lazy_sentinel;
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = try session.check(arena.allocator(), "main", &diagnostics);
    return .{
        .text = try typed_dump.render(allocator, checked.program, null),
        .work = session.statistics(),
    };
}

test "a session reads the stored syntax lazily unless SELKA_LAZY_SYNTAX turns it off" {
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, ".");
    defer session.deinit();
    try std.testing.expect(session.graph.syntax_mode.isLazy());
    var environment = std.process.Environ.Map.init(std.testing.allocator);
    defer environment.deinit();
    try session.enableSharedCache(&environment);
    try std.testing.expect(session.graph.syntax_mode.isLazy());
    try environment.put("SELKA_LAZY_SYNTAX", "0");
    try session.enableSharedCache(&environment);
    try std.testing.expectEqual(language.lazy_module.Mode.eager, session.graph.syntax_mode);
    try environment.put("SELKA_LAZY_SYNTAX", "1");
    try session.enableSharedCache(&environment);
    try std.testing.expect(session.graph.syntax_mode.isLazy());
}

test "a session that reads the stored syntax lazily checks the program a whole-syntax session checks, before and after an edit" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    const cold = try checkProject(std.testing.allocator, root, cache, false);
    defer cold.deinit(std.testing.allocator);
    // Both modules are served from the store as far as their declarations, and the program is the one the cold check made.
    const warm = try checkProjectLazily(std.testing.allocator, root, cache);
    defer warm.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), warm.work.syntax_hits);
    try std.testing.expectEqualStrings(cold.text, warm.text);
    // After an edit of `lib`, `main` is still served lazily and the program is what a fresh check of the edited tree makes.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = edited_source });
    const edited = try checkProjectLazily(std.testing.allocator, root, cache);
    defer edited.deinit(std.testing.allocator);
    const fresh = try checkProject(std.testing.allocator, root, null, false);
    defer fresh.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), edited.work.syntax_hits);
    try std.testing.expectEqualStrings(fresh.text, edited.text);
}

// spec-case: NEW-CORE-FRONTEND-CACHE-1
test "frontend validation stands in summaries without hydrating trees needed by later builds" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
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
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    const seed = try checkProject(std.testing.allocator, root, cache, false);
    defer seed.deinit(std.testing.allocator);
    try std.testing.expectError(error.ExpectedSourceError, rejectedProject(std.testing.allocator, root, null));
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data =
        \\
        \\public func change(x: str) -> int:
        \\    return len(x)
        \\
        \\public func keep(x: int) -> int:
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
    session.entry.suffix = "\n\nfunc main() -> int:\n    return helper(3)\n";
    session.setProviders(&.{.{ .path = "pkg/entry.selka", .text = "\npublic func helper(x: int) -> int:\n    return x + 1\n" }});
    var diagnostics: std.ArrayList(u8) = .empty;
    const checked = try session.check(arena.allocator(), "pkg.entry", &diagnostics);
    try std.testing.expectEqualStrings("pkg/entry.selka", session.entry.file);
    try std.testing.expectEqual(@as(usize, 1), session.interfaceIndex().units.len);
    try std.testing.expectEqual(@as(usize, 2), checked.program.functions.len);
    try std.testing.expectEqual(@as(usize, 64), frontend.compiler_identity.len);
    var limited = frontend.Session.init(std.testing.allocator, std.testing.io, ".");
    defer limited.deinit();
    limited.configureProject(.{ .max_file_bytes = 8 }, null);
    limited.setProviders(&.{.{ .path = "main.selka", .text = main_source }});
    var rejected: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.SourceError, limited.check(arena.allocator(), "main", &rejected));
    try std.testing.expect(std.mem.indexOf(u8, rejected.items, "E_PROJECT_BYTES") != null);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F1 validation sessions omit Core allocation contracts after a bounded body edit" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    const source =
        \\func helper(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return True
        \\@noalloc
        \\func bounded(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return helper(values, key)
        \\func main() -> int:
        \\    return 0
    ;
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source });
    const cold = try checkProject(std.testing.allocator, root, cache, true);
    defer cold.deinit(std.testing.allocator);
    const warm = try checkProject(std.testing.allocator, root, cache, true);
    defer warm.deinit(std.testing.allocator);
    try std.testing.expect(warm.work.summaries > 0);
    // Guest effects stay unchanged; the edit introduces runtime hash scratch.
    const changed = try std.mem.replaceOwned(u8, arena.allocator(), source, "return True", "return key in values");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = changed });
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(std.testing.allocator, cache);
    session.validationOnly();
    var diagnostics: std.ArrayList(u8) = .empty;
    _ = try session.check(arena.allocator(), "main", &diagnostics);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.items.len);
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "Core allocation contracts preserve legacy effects lists in cold and warm validation sessions" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data =
        \\func fixed(mut values: int[]) -> Unit:
        \\    values[0] = 42
        \\func apply(f: func(int) -> int, x: int) -> int:
        \\    return f(x)
        \\func main() -> int:
        \\    return 0
    });
    const cold = try checkProject(std.testing.allocator, root, cache, true);
    defer cold.deinit(std.testing.allocator);
    const warm = try checkProject(std.testing.allocator, root, cache, true);
    defer warm.deinit(std.testing.allocator);
    try std.testing.expect(warm.work.summaries > 0);
}

const borrowed_caller_source =
    // migrate-embedded: skip original borrowed-payload storage or return refusal and copy-repair witness
    \\public enum Error:
    \\    Incomplete
    \\    Malformed(value: str)
    \\    Unsupported(value: str)
    \\
    \\public func message(error: Error) -> str from error:
    \\    match error:
    \\        case Incomplete:
    \\            return "incomplete message"
    \\        case Malformed(value=detail):
    \\            return detail
    \\        case Unsupported(value=detail):
    \\            return detail
    \\
    \\func main() -> int:
    \\    const found = message(Error.Malformed(value="m"))
    \\    mut kept = message(Error.Malformed(value="n"))
    \\    kept = kept + "!"
    \\    return len(found) + len(kept)
    \\
;
const borrowed_repaired_source =
    \\public enum Error:
    \\    Incomplete
    \\    Malformed(value: str)
    \\    Unsupported(value: str)
    \\
    \\public func message(error: Error) -> str from error:
    \\    match error:
    \\        case Incomplete:
    \\            return "incomplete message"
    \\        case Malformed(value=detail):
    \\            return detail
    \\        case Unsupported(value=detail):
    \\            return detail
    \\
    \\func main() -> int:
    \\    const found = message(Error.Malformed(value="m"))
    \\    const kept = message(Error.Malformed(value="n"))
    \\    return len(found) + len(kept)
    \\
;

/// The stderr of `selka check` on `path` in a fresh process, with the frontend cache at `cache` unless `no_cache`. A
/// second process is what reuses the stored summaries, as a second command does.
fn checkProcess(arena: std.mem.Allocator, path: []const u8, cache: []const u8, no_cache: bool) ![]const u8 {
    return checkArguments(arena, path, cache, if (no_cache) &.{"--no-cache"} else &.{});
}

/// Run a fresh check process with explicit diagnostic or cache arguments.
fn checkArguments(arena: std.mem.Allocator, path: []const u8, cache: []const u8, args: []const []const u8) ![]const u8 {
    var environment = try options.privateEnvironment(arena);
    try environment.put("SELKA_FRONTEND_CACHE", cache);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ options.corePath(), "check", path });
    try argv.appendSlice(arena, args);
    const result = try std.process.run(arena, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    return result.stderr;
}

// A borrowed payload returned by a callee keeps its borrow through a cached check after a caller error (the stored
// signature's declared sources, R3): the cached diagnostics equal the fresh ones, and the repaired program checks clean.
test "frontend reuse keeps a borrowed payload return through a cached check after a caller error" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const path = try std.fs.path.join(a, &.{ root, "prog.selka" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = borrowed_caller_source });
    const cold = try checkProcess(a, path, cache, false);
    const cached = try checkProcess(a, path, cache, false);
    const fresh = try checkProcess(a, path, cache, true);
    try std.testing.expectEqualStrings(fresh, cold);
    try std.testing.expectEqualStrings(fresh, cached);
    try std.testing.expect(std.mem.indexOf(u8, cached, "E_SINGLE_OWNER_BORROW") != null);
    try std.testing.expect(std.mem.indexOf(u8, cached, "ownership rule R3") != null);
    try std.testing.expect(std.mem.indexOf(u8, cached, "E_SINGLE_OWNER_OVERLAP") == null);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = borrowed_repaired_source });
    const repaired = try checkProcess(a, path, cache, false);
    try std.testing.expect(std.mem.indexOf(u8, repaired, "error[") == null);
}

const three_owner_read_source =
    \\import dicts
    \\
    \\
    \\func width(values: dict[str, int]) -> int:
    \\    return len(values)
    \\
    \\
    \\func read_len(outer: dict[str, dict[str, dict[str, int]]], middle: dict[str, dict[str, int]], fallback: dict[str, int]) -> int:
    \\    return len(dicts.get(dicts.get(outer, "a", middle), "b", fallback)) + width(dicts.get(dicts.get(outer, "a", middle), "b", fallback))
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;
const three_owner_bound_source =
    \\import dicts
    \\
    \\
    \\func bound_len(outer: dict[str, dict[str, dict[str, int]]], middle: dict[str, dict[str, int]], fallback: dict[str, int]) -> int:
    \\    const inner = dicts.get(dicts.get(outer, "a", middle), "b", fallback)
    \\    return len(inner)
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

// Every declared source remains borrowed through a read or a const binding. An owning mutable store still needs a copy.
test "a three-owner borrowed result is accepted for reads and const bindings but refused in a mutable store" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "prog.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = three_owner_read_source });
    const read = try checkProcess(a, path, cache, true);
    try std.testing.expect(std.mem.indexOf(u8, read, "error[") == null);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = three_owner_bound_source });
    const bound = try checkProcess(a, path, cache, true);
    try std.testing.expect(std.mem.indexOf(u8, bound, "error[") == null);
    // A `mut` binding stored once from a place borrows it (D4); a write through it needs the copy.
    const mutable_source = try std.mem.replaceOwned(u8, a, three_owner_bound_source, "const inner =", "mut inner =");
    const stored_source = try std.mem.replaceOwned(u8, a, mutable_source, "    return len(inner)", "    inner[\"z\"] = 1\n    return len(inner)");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = stored_source });
    const stored = try checkProcess(a, path, cache, true);
    try std.testing.expect(std.mem.indexOf(u8, stored, "error[E_SINGLE_OWNER_BORROW]") != null);
    try std.testing.expect(std.mem.indexOf(u8, stored, "ownership rule R6") != null);
}

const refused_store_source =
    // migrate-embedded: skip original borrowed-payload storage or return refusal and copy-repair witness
    \\import json
    \\
    \\
    \\func store_payload(document: json.Json) -> bool:
    \\    mut kept = json.null_value()
    \\    match json.get(document, "meta"):
    \\        case Some(meta):
    \\            kept = meta
    \\        case None:
    \\            return False
    \\    return True
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;
const refused_return_source =
    // migrate-embedded: skip original borrowed-payload storage or return refusal and copy-repair witness
    \\import json
    \\
    \\
    \\func return_payload() -> json.Json:
    \\    mut document = json.null_value()
    \\    match json.get(document, "meta"):
    \\        case Some(meta):
    \\            return meta
    \\        case None:
    \\            return json.null_value()
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;
const refused_owner_source =
    \\import json
    \\
    \\
    \\func mutate_owner() -> bool:
    \\    mut local = json.null_value()
    \\    match json.get(local, "meta"):
    \\        case Some(meta):
    \\            local = json.null_value()
    \\            return json.as_str(meta) == Some("x")
    \\        case None:
    \\            return False
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

const MatchRefusal = struct { code: []const u8, rule: language.ownership_rules.Rule, copy: bool = false };
const RefusalRecord = struct {
    diagnostic: struct {
        code: []const u8,
        rule: language.ownership_rules.Rule,
        fix: ?struct { edits: []const struct { bytes: language.source.Span, text: []const u8 } } = null,
    },
};

/// Pin a match refusal's rule and, where offered, its exact copy on the payload and the repaired program's acceptance.
fn expectMatchRefusal(a: std.mem.Allocator, source: []const u8, expected: MatchRefusal) !void {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "prog.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = source });
    const stderr = try checkArguments(a, path, cache, &.{ "--no-cache", "--diagnostics=json" });
    const record = try std.json.parseFromSlice(RefusalRecord, a, stderr, .{ .ignore_unknown_fields = true });
    defer record.deinit();
    const failure = record.value.diagnostic;
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule);
    if (!expected.copy) return;
    const edits = (failure.fix orelse return error.TestUnexpectedResult).edits;
    try std.testing.expectEqual(@as(usize, 2), edits.len);
    try std.testing.expectEqualStrings("copy(", edits[0].text);
    try std.testing.expectEqualStrings(")", edits[1].text);
    try std.testing.expectEqual(edits[0].bytes.start, edits[0].bytes.end);
    try std.testing.expectEqual(edits[1].bytes.start, edits[1].bytes.end);
    try std.testing.expectEqualStrings("meta", source[edits[0].bytes.start..edits[1].bytes.start]);
    const repaired = try std.mem.concat(a, u8, &.{ source[0..edits[0].bytes.start], "copy(meta)", source[edits[1].bytes.start..] });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = repaired });
    const checked = try checkProcess(a, path, cache, true);
    try std.testing.expect(std.mem.indexOf(u8, checked, "error[") == null);
}

// A payload of a borrowed match result is refused where it is stored, returned past its owner's lifetime, or
// passed to a `mut` target, and an owner changed while an arm reads it is refused too (the match keeps its loans).
test "a borrowed match payload is refused where it is stored, returned, or outlives its owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try expectMatchRefusal(a, refused_store_source, .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B7, .copy = true });
    try expectMatchRefusal(a, refused_return_source, .{ .code = "E_SINGLE_OWNER_BORROW", .rule = .B7, .copy = true });
    try expectMatchRefusal(a, refused_owner_source, .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .X1 });
}

const moved_payload_source =
    // migrate-embedded: skip original borrowed-payload storage or return refusal and copy-repair witness
    \\import json
    \\
    \\
    \\func names(document: json.Json) -> str[]:
    \\    mut tags: str[] = []
    \\    match json.get(document, "tags"):
    \\        case Some(member):
    \\            match json.as_str(member):
    \\                case Some(body):
    \\                    append(mut tags, own body)
    \\                case None:
    \\                    append(mut tags, "?")
    \\        case None:
    \\            append(mut tags, "missing")
    \\    return tags
    \\
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

// A payload of a borrowed match that is moved into storage is refused, and the repair wraps the payload's name (the
// move's `own` marker stays on the call), so `selka fix` takes it: the preview names the copy and the migration writes it.
test "a moved payload of a borrowed match has a copy repair on its name" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "prog.selka" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "prog.selka", .data = moved_payload_source });
    var environment = try options.privateEnvironment(a);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "fix", "--check", path });
    const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = &environment });
    try std.testing.expect(result.term == .exited and result.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "E_SINGLE_OWNER_BORROW") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "would fix") != null);
}

/// A provider that serves two modules from memory and nothing from disk: `main` imports `lib`, as a command with generated inputs does.
const memory_modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const text = if (std.mem.eql(u8, relative, "main.selka")) main_source else if (std.mem.eql(u8, relative, "lib.selka")) lib_source else return error.NotFound;
        if (text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, text);
    }
};

test "G2o a session loads, indexes and merges in steps through the caller's provider, and the steps check what check checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var stepped = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
    defer stepped.deinit();
    stepped.useProvider(.{ .context = null, .read = memory_modules.read });
    stepped.configureProject(.{}, "main");
    var report: std.ArrayList(u8) = .empty;
    try stepped.loadModules(a, "main");
    try std.testing.expectEqual(@as(usize, 2), stepped.project.modules.items.len);
    try std.testing.expect(stepped.project.problem == null);
    try stepped.indexModules();
    try stepped.mergeDeclared(a, &report);
    try std.testing.expect(stepped.graph.compilation.declaresMain());
    const checked = try stepped.checkMerged(a, &report);
    try std.testing.expect(checked.program.functions.len >= 3);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);
    // A module the provider does not have is a loader error the caller words itself.
    var missing = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
    defer missing.deinit();
    missing.useProvider(.{ .context = null, .read = memory_modules.read });
    missing.configureProject(.{}, "absent");
    try std.testing.expectError(error.SourceError, missing.loadModules(a, "absent"));
    try std.testing.expect(missing.project.problem != null);
}

test "G2o a session without caches counts the bodies it checks, and a cached one counts through its own cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var counted = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
    defer counted.deinit();
    counted.countWork(std.testing.allocator);
    counted.useProvider(.{ .context = null, .read = memory_modules.read });
    counted.configureProject(.{}, "main");
    var report: std.ArrayList(u8) = .empty;
    _ = try counted.check(a, "main", &report);
    try std.testing.expect(counted.workCounter().?.statistics.checked >= 2);
    var bare = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
    defer bare.deinit();
    try std.testing.expect(bare.workCounter() == null);
}

test "G2o a check that produces the summary table its slot already holds does not store it again" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    const work = try std.fs.path.join(a, &.{ root, "work" });
    var report: std.ArrayList(u8) = .empty;
    {
        var first = frontend.Session.init(std.testing.allocator, std.testing.io, root);
        defer first.deinit();
        try first.enableCache(std.testing.allocator, work);
        first.validationOnly();
        _ = try first.check(a, "main", &report);
        try std.testing.expect(first.caches.frontend.?.frontend.runtime.stored);
    }
    var second = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer second.deinit();
    try second.enableCache(std.testing.allocator, work);
    second.validationOnly();
    _ = try second.check(a, "main", &report);
    try std.testing.expect(second.caches.frontend.?.stored != null);
    try std.testing.expect(!second.caches.frontend.?.frontend.runtime.stored);
}

test "G2o a session that discards trees keeps none, and a building one does" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var building = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer building.deinit();
    try building.enableCache(std.testing.allocator, try std.fs.path.join(a, &.{ root, "building" }));
    try std.testing.expect(building.caches.frontend.?.semantic.context.retain_summary_trees);
    var checking = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer checking.deinit();
    try checking.enableCache(std.testing.allocator, try std.fs.path.join(a, &.{ root, "checking" }));
    checking.validationOnly();
    try std.testing.expect(checking.caches.frontend.?.semantic.context.retain_summary_trees);
    checking.discardTrees();
    try std.testing.expect(!checking.caches.frontend.?.semantic.context.retain_summary_trees);
}

const library_source =
    \\import lib
    \\
    \\public func total(x: int) -> int:
    \\    return lib.change(x) + lib.keep(x)
    \\
;

// spec-case: G2O-2
test "G2o a library entry's first check leaves a mark, its second stores the summaries, its third stands in and stores nothing" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "library.selka", .data = library_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    const work = try std.fs.path.join(a, &.{ root, "work" });
    const slot: language.frontend_cache.SummarySlot = .{ .library = "library.selka" };
    var report: std.ArrayList(u8) = .empty;
    var tables: [3]usize = undefined;
    var rewritten: [3]bool = undefined;
    for (&tables, &rewritten) |*count, *wrote| {
        var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
        defer session.deinit();
        try session.enableCache(std.testing.allocator, work);
        session.validationOnly();
        try session.declare(a, "library", &report);
        try session.mergeDeclared(a, &report);
        try std.testing.expect(!session.graph.compilation.declaresMain());
        _ = try session.checkLibraryMerged(a, slot, &report);
        wrote.* = session.caches.frontend.?.frontend.runtime.stored;
        const bytes = (try session.caches.frontend.?.frontend.lookupSummariesIn(&session.project, slot)).?;
        defer std.testing.allocator.free(bytes);
        count.* = language.semantic_summary.decode(a, bytes).?.count();
    }
    // The first check left an empty mark, the second a table of the library's functions, the third the same table.
    try std.testing.expectEqual(@as(usize, 0), tables[0]);
    try std.testing.expect(tables[1] > 0);
    try std.testing.expectEqual(tables[1], tables[2]);
    try std.testing.expect(rewritten[1]);
    try std.testing.expect(!rewritten[2]);
}

const warning_lib_source =
    \\
    \\public func change(x: int) -> int:
    \\    return x + 1
    \\
    \\public func keep(x: int) -> int:
    \\    mut unused = 3
    \\    return x * 2
    \\
;

/// The diagnostics one fresh session's library check of `library.selka` leaves in its compilation, rendered after the check has returned.
fn libraryWarnings(a: std.mem.Allocator, gpa: std.mem.Allocator, root: []const u8, work: []const u8) ![]const u8 {
    var report: std.ArrayList(u8) = .empty;
    var session = frontend.Session.init(gpa, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(gpa, work);
    session.validationOnly();
    try session.declare(a, "library", &report);
    try session.mergeDeclared(a, &report);
    _ = try session.checkLibraryMerged(a, .{ .library = "library.selka" }, &report);
    var out: std.ArrayList(u8) = .empty;
    for (session.graph.compilation.diagnostics.items.items) |item| try out.print(a, "{s}: {s}\n", .{ item.code, item.message });
    return out.items;
}

test "G2p a warning a library check replays from its stored table is whole after the check returns" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "library.selka", .data = library_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = warning_lib_source });
    const work = try std.fs.path.join(a, &.{ root, "work" });
    const first = try libraryWarnings(a, std.testing.allocator, root, work);
    try std.testing.expect(std.mem.indexOf(u8, first, "W_UNUSED_BINDING") != null);
    // The second check stores the table; the third stands its bodies in and replays the warning from the table's own bytes.
    try std.testing.expectEqualStrings(first, try libraryWarnings(a, std.testing.allocator, root, work));
    try std.testing.expectEqualStrings(first, try libraryWarnings(a, std.testing.allocator, root, work));
}

// spec-case: G2O-2
test "G2o a complete-program session omits no body where a validation-only one omits the unchanged ones" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    const work = try std.fs.path.join(a, &.{ root, "work" });
    var report: std.ArrayList(u8) = .empty;
    var omitted: [3]usize = undefined;
    for (&omitted, [_]bool{ true, true, false }) |*count, validating| {
        var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
        defer session.deinit();
        try session.enableCache(std.testing.allocator, work);
        if (validating) session.validationOnly() else session.completeProgram();
        _ = try session.check(a, "main", &report);
        count.* = 0;
        if (session.demandState()) |state| for (state.omitted) |left_out| {
            count.* += @intFromBool(left_out);
        };
    }
    // The cold validation-only check omits nothing, the warm one every unchanged body, and the complete-program one none.
    try std.testing.expectEqual(@as(usize, 0), omitted[0]);
    try std.testing.expect(omitted[1] > 0);
    try std.testing.expectEqual(@as(usize, 0), omitted[2]);
}

// spec: G2O-3
test "G2o an explained check reports a failed body check and not a program that checked and then failed ownership validation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "main.selka" });
    var environment = try options.privateEnvironment(a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "helper.selka", .data = "public func value() -> int:\n    return 7\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\nfunc main() -> int:\n    return helper.value() + \"x\"\n" });
    const argv = [_][]const u8{ options.corePath(), "check-project", path, "--no-cache", "--explain-invalidation" };
    const mistyped = try std.process.run(a, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
    try std.testing.expect(mistyped.term == .exited and mistyped.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, mistyped.stderr, "\"version\":\"invalidation-report-v1\"") != null);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "import helper\n\nfunc main() -> int:\n    mut a: int[] = [1, 2]\n    mut b: int[] = a\n    append(mut b, 3)\n    return helper.value() + len(a)\n" });
    const unowned = try std.process.run(a, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
    try std.testing.expect(unowned.term == .exited and unowned.term.exited == 1);
    try std.testing.expect(std.mem.indexOf(u8, unowned.stderr, "\"version\":\"invalidation-report-v1\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, unowned.stderr, "E_OWN_MARKER") != null);
}

/// `main` calls `lib.keep` with a text argument, which does not check.
const mistyped_main_source =
    \\import lib
    \\
    \\func main() -> int:
    \\    return lib.keep("text")
    \\
;

const mistyped_modules = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, relative: []const u8, limit: usize) language.project.ReadError![]u8 {
        const text = if (std.mem.eql(u8, relative, "main.selka")) mistyped_main_source else if (std.mem.eql(u8, relative, "lib.selka")) lib_source else return error.NotFound;
        if (text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, text);
    }
};

// spec: G2O-4
test "G2o checkBodies returns the raw source error and leaves the diagnostics for a command that words its own failures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
    defer session.deinit();
    session.useProvider(.{ .context = null, .read = mistyped_modules.read });
    session.configureProject(.{}, "main");
    var report: std.ArrayList(u8) = .empty;
    try session.declare(a, "main", &report);
    try session.mergeDeclared(a, &report);
    try std.testing.expectError(error.SourceError, session.checkBodies());
    try std.testing.expect(session.graph.compilation.diagnostics.items.items.len != 0);
    try std.testing.expectEqual(@as(usize, 0), report.items.len);
    // A library check of the same graph needs no `main`, and a program that checks leaves a program behind.
    var sound = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
    defer sound.deinit();
    sound.useProvider(.{ .context = null, .read = memory_modules.read });
    sound.configureProject(.{}, "main");
    try sound.declare(a, "main", &report);
    try sound.mergeDeclared(a, &report);
    try sound.checkBodies();
    try std.testing.expect(sound.graph.compilation.program != null);
}

// spec: G2O-5
test "G2o two sessions over lent caches: the second parses and checks nothing the first kept" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var syntax = language.syntax_cache.Cache.init(std.testing.allocator, .{});
    defer syntax.deinit();
    var functions = language.semantic_cache.Cache.init(std.testing.allocator, 16 * 1024 * 1024);
    defer functions.deinit();
    var report: std.ArrayList(u8) = .empty;
    var hits: [2]usize = undefined;
    var reused: [2]usize = undefined;
    for (&hits, &reused) |*syntax_hits, *bodies_reused| {
        var session = frontend.Session.init(std.testing.allocator, std.testing.io, "/nowhere");
        defer session.deinit();
        session.useProvider(.{ .context = null, .read = memory_modules.read });
        session.configureProject(.{}, "main");
        session.lendCaches(&syntax, &functions);
        _ = try session.check(a, "main", &report);
        syntax_hits.* = syntax.statistics.hits;
        bodies_reused.* = functions.statistics.reused;
    }
    try std.testing.expectEqual(@as(usize, 0), hits[0]);
    try std.testing.expect(hits[1] >= 2);
    try std.testing.expect(reused[1] > reused[0]);
}

/// Load `main` and its imports in a fresh session over `root` and `cache`; the number of module digests the stat-trusted memo gave.
fn digestsVouched(allocator: std.mem.Allocator, root: []const u8, cache: []const u8) !usize {
    var session = frontend.Session.init(allocator, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(allocator, cache);
    try session.loadModules(allocator, "main");
    return session.files.digests.?.vouched;
}

/// Set the modification time of `name` to `nanoseconds` since the epoch. The change time becomes now, as for any write.
fn stamp(dir: std.Io.Dir, name: []const u8, nanoseconds: i96) !void {
    try dir.setTimestamps(std.testing.io, name, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = nanoseconds } } });
}

/// Stamp `name` an hour ahead of now: its last change is then inside the racy window for as long as a test can run, whatever the load.
/// A file that is only rewritten just before a call is inside a 50 ms window only if the call is quick, and a load can make it slow.
fn stampAhead(dir: std.Io.Dir, name: []const u8) !void {
    try stamp(dir, name, std.Io.Clock.real.now(std.testing.io).nanoseconds + 3_600 * std.time.ns_per_s);
}

test "a load takes the stored digest of a module whose stat tuple has not moved, and hashes a rewritten one" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    // The engine's racy window, plus a margin: the files are older than it by the time they are first observed.
    try std.Io.sleep(std.testing.io, .fromNanoseconds(frontend.digest_window_ns + 60 * std.time.ns_per_ms), .awake);
    try std.testing.expectEqual(@as(usize, 0), try digestsVouched(std.testing.allocator, root, cache));
    try std.testing.expectEqual(@as(usize, 2), try digestsVouched(std.testing.allocator, root, cache));
    // A module rewritten to the same size is hashed again, and the rewrite is inside the window, so it is not remembered either. The
    // rewrite is stamped an hour ahead: it stays inside the window however long the loads take, where one that merely follows the
    // rewrite ages out of the 50 ms window on a loaded machine and is remembered by the third load.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = edited_source });
    try stampAhead(temporary.dir, "lib.selka");
    try std.testing.expectEqual(@as(usize, 1), try digestsVouched(std.testing.allocator, root, cache));
    try std.testing.expectEqual(@as(usize, 1), try digestsVouched(std.testing.allocator, root, cache));
}

test "the module digests' racy window is the engine's own" {
    const engine = @import("engine/engine.zig");
    const configured: engine.Config = .{ .work = "" };
    try std.testing.expectEqual(configured.assumptions.racy_window_ns, frontend.digest_window_ns);
}

test "saving the digest memo does not count as a stored entry" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator());
    const cache = try std.fs.path.join(arena.allocator(), &.{ root, "cache" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = main_source });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib_source });
    // The first load stores the modules' header records; the files are stamped an hour ahead, so they are inside the racy window however
    // long the load takes, and it teaches the memo nothing.
    try stampAhead(temporary.dir, "main.selka");
    try stampAhead(temporary.dir, "lib.selka");
    try std.testing.expectEqual(@as(usize, 0), try digestsVouched(std.testing.allocator, root, cache));
    // Then the stamps go back, and the change time (now) ages past the window while the test sleeps.
    try stamp(temporary.dir, "main.selka", 1);
    try stamp(temporary.dir, "lib.selka", 1);
    try std.Io.sleep(std.testing.io, .fromNanoseconds(frontend.digest_window_ns + 60 * std.time.ns_per_ms), .awake);
    // The second finds the headers stored and the files aged: the memo learns both digests and is saved, and nothing else is.
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(std.testing.allocator, cache);
    try session.loadModules(std.testing.allocator, "main");
    try std.testing.expectEqual(@as(usize, 2), session.files.digests.?.table.count());
    try std.testing.expect(!session.files.digests.?.dirty);
    try std.testing.expect(!session.caches.frontend.?.frontend.runtime.stored);
}

test "a check that runs out of memory names the host ceiling it reached and not a host failure" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 40,000 small functions are about 5 MiB of source and need more than the 16 MiB ceiling plus its 256 MiB of address space.
    var source: std.ArrayList(u8) = .empty;
    for (0..40000) |index| try source.print(a, "func fn_{d}(a: int, b: int) -> int:\n    mut total = a\n    for k in range(b):\n        total = total + k * {d}\n    return total\n\n\n", .{ index, index });
    try source.appendSlice(a, "func main(out: Stream) -> int:\n    print(out, fn_1(2, 3))\n    return 0\n");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "big.selka", .data = source.items });
    const entry = try temporary.dir.realPathFileAlloc(std.testing.io, "big.selka", a);
    var environment = try options.privateEnvironment(a);
    _ = environment.swapRemove("SELKA_HOST_LIMIT_CHECKPOINT");
    _ = environment.swapRemove("SELKA_HOST_LIMIT_RESTORE");
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "16M");
    const bounded = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "check", entry }, .environ_map = &environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 2 }, bounded.term);
    try std.testing.expect(std.mem.indexOf(u8, bounded.stderr, "host failure") == null);
    try std.testing.expect(std.mem.indexOf(u8, bounded.stderr, "selka: out of memory: the compiler reached its own memory ceiling of 16 MiB") != null);
    try std.testing.expect(std.mem.indexOf(u8, bounded.stderr, "raise SELKA_HOST_MEMORY_LIMIT") != null);
    // The same check without a ceiling passes.
    try environment.put("SELKA_HOST_MEMORY_LIMIT", "0");
    const unbounded = try std.process.run(a, std.testing.io, .{ .argv = &.{ options.corePath(), "check", entry }, .environ_map = &environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, unbounded.term);
}
