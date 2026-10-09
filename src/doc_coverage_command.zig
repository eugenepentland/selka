//! `selka doc-coverage <repo-root>`: fail the build when an implemented feature
//! or a standard-library export has no documented, executable example.
const std = @import("std");
const coverage = @import("doc_coverage.zig");

/// Usage text for the `doc-coverage` subcommand.
pub const usage =
    "usage: selka doc-coverage [<repo-root>]\n" ++
    "  Resolves every src/features.json 'doc' pointer against the checkout, requires an\n" ++
    "  executed example in each language section and a command block in each tooling\n" ++
    "  section, and requires every src/stdlib export to be named and exercised in\n" ++
    "  docs/standard-library.md. Exits 1 when anything is undocumented.\n";

/// Allocation and host-output failures the check cannot turn into a report line.
pub const Error = error{ OutOfMemory, WriteFailed };

const file_limit: std.Io.Limit = .limited(8 * 1024 * 1024);
const guide_path = "docs/standard-library.md";
const excluded_prefix = "docs/legacy/";

const Counts = struct { language: usize = 0, tooling: usize = 0, modules: usize = 0, exports: usize = 0 };

const Report = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    documents: std.StringHashMapUnmanaged(?[]const u8),
    pages: std.StringHashMapUnmanaged(usize),
    failures: std.ArrayList([]const u8),
    counts: Counts,
};

/// Check the documentation coverage of the checkout named by `args`, or the working directory.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        write(process.io, std.Io.File.stdout(), usage) catch return error.WriteFailed;
        return 0;
    }
    if (args.len > 1) {
        write(process.io, std.Io.File.stderr(), usage) catch return error.WriteFailed;
        return 2;
    }
    const allocator = process.arena.allocator();
    var report: Report = .{
        .gpa = allocator,
        .io = process.io,
        .root = if (args.len == 1) args[0] else ".",
        .documents = .empty,
        .pages = .empty,
        .failures = .empty,
        .counts = .{},
    };
    try checkFeatures(&report);
    try checkModules(&report);
    return emit(&report);
}

fn write(io: std.Io, target: std.Io.File, bytes: []const u8) !void {
    try target.writeStreamingAll(io, bytes);
}

fn checkFeatures(report: *Report) Error!void {
    const text = (try document(report, "src/features.json")) orelse return fail(report, "cannot read src/features.json under '{s}'", .{report.root});
    const manifest = std.json.parseFromSlice(std.json.Value, report.gpa, text, .{}) catch
        return fail(report, "src/features.json is not valid JSON", .{});
    defer manifest.deinit();
    if (manifest.value != .object) return fail(report, "src/features.json is not a JSON object", .{});
    const implemented = manifest.value.object.get("implemented") orelse
        return fail(report, "src/features.json has no 'implemented' section", .{});
    if (implemented != .object) return fail(report, "'implemented' is not an object keyed by feature slug", .{});
    var entries = implemented.object.iterator();
    while (entries.next()) |entry| try checkFeature(report, entry.key_ptr.*, entry.value_ptr.*);
}

fn checkFeature(report: *Report, slug: []const u8, value: std.json.Value) Error!void {
    if (value != .object) return fail(report, "{s}: feature entry is not an object", .{slug});
    const kind = string(value, "kind") orelse return fail(report, "{s}: no 'kind'", .{slug});
    const summary = string(value, "summary") orelse return fail(report, "{s}: no 'summary'", .{slug});
    const pointer = string(value, "doc") orelse return fail(report, "{s}: no 'doc' pointer", .{slug});
    const language = std.mem.eql(u8, kind, "language");
    if (!language and !std.mem.eql(u8, kind, "tooling"))
        return fail(report, "{s}: kind '{s}' is neither 'language' nor 'tooling'", .{ slug, kind });
    if (summary.len == 0) return fail(report, "{s}: 'summary' is empty", .{slug});
    const found = (try locate(report, slug, pointer)) orelse return;
    const page = pointer[0..std.mem.indexOfScalar(u8, pointer, '#').?];
    const counted = try report.pages.getOrPut(report.gpa, page);
    counted.value_ptr.* = if (counted.found_existing) counted.value_ptr.* + 1 else 1;
    if (language) {
        report.counts.language += 1;
        if (!coverage.hasRunnableExample(found.body))
            try fail(report, "{s}: section '{s}' has no executed ```selka example", .{ slug, pointer });
        return;
    }
    report.counts.tooling += 1;
    if (!coverage.hasCommandExample(found.body))
        try fail(report, "{s}: section '{s}' has no command or program block", .{ slug, pointer });
}

fn locate(report: *Report, slug: []const u8, pointer: []const u8) Error!?coverage.Section {
    const at = std.mem.indexOfScalar(u8, pointer, '#') orelse {
        try fail(report, "{s}: doc pointer '{s}' names no heading anchor", .{ slug, pointer });
        return null;
    };
    const page = pointer[0..at];
    if (page.len == 0 or std.mem.indexOf(u8, page, "..") != null) {
        try fail(report, "{s}: doc pointer '{s}' is not a repository-relative page", .{ slug, pointer });
        return null;
    }
    // The example runner skips docs/legacy/, so an example there would never actually run.
    if (std.mem.startsWith(u8, page, excluded_prefix)) {
        try fail(report, "{s}: doc pointer '{s}' names a page under {s}, whose examples are never executed", .{ slug, pointer, excluded_prefix });
        return null;
    }
    const text = (try document(report, page)) orelse {
        try fail(report, "{s}: doc page '{s}' does not exist", .{ slug, page });
        return null;
    };
    return coverage.section(text, pointer[at + 1 ..]) orelse {
        try fail(report, "{s}: '{s}' has no heading with anchor '{s}'", .{ slug, page, pointer[at + 1 ..] });
        return null;
    };
}

fn checkModules(report: *Report) Error!void {
    const guide = (try document(report, guide_path)) orelse return fail(report, "cannot read {s}", .{guide_path});
    const path = try std.fs.path.join(report.gpa, &.{ report.root, "src/stdlib" });
    var directory = std.Io.Dir.cwd().openDir(report.io, path, .{ .iterate = true, .follow_symlinks = false }) catch
        return fail(report, "cannot list {s}", .{path});
    defer directory.close(report.io);
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterate();
    while (iterator.next(report.io) catch return fail(report, "cannot list {s}", .{path})) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".selka")) continue;
        try names.append(report.gpa, try report.gpa.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, before);
    for (names.items) |name| try checkModule(report, guide, name);
}

fn checkModule(report: *Report, guide: []const u8, file: []const u8) Error!void {
    const name = file[0 .. file.len - ".selka".len];
    const relative = try std.fmt.allocPrint(report.gpa, "src/stdlib/{s}", .{file});
    const source = (try document(report, relative)) orelse return fail(report, "cannot read {s}", .{relative});
    report.counts.modules += 1;
    const found = coverage.section(guide, name) orelse
        return fail(report, "{s} has no '## {s}' section", .{ guide_path, name });
    if (!coverage.hasRunnableExample(found.body))
        try fail(report, "{s}: '## {s}' has no executed ```selka example", .{ guide_path, name });
    var names = coverage.exports(source);
    while (names.next()) |exported| {
        report.counts.exports += 1;
        if (!coverage.mentions(found.body, exported))
            try fail(report, "{s}: '## {s}' never names the export '{s}'", .{ guide_path, name, exported });
        if (!coverage.documentsExport(source, exported))
            try fail(report, "{s}: export '{s}' has no '#' comment directly above its definition", .{ relative, exported });
    }
}

fn document(report: *Report, relative: []const u8) Error!?[]const u8 {
    const cached = try report.documents.getOrPut(report.gpa, relative);
    if (cached.found_existing) return cached.value_ptr.*;
    const path = try std.fs.path.join(report.gpa, &.{ report.root, relative });
    cached.value_ptr.* = std.Io.Dir.cwd().readFileAlloc(report.io, path, report.gpa, file_limit) catch null;
    return cached.value_ptr.*;
}

fn string(value: std.json.Value, name: []const u8) ?[]const u8 {
    const field = value.object.get(name) orelse return null;
    return if (field == .string) field.string else null;
}

fn before(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn fail(report: *Report, comptime format: []const u8, args: anytype) Error!void {
    try report.failures.append(report.gpa, try std.fmt.allocPrint(report.gpa, format, args));
}

fn emit(report: *Report) Error!u8 {
    var out: std.ArrayList(u8) = .empty;
    const counts = report.counts;
    try line(report, &out, "doc-coverage: {d} documented features ({d} language, {d} tooling) across {d} pages\n", .{ counts.language + counts.tooling, counts.language, counts.tooling, report.pages.count() });
    var pages: std.ArrayList([]const u8) = .empty;
    var keys = report.pages.keyIterator();
    while (keys.next()) |page| try pages.append(report.gpa, page.*);
    std.mem.sort([]const u8, pages.items, {}, before);
    for (pages.items) |page| try line(report, &out, "  {s}: {d}\n", .{ page, report.pages.get(page).? });
    try line(report, &out, "doc-coverage: {d} standard modules, {d} exports named in {s}\n", .{ counts.modules, counts.exports, guide_path });
    for (report.failures.items) |failure| try line(report, &out, "  ! {s}\n", .{failure});
    try line(report, &out, "doc-coverage: {d} failures\n", .{report.failures.items.len});
    write(report.io, std.Io.File.stdout(), out.items) catch return error.WriteFailed;
    return if (report.failures.items.len == 0) 0 else 1;
}

fn line(report: *Report, out: *std.ArrayList(u8), comptime format: []const u8, args: anytype) Error!void {
    try out.appendSlice(report.gpa, try std.fmt.allocPrint(report.gpa, format, args));
}

const testing = std.testing;

// spec: DOCCOV-3
test "a doc pointer without an anchor or with a parent escape is a failure, not a crash" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var report: Report = .{ .gpa = arena.allocator(), .io = testing.io, .root = ".", .documents = .empty, .pages = .empty, .failures = .empty, .counts = .{} };
    try testing.expect((try locate(&report, "slug", "docs/page.md")) == null);
    try testing.expect((try locate(&report, "slug", "../secrets.md#x")) == null);
    try testing.expect((try locate(&report, "slug", "docs/legacy/old.md#x")) == null);
    try testing.expect((try locate(&report, "slug", "docs/absent-page-name.md#x")) == null);
    try testing.expectEqual(@as(usize, 4), report.failures.items.len);
    try testing.expect(std.mem.indexOf(u8, report.failures.items[0], "names no heading anchor") != null);
    try testing.expect(std.mem.indexOf(u8, report.failures.items[1], "repository-relative") != null);
    try testing.expect(std.mem.indexOf(u8, report.failures.items[2], "never executed") != null);
    try testing.expect(std.mem.indexOf(u8, report.failures.items[3], "does not exist") != null);
}

// spec-case: DOCCOV-3
test "a feature entry missing its kind, summary or pointer is reported by slug" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var report: Report = .{ .gpa = arena.allocator(), .io = testing.io, .root = ".", .documents = .empty, .pages = .empty, .failures = .empty, .counts = .{} };
    const manifest = try std.json.parseFromSlice(std.json.Value, arena.allocator(), "{\"a\":{},\"b\":{\"kind\":\"other\",\"summary\":\"s\",\"doc\":\"d#e\"},\"c\":[]}", .{});
    defer manifest.deinit();
    var entries = manifest.value.object.iterator();
    while (entries.next()) |entry| try checkFeature(&report, entry.key_ptr.*, entry.value_ptr.*);
    try testing.expectEqual(@as(usize, 3), report.failures.items.len);
    try testing.expectEqualStrings("a: no 'kind'", report.failures.items[0]);
    try testing.expectEqualStrings("b: kind 'other' is neither 'language' nor 'tooling'", report.failures.items[1]);
    try testing.expectEqualStrings("c: feature entry is not an object", report.failures.items[2]);
}
