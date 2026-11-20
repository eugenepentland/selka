//! O2 keeps the O0 layer corpus as strict Core regressions, including each former disagreement.
const std = @import("std");
const print = std.debug.print;
const language = @import("selka");
const ownership = @import("single_owner.zig");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const Refusal = language.ownership_rules.Refusal;

const schema =
    \\resource Handle: filesystem
    \\func consume(own handle: Handle) -> int:
    \\    return 0
    \\
;
const entry = "func main() -> int:\n    return 0\n";
const Probe = struct {
    name: []const u8,
    text: []const u8,
    refusal: ?Refusal = null,
    instance: ?[]const u8 = null,
};

/// Supplies one in-memory entry module to the project loader, for a probe that imports a standard module.
const ProjectEntry = struct {
    source: []const u8,
    /// Serve the entry module to the project loader; other paths are not found.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const project_entry: *ProjectEntry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, project_entry.source);
    }
};

/// A checked probe: its program, its source and what the checker reported.
const Checked = struct {
    program: language.typed.Program,
    src: language.source.Source,
    diagnostics: []const language.diagnostic.Diagnostic,
};

fn expectInstance(a: std.mem.Allocator, unit: Checked, probe: Probe) !void {
    var report: std.ArrayList(u8) = .empty;
    const accepted = try ownership.audit(a, unit.program, unit.src, &report);
    try std.testing.expectEqual(probe.refusal == null, accepted);
    var lines = std.mem.splitScalar(u8, report.items, '\n');
    var found: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, a, line, .{});
        defer parsed.deinit();
        const record = parsed.value.object;
        if (!std.mem.eql(u8, record.get("version").?.string, "ownership-audit-v1")) continue;
        if (!std.mem.eql(u8, record.get("kind").?.string, "function")) continue;
        const detail = record.get("detail").?.object;
        if (!std.mem.eql(u8, detail.get("name").?.string, probe.instance.?)) continue;
        try std.testing.expect(detail.get("specialized").?.bool);
        try std.testing.expectEqual(probe.refusal == null, detail.get("accepted").?.bool);
        found += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), found);
}

/// Check a probe: one unit, or an embedded project when it imports a standard module (`lists.exchange`).
fn checkProbe(a: std.mem.Allocator, probe: Probe) !Checked {
    if (support.needsModules(probe.text)) {
        const project_entry = try a.create(ProjectEntry);
        project_entry.* = .{ .source = probe.text };
        const project = try a.create(language.embedded_project.Program);
        try project.init(a, .{ .context = project_entry, .read = ProjectEntry.read });
        const compilation = &project.compilation;
        return .{ .program = compilation.program.?, .src = compilation.src, .diagnostics = compilation.diagnostics.items.items };
    }
    const unit = try a.create(language.Compilation);
    unit.* = try language.Compilation.init(a, "ownership-layer.selka", probe.text);
    unit.check() catch |err| {
        print("O0 probe {s} stopped before Core:\n", .{probe.name});
        for (unit.diagnostics.items) |diagnostic| print("{s}: {s}\n", .{ diagnostic.code, diagnostic.message });
        return err;
    };
    return .{ .program = unit.program.?, .src = unit.src, .diagnostics = unit.diagnostics.items };
}

fn expectProbe(a: std.mem.Allocator, probe: Probe) !bool {
    const unit = try checkProbe(a, probe);
    for (unit.diagnostics) |diagnostic| {
        try std.testing.expectEqual(.warning, diagnostic.severity);
        try std.testing.expectEqualStrings("W_UNUSED_BINDING", diagnostic.code);
        try std.testing.expectEqual(@as(?language.ownership_rules.Rule, null), diagnostic.provenance.rule);
    }
    var failure: ownership.Failure = .{};
    if (probe.refusal) |expected| {
        try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program, unit.src, &failure));
        try std.testing.expectEqualStrings(expected.code, failure.code);
        try std.testing.expectEqual(expected.rule, failure.rule.?);
    } else {
        try ownership.checkWithSource(a, unit.program, unit.src, &failure);
    }
    if (probe.instance != null) try expectInstance(a, unit, probe);
    return probe.refusal == null;
}

fn resourceProbes(a: std.mem.Allocator) !usize {
    const bodies = [_]struct { name: []const u8, body: []const u8, refusal: ?Refusal }{
        .{ .name = "reuse", .body = "    _ = consume(own handle)\n    return consume(own handle)\n", .refusal = .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 } },
        .{ .name = "join_unused", .body = "    if condition:\n        _ = consume(own handle)\n    return 0\n", .refusal = null },
        .{ .name = "join_reused", .body = "    if condition:\n        _ = consume(own handle)\n    return consume(own handle)\n", .refusal = .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 } },
        .{ .name = "loop", .body = "    for index in range(2):\n        _ = consume(own handle)\n    return 0\n", .refusal = .{ .code = "E_SINGLE_OWNER_LOOP", .rule = .B6 } },
        .{ .name = "loop_break", .body = "    for index in range(2):\n        _ = consume(own handle)\n        break\n    return 0\n", .refusal = .{ .code = "E_SINGLE_OWNER_LOOP", .rule = .B6 } },
    };
    for (bodies) |body| for ([_]bool{ false, true }) |generic| {
        const declaration = if (generic) "func inspect[T](own handle: Handle, condition: bool, value: T) -> int:\n" else "func inspect(own handle: Handle, condition: bool) -> int:\n";
        const instantiate = if (generic) "func instantiate(own handle: Handle) -> int:\n    return inspect(own handle, True, 1)\n" else "";
        _ = try expectProbe(a, .{
            .name = body.name,
            .text = try std.mem.concat(a, u8, &.{ schema, declaration, body.body, instantiate, entry }),
            .refusal = body.refusal,
            .instance = if (generic) "inspect[i64]" else null,
        });
    };
    return bodies.len * 2;
}

test "ownership layer O0 resource probes reach Core with one move join and loop policy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 10), try resourceProbes(arena.allocator()));
}

const mutation_helpers =
    \\record Pair:
    \\    left: int[]
    \\    right: int[]
    \\func two(mut left: int[], mut right: int[]) -> Unit:
    \\    append(mut left, 1)
    \\    append(mut right, 2)
    \\func nested(mut rows: int[][], mut row: int[]) -> Unit:
    \\    append(mut rows, [1])
    \\    append(mut row, 2)
    \\func grow(mut rows: int[]) -> int:
    \\    append(mut rows, 3)
    \\    return 0
    \\
;

fn mutationProbes(a: std.mem.Allocator) !usize {
    const overlap: Refusal = .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .M5 };
    const receiver: Refusal = .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 };
    const probes = [_]struct { name: []const u8, body: []const u8, refusal: ?Refusal }{
        .{ .name = "same_argument", .body = "    mut rows = [[1], [2]]\n    two(mut rows[0], mut rows[0])\n", .refusal = overlap },
        .{ .name = "ancestor_argument", .body = "    mut rows = [[1], [2]]\n    nested(mut rows, mut rows[0])\n", .refusal = overlap },
        .{ .name = "dynamic_arguments", .body = "    mut rows = [[1], [2]]\n    mut index = 0\n    two(mut rows[index], mut rows[1])\n", .refusal = overlap },
        .{ .name = "disjoint_fields", .body = "    mut pair = Pair(left=[1], right=[2])\n    two(mut pair.left, mut pair.right)\n", .refusal = null },
        .{ .name = "disjoint_indices", .body = "    mut rows = [[1], [2]]\n    two(mut rows[0], mut rows[1])\n", .refusal = null },
        .{ .name = "receiver_index", .body = "    mut rows = [1]\n    rows[grow(mut rows)] = 9\n", .refusal = receiver },
        .{ .name = "receiver_rhs", .body = "    mut rows = [1]\n    rows[0] = grow(mut rows)\n", .refusal = null },
        .{ .name = "receiver_exchange", .body = "    mut rows = [1]\n    _ = lists.exchange(mut rows, grow(mut rows), 9)\n", .refusal = receiver },
        .{ .name = "receiver_disjoint_fields", .body = "    mut pair = Pair(left=[1], right=[2])\n    pair.left[0] = grow(mut pair.right)\n", .refusal = null },
    };
    for (probes) |probe| _ = try expectProbe(a, .{
        .name = probe.name,
        .text = try std.mem.concat(a, u8, &.{ if (std.mem.indexOf(u8, probe.body, "lists.") != null) "import lists\n\n" else "", mutation_helpers, "func main() -> int:\n", probe.body, "    return 0\n" }),
        .refusal = probe.refusal,
    });
    return probes.len;
}

test "ownership layer O0 mutation probes use Core place paths and RHS before receiver" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 9), try mutationProbes(arena.allocator()));
}

fn uncalledTemplate(a: std.mem.Allocator) !usize {
    const text = schema ++ "func inspect[T](own handle: Handle, value: T) -> int:\n    _ = consume(own handle)\n    return consume(own handle)\n" ++ entry;
    try std.testing.expect(try expectProbe(a, .{ .name = "reuse_generic_uncalled", .text = text }));
    var unit = try language.Compilation.init(a, "uncalled.selka", text);
    try unit.check();
    var instances: usize = 0;
    for (unit.program.?.functions) |function| if (std.mem.startsWith(u8, function.name, "inspect")) {
        instances += 1;
    };
    return instances;
}

test "ownership layer O0 uncalled template has no concrete ownership instance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(@as(usize, 0), try uncalledTemplate(arena.allocator()));
}

test "ownership layer instantiated managed generic reuse is refused in Core" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(!try expectProbe(arena.allocator(), .{
        .name = "managed_specialization_reuse",
        .text =
        \\func my_take[T](own values: T[]) -> int:
        \\    return len(values)
        \\func duplicate[T](own values: T[]) -> int:
        \\    _ = my_take(own values)
        \\    return my_take(own values)
        \\func main() -> int:
        \\    return duplicate(["owned"])
        ,
        .refusal = .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 },
        .instance = "duplicate[str]",
    }));
}

fn fr007Failure(a: std.mem.Allocator) !ownership.Failure {
    const checked = try @import("test_support.zig").checkSource(a,
        \\import network
        \\func my_exchange(own connection: network.Connection) -> int:
        \\    match network.read[16](own connection):
        \\        case ok(chunk):
        \\            _ = chunk
        \\        case err(code):
        \\            return code
        \\    _ = network.write[1](own connection, FixedArray[u8, 1]([0u8]))
        \\    return 0
        \\func main() -> int:
        \\    return 0
    );
    try std.testing.expect(checked.passed);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, checked.program.?, checked.src.?, &failure));
    return failure;
}

test "ownership layer FR007 minimized read then write refuses the second resource move" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const failure = try fr007Failure(arena.allocator());
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.B3, failure.rule.?);
}

/// Runs the guest suite in the debug mode (`release` false) or in the two release modes (`release` true); returns the modes run.
fn nativeAccepts(gpa: std.mem.Allocator, release: bool) !usize {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    _ = environment.swapRemove("SELKA_CORE_SANITIZE");
    try environment.put("ASAN_OPTIONS", "detect_leaks=1:halt_on_error=1");
    const all_modes = [_][]const []const u8{ &.{}, &.{ "--release", "--verify-facts" }, &.{ "--release", "--verify-facts" } };
    const selected: []const []const []const u8 = if (release) all_modes[1..] else all_modes[0..1];
    const first_index: usize = if (release) 1 else 0;
    for (selected, first_index..) |mode, index| {
        try support.requireReleaseArgs(mode);
        if (index == 2) try environment.put("SELKA_CORE_SANITIZE", "address");
        const argv = try std.mem.concat(a, []const u8, &.{ &.{ options.corePath(), "test", "tests/lang/ownership_layer.selka", "--force", "--json", "--jobs", "1", "--max-memory", "0", "--cache-dir", root }, mode });
        const ran = try std.process.run(a, std.testing.io, .{ .argv = argv, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) print("ownership layer native mode {d}: {s}{s}\n", .{ index, ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        const result = try std.json.parseFromSliceLeaky(std.json.Value, a, ran.stdout, .{});
        try std.testing.expectEqual(@as(i64, 5), result.object.get("passed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), result.object.get("failed").?.integer);
        try std.testing.expectEqual(@as(i64, 0), result.object.get("unsupported").?.integer);
        try std.testing.expectEqualStrings("", ran.stderr);
    }
    return selected.len;
}

test "ownership layer newly accepted joins and RHS assignment destroy owners in native modes" {
    try std.testing.expectEqual(@as(usize, 1), try nativeAccepts(std.testing.allocator, false));
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "ownership layer newly accepted joins and RHS assignment destroy owners in native modes (release)" {
    try support.requireRelease();
    try std.testing.expectEqual(@as(usize, 2), try nativeAccepts(std.testing.allocator, true));
}
