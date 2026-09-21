//! `mylang context` answers one bounded question about one declaration: the
//! envelope, the selector, the priority order, the byte budget, staleness and
//! the incomplete-project path are each pinned here.
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const pc = @import("project_compile.zig");
const api_diff = @import("api_diff.zig");
const context = @import("context.zig");
const identity: @import("source_receipt.zig").Identity = .{ .compiler_sha256 = @splat(0), .zig_version = "test", .architecture = "test", .os = "test", .abi = "test", .optimize = "test" };

const main_source =
    \\module main
    \\import model
    \\
    \\
    \\def helper(x: i64) -> i64 effects():
    \\    return x + 1
    \\
    \\
    \\def tally(x: i64) -> i64 effects():
    \\    return helper(x) + model.helper(x)
    \\
    \\
    \\def main() -> i64:
    \\    return tally(2)
    \\
    \\
    \\def test_main() -> bool:
    \\    return main() == 7
;

const model_source =
    \\module model
    \\
    \\
    \\public class Reading:
    \\    value: i64
    \\
    \\
    \\public def helper(x: i64) -> i64 effects():
    \\    return x
    \\
    \\
    \\public def validate(x: i64) -> i64 effects():
    \\    return x
    \\
    \\
    \\public def reading(r: Reading) -> Reading effects():
    \\    return r
;

/// A project whose body syntax fails outright: the declarations are still
/// lexable, but nothing can be resolved.
const unparsable_source =
    \\module main
    \\
    \\
    \\def tally(x: i64) -> i64:
    \\    return +
;

/// A project whose bodies do not check: `missing` is never declared, so the
/// declarations survive while every resolved relationship does not.
const broken_source =
    \\module main
    \\
    \\
    \\def tally(x: i64) -> i64:
    \\    return missing(x)
;

/// The fixture every test loads, and the reader that both loads it and re-reads
/// it. `drift` makes the reader report bytes the answer never saw, and `gone`
/// makes it report a source it can no longer read.
const Sources = struct {
    main: []const u8 = main_source,
    model: []const u8 = model_source,
    drift: bool = false,
    gone: bool = false,
    /// Static reads fail with NotFound for this one path.
    missing: ?[]const u8 = null,

    fn sourceOf(self: *const Sources, path: []const u8) ?[]const u8 {
        if (std.mem.eql(u8, path, "main.my")) return self.main;
        if (std.mem.eql(u8, path, "model.my")) return self.model;
        return null;
    }

    fn load(context_ptr: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Sources = @ptrCast(@alignCast(context_ptr.?));
        if (self.missing) |absent| {
            if (std.mem.eql(u8, path, absent)) return error.NotFound;
        }
        const bytes = self.sourceOf(path) orelse return error.NotFound;
        if (bytes.len > limit) return error.TooLarge;
        return allocator.dupe(u8, bytes);
    }

    fn reread(context_ptr: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
        const self: *Sources = @ptrCast(@alignCast(context_ptr.?));
        if (self.gone) return null;
        const bytes = self.sourceOf(path) orelse return null;
        if (self.drift) return allocator.dupe(u8, "module main\n") catch null;
        return allocator.dupe(u8, bytes) catch null;
    }
};

/// One loaded fixture. The index and the compilation both allocate from the
/// project arena, so releasing the project releases all three.
const Loaded = struct {
    sources: Sources,
    project: graph.Project,
    index: interfaces.Index,
    compilation: pc.Compilation,

    fn init(sources: Sources) !*Loaded {
        const self = try t.allocator.create(Loaded);
        errdefer t.allocator.destroy(self);
        self.* = .{ .sources = sources, .project = graph.Project.init(t.allocator), .index = undefined, .compilation = undefined };
        errdefer self.project.deinit();
        try self.project.load(.{ .context = &self.sources, .read = Sources.load }, "main", .{});
        self.index = try interfaces.build(&self.project);
        self.compilation = try pc.Compilation.init(&self.index);
        return self;
    }

    /// A project whose import never resolved, which is what the lexical
    /// candidate path sees: loading stopped, so no receipt can be taken.
    fn initUnloaded() !*Loaded {
        const self = try t.allocator.create(Loaded);
        errdefer t.allocator.destroy(self);
        self.* = .{ .sources = .{ .missing = "model.my" }, .project = graph.Project.init(t.allocator), .index = undefined, .compilation = undefined };
        errdefer self.project.deinit();
        try t.expectError(error.SourceError, self.project.load(.{ .context = &self.sources, .read = Sources.load }, "main", .{}));
        return self;
    }

    /// A project whose body syntax failed: loading succeeded, so declarations
    /// can still be recovered lexically, but no compilation can be merged.
    fn initUnparsable() !*Loaded {
        const self = try t.allocator.create(Loaded);
        errdefer t.allocator.destroy(self);
        self.* = .{ .sources = .{ .main = unparsable_source }, .project = graph.Project.init(t.allocator), .index = undefined, .compilation = undefined };
        errdefer self.project.deinit();
        try self.project.load(.{ .context = &self.sources, .read = Sources.load }, "main", .{});
        try t.expectError(error.SourceError, interfaces.build(&self.project));
        return self;
    }

    fn deinit(self: *Loaded) void {
        self.project.deinit();
        t.allocator.destroy(self);
    }
};

/// One answer's options, with the revision reader wired to the same sources the
/// fixture was loaded from.
fn options(loaded: *Loaded, selector: context.Selector) context.Options {
    return .{
        .entry = "main.my",
        .selector = selector,
        .revision = .{ .context = @as(?*anyopaque, @ptrCast(&loaded.sources)), .read = Sources.reread },
    };
}

/// Render and parse one answer, keeping its document alive for the caller.
fn answer(allocator: std.mem.Allocator, loaded: *Loaded, settings: context.Options) !std.json.Parsed(std.json.Value) {
    const rendered = try context.render(allocator, &loaded.compilation, identity, settings);
    defer allocator.free(rendered.bytes);
    return std.json.parseFromSlice(std.json.Value, allocator, rendered.bytes, .{ .allocate = .alloc_always });
}

fn sectionNamed(root: std.json.Value, name: []const u8) ?std.json.Value {
    for (root.object.get("sections").?.array.items) |entry| {
        if (std.mem.eql(u8, entry.object.get("name").?.string, name)) return entry;
    }
    return null;
}

fn recordsOf(section: std.json.Value) []std.json.Value {
    return section.object.get("records").?.array.items;
}

fn onlyRecord(section: std.json.Value) std.json.ObjectMap {
    return recordsOf(section)[0].object;
}

fn isPresent(value: ?std.json.Value) bool {
    const present = value orelse return false;
    return switch (present) {
        .null => false,
        else => true,
    };
}

fn mentions(value: std.json.Value, needle: []const u8) bool {
    return std.mem.indexOf(u8, value.string, needle) != null;
}

/// The one-based line and column of the first occurrence of `needle`.
fn positionOf(bytes: []const u8, needle: []const u8) struct { line: usize, column: usize } {
    const at = std.mem.indexOf(u8, bytes, needle) orelse 0;
    var line: usize = 1;
    var column: usize = 1;
    for (bytes[0..at]) |ch| {
        if (ch == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ .line = line, .column = column };
}

fn expectPriorityOrder(root: std.json.Value) !void {
    const expected = [_][]const u8{ "declaration", "contract", "types", "dependencies", "tests", "changes" };
    const sections = root.object.get("sections").?.array.items;
    try t.expectEqual(expected.len, sections.len);
    for (expected, 0..) |name, index| try t.expectEqualStrings(name, sections[index].object.get("name").?.string);
}

fn expectStaticReachability(section: std.json.Value) !void {
    const records = recordsOf(section);
    try t.expect(records.len != 0);
    for (records) |record| try t.expectEqualStrings("static-reachability", record.object.get("basis").?.string);
}

fn expectBudgetOmissions(root: std.json.Value) !void {
    const omissions = root.object.get("omissions").?.array.items;
    try t.expect(omissions.len != 0);
    for (omissions) |omission| try t.expectEqualStrings("budget", omission.object.get("reason").?.string);
}

// spec: CONTEXT-ENVELOPE-1
test "context publishes one agent-context-v1 envelope pinned to its source" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    const parsed = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "main::main" }));
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqualStrings("agent-context-v1", root.object.get("version").?.string);
    try t.expectEqualStrings("ok", root.object.get("status").?.string);
    try t.expectEqualStrings("main.my", root.object.get("entry").?.string);
    try t.expectEqualStrings("checked", root.object.get("analysis").?.object.get("status").?.string);
    try t.expectEqual(@as(i64, 8192), root.object.get("context_bytes").?.integer);
    const selector = root.object.get("selector").?.object;
    try t.expectEqualStrings("symbol", selector.get("kind").?.string);
    try t.expectEqualStrings("main::main", selector.get("symbol").?.string);
    try t.expectEqualStrings("main::main", selector.get("resolved").?.string);
    const snapshot = root.object.get("snapshot").?.object;
    try t.expectEqual(@as(i64, 2), snapshot.get("modules").?.integer);
    try t.expectEqualStrings("test", snapshot.get("compiler").?.object.get("zig_version").?.string);
    try t.expectEqual(@as(usize, 64), root.object.get("snapshot_sha256").?.string.len);
    try t.expect(root.object.get("sections").?.array.items.len != 0);
    try t.expectEqual(@as(usize, 0), root.object.get("omissions").?.array.items.len);
}

// spec: CONTEXT-SELECT-1
test "context resolves one exact name and reports missing and ambiguous selectors" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    const exact = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "model::helper" }));
    defer exact.deinit();
    try t.expectEqualStrings("model::helper", exact.value.object.get("selector").?.object.get("resolved").?.string);
    const absent = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "model::absent" }));
    defer absent.deinit();
    try t.expectEqualStrings("missing", absent.value.object.get("status").?.string);
    try t.expect(isPresent(absent.value.object.get("reason")));
    const ambiguous = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "helper" }));
    defer ambiguous.deinit();
    try t.expectEqualStrings("ambiguous", ambiguous.value.object.get("status").?.string);
    const candidates = ambiguous.value.object.get("candidates").?.array.items;
    try t.expectEqual(@as(usize, 2), candidates.len);
    try t.expectEqualStrings("main::helper", candidates[0].string);
    try t.expectEqualStrings("model::helper", candidates[1].string);
    var capped = options(loaded, .{ .symbol = "main::main" });
    capped.limits = .{ .symbols = 1 };
    const limited = context.render(t.allocator, &loaded.compilation, identity, capped);
    try t.expectError(error.NavigationLimit, limited);
}

// spec: CONTEXT-AT-1
test "context selects the innermost declaration covering one source position" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    const at = positionOf(model_source, "return x\n\n\npublic def reading");
    const spec = try std.fmt.allocPrint(t.allocator, "model.my:{d}:{d}", .{ at.line, at.column });
    defer t.allocator.free(spec);
    const parsed = try answer(t.allocator, loaded, options(loaded, .{ .at = spec }));
    defer parsed.deinit();
    try t.expectEqualStrings("model::validate", parsed.value.object.get("selector").?.object.get("resolved").?.string);
    const malformed = try answer(t.allocator, loaded, options(loaded, .{ .at = "model.my:not-a-position" }));
    defer malformed.deinit();
    try t.expectEqualStrings("missing", malformed.value.object.get("status").?.string);
    const outside = try answer(t.allocator, loaded, options(loaded, .{ .at = "elsewhere.my:1:1" }));
    defer outside.deinit();
    try t.expectEqualStrings("missing", outside.value.object.get("status").?.string);
    const past_end = try answer(t.allocator, loaded, options(loaded, .{ .at = "model.my:9000:1" }));
    defer past_end.deinit();
    try t.expectEqualStrings("missing", past_end.value.object.get("status").?.string);
}

// spec: CONTEXT-SECTIONS-1
test "context publishes its sections in priority order with labeled facts" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    const baseline = try api_diff.snapshot(t.allocator, &loaded.compilation);
    defer t.allocator.free(baseline);
    var settings = options(loaded, .{ .symbol = "main::main" });
    settings.baseline = .{ .path = "baseline.txt", .bytes = baseline };
    const parsed = try answer(t.allocator, loaded, settings);
    defer parsed.deinit();
    try expectPriorityOrder(parsed.value);
    const contract = onlyRecord(sectionNamed(parsed.value, "contract").?);
    try t.expectEqualStrings("main::main", contract.get("id").?.string);
    try t.expectEqualStrings("checked", contract.get("analysis").?.string);
    try t.expect(isPresent(contract.get("effects")));
    try t.expect(isPresent(contract.get("mutates")));
    try t.expect(isPresent(contract.get("return_origin")));
    const declaration = onlyRecord(sectionNamed(parsed.value, "declaration").?);
    try t.expect(mentions(declaration.get("snippet").?, "return tally"));
    try expectStaticReachability(sectionNamed(parsed.value, "tests").?);
    try t.expect(recordsOf(sectionNamed(parsed.value, "dependencies").?).len != 0);
    try t.expectEqual(@as(usize, 0), recordsOf(sectionNamed(parsed.value, "changes").?).len);
    var tuned = settings;
    tuned.baseline = .{ .path = "baseline.txt", .bytes = "not a baseline\n" };
    const rejected = context.render(t.allocator, &loaded.compilation, identity, tuned);
    try t.expectError(error.InvalidBaseline, rejected);
}

// spec: CONTEXT-BUDGET-1
test "context never exceeds the requested budget and names what it omitted" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    var generous = options(loaded, .{ .symbol = "main::tally" });
    generous.context_bytes = 65536;
    const roomy = try answer(t.allocator, loaded, generous);
    defer roomy.deinit();
    try t.expectEqual(@as(usize, 0), roomy.value.object.get("omissions").?.array.items.len);
    const full = roomy.value.object.get("emitted_bytes").?.integer;
    try t.expect(full > 0);
    // A budget under the complete answer is the only one that proves the
    // reduction ladder ran; the amount under it only has to exceed one record.
    const tight_budget = full - 20;
    var tight = options(loaded, .{ .symbol = "main::tally" });
    tight.context_bytes = @intCast(tight_budget);
    const parsed = try answer(t.allocator, loaded, tight);
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqual(tight_budget, root.object.get("context_bytes").?.integer);
    try t.expect(root.object.get("emitted_bytes").?.integer <= tight_budget);
    try expectBudgetOmissions(root);
    try t.expect(root.object.get("continuation").?.string.len != 0);
    // The declaration and its contract are never what a budget gives up.
    try t.expect(root.object.get("sections").?.array.items.len >= 2);
    // The documented minimum must hold the envelope for a real project, so the
    // smallest accepted budget is answered rather than refused.
    var floor = options(loaded, .{ .symbol = "main::main" });
    floor.context_bytes = context.minimum_context_bytes;
    const minimal = try answer(t.allocator, loaded, floor);
    defer minimal.deinit();
    try t.expectEqualStrings("ok", minimal.value.object.get("status").?.string);
    try t.expect(minimal.value.object.get("emitted_bytes").?.integer <= context.minimum_context_bytes);
    try t.expect(minimal.value.object.get("sections").?.array.items.len >= 2);
    var tiny = options(loaded, .{ .symbol = "main::main" });
    tiny.context_bytes = context.minimum_context_bytes - 1;
    const refused = context.render(t.allocator, &loaded.compilation, identity, tiny);
    try t.expectError(error.BudgetTooSmall, refused);
}

// spec: CONTEXT-STALE-1
test "context rejects an answer whose source changed while it was assembled" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    loaded.sources.drift = true;
    const parsed = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "main::main" }));
    defer parsed.deinit();
    try t.expectEqualStrings("stale", parsed.value.object.get("status").?.string);
    try t.expect(isPresent(parsed.value.object.get("reason")));
    try t.expectEqual(@as(usize, 0), parsed.value.object.get("sections").?.array.items.len);
    loaded.sources.drift = false;
    loaded.sources.gone = true;
    const unreadable = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "main::main" }));
    defer unreadable.deinit();
    try t.expectEqualStrings("stale", unreadable.value.object.get("status").?.string);
}

// spec: CONTEXT-PARTIAL-1
test "context answers an incomplete project with declarations and the reason" {
    var loaded = try Loaded.init(.{ .main = broken_source });
    defer loaded.deinit();
    try t.expectError(error.SourceError, loaded.compilation.check());
    const parsed = try answer(t.allocator, loaded, options(loaded, .{ .symbol = "main::tally" }));
    defer parsed.deinit();
    const root = parsed.value;
    try t.expectEqualStrings("partial", root.object.get("status").?.string);
    try t.expectEqualStrings("declaration-only", root.object.get("analysis").?.object.get("status").?.string);
    try t.expect(isPresent(root.object.get("analysis").?.object.get("reason")));
    const declaration = onlyRecord(sectionNamed(root, "declaration").?);
    try t.expectEqualStrings("main::tally", declaration.get("id").?.string);
    try t.expectEqual(@as(usize, 0), recordsOf(sectionNamed(root, "dependencies").?).len);
    const contract = onlyRecord(sectionNamed(root, "contract").?);
    try t.expectEqualStrings("declaration-only", contract.get("analysis").?.string);
    try t.expect(!isPresent(contract.get("effects")));
}

// spec-case: CONTEXT-PARTIAL-1
test "context names a declaration recovered only by lexing" {
    var loaded = try Loaded.initUnparsable();
    defer loaded.deinit();
    const rendered = try context.renderPartial(t.allocator, &loaded.project, identity, options(loaded, .{ .symbol = "main::tally" }));
    defer t.allocator.free(rendered.bytes);
    try t.expectEqual(context.Status.partial, rendered.status);
    const parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, rendered.bytes, .{ .allocate = .alloc_always });
    defer parsed.deinit();
    try t.expectEqualStrings("partial", parsed.value.object.get("status").?.string);
    try t.expectEqualStrings("lexical-only", parsed.value.object.get("analysis").?.object.get("status").?.string);
    try t.expectEqualStrings("main::tally", parsed.value.object.get("selector").?.object.get("resolved").?.string);
    const declaration = onlyRecord(sectionNamed(parsed.value, "declaration").?);
    try t.expectEqualStrings("main::tally", declaration.get("id").?.string);
    try t.expectEqualStrings("tally", declaration.get("name").?.string);
    const contract = onlyRecord(sectionNamed(parsed.value, "contract").?);
    try t.expectEqualStrings("lexical-only", contract.get("analysis").?.string);
    try t.expect(!isPresent(contract.get("effects")));
}

/// A reader that can re-read nothing, used to prove which inputs a run is
/// allowed to skip.
fn unreadableSource(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8) ?[]u8 {
    return null;
}

// spec-case: CONTEXT-STALE-1
test "context does not re-read a module the run supplied in memory" {
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    var settings = options(loaded, .{ .symbol = "main::main" });
    settings.revision.supplied = &.{ "main.y", "model.my" };
    settings.revision.read = unreadableSource;
    const parsed = try answer(t.allocator, loaded, settings);
    defer parsed.deinit();
    try t.expectEqualStrings("stale", parsed.value.object.get("status").?.string);
    var supplied = options(loaded, .{ .symbol = "main::main" });
    supplied.revision.supplied = &.{ "main.my", "model.my" };
    supplied.revision.read = unreadableSource;
    const skipped = try answer(t.allocator, loaded, supplied);
    defer skipped.deinit();
    try t.expectEqualStrings("ok", skipped.value.object.get("status").?.string);
}

// spec-case: CONTEXT-PARTIAL-1
test "context reports an unloaded project and an allocation failure as errors" {
    var unloaded = try Loaded.initUnloaded();
    defer unloaded.deinit();
    const bytes = context.renderPartial(t.allocator, &unloaded.project, identity, options(unloaded, .{ .symbol = "main::main" }));
    try t.expectError(error.IncompleteProject, bytes);
    var loaded = try Loaded.init(.{});
    defer loaded.deinit();
    try loaded.compilation.check();
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    const refused = context.render(failing.allocator(), &loaded.compilation, identity, options(loaded, .{ .symbol = "main::main" }));
    try t.expectError(error.OutOfMemory, refused);
}
