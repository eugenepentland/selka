//! `selka api-diff`: classify interface changes between a recorded baseline
//! and the current checked project.
//!
//! Versioned baselines record declaration fingerprints, normalized return
//! sources and the digest of the remaining contract. Narrowing to a nonempty
//! source subset is compatible when that remaining contract is unchanged.
//! Removing every source, adding a source and other interface changes are
//! breaking. Body-only changes are compatible.
const std = @import("std");
const incremental = @import("incremental.zig");
const project_compile = @import("project_compile.zig");

const baseline_model = @import("api_diff_baseline.zig");
/// Shared baseline model and comparison implementation.
pub const Error = baseline_model.Error;
/// Shared baseline model and comparison implementation.
pub const version = baseline_model.version;
/// Shared baseline model and comparison implementation.
pub const Class = baseline_model.Class;
/// Shared baseline model and comparison implementation.
pub const Entry = baseline_model.Entry;
/// Shared baseline model and comparison implementation.
pub const Change = baseline_model.Change;
/// Shared baseline model and comparison implementation.
pub const Report = baseline_model.Report;
/// Shared baseline model and comparison implementation.
pub const freeEntries = baseline_model.freeEntries;
/// Shared baseline model and comparison implementation.
pub const parseBaseline = baseline_model.parseBaseline;
/// CLI-only preflight for a baseline recorded before declared borrow sources.
pub const needsSourceUpgrade = baseline_model.needsSourceUpgrade;
/// Shared baseline model and comparison implementation.
pub const compareEntries = baseline_model.compareEntries;
/// Shared baseline model and comparison implementation.
pub const freeChanges = baseline_model.freeChanges;
/// Shared baseline model and comparison implementation.
pub const render = baseline_model.render;

/// Snapshot every declaration's identity and fingerprints for the current
/// project, one tab-separated row per declaration.
pub fn snapshot(allocator: std.mem.Allocator, compilation: *project_compile.Compilation) Error![]u8 {
    const modules = try allocator.alloc(usize, compilation.index.units.len);
    defer allocator.free(modules);
    for (modules, 0..) |*module, i| module.* = i;
    return snapshotModules(allocator, compilation.index, modules, false);
}

/// Read the current project's entries out of a rendered snapshot.
fn currentEntries(allocator: std.mem.Allocator, compilation: *project_compile.Compilation) Error![]Entry {
    const bytes = try snapshot(allocator, compilation);
    defer allocator.free(bytes);
    return parseBaseline(allocator, bytes);
}

/// Compare a baseline against the current project and classify every change.
/// Changed display names are allocations the caller owns until `freeChanges`.
pub fn compare(allocator: std.mem.Allocator, baseline: []const Entry, compilation: *project_compile.Compilation) Error!Report {
    const current = try currentEntries(allocator, compilation);
    defer freeEntries(allocator, current);
    return compareEntries(allocator, baseline, current);
}

/// Snapshot public declarations in the selected module set without checking bodies.
/// Rows retain the ordinary api-diff baseline format and deterministic name order.
pub fn snapshotPublic(allocator: std.mem.Allocator, index: *@import("interfaces.zig").Index, modules: []const usize) Error![]u8 {
    return snapshotModules(allocator, index, modules, true);
}

fn snapshotModules(allocator: std.mem.Allocator, index: *@import("interfaces.zig").Index, modules: []const usize, public_only: bool) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var rows: std.ArrayList(Entry) = .empty;
    for (modules) |module_id| {
        const module = index.project.modules.items[module_id];
        const unit = index.units[module_id];
        for (unit.symbols.items) |symbol| {
            if (public_only and !symbol.exported) continue;
            const item = incremental.declarationSnapshot(scratch, index, module_id, symbol) catch return error.InternalError;
            const contract = incremental.declarationBorrowContract(scratch, index, module_id, symbol) catch return error.InternalError;
            try rows.append(scratch, .{
                .identity = item.identity,
                .display = try std.fmt.allocPrint(scratch, "{s}::{s}", .{ module.name, symbol.name }),
                .kind = item.kind,
                .interface = item.interface_sha256 orelse "-",
                .body = item.body_sha256 orelse "-",
                .without_sources = contract.without_sources,
                .sources = try sourcePositions(scratch, contract.sources),
            });
        }
    }
    return baseline_model.serialize(allocator, rows.items);
}

fn sourcePositions(allocator: std.mem.Allocator, positions: []const u16) Error![]const u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    if (positions.len == 0) return "fresh";
    for (positions, 0..) |position, i| {
        if (i != 0) out.writer.writeByte(',') catch return error.OutOfMemory;
        out.writer.print("{d}", .{position}) catch return error.OutOfMemory;
    }
    return out.toOwnedSlice();
}

// spec: API-DIFF-1
test "api-diff classifies added compatible and breaking declarations" {
    const allocator = std.testing.allocator;
    const baseline_bytes = "# api-diff-baseline-v1\n" ++
        "a::gone\tapp::gone\tfunction\tiface-a\tbody-a\n" ++
        "a::same\tapp::same\tfunction\tiface-b\tbody-b\n" ++
        "a::moved\tapp::moved\tfunction\tiface-c\tbody-c\n";
    const baseline = try parseBaseline(allocator, baseline_bytes);
    defer freeEntries(allocator, baseline);
    try std.testing.expectEqual(@as(usize, 3), baseline.len);
    const current = [_]Entry{
        .{ .identity = "a::same", .display = "app::same", .kind = "function", .interface = "iface-b", .body = "body-b" },
        .{ .identity = "a::moved", .display = "app::moved", .kind = "function", .interface = "iface-c", .body = "body-c2" },
        .{ .identity = "a::new", .display = "app::new", .kind = "function", .interface = "iface-d", .body = "body-d" },
    };
    const report = try compareEntries(allocator, baseline, &current);
    defer freeChanges(allocator, report);
    try std.testing.expectEqual(@as(usize, 1), report.additive.len);
    try std.testing.expectEqual(@as(usize, 1), report.compatible.len);
    try std.testing.expectEqual(@as(usize, 1), report.breaking.len);
    try std.testing.expectEqual(@as(usize, 1), report.unchanged);
    try std.testing.expectEqualStrings("app::gone", report.breaking[0].display);
    try std.testing.expectEqualStrings("app::new", report.additive[0].display);
    const text = try render(allocator, report, false);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "api-diff: additive=1 compatible=1 breaking=1 unchanged=1") != null);
    const json = try render(allocator, report, true);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\":\"api-diff-v1\"") != null);
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(allocator, "not a baseline\n"));
}

test "O3 api-diff nonempty source narrowing needs an unchanged remaining contract" {
    const allocator = std.testing.allocator;
    const old: Entry = .{ .identity = "pick", .display = "app::pick", .kind = "function", .interface = "old", .body = "body", .without_sources = "same", .sources = "0,69" };
    var current = old;
    current.interface = "narrow";
    current.sources = "69";
    const narrow = try compareEntries(allocator, &.{old}, &.{current});
    defer freeChanges(allocator, narrow);
    try std.testing.expectEqual(@as(usize, 1), narrow.compatible.len);
    current.without_sources = "different-type";
    const changed = try compareEntries(allocator, &.{old}, &.{current});
    defer freeChanges(allocator, changed);
    try std.testing.expectEqual(@as(usize, 1), changed.breaking.len);
    current = old;
    current.interface = "broader";
    current.sources = "0,1,69";
    const broader = try compareEntries(allocator, &.{old}, &.{current});
    defer freeChanges(allocator, broader);
    try std.testing.expectEqual(@as(usize, 1), broader.breaking.len);
    const legacy: Entry = .{ .identity = "pick", .display = "app::pick", .kind = "function", .interface = "legacy", .body = "body" };
    const conservative = try compareEntries(allocator, &.{legacy}, &.{current});
    defer freeChanges(allocator, conservative);
    try std.testing.expectEqual(@as(usize, 1), conservative.breaking.len);
}

test "O3 api-diff v2 roundtrip preserves source positions above 63 and rejects malformed rows" {
    const allocator = std.testing.allocator;
    const entry: Entry = .{ .identity = "pick", .display = "app::pick", .kind = "function", .interface = "all", .body = "body", .without_sources = "other", .sources = "0,69" };
    const bytes = try baseline_model.serialize(allocator, &.{entry});
    defer allocator.free(bytes);
    const parsed = try parseBaseline(allocator, bytes);
    defer freeEntries(allocator, parsed);
    try std.testing.expectEqualStrings("0,69", parsed[0].sources);
    try std.testing.expectEqualStrings("other", parsed[0].without_sources);
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(allocator, "# api-diff-baseline-v2\npick\tapp::pick\tfunction\tall\tbody\tother\n"));
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(allocator, "# api-diff-baseline-v2\npick\tapp::pick\tfunction\tall\tbody\tother\t69,0\n"));
}

fn baselineParseAllocations(allocator: std.mem.Allocator) !void {
    const entries = try parseBaseline(allocator, "# api-diff-baseline-v2\n" ++
        "pick\tapp::pick\tfunction\tall\tbody\tother\t0,69\n" ++
        "main\tapp::main\tfunction\tmain\tbody\tmain\tfresh\n");
    defer freeEntries(allocator, entries);
    try std.testing.expectEqual(@as(usize, 2), entries.len);
}

test "O3 api-diff parseRow frees partially allocated v2 rows on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, baselineParseAllocations, .{});
}

test "F4 api-diff distinguishes final removal subset addition and normalized reorder" {
    const allocator = std.testing.allocator;
    const old: Entry = .{ .identity = "pick", .display = "app::pick", .kind = "function", .interface = "old", .body = "body", .without_sources = "same", .sources = "0,69" };
    const cases = [_]struct { sources: []const u8, interface: []const u8, compatible: usize, breaking: usize, unchanged: usize }{
        .{ .sources = "fresh", .interface = "fresh", .compatible = 0, .breaking = 1, .unchanged = 0 },
        .{ .sources = "69", .interface = "subset", .compatible = 1, .breaking = 0, .unchanged = 0 },
        .{ .sources = "0,1,69", .interface = "added", .compatible = 0, .breaking = 1, .unchanged = 0 },
        // Snapshotting sorts the source positions, so reordering retains both fingerprints.
        .{ .sources = "0,69", .interface = "old", .compatible = 0, .breaking = 0, .unchanged = 1 },
    };
    for (cases) |case| {
        var current = old;
        current.sources = case.sources;
        current.interface = case.interface;
        const report = try compareEntries(allocator, &.{old}, &.{current});
        defer freeChanges(allocator, report);
        try std.testing.expectEqual(@as(usize, 0), report.additive.len);
        try std.testing.expectEqual(case.compatible, report.compatible.len);
        try std.testing.expectEqual(case.breaking, report.breaking.len);
        try std.testing.expectEqual(case.unchanged, report.unchanged);
    }
}

test "F4 api-diff upgrade preflight preserves shared v1 and comment baseline readers" {
    const allocator = std.testing.allocator;
    const bytes = "# api-diff-baseline-v1\npick\tapp::pick\tfunction\tinterface\tbody\n";
    const parsed = try parseBaseline(allocator, bytes);
    defer freeEntries(allocator, parsed);
    const released = try baseline_model.parseReleaseBaseline(allocator, bytes);
    defer freeEntries(allocator, released);
    const comments = try parseBaseline(allocator, "# legacy-comment\n");
    defer freeEntries(allocator, comments);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqual(@as(usize, 1), released.len);
    try std.testing.expectEqualStrings("-", parsed[0].without_sources);
    try std.testing.expectEqualStrings("-", released[0].sources);
    try std.testing.expectEqual(@as(usize, 0), comments.len);
}
