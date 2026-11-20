//! The ownership matrix in the gate (stage O5 of `docs/audits/test-loop-plan-2026-11-09.md`, 10 November 2026). The matrix
//! (`experiments/ownership-matrix-20261109/matrix.py`) writes one small program per value source, position, verb and type.
//! `test/fixtures/ownership-matrix/` holds all 1,775 of them, grouped by type and verdict, and `verdicts.tsv` pins what
//! `selka check` says of each when it is checked alone (cell id, verdict, code, rule); `gate_fixtures.py` beside `matrix.py`
//! writes both from a compiler. For each type this test checks the refused and the accepted program and compares every
//! cell's first error with the table, so a change to what is accepted shows in the table's diff. Then it builds the accepted
//! program as `selka build` does by default and as the language suites are built (`--debug-o0 --verify-facts`), and runs
//! both binaries under the leak check: every cell the check accepts must build and run (exit X4). When a build fails, the
//! cells are bisected and the failing ones are named. A cell listed in `known-build-failures.tsv` is left out of its mode's
//! build and must fail there alone with its listed code; why each is listed is in the matrix's `DECISIONS.md`.
const std = @import("std");
const testing = std.testing;

const fixtures = "test/fixtures/ownership-matrix";

/// One cell's verdict: `ok`, or the code and rule of its first error.
const Verdict = struct { id: []const u8, verdict: []const u8 };

/// One cell of a grouped program: its id and its text (the cell's `probe_` and `call_` functions).
const Chunk = struct { id: []const u8, text: []const u8 };

/// A grouped program cut into the header every cell shares and its cells.
const Program = struct { header: []const u8, chunks: []const Chunk };

/// A build of the accepted cells: the compiler's flags, and the cache and executable under a private directory.
const Mode = struct { name: []const u8, flags: []const []const u8 };

const modes = [_]Mode{
    .{ .name = "default build", .flags = &.{} },
    .{ .name = "--debug-o0 --verify-facts", .flags = &.{ "--debug-o0", "--verify-facts" } },
};

fn compilerPath() []const u8 {
    return @import("test_paths").corePath();
}

fn run(a: std.mem.Allocator, argv: []const []const u8, leak_check: bool) !std.process.RunResult {
    var environment = try @import("test_paths").privateEnvironment(a);
    if (leak_check) try environment.put("SELKA_CORE_LEAKCHECK", "1");
    return std.process.run(a, testing.io, .{ .argv = argv, .environ_map = &environment });
}

/// The cell of each line of `text` (null outside every cell): a line belongs to the `probe_` or `call_` function above it.
fn owners(a: std.mem.Allocator, text: []const u8) ![]?[]const u8 {
    var found: std.ArrayList(?[]const u8) = .empty;
    var current: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (cellOf(line)) |id| {
            current = id;
        } else if (std.mem.startsWith(u8, line, "func ") or std.mem.startsWith(u8, line, "record ")) {
            current = null;
        }
        try found.append(a, current);
    }
    return found.items;
}

/// The cell a `func probe_ID(` or `func call_ID(` line opens.
fn cellOf(line: []const u8) ?[]const u8 {
    for ([_][]const u8{ "func probe_", "func call_" }) |prefix| {
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const rest = line[prefix.len..];
        return rest[0 .. std.mem.indexOfScalar(u8, rest, '(') orelse return null];
    }
    return null;
}

/// Check `path` and record each cell's verdict in `verdicts`: its first error's code and rule, or `ok`. An error outside
/// every cell is recorded under the line it is on.
fn checkCells(a: std.mem.Allocator, path: []const u8, verdicts: *std.StringArrayHashMapUnmanaged([]const u8)) !void {
    const text = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, a, .unlimited);
    const lines = try owners(a, text);
    for (lines) |owner| {
        const id = owner orelse continue;
        if (!verdicts.contains(id)) try verdicts.put(a, id, "ok");
    }
    const result = try run(a, &.{ compilerPath(), "check", path, "--diagnostics=json" }, false);
    var errors: std.StringHashMapUnmanaged(void) = .empty;
    var output = std.mem.splitScalar(u8, try std.mem.concat(a, u8, &.{ result.stdout, result.stderr }), '\n');
    while (output.next()) |line| {
        if (!std.mem.startsWith(u8, line, "{")) continue;
        const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
        const diagnostic = (parsed.object.get("diagnostic") orelse continue).object;
        if (!std.mem.eql(u8, diagnostic.get("severity").?.string, "error")) continue;
        const location = diagnostic.get("location");
        const number: usize = if (location) |at| @intCast(at.object.get("start").?.object.get("line").?.integer) else 0;
        const rule = if (diagnostic.get("rule")) |value| value.string else "-";
        const said = try std.fmt.allocPrint(a, "{s} {s}", .{ diagnostic.get("code").?.string, rule });
        const id = if (number >= 1 and number <= lines.len) lines[number - 1] else null;
        const key = id orelse try std.fmt.allocPrint(a, "{s}:{d} (outside every cell)", .{ path, number });
        if (errors.contains(key)) continue;
        try errors.put(a, key, {});
        try verdicts.put(a, key, said);
    }
}

/// The table's rows for `type_name`, rendered one per line as `id verdict`.
fn pinned(a: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    const table = try std.Io.Dir.cwd().readFileAlloc(testing.io, fixtures ++ "/verdicts.tsv", a, .unlimited);
    var out: std.ArrayList(u8) = .empty;
    var rows = std.mem.splitScalar(u8, table, '\n');
    while (rows.next()) |row| {
        if (row.len == 0 or row[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, row, '\t');
        const id = fields.next().?;
        if (!std.mem.startsWith(u8, id, type_name) or !std.mem.startsWith(u8, id[type_name.len..], "__")) continue;
        const verdict = fields.next().?;
        const code = fields.next().?;
        const rule = fields.next().?;
        if (std.mem.eql(u8, verdict, "ok")) {
            try out.print(a, "{s} ok\n", .{id});
        } else {
            try out.print(a, "{s} {s} {s}\n", .{ id, code, rule });
        }
    }
    return out.items;
}

/// What the compiler says of each cell of `type_name`, in the table's order, then anything the table does not name.
fn answered(a: std.mem.Allocator, type_name: []const u8, table: []const u8) ![]const u8 {
    var verdicts: std.StringArrayHashMapUnmanaged([]const u8) = .empty;
    for ([_][]const u8{ "refused", "accepted" }) |kind| {
        try checkCells(a, try std.fmt.allocPrint(a, fixtures ++ "/{s}_{s}.selka", .{ kind, type_name }), &verdicts);
    }
    var out: std.ArrayList(u8) = .empty;
    var named: std.StringHashMapUnmanaged(void) = .empty;
    var rows = std.mem.splitScalar(u8, table, '\n');
    while (rows.next()) |row| {
        if (row.len == 0) continue;
        const id = row[0..std.mem.indexOfScalar(u8, row, ' ').?];
        try named.put(a, id, {});
        try out.print(a, "{s} {s}\n", .{ id, verdicts.get(id) orelse "missing from the fixtures" });
    }
    for (verdicts.keys(), verdicts.values()) |id, verdict| {
        if (!named.contains(id)) try out.print(a, "{s} {s} (not in the table)\n", .{ id, verdict });
    }
    return out.items;
}

/// Cut a grouped program into its header and cells; the accepted programs end with a `main` that is left out.
fn split(a: std.mem.Allocator, text: []const u8) !Program {
    var chunks: std.ArrayList(Chunk) = .empty;
    var header: ?[]const u8 = null;
    var start: usize = 0;
    var id: ?[]const u8 = null;
    var offset: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| : (offset += line.len + 1) {
        const opens = std.mem.startsWith(u8, line, "func probe_");
        if (!opens and !std.mem.startsWith(u8, line, "func main(")) continue;
        if (id) |previous| try chunks.append(a, .{ .id = previous, .text = text[start..offset] });
        if (header == null) header = text[0..offset];
        start = offset;
        id = if (opens) cellOf(line) else null;
    }
    if (id) |previous| try chunks.append(a, .{ .id = previous, .text = text[start..] });
    return .{ .header = header orelse text, .chunks = chunks.items };
}

/// A program of `chunks` with a `main` that calls each and returns 0.
fn assemble(a: std.mem.Allocator, header: []const u8, chunks: []const Chunk) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(a, header);
    for (chunks) |chunk| try out.appendSlice(a, chunk.text);
    try out.appendSlice(a, "\nfunc main() -> int:\n    mut total = 0\n");
    for (chunks) |chunk| try out.print(a, "    total = total + call_{s}()\n", .{chunk.id});
    try out.appendSlice(a, "    if total < 0:\n        return 3\n    return 0\n");
    return out.items;
}

/// Build `text` in `mode` under `directory` and run it under the leak check: null when both succeed, else the reason.
fn buildAndRun(a: std.mem.Allocator, directory: []const u8, text: []const u8, mode: Mode) !?[]const u8 {
    const source = try std.fs.path.join(a, &.{ directory, "cells.selka" });
    const binary = try std.fs.path.join(a, &.{ directory, "cells" });
    try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = source, .data = text });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ compilerPath(), "build", source, "-o", binary, "--cache-dir", try std.fs.path.join(a, &.{ directory, "cache" }) });
    try argv.appendSlice(a, mode.flags);
    try argv.append(a, "--zig=" ++ @import("test_options").zig_path);
    const built = try run(a, argv.items, false);
    if (built.term != .exited or built.term.exited != 0) return try firstError(a, "build", built.stderr);
    const ran = try run(a, &.{binary}, true);
    if (ran.term == .exited and ran.term.exited == 0) return null;
    return try std.fmt.allocPrint(a, "run: {any}: {s}", .{ ran.term, try firstError(a, "stderr", ran.stderr) });
}

/// The first line of `stderr` that names an error, else its last line.
fn firstError(a: std.mem.Allocator, what: []const u8, stderr: []const u8) ![]const u8 {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    var last: []const u8 = "";
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "error") != null) return std.fmt.allocPrint(a, "{s}: {s}", .{ what, line });
        if (line.len != 0) last = line;
    }
    return std.fmt.allocPrint(a, "{s}: {s}", .{ what, last });
}

/// At most this many failing cells are named, so that a change that breaks most cells still ends within the test deadline.
const named_limit = 8;

/// The cells among `chunks` that fail in `mode`, found by halving: a group that fails and has one cell names it, and a
/// group that fails while both halves pass is named as a group.
fn bisect(a: std.mem.Allocator, directory: []const u8, program: Program, chunks: []const Chunk, mode: Mode, out: *std.ArrayList(u8)) !void {
    if (std.mem.count(u8, out.items, "\n") >= named_limit) return;
    const reason = try buildAndRun(a, directory, try assemble(a, program.header, chunks), mode) orelse return;
    if (chunks.len == 1) return out.print(a, "{s} ({s}): {s}\n", .{ chunks[0].id, mode.name, reason });
    const before = out.items.len;
    try bisect(a, directory, program, chunks[0 .. chunks.len / 2], mode, out);
    try bisect(a, directory, program, chunks[chunks.len / 2 ..], mode, out);
    if (out.items.len == before) try out.print(a, "{d} cells from {s} together ({s}): {s}\n", .{ chunks.len, chunks[0].id, mode.name, reason });
}

/// The cells the check accepts that a build mode is known to refuse (`known-build-failures.tsv`: cell, mode, code). The
/// accepted program is built in that mode without them, and each must still fail there with its code, so that a fix
/// shows as a line to delete.
fn knownFailures(a: std.mem.Allocator) ![]const [3][]const u8 {
    const table = try std.Io.Dir.cwd().readFileAlloc(testing.io, fixtures ++ "/known-build-failures.tsv", a, .unlimited);
    var found: std.ArrayList([3][]const u8) = .empty;
    var rows = std.mem.splitScalar(u8, table, '\n');
    while (rows.next()) |row| {
        if (row.len == 0 or row[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, row, '\t');
        try found.append(a, .{ fields.next().?, fields.next().?, fields.next().? });
    }
    return found.items;
}

/// Whether `known` lists `id` as failing in `mode`.
fn knownIn(known: []const [3][]const u8, id: []const u8, mode: Mode) bool {
    for (known) |row| {
        if (std.mem.eql(u8, row[0], id) and std.mem.eql(u8, row[1], mode.name)) return true;
    }
    return false;
}

/// Build and run the accepted program of `type_name` in every mode; the cells that fail, one per line.
fn failingBuilds(a: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();
    const directory = try temporary.dir.realPathFileAlloc(testing.io, ".", a);
    const path = try std.fmt.allocPrint(a, fixtures ++ "/accepted_{s}.selka", .{type_name});
    const text = try std.Io.Dir.cwd().readFileAlloc(testing.io, path, a, .unlimited);
    const program = try split(a, text);
    const known = try knownFailures(a);
    var out: std.ArrayList(u8) = .empty;
    for (modes) |mode| {
        var kept: std.ArrayList(Chunk) = .empty;
        for (program.chunks) |chunk| {
            if (!knownIn(known, chunk.id, mode)) try kept.append(a, chunk);
        }
        // The fixture as committed (less the known failures) first; its cells are bisected only when it fails.
        const whole = if (kept.items.len == program.chunks.len) text else try assemble(a, program.header, kept.items);
        if (try buildAndRun(a, directory, whole, mode) != null) {
            const before = out.items.len;
            try bisect(a, directory, program, kept.items, mode, &out);
            if (out.items.len == before) try out.print(a, "{s} ({s}) fails, and its cells rebuilt with a new main do not\n", .{ path, mode.name });
        }
        for (program.chunks) |chunk| {
            if (!knownIn(known, chunk.id, mode)) continue;
            const reason = try buildAndRun(a, directory, try assemble(a, program.header, &.{chunk}), mode);
            const code = for (known) |row| {
                if (std.mem.eql(u8, row[0], chunk.id) and std.mem.eql(u8, row[1], mode.name)) break row[2];
            } else unreachable;
            if (reason == null) {
                try out.print(a, "{s} ({s}) builds now: delete its line from known-build-failures.tsv\n", .{ chunk.id, mode.name });
            } else if (std.mem.indexOf(u8, reason.?, code) == null) {
                try out.print(a, "{s} ({s}) is known to fail with {s}, and fails with: {s}\n", .{ chunk.id, mode.name, code, reason.? });
            }
        }
    }
    return out.items;
}

/// The matrix's cells of `type_name`: each keeps its pinned verdict, and every accepted one builds and runs.
fn expectCells(type_name: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const table = try pinned(a, type_name);
    try testing.expect(table.len != 0);
    try testing.expectEqualStrings(table, try answered(a, type_name, table));
    try testing.expectEqualStrings("", try failingBuilds(a, type_name));
}

test "ownership matrix: every str cell keeps its pinned verdict, and every str cell the check accepts builds and runs" {
    try expectCells("text");
}

test "ownership matrix: every record cell keeps its pinned verdict, and every record cell the check accepts builds and runs" {
    try expectCells("item");
}

test "ownership matrix: every bytes cell keeps its pinned verdict, and every bytes cell the check accepts builds and runs" {
    try expectCells("bytes");
}

test "ownership matrix: every int[] cell keeps its pinned verdict, and every int[] cell the check accepts builds and runs" {
    try expectCells("ints");
}
