//! Existing compiler checks, applied to the shared release project's inventory.
const std = @import("std");
const host = @import("release_context.zig");
const Context = host.Context;
const reports = @import("release_report.zig");
/// Failures of native execution, declaration resolution or test report validation.
pub const Error = host.Error || @import("interfaces.zig").ContractError || error{InvalidTestReport};
/// Check canonical formatting for every eligible project source, even unreachable ones.
pub fn format(context: Context) Error!void {
    for (try host.files(context, .source)) |path| {
        const child = try context.child(&.{ "fmt", path, "--check" });
        try child.checkHost();
        if (child.status != 0) try context.report.add("E_RELEASE_STEP_FAILED", path, 1, try std.fmt.allocPrint(context.allocator(), "source is not canonically formatted; run `selka fmt {s} --write`, " ++
            "or add the path to `release.exclude` in selka.json when it is an intentional fixture or repro source\n{s}", .{ path, child.stderr }));
    }
}
/// Check every configured entry and test root, including library-only roots.
pub fn check(context: Context) Error!void {
    for (context.model.selection.roots) |root| {
        const before = context.report.findings.items.len;
        const child = try context.child(&.{ "check", root, "--diagnostics=json" });
        try child.checkHost();
        _ = try context.report.appendJson(child.stderr, false);
        if (child.status != 0 and context.report.errors(before) == 0) try context.report.add("E_RELEASE_STEP_FAILED", root, 1, try std.fmt.allocPrint(context.allocator(), "source check refused: {s}", .{child.stderr}));
    }
}
/// Keep the project's lint profile, excluding documentation findings handled by docs.
pub fn lint(context: Context) Error!void {
    for (context.model.selection.roots) |root| {
        const before = context.report.findings.items.len;
        const child = try context.child(&.{ "lint", root, "--gate", "--json" });
        try child.checkHost();
        _ = try context.report.appendJson(child.stderr, true);
        var kept = before;
        for (context.report.findings.items[before..]) |finding| {
            if (@import("release_project.zig").excluded(finding.path, context.model.options.exclude)) continue;
            context.report.findings.items[kept] = finding;
            kept += 1;
        }
        context.report.findings.shrinkRetainingCapacity(kept);
        if (child.status == 1) try context.report.add("E_RELEASE_STEP_FAILED", root, 1, try std.fmt.allocPrint(context.allocator(), "lint could not check this root: {s}", .{child.stderr}));
    }
}
/// Run each selected test root once through `selka test`, the same path an
/// ordinary run takes: one build per root, forked trials and reusable receipts
/// (FR-423). Every verdict of every root is aggregated by case name, so a case a
/// shared module contributes to two roots is still reported once.
pub fn tests(context: Context) Error![]const u8 {
    const a = context.allocator();
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var counts: Counts = .{};
    for (context.model.selection.roots) |root| {
        const child = try context.child(&.{ "test", root, "--json" });
        try child.checkHost();
        const parsed = parseReport(a, child.stdout) catch |err| {
            if (err == error.OutOfMemory or child.status == 0) return err;
            _ = try context.report.appendJson(child.stderr, false);
            try context.report.add("E_RELEASE_STEP_FAILED", root, 1, try std.fmt.allocPrint(a, "test {s} did not produce a verdict: {s}", .{ root, child.stderr }));
            continue;
        };
        try aggregate(a, context.report, root, parsed, &seen, &counts);
    }
    return std.fmt.allocPrint(a, "{d} tests, {d} examples, {d} passed, {d} cached, {d} skipped", .{ counts.tests, counts.examples, counts.passed, counts.cached, counts.skipped });
}

/// One run's verdict counts, as the step's detail line reports them.
pub const Counts = struct { tests: usize = 0, examples: usize = 0, passed: usize = 0, cached: usize = 0, skipped: usize = 0 };

/// Count one root's verdicts once each and refuse every case that did not pass.
/// A cached pass is a pass: its receipt is the evidence an ordinary run reuses.
pub fn aggregate(memory: std.mem.Allocator, report: *reports.Report, root: []const u8, parsed: std.json.Value, seen: *std.StringHashMapUnmanaged(void), counts: *Counts) Error!void {
    if (parsed != .object) return error.InvalidTestReport;
    const cases = parsed.object.get("tests") orelse return error.InvalidTestReport;
    if (cases != .array) return error.InvalidTestReport;
    for (cases.array.items) |verdict| {
        const name = reports.string(verdict, "name");
        if (name.len == 0) return error.InvalidTestReport;
        if ((try seen.getOrPut(memory, name)).found_existing) continue;
        if (std.mem.endsWith(u8, name, ".example")) counts.examples += 1 else counts.tests += 1;
        const status = reports.string(verdict, "status");
        if (std.mem.eql(u8, status, "passed")) {
            counts.passed += 1;
            continue;
        }
        if (std.mem.eql(u8, status, "cached")) {
            counts.cached += 1;
            continue;
        }
        if (std.mem.eql(u8, status, "skipped")) counts.skipped += 1;
        try report.add("E_RELEASE_STEP_FAILED", root, 1, try std.fmt.allocPrint(memory, "{s} {s}: {s}; release requires every test and example to pass", .{ name, status, reports.string(verdict, "reason") }));
    }
}
/// Require exactly the named case, preventing silent omissions or substring matches.
pub fn soleVerdict(root: std.json.Value, name: []const u8) error{InvalidTestReport}!std.json.Value {
    if (root != .object) return error.InvalidTestReport;
    const cases = root.object.get("tests") orelse return error.InvalidTestReport;
    if (cases != .array) return error.InvalidTestReport;
    if (cases.array.items.len != 1) return error.InvalidTestReport;
    const verdict = cases.array.items[0];
    if (!std.mem.eql(u8, reports.string(verdict, "name"), name)) return error.InvalidTestReport;
    return verdict;
}
/// Decode native JSON output while distinguishing allocation and malformed reports.
pub fn parseReport(a: std.mem.Allocator, bytes: []const u8) (std.mem.Allocator.Error || error{InvalidTestReport})!std.json.Value {
    const parsed = std.json.parseFromSlice(std.json.Value, a, bytes, .{ .allocate = .alloc_always }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.InvalidTestReport;
    };
    return parsed.value;
}
