//! Navigation at project scale: no fixed cap on the tables, the bounded
//! `index-project` documents, the call-site spelling of a declaration, and the
//! syntax-derived `tests-for` answer on a project that does not check.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const pc = @import("project_compile.zig");
const navigation = @import("navigation.zig");
const navigation_partial = @import("navigation_partial.zig");
const navigation_syntax = @import("navigation_syntax.zig");
const views = @import("navigation_views.zig");
const identity: @import("source_receipt.zig").Identity = .{ .compiler_sha256 = @splat(0), .zig_version = "test", .architecture = "test", .os = "test", .abi = "test", .optimize = "test" };

const File = struct { path: []const u8, bytes: []const u8 };
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        for (self.entries) |file| {
            if (!std.mem.eql(u8, file.path, path)) continue;
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        }
        return error.NotFound;
    }
    fn provider(self: *Files) graph.Provider {
        return .{ .context = self, .read = read };
    }
};

/// Two modules: `main` calls `data` through an alias and a domain member
/// through its module path, and two discovered tests — one by name, one by
/// `@test` — reach the helpers.
const data_source =
    \\
    \\
    \\public record Box:
    \\    value: int
    \\
    \\
    \\public domain Meters: int:
    \\    func make(value: int) -> Meters effects():
    \\        return wrap[Meters](value)
    \\
    \\
    \\public func read(box: Box) -> int effects():
    \\    return box.value
;
const main_source =
    \\import data as d
    \\
    \\
    \\func helper(x: int) -> int:
    \\    mut meters = d.Meters.make(x)
    \\    return d.read(d.Box(value=x)) + 1
    \\
    \\
    \\func main() -> int:
    \\    return helper(1)
    \\
    \\
    \\func test_helper() -> bool:
    \\    return helper(1) == 2
    \\
    \\
    \\@test
    \\func main_answers() -> bool:
    \\    return main() == 2
;
/// `main_source` with a type error in `main`, so no body checks.
const red_main_source =
    \\import data as d
    \\
    \\
    \\func helper(x: int) -> int:
    \\    mut meters = d.Meters.make(x)
    \\    return d.read(d.Box(value=x)) + 1
    \\
    \\
    \\func main() -> int:
    \\    return helper(1) + "red"
    \\
    \\
    \\func test_helper() -> bool:
    \\    return helper(1) == 2
    \\
    \\
    \\@test
    \\func main_answers() -> bool:
    \\    return main() == 2
;
const green = [_]File{ .{ .path = source_names.entry, .bytes = main_source }, .{ .path = "data.selka", .bytes = data_source } };
const red = [_]File{ .{ .path = source_names.entry, .bytes = red_main_source }, .{ .path = "data.selka", .bytes = data_source } };

/// One loaded fixture and its merged compilation, checked when the bodies check.
const Scene = struct {
    files: Files,
    project: graph.Project,
    index: interfaces.Index = undefined,
    compilation: pc.Compilation = undefined,

    fn open(self: *Scene) !void {
        try self.project.load(self.files.provider(), "main", .{});
        self.index = try interfaces.build(&self.project);
        self.compilation = try pc.Compilation.init(&self.index);
        self.compilation.check() catch |err| switch (err) {
            error.SourceError => {},
            else => return err,
        };
    }
};

fn scene(entries: []const File) Scene {
    return .{ .files = .{ .entries = entries }, .project = graph.Project.init(t.allocator) };
}

/// The document one `index-project` view prints for a compilation.
fn view(compilation: *pc.Compilation, request: views.Request, status: views.Status) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(t.allocator);
    errdefer out.deinit();
    try t.expectEqual(status, try views.writeChecked(&out.writer, t.allocator, compilation, identity, request));
    return out.toOwnedSlice();
}

fn parse(bytes: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, t.allocator, bytes, .{});
}

fn count(value: std.json.Value, key: []const u8) usize {
    return value.object.get(key).?.array.items.len;
}

/// A module of `functions` one-line functions, each reading its parameter
/// through a local: three symbols and at least two relationship rows apiece.
fn generated(allocator: std.mem.Allocator, functions: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("\n\nfunc main() -> int:\n    return 0\n");
    for (0..functions) |i| try text.writer.print("\n\nfunc f{d}(n: int) -> int:\n    const x = n\n    return x\n", .{i});
    return text.toOwnedSlice();
}

/// `count` top-level `def` candidates past a body syntax failure: only the
/// lexer's view of the module survives.
fn lexicalSource(allocator: std.mem.Allocator, candidates: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("\n\n");
    for (0..candidates) |i| try text.writer.print("func f{d}\n", .{i});
    return text.toOwnedSlice();
}

/// Every symbol a selection published has an id under `prefix`.
fn allInModule(value: std.json.Value, prefix: []const u8) !void {
    for (value.object.get("symbols").?.array.items) |symbol| {
        try t.expect(std.mem.startsWith(u8, symbol.object.get("id").?.string, prefix));
    }
}

/// Whether a published reference leaves `from`.
fn hasReferenceFrom(value: std.json.Value, from: []const u8) bool {
    for (value.object.get("references").?.array.items) |reference| {
        if (std.mem.eql(u8, reference.object.get("from").?.string, from)) return true;
    }
    return false;
}

/// The syntax answer for `subject` is the checked answer plus the basis line.
fn sameAnswer(checked: *pc.Compilation, syntax: navigation_syntax.Graph, subject: []const u8) !void {
    const expected = (try navigation.renderTestsFor(t.allocator, checked, subject)).?;
    defer t.allocator.free(expected);
    const answered = (try navigation_syntax.renderTestsFor(t.allocator, syntax, subject)).?;
    defer t.allocator.free(answered);
    try t.expect(std.mem.startsWith(u8, answered, expected));
    try t.expectEqualStrings("  " ++ navigation_syntax.basis ++ "\n", answered[expected.len..]);
}

// spec: NAVIGATION-SCALE-1
test "navigation has no fixed cap: the tables grow past any count only an explicit caller cap refuses" {
    // No command sets a cap, and the default is none.
    try t.expectEqual(@as(?usize, null), (navigation.Limits{}).symbols);
    try t.expectEqual(@as(?usize, null), (navigation.Limits{}).references);

    // A checked project whose tables exceed a small cap: the cap, standing in
    // for the old fixed 50000/250000, refuses it; the command path answers it.
    const source = try generated(t.allocator, 200);
    defer t.allocator.free(source);
    var checked = scene(&.{.{ .path = source_names.entry, .bytes = source }});
    defer checked.project.deinit();
    try checked.open();
    try t.expect(checked.compilation.program != null);
    var facts = try navigation.collect(t.allocator, &checked.compilation, identity, .{});
    defer facts.deinit();
    try t.expect(facts.symbols.len > 600 and facts.references.len > 400);
    try t.expectError(error.NavigationLimit, navigation.collect(t.allocator, &checked.compilation, identity, .{ .limits = .{ .symbols = 600 } }));
    try t.expectError(error.NavigationLimit, navigation.collect(t.allocator, &checked.compilation, identity, .{ .limits = .{ .references = 400 } }));
    const full = try view(&checked.compilation, .{ .view = .full }, .ok);
    defer t.allocator.free(full);
    const document = try parse(full);
    defer document.deinit();
    try t.expectEqual(facts.symbols.len, count(document.value, "symbols"));
    try t.expectEqual(facts.references.len, count(document.value, "references"));

    // The lexical recovery path past the old fixed 50000-candidate cap.
    const lexical = try lexicalSource(t.allocator, 50_001);
    defer t.allocator.free(lexical);
    var files: Files = .{ .entries = &.{.{ .path = source_names.entry, .bytes = lexical }} };
    var loaded = graph.Project.init(t.allocator);
    defer loaded.deinit();
    try loaded.load(files.provider(), "main", .{});
    var recovered = try navigation_partial.candidates(t.allocator, &loaded);
    defer recovered.deinit();
    try t.expectEqual(@as(usize, 50_001), recovered.symbols.len);
}

// spec: NAVIGATION-SUMMARY-1
test "index-project defaults to a per-module summary whose size follows the module count" {
    var fixture = scene(&green);
    defer fixture.project.deinit();
    try fixture.open();
    const bytes = try view(&fixture.compilation, .{ .entry = "app/main.selka" }, .ok);
    defer t.allocator.free(bytes);
    const document = try parse(bytes);
    defer document.deinit();
    const root = document.value.object;
    try t.expectEqualStrings("navigation-summary-v1", root.get("version").?.string);
    try t.expect(root.get("checked").?.bool);
    try t.expect(root.get("symbols") == null and root.get("references") == null);
    try t.expectEqual(@as(i64, 2), root.get("totals").?.object.get("modules").?.integer);
    const modules = root.get("modules").?.array.items;
    try t.expectEqual(@as(usize, 2), modules.len);
    const data_row = modules[0].object;
    try t.expectEqualStrings("data", data_row.get("module").?.string);
    try t.expectEqualStrings("data.selka", data_row.get("path").?.string);
    // `Box`, `Meters`, its member `Meters.make` and `read`.
    try t.expectEqual(@as(i64, 4), data_row.get("exported").?.integer);
    try t.expectEqual(@as(i64, 2), data_row.get("kinds").?.object.get("function").?.integer);
    try t.expectEqual(@as(i64, 2), data_row.get("kinds").?.object.get("type").?.integer);
    try t.expect(data_row.get("kinds").?.object.get("case") == null);
    const main_row = modules[1].object;
    try t.expectEqual(@as(i64, 4), main_row.get("kinds").?.object.get("function").?.integer);
    try t.expectEqual(@as(i64, 1), main_row.get("kinds").?.object.get("local").?.integer);
    const queries = root.get("queries").?.object;
    try t.expectEqualStrings("selka index-project app/main.selka --module=MODULE", queries.get("module").?.string);
    try t.expectEqualStrings("selka context app/main.selka --symbol=MODULE.NAME", queries.get("context").?.string);
    try t.expectEqualStrings("selka index-project app/main.selka --full", queries.get("full").?.string);
}

// spec: NAVIGATION-FULL-1
test "index-project --full streams the complete navigation-v1 document byte for byte" {
    var fixture = scene(&green);
    defer fixture.project.deinit();
    try fixture.open();
    const streamed = try view(&fixture.compilation, .{ .view = .full }, .ok);
    defer t.allocator.free(streamed);
    const rendered = try navigation.render(t.allocator, &fixture.compilation, identity, .{});
    defer t.allocator.free(rendered);
    try t.expectEqualStrings(rendered, streamed);
    try t.expect(std.mem.startsWith(u8, streamed, "{\"version\":\"navigation-v1\","));
}

// spec: NAVIGATION-SELECT-1
test "index-project filters publish the navigation-v1 records they select and name what they could not" {
    var fixture = scene(&green);
    defer fixture.project.deinit();
    try fixture.open();

    const by_module = try view(&fixture.compilation, .{ .view = .{ .selection = .{ .module = "data" } } }, .ok);
    defer t.allocator.free(by_module);
    const module_document = try parse(by_module);
    defer module_document.deinit();
    try t.expectEqualStrings("navigation-selection-v1", module_document.value.object.get("version").?.string);
    try allInModule(module_document.value, "data::");
    // `main` calls into `data`, so the selection carries that incoming edge and
    // the snapshot row of the module it is located in.
    try t.expect(hasReferenceFrom(module_document.value, "main::helper"));
    try t.expectEqual(@as(usize, 2), module_document.value.object.get("snapshot").?.object.get("inputs").?.array.items.len);

    const by_symbol = try view(&fixture.compilation, .{ .view = .{ .selection = .{ .symbol = "main.helper" } } }, .ok);
    defer t.allocator.free(by_symbol);
    const symbol_document = try parse(by_symbol);
    defer symbol_document.deinit();
    try t.expectEqualStrings("main::helper", symbol_document.value.object.get("selection").?.object.get("resolved").?.string);
    const selected = symbol_document.value.object.get("symbols").?.array.items;
    try t.expectEqualStrings("main::helper", selected[0].object.get("id").?.string);
    // Its parameter and its local are members it owns.
    try t.expectEqual(@as(usize, 3), selected.len);

    const by_kind = try view(&fixture.compilation, .{ .view = .{ .selection = .{ .module = "data", .kind = "type" } } }, .ok);
    defer t.allocator.free(by_kind);
    const kind_document = try parse(by_kind);
    defer kind_document.deinit();
    try t.expectEqual(@as(usize, 2), count(kind_document.value, "symbols"));

    const missing = try view(&fixture.compilation, .{ .view = .{ .selection = .{ .symbol = "main.absent" } } }, .missing);
    defer t.allocator.free(missing);
    const missing_document = try parse(missing);
    defer missing_document.deinit();
    try t.expectEqualStrings("missing", missing_document.value.object.get("status").?.string);
    try t.expectEqual(@as(usize, 0), count(missing_document.value, "symbols"));

    const unknown_module = try view(&fixture.compilation, .{ .view = .{ .selection = .{ .module = "nowhere" } } }, .missing);
    defer t.allocator.free(unknown_module);
    try t.expect(std.mem.indexOf(u8, unknown_module, "no loaded module has that name") != null);

    // `x`-style names every function repeats are ambiguous without a module.
    const ambiguous = try view(&fixture.compilation, .{ .view = .{ .selection = .{ .symbol = "value" } } }, .ambiguous);
    defer t.allocator.free(ambiguous);
    const ambiguous_document = try parse(ambiguous);
    defer ambiguous_document.deinit();
    try t.expect(ambiguous_document.value.object.get("candidates").?.array.items.len >= 2);
}

// spec: NAVIGATION-SPELLING-1
test "a dotted call-site spelling resolves at every module split and never picks among several" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const ids = [_][]const u8{ "m060::f060_00", "shared.units::Distance.make", "a.b::c", "a::b.c", "main::main" };
    try t.expectEqualStrings("m060::f060_00", (try navigation.resolveSpelling(scratch, "m060::f060_00", &ids)).found);
    try t.expectEqualStrings("m060::f060_00", (try navigation.resolveSpelling(scratch, "m060.f060_00", &ids)).found);
    try t.expectEqualStrings("shared.units::Distance.make", (try navigation.resolveSpelling(scratch, "shared.units.Distance.make", &ids)).found);
    const both = (try navigation.resolveSpelling(scratch, "a.b.c", &ids)).ambiguous;
    try t.expectEqual(@as(usize, 2), both.len);
    try t.expectEqualStrings("a.b::c", both[0]);
    try t.expect((try navigation.resolveSpelling(scratch, "m060.missing", &ids)) == .missing);
    try t.expect((try navigation.resolveSpelling(scratch, "m060::f060_01", &ids)) == .missing);
    try t.expect((try navigation.resolveSpelling(scratch, "main", &ids)) == .missing);
}

// spec: TESTS-FOR-SYNTAX-1
test "tests-for on a project that does not check answers from the syntax call graph" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var checked = scene(&green);
    defer checked.project.deinit();
    try checked.open();
    try t.expect(checked.compilation.program != null);
    var broken = scene(&red);
    defer broken.project.deinit();
    try broken.open();
    try t.expect(broken.compilation.program == null);
    const syntax = try navigation_syntax.build(scratch, &broken.compilation);
    // Alias calls, a domain member behind an alias and the `@test` rule all
    // resolve the way the checker resolves them.
    try sameAnswer(&checked.compilation, syntax, "data::read");
    try sameAnswer(&checked.compilation, syntax, "main::helper");
    try sameAnswer(&checked.compilation, syntax, "data::Meters.make");
    const helper = (try navigation_syntax.renderTestsFor(t.allocator, syntax, "main::helper")).?;
    defer t.allocator.free(helper);
    try t.expect(std.mem.indexOf(u8, helper, "direct (1): main::test_helper\n") != null);
    try t.expect(std.mem.indexOf(u8, helper, "reached-by (2):") != null);
    try t.expectEqual(@as(?[]u8, null), try navigation_syntax.renderTestsFor(t.allocator, syntax, "main::absent"));
}
