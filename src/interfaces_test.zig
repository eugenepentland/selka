//! Module interface and export privacy tests covering qualified names, semantic checking, execution, and allocation failures.
const effects_removed_code = "E_EFFECTS_REMOVED";
const empty_effect_clause = " effects()";
const project_compile_module = @import("project_compile.zig");
const units_path = "units.selka";
/// Local name a facade publishes and resolves through in these scenarios.
const distance_name = "Distance";
const contracts_module = "contracts.selka";
const duplicates_module = @import("duplicates.zig");
const std = @import("std");
const t = std.testing;
const graph = @import("project.zig");
const ast = @import("ast.zig");
const interfaces = @import("interfaces.zig");
const source = @import("source.zig");
const fact_status = @import("fact_status.zig");
const module_names = @import("module_names.zig");
const project_syntax = @import("project_syntax.zig");
const diagnostic_module = @import("diagnostic.zig");
const native = @import("native_execute.zig");
const File = struct { path: []const u8, bytes: []const u8 };
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) graph.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        for (self.entries) |file| if (std.mem.eql(u8, file.path, path)) {
            if (file.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, file.bytes);
        };
        return error.NotFound;
    }
    fn provider(self: *Files) graph.Provider {
        return .{ .context = self, .read = read };
    }
};
const units =
    \\
    \\
    \\public domain Distance: i64:
    \\    private func raw(x: i64) -> Distance:
    \\        return wrap[Distance](x)
    \\
    \\    func make(x: i64) -> Distance effects():
    \\        return Distance.raw(x)
    \\
    \\
    \\func hidden() -> i64:
    \\    return 9
;
const entry =
    \\import units
    \\
    \\
    \\public record Sample:
    \\    distance: units.Distance
    \\
    \\
    \\public func echo(x: FixedArray[units.Distance, 2]) -> FixedArray[units.Distance, 2] effects():
    \\    return x
    \\
    \\
    \\func main() -> i64:
    \\    mut x = units.Distance.make(2)
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    const current_entry = try std.mem.replaceOwned(u8, allocator, entry, empty_effect_clause, "");
    defer allocator.free(current_entry);
    const current_units = try std.mem.replaceOwned(u8, allocator, units, empty_effect_clause, "");
    defer allocator.free(current_units);
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = current_entry }, .{ .path = units_path, .bytes = current_units } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    const distance = try index.resolve(.{ .from = 0, .alias = "units", .name = distance_name, .kind = .type, .owner = null, .span = span });
    try t.expectEqual(@as(usize, 1), distance.module);
    _ = try index.resolve(.{ .from = 0, .alias = "units", .name = "Distance.make", .kind = .function, .owner = null, .span = span });
    _ = try index.resolve(.{ .from = 1, .alias = null, .name = "Distance.raw", .kind = .function, .owner = distance_name, .span = span });
    _ = try index.resolve(.{ .from = 1, .alias = null, .name = "hidden", .kind = .function, .owner = null, .span = span });
    const text = try index.render(allocator);
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function Distance.make") != null);
    try t.expect(std.mem.indexOf(u8, text, "Distance.raw") == null);
    try t.expect(std.mem.indexOf(u8, text, "hidden") == null);
    try t.expect(std.mem.indexOf(u8, text, "bodies not type checked") != null);
    const syntax = index.units[0].syntax;
    var call_seen = false;
    for (syntax.nodes.items) |node| if (node.data == .call) {
        call_seen = true;
        try t.expectEqualStrings("units.Distance", project.modules.items[0].src.text(node.data.call.owner.?));
    };
    try t.expect(call_seen);
}
test "module interfaces resolve nominal identities and exported domain methods with allocation failures" {
    // Preserve both exact old module fixtures as executable effect-removal witnesses.
    try reject(entry, "E_EFFECTS_REMOVED");
    try reject("import units\nfunc main() -> int:\n    return 0\n", "E_EFFECTS_REMOVED");
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}

// spec: INTERFACE-SIGNATURE-1
test "default interface listing renders the whole signature with Python capability spellings" {
    const body =
        \\
        \\
        \\public func main(fs: Filesystem, clock: Clock) -> int:
        \\    _ = fs
        \\    _ = clock
        \\    return 0
        \\
        \\
        \\public func bump(mut values: int[]) -> int:
        \\    values[0] = values[0] + 1
        \\    return values[0]
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "func(fs:Filesystem,clock:Clock)->i64") != null);
    try t.expect(std.mem.indexOf(u8, text, "filesystem_cap") == null);
    try t.expect(std.mem.indexOf(u8, text, "clock_cap") == null);
    try t.expect(std.mem.indexOf(u8, text, "effects(") == null);
    try t.expect(std.mem.indexOf(u8, text, "func(mut values:i64[])->i64") != null);
    try t.expect(std.mem.indexOf(u8, text, "ceiling(") == null);
}

// spec: KEYWORD-ONLY-3
test "an interface signature prints individual named parameter markers" {
    const body =
        \\
        \\
        \\public func issue(host: int, named code: int, named file: int = 0) -> int:
        \\    return host + code + file
        \\
        \\
        \\public func main() -> int:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "func(host:i64,named code:i64,named file:i64=0)->i64") != null);
}

// spec-case: TUPLE-7
test "list-interfaces spells a tuple signature back in source form" {
    const retired_body =
        \\import strings
        \\
        \\
        \\public func split(text: str, sep: str) -> tuple[str, str]:
        \\    return text, sep
        \\
        \\
        \\public func main() -> int:
        \\    const head, rest = split("key=value", "=")
        \\    return strings.char_count(head) + strings.char_count(rest)
    ;
    // Preserve the retired tuple witness and check current nominal return coverage.
    try rejectChecked(retired_body, "", "E_TUPLE_REMOVED");
    const body =
        \\import strings
        \\public record Split:
        \\    head: str
        \\    rest: str
        \\
        \\public func split(text: str, sep: str) -> Split:
        \\    return Split(head=copy(text), rest=copy(sep))
        \\
        \\public func main() -> int:
        \\    const pair = split("key=value", "=")
        \\    return strings.char_count(pair.head) + strings.char_count(pair.rest)
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    const surface = try @import("typed.zig").surfaceTypeText(t.allocator, text);
    defer t.allocator.free(surface);
    try t.expect(std.mem.indexOf(u8, surface, "export type Split") != null);
    try t.expect(std.mem.indexOf(u8, surface, "func(text:str, sep:str)->main.Split") != null);
}

fn reject(body: []const u8, code: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = body }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    try t.expectError(error.SourceError, interfaces.build(&project));
    try t.expectEqualStrings(code, project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
}

/// Test only: erase the one retired clause present in these interface fixtures.
/// Keep original guest bytes and exercise their exact removal when they contain it.
fn rejectEffectErased(body: []const u8, code: []const u8) !void {
    if (std.mem.indexOf(u8, body, empty_effect_clause) != null) try reject(body, effects_removed_code);
    const current_body = try std.mem.replaceOwned(u8, t.allocator, body, empty_effect_clause, "");
    defer t.allocator.free(current_body);
    const current_units = try std.mem.replaceOwned(u8, t.allocator, units, empty_effect_clause, "");
    defer t.allocator.free(current_units);
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = current_body }, .{ .path = units_path, .bytes = current_units } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    try t.expectError(error.SourceError, interfaces.build(&project));
    try t.expectEqualStrings(code, project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
}
// spec-case: DOC-1
test "list-interfaces prints a declaration's first docstring line" {
    const body =
        \\
        \\
        \\public record Point:
        \\    """A point in the plane."""
        \\    x: int
        \\
        \\
        \\public func area(width: int, height: int) -> int:
        \\    """The rectangle's area.
        \\
        \\    Long detail that the listing drops.
        \\    """
        \\    return width * height
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export type Point # A point in the plane.") != null);
    try t.expect(std.mem.indexOf(u8, text, "# The rectangle's area.") != null);
    try t.expect(std.mem.indexOf(u8, text, "Long detail") == null);
}
// spec: PROJ-3
test "module interfaces reject duplicate exports missing symbols and private type leaks" {
    try rejectEffectErased(
        \\export Missing
    , "E_EXPORT_REMOVED");
    try rejectEffectErased(
        \\import units
        \\export units.Missing
        \\export units.Missing
    , "E_DUPLICATE_EXPORT");
    try rejectEffectErased(
        \\import units
        \\
        \\
        \\record units:
        \\    pass
    , "E_IMPORT_ALIAS");
    try rejectEffectErased(
        \\
        \\
        \\record X:
        \\    pass
        \\
        \\
        \\func X() -> i64:
        \\    return 0
    , "E_DUPLICATE_SYMBOL");
    try rejectEffectErased(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func f(x: Secret) -> i64:
        \\    return 0
    , "E_PRIVATE_INTERFACE");
    try rejectEffectErased(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public record Box:
        \\    value: FixedArray[Secret, 2]
    , "E_PRIVATE_INTERFACE");
    try rejectEffectErased(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public enum Box:
        \\    value(value: Secret)
    , "E_PRIVATE_INTERFACE");
    try rejectEffectErased(
        \\
        \\
        \\public func f(x: Missing) -> i64:
        \\    return 0
    , "E_UNKNOWN_SYMBOL");
    try rejectEffectErased(
        \\func broken(
    , "E_SYNTAX");
}
// spec-case: DIAG-ORACLE-1
test "module interfaces suggest close function names for unknown symbols" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\
        \\
        \\func twice(x: i64) -> i64:
        \\    return x + x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = null, .name = "twic", .kind = .function, .owner = null, .span = span }));
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
    try t.expect(std.mem.indexOf(u8, message, "did you mean `twice`?") != null);
}
/// The rendered `E_UNKNOWN_SYMBOL` for `alias.name` from a main module that imports `import_line` (F-51).
fn standardMiss(import_line: []const u8, alias: []const u8, name: []const u8, kind: interfaces.Kind) ![]const u8 {
    const main = try std.fmt.allocPrint(t.allocator, "{s}\n\n\nfunc main() -> i64:\n    return 0\n", .{import_line});
    defer t.allocator.free(main);
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = main }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = alias, .name = name, .kind = kind, .owner = null, .span = span }));
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", project.problem.?.code);
    return project.renderProblem(t.allocator);
}
// spec-case: DIAG-ORACLE-1
test "an unknown name of a module names the module, its close names and the standard modules that declare it (F-51)" {
    const near = try standardMiss("import strings", "strings", "joinx", .function);
    defer t.allocator.free(near);
    try t.expect(std.mem.indexOf(u8, near, "module `strings` declares no `joinx`; did you mean `join`?") != null);
    const elsewhere = try standardMiss("import strings", "strings", "contains", .function);
    defer t.allocator.free(elsewhere);
    try t.expect(std.mem.indexOf(u8, elsewhere, "module `strings` declares no `contains`; whether text holds a part is the operator `in`: " ++
        "write `part in text` (`lists.contains` is only for lists)") != null);
    const aliased = try standardMiss("import lists as l", "l", "join", .function);
    defer t.allocator.free(aliased);
    try t.expect(std.mem.indexOf(u8, aliased, "module `lists` (imported as `l`) declares no `join`; the standard modules `bytes` and " ++
        "`strings` declare a function `join` (import one, as in `bytes.join(...)`)") != null);
    const type_name = try standardMiss("import strings", "strings", "Nope", .type);
    defer t.allocator.free(type_name);
    try t.expect(std.mem.indexOf(u8, type_name, "module `strings` declares no `Nope`") != null);
    try t.expect(std.mem.indexOf(u8, type_name, "standard module") == null);
}
/// Resolve `spelled` (`strings.contains`) as written at the start of `statement`, in a main module that imports `import_line`: the
/// problem's message must be `message`, and its fix the one edit that replaces `fix[0]` with `fix[1]`, or none when `fix` is null.
fn expectMembershipMiss(import_line: []const u8, statement: []const u8, spelled: []const u8, message: []const u8, fix: ?[2][]const u8) !void {
    const main = try std.fmt.allocPrint(t.allocator, "{s}\n\n\nfunc main() -> i64:\n    {s}\n        return 1\n    return 0\n", .{ import_line, statement });
    defer t.allocator.free(main);
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = main }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const at = std.mem.indexOf(u8, main, spelled).?;
    const dot = std.mem.indexOfScalar(u8, spelled, '.').?;
    const span: source.Span = .{ .start = at, .end = at + spelled.len };
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = spelled[0..dot], .name = spelled[dot + 1 ..], .kind = .function, .owner = null, .span = span }));
    const problem = project.problem.?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", problem.code);
    try t.expectEqualStrings(message, problem.message);
    const wanted = fix orelse {
        try t.expect(problem.fix == null);
        return;
    };
    try t.expectEqualStrings(wanted[0], main[problem.fix.?.span.start..problem.fix.?.span.end]);
    try t.expectEqualStrings(wanted[1], problem.fix.?.text);
    try t.expectEqual(@as(usize, 0), problem.fix_more.len);
}
// MSG-B 1: `strings.contains(text, part)` was answered with `lists.contains`, a function for lists. The answer is the operator `in`
// with the operands swapped; the call is rewritten when both operands are plain, and the sentence keeps the type's placeholders when
// they are not.
test "contains asked of text, bytes, a set or a dictionary module is told to write the operator in, with the call rewritten when plain" {
    try expectMembershipMiss(
        "import strings",
        "if strings.contains(text, \"ell\"):",
        "strings.contains",
        "module `strings` declares no `contains`; whether text holds a part is the operator `in`: write `\"ell\" in text` (`lists.contains` is only for lists)",
        .{ "strings.contains(text, \"ell\")", "\"ell\" in text" },
    );
    try expectMembershipMiss(
        "import bytes as b",
        "if not b.contains(frame.data, 10):",
        "b.contains",
        "module `bytes` (imported as `b`) declares no `contains`; whether bytes hold a byte or a run of bytes is the operator `in`: write `10 in frame.data` (`lists.contains` is only for lists)",
        .{ "not b.contains(frame.data, 10)", "10 not in frame.data" },
    );
    try expectMembershipMiss(
        "import sets",
        "if sets.contains(seen, name) == flag:",
        "sets.contains",
        "module `sets` declares no `contains`; whether a set holds a value is the operator `in`: write `name in seen` (`lists.contains` is only for lists)",
        .{ "sets.contains(seen, name)", "(name in seen)" },
    );
    try expectMembershipMiss(
        "import dicts",
        "if dicts.contains(table, strings.lower(name)):",
        "dicts.contains",
        "module `dicts` declares no `contains`; whether a dictionary has a key is the operator `in`: write `key in mapping` (`lists.contains` is only for lists)",
        null,
    );
    try expectMembershipMiss(
        "import strings",
        "if strings.contains(values=text, part=\"x\"):",
        "strings.contains",
        "module `strings` declares no `contains`; whether text holds a part is the operator `in`: write `part in text` (`lists.contains` is only for lists)",
        null,
    );
}
/// What resolving a bare name left in the project: the problem's message, and the text its fix deletes (null: no fix).
const BareMiss = struct {
    message: []const u8,
    removed: ?[]const u8,

    fn deinit(self: BareMiss) void {
        t.allocator.free(self.message);
        if (self.removed) |text| t.allocator.free(text);
    }
};

/// Resolve the bare `name` written as `call` in `files[0]` (the main module, a program of one function), which must be refused as
/// `E_UNKNOWN_SYMBOL`; the caller releases what it returns.
fn bareMiss(files: []const File, name: []const u8, call: []const u8) !BareMiss {
    var served: Files = .{ .entries = files };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(served.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const main = files[0].bytes;
    const at = std.mem.indexOf(u8, main, call).?;
    const span: source.Span = .{ .start = at, .end = at + name.len };
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = null, .name = name, .kind = .function, .owner = null, .span = span }));
    const problem = project.problem.?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", problem.code);
    const edit = problem.fix orelse return .{ .message = try t.allocator.dupe(u8, problem.message), .removed = null };
    try t.expectEqualStrings("", edit.text);
    return .{ .message = try t.allocator.dupe(u8, problem.message), .removed = try t.allocator.dupe(u8, main[edit.span.start..edit.span.end]) };
}

/// `bareMiss` of a program of the one module `main`: the message must be `message`, and the fix delete `removed`, or none when null.
fn expectBareMiss(main: []const u8, name: []const u8, call: []const u8, message: []const u8, removed: ?[]const u8) !void {
    const miss = try bareMiss(&.{.{ .path = "main.selka", .bytes = main }}, name, call);
    defer miss.deinit();
    try t.expectEqualStrings(message, miss.message);
    if (removed) |wanted| try t.expectEqualStrings(wanted, miss.removed.?) else try t.expect(miss.removed == null);
}

/// The names `alias.NAME(...)` a message offers as examples, in the order it writes them.
fn offeredNames(alias: []const u8, message: []const u8, found: *[8][]const u8) []const []const u8 {
    var buffer: [64]u8 = undefined;
    const marker = std.fmt.bufPrint(&buffer, "`{s}.", .{alias}) catch return found[0..0];
    var count: usize = 0;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, message, from, marker)) |at| {
        const start = at + marker.len;
        const end = std.mem.indexOfPos(u8, message, start, "(...)`") orelse break;
        found[count] = message[start..end];
        count += 1;
        from = end;
    }
    return found[0..count];
}

// MSG-B 2: `import sort` makes `sort` the module's name, so the builtin `sort(mut values)` was read as a call of the module and refused
// with "this module declares no `sort`", which says nothing of the import. The message names the module, the builtin it hides and what to
// write; the import is deleted by the repair when the call is the builtin's and the file names the module nowhere else.
test "a bare call of a builtin that an import hides says the import owns the name, and deletes the import when it is used for nothing else" {
    const head = "this module declares no `sort`; `sort` here names the imported module `sort`, which hides the builtin `sort`: write a function of the module";
    const tail = " (`selka reference --query sort` lists them), or remove `import sort` to reach the builtin";
    const call = "import sort\n\n\nfunc main() -> i64:\n    mut xs = [3, 1]\n    sort(mut xs, key=by_name)\n    return 0\n";
    const miss = try bareMiss(&.{.{ .path = "main.selka", .bytes = call }}, "sort", "sort(mut xs");
    defer miss.deinit();
    try t.expectEqualStrings("import sort\n", miss.removed.?);
    // The sentence is the frame above and one or two names of the module as it stands: each is a public function of the standard `sort`
    // that takes its first parameter `mut` when the module has such a function (the shape of the call written).
    try t.expect(std.mem.startsWith(u8, miss.message, head ++ ", such as `sort.sort_"));
    try t.expect(std.mem.endsWith(u8, miss.message, tail));
    var found: [8][]const u8 = undefined;
    const offered = offeredNames("sort", miss.message, &found);
    try t.expect(offered.len == 1 or offered.len == 2);
    const library = @import("standard_library.zig").source("sort.selka").?;
    for (offered) |name| {
        const declared = try std.fmt.allocPrint(t.allocator, "public func {s}", .{name});
        defer t.allocator.free(declared);
        const at = std.mem.indexOf(u8, library, declared) orelse return error.TestUnexpectedResult;
        const line = library[at..std.mem.indexOfScalarPos(u8, library, at, '\n').?];
        try t.expect(std.mem.indexOf(u8, line, "(mut ") != null);
    }
    try expectBareMiss("import strings\nimport sort  # the order\n\n\nfunc main() -> i64:\n    mut xs = [3, 1]\n    sort(mut xs)\n    return 0\n", "sort", "sort(mut xs", miss.message, "import sort  # the order\n");
    // The module is used by a qualifier elsewhere, or the call is not the builtin's form: the message stays, and the edit is the author's.
    try expectBareMiss("import sort\n\n\nfunc main() -> i64:\n    mut xs = [3, 1]\n    sort(mut xs)\n    return len(sort.sort_ints(xs))\n", "sort", "sort(mut xs", miss.message, null);
    try expectBareMiss("import sort\n\n\nfunc main() -> i64:\n    mut xs = [3, 1]\n    xs = sort(xs)\n    return 0\n", "sort", "sort(xs", miss.message, null);
    // An import under another name leaves the name to the builtin, and a name no import owns keeps the plain sentence.
    try expectBareMiss("import sort as srt\n\n\nfunc main() -> i64:\n    return srt.min_int([1])\n", "sort", "srt.min_int", "this module declares no `sort`", null);
    try expectBareMiss("import strings\n\n\nfunc main() -> i64:\n    return min_int([1])\n", "min_int", "min_int", "this module declares no `min_int`", null);
}

// The names the message offers come from the module by a rule, so it stays right as the module grows: the exported functions named
// `NAME_...`; those whose first parameter is `mut` (the shape of the call) when there are any, else all of them; at most two, the shorter
// name first and the same length in alphabetical order. A module of the project (no standard list to point at) is checked on its own terms.
test "the functions a hidden-builtin message offers are chosen by the shape of the call, the length of the name and no more than two" {
    const main = "import take\n\n\nfunc main() -> i64:\n    mut xs = [3, 1]\n    take(mut xs)\n    return 0\n";
    const frame = "this module declares no `take`; `take` here names the imported module `take`, which hides the builtin `take`: write a function of the module";
    const leave = ", or remove `import take` to reach the builtin";
    const in_place =
        \\public func take_first(mut values: int[]) -> int:
        \\    return 0
        \\
        \\
        \\public func take_all(mut values: int[], count: int) -> int:
        \\    return count
        \\
        \\
        \\public func take_two(mut values: int[], count: int) -> int:
        \\    return count
        \\
        \\
        \\public func take_n(values: int[]) -> int:
        \\    return 0
        \\
        \\
        \\func take_private(mut values: int[]) -> int:
        \\    return 0
        \\
        \\
        \\public func takes(mut values: int[]) -> int:
        \\    return 0
        \\
    ;
    const chosen = try bareMiss(&.{ .{ .path = "main.selka", .bytes = main }, .{ .path = "take.selka", .bytes = in_place } }, "take", "take(mut xs");
    defer chosen.deinit();
    try t.expectEqualStrings(frame ++ ", such as `take.take_all(...)` or `take.take_two(...)`" ++ leave, chosen.message);
    try t.expectEqualStrings("import take\n", chosen.removed.?);
    const by_value =
        \\public func take_first(values: int[]) -> int:
        \\    return 0
        \\
        \\
        \\public func take_n(values: int[]) -> int:
        \\    return 0
        \\
        \\
        \\public func take_ab(values: int[]) -> int:
        \\    return 0
        \\
    ;
    const copies = try bareMiss(&.{ .{ .path = "main.selka", .bytes = main }, .{ .path = "take.selka", .bytes = by_value } }, "take", "take(mut xs");
    defer copies.deinit();
    try t.expectEqualStrings(frame ++ ", such as `take.take_n(...)` or `take.take_ab(...)`" ++ leave, copies.message);
    const unrelated = "public func other(values: int[]) -> int:\n    return 0\n";
    const none = try bareMiss(&.{ .{ .path = "main.selka", .bytes = main }, .{ .path = "take.selka", .bytes = unrelated } }, "take", "take(mut xs");
    defer none.deinit();
    try t.expectEqualStrings(frame ++ ", as `take.NAME(...)`" ++ leave, none.message);
}
/// The `E_UNKNOWN_SYMBOL` message for `alias.name` in a main module that imports `import_line`, loaded with `hidden` as the local files a
/// standard module hides (`Options.standard.hidden`).
fn hiddenMiss(import_line: []const u8, hidden: []const []const u8, alias: []const u8, name: []const u8, kind: interfaces.Kind) ![]const u8 {
    const main = try std.fmt.allocPrint(t.allocator, "{s}\n\n\nfunc main() -> i64:\n    return 0\n", .{import_line});
    defer t.allocator.free(main);
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = main }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{ .standard = .{ .hidden = hidden } });
    var index = try interfaces.build(&project);
    const span = project.modules.items[0].header.declaration;
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = alias, .name = name, .kind = kind, .owner = null, .span = span }));
    return t.allocator.dupe(u8, project.problem.?.message);
}
// MSG-B 3: a project's `options.selka` loses to the standard module `options`; the refusal of a name only that file declares says whose
// `options` it is. A file that no standard module is named like, and a module the project does not hide, keep the plain sentence.
test "an unknown name of a standard module that a local file of the same name hides says the file is not used" {
    const hidden: []const []const u8 = &.{ "options.selka", "notes.selka" };
    const typed_name = try hiddenMiss("import options", hidden, "options", "Options", .type);
    defer t.allocator.free(typed_name);
    try t.expectEqualStrings("module `options` declares no `Options`; `options` here is the standard module, so your `options.selka` is not used: rename it", typed_name);
    const aliased = try hiddenMiss("import options as opts", hidden, "opts", "Options", .type);
    defer t.allocator.free(aliased);
    try t.expectEqualStrings("module `options` (imported as `opts`) declares no `Options`; `options` here is the standard module, so your `options.selka` is not used: rename it", aliased);
    const function = try hiddenMiss("import options", hidden, "options", "take", .function);
    defer t.allocator.free(function);
    try t.expect(std.mem.startsWith(u8, function, "module `options` declares no `take`; `options` here is the standard module, so your `options.selka` is not used: rename it"));
    const other = try hiddenMiss("import strings", hidden, "strings", "Options", .type);
    defer t.allocator.free(other);
    try t.expectEqualStrings("module `strings` declares no `Options`", other);
    const none = try hiddenMiss("import options", &.{}, "options", "Options", .type);
    defer t.allocator.free(none);
    try t.expectEqualStrings("module `options` declares no `Options`", none);
    const unrelated = try hiddenMiss("import options", &.{"notes.selka"}, "options", "Options", .type);
    defer t.allocator.free(unrelated);
    try t.expectEqualStrings("module `options` declares no `Options`", unrelated);
}
/// The `E_UNKNOWN_SYMBOL` message for `strings.NAME` in a main module that imports `strings` (B2), and whether the problem carries a
/// fix: it never does, since a nearest name is a guess and a fix is applied unasked.
fn nearestOf(name: []const u8) ![]const u8 {
    const main = try std.fmt.allocPrint(t.allocator, "import strings\n\n\nfunc main() -> i64:\n    return 0\n# strings.{s}\n", .{name});
    defer t.allocator.free(main);
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = main }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const end = main.len - 1;
    const span: source.Span = .{ .start = end - "strings.".len - name.len, .end = end };
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = "strings", .name = name, .kind = .function, .owner = null, .span = span }));
    const problem = project.problem.?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", problem.code);
    try t.expect(problem.fix == null);
    return t.allocator.dupe(u8, problem.message);
}
// spec-case: DIAG-ORACLE-1
test "an unknown name of a module lists its nearest names and carries no fix, since a nearest name is a guess (B2)" {
    const typo = try nearestOf("isdigit");
    defer t.allocator.free(typo);
    try t.expectEqualStrings("module `strings` declares no `isdigit`; did you mean `is_digit`?", typo);
    // Two names within two edits: both are listed and the author chooses.
    const two = try nearestOf("upr");
    defer t.allocator.free(two);
    try t.expectEqualStrings("module `strings` declares no `upr`; did you mean one of: `chr`, `upper`?", two);
    const short = try nearestOf("lne");
    defer t.allocator.free(short);
    try t.expectEqualStrings("module `strings` declares no `lne`; did you mean `lines`?", short);
}
// spec-case: DIAG-ORACLE-1
test "a name no function of the module sits within two edits of lists the names it contains or sits in (B2)" {
    const joined = try nearestOf("splitlines");
    defer t.allocator.free(joined);
    try t.expectEqualStrings("module `strings` declares no `splitlines`; did you mean one of: `lines`, `split`?", joined);
    const nothing = try nearestOf("tirm_start");
    defer t.allocator.free(nothing);
    try t.expectEqualStrings("module `strings` declares no `tirm_start`", nothing);
}
test "module privacy rejects direct private access wrong kinds and transitive import names" {
    const current_entry = try std.mem.replaceOwned(u8, t.allocator, entry, empty_effect_clause, "");
    defer t.allocator.free(current_entry);
    const current_units = try std.mem.replaceOwned(u8, t.allocator, units, empty_effect_clause, "");
    defer t.allocator.free(current_units);
    const cases = [_]struct { alias: ?[]const u8, name: []const u8, kind: interfaces.Kind, code: []const u8, from: usize = 0 }{
        .{ .alias = "units", .name = "hidden", .kind = .function, .code = "E_PRIVATE_SYMBOL" },
        .{ .alias = "units", .name = "Distance.raw", .kind = .function, .code = "E_PRIVATE_SYMBOL" },
        .{ .alias = "units", .name = "Distance", .kind = .function, .code = "E_SYMBOL_KIND" },
        .{ .alias = "other", .name = "Distance", .kind = .type, .code = "E_UNKNOWN_IMPORT" },
        .{ .alias = null, .name = "Distance", .kind = .type, .code = "E_UNKNOWN_SYMBOL" },
        .{ .alias = null, .name = "Distance.raw", .kind = .function, .code = "E_PRIVATE_FUNCTION", .from = 1 },
    };
    for (cases) |case| {
        var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = current_entry }, .{ .path = units_path, .bytes = current_units } } };
        var project = graph.Project.init(t.allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try interfaces.build(&project);
        try t.expectError(error.SourceError, index.resolve(.{ .from = case.from, .alias = case.alias, .name = case.name, .kind = case.kind, .owner = null, .span = project.modules.items[case.from].header.declaration }));
        try t.expectEqualStrings(case.code, project.problem.?.code);
        const message = try project.renderProblem(t.allocator);
        defer t.allocator.free(message);
        if (std.mem.eql(u8, case.code, "E_PRIVATE_SYMBOL")) try t.expect(std.mem.indexOf(u8, message, "units.selka:") != null);
    }
}

const scanner_module = "\n\nfunc helper() -> int:\n    return 7\n\n\npublic func scan() -> int:\n    return helper()\n";
/// Resolve `scanner.helper` from the entry module `entry` whose source is
/// `text`, beside `scanner.selka`, and answer the privacy problem code or null.
fn privateHelperProblem(module: []const u8, text: []const u8, extra: ?File) !?[]const u8 {
    const path = try std.fmt.allocPrint(t.allocator, "{s}.selka", .{module});
    defer t.allocator.free(path);
    const all = [_]File{ .{ .path = path, .bytes = text }, .{ .path = "scanner.selka", .bytes = scanner_module }, extra orelse .{ .path = "unused.selka", .bytes = "" } };
    var files: Files = .{ .entries = if (extra == null) all[0..2] else all[0..3] };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), module, .{});
    var index = try interfaces.build(&project);
    const from = project.names.get(if (extra == null) module else "scanner_test").?;
    _ = index.resolve(.{ .from = from, .alias = "scanner", .name = "helper", .kind = .function, .owner = null, .span = project.modules.items[from].header.declaration }) catch |err| {
        if (err != error.SourceError) return err;
        return project.problem.?.code;
    };
    return null;
}

// spec: TEST-PRIVATE-ACCESS-1
test "a module's test file resolves its private declarations and nothing else does" {
    const tester = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == 7\n";
    try t.expectEqual(@as(?[]const u8, null), try privateHelperProblem("scanner_test", tester, null));
    const other = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == 7\n";
    try t.expectEqualStrings("E_PRIVATE_SYMBOL", (try privateHelperProblem("parser_test", other, null)).?);
    // A `scanner_test` another module imports is a library, not a test file,
    // so it could hand the private helper on: it sees only the public surface.
    const importer = "import scanner_test\n\n\nfunc main() -> int:\n    return 0\n";
    try t.expectEqualStrings("E_PRIVATE_SYMBOL", (try privateHelperProblem("main", importer, .{ .path = "scanner_test.selka", .bytes = tester })).?);
}

/// The module `scanner_test` tests in a project loaded through the entry `entry_name` (source `text`) beside `scanner.selka` and
/// `scanner_test.selka`, named, or null.
fn testedThrough(entry_name: []const u8, text: []const u8, tester: []const u8) !?[]const u8 {
    const path = try std.fmt.allocPrint(t.allocator, "{s}.selka", .{entry_name});
    defer t.allocator.free(path);
    var files: Files = .{ .entries = &.{ .{ .path = path, .bytes = text }, .{ .path = "scanner.selka", .bytes = scanner_module }, .{ .path = "scanner_test.selka", .bytes = tester } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), entry_name, .{});
    var index = try interfaces.build(&project);
    const tested = index.testedModule(project.names.get("scanner_test").?) orelse return null;
    return if (std.mem.eql(u8, project.modules.items[tested].name, "scanner")) "scanner" else "another module";
}

// FX10: the check a directory test run's roots share enters through a generated entry that imports each root. That import only
// loads the test file: counting it refused the test file's call of a private helper that its own check accepts, which the
// checked-body store then hid on the next run, so the shared program flagged the helper private to its unit and the test was
// reported unsupported. A real importer still withdraws the access, and `testedModule` (which the checked-body keys fold) says so.
test "a test file loaded by a generated entry keeps its module's private declarations, and a real importer withdraws them" {
    const tester = "import scanner\n\n\npublic func test_helper() -> bool:\n    return scanner.helper() == 7\n";
    const run_entry = "import scanner_test as root_0\n\nfunc main() -> int:\n    return 0\n";
    try t.expectEqual(@as(?[]const u8, null), try privateHelperProblem("selka_directory_run", run_entry, .{ .path = "scanner_test.selka", .bytes = tester }));
    try t.expectEqual(@as(?[]const u8, null), try privateHelperProblem("selka_check_all", run_entry, .{ .path = "scanner_test.selka", .bytes = tester }));
    try t.expectEqualStrings("scanner", (try testedThrough("selka_directory_run", run_entry, tester)).?);
    try t.expectEqualStrings("scanner", (try testedThrough("selka_check_all", run_entry, tester)).?);
    const importer = "import scanner_test\n\n\nfunc main() -> int:\n    return 0\n";
    try t.expectEqualStrings("E_PRIVATE_SYMBOL", (try privateHelperProblem("main", importer, .{ .path = "scanner_test.selka", .bytes = tester })).?);
    try t.expectEqual(@as(?[]const u8, null), try testedThrough("main", importer, tester));
    // Only the generated name is exempt: a module merely ending in it is a real importer.
    try t.expectEqual(@as(?[]const u8, null), try testedThrough("my_selka_directory_run", importer, tester));
}

test "module grammar parses qualified variant match constructors and free calls" {
    const text =
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut x = units.Choice.a
        \\    mut y = units.helper()
        \\    match x:
        \\        case units.Choice.a:
        \\            return y
    ;
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = text },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public enum Choice:
        \\    a
        \\
        \\
        \\public func helper() -> i64:
        \\    return 1
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    const index = try interfaces.build(&project);
    const src = project.modules.items[0].src;
    try expectQualifiedSyntax(index.units[0].syntax, src);
}

fn mergedScenario(allocator: std.mem.Allocator) !void {
    // Keep the retired domain fixtures above for their original recognizers.
    const modern_units =
        \\public record Distance:
        \\    value: i64
        \\
        \\func raw(x: i64) -> Distance:
        \\    return Distance(value=x)
        \\
        \\public func make(x: i64) -> Distance:
        \\    return raw(x)
        \\
        \\func hidden() -> i64:
        \\    return 9
    ;
    const entry_without_effects = try std.mem.replaceOwned(u8, allocator, entry, empty_effect_clause, "");
    defer allocator.free(entry_without_effects);
    const modern_entry = try std.mem.replaceOwned(u8, allocator, entry_without_effects, "units.Distance.make", "units.make");
    defer allocator.free(modern_entry);
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = modern_entry }, .{ .path = units_path, .bytes = modern_units } } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try project_syntax.build(&index);
    try t.expectEqual(index.units[0].syntax.functions.len + index.units[1].syntax.functions.len, merged.syntax.functions.len);
    for (merged.syntax.functions, merged.function_modules) |function, module| {
        const at = merged.src.locate(function.name.start);
        try t.expectEqualStrings(project.modules.items[module].src.path, at.path);
        const range = merged.modules[module];
        try t.expect(@backingInt(function.body) >= range.statement_start and @backingInt(function.body) < range.statement_end);
    }
    for (merged.modules, index.units, 0..) |range, unit, module| {
        for (merged.syntax.nodes.items[range.node_start..range.node_end], unit.syntax.nodes.items) |node, original| {
            try t.expectEqualStrings(project.modules.items[module].src.text(original.span), merged.src.text(node.span));
            if (node.data == .call) for (node.data.call.arguments) |argument| try t.expect(@backingInt(argument) >= range.node_start and @backingInt(argument) < range.node_end);
        }
    }
    try t.expectEqualStrings("units.Distance", merged.src.text(merged.syntax.types.records[0].fields[0].ty));
    const original_span = index.units[1].syntax.functions[0].name;
    try t.expectEqualStrings("raw", project.modules.items[1].src.text(original_span));
    try t.expect(original_span.start < merged.syntax.functions[2].name.start);
}
test "module AST relocation retains source spelling namespace ownership and node references under allocation failure" {
    try mergedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), mergedScenario, .{});
}

fn checkedScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut x = units.make(12)
        \\    return units.number(x)
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public record Distance:
        \\    value: i64
        \\
        \\func raw(x: i64) -> Distance:
        \\    return Distance(value=x)
        \\
        \\public func make(x: i64) -> Distance:
        \\    return raw(x)
        \\
        \\public func number(x: Distance) -> i64:
        \\    return x.value
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 12), result.value);
}
test "a module import named like a builtin type leaves the type visible" {
    const main =
        \\import bytes
        \\
        \\record Chunk:
        \\    body: bytes
        \\
        \\
        \\func main() -> i64:
        \\    const chunk = Chunk(body=b"  x ")
        \\    return len(bytes.strip(chunk.body)) - 1
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = main }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}
test "cross module domain factories type check and execute with allocation failure cleanup" {
    try checkedScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), checkedScenario, .{});
}

fn rejectChecked(main: []const u8, dependency: []const u8, code: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = units_path, .bytes = dependency } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    var index = interfaces.build(&project) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    var found: ?usize = null;
    for (compilation.diagnostics.items.items, 0..) |item, diagnostic_index| {
        if (std.mem.eql(u8, code, item.code)) found = diagnostic_index;
    }
    try t.expect(found != null);
    const rendered = try compilation.diagnostics.items.items[found.?].render(t.allocator, compilation.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, ".selka:") != null);
}
test "shared record types cross module boundaries and hidden names do not shadow caller locals" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut hidden = 7
        \\    mut x = units.make(hidden)
        \\    return units.value(x)
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public record X:
        \\    number: i64
        \\
        \\
        \\func hidden() -> i64:
        \\    return 99
        \\
        \\
        \\public func make(n: i64) -> X:
        \\    return X(number=n)
        \\
        \\
        \\public func value(x: X) -> i64:
        \\    return x.number
        \\
        \\
        \\func main() -> i64:
        \\    return 88
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 7), result.value);
}

fn grouped(analysis: duplicates_module.Analysis, program: @import("typed.zig").Program, left: []const u8, right: []const u8) bool {
    for (analysis.groups) |group| {
        var found_left = false;
        var found_right = false;
        for (group.members) |id| {
            const name = program.functions[@backingInt(id)].name;
            found_left = found_left or std.mem.eql(u8, name, left);
            found_right = found_right or std.mem.eql(u8, name, right);
        }
        if (found_left and found_right) return true;
    }
    return false;
}
fn discoveryScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import left
        \\import right
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = "left.selka", .bytes =
        \\import shared as s
        \\
        \\
        \\record Box:
        \\    n: i64
        \\
        \\
        \\func pure(x: i64) -> i64:
        \\    return x * 2 + 3
        \\
        \\
        \\func nominal(x: Box) -> Box:
        \\    return x
        \\
        \\
        \\func helper(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\func wrapper(x: i64) -> i64:
        \\    return helper(x)
        \\
        \\
        \\func shared_use(x: s.Box) -> i64:
        \\    return s.number(x)
        },
        .{ .path = "right.selka", .bytes =
        \\import shared as q
        \\
        \\
        \\record Box:
        \\    n: i64
        \\
        \\
        \\func pure(value: i64) -> i64:
        \\    return value * 2 + 3
        \\
        \\
        \\func nominal(value: Box) -> Box:
        \\    return value
        \\
        \\
        \\func helper(value: i64) -> i64:
        \\    return value + 1
        \\
        \\
        \\func wrapper(value: i64) -> i64:
        \\    return helper(value)
        \\
        \\
        \\func shared_use(value: q.Box) -> i64:
        \\    return q.number(value)
        },
        .{ .path = "shared.selka", .bytes =
        \\
        \\
        \\public record Box:
        \\    n: i64
        \\
        \\
        \\public func number(x: Box) -> i64:
        \\    return x.n
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    var analysis = try duplicates_module.discover(allocator, compilation.program.?, .{ .min_nodes = 1, .approximate = true, .near_options = .{ .max_work = 10000 } });
    defer analysis.deinit();
    try t.expect(grouped(analysis, compilation.program.?, "left::pure", "right::pure"));
    try t.expect(grouped(analysis, compilation.program.?, "left::shared_use", "right::shared_use"));
    try t.expect(!grouped(analysis, compilation.program.?, "left::nominal", "right::nominal"));
    try t.expect(!grouped(analysis, compilation.program.?, "left::wrapper", "right::wrapper"));
    const text = try duplicates_module.render(allocator, analysis, compilation.program.?, compilation.src);
    defer allocator.free(text);
    for ([_][]const u8{ "left.selka:8:", "right.selka:8:", "left::pure", "right::pure", "approximate near-v3" }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "module duplicate discovery preserves nominal types and callees while normalizing shared import aliases" {
    try discoveryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), discoveryScenario, .{});
}

fn qualityScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import api
        \\
        \\
        \\func main() -> i64:
        \\    return api.used()
        },
        .{ .path = "api.selka", .bytes =
        \\
        \\
        \\public func used() -> i64:
        \\    return 7
        \\
        \\
        \\public func unused() -> i64:
        \\    return helper()
        \\
        \\
        \\func helper() -> i64:
        \\    return 2
        \\
        \\
        \\func isolated() -> i64:
        \\    return 3
        \\
        \\
        \\func cycle_a() -> i64:
        \\    return cycle_b()
        \\
        \\
        \\func cycle_b() -> i64:
        \\    return cycle_a()
        \\
        \\
        \\public record D:
        \\    value: i64
        \\
        \\func raw(x: i64) -> D:
        \\    return D(value=x)
        \\
        \\public func make(x: i64) -> D:
        \\    return raw(x)
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    try t.expectEqual(@as(usize, 3), roots.len);
    const quality = @import("quality.zig");
    var analysis = try quality.analyzeWithExports(allocator, compilation.program.?, compilation.src, compilation.syntax, .{}, roots);
    defer analysis.deinit();
    for (compilation.program.?.functions, analysis.functions) |function, metrics| {
        const expected_main = std.mem.eql(u8, function.name, "main::main") or std.mem.eql(u8, function.name, "api::used");
        const expected_export = std.mem.eql(u8, function.name, "api::used") or std.mem.eql(u8, function.name, "api::unused") or std.mem.eql(u8, function.name, "api::make");
        const expected_api = expected_export or std.mem.eql(u8, function.name, "api::helper") or std.mem.eql(u8, function.name, "api::raw");
        try t.expectEqual(expected_main, metrics.reachable);
        try t.expectEqual(expected_export, metrics.exported);
        try t.expectEqual(expected_api, metrics.reachable_from_exports);
    }
    const text = try quality.render(allocator, analysis, compilation.program.?, compilation.src);
    defer allocator.free(text);
    for ([_][]const u8{
        "quality-modules-v1",
        "module-exported=true reachable-from-exports=true",
        "module-exported=false reachable-from-exports=true domain-private=false",
        "no call path from main or exported interfaces",
        "calls api::used at main.selka:",
        "not evidence of external callers",
    }) |part| try t.expect(std.mem.indexOf(u8, text, part) != null);
}
test "module quality reports distinguish main export and private helper reachability under allocation failure" {
    try qualityScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), qualityScenario, .{});
}

fn expectQualifiedSyntax(syntax: @import("ast.zig").Program, src: @import("source.zig").Source) !void {
    var calls: usize = 0;
    var variants: usize = 0;
    var matches: usize = 0;
    for (syntax.nodes.items) |node| switch (node.data) {
        .call => |call| {
            try t.expectEqualStrings("units.helper", src.text(call.name));
            calls += 1;
        },
        // A payload-free case reads as a field of its qualified enum until the checker rewrites it.
        .field => |field| {
            try t.expectEqualStrings("units.Choice", src.text(syntax.nodes.items[@backingInt(field.base)].data.name));
            try t.expectEqualStrings("a", src.text(field.name));
            variants += 1;
        },
        else => {},
    };
    for (syntax.statements.items) |statement| if (statement.data == .match) {
        try t.expectEqualStrings("units.Choice", src.text(statement.data.match.arms[0].ty));
        matches += 1;
    };
    try t.expectEqual(@as(usize, 1), calls);
    try t.expectEqual(@as(usize, 1), variants);
    try t.expectEqual(@as(usize, 1), matches);
}

test "AST relocation rejects dangling expression and statement identities" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const statements = index.units[0].syntax.statements.items;
    const saved = statements[0];
    statements[0].data = .{ .ret = @fromBackingInt(index.units[0].syntax.nodes.items.len) };
    try t.expectError(error.InvalidNodeId, project_syntax.build(&index));
    statements[0] = saved;
    @constCast(index.units[0].syntax.functions)[0].body = @fromBackingInt(statements.len);
    try t.expectError(error.InvalidStatementId, project_syntax.build(&index));
}
test "public type selection rejects private and unknown nominal types" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\
        \\
        \\record Hidden:
        \\    n: i64
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("main::Hidden"));
    try t.expectError(error.UnknownPublicValueType, compilation.publicValueType("main::Missing"));
}

test "schema rendering rejects an exported declaration missing its checked type" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\
        \\
        \\public record Visible:
        \\    n: i64
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    compilation.program.?.records = &.{};
    try t.expectError(error.InvalidCheckedType, @import("schema.zig").render(t.allocator, &compilation));
}

test "public schema renders normalized mutates metadata and callback contracts" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\
        \\
        \\public func touch(mut values: int[]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\public func apply(f: func(mut values: int[]) -> Unit) -> Unit:
        \\    _ = f
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    const schema = try @import("schema.zig").render(t.allocator, &compilation);
    defer t.allocator.free(schema);
    try t.expect(std.mem.indexOf(u8, schema, "\"name\":\"main::touch\"") != null);
    try t.expect(std.mem.indexOf(u8, schema, "\"mutates\":[0]") != null);
    try t.expect(std.mem.indexOf(u8, schema, "\"return_origin\":\"fresh\"") != null);
}

test "generic syntax module interfaces retain scoped type names without hiding private concrete types" {
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func f[T](x: T, y: FixedArray[Secret, 2]) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
    const text =
        \\
        \\
        \\public func echo[T: copy](x: FixedArray[T, 2]) -> FixedArray[T, 2]:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = text }} };
    var cache = @import("syntax_cache.zig").Cache.init(t.allocator, .{});
    defer cache.deinit();
    for (0..2) |_| {
        var project = graph.Project.init(t.allocator);
        defer project.deinit();
        try project.load(files.provider(), "main", .{});
        var index = try interfaces.buildWithCache(&project, &cache, null);
        const merged = try project_syntax.build(&index);
        const parameters = merged.syntax.functions[0].signature.type_parameters;
        try t.expectEqual(@as(usize, 1), parameters.len);
        try t.expectEqualStrings("copy", merged.src.text(parameters[0].requirements[0]));
    }
    try t.expectEqual(@as(usize, 1), cache.statistics.hits);
}

test "generic requirements checkGenericRequirements validates exported and uncalled private templates" {
    try reject(
        \\
        \\
        \\public func f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\func private_template[T: unknown](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

fn expectInterfaceEffects(allocator: std.mem.Allocator, entries: []const File) !void {
    var files: Files = .{ .entries = entries };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    try t.expectError(error.SourceError, interfaces.build(&project));
    try t.expectEqualStrings(effects_removed_code, project.problem.?.code);
}

/// Executable nominal counterpart of the original units domain fixture.
const current_checked_units =
    \\public record Distance:
    \\    value: i64
    \\func raw(x: i64) -> Distance:
    \\    return Distance(value=x)
    \\public func make(x: i64) -> Distance:
    \\    return raw(x)
    \\func hidden() -> i64:
    \\    return 9
;

fn rejectCheckedCurrent(main: []const u8, dependency: []const u8, code: []const u8) !void {
    if (std.mem.indexOf(u8, main, empty_effect_clause) != null or std.mem.indexOf(u8, dependency, empty_effect_clause) != null)
        try rejectChecked(main, dependency, effects_removed_code);
    const erased_main = try std.mem.replaceOwned(u8, t.allocator, main, empty_effect_clause, "");
    defer t.allocator.free(erased_main);
    const current_main = try std.mem.replaceOwned(u8, t.allocator, erased_main, "units.Distance.raw", "units.raw");
    defer t.allocator.free(current_main);
    const current_dependency = try std.mem.replaceOwned(u8, t.allocator, if (std.mem.eql(u8, dependency, units)) current_checked_units else dependency, empty_effect_clause, "");
    defer t.allocator.free(current_dependency);
    try rejectChecked(current_main, current_dependency, code);
}
fn namedConstraintIndexScenario(allocator: std.mem.Allocator) !void {
    const text =
        // migrate-embedded: skip original effects or named-constraint interface refusal witness
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
        \\
        \\
        \\public func total[P: Prices](policy: P, subtotal: int) -> int effects():
        \\    return P.price(policy, subtotal)
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = text }} };
    try expectInterfaceEffects(allocator, files.entries);
    const current_text = try std.mem.replaceOwned(u8, allocator, text, empty_effect_clause, "");
    defer allocator.free(current_text);
    files.entries = &.{.{ .path = "main.selka", .bytes = current_text }};
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const syntax = index.units[0].syntax;
    try t.expectEqual(@as(usize, 1), syntax.types.constraints.len);
    const constraint = syntax.types.constraints[0];
    const id = try index.resolve(.{ .from = 0, .alias = null, .name = "Prices", .kind = .constraint, .owner = null, .span = constraint.name });
    try t.expectEqual(interfaces.Kind.constraint, index.units[id.module].symbols.items[id.symbol].kind);
    const rendered = try index.render(allocator);
    defer allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "export constraint Prices") != null);
    const merged = try project_syntax.build(&index);
    try t.expectEqual(@as(usize, 1), merged.syntax.types.constraints.len);
    var sink: diagnostic_module.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    var names: module_names.Names = .{ .index = &index, .src = merged.src };
    const resolved = try names.constraintIdentity(.{ .alias = null, .name = merged.syntax.types.constraints[0].name }, &sink);
    try t.expectEqual(@as(usize, 0), resolved.module);
}

fn namedConstraintImportScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{
        .entries = &.{
            .{
                .path = "main.selka",
                .bytes =
                // migrate-embedded: skip intentional syntax/interface constraint-identity fixture
                \\import contracts
                \\
                \\
                \\public func total[P: contracts.Prices](policy: P, subtotal: int) -> int effects():
                \\    return P.price(policy, subtotal)
            },
            .{
                .path = contracts_module,
                .bytes =
                // migrate-embedded: skip intentional syntax/interface constraint-identity fixture
                \\
                \\
                \\public constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
            },
        },
    };
    try expectInterfaceEffects(allocator, files.entries);
    var modern_entries: [2]File = undefined;
    var initialized: usize = 0;
    defer for (modern_entries[0..initialized]) |file| allocator.free(file.bytes);
    for (files.entries, 0..) |file, i| {
        modern_entries[i] = .{ .path = file.path, .bytes = try std.mem.replaceOwned(u8, allocator, file.bytes, empty_effect_clause, "") };
        initialized += 1;
    }
    files.entries = &modern_entries;
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const bound = index.units[0].syntax.functions[0].signature.type_parameters[0].named_requirements[0];
    const identity = try index.resolve(.{ .from = 0, .alias = "contracts", .name = "Prices", .kind = .constraint, .owner = null, .span = bound.name });
    try t.expectEqual(@as(usize, 1), identity.module);
    const rendered = try index.render(allocator);
    defer allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "export constraint Prices") != null);
}

// spec: NAMED-CONSTRAINT-MODULE-7
test "named constraints resolve imported exported constraints" {
    try namedConstraintImportScenario(t.allocator);
}

// spec: NAMED-CONSTRAINT-MODULE-1
test "named constraints index export render and accept function bounds" {
    try namedConstraintIndexScenario(t.allocator);
}

// spec: NAMED-CONSTRAINT-MODULE-2
test "named constraints reject nominal bounds and wrong kinds" {
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public record Box[T: Prices]:
        \\    pass
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public enum Box[T: Prices]:
        \\    item(value: T)
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f(x: Prices) -> int:
        \\    return 0
    , "E_SYMBOL_KIND");
    try reject(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f(x: Prices[int]) -> int:
        \\    return 0
    , "E_SYMBOL_KIND");
}

// spec: NAMED-CONSTRAINT-MODULE-3
test "named constraints enforce private interface exposure and unknown names" {
    try rejectEffectErased(
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f[T: Prices](x: T) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
    try rejectEffectErased(
        \\
        \\
        \\public func f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try rejectEffectErased(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public constraint Prices[P] = copy + op(price(policy: P, secret: Secret) -> int effects())
    , "E_PRIVATE_INTERFACE");
}

// spec: NAMED-CONSTRAINT-MODULE-4
test "named constraints participate in duplicate declaration checks" {
    try reject(
        \\
        \\
        \\record Prices:
        \\    pass
        \\
        \\
        \\constraint Prices[P] = copy
    , "E_DUPLICATE_SYMBOL");
}

// spec: NAMED-CONSTRAINT-MODULE-6
test "named constraints reject subject shadowing declarations imports and builtins" {
    try rejectEffectErased(
        \\
        \\
        \\record P:
        \\    pass
        \\
        \\
        \\constraint Prices[P] = copy
        \\
        \\
        \\public func f(x: i64) -> int:
        \\    return 0
    , "E_SHADOWING");
    try rejectEffectErased(
        \\import units
        \\
        \\
        \\constraint Prices[units] = copy
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_SHADOWING");
    try rejectEffectErased(
        \\
        \\
        \\constraint Prices[int] = copy
    , "E_GENERIC_PARAMETER");
}

// spec: NAMED-CONSTRAINT-MODULE-5
test "named constraints constraintIdentity reports unmapped sources as internal errors" {
    const text =
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = text }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var sink: diagnostic_module.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    var names: module_names.Names = .{ .index = &index, .src = project.modules.items[0].src };
    const bound: ast.BoundReference = .{ .alias = null, .name = project.modules.items[0].header.declaration };
    try t.expectError(error.InternalError, names.constraintIdentity(bound, &sink));
}

fn expectNamedConstraintLocatedErrors() !void {
    try reject(
        \\
        \\
        \\public func f[T: unknown](x: T) -> T:
        \\    return x
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\
        \\
        \\constraint Prices[P] = field(tag: P)
    , "E_GENERIC_REQUIREMENT");
}

test "named constraints resolveConstraint and checkConstraint report located errors" {
    try expectNamedConstraintLocatedErrors();
}

fn acceptNamedConstraintModule(main: []const u8, contracts: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = contracts_module, .bytes = contracts } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

fn rejectNamedConstraintModule(main: []const u8, contracts: []const u8, code: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = contracts_module, .bytes = contracts } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    project.load(files.provider(), "main", .{}) catch |err| {
        try t.expectEqual(error.SourceError, err);
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    try t.expectError(error.SourceError, interfaces.build(&project));
    try t.expectEqualStrings(code, project.problem.?.code);
    const message = try project.renderProblem(t.allocator);
    defer t.allocator.free(message);
}

// spec-case: NAMED-CONSTRAINT-MODULE-7
test "named constraints accept an imported exported bound when the defining module has more declarations" {
    try acceptNamedConstraintModule(
        \\import contracts
        \\
        \\
        \\public func f[T: copy](x: T) -> T:
        \\    return x
        \\
        \\
        \\public func g[T: copy](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\record One:
        \\    a: int
        \\
        \\
        \\record Two:
        \\    a: int
        \\
        \\
        \\record Three:
        \\    a: int
        \\
        \\
        \\public record C:
        \\    pass
    );
}

// spec-case: NAMED-CONSTRAINT-MODULE-7
test "named constraints accept an imported exported bound when the defining module is smaller" {
    try acceptNamedConstraintModule(
        \\import contracts
        \\
        \\
        \\public func f[T: copy](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\record One:
        \\    a: int
        \\
        \\
        \\public record C:
        \\    pass
    );
}

// spec-case: NAMED-CONSTRAINT-MODULE-3
test "named constraints reject an unexported constraint imported from another module" {
    try rejectNamedConstraintModule(
        \\import contracts
        \\
        \\
        \\public func f[T: contracts.C](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        // migrate-embedded: skip original effects or named-constraint interface refusal witness
        \\
        \\
        \\constraint C[T] = copy
    , "E_PRIVATE_SYMBOL");
}

// spec-case: NAMED-CONSTRAINT-MODULE-3
test "named constraints reject a same-module unexported constraint exposed by an exported generic" {
    try reject(
        \\
        \\
        \\constraint C[T] = copy
        \\
        \\
        \\public func f[T: C](x: T) -> T:
        \\    return x
    , "E_PRIVATE_INTERFACE");
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-1
test "named constraints supply copy from an imported constraint to a structural field bound" {
    try acceptNamedConstraintModule(
        \\import contracts
        \\
        \\
        \\func value[T: copy + field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\public record C:
        \\    pass
    );
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-5
test "named constraints accept implied copy from equality with a structural field" {
    try acceptChecked(
        \\
        \\
        \\func value[T: equality + field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "");
}

// spec-case: NAMED-CONSTRAINT-SEMANTICS-7
test "named constraints reject a structural field bound without copy" {
    try reject(
        \\
        \\
        \\func value[T: field(value: int)](x: T) -> int:
        \\    return x.value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

test "generic body contracts respect module-local declaration and import scopes" {
    try rejectChecked(
        \\import units
        \\
        \\
        \\func f[T](x: T) -> T:
        \\    mut units = x
        \\    return units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , "", "E_SHADOWING");
    try acceptChecked(
        \\import units
        \\
        \\
        \\func f[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\record T:
        \\    pass
    );
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\func bad[T](x: T, y: T) -> T:
        \\    return x + y
    , "E_GENERIC_OPERATION");
}

test "generic calls preserve imported declaration identity and private boundaries" {
    const main =
        \\import units
        \\
        \\
        \\func identity[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    const dependency =
        \\
        \\
        \\public func identity[U](x: U) -> U:
        \\    return x
    ;
    try acceptChecked(main, dependency);
    // A domain member names its type arguments through its owner: `m.D.make[T](x)`.
    // migrate-embedded: skip retained legacy domain generic-call fixture
    const domain_main =
        \\import units
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.D.make[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    const modern_domain_main =
        \\import units
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.make[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    // migrate-embedded: skip retained legacy domain generic-call fixture
    const domain_dependency =
        \\
        \\
        \\public domain D: i64:
        \\    private func hidden[T](x: T) -> T:
        \\        return x
        \\
        \\    func make[U](x: U) -> U effects():
        \\        return D.hidden[U](x)
    ;
    const modern_domain_dependency =
        \\
        \\
        \\public record D:
        \\    value: i64
        \\
        \\func hidden[T](x: T) -> T:
        \\    return x
        \\
        \\public func make[U](x: U) -> U effects():
        \\    return hidden[U](x)
    ;
    try rejectChecked(domain_main, domain_dependency, "E_EFFECTS_REMOVED");
    const domain_without_effects = try std.mem.replaceOwned(u8, t.allocator, domain_dependency, empty_effect_clause, "");
    defer t.allocator.free(domain_without_effects);
    try rejectChecked(domain_main, domain_without_effects, "E_DOMAIN_REMOVED");
    try rejectChecked(modern_domain_main, modern_domain_dependency, "E_EFFECTS_REMOVED");
    const modern_dependency = try std.mem.replaceOwned(u8, t.allocator, modern_domain_dependency, empty_effect_clause, "");
    defer t.allocator.free(modern_dependency);
    try acceptChecked(modern_domain_main, modern_dependency);
    try rejectChecked(main,
        \\
        \\
        \\func identity[U](x: U) -> U:
        \\    return x
    , "E_PRIVATE_SYMBOL");
    const retired_integer_dependency =
        \\
        \\
        \\public func identity[U: integer](x: U) -> U effects():
        \\    return x
    ;
    try rejectChecked(main, retired_integer_dependency, "E_EFFECTS_REMOVED");
    const integer_dependency = try std.mem.replaceOwned(u8, t.allocator, retired_integer_dependency, empty_effect_clause, "");
    defer t.allocator.free(integer_dependency);
    try rejectChecked(main, integer_dependency, "E_GENERIC_ARGUMENT");
}

fn genericCallsScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import units
        \\
        \\
        \\func forward[T: integer](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public func identity[U](x: U) -> U:
        \\    _ = helper(1)
        \\    return x
        \\
        \\
        \\func helper(x: i64) -> i64:
        \\    return x + 1
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try project_syntax.build(&index);
    var names: @import("module_names.zig").Names = .{ .index = &index, .src = merged.src };
    var sink: diagnostic_module.Sink = .{ .allocator = project.arena.allocator() };
    try @import("generic_bodies.zig").checkWithNames(allocator, merged.src, merged.syntax, &sink, &names);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
test "generic calls module resolution and signature substitution release allocation failures" {
    try genericCallsScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericCallsScenario, .{});
}

test "generic calls requirement diagnostics link caller and imported declaration locations" {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import units
        \\
        \\
        \\func forward[T](x: T) -> T:
        \\    return units.identity[T](x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public func identity[U: integer](x: U) -> U:
        \\    return x
        },
    } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    const failure = compilation.diagnostics.items.items[0];
    try t.expectEqualStrings("E_GENERIC_ARGUMENT", failure.code);
    try t.expectEqualStrings("main.selka", compilation.src.locate(failure.span.start).path);
    try t.expectEqualStrings("T", compilation.src.text(failure.span));
    try t.expect(failure.related != null);
    try t.expectEqualStrings(units_path, compilation.src.locate(failure.related.?.span.start).path);
    try t.expectEqualStrings("U", compilation.src.text(failure.related.?.span));
}

fn acceptChecked(main: []const u8, dependency: []const u8) !void {
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = units_path, .bytes = dependency } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

fn genericExecutionScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes =
        \\import units
        \\
        \\
        \\func id[T: integer](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    _ = units.id[units.Box](units.Box(value=1))
        \\    mut x = 0
        \\    x = units.set[i64](x, 2)
        \\    mut values: FixedArray[i64, 1] = FixedArray[i64, 1]([x])
        \\    return units.run() + id[i64](units.head[i64](values))
        },
        .{ .path = units_path, .bytes =
        \\
        \\
        \\public record Box:
        \\    value: i64
        \\
        \\
        \\public func view[T](v: FixedArray[T, 1]) -> FixedArray[T, 1]:
        \\    return v
        \\
        \\
        \\public func head[T](v: FixedArray[T, 1]) -> T:
        \\    mut seen = view[T](v)
        \\    return seen[0]
        \\
        \\
        \\public func set[T](x: T, y: T) -> T:
        \\    _ = x
        \\    return y
        \\
        \\
        \\public func id[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\public func run() -> i64:
        \\    if id[bool](True):
        \\        return id[i64](5)
        \\    return 0
        },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    var nominal_instance = false;
    for (compilation.program.?.functions) |function| {
        if (!std.mem.eql(u8, function.name, "units::id[units::Box]")) continue;
        nominal_instance = true;
        try t.expectEqual(@as(usize, 1), function.type_arguments.len);
        try t.expectEqualStrings("units::Box", @import("typed.zig").typeName(function.type_arguments[0], compilation.program.?.records));
    }
    try t.expect(nominal_instance);
    const roots = try compilation.exportRoots(allocator);
    defer allocator.free(roots);
    try t.expectEqual(@as(usize, 1), roots.len);
    const schema = try @import("schema.zig").render(allocator, &compilation);
    defer allocator.free(schema);
    try t.expect(std.mem.indexOf(u8, schema, "units::id[") == null);
}
test "generic execution retains module identities and ordinary public schema roots" {
    try genericExecutionScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericExecutionScenario, .{});
}

// spec: EXPORT-PLACEMENT-1
test "exports after declarations retain interface validation and scope boundaries" {
    try acceptChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return units.value() - 42
    ,
        \\
        \\
        \\public func value() -> i64:
        \\    return 42
        \\
        \\
    );
    try reject(
        \\export Missing
    , "E_EXPORT_REMOVED");
    try reject(
        \\import units
        \\export units.value
        \\export units.value
    , "E_DUPLICATE_EXPORT");
    try reject(
        \\
        \\
        \\record Secret:
        \\    pass
        \\
        \\
        \\public func value(x: Secret) -> i64:
        \\    return 0
        \\
        \\
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\func value() -> i64:
        \\    export value
        \\    return 0
    , "E_SYNTAX");
    try reject(
        \\
        \\
        \\record Value:
        \\    export Value
    , "E_SYNTAX");
    try reject(
        \\
        \\
        \\func value() -> i64:
        \\    return 0
        \\
        \\
        \\import units
    , "E_SYNTAX");
}

fn scatteredExports(allocator: std.mem.Allocator) !void {
    const body =
        \\
        \\
        \\public record Value:
        \\    n: i64
        \\
        \\
        \\
        \\
        \\public func value() -> i64:
        \\    mut export = 42
        \\    return export
        \\
        \\
        \\public type Number = i64
        \\
        \\
        \\
        \\
        \\public const answer: Number = 42
        \\
        \\
        \\
        \\
        \\public func main() -> i64:
        \\    return value() - answer
        \\
        \\
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    const names = [_][]const u8{ "Value", "value", "Number", "answer", "main" };
    var index = try interfaces.build(&project);
    const unit = index.units[0];
    try t.expectEqual(names.len, unit.syntax.types.public_declarations.len);
    for (unit.syntax.types.public_declarations, names) |span, name| {
        try t.expectEqualStrings(name, project.modules.items[0].src.text(span));
    }
    var last: usize = 0;
    for (names) |name| {
        const id = unit.names.get(name).?;
        try t.expect(unit.symbols.items[id].exported);
        try t.expect(unit.symbols.items[id].span.start > last);
        last = unit.symbols.items[id].span.start;
    }
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try t.expectEqual(@as(i64, 0), (try native.run(&compilation)).value);
}

test "scattered exports preserve source order and spans through compilation and allocation failures" {
    try scatteredExports(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scatteredExports, .{});
}

test "late duplicate re-export diagnostics locate both original directives" {
    const body =
        \\import units
        \\export units.value
        \\
        \\
        \\export units.value
    ;
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = body }, .{ .path = units_path, .bytes = units } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(files.provider(), "main", .{}));
    const failure = project.problem.?;
    try t.expectEqualStrings("E_DUPLICATE_EXPORT", failure.code);
    try t.expectEqual(std.mem.lastIndexOf(u8, body, "units.value").?, failure.site.span.start);
    try t.expectEqual(std.mem.indexOf(u8, body, "units.value").?, failure.related.?.span.start);
}

const facade_units =
    \\
    \\
    \\public record Distance:
    \\    value: i64
    \\
    \\
    \\public func make(value: i64) -> Distance:
    \\    return Distance(value=value)
    \\
    \\
    \\public func metres(distance: Distance) -> i64:
    \\    return distance.value
    \\
    \\
    \\func secret() -> i64:
    \\    return 1
;
const facade_module =
    \\import shared.units
    \\export shared.units.Distance
    \\export shared.units.make
    \\export shared.units.metres
;
const facade_entry =
    \\import facade
    \\
    \\
    \\func main() -> i64:
    \\    mut distance: facade.Distance = facade.make(42)
    \\    return facade.metres(distance)
;
/// A facade module publishes imported declarations under its own local names,
/// and a third module names, constructs and calls them through the facade.
fn facadeScenario(allocator: std.mem.Allocator) !void {
    var files: Files = .{ .entries = &.{
        .{ .path = "main.selka", .bytes = facade_entry },
        .{ .path = "facade.selka", .bytes = facade_module },
        .{ .path = "shared/units.selka", .bytes = facade_units },
    } };
    var project = graph.Project.init(allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const units_id = project.names.get("shared.units").?;
    const facade_id = project.names.get("facade").?;
    const main_id = project.names.get("main").?;
    const site = project.modules.items[facade_id].header.declaration;
    const distance = try index.resolve(.{ .from = main_id, .alias = "facade", .name = distance_name, .kind = .type, .owner = null, .span = site });
    try t.expectEqual(units_id, distance.module);
    try t.expectEqualStrings(distance_name, index.units[distance.module].symbols.items[distance.symbol].name);
    const make = try index.resolve(.{ .from = main_id, .alias = "facade", .name = "make", .kind = .function, .owner = null, .span = site });
    try t.expectEqual(units_id, make.module);
    const text = try index.render(allocator);
    defer allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "module facade\n  export type Distance\n") != null);
    try t.expect(std.mem.indexOf(u8, text, "  export function make func(value:i64)->shared.units::Distance") != null);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 42), result.value);
}
// spec: REEXPORT-1
test "re-export facade publishes an imported declaration and a third module resolves through it" {
    try facadeScenario(t.allocator);
}
// spec: REEXPORT-2
test "re-export rejects an unimported qualifier an unknown target and a private declaration" {
    try rejectEffectErased(
        \\import units
        \\export missing.Distance
    , "E_UNKNOWN_EXPORT");
    try rejectEffectErased(
        \\import units
        \\export units.Missing
    , "E_UNKNOWN_EXPORT");
    try rejectEffectErased(
        \\import units
        \\export units.hidden
    , "E_PRIVATE_SYMBOL");
}

test "cross module bodies enforce private functions private types nominal identity and local shadowing" {
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return units.hidden()
    , units, "E_PRIVATE_SYMBOL");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    _ = units.Distance.raw(1)
        \\    return 0
    , units, "E_PRIVATE_SYMBOL");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut x = units.Hidden()
        \\    return 0
    ,
        \\
        \\
        \\record Hidden:
        \\    pass
    , "E_PRIVATE_SYMBOL");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\record X:
        \\    pass
        \\
        \\
        \\func main() -> i64:
        \\    return units.take(X())
    ,
        \\
        \\
        \\public record X:
        \\    pass
        \\
        \\
        \\public func take(x: X) -> i64 effects():
        \\    return 0
    , "E_TYPE");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut units = 1
        \\    return units
    , units, "E_SHADOWING");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return hidden()
    , units, "E_UNKNOWN_SYMBOL");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\func bad() -> i64:
        \\    return True
    , "E_TYPE");
    try rejectCheckedCurrent(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ,
        \\
        \\
        \\record Recursive:
        \\    next: Recursive
    , "E_RECURSIVE_RECORD");
}

test "generic calls concrete helpers retain imported identity and module privacy" {
    const caller =
        \\import units
        \\
        \\
        \\func helper(x: i64) -> bool:
        \\    return x == 0
        \\
        \\
        \\func f[T](x: T) -> i64:
        \\    _ = x
        \\    return units.helper(1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    try acceptChecked(caller,
        \\
        \\
        \\public func helper(x: i64) -> i64:
        \\    return leaf(x)
        \\
        \\
        \\func leaf(x: i64) -> i64:
        \\    return x + 1
    );
    try rejectChecked(caller,
        \\
        \\
        \\func helper(x: i64) -> i64:
        \\    return x
    , "E_PRIVATE_SYMBOL");
    const record_caller =
        \\import units
        \\
        \\
        \\func f[T](x: T) -> i64:
        \\    _ = x
        \\    return units.helper(1)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    try acceptChecked(record_caller,
        \\
        \\
        \\public record D:
        \\    value: i64
        \\
        \\public func helper(x: i64) -> i64:
        \\    return leaf(x)
        \\
        \\func leaf(x: i64) -> i64:
        \\    return x + 1
    );
}

test "interface closure includes record fields and enum table keys" {
    try reject(
        \\
        \\
        \\record Hidden:
        \\    value: i64
        \\
        \\
        \\public record D:
        \\    value: Hidden
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\
        \\
        \\enum Key:
        \\    a
        \\    b
        \\
        \\
        \\public record Table:
        \\    values: [Key]i64
    , "E_PRIVATE_INTERFACE");
    try reject(
        \\export units
        \\import units
    , "E_EXPORT_REMOVED");
}

// spec: ERGONOMIC-INTEGRATION-1
test "cross module effect and recoverable result obligations are enforced" {
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64 effects():
        \\    return units.allocate()
    ,
        \\
        \\
        \\public func allocate() -> i64 effects(managed_allocation):
        \\    mut values: i64[] = []
        \\    append(mut values, 1)
        \\    return values[0u64]
    , "E_EFFECTS_REMOVED");
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut pending = units.fallible()
        \\    return 0
    ,
        \\
        \\
        \\public result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\public func fallible() -> R effects():
        \\    return Ok(7)
    , "E_EFFECTS_REMOVED");
    try rejectChecked(
        "import units\n\nfunc main() -> int:\n    mut pending = units.fallible()\n    return 0\n",
        "public result R:\n    ok: int,\n    err: int\n\npublic func fallible() -> R:\n    return Ok(7)\n",
        "E_RESULT_UNHANDLED",
    );
}

// spec-case: EFFECTS-REMOVED-1
test "exported functions publish their inferred ceiling while explicit ceilings stay upper bounds" {
    // A pure export checks without an author ceiling and publishes effects=.
    const pure =
        \\
        \\
        \\public func value(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\func main() -> i64:
        \\    return value(41)
    ;
    var files_pure: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = pure }} };
    var project_pure = graph.Project.init(t.allocator);
    defer project_pure.deinit();
    try project_pure.load(files_pure.provider(), "main", .{});
    var index_pure = try interfaces.build(&project_pure);
    var compilation_pure = try project_compile_module.Compilation.init(&index_pure);
    try compilation_pure.check();
    index_pure.program = compilation_pure.program.?;
    const pure_contracts = try index_pure.renderContracts(t.allocator);
    defer t.allocator.free(pure_contracts);
    try t.expect(std.mem.indexOf(u8, pure_contracts, "\"name\":\"value\"") != null);
    try t.expect(std.mem.indexOf(u8, pure_contracts, "\"permissions\":\"mutates=;origin=fresh\"") != null);

    // An allocating export publishes the derived managed_allocation ceiling.
    const allocating =
        \\
        \\
        \\public func value() -> i64:
        \\    mut items: i64[] = []
        \\    append(mut items, 7)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
        \\    return value()
    ;
    var files_alloc: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = allocating }} };
    var project_alloc = graph.Project.init(t.allocator);
    defer project_alloc.deinit();
    try project_alloc.load(files_alloc.provider(), "main", .{});
    var index_alloc = try interfaces.build(&project_alloc);
    var compilation_alloc = try project_compile_module.Compilation.init(&index_alloc);
    try compilation_alloc.check();
    index_alloc.program = compilation_alloc.program.?;
    const alloc_contracts = try index_alloc.renderContracts(t.allocator);
    defer t.allocator.free(alloc_contracts);
    try t.expect(std.mem.indexOf(u8, alloc_contracts, "\"permissions\":\"mutates=;origin=fresh\"") != null);
    try t.expect(std.mem.indexOf(u8, alloc_contracts, "effects=managed_allocation,output") == null);

    // An exported generic template and a public domain operation also check and publish.
    const generic =
        \\
        \\
        \\public func identity[T](x: T) -> T:
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return identity[i64](41)
    ;
    var files_generic: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = generic }} };
    var project_generic = graph.Project.init(t.allocator);
    defer project_generic.deinit();
    try project_generic.load(files_generic.provider(), "main", .{});
    var index_generic = try interfaces.build(&project_generic);
    var compilation_generic = try project_compile_module.Compilation.init(&index_generic);
    try compilation_generic.check();
    index_generic.program = compilation_generic.program.?;
    const generic_contracts = try index_generic.renderContracts(t.allocator);
    defer t.allocator.free(generic_contracts);
    try t.expect(std.mem.indexOf(u8, generic_contracts, "\"name\":\"identity\"") != null);
    try t.expect(std.mem.indexOf(u8, generic_contracts, "\"permissions\":\"mutates=;origin=fresh\"") != null);

    const domain =
        \\
        \\
        \\public record Distance:
        \\    value: i64
        \\
        \\func raw(x: i64) -> Distance:
        \\    return Distance(value=x)
        \\
        \\public func make(x: i64) -> Distance:
        \\    return raw(x)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var files_domain: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = domain }} };
    var project_domain = graph.Project.init(t.allocator);
    defer project_domain.deinit();
    try project_domain.load(files_domain.provider(), "main", .{});
    var index_domain = try interfaces.build(&project_domain);
    var compilation_domain = try project_compile_module.Compilation.init(&index_domain);
    try compilation_domain.check();
    index_domain.program = compilation_domain.program.?;
    const domain_contracts = try index_domain.renderContracts(t.allocator);
    defer t.allocator.free(domain_contracts);
    try t.expect(std.mem.indexOf(u8, domain_contracts, "\"name\":\"make\"") != null);
    try t.expect(std.mem.indexOf(u8, domain_contracts, "\"permissions\":\"mutates=;origin=fresh\"") != null);

    // An explicit ceiling is still an opt-in narrowing and still rejects excess.
    const narrowed =
        // migrate-embedded: skip original effects or named-constraint interface refusal witness
        \\
        \\
        \\public func value() -> i64 effects():
        \\    mut items: i64[] = []
        \\    append(mut items, 7)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
        \\    return value()
    ;
    var files_narrow: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = narrowed }} };
    var project_narrow = graph.Project.init(t.allocator);
    defer project_narrow.deinit();
    try project_narrow.load(files_narrow.provider(), "main", .{});
    try t.expectError(error.SourceError, interfaces.build(&project_narrow));
    try t.expectEqualStrings("E_EFFECTS_REMOVED", project_narrow.problem.?.code);
}

/// Whether the named contract declaration carries the `@test` discovery marker.
fn contractTestMarker(allocator: std.mem.Allocator, contracts: []const u8, name: []const u8) !bool {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, contracts, .{});
    defer parsed.deinit();
    for (parsed.value.object.get("modules").?.array.items) |module| {
        for (module.object.get("declarations").?.array.items) |declaration| {
            if (!std.mem.eql(u8, declaration.object.get("name").?.string, name)) continue;
            const marker = declaration.object.get("test") orelse return false;
            return marker == .bool and marker.bool;
        }
    }
    return false;
}

// spec: ATTR-2
test "@test declarations publish a discovery marker in the contract manifest" {
    const body =
        \\
        \\
        \\public func helper(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\@test
        \\func takes_param(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\@test
        \\func checks() -> bool:
        \\    return True
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const contracts = try index.renderContracts(t.allocator);
    defer t.allocator.free(contracts);
    try t.expect(try contractTestMarker(t.allocator, contracts, "checks"));
    try t.expect(try contractTestMarker(t.allocator, contracts, "takes_param"));
    try t.expect(!try contractTestMarker(t.allocator, contracts, "helper"));
}

// spec: PUBLIC-DECL-1
test "a public declaration crosses the module boundary while an unmarked one stays private" {
    const dependency =
        \\
        \\
        \\public func answer() -> i64:
        \\    return 42
        \\
        \\
        \\public record Reading:
        \\    value: i64
        \\
        \\
        \\func hidden() -> i64:
        \\    return 7
    ;
    const main =
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    mut reading: units.Reading = units.Reading(value=units.answer())
        \\    return reading.value
    ;
    var files: Files = .{ .entries = &.{ .{ .path = "main.selka", .bytes = main }, .{ .path = units_path, .bytes = dependency } } };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    try rejectChecked(
        \\import units
        \\
        \\
        \\func main() -> i64:
        \\    return units.hidden()
    , dependency, "E_PRIVATE_SYMBOL");
}

/// The plan's incomplete-interface fixture: one complete declaration with a
/// declared ceiling and one whose body is still a typed hole. The hole makes the
/// body check fail, which is the state `selka list-interfaces` renders after it
/// ignores the body diagnostic.
const checked_ceiling_fixture =
    \\
    \\
    \\public func double(x: i64) -> i64:
    \\    return x * 2
    \\
    \\
    \\public func pure(x: i64) -> i64:
    \\    return x + 1
    \\
    \\
    \\func main() -> i64:
    \\    return double(2)
;
const hole_fixture =
    \\
    \\
    \\public func double(x: i64) -> i64 effects(managed_allocation):
    \\    return x * 2
    \\
    \\
    \\public func unfinished(x: i64) -> i64:
    \\    return todo[i64]()
    \\
    \\
    \\func main() -> i64:
    \\    return double(2)
;

// spec: INTERFACE-FACTS-1
test "an unchecked listing reports an unavailable inferred set and keeps a declared ceiling" {
    try rejectChecked(hole_fixture, "", "E_EFFECTS_REMOVED");
    const modern_fixture = try std.mem.replaceOwned(u8, t.allocator, hole_fixture, " effects(managed_allocation)", "");
    defer t.allocator.free(modern_fixture);
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = modern_fixture }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    // Body checking fails on the hole, which is what leaves the summary
    // unavailable; the interface gate restores the pre-check problem and lists
    // declarations anyway, exactly as `selka list-interfaces` does.
    const saved_problem = project.problem;
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_TYPED_HOLE", compilation.diagnostics.items.items[0].code);
    project.problem = saved_problem;
    try t.expect(compilation.program == null);
    index.program = compilation.program;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function double func(x:i64)->i64 analysis(declaration-only) tests(unavailable)") != null);
    try t.expect(std.mem.indexOf(u8, text, "export function unfinished func(x:i64)->i64 analysis(declaration-only) tests(unavailable)") != null);
    // The internal conservative mask is a bound, never a published inference.
    try t.expect(std.mem.indexOf(u8, text, "filesystem") == null);
}
// spec-case: INTERFACE-FACTS-1
test "a checked listing publishes the inferred set with no analysis clause" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = checked_ceiling_fixture }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function double func(x:i64)->i64 analysis(checked) tests(0)") != null);
    try t.expect(std.mem.indexOf(u8, text, "export function pure func(x:i64)->i64 analysis(checked) tests(0)") != null);
    try t.expect(std.mem.indexOf(u8, text, "analysis(checked)") != null);
    try t.expect(std.mem.indexOf(u8, text, "unavailable") == null);
}

// spec: INTERFACE-FACTS-2
test "an uninstantiated generic publishes an unavailable template summary" {
    const body =
        \\
        \\
        \\public func build[T](x: T) -> i64:
        \\    mut items: i64[] = []
        \\    append(mut items, 1)
        \\    return items[0]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    // The program checks; it simply holds no instantiation of the template, so
    // the checker's conservative mask is not an inferred fact for it.
    try compilation.check();
    index.program = compilation.program.?;
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "export function build func(x:$0)->i64 analysis(template)") != null);
    try t.expect(std.mem.indexOf(u8, text, "filesystem") == null);
    // The reachability index exists here, so no tests column is published and
    // none is claimed unavailable.
    try t.expect(std.mem.indexOf(u8, text, "tests(unavailable)") == null);
}

// spec: INTERFACE-CONTRACT-STATUS-1
test "the contract manifest states whether a checked program supplied inferred effects" {
    // Preserve the retired ceiling spelling; current manifests expose no effect fields.
    try reject(hole_fixture, "E_EFFECTS_REMOVED");
    const current_hole = try std.mem.replaceOwned(u8, t.allocator, hole_fixture, " effects(managed_allocation)", "");
    defer t.allocator.free(current_hole);
    var files_unchecked: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = current_hole }} };
    var project_unchecked = graph.Project.init(t.allocator);
    defer project_unchecked.deinit();
    try project_unchecked.load(files_unchecked.provider(), "main", .{});
    var index_unchecked = try interfaces.build(&project_unchecked);
    const unchecked = try index_unchecked.renderContracts(t.allocator);
    defer t.allocator.free(unchecked);
    // Declaration-only status survives; mutation permissions are not inferred effects.
    try t.expect(std.mem.indexOf(u8, unchecked, "\"analysis\":\"declaration-only\"") != null);
    try t.expect(std.mem.indexOf(u8, unchecked, "\"permissions\":\"mutates=;origin=fresh\"") != null);
    try t.expect(std.mem.indexOf(u8, unchecked, "filesystem") == null);

    var files_checked: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = checked_ceiling_fixture }} };
    var project_checked = graph.Project.init(t.allocator);
    defer project_checked.deinit();
    try project_checked.load(files_checked.provider(), "main", .{});
    var index_checked = try interfaces.build(&project_checked);
    var compilation_checked = try project_compile_module.Compilation.init(&index_checked);
    try compilation_checked.check();
    index_checked.program = compilation_checked.program.?;
    const checked = try index_checked.renderContracts(t.allocator);
    defer t.allocator.free(checked);
    // Checked manifests omit the declaration-only status.
    try t.expect(std.mem.indexOf(u8, checked, "\"analysis\"") == null);
    try t.expect(std.mem.indexOf(u8, checked, "\"permissions\":\"mutates=;origin=fresh\"") != null);
    for ([_][]const u8{ unchecked, checked }) |manifest| {
        try t.expect(std.mem.indexOf(u8, manifest, "\"version\":\"interface-contracts-v2\"") != null);
        try t.expect(std.mem.indexOf(u8, manifest, "\"name\":\"double\"") != null);
        try t.expect(std.mem.indexOf(u8, manifest, "\"effects\"") == null);
        try t.expect(std.mem.indexOf(u8, manifest, "\"inferred\"") == null);
        try t.expect(std.mem.indexOf(u8, manifest, "\"ceiling\"") == null);
    }
}

// spec: FACT-STATUS-1
test "the shared fact-status vocabulary spells the statuses the reference publishes" {
    try t.expectEqualStrings("checked", fact_status.name(.checked));
    try t.expectEqualStrings("template", fact_status.name(.template));
    try t.expectEqualStrings("declaration-only", fact_status.name(.declaration_only));
    try t.expectEqualStrings("declared", fact_status.name(.declared));
    try t.expectEqualStrings("lexical-only", fact_status.name(.lexical_only));
}

// spec-case: EFFECTS-REMOVED-1
test "a Filesystem, Clock or Environment parameter reaches the published ceiling" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\
        \\public func stamp(_fs: Filesystem, _clock: Clock, _env: Environment, _net: Network, _random: Entropy) -> int:
        \\    return 0
        \\
        \\func main() -> int:
        \\    return 0
        \\
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const listing = try index.render(t.allocator);
    defer t.allocator.free(listing);
    try t.expect(std.mem.indexOf(u8, listing, "ceiling(") == null);
}

// spec-case: NUM-LITERAL-4
test "constant hints inspect declaration policy without recording project problems" {
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes =
        \\public const VALUE: int = 42
        \\func ordinary() -> int:
        \\    return 1
        \\func main() -> int:
        \\    return VALUE
    }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const merged = try project_syntax.build(&index);
    const names: module_names.Names = .{ .index = &index, .src = merged.src };
    try t.expect(try names.isConstant(merged.syntax.functions[0].name));
    try t.expect(!try names.isConstant(merged.syntax.functions[1].name));
    try t.expect(!try names.isConstant(merged.syntax.functions[2].name));
    try t.expect(project.problem == null);
}

// spec-case: EFFECTS-REMOVED-1
test "retired effects disappear from interface listings contracts and public schemas" {
    const body = "public func update(mut values: int[]) -> int:\n    values[0] = 1\n    return values[0]\n\n" ++
        "public func apply(callback: func(int) -> int, value: int) -> int:\n    return callback(value)\n\n" ++
        "func main() -> int:\n    return 0\n";
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = body }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    var compilation = try project_compile_module.Compilation.init(&index);
    try compilation.check();
    index.program = compilation.program.?;
    const listing = try index.render(t.allocator);
    defer t.allocator.free(listing);
    const contracts = try index.renderContracts(t.allocator);
    defer t.allocator.free(contracts);
    try t.expect(std.mem.indexOf(u8, listing, "effects(") == null);
    try t.expect(std.mem.indexOf(u8, listing, "ceiling(") == null);
    try t.expect(std.mem.indexOf(u8, contracts, "effects=") == null);
    try t.expect(std.mem.indexOf(u8, contracts, "mutates=0") != null);
    const program = compilation.program.?;
    const functions = try t.allocator.alloc(@import("typed.zig").FunctionId, program.functions.len);
    defer t.allocator.free(functions);
    for (functions, 0..) |*function, number| function.* = @fromBackingInt(number);
    const schema = try @import("schema_graph.zig").render(t.allocator, &index, program, functions);
    defer t.allocator.free(schema);
    try t.expect(std.mem.indexOf(u8, schema, "\"effects\"") == null);
    try t.expect(std.mem.indexOf(u8, schema, "\"mutates\"") != null);
}

// spec-case: W10-LIST-BUILTIN-1
test "W10 the listing marks a builtin func of the standard library with its word" {
    const main_source = "import strings\nimport lists\n\npublic func shout(text: str) -> str:\n    return strings.upper(text)\n\n" ++
        "func main() -> int:\n    mut xs = [1]\n    return lists.pop(mut xs)\n";
    var files: Files = .{ .entries = &.{.{ .path = "main.selka", .bytes = main_source }} };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(files.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const text = try index.render(t.allocator);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "  export builtin function upper func(text:str)->str") != null);
    try t.expect(std.mem.indexOf(u8, text, "  export builtin function pop ") != null);
    try t.expect(std.mem.indexOf(u8, text, "  export function shout func(text:str)->str") != null);
    try t.expect(std.mem.indexOf(u8, text, "  export function find ") != null);
    try t.expect(std.mem.indexOf(u8, text, "  export builtin function strip ") != null);
}

/// What resolving the call of an enum case as a type left in the project: the problem's message, the text its fix replaces and the
/// text it writes there (both null: no fix).
const CaseMiss = struct {
    message: []const u8,
    replaced: ?[]const u8,
    written: ?[]const u8,

    fn deinit(self: CaseMiss) void {
        t.allocator.free(self.message);
        if (self.replaced) |text| t.allocator.free(text);
        if (self.written) |text| t.allocator.free(text);
    }
};

/// Resolve `name` as written in the call `alias.name(` (`name(` for a null alias) in `files[0]`, which must be refused as `E_UNKNOWN_SYMBOL`;
/// the caller releases what it returns.
fn caseMiss(files: []const File, alias: ?[]const u8, name: []const u8) !CaseMiss {
    var served: Files = .{ .entries = files };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(served.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const main = files[0].bytes;
    var buffer: [64]u8 = undefined;
    const spelled = if (alias) |qualifier| try std.fmt.bufPrint(&buffer, "{s}.{s}(", .{ qualifier, name }) else try std.fmt.bufPrint(&buffer, "{s}(", .{name});
    const at = std.mem.indexOf(u8, main, spelled).?;
    const span: source.Span = .{ .start = at, .end = at + spelled.len - 1 };
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = alias, .name = name, .kind = .type, .owner = null, .span = span }));
    const problem = project.problem.?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", problem.code);
    const message = try t.allocator.dupe(u8, problem.message);
    const edit = problem.fix orelse return .{ .message = message, .replaced = null, .written = null };
    return .{ .message = message, .replaced = try t.allocator.dupe(u8, main[edit.span.start..edit.span.end]), .written = try t.allocator.dupe(u8, edit.text) };
}

/// `caseMiss` for a bare name of the given kind, written as `call` in `files[0]`.
fn importedMiss(files: []const File, kind: interfaces.Kind, name: []const u8, call: []const u8) !CaseMiss {
    var served: Files = .{ .entries = files };
    var project = graph.Project.init(t.allocator);
    defer project.deinit();
    try project.load(served.provider(), "main", .{});
    var index = try interfaces.build(&project);
    const main = files[0].bytes;
    const at = std.mem.indexOf(u8, main, call).?;
    const span: source.Span = .{ .start = at, .end = at + name.len };
    try t.expectError(error.SourceError, index.resolve(.{ .from = 0, .alias = null, .name = name, .kind = kind, .owner = null, .span = span }));
    const problem = project.problem.?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", problem.code);
    const message = try t.allocator.dupe(u8, problem.message);
    const edit = problem.fix orelse return .{ .message = message, .replaced = null, .written = null };
    return .{ .message = message, .replaced = try t.allocator.dupe(u8, main[edit.span.start..edit.span.end]), .written = try t.allocator.dupe(u8, edit.text) };
}

// R5B-MSGS 1: a bare `new_bitout()` or `BitOut` after `import bitio` was refused as "this module declares no ..." three times in two rounds: the
// message never said the imported module has the name. When exactly one imported module declares it publicly, as the kind the position needs,
// the message names it and the spelling, and the fix writes the qualifier; with two or three it names them and chooses none.
test "a bare name that one imported module declares is answered with the module and its spelling, and a fix" {
    const bitio = "public record BitOut:\n    out: int[]\n\n\npublic const LIMIT: int = 7\n\n\npublic func new_bitout() -> BitOut:\n    return BitOut(out=[])\n\n\nfunc inner() -> int:\n    return 1\n";
    const main = "import bitio\n\n\nfunc keep(w: BitOut) -> int:\n    return LIMIT + inner()\n\n\nfunc main() -> int:\n    const w = new_bitout()\n    const v = BitOut(out=[])\n    return keep(w) + len(v.out)\n";
    const files = [_]File{ .{ .path = "main.selka", .bytes = main }, .{ .path = "bitio.selka", .bytes = bitio } };
    const function = try importedMiss(&files, .function, "new_bitout", "new_bitout()");
    defer function.deinit();
    try t.expectEqualStrings("this module declares no `new_bitout`; the imported module `bitio` declares it: write `bitio.new_bitout`", function.message);
    try t.expectEqualStrings("", function.replaced.?);
    try t.expectEqualStrings("bitio.", function.written.?);
    const record = try importedMiss(&files, .type, "BitOut", "BitOut)");
    defer record.deinit();
    try t.expectEqualStrings("this module declares no `BitOut`; the imported module `bitio` declares it: write `bitio.BitOut`", record.message);
    try t.expectEqualStrings("bitio.", record.written.?);
    // A record is constructed like a function is called: the call is resolved as a function, and the record is offered all the same.
    const constructed = try importedMiss(&files, .function, "BitOut", "BitOut(out=[])");
    defer constructed.deinit();
    try t.expectEqualStrings("this module declares no `BitOut`; the imported module `bitio` declares it: write `bitio.BitOut`", constructed.message);
    try t.expectEqualStrings("bitio.", constructed.written.?);
    const constant = try importedMiss(&files, .function, "LIMIT", "LIMIT +");
    defer constant.deinit();
    try t.expectEqualStrings("this module declares no `LIMIT`; the imported module `bitio` declares it: write `bitio.LIMIT`", constant.message);
    // A private declaration of the imported module is not offered, nor a name of another kind than the position needs.
    const private = try importedMiss(&files, .function, "inner", "inner()");
    defer private.deinit();
    try t.expectEqualStrings("this module declares no `inner`", private.message);
    try t.expect(private.written == null);
    const wrong_kind = try importedMiss(&files, .type, "new_bitout", "new_bitout()");
    defer wrong_kind.deinit();
    try t.expectEqualStrings("this module declares no `new_bitout`", wrong_kind.message);
    // The import's own alias is the qualifier written.
    const renamed = [_]File{ .{ .path = "main.selka", .bytes = "import bitio as bio\n\n\nfunc main() -> int:\n    const w = new_bitout()\n    return 0\n" }, files[1] };
    const aliased = try importedMiss(&renamed, .function, "new_bitout", "new_bitout()");
    defer aliased.deinit();
    try t.expectEqualStrings("this module declares no `new_bitout`; the imported module `bitio` (imported as `bio`) declares it: write `bio.new_bitout`", aliased.message);
    try t.expectEqualStrings("bio.", aliased.written.?);
}

test "a bare name that two imported modules declare names both and chooses neither" {
    const first = "public func put(n: int) -> int:\n    return n\n";
    const second = "public func put(n: int) -> int:\n    return n + 1\n";
    const main = "import first\nimport second\n\n\nfunc main() -> int:\n    return put(1)\n";
    const files = [_]File{ .{ .path = "main.selka", .bytes = main }, .{ .path = "first.selka", .bytes = first }, .{ .path = "second.selka", .bytes = second } };
    const both = try importedMiss(&files, .function, "put", "put(1)");
    defer both.deinit();
    try t.expectEqualStrings("this module declares no `put`; the imported modules `first` and `second` each declare it: write `first.put` or `second.put`, whichever you mean", both.message);
    try t.expect(both.written == null);
    // A module the file does not import is not named, and a module that declares it privately does not count.
    const lone = [_]File{ .{ .path = "main.selka", .bytes = "import first\n\n\nfunc main() -> int:\n    return put(1)\n" }, files[1], files[2] };
    const one = try importedMiss(&lone, .function, "put", "put(1)");
    defer one.deinit();
    try t.expectEqualStrings("this module declares no `put`; the imported module `first` declares it: write `first.put`", one.message);
    const caller = "import first\n\n\nfunc main() -> int:\n    return first.put(2) + other(1)\n";
    const unimported = [_]File{ .{ .path = "main.selka", .bytes = caller }, files[1], .{ .path = "other.selka", .bytes = "public func other(n: int) -> int:\n    return n\n" } };
    const absent = try importedMiss(&unimported, .function, "other", "other(1)");
    defer absent.deinit();
    try t.expectEqualStrings("this module declares no `other`", absent.message);
}

// R3-SMALLDIAG: an enum case named without its enum (`argparse.MissingValue` for `argparse.Error.MissingValue`) said only "declares no". When
// exactly one enum in reach has the case the message names `Enum.case` and the fix writes it; with two, or a private enum, nothing is guessed.
test "an enum case named without its enum is answered with Enum.case and a fix when exactly one enum in reach has it" {
    const shapes = "public enum Shape:\n    Circle(radius: int)\n    Square(side: int)\n\n\npublic enum Mark:\n    Circle(color: int)\n    Dot\n\n\nenum Hidden:\n    Secret(code: int)\n";
    const main = "import shapes\n\n\nenum Mode:\n    Fast\n    Slow(level: int)\n\n\nfunc main() -> i64:\n    const a = shapes.Square(side=3)\n" ++
        "    const b = Square(side=4)\n    const c = Slow(level=1)\n    const d = shapes.Circle(radius=1)\n    const e = shapes.Secret(code=1)\n    const f = Circle(radius=1)\n    return 0\n";
    const files = [_]File{ .{ .path = "main.selka", .bytes = main }, .{ .path = "shapes.selka", .bytes = shapes } };
    const note = "? A case of an enum is written with its enum";
    const qualified = try caseMiss(&files, "shapes", "Square");
    defer qualified.deinit();
    try t.expectEqualStrings("module `shapes` declares no `Square`; did you mean `shapes.Shape.Square`" ++ note, qualified.message);
    try t.expectEqualStrings("shapes.Square", qualified.replaced.?);
    try t.expectEqualStrings("shapes.Shape.Square", qualified.written.?);
    const imported = try caseMiss(&files, null, "Square");
    defer imported.deinit();
    try t.expectEqualStrings("this module declares no `Square`; did you mean `shapes.Shape.Square`" ++ note, imported.message);
    try t.expectEqualStrings("Square", imported.replaced.?);
    try t.expectEqualStrings("shapes.Shape.Square", imported.written.?);
    const own = try caseMiss(&files, null, "Slow");
    defer own.deinit();
    try t.expectEqualStrings("this module declares no `Slow`; did you mean `Mode.Slow`" ++ note, own.message);
    try t.expectEqualStrings("Mode.Slow", own.written.?);
    // Two enums of the module have `Circle`, and `Hidden` is not public: the plain message and no edit.
    const two = try caseMiss(&files, "shapes", "Circle");
    defer two.deinit();
    try t.expectEqualStrings("module `shapes` declares no `Circle`", two.message);
    try t.expect(two.replaced == null);
    const bare_two = try caseMiss(&files, null, "Circle");
    defer bare_two.deinit();
    try t.expectEqualStrings("this module declares no `Circle`", bare_two.message);
    const private = try caseMiss(&files, "shapes", "Secret");
    defer private.deinit();
    try t.expectEqualStrings("module `shapes` declares no `Secret`", private.message);
    try t.expect(private.written == null);
}
