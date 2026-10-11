//! Semantic template metadata checks names and requirements before executable specialization.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const templates = @import("nominal_templates.zig");
const fixture =
    \\record Pair[T, U]:
    \\    first: T
    \\    second: U
    \\
    \\
    \\enum Slot[T]:
    \\    none
    \\    some(value: T)
    \\
    \\
    \\record Row[T: equality]:
    \\    pair: Pair[T, bool]
    \\    slots: FixedArray[Slot[T], 2]
    \\
    \\
    \\resource File: filesystem
    \\
    \\
    \\record Owned[T]:
    \\    file: File
    \\    value: T
    \\
    \\
    \\result Answer[T]:
    \\    ok: T,
    \\    err: i64
    \\
    \\
    \\record Pending:
    \\    answer: Answer[i64]
    \\
    \\
    \\enum Tag[T]:
    \\    left
    \\    right
    \\
    \\
    \\domain Id: i64:
    \\    pass
    \\
    \\
    \\record Empty:
    \\    zero: FixedArray[File, 0]
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
fn collect(compilation: *language.Compilation, sink: *language.diagnostic.Sink) !templates.Index {
    try compilation.parse();
    return templates.collect(compilation.arena.allocator(), compilation.src, compilation.syntax.?, sink, null);
}
fn named(index: templates.Index, name: []const u8) !templates.Declaration {
    const id = index.names.get(name);
    try t.expect(id != null);
    return index.declarations.items[id.?];
}
fn metadataScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "templates.my", fixture);
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try collect(&compilation, &sink);
    const row = try named(index, "Row");
    const pair = row.fields[0].ty.?.application;
    try t.expectEqual(index.names.get("Pair").?, pair.declaration);
    try t.expectEqual(@as(usize, 0), pair.arguments[0].parameter);
    try t.expectEqual(@import("typed.zig").Type.bool, pair.arguments[1].builtin);
    const slots = row.fields[1].ty.?.array;
    try t.expectEqual(@as(?usize, 2), slots.length);
    try t.expectEqual(index.names.get("Slot").?, slots.element.application.declaration);
    try t.expectEqual(@as(usize, 0), slots.element.application.arguments[0].parameter);
    try t.expect(row.guarantees.contains(.copy));
    try t.expect(!row.guarantees.contains(.equality));
    for ([_][]const u8{ "File", "Owned", "Answer", "Pending" }) |name| try t.expect(!(try named(index, name)).guarantees.contains(.copy));
    for ([_][]const u8{ "Tag", "Id" }) |name| {
        const declaration = try named(index, name);
        try t.expect(declaration.guarantees.contains(.equality));
        try t.expect(!declaration.guarantees.contains(.integer));
    }
    try t.expect((try named(index, "Empty")).guarantees.contains(.copy));
}
fn rejectionScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "invalid.my",
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\resource File: filesystem
        \\
        \\
        \\record Bad:
        \\    value: Box[File]
    );
    defer compilation.deinit();
    compilation.check() catch |err| {
        if (err != error.SourceError) return err;
        try t.expectEqualStrings("E_GENERIC_REQUIREMENT", compilation.diagnostics.items[0].code);
        try t.expect(compilation.program == null);
        return;
    };
    return error.TestUnexpectedResult;
}
fn separateSinkScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "allocators.my",
        \\record Box[T]:
        \\    value: T
    );
    defer compilation.deinit();
    try compilation.parse();
    var sink: language.diagnostic.Sink = .{ .allocator = allocator };
    defer sink.items.deinit(allocator);
    const catalog = try @import("records.zig").collectWithNames(compilation.arena.allocator(), compilation.src, compilation.syntax.?, &sink, null);
    try t.expectEqual(@as(usize, 3), catalog.records.len);
    try t.expect(catalog.templates.names.contains("Box"));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
// spec: NOMINAL-TEMPLATE-CHECK-1
test "nominal template collect and expression preserve identity and guarantees across allocation failures" {
    try metadataScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), metadataScenario, .{});
    try rejectionScenario(t.allocator);
    try t.checkAllAllocationFailures(stable.allocator(), rejectionScenario, .{});
    try separateSinkScenario(t.allocator);
    try t.checkAllAllocationFailures(stable.allocator(), separateSinkScenario, .{});
}
fn reject(text: []const u8, code: []const u8, token: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "bad-template.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diagnostic = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, diagnostic.code);
    try t.expectEqualStrings(token, compilation.src.text(diagnostic.span));
    try t.expect(compilation.program == null);
}
test "unused nominal template fields reject unknown names duplicate members and invalid result schemas" {
    try reject(
        \\record Box[T]:
        \\    value: Missing
    , "E_UNKNOWN_TYPE", "Missing");
    try reject(
        \\record Box[T]:
        \\    value: T
        \\    value: i64
    , "E_DUPLICATE_FIELD", "value");
    // An enum or union suite cannot be empty, so E_EMPTY_VARIANTS has no source form.
    try reject(
        \\enum Slot[T]:
        \\    some(value: T)
        \\    some(value: i64)
    , "E_DUPLICATE_VARIANT", "some");
    try reject(
        \\result Answer[T]:
        \\    yes: T,
        \\    no: i64
    , "E_RESULT_SCHEMA", "Answer");
    try reject(
        \\result Answer[T]:
        \\    ok: T,
        \\    err
    , "E_RESULT_SCHEMA", "err");
    try reject(
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\domain Box: i64:
        \\    pass
    , "E_DUPLICATE_TYPE", "Box");
}
test "nominal template applications check arity and constructor kinds inside unused declarations" {
    try reject(
        \\record Pair[T, U]:
        \\    a: T
        \\    b: U
        \\
        \\
        \\record Bad[V]:
        \\    x: Pair[V]
    , "E_GENERIC_ARITY", "Pair[V]");
    try reject(
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\record Bad:
        \\    value: Box
    , "E_GENERIC_ARITY", "Box");
    try reject(
        \\record Plain:
        \\    pass
        \\
        \\
        \\record Bad[T]:
        \\    value: Plain[T]
    , "E_GENERIC_ARITY", "Plain[T]");
    try reject(
        \\record Bad[T]:
        \\    value: T[i64]
    , "E_TYPE_APPLICATION", "T");
    try reject(
        \\record Bad[T]:
        \\    value: FixedArray[Missing[T], 2]
    , "E_UNKNOWN_TYPE", "Missing");
}
test "nominal template requirements reject insufficient symbolic promises and concrete operations" {
    const prefix =
        \\record Key[T: equality]:
        \\    value: T
        \\
        \\
        \\record Number[T: integer]:
        \\    value: T
        \\
        \\
        \\
    ;
    try reject(prefix ++
        \\record Bad[T]:
        \\    value: Key[T]
    , "E_GENERIC_REQUIREMENT", "T");
    try reject(prefix ++
        \\record Bad[T: equality]:
        \\    value: Number[T]
    , "E_GENERIC_REQUIREMENT", "T");
    try reject(prefix ++
        \\record Bad[T]:
        \\    value: Number[bool]
    , "E_GENERIC_REQUIREMENT", "bool");
    try reject(prefix ++
        \\domain Id: i64:
        \\    pass
        \\
        \\
        \\record Bad[T]:
        \\    value: Number[Id]
    , "E_GENERIC_REQUIREMENT", "Id");
    try reject(prefix ++
        \\record Bad[T]:
        \\    value: Key[FixedArray[T, 0]]
    , "E_GENERIC_REQUIREMENT", "FixedArray[T, 0]");
    try reject(prefix ++
        \\record Bad[T]:
        \\    value: Key[Key[i64]]
    , "E_GENERIC_REQUIREMENT", "Key[i64]");
    var repaired = try language.Compilation.init(t.allocator, "repaired.my", prefix ++
        \\record Good[T: integer]:
        \\    key: Key[T]
        \\    number: Number[T]
        \\    flag: Key[bool]
    );
    defer repaired.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = repaired.arena.allocator() };
    const index = try collect(&repaired, &sink);
    try t.expect((try named(index, "Good")).guarantees.contains(.copy));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
test "nominal template requirements preserve transitive owner and pending result obligations" {
    const prefix =
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\resource File: filesystem
        \\
        \\
        \\
    ;
    try reject(prefix ++
        \\record Bad:
        \\    value: Box[File]
    , "E_GENERIC_REQUIREMENT", "File");
    try reject(prefix ++
        \\record Bad:
        \\    value: Box[Outer]
        \\
        \\
        \\record Outer:
        \\    inner: Inner
        \\
        \\
        \\record Inner:
        \\    file: File
    , "E_GENERIC_REQUIREMENT", "Outer");
    try reject(prefix ++
        \\result Answer:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\record Pending:
        \\    answer: Answer
        \\
        \\
        \\record Bad:
        \\    value: Box[FixedArray[Pending, 1]]
    , "E_GENERIC_REQUIREMENT", "FixedArray[Pending, 1]");
    try reject(prefix ++
        \\record Owner[T]:
        \\    file: File
        \\    value: T
        \\
        \\
        \\record Bad:
        \\    value: Box[Owner[i64]]
    , "E_GENERIC_REQUIREMENT", "Owner[i64]");
    try reject(prefix ++
        \\record Bad:
        \\    value: Box[Box[File]]
    , "E_GENERIC_REQUIREMENT", "File");
}
test "nominal template arrays validate lengths keys and symbolic enum table boundaries" {
    try reject(
        \\record Box[T]:
        \\    value: FixedArray[T, 2u8]
    , "E_ARRAY_LENGTH", "2u8");
    try reject(
        \\enum Key:
        \\    one
        \\    two
        \\
        \\
        \\record Box[T]:
        \\    value: [Key]T
    , "E_GENERIC_ARRAY_KEY", "[Key]T");
    try reject(
        \\record Key:
        \\    pass
        \\
        \\
        \\record Box[T]:
        \\    value: [Key]i64
    , "E_TABLE_KEY", "Key");
    try reject(
        \\enum Key[T: integer]:
        \\    one
        \\    two
        \\
        \\
        \\record Box[T]:
        \\    value: [Key[bool]]i64
    , "E_GENERIC_REQUIREMENT", "bool");
    var compilation = try language.Compilation.init(t.allocator, "valid.my",
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\resource File: filesystem
        \\
        \\
        \\enum Key:
        \\    one
        \\    two
        \\
        \\
        \\enum Tag[T]:
        \\    first
        \\    second
        \\
        \\
        \\record Valid[U: integer]:
        \\    empty: Box[FixedArray[File, 0]]
        \\    table: [Key]Box[i64]
        \\    tags: [Tag[i64]]bool
        \\    pair: Box[FixedArray[U, 2]]
    );
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try collect(&compilation, &sink);
    try t.expect((try named(index, "Valid")).guarantees.contains(.copy));
}
test "nominal guarantee propagation handles long reverse ordered declaration chains" {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    try text.writer.writeAll(
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\resource File: filesystem
        \\
        \\
        \\
    );
    for (0..1200) |i| try text.writer.print("record Link{d}:\n    next: Link{d}\n\n\n", .{ i, i + 1 });
    try text.writer.writeAll(
        \\record Link1200:
        \\    file: File
        \\
        \\
        \\record Bad:
        \\    value: Box[Link0]
    );
    try reject(text.written(), "E_GENERIC_REQUIREMENT", "Link0");
}

/// A chain of `levels` aliases, each a pair of the next, whose first name
/// expands to about 2^levels visits, used by one field.
fn aliasChain(allocator: std.mem.Allocator, levels: usize) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    try text.writer.writeAll("record Pair[A, B]:\n    first: A\n    second: B\n\n\n");
    for (0..levels) |level| try text.writer.print("type T{d} = Pair[T{d}, T{d}]\n\n\n", .{ level, level + 1, level + 1 });
    try text.writer.print("type T{d} = i64\n\n\nrecord Holder:\n    value: T0\n", .{levels});
    return text.toOwnedSlice();
}
// spec: NOMINAL-TEMPLATE-BUDGET-1
test "nominal expression checking bounds each top-level expression without issuing executable type IDs" {
    var compilation = try language.Compilation.init(t.allocator, "budget.my",
        \\record Box[T]:
        \\    value: T
    );
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    var index = try collect(&compilation, &sink);
    const declaration = try named(index, "Box");
    const span = compilation.syntax.?.types.records[0].fields[0].ty;
    // Every top-level expression starts a fresh budget: resolving the same
    // field more times than one expression may visit is never refused.
    for (0..100001) |_| try t.expectEqual(@as(usize, 0), (try index.expression(span, declaration.parameters)).parameter);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
    // One expression that expands past the budget is refused at its own spelling.
    const text = try aliasChain(t.allocator, 17);
    defer t.allocator.free(text);
    var chain = try language.Compilation.init(t.allocator, "chain.my", text);
    defer chain.deinit();
    var chain_sink: language.diagnostic.Sink = .{ .allocator = chain.arena.allocator() };
    try t.expectError(error.SourceError, collect(&chain, &chain_sink));
    const problem = chain_sink.items.items[0];
    try t.expectEqualStrings("E_GENERIC_LIMIT", problem.code);
    try t.expectEqualStrings("T0", chain.src.text(problem.span));
    try t.expect(std.mem.indexOf(u8, problem.message, "100000 visits") != null);
}
const Modules = struct {
    strict: bool = false,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *Modules = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\import left as l
            \\import right as r
            \\
            \\
            \\record Holder[T]:
            \\    a: l.Box[T]
            \\    b: r.Box[T]
            \\    c: l.Box[T]
            \\
            \\
            \\func main() -> i64:
            \\    return 0
        );
        if (std.mem.eql(u8, path, "left.my")) return allocator.dupe(u8, if (self.strict)
            \\
            \\
            \\public record Box[U: equality]:
            \\    value: U
        else
            \\
            \\
            \\public record Box[U]:
            \\    value: U
        );
        if (std.mem.eql(u8, path, "right.my")) return allocator.dupe(u8,
            \\
            \\
            \\public record Box[U]:
            \\    value: U
        );
        return error.NotFound;
    }
};
test "nominal metadata preserves distinct imported template identities and related requirement sites" {
    for ([_]bool{ false, true }) |strict| {
        var files: Modules = .{ .strict = strict };
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = &files, .read = Modules.read }, "main", .{});
        var interfaces = try language.interfaces.build(&project);
        const merged = try @import("project_syntax.zig").build(&interfaces);
        var names: @import("module_names.zig").Names = .{ .index = &interfaces, .src = merged.src };
        var sink: language.diagnostic.Sink = .{ .allocator = project.arena.allocator() };
        const result = templates.collect(project.arena.allocator(), merged.src, merged.syntax, &sink, &names);
        if (strict) {
            try t.expectError(error.SourceError, result);
            const problem = sink.items.items[0];
            try t.expectEqualStrings("E_GENERIC_REQUIREMENT", problem.code);
            const primary = try merged.src.originalSpan(problem.span);
            const related = try merged.src.originalSpan(problem.related.?.span);
            try t.expectEqualStrings("main", project.modules.items[primary.input].name);
            try t.expectEqualStrings("left", project.modules.items[related.input].name);
        } else {
            const index = try result;
            const holder = try named(index, "main::Holder");
            const left = holder.fields[0].ty.?.application.declaration;
            const right = holder.fields[1].ty.?.application.declaration;
            try t.expect(left != right);
            try t.expectEqual(left, holder.fields[2].ty.?.application.declaration);
            try t.expectEqual(index.names.get("left::Box").?, left);
            try t.expectEqual(index.names.get("right::Box").?, right);
        }
    }
}

// spec-case: NOMINAL-INSTANCE-1
test "synthetic enum payload identity preserves standalone display and source visibility" {
    var compilation = try language.Compilation.init(t.allocator, "standalone.my",
        \\enum Packet:
        \\    data(value: i64)
        \\    none
        \\
        \\func main() -> i64:
        \\    match Packet.data(value=42):
        \\        case Packet.data(value=n):
        \\            return n
        \\        case _:
        \\            return 0
    );
    defer compilation.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    const index = try collect(&compilation, &sink);
    var found = false;
    for (index.declarations.items, 0..) |declaration, id| {
        if (!index.isSynthetic(id)) continue;
        if (declaration.builtin_name) |name| {
            if (std.mem.eql(u8, name, "Packet.data")) found = true;
        }
    }
    try t.expect(found);
    try t.expect(!index.names.contains("Packet.data"));
    try compilation.check();
    try t.expect(hasRecordName(compilation.program.?.records, "Packet.data"));
}

fn hasRecordName(records: []const language.typed.Record, name: []const u8) bool {
    for (records) |record| if (std.mem.eql(u8, record.name, name)) return true;
    return false;
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "nominal borrowed view prelude preserves explicit source aliases" {
    var compilation = try language.Compilation.init(t.allocator, "aliases.my",
        \\type TextView = int
        \\type ByteView = int
        \\func main() -> int:
        \\    const text: TextView = 4
        \\    const data: ByteView = 3
        \\    return text + data
    );
    defer compilation.deinit();
    try compilation.check();
}
