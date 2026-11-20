//! Check-at-scale coverage: the lexer-free paths the per-edit check relies on
//! agree exactly with the full lexer, and a check that stands summaries in for
//! unchanged bodies reports exactly what a check without them reports.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const lexer = language.lexer;
const diagnostic = language.diagnostic;
const summary = language.semantic_summary;
const File = language.embedded_project.File;
const semantic_key = @import("semantic_key.zig");
const removed_names = @import("removed_names.zig");
const semantic_store = @import("semantic_store.zig");
const cache_key = @import("cache_key.zig");

const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return language.embedded_project.read(allocator, self.entries, path, limit);
    }
};

/// What one project check did and reported.
const Outcome = struct {
    /// Bodies actually checked.
    checked: usize,
    /// Bodies the semantic cache served from its in-memory set or its durable store.
    reused: usize,
    /// Bodies (or, for a lowering command, body facts) a summary stood in for
    /// in the final check; zero after a repeat in full.
    stood_in: usize,
    /// Actual omitted body trees admitted by a lowering host.
    omitted: usize,
    /// Checked bodies the check wrote to the durable store it was given (zero without one).
    stored: usize = 0,
    /// Every diagnostic rendered in order; owned by `t.allocator`.
    diagnostics: []u8,
    /// The same diagnostics as `--diagnostics=json` writes them, a repair's edits included; owned by `t.allocator`.
    json: []u8 = &.{},
    /// Every checked function's mutation and return-origin facts, one line
    /// each; owned by `t.allocator` and empty when the check failed.
    facts: []u8,
    /// The encoded summaries the check produced, or null when it published none.
    summaries: ?[]u8,
    /// What the verify sampling of the pass stand-in compared, and how many it found different (`Mode.verify` samples every one).
    verified: u32 = 0,
    mismatched: u32 = 0,
    /// How many module groups the planner published in the request's prepared facts.
    groups: usize = 0,
    /// How many of them the previous table answered for as a whole, and how many of those were stored again as they were.
    matched: u32 = 0,
    kept: u32 = 0,
    /// The first function the verify sampling found different, and what differed; owned by `t.allocator`.
    first: []u8 = &.{},

    fn deinit(self: Outcome) void {
        t.allocator.free(self.first);
        t.allocator.free(self.diagnostics);
        t.allocator.free(self.json);
        t.allocator.free(self.facts);
        if (self.summaries) |payload| t.allocator.free(payload);
    }
};

/// How a check runs: as `check` (summaries stand in for bodies) or as a command
/// that lowers the program (every body checked, summaries stand in for facts).
const Mode = enum { check, lowering, allocation_contracts, demand, demand_missing, verify, build, restore };

fn admitDemand(context: *const anyopaque, key: []const u8, _: [32]u8, _: [32]u8) bool {
    const mode: *const Mode = @ptrCast(@alignCast(context));
    return mode.* != .demand_missing or !std.mem.endsWith(u8, key, "\x1fplain");
}

fn omissionCount(request: summary.Request) usize {
    const demand = request.policy.demand orelse return 0;
    var count: usize = 0;
    for (demand.omitted) |omitted| count += @intFromBool(omitted);
    return count;
}

/// Check the project `files` (entry module `main`) with the given previous
/// summaries, exactly as `check` or a lowering command does through a cache.
fn checkProject(files: []const File, previous: ?[]const u8, mode: Mode) !Outcome {
    return runProject(files, previous, mode, .executable);
}

/// Check the library `files` (entry module `main`, which declares no `main` function)
/// with the given previous summaries, exactly as `check` does for a library.
fn checkLibrary(files: []const File, previous: ?[]const u8) !Outcome {
    return runProject(files, previous, .check, .library);
}

/// The library check with no semantic cache at all: what every cached library check must report.
fn checkLibraryPlain(files: []const File) !Outcome {
    return runProject(files, null, .check, .plain_library);
}

/// Which check a run makes: an executable's, a library's through the cache, or a library's without one.
const Variant = enum { executable, library, plain_library };

/// `checkProject`, `checkLibrary` or `checkLibraryPlain`: the same report around each check.
fn runProject(files: []const File, previous: ?[]const u8, mode: Mode, variant: Variant) !Outcome {
    return runProjectWith(files, previous, mode, variant, .{});
}

/// What a run adds to its mode: the durable store of checked bodies, and a lowering host of the test's own that replaces the mode's.
const Extras = struct {
    durable: ?*semantic_store.Store = null,
    host: ?summary.Demand = null,
    verify_every: u32 = 0,
    profile: ?*language.timings.Profile = null,
    /// How the check treats a typed hole: refused, as `check` does, or kept as a trap, as a debug build does.
    holes: diagnostic.HoleMode = .refuse,
};

/// `runProject` with the semantic cache's checked bodies kept in the durable store `durable` when given, so a later
/// call (a new process, in the real build) can reuse them. Without a store the cache keeps nothing.
fn runProjectWith(files: []const File, previous: ?[]const u8, mode: Mode, variant: Variant, extras: Extras) !Outcome {
    const durable = extras.durable;
    var provider: Files = .{ .entries = files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.diagnostics.hole_mode = extras.holes;
    var cache = language.semantic_cache.Cache.init(t.allocator, if (durable == null) 0 else 4 << 20);
    defer cache.deinit();
    if (durable) |store| {
        cache.context.persistent = store;
        cache.context.retain_summary_trees = true;
    }
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    var request: summary.Request = .{ .body_policy = switch (mode) {
        .check, .verify => .summaries,
        .lowering, .demand, .demand_missing, .build, .restore => .concrete,
        .allocation_contracts => .allocation_contracts,
    } };
    if (mode == .demand or mode == .demand_missing) request.policy.demand = .{ .context = &mode, .allow = admitDemand };
    // The lowering host's own policy: its artifacts read no callee body.
    if (mode == .build or mode == .restore) request.policy.demand = .{ .context = &mode, .allow = admitDemand, .body_dependencies = false, .facts_unread = true };
    // A host that asks for the trees of the bodies it restores (`Session.checkBodiesOf`).
    if (mode == .restore) request.policy.restores_trees = true;
    if (mode == .verify) request.policy.verify.every = 1;
    if (extras.host) |host| request.policy.demand = host;
    if (extras.verify_every != 0) request.policy.verify.every = extras.verify_every;
    var decoded: summary.Index = .{};
    if (previous) |payload| {
        const restored = summary.decode(arena_state.allocator(), payload);
        try t.expect(restored != null);
        decoded = restored.?;
        request.previous = &decoded;
    }
    cache.context.summaries = &request;
    cache.context.timing = extras.profile;
    var library_program: ?language.typed.Program = null;
    switch (variant) {
        .executable => compilation.checkWithCache(&cache) catch |err| switch (err) {
            error.SourceError => {},
            else => return err,
        },
        .library => library_program = compilation.checkLibraryProgramWithCache(&cache) catch |err| switch (err) {
            error.SourceError => null,
            else => return err,
        },
        .plain_library => library_program = compilation.checkLibraryProgram() catch |err| switch (err) {
            error.SourceError => null,
            else => return err,
        },
    }
    var rendered: std.Io.Writer.Allocating = .init(t.allocator);
    defer rendered.deinit();
    var json: std.Io.Writer.Allocating = .init(t.allocator);
    defer json.deinit();
    for (compilation.diagnostics.items.items) |item| {
        const text = try item.render(arena_state.allocator(), compilation.src);
        try rendered.writer.writeAll(text);
        try json.writer.writeAll(try language.diagnostic_output.render(arena_state.allocator(), item, compilation.src, .json));
    }
    var facts: std.Io.Writer.Allocating = .init(t.allocator);
    defer facts.deinit();
    if (library_program orelse compilation.program) |program| for (program.functions) |function| {
        try facts.writer.print("{s} mutates={any} writes={} external={} origin={s} private={}\n", .{
            function.name,
            function.signature.mutates,
            function.signature.inferred.writes,
            function.signature.inferred.external,
            @tagName(function.signature.return_origin),
            @backingInt(function.id) < program.private.len and program.private[@backingInt(function.id)],
        });
    };
    return .{
        .checked = cache.statistics.checked,
        .reused = cache.statistics.reused,
        .stood_in = request.stood_in,
        .omitted = omissionCount(request),
        .stored = if (durable) |store| store.statistics.stored else 0,
        .diagnostics = try rendered.toOwnedSlice(),
        .json = try json.toOwnedSlice(),
        .facts = try facts.toOwnedSlice(),
        .summaries = if (request.produced) |produced| try summary.encodeFrom(t.allocator, produced, request.previous, .{}) else null,
        .verified = request.policy.verify.compared,
        .mismatched = request.policy.verify.mismatched,
        .groups = if (request.prepared) |prepared| prepared.grouping.modules.len else 0,
        .matched = if (request.prepared) |prepared| prepared.grouping.matched else 0,
        .kept = if (request.prepared) |prepared| prepared.grouping.kept else 0,
        .first = try t.allocator.dupe(u8, request.policy.verify.first),
    };
}

/// Check `changed` in `mode` with the summaries a `check` of `original` left (none when it was refused, as a W13 refusal
/// is), and again with none. Both outcomes are returned for comparison.
fn checkAfterEditAs(original: []const File, changed: []const File, mode: Mode) !struct { warm: Outcome, cold: Outcome } {
    const seed = try checkProject(original, null, .check);
    defer seed.deinit();
    const warm = try checkProject(changed, seed.summaries, mode);
    errdefer warm.deinit();
    const cold = try checkProject(changed, null, mode);
    return .{ .warm = warm, .cold = cold };
}

/// `checkAfterEditAs` for `check` itself.
fn checkAfterEdit(original: []const File, changed: []const File) !struct { warm: Outcome, cold: Outcome } {
    const outcome = try checkAfterEditAs(original, changed, .check);
    return .{ .warm = outcome.warm, .cold = outcome.cold };
}

const lib_source =
    \\
    \\
    \\public record Acc:
    \\    total: int
    \\    count: int
    \\
    \\
    \\public func gather(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for k in range(n):
    \\        append(mut xs, k * 2)
    \\    mut acc = Acc(total=0, count=0)
    \\    for x in xs:
    \\        acc = Acc(total=acc.total + x, count=acc.count + 1)
    \\    return acc.total
    \\
    \\
    \\public func spread(n: int) -> int:
    \\    mut ys: int[] = [n, n + 1]
    \\    mut unused = 3
    \\    return ys[0] + ys[1]
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;
const mid_source =
    \\import lib
    \\
    \\
    \\public func twice(n: int) -> int:
    \\    return lib.gather(n) + lib.gather(n + 1)
    \\
    \\
    \\public func bounded(n: int) -> int:
    \\    return lib.plain(n) * 2
    \\
    \\
    \\public func count(n: int) -> int:
    \\    mut zs: int[] = [n]
    \\    return lib.spread(zs[0])
    \\
;
const main_source =
    \\import mid
    \\
    \\
    \\func main() -> int:
    \\    return mid.twice(3) + mid.bounded(2) + mid.count(1)
    \\
;

fn projectFiles(lib: []const u8) [3]File {
    return .{
        .{ .path = "main.selka", .bytes = main_source },
        .{ .path = "mid.selka", .bytes = mid_source },
        .{ .path = "lib.selka", .bytes = lib },
    };
}

/// `lib_source` with one occurrence of `from` replaced by `to`.
fn libEdited(comptime from: []const u8, comptime to: []const u8) []const u8 {
    const at = comptime std.mem.indexOf(u8, lib_source, from).?;
    return lib_source[0..at] ++ to ++ lib_source[at + from.len ..];
}

const hole_main =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    return lib.fine(1)
;
const hole_lib =
    \\public func pending() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func fine(x: int) -> int:
    \\    return x * 2
;

// The summary table a check publishes while it keeps a typed hole as a trap (a debug build) must not stand the hole's body in for a
// check that refuses holes: the hole mode is in no key of the table.
test "a summary made while a hole was a trap never stands the hole's body in for a check that refuses holes" {
    const files = [_]File{ .{ .path = "main.selka", .bytes = hole_main }, .{ .path = "lib.selka", .bytes = hole_lib } };
    const trapped = try runProjectWith(&files, null, .check, .executable, .{ .holes = .trap });
    defer trapped.deinit();
    const refused = try runProjectWith(&files, trapped.summaries.?, .check, .executable, .{});
    defer refused.deinit();
    const cold = try runProjectWith(&files, null, .check, .executable, .{});
    defer cold.deinit();
    try t.expectEqual(@as(usize, 0), trapped.diagnostics.len);
    try t.expect(trapped.summaries != null);
    try t.expect(std.mem.indexOf(u8, refused.diagnostics, "E_TYPED_HOLE") != null);
    try t.expectEqualStrings(cold.diagnostics, refused.diagnostics);
    // The function beside the hole still stands in from the table the trapped check made.
    try t.expectEqual(@as(usize, 1), refused.stood_in);
}

// spec: CHECK-SUMMARY-1
test "a body edit checks only that body and reports what a check without summaries reports" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)"));
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // The edited body and the entry point are checked; the other five stand in.
    try t.expectEqual(@as(usize, 2), outcome.warm.checked);
    try t.expectEqual(@as(usize, 5), outcome.warm.stood_in);
    try t.expectEqual(@as(usize, 7), outcome.cold.checked);
    // The stood-in `spread` still reports its unused binding.
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "W_UNUSED_BINDING") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
}

// A table another worktree left, two versions of the project behind, is the table a fresh work directory is served (G4c-2a).
test "a table two versions old costs reuse and changes no output" {
    const first = projectFiles(lib_source);
    const second_lib = comptime libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)");
    const second = projectFiles(second_lib);
    const at = comptime std.mem.indexOf(u8, second_lib, "return n + 1").?;
    const third = projectFiles(second_lib[0..at] ++ "return n + 2" ++ second_lib[at + "return n + 1".len ..]);
    const old = try checkProject(&first, null, .check);
    defer old.deinit();
    const recent = try checkProject(&second, old.summaries.?, .check);
    defer recent.deinit();
    // The third version against the table of the first, against the table of the second, and against none.
    const older = try checkProject(&third, old.summaries.?, .check);
    defer older.deinit();
    const newer = try checkProject(&third, recent.summaries.?, .check);
    defer newer.deinit();
    const cold = try checkProject(&third, null, .check);
    defer cold.deinit();
    // The older table lacks the first edit as well as the second, so it stands in fewer bodies; both stand in more than none does.
    try t.expect(older.checked > newer.checked);
    try t.expect(older.checked < cold.checked);
    try t.expectEqualStrings(cold.diagnostics, older.diagnostics);
    try t.expectEqualStrings(cold.diagnostics, newer.diagnostics);
    try t.expectEqualStrings(cold.facts, older.facts);
    try t.expectEqualStrings(cold.facts, newer.facts);
}

// spec-case: CHECK-SUMMARY-1
test "an unchanged project stands in every body but the entry point" {
    const original = projectFiles(lib_source);
    const outcome = try checkAfterEdit(&original, &original);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 1), outcome.warm.checked);
    try t.expectEqual(@as(usize, 6), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// spec-case: CHECK-SUMMARY-1
test "a record shape edit re-checks every body that uses the record" {
    const original = projectFiles(lib_source);
    // A new defaulted field changes `Acc`'s shape but keeps every use valid.
    const widened = projectFiles(libEdited("    count: int\n", "    count: int\n    note: int = 0\n"));
    const outcome = try checkAfterEdit(&original, &widened);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `gather` touches `Acc`; the persisted graph also invalidates `twice`.
    try t.expectEqual(@as(usize, 3), outcome.warm.checked);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // A field type edit breaks the body that builds the record: the same error.
    const retyped = projectFiles(libEdited("    total: int\n", "    total: str\n"));
    const broken = try checkAfterEdit(&original, &retyped);
    defer broken.warm.deinit();
    defer broken.cold.deinit();
    try t.expect(broken.warm.summaries == null);
    try t.expect(std.mem.indexOf(u8, broken.warm.diagnostics, "error[") != null);
    try t.expectEqualStrings(broken.cold.diagnostics, broken.warm.diagnostics);
}

/// A new helper's read-only parameter is the contract a changed body may violate.
fn readonlyMutationProject(comptime writes: bool) [3]File {
    const library = comptime libEdited("    return n + 1\n", "    mut values = [n]\n    return read(values)\n") ++ "\n" ++ if (writes)
        "func read(values: int[]) -> int:\n    values[0] += 1\n    return values[0]\n"
    else
        "func read(values: int[]) -> int:\n    return values[0] + 1\n";
    return projectFiles(library);
}

// spec-case: CHECK-SUMMARY-1
test "a callee body gaining a readonly parameter write is reported by the first attempt" {
    const original = readonlyMutationProject(false);
    const changed = readonlyMutationProject(true);
    const unchanged = try checkAfterEdit(&original, &original);
    defer unchanged.warm.deinit();
    defer unchanged.cold.deinit();
    try t.expectEqual(@as(usize, 1), unchanged.warm.checked);
    try t.expectEqual(@as(usize, 7), unchanged.warm.stood_in);
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // The write fails its own body, which is a body check's finding: the attempt that stood
    // the other bodies in reports it, and a repeat in full would have stood none in.
    try t.expectEqual(@as(usize, 6), outcome.warm.stood_in);
    try t.expectEqual(@as(usize, 2), outcome.warm.checked);
    try t.expectEqual(@as(usize, 8), outcome.cold.checked);
    try t.expect(outcome.warm.summaries == null);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "E_IMMUTABLE") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// A signature that names no identifier (not even a return type) leaves
// nothing module-scoped in its fingerprint but the defining module itself.
const alpha_source =
    \\
    \\
    \\public func value():
    \\    pass
    \\
;
// The same declaration text as `alpha.value`, but its body allocates.
const beta_source =
    \\
    \\
    \\public func value():
    \\    mut xs: int[] = [1]
    \\    assert xs[0] == 1
    \\
;

fn aliasProject(user: []const u8) [4]File {
    return .{
        .{ .path = "main.selka", .bytes = "import user\nimport beta\n\n\nfunc main() -> int:\n    user.bounded()\n    beta.value()\n    return 0\n" },
        .{ .path = "user.selka", .bytes = user },
        .{ .path = "alpha.selka", .bytes = alpha_source },
        .{ .path = "beta.selka", .bytes = beta_source },
    };
}

/// Byte-identical declarations still name different nominal Token types in each module.
fn nominalAliasProject(comptime target: []const u8) [4]File {
    const declaration = "public record Token:\n    value: int\n\npublic func value() -> Token:\n    return Token(value=1)\n";
    return .{
        .{ .path = "main.selka", .bytes = "import user\nimport alpha\nimport beta\n\nfunc accept(token: alpha.Token) -> int:\n    return token.value\n\nfunc main() -> int:\n    _ = beta.value()\n    return accept(user.bounded())\n" },
        .{ .path = "user.selka", .bytes = "import " ++ target ++ " as source\n\npublic func bounded() -> source.Token:\n    return source.value()\n" },
        .{ .path = "alpha.selka", .bytes = declaration },
        .{ .path = "beta.selka", .bytes = declaration },
    };
}

// spec: SEMANTIC-KEY-IDENTITY-1
test "an import alias retargeted to identical text rechecks its distinct nominal return type" {
    const through_alpha = nominalAliasProject("alpha");
    const through_beta = nominalAliasProject("beta");
    const unchanged = try checkAfterEdit(&through_alpha, &through_alpha);
    defer unchanged.warm.deinit();
    defer unchanged.cold.deinit();
    try t.expectEqual(@as(usize, 1), unchanged.warm.checked);
    try t.expectEqual(@as(usize, 4), unchanged.warm.stood_in);
    const outcome = try checkAfterEdit(&through_alpha, &through_beta);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expect(outcome.warm.summaries == null);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "E_TYPE") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// spec-case: SEMANTIC-KEY-IDENTITY-1
test "deprecating a callee in another module warns at its stood-in callers" {
    const original = projectFiles(lib_source);
    const deprecated = projectFiles(libEdited("public func plain(", "@deprecated(\"use twice\")\npublic func plain("));
    const outcome = try checkAfterEdit(&original, &deprecated);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "W_DEPRECATED") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// spec: CHECK-SUMMARY-2
test "a lowering command checks every body and stands summaries in only for their facts" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)"));
    const outcome = try checkAfterEditAs(&original, &changed, .lowering);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // Every body is checked, because lowering needs its tree; the five
    // unchanged bodies' effect and mutation facts come from their summaries.
    try t.expectEqual(@as(usize, 7), outcome.warm.checked);
    try t.expectEqual(@as(usize, 5), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // It had summaries to stand in, so it publishes none; without any it does.
    try t.expect(outcome.warm.summaries == null);
    try t.expect(outcome.cold.summaries != null);
}

// spec-case: CHECK-SUMMARY-2
test "a lowering command whose edit changes a callee's facts publishes the facts it computed in full" {
    const original = projectFiles(lib_source);
    const allocating = projectFiles(libEdited("    return n + 1\n", "    mut ws: int[] = [n]\n    return ws[0] + 1\n"));
    // Allocation ceilings are retired. Exercise the surviving managed-write
    // fact explicitly while preserving the original source inputs above.
    const spread_head = "    mut ys: int[] = [n, n + 1]\n";
    const writing_head = spread_head ++ "    append(mut ys, n + 2)\n";
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, original[2].bytes, spread_head));
    const writing_lib = try std.mem.replaceOwned(u8, t.allocator, original[2].bytes, spread_head, writing_head);
    defer t.allocator.free(writing_lib);
    try t.expect(!std.mem.eql(u8, writing_lib, lib_source));
    const writing_original = projectFiles(writing_lib);
    const baseline = try checkProject(&writing_original, null, .lowering);
    defer baseline.deinit();
    const allocating_spread = try std.mem.replaceOwned(u8, t.allocator, allocating[2].bytes, spread_head, writing_head);
    defer t.allocator.free(allocating_spread);
    const plain_head = "    mut ws: int[] = [n]\n";
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, allocating_spread, plain_head));
    const allocating_writes = try std.mem.replaceOwned(u8, t.allocator, allocating_spread, plain_head, plain_head ++ "    append(mut ws, n + 1)\n");
    defer t.allocator.free(allocating_writes);
    try t.expect(!std.mem.eql(u8, allocating_writes, allocating_spread));
    var allocating_current = allocating;
    allocating_current[2].bytes = allocating_writes;
    const outcome = try checkAfterEditAs(&writing_original, &allocating_current, .lowering);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 0), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // The old effect ceiling no longer rejects this valid program. The new
    // `plain` write changes retained facts, so the full repeat publishes them.
    try t.expectEqual(@as(usize, 7), outcome.warm.checked);
    try t.expect(outcome.warm.summaries != null);
    try t.expect(outcome.cold.summaries != null);
    try t.expect(!std.mem.eql(u8, baseline.facts, outcome.cold.facts));
    try t.expect(std.mem.indexOf(u8, outcome.cold.diagnostics, "error[") == null);
    // `spread` loses its explicit managed write in a still-valid program. The
    // command repeats in full and publishes, so the next one stands in again.
    const pure = projectFiles(libEdited("    mut ys: int[] = [n, n + 1]\n    mut unused = 3\n    return ys[0] + ys[1]\n", "    mut unused = 3\n    return n + n + 1\n"));
    const repeated = try checkAfterEditAs(&writing_original, &pure, .lowering);
    defer repeated.warm.deinit();
    defer repeated.cold.deinit();
    try t.expectEqual(@as(usize, 0), repeated.warm.stood_in);
    try t.expectEqual(@as(usize, 7), repeated.warm.checked);
    try t.expect(repeated.warm.summaries != null);
    try t.expect(!std.mem.eql(u8, baseline.facts, repeated.cold.facts));
    try t.expectEqualStrings(repeated.cold.facts, repeated.warm.facts);
    try t.expectEqualStrings(repeated.cold.diagnostics, repeated.warm.diagnostics);
    // Published changed facts must support the next lowering request without
    // another full repeat; stale mutation facts would fail this comparison.
    const next = try checkProject(&pure, repeated.warm.summaries.?, .lowering);
    defer next.deinit();
    try t.expectEqual(@as(usize, 6), next.stood_in);
    try t.expectEqualStrings(repeated.cold.facts, next.facts);
    try t.expectEqualStrings(repeated.cold.diagnostics, next.diagnostics);
}

/// A recall over one earlier preparation's own names, or over wrong digests.
const TestRecall = struct {
    prepared: *const semantic_key.Prepared,
    corrupt: bool,

    fn names(context: *const anyopaque, key: []const u8, digest: [32]u8) ?[]const semantic_key.Name {
        const self: *const TestRecall = @ptrCast(@alignCast(context));
        for (self.prepared.keys, 0..) |candidate, index| {
            if (!std.mem.eql(u8, candidate, key)) continue;
            var stored = self.prepared.recalled.digests[index];
            if (self.corrupt) stored[0] ^= 1;
            if (!std.mem.eql(u8, &stored, &digest)) return null;
            return self.prepared.recalled.names[index];
        }
        return null;
    }
};

/// The lib project loaded, with its keys prepared.
const Prepared = struct {
    index: *language.interfaces.Index,
    compilation: language.project_compile.Compilation,
    keys: semantic_key.Prepared,
};

/// Load the lib project and prepare its dependency keys with `recall`.
fn prepareProject(arena: std.mem.Allocator, recall: ?semantic_key.Recall) !Prepared {
    const files = projectFiles(lib_source);
    return prepareFiles(arena, &files, recall);
}

/// Load the project of `files` (the entry is `main`) and prepare its dependency keys with `recall`.
fn prepareFiles(arena: std.mem.Allocator, files: []const File, recall: ?semantic_key.Recall) !Prepared {
    var provider: Files = .{ .entries = files };
    const project = try arena.create(language.project.Project);
    project.* = language.project.Project.init(arena);
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    const index = try arena.create(language.interfaces.Index);
    index.* = try language.interfaces.build(project);
    const compilation = try language.project_compile.Compilation.init(index);
    const keys = try semantic_key.prepare(arena, compilation.src, compilation.syntax, .{ .build = "test", .mutation = "mutation-v1" }, index, recall);
    return .{ .index = index, .compilation = compilation, .keys = keys };
}

/// Prepare the dependency keys of the lib project with `recall`.
fn prepareKeys(arena: std.mem.Allocator, recall: ?semantic_key.Recall) !semantic_key.Prepared {
    return (try prepareProject(arena, recall)).keys;
}

// spec: CHECK-SCALE-KEYS-1
test "dependency keys resolved from recalled names equal those from walking the syntax" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const walked = try prepareKeys(arena, null);
    try t.expect(walked.recalled.names.len == walked.keys.len);
    var matching: TestRecall = .{ .prepared = &walked, .corrupt = false };
    const recalled = try prepareKeys(arena, .{ .context = &matching, .names = TestRecall.names });
    try t.expectEqual(walked.contexts.len, recalled.contexts.len);
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(walked.contexts), std.mem.sliceAsBytes(recalled.contexts));
    // A recall whose digest no longer matches the region is ignored.
    var stale: TestRecall = .{ .prepared = &walked, .corrupt = true };
    const fallback = try prepareKeys(arena, .{ .context = &stale, .names = TestRecall.names });
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(walked.contexts), std.mem.sliceAsBytes(fallback.contexts));
    try t.expectEqualSlices(u8, std.mem.sliceAsBytes(walked.recalled.digests), std.mem.sliceAsBytes(fallback.recalled.digests));
}

/// Check, for every function of `made`, that the lookups resolved from its recalled names equal the ones found by walking its tree.
/// Returns how many functions were compared and how many of them look something up in another module.
fn compareLookups(surface: *semantic_key.Surface, made: Prepared) !struct { functions: usize, crossing: usize } {
    var crossing: usize = 0;
    for (made.keys.recalled.names, 0..) |names, at| {
        const walked = try surface.functionLookups(at, null);
        const replayed = try surface.functionLookups(at, names);
        try t.expectEqual(walked.len, replayed.len);
        for (walked, replayed) |left, right| try t.expectEqualStrings(left, right);
        const own = surface.moduleOfKey(semantic_key.Surface.functionKey(at));
        for (walked) |text| {
            const split = std.mem.indexOfScalar(u8, text, 0x1f) orelse return error.TestUnexpectedResult;
            if ((try std.fmt.parseInt(usize, text[0..split], 10)) != own) {
                crossing += 1;
                break;
            }
        }
    }
    return .{ .functions = made.keys.recalled.names.len, .crossing = crossing };
}

test "the lookups of a function resolved from its recalled names equal those found by walking its tree, and a recalled list that disagrees with the tree shows" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const made = try prepareProject(arena, null);
    var surface = try semantic_key.Surface.initRecording(arena, made.compilation.src, made.compilation.syntax, made.index);
    defer surface.deinit();
    const compared = try compareLookups(&surface, made);
    try t.expectEqual(made.keys.keys.len, compared.functions);
    // `mid` calls into `lib`: the replay reproduces the lookups that cross modules, found or not.
    try t.expect(compared.crossing >= 2);
    // `gather` looks up `range`, `append` and `Acc`, of which the project declares only the last: a negative lookup is a lookup.
    const gather = try functionNamed(&surface, made, "gather");
    const walked = try surface.functionLookups(gather, null);
    try t.expect(walked.len > 0);
    // A recalled list that lost its names says there were no lookups, and one with a name the tree never mentions says one more: the
    // walk and the replay then disagree, which is how a record written from stale names is found.
    const lost = try surface.functionLookups(gather, &.{});
    try t.expectEqual(@as(usize, 0), lost.len);
    const names = made.keys.recalled.names[gather];
    const longer = try std.mem.concat(arena, semantic_key.Name, &.{ names, &.{.{ .text = "no_such_name_anywhere" }} });
    const extra = try surface.functionLookups(gather, longer);
    try t.expectEqual(walked.len + 1, extra.len);
}

test "the lookups of a member call resolved from its recalled names keep the owner the name was recorded with" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const files = [_]File{
        .{ .path = "main.selka", .bytes = "import lib\n\n\nfunc main() -> int:\n    mut xs: int[] = [1, 2]\n    return xs.len() + lib.plain(1)\n" },
        .{ .path = "lib.selka", .bytes = lib_source },
    };
    const made = try prepareFiles(arena, &files, null);
    var surface = try semantic_key.Surface.initRecording(arena, made.compilation.src, made.compilation.syntax, made.index);
    defer surface.deinit();
    // `xs.len()` is recorded as the name `len` owned by `xs`: replaying it as a bare `len` would consult another key.
    try t.expect(ownedNames(made.keys.recalled.names[0]) >= 1);
    const compared = try compareLookups(&surface, made);
    try t.expectEqual(made.keys.keys.len, compared.functions);
    try t.expect(compared.crossing >= 1);
}

/// How many of `names` were recorded with an owner (`owner.name(...)`).
fn ownedNames(names: []const semantic_key.Name) usize {
    var owned: usize = 0;
    for (names) |name| owned += @intFromBool(name.owner != null);
    return owned;
}

/// The index of the function of the lib project spelled `name`.
fn functionNamed(surface: *semantic_key.Surface, made: Prepared, name: []const u8) !usize {
    for (made.keys.keys, 0..) |_, at| {
        const spelled = try surface.nameOf(semantic_key.Surface.functionKey(at));
        if (std.mem.eql(u8, spelled, name) or std.mem.endsWith(u8, spelled, name)) return at;
    }
    return error.TestUnexpectedResult;
}

// spec-case: CHECK-SCALE-LEX-1
test "header discovery keeps its diagnostics and import facts after its scratch tokens are reset" {
    // Every module's tokens are released before the next module is read, so
    // what discovery keeps must live in the project arena.
    const files = [_]File{
        .{ .path = "main.selka", .bytes = "import lib\nimport unused\n\n\nfunc main() -> int:\n    return lib.value()\n" },
        .{ .path = "lib.selka", .bytes = "\n\npublic func value() -> int:\n    return 1\n" },
        .{ .path = "unused.selka", .bytes = "\n\npublic func other() -> int:\n    return 2\n" },
    };
    var provider: Files = .{ .entries = &files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    const imports = project.modules.items[0].imports;
    try t.expectEqual(@as(usize, 2), imports.len);
    try t.expectEqualStrings("lib", imports[0].name);
    try t.expect(imports[0].seen);
    try t.expect(!imports[1].seen);
    // A lexical failure in an imported module reports its located message.
    const broken = [_]File{
        .{ .path = "main.selka", .bytes = "import lib\n\n\nfunc main() -> int:\n    return lib.value()\n" },
        .{ .path = "lib.selka", .bytes = "module lib\n\n\npublic def value() -> int:\n    return 1 $ 2\n" },
    };
    var broken_provider: Files = .{ .entries = &broken };
    var failed = language.project.Project.init(t.allocator);
    defer failed.deinit();
    try t.expectError(error.SourceError, failed.load(.{ .context = &broken_provider, .read = Files.read }, "main", .{}));
    try t.expectEqualStrings("E_TOKEN", failed.problem.?.code);
    try t.expectEqualStrings("unexpected character in source", failed.problem.?.message);
}

// spec-case: CACHE-CHECKSUM-1
test "cached syntax decodes in place and a damaged entry is still a counted miss" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var caller = std.heap.ArenaAllocator.init(t.allocator);
    defer caller.deinit();
    var cache = language.frontend_cache.Cache.init(t.allocator, t.io, root, "check-scale-identity");
    const files = projectFiles(lib_source);
    var provider: Files = .{ .entries = &files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    const index = try language.interfaces.buildWithCache(&project, null, null);
    const module = project.modules.items[0];
    try cache.rememberSyntax(module.src, module.header.body_start, index.units[0].syntax);
    const hit = (try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)).?;
    try t.expectEqual(index.units[0].syntax.nodes.items.len, hit.nodes.items.len);
    try t.expectEqual(@as(usize, 1), cache.statistics.syntax.hits);
    const path = try cache.entryPath(cache.syntaxKey(module.src, module.header.body_start));
    defer t.allocator.free(path);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, path, t.allocator, .limited(1 << 24));
    defer t.allocator.free(bytes);
    bytes[bytes.len - 9] ^= 0x40;
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = path, .data = bytes });
    try t.expect((try cache.lookupSyntax(caller.allocator(), module.src, module.header.body_start)) == null);
    try t.expectEqual(@as(usize, 1), cache.statistics.damaged);
}

// `user` reaches `shapes.Inner` only through a list element, a dictionary
// value, an Option payload and a call's return type, never by naming it.
const reach_shapes =
    \\public record Inner:
    \\    x: int
    \\public record Outer:
    \\    items: Inner[]
    \\    table: dict[str, Inner]
    \\    maybe: Inner?
    \\public func make() -> Outer:
    \\    mut items: Inner[] = []
    \\    append(mut items, Inner(x=1))
    \\    mut table: dict[str, Inner] = {}
    \\    return Outer(items=own items, table=own table, maybe=None)
    \\
;
const reach_user =
    \\import shapes
    \\public func first(o: shapes.Outer) -> int:
    \\    mut v = copy(o.items[0])
    \\    return v.x
    \\public func looked(o: shapes.Outer) -> int:
    \\    return o.table["k"].x
    \\public func maybe(o: shapes.Outer) -> int:
    \\    match o.maybe:
    \\        case Some(v):
    \\            return v.x
    \\        case None:
    \\            return 0
    \\public func chained() -> int:
    \\    return shapes.make().items[0].x
    \\
;

fn reachFiles(shapes: []const u8) [3]File {
    return .{
        .{ .path = "main.selka", .bytes = "import shapes\nimport user\nfunc main() -> int:\n    mut o = shapes.make()\n    return user.first(o) + user.looked(o) + user.maybe(o) + user.chained()\n" },
        .{ .path = "user.selka", .bytes = reach_user },
        .{ .path = "shapes.selka", .bytes = shapes },
    };
}

/// `reach_shapes` with each `from` replaced by the matching `to`.
fn shapesEdited(comptime edits: []const [2][]const u8) []const u8 {
    comptime var text: []const u8 = reach_shapes;
    inline for (edits) |edit| {
        const at = comptime std.mem.indexOf(u8, text, edit[0]).?;
        text = text[0..at] ++ edit[1] ++ text[at + edit[0].len ..];
    }
    return text;
}

// spec: SEMANTIC-KEY-TRANSITIVE-1
test "renaming fields reached through copied list values, dict, Option and return types re-checks every user" {
    const original = reachFiles(reach_shapes);
    const renamed = reachFiles(shapesEdited(&.{ .{ "    x: int", "    y: int" }, .{ "Inner(x=1)", "Inner(y=1)" } }));
    const outcome = try checkAfterEdit(&original, &renamed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // All four `user` bodies read the renamed field: none may stand in.
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, outcome.cold.diagnostics, "E_UNKNOWN_FIELD"));
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    const lowering = try checkAfterEditAs(&original, &renamed, .lowering);
    defer lowering.warm.deinit();
    defer lowering.cold.deinit();
    try t.expectEqualStrings(lowering.cold.diagnostics, lowering.warm.diagnostics);
}

// spec-case: SEMANTIC-KEY-TRANSITIVE-1
test "retyping a field reached only through element and return types re-checks every user" {
    const original = reachFiles(reach_shapes);
    const retyped = reachFiles(shapesEdited(&.{ .{ "    x: int", "    x: float" }, .{ "Inner(x=1)", "Inner(x=1.0)" } }));
    const outcome = try checkAfterEdit(&original, &retyped);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 4), std.mem.count(u8, outcome.cold.diagnostics, "error["));
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // A field type edit that keeps every body valid still re-checks them, and
    // the facts a lowering command publishes are the cold ones.
    const widened = reachFiles(shapesEdited(&.{ .{ "    x: int", "    x: int\n    tags: int[]" }, .{ "Inner(x=1)", "Inner(x=1, tags=[])" } }));
    const lowering = try checkAfterEditAs(&original, &widened, .lowering);
    defer lowering.warm.deinit();
    defer lowering.cold.deinit();
    try t.expectEqualStrings(lowering.cold.facts, lowering.warm.facts);
    try t.expectEqualStrings(lowering.cold.diagnostics, lowering.warm.diagnostics);
}

// spec: CHECK-SHAPES-1
test "a summary whose touched record shape no longer matches is not stood in" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const files = reachFiles(reach_shapes);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    const decoded_index = summary.decode(arena, seed.summaries.?).?;
    const decoded = try decoded_index.table(arena);
    try t.expect(decoded.records.len != 0);
    // Pretend the first record `first` touched had a different shape when the table was made: every body that touched it is checked again.
    const first = decoded_index.find("fn\x1fuser\x1f\x1ffirst").?;
    try t.expect(decoded.summaries[first].stubbable and decoded.summaries[first].uses.records.len != 0);
    const shapes = try arena.dupe([32]u8, decoded.record_shapes);
    shapes[decoded.summaries[first].uses.records[0]][0] ^= 1;
    const tampered = try summary.encode(arena, .{ .records = decoded.records, .record_shapes = shapes, .summaries = decoded.summaries });
    const warm = try checkProject(&files, tampered, .check);
    defer warm.deinit();
    const untouched = try checkProject(&files, seed.summaries.?, .check);
    defer untouched.deinit();
    try t.expect(warm.stood_in < untouched.stood_in);
    try t.expectEqual(untouched.checked + (untouched.stood_in - warm.stood_in), warm.checked);
    try t.expectEqualStrings(untouched.diagnostics, warm.diagnostics);
}

// spec-case: CHECK-SHAPES-1
test "a retained checked tree whose touched record shape no longer matches misses" {
    const files = reachFiles(reach_shapes);
    var cache = language.semantic_cache.Cache.init(t.allocator, 16 * 1024 * 1024);
    defer cache.deinit();
    try checkRetained(&files, &cache);
    try t.expect(cache.entries.len != 0);
    try checkRetained(&files, &cache);
    const reason = @backingInt(language.semantic_cache.MissReason.record_shape_changed);
    try t.expectEqual(@as(usize, 0), cache.statistics.rejections.total[reason]);
    corruptRecordShapes(&cache);
    const reused_before = cache.statistics.reused;
    try checkRetained(&files, &cache);
    try t.expect(cache.statistics.rejections.total[reason] != 0);
    try t.expectEqual(reused_before, cache.statistics.reused);
}

/// Pretend every retained tree was checked against different records.
fn corruptRecordShapes(cache: *language.semantic_cache.Cache) void {
    for (cache.entries) |entry| for (@constCast(entry.meta.record_refs)) |*reference| {
        reference.shape[0] ^= 1;
    };
}

/// Check the project `files` through the retained checked-tree path.
fn checkRetained(files: []const File, cache: *language.semantic_cache.Cache) !void {
    var provider: Files = .{ .entries = files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.checkWithCache(cache);
}

// spec-case: CHECK-SUMMARY-1
/// A table of four functions, their summaries in `summaries` and their keys indexed.
fn indexedKeys(allocator: std.mem.Allocator, summaries: []summary.Summary, keys: []const []const u8) !summary.Index {
    var index: summary.Index = .{ .summaries = summaries };
    for (keys, summaries, 0..) |key, *entry, position| {
        entry.* = .{ .key = key, .context = @splat(0), .region = .{ .len = 0, .digest = @splat(0), .names = &.{} }, .fact = .{}, .stubbable = true };
        try index.by_key.put(allocator, key, @intCast(position));
    }
    return index;
}

test "G2p findNear answers what find answers whatever the hint" {
    const keys = [_][]const u8{ "fn\x1fa\x1f\x1fone", "fn\x1fa\x1f\x1ftwo", "fn\x1fb\x1f\x1fone", "fn\x1fb\x1f\x1fthree" };
    var summaries: [keys.len]summary.Summary = undefined;
    var index = try indexedKeys(std.testing.allocator, &summaries, &keys);
    defer index.by_key.deinit(std.testing.allocator);
    // A right hint, a wrong one, one past the end, and a key the table does not hold.
    try std.testing.expectEqual(@as(?u32, 2), index.findNear(keys[2], 2));
    try std.testing.expectEqual(@as(?u32, 2), index.findNear(keys[2], 0));
    try std.testing.expectEqual(@as(?u32, 3), index.findNear(keys[3], 4));
    try std.testing.expectEqual(@as(?u32, 0), index.findNear(keys[0], std.math.maxInt(u32)));
    try std.testing.expectEqual(@as(?u32, null), index.findNear("fn\x1fz\x1f\x1fnone", 1));
    for (keys) |key| try std.testing.expectEqual(index.find(key), index.findNear(key, 1));
}

test "stored summaries round-trip and a foreign payload is refused" {
    const original = projectFiles(lib_source);
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const decoded = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    try t.expectEqual(@as(usize, 7), decoded.count());
    try t.expect(decoded.find("fn\x1fmain\x1f\x1fmain") != null);
    try t.expect(!decoded.at(decoded.find("fn\x1fmain\x1f\x1fmain").?).stubbable);
    try t.expect(summary.decode(arena_state.allocator(), seed.summaries.?[0 .. seed.summaries.?.len - 1]) == null);
    try t.expect(summary.decode(arena_state.allocator(), "not a summary table") == null);
}

/// Count spellings whose lexer-free answer differs from `qualifiedName(lex(...))`.
/// A spelling the fast path defers (`slow`) is not compared: the caller lexes it.
fn quickDisagreements(spellings: []const []const u8) !usize {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var count: usize = 0;
    for (spellings) |text| {
        const quick = lexer.quickQualifiedName(text);
        if (quick == .slow) continue;
        var sink: diagnostic.Sink = .{ .allocator = arena };
        const tokens = lexer.lex(arena, text, &sink) catch {
            count += 1;
            continue;
        };
        const slow = lexer.qualifiedName(text, tokens);
        const same = switch (quick) {
            .slow => unreachable,
            .none => slow == null,
            .name => |name| if (slow) |expected|
                std.mem.eql(u8, name.name, expected.name) and
                    (name.alias == null) == (expected.alias == null) and
                    std.mem.eql(u8, name.alias orelse "", expected.alias orelse "")
            else
                false,
        };
        if (!same) count += 1;
    }
    return count;
}

/// Lex `bytes` and return its token tags, owned by `arena`.
fn tags(arena: std.mem.Allocator, bytes: []const u8) ![]lexer.Tag {
    var sink: diagnostic.Sink = .{ .allocator = arena };
    const tokens = try lexer.lex(arena, bytes, &sink);
    const out = try arena.alloc(lexer.Tag, tokens.len);
    for (tokens, out) |token, *tag| tag.* = token.tag;
    return out;
}

// spec: CHECK-SCALE-LEX-1
test "a dotted reference spelling normalizes without the lexer exactly as with it" {
    const spellings = [_][]const u8{
        "value",         "m239.f239_00", "shared.units.area", "_hidden.x9", "len",     "xs.len",    "a.b.len", "True",
        "a.None",        "push",         "List",              "contains",   "f64_add", "a.f64_add", "a . b",   "a::b",
        "9lives",        "a..b",         ".a",                "a.",         "",        "x#y",
        "é",
        "Domain.member",
    };
    try t.expectEqual(@as(usize, 0), try quickDisagreements(&spellings));
    try t.expectEqualStrings("m239", lexer.quickQualifiedName("m239.f239_00").name.alias.?);
    try t.expectEqualStrings("f239_00", lexer.quickQualifiedName("m239.f239_00").name.name);
    try t.expectEqualStrings("shared.units", lexer.quickQualifiedName("shared.units.area").name.alias.?);
    // `len` is a prelude builtin name, not a reserved word (stage 0), so a dotted
    // `xs.len` normalizes as an ordinary name now.
    try t.expect(lexer.quickQualifiedName("xs.len") == .name);
    try t.expectEqualStrings("len", lexer.quickQualifiedName("xs.len").name.name);
    try t.expect(lexer.quickQualifiedName("a . b") == .slow);
    // A freed word (`f64_add`, stage 0 F7/F8) is an ordinary identifier, so the
    // quick path names it like any other reference instead of deferring.
    try t.expect(lexer.quickQualifiedName("a.f64_add") == .name);
}

// spec-case: CHECK-SCALE-LEX-1
test "reserved words removed spellings and layout lex exactly as before the keyword map" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const words = try tags(arena, "def class True False None and or not while whilex len push List __float_sqrt assert");
    const expected = [_]lexer.Tag{
        .kw_def, .kw_class, .kw_true, .kw_false, .kw_none, .and_and, .or_or, .bang, .kw_while, .ident, .ident, .ident, .ident, .kw_f64_sqrt, .kw_assert, .eof,
    };
    try t.expectEqualSlices(lexer.Tag, &expected, words);
    try t.expect(!lexer.isIdentifier("while"));
    try t.expect(lexer.isIdentifier("whilex"));
    // A soft builtin name is an identifier: `len(xs)` stays a builtin call in the
    // parser, while a binding, parameter or field may be spelled `len`.
    try t.expect(lexer.isIdentifier("len"));
    var sink: diagnostic.Sink = .{ .allocator = arena };
    // A freed word (`f64_add`, stage 0 F7/F8) lexes as an identifier; its old
    // *use* is what reports the migration, in the checker.
    const freed = try lexer.lex(arena, "x = f64_add", &sink);
    try t.expectEqual(@as(usize, 4), freed.len);
    try t.expectEqual(lexer.Tag.ident, freed[0].tag);
    try t.expectEqual(lexer.Tag.ident, freed[2].tag);
    // No word is refused at tokenization any more (F7): the lexical channel
    // keeps only removed punctuation, which still reports where it is written.
    try t.expect(!removed_names.removedLexically("wrap"));
    try t.expectError(error.SourceError, lexer.lex(arena, "x = a => b", &sink));
    try t.expectEqualStrings("E_REMOVED_SPELLING", sink.items.items[0].code);
    // A multi-line string ends its line; the next token opens a new statement.
    const layout = try tags(arena, "def f() -> str:\n    s = '''a\nb'''\n    return s\nx = 1\n");
    const layout_expected = [_]lexer.Tag{
        .kw_def, .ident, .lparen, .rparen, .arrow, .ident, .indent, .ident, .equal, .bytes, .kw_return, .ident, .dedent, .ident, .equal, .integer, .eof,
    };
    try t.expectEqualSlices(lexer.Tag, &layout_expected, layout);
}

/// Build the bounded declaration explicitly; fail if fixture drift makes it a no-op.
fn boundedMidSource(allocator: std.mem.Allocator) ![]u8 {
    const declaration = "public func bounded(n: int) -> int:";
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, mid_source, declaration));
    const bounded = try std.mem.replaceOwned(u8, allocator, mid_source, declaration, "@noalloc\n" ++ declaration);
    errdefer allocator.free(bounded);
    try t.expect(!std.mem.eql(u8, bounded, mid_source));
    try t.expect(std.mem.indexOf(u8, bounded, "@noalloc\n" ++ declaration) != null);
    return bounded;
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "allocation contract summaries retain concrete bounded closures across reordered declarations" {
    var original = projectFiles(lib_source);
    original[1].bytes = try boundedMidSource(t.allocator);
    defer t.allocator.free(original[1].bytes);
    const unchanged = try checkAfterEditAs(&original, &original, .allocation_contracts);
    defer unchanged.warm.deinit();
    defer unchanged.cold.deinit();
    try t.expectEqual(@as(usize, 3), unchanged.warm.checked);
    try t.expectEqual(@as(usize, 4), unchanged.warm.stood_in);
    try t.expectEqualStrings(unchanged.cold.facts, unchanged.warm.facts);
    const gather_at = comptime std.mem.indexOf(u8, lib_source, "public func gather").?;
    const plain_at = comptime std.mem.indexOf(u8, lib_source, "public func plain").?;
    const reordered_source = lib_source[0..gather_at] ++ lib_source[plain_at..] ++ "\n\n" ++ lib_source[gather_at..plain_at];
    var reordered = projectFiles(reordered_source);
    reordered[1].bytes = original[1].bytes;
    const moved = try checkAfterEditAs(&original, &reordered, .allocation_contracts);
    defer moved.warm.deinit();
    defer moved.cold.deinit();
    try t.expectEqual(@as(usize, 3), moved.warm.checked);
    try t.expectEqual(@as(usize, 4), moved.warm.stood_in);
    try t.expectEqualStrings(moved.cold.facts, moved.warm.facts);
    try t.expectEqualStrings(moved.cold.diagnostics, moved.warm.diagnostics);
}

const side_source =
    \\public func lonely(n: int) -> int:
    \\    return n - 1
    \\
;
const side_main_source =
    \\import mid
    \\import side
    \\
    \\
    \\func main() -> int:
    \\    return mid.twice(3) + mid.bounded(2) + mid.count(1) + side.lonely(4)
    \\
;

/// The chain of `projectFiles` with `bounded` promising `@noalloc` and a module no function of the chain imports.
fn boundedProject(allocator: std.mem.Allocator, bounded_body: []const u8) ![4]File {
    const declaration = "public func bounded(n: int) -> int:\n    return lib.plain(n) * 2";
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, mid_source, declaration));
    const edited = try std.mem.replaceOwned(u8, allocator, mid_source, declaration, bounded_body);
    return .{
        .{ .path = "main.selka", .bytes = side_main_source },
        .{ .path = "mid.selka", .bytes = edited },
        .{ .path = "lib.selka", .bytes = lib_source },
        .{ .path = "side.selka", .bytes = side_source },
    };
}

// spec: FRONTEND-ALLOCATION-SUMMARY-1
test "a changed bounded body keeps concrete what it can name, and no more" {
    const original_body = "@noalloc\npublic func bounded(n: int) -> int:\n    return lib.plain(n) * 2";
    const changed_body = "@noalloc\npublic func bounded(n: int) -> int:\n    return lib.plain(n) * 3";
    const original = try boundedProject(t.allocator, original_body);
    defer t.allocator.free(original[1].bytes);
    const changed = try boundedProject(t.allocator, changed_body);
    defer t.allocator.free(changed[1].bytes);
    const outcome = try checkAfterEditAs(&original, &changed, .allocation_contracts);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // The edited bounded body and the entry point are checked, with the five other functions of `mid` and `lib`, which it can call.
    // `side` is no module `mid` imports, so its function stays stood in; before G2i the edit sent the whole program to a full check.
    try t.expectEqual(@as(usize, 7), outcome.warm.checked);
    try t.expectEqual(@as(usize, 1), outcome.warm.stood_in);
    try t.expectEqual(@as(usize, 8), outcome.cold.checked);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
}

// spec: FRONTEND-ALLOCATION-SUMMARY-1
test "a call added to a bounded body reaches a function the previous summaries did not link it to" {
    const original_body = "@noalloc\npublic func bounded(n: int) -> int:\n    return lib.plain(n) * 2";
    const added_body = "@noalloc\npublic func bounded(n: int) -> int:\n    return lib.plain(n) * 2 + lib.spread(n)";
    const original = try boundedProject(t.allocator, original_body);
    defer t.allocator.free(original[1].bytes);
    const added = try boundedProject(t.allocator, added_body);
    defer t.allocator.free(added[1].bytes);
    const outcome = try checkAfterEditAs(&original, &added, .allocation_contracts);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `lib.spread` was not in the bounded body's closure before the edit and is stood in; the new call needs its tree, so the
    // edit keeps every function of `lib` concrete.
    try t.expectEqual(@as(usize, 7), outcome.warm.checked);
    try t.expectEqual(@as(usize, 1), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
}

// spec: FRONTEND-ALLOCATION-SUMMARY-1
test "a callee of a bounded body that gains a call keeps the new callee concrete" {
    const body = "@noalloc\npublic func bounded(n: int) -> int:\n    return lib.plain(n) * 2";
    const original = try boundedProject(t.allocator, body);
    defer t.allocator.free(original[1].bytes);
    var changed = original;
    changed[2].bytes = libEdited("public func plain(n: int) -> int:\n    return n + 1\n", "public func plain(n: int) -> int:\n    return n + spread(n)\n");
    const outcome = try checkAfterEditAs(&original, &changed, .allocation_contracts);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `plain` is changed and `bounded` calls it, so everything `plain` can name is concrete: `spread` was linked to nothing the previous
    // summaries followed from `plain`, and a stood-in `spread` would have no tree for the allocation check to read. `mid`'s other two
    // bodies and `side` stay stood in.
    try t.expectEqual(@as(usize, 5), outcome.warm.checked);
    try t.expectEqual(@as(usize, 3), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
}

const extern_lib_tail =
    \\
    \\
    \\extern func scale(host: Host, n: int) -> int
    \\
;

// spec: CHECK-SUMMARY-1
test "a declaration kind that cannot stand in whole stands in for its passes alone: its facts and warnings are replayed and its body is checked as usual" {
    const original = projectFiles(lib_source ++ extern_lib_tail);
    const outcome = try checkAfterEdit(&original, &original);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // The entry point and the extern declaration are the two bodies checked; the extern's summary cannot stand in whole (a foreign
    // declaration is checked for its signature), but its passes are not run again, so it counts with the six functions that stand in.
    try t.expectEqual(@as(usize, 2), outcome.warm.checked);
    try t.expectEqual(@as(usize, 7), outcome.warm.stood_in);
    try t.expectEqual(@as(usize, 8), outcome.cold.checked);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "W_UNUSED_BINDING") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    // Editing the declaration checks and analyses it again.
    const edited = projectFiles(lib_source ++ "\n\nextern func scale(host: Host, n: int, m: int) -> int\n");
    const changed = try checkAfterEdit(&original, &edited);
    defer changed.warm.deinit();
    defer changed.cold.deinit();
    try t.expectEqualStrings(changed.cold.diagnostics, changed.warm.diagnostics);
    try t.expectEqualStrings(changed.cold.facts, changed.warm.facts);
    try t.expect(changed.warm.stood_in < outcome.warm.stood_in);
}

// spec: CHECK-SUMMARY-1
test "a constant stands in whole: its body is neither checked nor replayed, and an edit to its value checks it again" {
    const tail =
        \\
        \\
        \\const margin: int = 2
        \\
        \\
        \\public func padded(n: int) -> int:
        \\    return n + margin
        \\
    ;
    const original = projectFiles(lib_source ++ tail);
    const outcome = try checkAfterEdit(&original, &original);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 1), outcome.warm.checked);
    try t.expectEqual(@as(usize, 8), outcome.warm.stood_in);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    const edited = projectFiles(lib_source ++ "\n\nconst margin: int = 3\n\n\npublic func padded(n: int) -> int:\n    return n + margin\n");
    const changed = try checkAfterEdit(&original, &edited);
    defer changed.warm.deinit();
    defer changed.cold.deinit();
    try t.expectEqualStrings(changed.cold.diagnostics, changed.warm.diagnostics);
    try t.expectEqualStrings(changed.cold.facts, changed.warm.facts);
    try t.expect(changed.warm.checked >= 2);
}

// spec: CHECK-SUMMARY-1
test "verify sampling withholds a pass stand-in and finds a stored summary that is not what the passes compute" {
    const original = projectFiles(lib_source ++ extern_lib_tail);
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    // Every pass stand-in is withheld and compared: the extern declaration's is the only one here, and it agrees with the passes.
    const honest = try checkProject(&original, seed.summaries.?, .verify);
    defer honest.deinit();
    try t.expect(honest.verified >= 1);
    try t.expectEqual(@as(u32, 0), honest.mismatched);
    try t.expectEqualStrings(seed.facts, honest.facts);
    try t.expectEqualStrings(seed.diagnostics, honest.diagnostics);
    // A stored fact that says the declaration's passes found something they do not is found.
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const decoded_index = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    const decoded = try decoded_index.table(arena_state.allocator());
    const tampered = try arena_state.allocator().dupe(summary.Summary, decoded.summaries);
    const at = decoded_index.find("fn\x1flib\x1f\x1fscale") orelse return error.TestUnexpectedResult;
    tampered[at].fact.inferred.writes = !tampered[at].fact.inferred.writes;
    const forged = try summary.encode(t.allocator, .{ .records = decoded.records, .record_shapes = decoded.record_shapes, .summaries = tampered });
    defer t.allocator.free(forged);
    const found = try checkProject(&original, forged, .verify);
    defer found.deinit();
    try t.expect(found.mismatched >= 1);
    // The finding names the function and what differed.
    try t.expect(std.mem.indexOf(u8, found.first, "scale") != null and std.mem.indexOf(u8, found.first, "facts") != null);
    // The stale stand-in was not trusted: what the check reports is what a check without summaries reports.
    try t.expectEqualStrings(seed.diagnostics, found.diagnostics);
}

const value_table_source =
    \\public record Entry:
    \\    name: str
    \\    run: func(int) -> int
    \\
    \\
    \\func scale(x: int) -> int:
    \\    return x * 3
    \\
    \\
    \\func one(x: int) -> int:
    \\    return scale(x) + 1
    \\
    \\
    \\func two(x: int) -> int:
    \\    return x * 2
    \\
    \\
    \\public func entries() -> Entry[]:
    \\    return [Entry(name="one", run=one), Entry(name="two", run=two)]
    \\
;

fn valueTableProject(comptime label: []const u8) [3]File {
    const note = "public func label() -> str:\n    return \"" ++ label ++ "\"\n";
    return .{
        .{ .path = "main.selka", .bytes = "import note\nimport tbl\n\n\nfunc main() -> int:\n    return len(tbl.entries()) + len(note.label())\n" },
        .{ .path = "tbl.selka", .bytes = value_table_source },
        .{ .path = "note.selka", .bytes = note },
    };
}

/// The line of `facts` that describes the function `name`.
fn factsLineOf(facts: []const u8, name: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, facts, '\n');
    while (lines.next()) |line| if (std.mem.startsWith(u8, line, name) and line.len > name.len and line[name.len] == ' ') return line;
    return "";
}

// spec: CHECK-SUMMARY-1
test "a body that stands in still keeps the functions it names as values visible to other units" {
    const original = valueTableProject("a");
    const changed = valueTableProject("b");
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `entries` stands in, with no checked nodes of its own, and `main` is the one body checked in `tbl`'s place.
    try t.expect(outcome.warm.stood_in >= 2);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    // The two functions a table names as values can be named from another unit; the function that is only called is private to its module.
    try t.expect(std.mem.endsWith(u8, factsLineOf(outcome.warm.facts, "tbl::one"), "private=false"));
    try t.expect(std.mem.endsWith(u8, factsLineOf(outcome.warm.facts, "tbl::two"), "private=false"));
    try t.expect(std.mem.endsWith(u8, factsLineOf(outcome.warm.facts, "tbl::scale"), "private=true"));
}

// spec: CHECK-SUMMARY-1
test "verify sampling finds a stored summary that forgets a function its body names as a value" {
    const files = valueTableProject("a");
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    const honest = try checkProject(&files, seed.summaries.?, .verify);
    defer honest.deinit();
    try t.expect(honest.verified >= 2);
    try t.expectEqual(@as(u32, 0), honest.mismatched);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const decoded_index = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    const entries = decoded_index.find("fn\x1ftbl\x1f\x1fentries") orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 2), decoded_index.valuesAt(entries).len);
    const decoded = try decoded_index.table(arena_state.allocator());
    const tampered = try arena_state.allocator().dupe(summary.Summary, decoded.summaries);
    tampered[entries].uses.values = tampered[entries].uses.values[0..1];
    const forged = try summary.encode(t.allocator, .{ .records = decoded.records, .record_shapes = decoded.record_shapes, .summaries = tampered });
    defer t.allocator.free(forged);
    const found = try checkProject(&files, forged, .verify);
    defer found.deinit();
    try t.expect(found.mismatched >= 1);
    try t.expect(std.mem.indexOf(u8, found.first, "entries") != null and std.mem.indexOf(u8, found.first, "function values") != null);
}

/// A library of callees whose inferred facts a body edit can change without touching a signature, and callers of each.
fn calleeFactsProject(comptime part: []const u8, comptime bump: []const u8, comptime choose: []const u8) [2]File {
    const library = "\n\npublic func part(text: str) -> str from text:\n" ++ part ++ "\n\n\npublic func bump(mut values: int[]) -> int:\n" ++ bump ++
        "\n\n\npublic func choose(first: int[], second: int[]) -> int[] from first, second:\n" ++ choose ++ "\n";
    return .{
        .{ .path = "main.selka", .bytes = callee_facts_main },
        .{ .path = "lib.selka", .bytes = library },
    };
}

const callee_facts_main =
    \\import lib
    \\
    \\
    \\func shout(text: str) -> str:
    \\    const kept = lib.part(text)
    \\    return kept
    \\
    \\
    \\func tick(n: int) -> int:
    \\    mut values: int[] = [n]
    \\    return lib.bump(mut values) + values[0]
    \\
    \\
    \\func pick(n: int) -> int:
    \\    mut first: int[] = [n]
    \\    mut second: int[] = [n + 1]
    \\    const chosen = lib.choose(first, second)
    \\    append(mut second, 3)
    \\    return chosen[0] + len(second)
    \\
    \\
    \\func main() -> int:
    \\    return len(shout("abcdefgh")) + tick(1) + pick(2)
    \\
;

const borrowing_part = "    return text[0:4]";
const copying_part = "    return copy(text[0:4])";
const reading_bump = "    return values[0]";
const writing_bump = "    values[0] += 1\n    return values[0]";
const first_choice = "    return first";
const second_choice = "    return second";
const copied_choice = "    return copy(first)";

/// Edit one callee's body (`callee` is its stable key), check the project in the mode a build checks it in (the callers' trees are needed,
/// since a callee's body changed), and require what a check with no summaries reports: the same diagnostics and the same facts of every
/// function. The callers of the edited function stand in for their passes all the same. `fact_changes` says whether the edit changes the
/// fact the summary stores for the callee: a result's origin is the declared one in every fact (`origins.buildSummaries`), so an edit to
/// the body of a function that declares `from` changes none, and a write to a `mut` parameter changes the callee's own.
fn expectCalleeEditAgrees(original: []const File, changed: []const File, callee: []const u8, fact_changes: bool) !void {
    const seed = try checkProject(original, null, .check);
    defer seed.deinit();
    const warm = try checkProject(changed, seed.summaries.?, .demand);
    defer warm.deinit();
    const cold = try checkProject(changed, null, .demand);
    defer cold.deinit();
    try t.expect(warm.summaries != null);
    try t.expectEqualStrings(cold.diagnostics, warm.diagnostics);
    try t.expectEqualStrings(cold.facts, warm.facts);
    // The two callers of the edited function that are not the entry point and the two functions that do not call it stand in.
    try t.expectEqual(@as(usize, 5), warm.stood_in);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const before = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    const after = summary.decode(arena_state.allocator(), warm.summaries.?).?;
    const was = before.at(before.find(callee) orelse return error.TestUnexpectedResult).*;
    const is = after.at(after.find(callee) orelse return error.TestUnexpectedResult).*;
    try t.expectEqual(fact_changes, !summary.sameFact(was.fact, is.fact));
}

// spec: CHECK-SUMMARY-1
test "a callee body edit that changes what the passes infer about it leaves its callers with the passes a check without summaries gives them" {
    const original = calleeFactsProject(borrowing_part, reading_bump, first_choice);
    // An accessor stops returning a borrow of its argument (its declared contract still says it may).
    try expectCalleeEditAgrees(&original, &calleeFactsProject(copying_part, reading_bump, first_choice), "fn\x1flib\x1f\x1fpart", false);
    // A callee starts writing the parameter it declares `mut`: its own fact changes.
    try expectCalleeEditAgrees(&original, &calleeFactsProject(borrowing_part, writing_bump, first_choice), "fn\x1flib\x1f\x1fbump", true);
    // A result's origin moves from one argument to the other, and then to a fresh value.
    try expectCalleeEditAgrees(&original, &calleeFactsProject(borrowing_part, reading_bump, second_choice), "fn\x1flib\x1f\x1fchoose", false);
    try expectCalleeEditAgrees(&original, &calleeFactsProject(borrowing_part, reading_bump, copied_choice), "fn\x1flib\x1f\x1fchoose", false);
}

// spec: FRONTEND-ALLOCATION-SUMMARY-1
test "F2 bounded body edits publish summaries for the next unrelated edit" {
    for ([_]Mode{ .check, .allocation_contracts }) |mode| try boundedSummarySequence(mode);
}

fn boundedSummarySequence(mode: Mode) !void {
    var original = projectFiles(lib_source);
    original[1].bytes = try boundedMidSource(t.allocator);
    defer t.allocator.free(original[1].bytes);
    const seed = try checkProject(&original, null, mode);
    defer seed.deinit();
    var edited = original;
    edited[1].bytes = try std.mem.replaceOwned(u8, t.allocator, original[1].bytes, "lib.plain(n) * 2", "lib.plain(n) * 3");
    defer t.allocator.free(edited[1].bytes);
    const changed = try checkProject(&edited, seed.summaries.?, mode);
    defer changed.deinit();
    try t.expect(changed.summaries != null);
    var unrelated = edited;
    unrelated[2].bytes = libEdited("    return n + 1\n", "    return n + 2\n");
    const third = try checkProject(&unrelated, changed.summaries.?, mode);
    defer third.deinit();
    const cold = try checkProject(&unrelated, null, mode);
    defer cold.deinit();
    try t.expect(third.stood_in > 0);
    try t.expect(third.summaries != null);
    try t.expectEqualStrings(cold.facts, third.facts);
    try t.expectEqualStrings(cold.diagnostics, third.diagnostics);
}

// spec: FRONTEND-DEMAND-1
test "demand lowering omits unrelated trees and checks changed functions with their transitive consumers" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)"));
    const outcome = try checkAfterEditAs(&original, &changed, .demand);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 3), outcome.warm.checked);
    try t.expectEqual(@as(usize, 4), outcome.warm.omitted);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expect(outcome.warm.summaries != null);
}

/// `runProject` through the durable semantic body store at `root`, opened fresh for this call as a new process would open it.
fn checkDurable(root: []const u8, files: []const File, previous: ?[]const u8, mode: Mode) !Outcome {
    var store = semantic_store.Store.init(t.allocator, t.io, root, cache_key.Contract.default, language.semantic_cache.mutation_contract_version);
    defer store.deinit();
    return runProjectWith(files, previous, mode, .executable, .{ .durable = &store });
}

/// A lowering host that answers for whole modules, counting what it is asked. `claim` is how many members of a module it says are admitted,
/// all of them when `claim_all`; `deny` names a function (by the end of its key) that `allow` refuses whatever a module answer said.
const ModuleHost = struct {
    module_asks: usize = 0,
    function_asks: usize = 0,
    claim: bool = true,
    answer_modules: bool = true,
    refuse_suffix: []const u8 = "\x1f\x1fnone",

    fn demand(self: *ModuleHost) summary.Demand {
        return .{ .context = self, .allow = allow, .allow_module = if (self.answer_modules) allowModule else null, .body_dependencies = false, .facts_unread = true };
    }

    fn allow(context: *const anyopaque, key: []const u8, _: [32]u8, _: [32]u8) bool {
        const self: *ModuleHost = @ptrCast(@alignCast(@constCast(context)));
        self.function_asks += 1;
        return !std.mem.endsWith(u8, key, self.refuse_suffix);
    }

    fn allowModule(context: *const anyopaque, group: language.semantic_key.ModuleGroup, out: []bool) bool {
        const self: *ModuleHost = @ptrCast(@alignCast(@constCast(context)));
        self.module_asks += 1;
        if (!self.claim) return false;
        @memset(out, true);
        _ = group;
        return true;
    }
};

test "G2p a host that answers for a module leaves out the module's stood-in bodies as asking about each function would" {
    const files = projectFiles(lib_source);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    var plain = ModuleHost{ .answer_modules = false };
    const per_function = try runProjectWith(&files, seed.summaries.?, .demand, .executable, .{ .host = plain.demand() });
    defer per_function.deinit();
    var modules = ModuleHost{};
    const per_module = try runProjectWith(&files, seed.summaries.?, .demand, .executable, .{ .host = modules.demand() });
    defer per_module.deinit();
    try t.expect(per_function.omitted > 0);
    try t.expectEqual(per_function.omitted, per_module.omitted);
    try t.expectEqualStrings(per_function.diagnostics, per_module.diagnostics);
    try t.expectEqualStrings(per_function.facts, per_module.facts);
    try t.expect(modules.module_asks >= 1);
    try t.expectEqual(@as(usize, 0), plain.module_asks);
    // A Debug compiler asks about each function a module answer covered, to hold the two together; nothing else is asked.
    try t.expectEqual(per_function.omitted, modules.function_asks);
}

/// Whether the profile recorded a phase called `name`.
fn recorded(profile: *const language.timings.Profile, name: []const u8) bool {
    for (profile.records.phases[0..profile.records.len]) |phase| if (std.mem.eql(u8, phase.name, name)) return true;
    return false;
}

test "G2p the planning reports its phases, the module asks among them" {
    const files = projectFiles(lib_source);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    var host = ModuleHost{};
    var profile = language.timings.Profile.init(t.io, true, .compiler);
    const outcome = try runProjectWith(&files, seed.summaries.?, .demand, .executable, .{ .host = host.demand(), .profile = &profile });
    defer outcome.deinit();
    for ([_][]const u8{ "plan_decide", "plan_current", "plan_consumers", "plan_demand", "plan_groups", "plan_modules" }) |name| try t.expect(recorded(&profile, name));
}

test "G2p the modules are grouped for a request that asks no host, so whatever writes receipts after it can write the modules' records" {
    const files = projectFiles(lib_source);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    // Three modules, each with ordinary functions; the request has no demand host (a full retry has none).
    const outcome = try checkProject(&files, seed.summaries.?, .check);
    defer outcome.deinit();
    try t.expectEqual(@as(usize, 3), outcome.groups);
}

test "G2p a module answer that is a miss, or says nothing of some functions, falls back to asking about each function" {
    const files = projectFiles(lib_source);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    var plain = ModuleHost{ .answer_modules = false };
    const expected = try runProjectWith(&files, seed.summaries.?, .demand, .executable, .{ .host = plain.demand() });
    defer expected.deinit();
    var missing = ModuleHost{ .claim = false };
    const miss = try runProjectWith(&files, seed.summaries.?, .demand, .executable, .{ .host = missing.demand() });
    defer miss.deinit();
    try t.expectEqual(expected.omitted, miss.omitted);
    try t.expectEqual(plain.function_asks, missing.function_asks);
    try t.expect(missing.module_asks >= 1);
}

test "G2p a module answer that claims what the host would refuse is a finding when the request verifies" {
    const files = projectFiles(lib_source);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    // The host claims every function of a module but refuses `plain`; the request verifies one function in a million withheld, so the module
    // answer's functions are all compared with the host's own answers.
    var lying = ModuleHost{ .refuse_suffix = "\x1fplain" };
    const outcome = try runProjectWith(&files, seed.summaries.?, .demand, .executable, .{ .host = lying.demand(), .verify_every = 1_000_000 });
    defer outcome.deinit();
    try t.expect(outcome.verified > 0);
    try t.expectEqual(@as(u32, 1), outcome.mismatched);
    try t.expect(std.mem.endsWith(u8, outcome.first, "\x1fplain"));
}

test "a body stored under one ownership policy is served under another, and a stand-in is never served as a full body" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const files = projectFiles(lib_source);
    // The reference: a lowering check with no cache at all.
    const plain = try runProject(&files, null, .lowering, .executable);
    defer plain.deinit();
    // Seeds the durable body store with full checked trees and the summaries of the same project.
    const seed = try checkDurable(root, &files, null, .lowering);
    defer seed.deinit();
    try t.expect(seed.summaries != null);
    // Ownership admits every body: the omitted bodies are stood in, never checked, and so never stored as bodies.
    const admitted = try checkDurable(root, &files, seed.summaries.?, .demand);
    defer admitted.deinit();
    // Ownership refuses every omission, so every body needs its full tree: the store serves them and no stand-in does.
    const refused = try checkDurable(root, &files, seed.summaries.?, .lowering);
    defer refused.deinit();
    try t.expect(admitted.omitted > 0);
    try t.expectEqual(@as(usize, 0), refused.omitted);
    try t.expect(refused.reused > 0);
    try t.expectEqualStrings(plain.facts, admitted.facts);
    try t.expectEqualStrings(plain.diagnostics, admitted.diagnostics);
    try t.expectEqualStrings(plain.facts, refused.facts);
    try t.expectEqualStrings(plain.diagnostics, refused.diagnostics);
}

test "a build that publishes check summaries stores only the checked bodies a later build can read" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)"));
    const plain = try runProject(&changed, null, .lowering, .executable);
    defer plain.deinit();
    // A host that omits bodies is stood in whole by the summaries the build publishes: of the seven bodies only the entry point, which no
    // summary stands in for, is written. A host that omits nothing has no reuse but the store and keeps all seven.
    const seed = try checkDurable(root, &original, null, .build);
    defer seed.deinit();
    try t.expect(seed.summaries != null);
    try t.expectEqual(@as(usize, 7), seed.checked);
    try t.expectEqual(@as(usize, 1), seed.stored);
    var every = t.tmpDir(.{});
    defer every.cleanup();
    const every_root = try every.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(every_root);
    const keeping = try checkDurable(every_root, &original, null, .lowering);
    defer keeping.deinit();
    try t.expectEqual(@as(usize, 7), keeping.stored);
    // A host that restores the trees it asks for reads the stored body of a stood-in function, so its build writes all seven too.
    var restoring_dir = t.tmpDir(.{});
    defer restoring_dir.cleanup();
    const restoring_root = try restoring_dir.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(restoring_root);
    const restoring = try checkDurable(restoring_root, &original, null, .restore);
    defer restoring.deinit();
    try t.expectEqual(@as(usize, 7), restoring.stored);
    // The next build, after an edit, is served exactly: the edited body is the one checked, the entry point comes from the store, and the other
    // five stand in, so no body that was not written is wanted.
    const warm = try checkDurable(root, &changed, seed.summaries.?, .build);
    defer warm.deinit();
    try t.expectEqual(@as(usize, 1), warm.checked);
    try t.expectEqual(@as(usize, 5), warm.omitted);
    try t.expect(warm.reused >= 1);
    try t.expectEqualStrings(plain.facts, warm.facts);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
    // A host whose artifacts read callee bodies needs the tree of a function whose callee changed although its summary stands in whole: that
    // tree is kept, so the next time the callee changes it is restored and not checked again.
    var reading_dir = t.tmpDir(.{});
    defer reading_dir.cleanup();
    const reading_root = try reading_dir.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(reading_root);
    const reading_seed = try checkDurable(reading_root, &original, null, .demand);
    defer reading_seed.deinit();
    try t.expectEqual(@as(usize, 1), reading_seed.stored);
    const reading_first = try checkDurable(reading_root, &changed, reading_seed.summaries.?, .demand);
    defer reading_first.deinit();
    try t.expect(reading_first.stored >= 1);
    const again = projectFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 4)"));
    const reading_second = try checkDurable(reading_root, &again, reading_first.summaries.?, .demand);
    defer reading_second.deinit();
    try t.expect(reading_second.reused > reading_first.reused);
    try t.expect(reading_second.checked < reading_first.checked);
    try t.expectEqualStrings(plain.facts, reading_first.facts);
    // A host that refuses the artifact of `plain` needs its tree: it is not in the store, so it is checked afresh with the same result.
    const refused = try checkDurable(root, &changed, seed.summaries.?, .demand_missing);
    defer refused.deinit();
    try t.expect(refused.omitted < 5);
    try t.expectEqualStrings(plain.facts, refused.facts);
    try t.expectEqualStrings(plain.diagnostics, refused.diagnostics);
}

// spec: FRONTEND-DEMAND-1
test "a lowering host that reads no callee body leaves the callers of an edited function out of the check" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("public func plain(n: int) -> int:\n    return n + 1\n", "public func plain(n: int) -> int:\n    return n + 2\n"));
    // A host whose artifacts read callee bodies has the callers of `plain` checked with it.
    const reading = try checkAfterEditAs(&original, &changed, .demand);
    defer reading.warm.deinit();
    defer reading.cold.deinit();
    // The lowering host reads signatures: only `plain` and the entry point are checked, and the callers' trees stay out.
    const lowering = try checkAfterEditAs(&original, &changed, .build);
    defer lowering.warm.deinit();
    defer lowering.cold.deinit();
    try t.expectEqual(@as(usize, 2), lowering.warm.checked);
    try t.expect(lowering.warm.checked < reading.warm.checked);
    try t.expect(lowering.warm.omitted > reading.warm.omitted);
    for ([_]@TypeOf(lowering){ reading, lowering }) |outcome| {
        try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
        try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
        try t.expect(outcome.warm.summaries != null);
    }
}

// spec: FRONTEND-DEMAND-1
test "an edit that changes what the edited function writes does not repeat the check in full" {
    const original = calleeFactsProject(borrowing_part, reading_bump, first_choice);
    const changed = calleeFactsProject(borrowing_part, writing_bump, first_choice);
    const outcome = try checkAfterEditAs(&original, &changed, .build);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `bump` starts writing its `mut` parameter, so its stored fact is not the one its new text gives it. Its callers read its declaration, not
    // that fact: the edited function and the entry point are the two bodies checked, and what is reported is what a check with no summaries reports.
    try t.expectEqual(@as(usize, 2), outcome.warm.checked);
    try t.expect(outcome.cold.checked > 2 * outcome.warm.checked);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    // A command with no host that says so holds the edited body's facts against the stored ones, and a change repeats the check in full.
    const repeating = try checkAfterEditAs(&original, &changed, .lowering);
    defer repeating.warm.deinit();
    defer repeating.cold.deinit();
    try t.expectEqual(@as(usize, 0), repeating.warm.stood_in);
    try t.expectEqualStrings(repeating.cold.facts, repeating.warm.facts);
}

// spec-case: FRONTEND-DEMAND-1
test "demand lowering propagates changed inferred facts without reconstructing unrelated bodies" {
    const original = projectFiles(lib_source);
    const pure = projectFiles(libEdited("    mut ys: int[] = [n, n + 1]\n    mut unused = 3\n    return ys[0] + ys[1]\n", "    mut unused = 3\n    return n + n + 1\n"));
    const outcome = try checkAfterEditAs(&original, &pure, .demand);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 3), outcome.warm.checked);
    try t.expectEqual(@as(usize, 4), outcome.warm.omitted);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expect(outcome.warm.summaries != null);
}

// spec-case: FRONTEND-DEMAND-1
test "demand lowering requires a host artifact and reports a changed body's diagnostics from the first attempt" {
    const original = projectFiles(lib_source);
    const changed = projectFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)"));
    const missing = try checkAfterEditAs(&original, &changed, .demand_missing);
    defer missing.warm.deinit();
    defer missing.cold.deinit();
    try t.expectEqual(@as(usize, 4), missing.warm.checked);
    try t.expectEqual(@as(usize, 3), missing.warm.omitted);
    try t.expectEqualStrings(missing.cold.facts, missing.warm.facts);
    try t.expectEqualStrings(missing.cold.diagnostics, missing.warm.diagnostics);
    const readonly_original = readonlyMutationProject(false);
    const changed_write = readonlyMutationProject(true);
    const rejected = try checkAfterEditAs(&readonly_original, &changed_write, .demand);
    defer rejected.warm.deinit();
    defer rejected.cold.deinit();
    // The rejected body is the changed one: the first attempt reports it, with the unrelated
    // trees still omitted, instead of repeating every body.
    try t.expect(rejected.warm.omitted > 0);
    try t.expect(rejected.warm.checked < rejected.cold.checked);
    try t.expectEqual(@as(usize, 8), rejected.cold.checked);
    try t.expect(rejected.warm.summaries == null);
    try t.expectEqualStrings(rejected.cold.diagnostics, rejected.warm.diagnostics);
    try t.expect(std.mem.indexOf(u8, rejected.warm.diagnostics, "E_IMMUTABLE") != null);
}

// spec-case: FRONTEND-DEMAND-1
test "demand lowering retains usable ordinary summaries beside a generic specialization" {
    const original = [_]File{.{ .path = "main.selka", .bytes =
        \\func identity[T](value: T) -> T:
        \\    return value
        \\func specialized() -> int:
        \\    return identity(2)
        \\func independent(n: int) -> int:
        \\    return n + 1
        \\func main() -> int:
        \\    return specialized() + independent(1)
        \\
    }};
    const changed = [_]File{.{ .path = "main.selka", .bytes =
        \\func identity[T](value: T) -> T:
        \\    return value
        \\func specialized() -> int:
        \\    return identity(2)
        \\func independent(n: int) -> int:
        \\    return n + 1
        \\func main() -> int:
        \\    return specialized() + independent(2)
        \\
    }};
    const outcome = try checkAfterEditAs(&original, &changed, .demand);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual(@as(usize, 3), outcome.warm.checked);
    try t.expectEqual(@as(usize, 1), outcome.warm.omitted);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expect(outcome.warm.summaries != null);
}

const generic_stand_in_source =
    \\record Box[T]:
    \\    value: T
    \\
    \\
    \\func identity[T](value: T) -> T:
    \\    return value
    \\
    \\
    \\func relay[T](value: T) -> T:
    \\    return identity(value)
    \\
    \\
    \\func specialized() -> int:
    \\    return identity(2) + relay(3)
    \\
    \\
    \\func boxed(n: int) -> int:
    \\    const box = Box[int](value=n)
    \\    return box.value
    \\
    \\
    \\func parse(text: str) -> bytes fails str:
    \\    return try bytes.fromhex(text)
    \\
    \\
    \\func parsed(text: str) -> int:
    \\    match parse(text):
    \\        case Ok(data):
    \\            return len(data)
    \\        case Err(_):
    \\            return 9
    \\
    \\
    \\func independent(n: int) -> int:
    \\    return n + 1
    \\
    \\
    \\func main() -> int:
    \\    return specialized() + boxed(1) + parsed("00ff") + independent(MARK)
    \\
;

fn genericStandInProject(comptime mark: []const u8) [1]File {
    @setEvalBranchQuota(100_000);
    const at = comptime std.mem.indexOf(u8, generic_stand_in_source, "MARK").?;
    return .{.{ .path = "main.selka", .bytes = generic_stand_in_source[0..at] ++ mark ++ generic_stand_in_source[at + 4 ..] }};
}

// spec: FRONTEND-DEMAND-1
test "a body that names a specialization or a type interned while checking stands in whole, and what it names is registered again" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const original = genericStandInProject("1");
    const changed = genericStandInProject("2");
    const plain = try runProject(&changed, null, .lowering, .executable);
    defer plain.deinit();
    const seed = try checkDurable(root, &original, null, .lowering);
    defer seed.deinit();
    try t.expect(seed.summaries != null);
    const warm = try checkDurable(root, &changed, seed.summaries.?, .demand);
    defer warm.deinit();
    // `specialized` calls an instance, `boxed` names a generic record's instance, and `parse` and `parsed` name a `Result[bytes, str]`
    // that is first met while they are checked; none is checked or replayed. The entry point is the one body checked, and the other
    // four are left out.
    try t.expectEqual(@as(usize, 1), warm.checked);
    try t.expectEqual(@as(usize, 5), warm.omitted);
    try t.expect(warm.stood_in >= 5);
    // The instance and the interned record exist all the same: the functions and the diagnostics are those of a check with no cache.
    try t.expectEqualStrings(plain.facts, warm.facts);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
    // Every stand-in withheld and compared, whole ones included: the facts, the diagnostics and the references of each agree with the
    // body checked afresh.
    const verified = try checkDurable(root, &changed, seed.summaries.?, .verify);
    defer verified.deinit();
    // `relay` reaches `identity` through its own specialization: the stored templates hold both, the body names one.
    try t.expect(verified.verified >= 5);
    try t.expectEqual(@as(u32, 0), verified.mismatched);
    try t.expectEqualStrings(plain.facts, verified.facts);
    // A stored reference that is not what the body names is found.
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const decoded_index = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    const decoded = try decoded_index.table(arena_state.allocator());
    const tampered = try arena_state.allocator().dupe(summary.Summary, decoded.summaries);
    const specialized = decoded_index.find("fn\x1fmain\x1f\x1fspecialized") orelse return error.TestUnexpectedResult;
    const refs = tampered[specialized].uses.refs orelse return error.TestUnexpectedResult;
    const functions = try arena_state.allocator().dupe(@TypeOf(refs.functions[0]), refs.functions);
    functions[0].key = "spec\x1fother";
    tampered[specialized].uses.refs = .{ .functions = functions, .records = refs.records, .templates = refs.templates };
    const forged = try summary.encode(t.allocator, .{ .records = decoded.records, .record_shapes = decoded.record_shapes, .summaries = tampered });
    defer t.allocator.free(forged);
    const found = try checkDurable(root, &changed, forged, .verify);
    defer found.deinit();
    try t.expect(found.mismatched >= 1);
    try t.expect(std.mem.indexOf(u8, found.first, "specialized") != null and std.mem.indexOf(u8, found.first, "references") != null);
    // The type that is first met while a body is checked is named by a recipe in that body's summary.
    const parse = decoded_index.find("fn\x1fmain\x1f\x1fparse") orelse return error.TestUnexpectedResult;
    const parse_refs = tampered[parse].uses.refs orelse return error.TestUnexpectedResult;
    try t.expect(parse_refs.records.len != 0 and parse_refs.records[parse_refs.records.len - 1].recipes.len == 1);
    // Editing the template's body checks what names it again.
    const retemplated = [_]File{.{ .path = "main.selka", .bytes = comptime blk: {
        @setEvalBranchQuota(100_000);
        const at = std.mem.indexOf(u8, generic_stand_in_source, "    return value\n").?;
        break :blk (generic_stand_in_source[0..at] ++ "    const same = value\n    return same\n" ++ generic_stand_in_source[at + "    return value\n".len ..])[0..];
    } }};
    const edited = try checkDurable(root, &retemplated, seed.summaries.?, .demand);
    defer edited.deinit();
    const edited_plain = try runProject(&retemplated, null, .lowering, .executable);
    defer edited_plain.deinit();
    try t.expect(edited.omitted < warm.omitted);
    try t.expectEqualStrings(edited_plain.facts, edited.facts);
    try t.expectEqualStrings(edited_plain.diagnostics, edited.diagnostics);
}

const formatted_dependency_main = "import report\nfunc main(out: Stream) -> int:\n    return report.describe(out)\n";
const formatted_dependency_report = "import core.stats\npublic func describe(out: Stream) -> int:\n    print(out, f\"value {core.stats.total()}\")\n    return 0\n";

fn formattedDependencyProject(stats: []const u8) [3]File {
    return .{
        .{ .path = "main.selka", .bytes = formatted_dependency_main },
        .{ .path = "report.selka", .bytes = formatted_dependency_report },
        .{ .path = "core/stats.selka", .bytes = stats },
    };
}

// spec: CHECK-SUMMARY-3
test "summary validation invalidates formatted cross-module consumers after signature and visibility edits" {
    const original = formattedDependencyProject("public func total() -> int:\n    return 1\n");
    const signature = formattedDependencyProject("public func total(extra: int) -> int:\n    return extra\n");
    const arity = try checkAfterEdit(&original, &signature);
    defer arity.warm.deinit();
    defer arity.cold.deinit();
    try t.expectEqualStrings(arity.cold.diagnostics, arity.warm.diagnostics);
    try t.expect(std.mem.indexOf(u8, arity.warm.diagnostics, "E_ARITY") != null);
    try t.expect(arity.warm.summaries == null);
    const privacy = formattedDependencyProject("func total() -> int:\n    return 1\n");
    const private = try checkAfterEdit(&original, &privacy);
    defer private.warm.deinit();
    defer private.cold.deinit();
    try t.expectEqualStrings(private.cold.diagnostics, private.warm.diagnostics);
    try t.expect(std.mem.indexOf(u8, private.warm.diagnostics, "error[") != null);
    try t.expect(private.warm.summaries == null);
}

// spec-case: CHECK-SUMMARY-3
test "summary validation reports every dependent diagnostic of a renamed declaration" {
    const original = formattedDependencyProject("public func total() -> int:\n    return 1\npublic func direct() -> int:\n    return total()\n");
    const renamed = formattedDependencyProject("public func total_renamed() -> int:\n    return 1\npublic func direct() -> int:\n    return total()\n");
    const outcome = try checkAfterEdit(&original, &renamed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "E_UNKNOWN_SYMBOL") != null);
    try t.expect(outcome.warm.summaries == null);
}

// spec-case: CHECK-SUMMARY-3
test "summary validation and retained body caches both reject dotted import signature and privacy edits" {
    const original = formattedDependencyProject("public func total() -> int:\n    return 1\n");
    var cache = language.semantic_cache.Cache.init(t.allocator, 16 * 1024 * 1024);
    defer cache.deinit();
    try checkRetained(&original, &cache);
    try t.expect(cache.entries.len != 0);
    const signature = formattedDependencyProject("public func total(extra: int) -> int:\n    return extra\n");
    try t.expectError(error.SourceError, checkRetained(&signature, &cache));
    const context_reason = @backingInt(language.semantic_cache.MissReason.context_changed);
    try t.expect(cache.statistics.rejections.total[context_reason] != 0);
    try checkRetained(&original, &cache);
    const privacy = formattedDependencyProject("func total() -> int:\n    return 1\n");
    try t.expectError(error.SourceError, checkRetained(&privacy, &cache));
    const lowering = try checkAfterEditAs(&original, &signature, .lowering);
    defer lowering.warm.deinit();
    defer lowering.cold.deinit();
    try t.expectEqualStrings(lowering.cold.diagnostics, lowering.warm.diagnostics);
    try t.expect(std.mem.indexOf(u8, lowering.warm.diagnostics, "E_ARITY") != null);
}

// spec-case: CHECK-SHAPES-1
test "summary record shape admission preserves reordered touched lists" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const files = reachFiles(reach_shapes);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    const decoded = try (summary.decode(arena, seed.summaries.?).?).table(arena);
    const changed = try arena.dupe(summary.Summary, decoded.summaries);
    for (changed) |*entry| {
        const reordered = try arena.dupe(u32, entry.uses.records);
        std.mem.reverse(u32, reordered);
        entry.uses.records = reordered;
    }
    const payload = try summary.encode(arena, .{ .records = decoded.records, .record_shapes = decoded.record_shapes, .summaries = changed });
    const warm = try checkProject(&files, payload, .check);
    defer warm.deinit();
    const unchanged = try checkProject(&files, seed.summaries.?, .check);
    defer unchanged.deinit();
    try t.expectEqual(unchanged.checked, warm.checked);
    try t.expectEqual(unchanged.stood_in, warm.stood_in);
    try t.expectEqualStrings(unchanged.diagnostics, warm.diagnostics);
    try t.expectEqualStrings(unchanged.facts, warm.facts);
}

// spec-case: CHECK-SUMMARY-1
test "summary callee ordinals remain valid after preceding declarations are inserted" {
    const original = projectFiles(lib_source);
    const changed = projectFiles("func inserted(n: int) -> int:\n    return n + 2\n" ++ lib_source);
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    const warm = try checkProject(&changed, seed.summaries.?, .demand);
    defer warm.deinit();
    const cold = try checkProject(&changed, null, .demand);
    defer cold.deinit();
    try t.expect(warm.stood_in > 0);
    try t.expectEqualStrings(cold.diagnostics, warm.diagnostics);
    try t.expectEqualStrings(cold.facts, warm.facts);
    const repeated = try checkProject(&changed, warm.summaries.?, .demand);
    defer repeated.deinit();
    try t.expect(repeated.checked < warm.checked);
    try t.expectEqualStrings(cold.diagnostics, repeated.diagnostics);
    try t.expectEqualStrings(cold.facts, repeated.facts);
}

/// Original effect-clause inputs reject during project parsing, before summary production.
fn expectRemovedProject(files: []const File) !void {
    var provider: Files = .{ .entries = files };
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try project.load(.{ .context = &provider, .read = Files.read }, "main", .{});
    try t.expectError(error.SourceError, language.interfaces.build(&project));
    try t.expectEqualStrings("E_EFFECTS_REMOVED", project.problem.?.code);
}

// migrate-embedded: skip intentional original effect-bounded caller project
const legacy_mid_source =
    \\import lib
    \\
    \\
    \\public func twice(n: int) -> int:
    \\    return lib.gather(n) + lib.gather(n + 1)
    \\
    \\
    \\public func bounded(n: int) -> int effects():
    \\    return lib.plain(n) * 2
    \\
    \\
    \\public func count(n: int) -> int:
    \\    mut zs: int[] = [n]
    \\    return lib.spread(zs[0])
    \\
;

// spec-case: EFFECTS-REMOVED-1
test "the original summary and demand effect-negative project keeps its source" {
    var original = projectFiles(libEdited("    return n + 1\n", "    mut ws: int[] = [n]\n    return ws[0] + 1\n"));
    original[1].bytes = legacy_mid_source;
    try expectRemovedProject(&original);
    // migrate-embedded: skip intentional original alias-retarget effect-negative project
    const alias = aliasProject("import beta as source\n\n\npublic func bounded() -> Unit effects():\n    source.value()\n");
    try expectRemovedProject(&alias);
}

const h2_source =
    \\public func up(text: str) -> str from text:
    \\    return text
    \\
;
const h3_source =
    \\public func idle() -> int:
    \\    return 0
    \\
;
const helper_source =
    \\import h2
    \\import h3
    \\
    \\
    \\public func shout(text: str) -> str:
    \\    return f"{h2.up(text)}!"
    \\
;
const importer_source =
    \\import helper
    \\
    \\
    \\func main() -> int:
    \\    return len(helper.shout("a")) + 1
    \\
;

fn importerFiles(importer: []const u8) [4]File {
    return .{
        .{ .path = "main.selka", .bytes = importer },
        .{ .path = "helper.selka", .bytes = helper_source },
        .{ .path = "h2.selka", .bytes = h2_source },
        .{ .path = "h3.selka", .bytes = h3_source },
    };
}

test "a stood-in executable body keeps the imports its f-string holes use and still names an unused one" {
    const original = importerFiles(importer_source);
    const edited = importerFiles(importer_source[0 .. importer_source.len - "+ 1\n".len] ++ "+ 2\n");
    const outcome = try checkAfterEdit(&original, &edited);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    // `helper.shout` is stood in, so it is never resolved again: `h2`, used only inside its
    // f-string hole, must not be reported, and `h3`, not used at all, still is.
    try t.expect(outcome.warm.stood_in >= 1);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "`h2`") == null);
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "`h3` is never referenced") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
}

// A library has no entry point. Its first function is the placeholder entry index of the
// check: always checked, never a `main`. Everything else is stood in like an executable's.
const library_entry_source =
    \\import mid
    \\
    \\
    \\public func total(n: int) -> int:
    \\    return mid.twice(n) + mid.bounded(n)
    \\
    \\
    \\public func counted(n: int) -> int:
    \\    return mid.count(n)
    \\
;

fn libraryFiles(lib: []const u8) [3]File {
    return .{
        .{ .path = "main.selka", .bytes = library_entry_source },
        .{ .path = "mid.selka", .bytes = mid_source },
        .{ .path = "lib.selka", .bytes = lib },
    };
}

test "a library body edit stands in the other bodies and reports what an uncached library check reports" {
    const original = libraryFiles(lib_source);
    const changed = libraryFiles(libEdited("append(mut xs, k * 2)", "append(mut xs, k * 3)"));
    const seed = try checkLibrary(&original, null);
    defer seed.deinit();
    try t.expect(seed.summaries != null);
    const warm = try checkLibrary(&changed, seed.summaries.?);
    defer warm.deinit();
    const plain = try checkLibraryPlain(&changed);
    defer plain.deinit();
    // Eight bodies; the edited one and the placeholder entry index are checked, six stand in.
    try t.expectEqual(@as(usize, 8), seed.checked);
    try t.expectEqual(@as(usize, 6), warm.stood_in);
    try t.expectEqual(@as(usize, 2), warm.checked);
    // The stood-in `spread` still reports its unused binding, as the uncached check does.
    try t.expect(std.mem.indexOf(u8, warm.diagnostics, "W_UNUSED_BINDING") != null);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
    try t.expectEqualStrings(plain.facts, warm.facts);
}

test "an unchanged library stands in every body but the placeholder entry index" {
    const original = libraryFiles(lib_source);
    const seed = try checkLibrary(&original, null);
    defer seed.deinit();
    const warm = try checkLibrary(&original, seed.summaries.?);
    defer warm.deinit();
    const plain = try checkLibraryPlain(&original);
    defer plain.deinit();
    try t.expectEqual(@as(usize, 1), warm.checked);
    try t.expectEqual(@as(usize, 7), warm.stood_in);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
    try t.expectEqualStrings(plain.facts, warm.facts);
}

const library_user_source =
    \\import helper
    \\
    \\
    \\public func twice(text: str) -> str:
    \\    return helper.shout(helper.shout(text))
    \\
    \\
    \\public func other(n: int) -> int:
    \\    return n + 1
    \\
;

test "a stood-in library body keeps the imports its f-string holes use and still names an unused one" {
    const original = importerFiles(library_user_source);
    const edited = importerFiles(library_user_source[0 .. library_user_source.len - "    return n + 1\n".len] ++ "    return n + 2\n");
    const seed = try checkLibrary(&original, null);
    defer seed.deinit();
    const warm = try checkLibrary(&edited, seed.summaries.?);
    defer warm.deinit();
    const plain = try checkLibraryPlain(&edited);
    defer plain.deinit();
    // `helper.shout` is stood in; `h2` is used only inside its f-string hole and `h3` not at all.
    try t.expect(warm.stood_in >= 1);
    try t.expect(std.mem.indexOf(u8, warm.diagnostics, "`h2`") == null);
    try t.expect(std.mem.indexOf(u8, warm.diagnostics, "`h3` is never referenced") != null);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
}

test "an edit to an imported module re-checks the library body that calls it and reports the new error" {
    const original = importerFiles(library_user_source);
    // `up` gains a parameter: the f-string call in `helper.shout` no longer checks.
    const changed = [4]File{
        original[0],
        original[1],
        .{ .path = "h2.selka", .bytes = "public func up(text: str, extra: int) -> str from text:\n    return text\n" },
        original[3],
    };
    const seed = try checkLibrary(&original, null);
    defer seed.deinit();
    const warm = try checkLibrary(&changed, seed.summaries.?);
    defer warm.deinit();
    const plain = try checkLibraryPlain(&changed);
    defer plain.deinit();
    try t.expect(std.mem.indexOf(u8, warm.diagnostics, "error[E_ARITY]") != null);
    try t.expect(warm.summaries == null);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
}

test "a body that fails to check is reported by the first attempt without a repeat in full" {
    const original = projectFiles(lib_source);
    // `plain` returns text now: its own body fails, and so does the one body that calls it.
    const changed = projectFiles(libEdited("    return n + 1\n", "    return \"x\"\n"));
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expect(std.mem.indexOf(u8, outcome.warm.diagnostics, "error[E_TYPE]") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // A repeat in full would leave nothing stood in.
    try t.expect(outcome.warm.stood_in > 0);
    try t.expectEqual(@as(usize, 0), outcome.cold.stood_in);
    try t.expect(outcome.warm.summaries == null);
    // The library check takes the same shortcut.
    const library_original = libraryFiles(lib_source);
    const library_changed = libraryFiles(libEdited("    return n + 1\n", "    return \"x\"\n"));
    const seed = try checkLibrary(&library_original, null);
    defer seed.deinit();
    const warm = try checkLibrary(&library_changed, seed.summaries.?);
    defer warm.deinit();
    const plain = try checkLibraryPlain(&library_changed);
    defer plain.deinit();
    try t.expect(std.mem.indexOf(u8, warm.diagnostics, "error[E_TYPE]") != null);
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
    try t.expect(warm.stood_in > 0);
}

fn restoredTable(arena: std.mem.Allocator, index: summary.Index) !summary.Table {
    return index.table(arena);
}

/// Every prefix of `payload` and a payload with a byte too many is a miss, never a crash.
fn expectNoTruncationDecodes(payload: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    for (0..payload.len) |length| try t.expect(summary.decode(arena_state.allocator(), payload[0..length]) == null);
    const longer = try std.mem.concat(t.allocator, u8, &.{ payload, "x" });
    defer t.allocator.free(longer);
    try t.expect(summary.decode(arena_state.allocator(), longer) == null);
}

/// Encoding `table` with each of `hints` gives the bytes `expected`.
fn expectSizedEncodings(table: summary.Table, expected: []const u8, hints: []const summary.SizeHint) !void {
    for (hints) |hint| {
        const sized = try summary.encodeSized(t.allocator, table, hint);
        defer t.allocator.free(sized);
        try t.expectEqualSlices(u8, expected, sized);
    }
}

test "a summary table round trips through its compact payload and stays smaller than the plain codec's" {
    const files = libraryFiles(lib_source);
    const seed = try checkLibrary(&files, null);
    defer seed.deinit();
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const decoded = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    const whole = try restoredTable(arena_state.allocator(), decoded);
    try t.expectEqual(@as(usize, 8), decoded.count());
    // Encoding what was decoded gives the very payload that was decoded.
    const again = try summary.encode(t.allocator, whole);
    defer t.allocator.free(again);
    try t.expectEqualSlices(u8, seed.summaries.?, again);
    // G2p: the decoded index remembers the size of its payload, and encoding with that size (or with sizes far off) gives the same bytes.
    try t.expectEqual(seed.summaries.?.len, decoded.size.bytes);
    try expectSizedEncodings(whole, again, &.{ decoded.size, .{ .bytes = 1, .strings = 1 }, .{ .bytes = 1 << 20, .strings = 4096 } });
    // Names, notes and shapes survive: the unused binding `spread` reports is stored once and replayed.
    var notes: usize = 0;
    var names: usize = 0;
    for (whole.summaries) |entry| {
        notes += entry.notes.body.len + entry.notes.pass.len;
        names += entry.region.names.len;
    }
    try t.expect(notes >= 1);
    try t.expect(names >= 8);
    var plain = language.persist_codec.Writer.init(t.allocator);
    defer plain.deinit();
    try plain.write(summary.Table, whole);
    // Each section carries its own pools and fixed-width columns, so a small table keeps less of the saving than a large one.
    try t.expect(seed.summaries.?.len * 10 < plain.bytes.items.len * 9);
    try expectNoTruncationDecodes(seed.summaries.?);
}

test "a summary table keeps every kind of field through the compact payload" {
    const owner: ?[]const u8 = "Domain";
    const names = [_]semantic_key.Name{ .{ .text = "alpha.call" }, .{ .text = "member", .owner = owner }, .{ .text = "alpha.call" } };
    const body = [_]summary.Note{
        .{ .code = "W_UNUSED_BINDING", .severity = .warning, .start = 3, .end = 9, .message = "binding is never read" },
        .{ .code = "E_IMMUTABLE", .severity = .err, .start = 0, .end = 1_000_000, .message = "read-only", .rule = .B1 },
    };
    const rows = [_]summary.Summary{
        .{
            .key = "one::first",
            .context = @splat(1),
            .region = .{ .len = 300, .digest = @splat(2), .names = &names },
            .fact = .{ .mutates = &.{ 0, 70_000 % 65_536 }, .mutates_unknown = true, .return_origin = .{ .positions = &.{ 1, 2 }, .unknown = true }, .inferred = .{ .writes = true, .external = true } },
            .notes = .{ .body = &body, .pass = body[0..1] },
            .uses = .{ .callees = &.{ 1, 0 }, .values = &.{1}, .records = &.{ 0, 1 } },
            .stubbable = true,
        },
        .{
            .key = "one::second",
            .context = @splat(4),
            .region = .{ .len = 1, .digest = @splat(5) },
            .fact = .{},
            .uses = .{ .callees = &.{ 0, 1 } },
            .stubbable = false,
        },
    };
    const table: summary.Table = .{ .records = &.{ "Acc", "Row" }, .record_shapes = &.{ @splat(3), @splat(4) }, .summaries = &rows };
    const payload = try summary.encode(t.allocator, table);
    defer t.allocator.free(payload);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const index = summary.decode(arena_state.allocator(), payload).?;
    const first_at = index.find("one::first").?;
    const first = index.at(first_at).*;
    try t.expectEqual(@as(usize, 3), first.region.names.len);
    try t.expectEqualStrings("Domain", first.region.names[1].owner.?);
    try t.expect(first.region.names[2].owner == null);
    try t.expectEqualStrings("alpha.call", first.region.names[2].text);
    try t.expectEqual(@as(u16, 70_000 % 65_536), first.fact.mutates[1]);
    try t.expect(first.fact.mutates_unknown and first.fact.return_origin.unknown and first.fact.inferred.writes and first.fact.inferred.external);
    try t.expectEqual(@as(usize, 2), first.notes.body.len);
    try t.expect(first.notes.body[1].rule.? == .B1);
    try t.expectEqual(@as(u32, 1_000_000), first.notes.body[1].end);
    try t.expectEqualSlices(u8, &@as([32]u8, @splat(3)), &index.recordShape(first_at, first.uses.records[0]));
    try t.expectEqualSlices(u8, &@as([32]u8, @splat(4)), &index.recordShape(first_at, first.uses.records[1]));
    try t.expectEqualStrings("Acc", index.recordName(first_at, first.uses.records[0]));
    try t.expect(first.stubbable);
    const second_at = index.find("one::second").?;
    const second = index.at(second_at).*;
    try t.expect(!second.stubbable);
    // The functions a body names as values are stored beside its callees, and only for a body that names some.
    try t.expectEqualSlices(u32, &.{ second_at, first_at }, index.calleesAt(first_at));
    try t.expectEqualSlices(u32, &.{second_at}, index.valuesAt(first_at));
    try t.expectEqual(@as(usize, 0), index.valuesAt(second_at).len);
    const again = try summary.encode(t.allocator, try index.table(arena_state.allocator()));
    defer t.allocator.free(again);
    try t.expectEqualSlices(u8, payload, again);
    const zero = [_]summary.Summary{.{ .key = "z::zero", .context = @splat(0), .region = .{ .len = 0, .digest = @splat(0) }, .fact = .{}, .stubbable = false }};
    const zero_payload = try summary.encode(t.allocator, .{ .summaries = &zero });
    defer t.allocator.free(zero_payload);
    const restored_zero = summary.decode(arena_state.allocator(), zero_payload).?;
    try t.expectEqual(@as(usize, 1), restored_zero.count());
    try expectNoTruncationDecodes(payload);
}

const waiver_main_source =
    \\import lib
    \\import other
    \\
    \\
    \\func main() -> int:
    \\    if lib.sign(43) and other.sign(45):
    \\        return lib.plain(1)
    \\    return 0
    \\
;

const waiver_lib_source =
    \\public func sign(c: int) -> bool:
    \\    return c == 43 or c == 45 or c == 47
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

const waiver_other_source =
    \\public func sign(c: int) -> bool:
    \\    return c == 1 or c == 2 or c == 3
    \\
;

const file_waiver = "# lint: allow-file byte-set reason=\"the tests mirror the grammar\"\n";

fn waiverFiles(lib: []const u8) [3]File {
    return .{
        .{ .path = "main.selka", .bytes = waiver_main_source },
        .{ .path = "lib.selka", .bytes = lib },
        .{ .path = "other.selka", .bytes = waiver_other_source },
    };
}

/// How many `W_BYTE_SET` warnings the rendered diagnostics hold.
fn byteSetWarnings(rendered: []const u8) usize {
    return std.mem.count(u8, rendered, "W_BYTE_SET");
}

test "a file-wide waiver added to an unchanged module silences its warning on an edit build as on a cold build" {
    const original = waiverFiles(waiver_lib_source);
    const changed = waiverFiles(file_waiver ++ waiver_lib_source);
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    // Both modules draw the warning before the waiver; only the module that holds the waiver loses it.
    try t.expectEqual(@as(usize, 2), byteSetWarnings(seed.diagnostics));
    try t.expectEqual(@as(usize, 1), byteSetWarnings(outcome.warm.diagnostics));
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // `plain` and the other module's `sign` stand in (its warning is stored with a guard over its file's waivers, which did not change);
    // `main` is the entry, and the `sign` of the module whose waivers changed is analysed again, which is what silences its warning.
    try t.expectEqual(@as(usize, 2), outcome.warm.stood_in);
}

test "a file-wide waiver removed from a module brings its warning back on an edit build as on a cold build" {
    const original = waiverFiles(file_waiver ++ waiver_lib_source);
    const changed = waiverFiles(waiver_lib_source);
    const outcome = try checkAfterEdit(&original, &changed);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    try t.expectEqual(@as(usize, 1), byteSetWarnings(seed.diagnostics));
    try t.expectEqual(@as(usize, 2), byteSetWarnings(outcome.warm.diagnostics));
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    // The function the waiver silenced was not stood in, which is what lets its warning come back; the other module's `sign` was.
    try t.expectEqual(@as(usize, 2), outcome.warm.stood_in);
}

test "a file-wide waiver anywhere in its file waives, and one for another rule or another file does not" {
    const at_end = waiverFiles(waiver_lib_source ++ "\n\n" ++ file_waiver);
    const end_outcome = try checkAfterEdit(&at_end, &at_end);
    defer end_outcome.warm.deinit();
    defer end_outcome.cold.deinit();
    try t.expectEqual(@as(usize, 1), byteSetWarnings(end_outcome.warm.diagnostics));
    try t.expectEqualStrings(end_outcome.cold.diagnostics, end_outcome.warm.diagnostics);
    // The same comment naming another rule waives nothing here.
    const other_rule = waiverFiles("# lint: allow-file range-chain reason=\"unrelated\"\n" ++ waiver_lib_source);
    const rule_outcome = try checkAfterEdit(&other_rule, &other_rule);
    defer rule_outcome.warm.deinit();
    defer rule_outcome.cold.deinit();
    try t.expectEqual(@as(usize, 2), byteSetWarnings(rule_outcome.warm.diagnostics));
    try t.expectEqualStrings(rule_outcome.cold.diagnostics, rule_outcome.warm.diagnostics);
}

// FX13: a W13 refusal's text and repair read the file beyond the function's own region (a name another function binds,
// the file's imports, a declaration of the prelude name), so a check with the summaries of the file as it was must report
// exactly what a check without them reports, text and JSON (the repair's edits) alike. Since W13-S5 the sites are refused
// and no waiver excuses one; a refusing check publishes no summaries, and a check that passes again must pass warm too.

const w13_main_source =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    return lib.plain(1)
    \\
;

const w13_search_source =
    \\public func first_x(text: str) -> int:
    \\    const at = text.find("x", 1)
    \\    return at
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

const method_form_waiver = "# lint: allow-file method-form reason=\"pinned beside its home\"\n";

fn w13Files(lib: []const u8) [2]File {
    return .{
        .{ .path = "main.selka", .bytes = w13_main_source },
        .{ .path = "lib.selka", .bytes = lib },
    };
}

const w13_library_source =
    \\import lib
    \\
    \\
    \\public func head(n: int) -> int:
    \\    return lib.plain(n)
    \\
;

/// Check `changed` after `original` three ways, and require from each the text and JSON (the repairs' edits) a check without
/// any cache reports: an executable's check with the summaries `original` left, a library's check with its summaries, and a
/// lowering check served by the durable checked-body store `original` filled. Returns the W13 refusals reported.
fn expectW13AsCold(original: []const u8, changed: []const u8) !usize {
    const before = w13Files(original);
    const after = w13Files(changed);
    const outcome = try checkAfterEdit(&before, &after);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.json, outcome.warm.json);

    const library_before: [2]File = .{ .{ .path = "main.selka", .bytes = w13_library_source }, .{ .path = "lib.selka", .bytes = original } };
    const library_after: [2]File = .{ .{ .path = "main.selka", .bytes = w13_library_source }, .{ .path = "lib.selka", .bytes = changed } };
    const seed = try checkLibrary(&library_before, null);
    defer seed.deinit();
    const warm = try checkLibrary(&library_after, seed.summaries);
    defer warm.deinit();
    const plain = try checkLibraryPlain(&library_after);
    defer plain.deinit();
    try t.expectEqualStrings(plain.diagnostics, warm.diagnostics);
    try t.expectEqualStrings(plain.json, warm.json);

    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const filled = try checkDurable(root, &before, null, .lowering);
    defer filled.deinit();
    const served = try checkDurable(root, &after, null, .lowering);
    defer served.deinit();
    const fresh = try runProject(&after, null, .lowering, .executable);
    defer fresh.deinit();
    try t.expectEqualStrings(fresh.diagnostics, served.diagnostics);
    try t.expectEqualStrings(fresh.json, served.json);
    return std.mem.count(u8, outcome.warm.diagnostics, "E_METHOD_REMOVED") + std.mem.count(u8, outcome.warm.diagnostics, "E_REMOVED_SPELLING");
}

test "FX13: a method-form file waiver added after a check excuses no refusal (W13-S5)" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_search_source, w13_search_source ++ "\n" ++ method_form_waiver));
}

test "FX13: a method-form file waiver removed after a check leaves the refusal as it was (W13-S5)" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(method_form_waiver ++ w13_search_source, w13_search_source));
}

const w13_migrated_source =
    \\import strings
    \\
    \\
    \\public func first_x(text: str) -> int:
    \\    const at = strings.find(text, "x", 1)
    \\    return at.unwrap_or(0 - 1)
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

test "FX13: an edit that removes a file's last old spelling makes a cached check pass as an uncached one does (W13-S5)" {
    try t.expectEqual(@as(usize, 0), try expectW13AsCold(w13_search_source, w13_migrated_source));
}

test "FX13: an edit that brings an old spelling back makes a cached check refuse it as an uncached one does (W13-S5)" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_migrated_source, w13_search_source));
}

const w13_bound_source =
    \\public func digits(hex: str) -> int:
    \\    return len(hex)
    \\
    \\
    \\public func shown(data: bytes) -> str:
    \\    return data.hex()
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

const w13_renamed_source =
    \\public func digits(hex_text: str) -> int:
    \\    return len(hex_text)
    \\
    \\
    \\public func shown(data: bytes) -> str:
    \\    return data.hex()
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

test "FX13: renaming a parameter that hid a module restores the rewrite of a call in another function" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_bound_source, w13_renamed_source));
}

test "FX13: a parameter that hides a module, added in another function, withholds the rewrite" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_renamed_source, w13_bound_source));
}

const w13_imported_source =
    \\import strings
    \\
    \\
    \\public func loud(text: str) -> str:
    \\    return text.zfill(5)
    \\
    \\
    \\public func quiet(text: str) -> str:
    \\    return strings.lower(text)
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

const w13_unimported_source =
    \\
    \\
    \\
    \\public func loud(text: str) -> str:
    \\    return text.zfill(5)
    \\
    \\
    \\public func quiet(text: str) -> str:
    \\    return text
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

test "FX13: removing the import a rewrite relied on makes the rewrite add it" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_imported_source, w13_unimported_source));
}

const w13_sqrt_source =
    \\import math
    \\
    \\
    \\public func root(x: float) -> float:
    \\    return math.sqrt(x)
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

const w13_claimed_source =
    \\import math
    \\
    \\
    \\public func root(x: float) -> float:
    \\    return math.sqrt(x)
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
    \\
    \\func sqrt(x: float) -> float:
    \\    return x
    \\
;

test "FX13: a declaration of the prelude name, added after a check, withholds a duplicate's rewrite" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_sqrt_source, w13_claimed_source));
}

test "FX13: removing the declaration of the prelude name restores a duplicate's rewrite" {
    try t.expectEqual(@as(usize, 1), try expectW13AsCold(w13_claimed_source, w13_sqrt_source));
}

const w13_param_source =
    \\public func digits(hex: str) -> int:
    \\    return len(hex)
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
;

const w13_import_added_source =
    \\import hex
    \\
    \\
    \\public func digits(hex: str) -> int:
    \\    return len(hex)
    \\
    \\
    \\public func plain(n: int) -> int:
    \\    return n + 1
    \\
    \\
    \\public func shown(data: bytes) -> str:
    \\    return hex.encode(data)
    \\
;

// W13's last step turns its warnings into refusals. A refusal is never served from a record: a check that refuses publishes no
// summaries, and a body whose check reported anything is kept out of the checked-body store. So a refusal that depends on the
// rest of its file (here a module imported after the check, which a parameter of an unchanged function now hides) is reported
// by a check with the summaries of the file as it was, exactly as without them.
test "FX13: a refusal decided by the rest of the file is reported with the summaries of the file as it was" {
    const before = w13Files(w13_param_source);
    const after = w13Files(w13_import_added_source);
    const outcome = try checkAfterEdit(&before, &after);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expect(std.mem.indexOf(u8, outcome.cold.diagnostics, "E_SHADOWING") != null);
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.json, outcome.warm.json);
    // The refusing check publishes no summaries for a later check to serve.
    try t.expect(outcome.cold.summaries == null);
    try t.expect(outcome.warm.summaries == null);
}

fn sectionRow(key: []const u8, tag: u8, mutates: []const u16, stubbable: bool) summary.Summary {
    return .{ .key = key, .context = @splat(tag), .region = .{ .len = 10, .digest = @splat(tag +% 1) }, .fact = .{ .mutates = mutates }, .stubbable = stubbable };
}

test "a summary table is cut into one section per module, and a function is found, flagged and read on its own" {
    const rows = [_]summary.Summary{
        sectionRow("fn\x1fa\x1f\x1ffirst", 1, &.{1}, true),
        sectionRow("fn\x1fa\x1f\x1fsecond", 2, &.{}, false),
        sectionRow("fn\x1fb\x1f\x1fthird", 3, &.{ 0, 2 }, true),
    };
    const payload = try summary.encode(t.allocator, .{ .summaries = &rows });
    defer t.allocator.free(payload);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const index = summary.decode(arena_state.allocator(), payload).?;
    try t.expectEqual(@as(usize, 3), index.count());
    try t.expectEqual(@as(usize, 2), index.sections.?.sectionCount());
    const third = index.find("fn\x1fb\x1f\x1fthird").?;
    try t.expectEqual(@as(u32, 2), third);
    try t.expect(index.flagsAt(third).stubbable);
    try t.expect(!index.flagsAt(index.find("fn\x1fa\x1f\x1fsecond").?).stubbable);
    try t.expectEqualSlices(u16, &.{ 0, 2 }, index.factAt(third).mutates);
    try t.expectEqualSlices(u8, &@as([32]u8, @splat(3)), &index.at(third).context);
    try t.expectEqual(@as(?u32, null), index.find("fn\x1fa\x1f\x1fmissing"));
    try t.expectEqual(@as(?u32, null), index.find("fn\x1fz\x1f\x1fthird"));
    // The signature of a section is the one the planner computes for a module group.
    var hasher = @import("semantic_sections.zig").SignatureHasher.init("b", 1);
    hasher.add(@splat(3), @splat(4));
    try t.expectEqualSlices(u8, &hasher.final(), index.sections.?.signatureOf(index.sections.?.byName("b").?));
}

test "a section marked for reuse is copied as it was stored, and a section that does not check is absent" {
    const names = [_]semantic_key.Name{.{ .text = "helper" }};
    var rows = [_]summary.Summary{ sectionRow("fn\x1fa\x1f\x1ff", 1, &.{}, true), sectionRow("fn\x1fb\x1f\x1fg", 2, &.{}, true) };
    rows[0].region.names = &names;
    const before = try summary.encode(t.allocator, .{ .summaries = &rows });
    defer t.allocator.free(before);
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const previous = summary.decode(arena_state.allocator(), before).?;
    const view = previous.sections.?;
    // Module a is stored as it was: its row here is a light row without the names, and the names come back from the stored bytes.
    var light = rows;
    light[0].region.names = &.{};
    const members_a = [_]u32{0};
    const members_b = [_]u32{1};
    var cut = [_]summary.OutSection{
        .{ .name = "a", .signature = view.signatureOf(0).*, .members = &members_a, .reuse = 0 },
        .{ .name = "b", .signature = view.signatureOf(1).*, .members = &members_b },
    };
    try t.expect(!previous.isTable(&cut));
    const after = try summary.encodeFrom(t.allocator, .{ .summaries = &light, .sections = &cut }, &previous, .{});
    defer t.allocator.free(after);
    const again = summary.decode(arena_state.allocator(), after).?;
    try t.expectEqualStrings("helper", again.at(0).region.names[0].text);
    // Every section stored as it was: the table is the previous one, byte for byte.
    cut[1].reuse = 1;
    try t.expect(previous.isTable(&cut));
    const same = try summary.encodeFrom(t.allocator, .{ .summaries = &light, .sections = &cut }, &previous, .{});
    defer t.allocator.free(same);
    try t.expectEqualSlices(u8, before, same);
    // A section whose bytes do not check is absent: its functions are found nowhere and stand in for nothing; the others are unharmed.
    const damaged = try t.allocator.dupe(u8, before);
    defer t.allocator.free(damaged);
    const cold = view.coldBytes(1);
    damaged[@intFromPtr(cold.ptr) - @intFromPtr(before.ptr) + cold.len - 1] ^= 1;
    const broken = summary.decode(arena_state.allocator(), damaged).?;
    try t.expectEqual(@as(?u32, null), broken.find("fn\x1fb\x1f\x1fg"));
    try t.expect(broken.find("fn\x1fa\x1f\x1ff") != null);
    try t.expect(!broken.at(1).stubbable);
    try t.expectEqualStrings("", broken.at(1).key);
    // A shared block that does not check leaves no record or string to read, and a table whose pool cannot be carried over is written afresh.
    const no_shared = try t.allocator.dupe(u8, before);
    defer t.allocator.free(no_shared);
    no_shared[no_shared.len - 1] ^= 1;
    const lost = summary.decode(arena_state.allocator(), no_shared).?;
    try t.expectEqual(@as(usize, 0), lost.recordCount());
    try t.expect(lost.sections.?.needsRebuild());
    try t.expect(!previous.sections.?.needsRebuild());
}

test "a warm check of an unchanged project stores the table it started from, section for section" {
    const files = reachFiles(reach_shapes);
    const seed = try checkProject(&files, null, .check);
    defer seed.deinit();
    const warm = try checkProject(&files, seed.summaries.?, .check);
    defer warm.deinit();
    try t.expect(warm.stood_in > 0);
    try t.expectEqualSlices(u8, seed.summaries.?, warm.summaries.?);
}

fn encodeOnce(allocator: std.mem.Allocator, table: summary.Table) !void {
    const payload = try @import("semantic_sections.zig").encodeTable(allocator, table, null, .{});
    allocator.free(payload);
}

test "encodeTable reports an allocation failure and frees what it allocated" {
    const rows = [_]summary.Summary{ sectionRow("fn\x1fa\x1f\x1ff", 1, &.{1}, true), sectionRow("fn\x1fb\x1f\x1fg", 2, &.{}, false) };
    var failing = std.testing.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, @import("semantic_sections.zig").encodeTable(failing.allocator(), .{ .summaries = &rows }, null, .{}));
    try std.testing.checkAllAllocationFailures(t.allocator, encodeOnce, .{summary.Table{ .summaries = &rows }});
}

test "a warm check answers for each module the table holds exactly, and stores the sections it kept as they were" {
    const original = reachFiles(reach_shapes);
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    try t.expectEqual(@as(u32, 0), seed.matched);
    const same = try checkProject(&original, seed.summaries.?, .check);
    defer same.deinit();
    try t.expectEqual([3]u32{ 3, 3, 2 }, [3]u32{ @intCast(same.groups), same.matched, same.kept });
    const edited = reachFiles(shapesEdited(&.{.{ "Inner(x=1)", "Inner(x=2)" }}));
    const outcome = try checkAfterEdit(&original, &edited);
    defer outcome.warm.deinit();
    defer outcome.cold.deinit();
    try t.expectEqual([3]u32{ 3, 2, 1 }, [3]u32{ @intCast(outcome.warm.groups), outcome.warm.matched, outcome.warm.kept });
    try t.expectEqualStrings(outcome.cold.diagnostics, outcome.warm.diagnostics);
    try t.expectEqualStrings(outcome.cold.facts, outcome.warm.facts);
}

test "a table written from kept sections is read by the next check, which stores it again unchanged" {
    const original = reachFiles(reach_shapes);
    const seed = try checkProject(&original, null, .check);
    defer seed.deinit();
    // The edit leaves `user` and `main` as they were, so their sections are kept; the next check starts from the table written with them.
    const edited = reachFiles(shapesEdited(&.{.{ "Inner(x=1)", "Inner(x=2)" }}));
    const first = try checkProject(&edited, seed.summaries.?, .check);
    defer first.deinit();
    try t.expect(first.kept > 0);
    const second = try checkProject(&edited, first.summaries.?, .check);
    defer second.deinit();
    try t.expect(second.stood_in > first.stood_in);
    try t.expectEqualSlices(u8, first.summaries.?, second.summaries.?);
    // Every function of the kept sections reads back as it was stored: facts, flags and keys.
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const was = summary.decode(arena_state.allocator(), seed.summaries.?).?;
    const is = summary.decode(arena_state.allocator(), second.summaries.?).?;
    const user = was.find("fn\x1fuser\x1f\x1ffirst").?;
    const user_now = is.find("fn\x1fuser\x1f\x1ffirst").?;
    try t.expect(summary.sameFact(was.factAt(user), is.factAt(user_now)));
    try t.expectEqual(was.flagsAt(user), is.flagsAt(user_now));
}

test "a diagnostic rebuilt from a stored note owns its text, so it outlives the payload the note was read from" {
    const message = try t.allocator.dupe(u8, "binding is never read");
    const edit_text = try t.allocator.dupe(u8, "mut value");
    const edits = [_]summary.FixEdit{.{ .start = 1, .end = 2, .text = edit_text }};
    const note: summary.Note = .{ .code = "W_UNUSED_BINDING", .severity = .warning, .start = 0, .end = 3, .message = message, .fix = &edits };
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const item = try summary.diagnosticOf(arena_state.allocator(), note, 10);
    @memset(message, 'x');
    @memset(edit_text, 'y');
    t.allocator.free(message);
    t.allocator.free(edit_text);
    try t.expectEqualStrings("binding is never read", item.message);
    try t.expectEqualStrings("W_UNUSED_BINDING", item.code);
    try t.expectEqualStrings("mut value", item.provenance.fix.?.edit.text);
    try t.expectEqual(@as(usize, 11), item.provenance.fix.?.edit.span.start);
}
