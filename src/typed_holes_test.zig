//! Holes are explicit typed obligations, never executable placeholders.
const std = @import("std");
const t = std.testing;
const diagnostic = @import("diagnostic.zig");
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const source = @import("source.zig");

const two_holes =
    \\func first() -> i64:
    \\    return todo[i64]()
    \\
    \\
    \\func second[T](x: T) -> T:
    \\    _ = x
    \\    return todo[T]()
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;

const snapshot_source =
    \\func ordinary(x: int) -> int:
    \\    mut y = x + 1
    \\    return todo[int]()
    \\
    \\
    \\func maybe(flag: bool) -> int:
    \\    if flag:
    \\        mut pending = 1
    \\    return todo[int]()
    \\
    \\
    \\func bounded(mut values: int[]) -> int effects(mutation):
    \\    return todo[int]()
    \\
    \\
    \\func template[T: copy + storable](value: T) -> T:
    \\    return todo[T]()
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const independent_source =
    \\func broken() -> int:
    \\    return absent_name()
    \\
    \\
    \\func holed(x: int) -> int:
    \\    return todo[int]()
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

const single_hole =
    \\func first() -> int:
    \\    return todo[int]()
    \\
    \\
    \\func main() -> int:
    \\    return 7
;

const moved_hole =
    \\func first() -> int:
    \\
    \\    return todo[int]()
    \\
    \\
    \\func main() -> int:
    \\    return 7
;

const filled_hole =
    \\func first() -> int:
    \\    return 7
    \\
    \\
    \\func main() -> int:
    \\    return 7
;

fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "holes.selka", two_holes);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    for (compilation.diagnostics.items) |item| {
        try t.expectEqualStrings("E_TYPED_HOLE", item.code);
        try t.expectEqualStrings("todo", compilation.src.text(item.span));
        try t.expect(item.related != null);
    }
    try t.expectError(error.SourceError, native.run(&compilation));
    try t.expect(compilation.program == null);
}
// spec: TYPED-HOLES-1
test "typed implementation obligations report independent generic and ordinary holes under allocation failure" {
    try scenario(t.allocator);
    try t.checkAllAllocationFailures(t.allocator, scenario, .{});
}
test "formatting retains typed holes and filling them restores executable checking" {
    var c = try language.Compilation.init(t.allocator, "holes.selka", two_holes);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "todo[i64]()") != null);
    var repaired = try language.Compilation.init(t.allocator, "fixed.selka",
        \\func main() -> i64:
        \\    return 7
    );
    defer repaired.deinit();
    try t.expectEqual(@as(i64, 7), (try native.run(&repaired)).value);
}

test "trap mode keeps a typed hole as a node of its declared type and reports nothing" {
    var compilation = try language.Compilation.init(t.allocator, "trap.selka", single_hole);
    defer compilation.deinit();
    compilation.checking.holes = .trap;
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
    try t.expect(language.typed.hasHole(compilation.program.?));
}

/// A skeleton: every parameter of `skeleton` is unread because its body is still a hole.
const unfinished_parameters =
    \\public func skeleton(fs: Filesystem, path: str, flag: int) -> bytes:
    \\    return todo[bytes]()
    \\
    \\
    \\func main() -> int:
    \\    return 0
;

/// Check `bytes` with holes kept as traps, as `build`, `run` and `test` do, and return the diagnostic codes in order.
fn trapCodes(allocator: std.mem.Allocator, bytes: []const u8) ![]const []const u8 {
    var compilation = try language.Compilation.init(allocator, "skeleton.selka", bytes);
    defer compilation.deinit();
    compilation.checking.holes = .trap;
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    const codes = try allocator.alloc([]const u8, compilation.diagnostics.items.len);
    for (compilation.diagnostics.items, codes) |item, *code| code.* = try allocator.dupe(u8, item.code);
    return codes;
}

// spec: TYPED-HOLES-1
test "a body that still holds a hole is not refused or warned about for parameters it does not read" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const codes = try trapCodes(arena.allocator(), unfinished_parameters);
    try t.expectEqual(@as(usize, 0), codes.len);
}

// spec: TYPED-HOLES-1
test "filling the hole makes an unread capability an error again, and a hole elsewhere does not excuse it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const filled = try std.mem.replaceOwned(u8, a, unfinished_parameters, "todo[bytes]()", "b\"\"");
    const filled_codes = try trapCodes(a, filled);
    try t.expectEqual(@as(usize, 3), filled_codes.len);
    try t.expectEqualStrings("E_UNUSED_CAPABILITY", filled_codes[0]);
    try t.expectEqualStrings("W_UNUSED_BINDING", filled_codes[1]);
    const beside = try trapCodes(a,
        \\public func skeleton(path: str) -> int:
        \\    return todo[int]()
        \\
        \\
        \\public func finished(fs: Filesystem) -> int:
        \\    return 1
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqual(@as(usize, 1), beside.len);
    try t.expectEqualStrings("E_UNUSED_CAPABILITY", beside[0]);
}

// spec: TYPED-HOLES-1
test "a hole spares only the parameters of its own function, and only in trap mode" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const local = try trapCodes(a,
        \\public func skeleton(fs: Filesystem) -> int:
        \\    const note = 3
        \\    return todo[int]()
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    try t.expectEqual(@as(usize, 1), local.len);
    try t.expectEqualStrings("W_UNUSED_BINDING", local[0]);
    var refused = try language.Compilation.init(a, "refused.selka", unfinished_parameters);
    defer refused.deinit();
    try t.expectError(error.SourceError, refused.check());
    try t.expect(diagnostic.holesOnly(refused.diagnostics.items));
}

test "a refusal made only of typed holes is recognised, a hole-only shadow program keeps the hole, and any other refusal recovers the bodies that checked" {
    var holes_only = try language.Compilation.init(t.allocator, "holes.selka", two_holes);
    defer holes_only.deinit();
    try t.expectError(error.SourceError, holes_only.check());
    try t.expect(diagnostic.holesOnly(holes_only.diagnostics.items));
    const shadow = try holes_only.holeProgram(false);
    try t.expect(shadow != null);
    try t.expect(language.typed.hasHole(shadow.?));
    var mixed = try language.Compilation.init(t.allocator, "mixed.selka", independent_source);
    defer mixed.deinit();
    try t.expectError(error.SourceError, mixed.check());
    try t.expect(!diagnostic.holesOnly(mixed.diagnostics.items));
    // The body that failed is stood in; the holed body checks with its hole as a typed node (F-RC-214).
    const recovered = (try mixed.holeProgram(false)).?;
    var stood_in: usize = 0;
    for (recovered.functions) |function| stood_in += @intFromBool(language.typed.recoveredStandIn(function));
    try t.expectEqual(@as(usize, 1), stood_in);
    try t.expect(language.typed.hasHole(recovered));
    try t.expect(!diagnostic.holesOnly(mixed.diagnostics.items));
}

const hidden_by_hole =
    \\func hole() -> int:
    \\    return todo[int]()
    \\
    \\
    \\func case_unused(out: Stream, fs: Filesystem) -> bool:
    \\    return fs.exists("x")
    \\
    \\
    \\func main() -> int:
    \\    mut spare = 3
    \\    return 0
;

test "the check that keeps holes as traps contributes the errors and warnings a refused check never reached" {
    var unit = try language.Compilation.init(t.allocator, "hidden.selka", hidden_by_hole);
    defer unit.deinit();
    try t.expectError(error.SourceError, unit.check());
    try t.expect(diagnostic.holesOnly(unit.diagnostics.items));
    try t.expectEqual(@as(usize, 1), unit.diagnostics.items.len);
    // The follow-up check fails too (the unread `out`), so there is no program; what it found is now in the list, once.
    try t.expect((try unit.holeProgram(false)) == null);
    var codes: [3][]const u8 = undefined;
    try t.expectEqual(codes.len, unit.diagnostics.items.len);
    for (unit.diagnostics.items, &codes) |item, *code| code.* = item.code;
    try t.expectEqualStrings("E_TYPED_HOLE", codes[0]);
    try t.expectEqualStrings("E_UNUSED_CAPABILITY", codes[1]);
    try t.expectEqualStrings("W_UNUSED_BINDING", codes[2]);
}

test "a diagnostic is held when its code and place are in the list" {
    const here: diagnostic.Diagnostic = .{ .code = "E_TYPED_HOLE", .span = .{ .start = 3, .end = 9 }, .message = "a" };
    const items = [_]diagnostic.Diagnostic{here};
    try t.expect(diagnostic.holds(&items, .{ .code = "E_TYPED_HOLE", .span = .{ .start = 3, .end = 9 }, .message = "b" }));
    try t.expect(!diagnostic.holds(&items, .{ .code = "E_TYPE", .span = .{ .start = 3, .end = 9 }, .message = "a" }));
    try t.expect(!diagnostic.holds(&items, .{ .code = "E_TYPED_HOLE", .span = .{ .start = 3, .end = 10 }, .message = "a" }));
    try t.expect(!diagnostic.holds(&.{}, here));
}

/// Parse and check one source, returning the compilation for the caller to release.
fn checked(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !language.Compilation {
    var compilation = try language.Compilation.init(allocator, path, bytes);
    errdefer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    return compilation;
}

/// The obligation recorded for the hole inside the callable named `name`.
fn obligationFor(compilation: *const language.Compilation, name: []const u8) !*const diagnostic.Obligation {
    for (compilation.diagnostics.items) |item| {
        const obligation = item.provenance.obligation orelse continue;
        const function = obligation.header.function orelse continue;
        if (std.mem.eql(u8, function.text, name)) return obligation;
    }
    return error.MissingObligation;
}

/// The recorded type of the binding named `name`, or null when it was not published.
fn bindingType(obligation: *const diagnostic.Obligation, name: []const u8) ?[]const u8 {
    for (obligation.bindings) |binding| if (std.mem.eql(u8, binding.name, name)) return binding.ty;
    return null;
}

/// Whether the snapshot records `requirement` as in force for `subject`.
fn hasRequirement(obligation: *const diagnostic.Obligation, subject: []const u8, requirement: []const u8) bool {
    for (obligation.requirements) |entry| {
        if (std.mem.eql(u8, entry.subject, subject) and std.mem.eql(u8, entry.requirement, requirement)) return true;
    }
    return false;
}

/// The JSON text of one diagnostic that is not a typed hole.
fn unrelatedJson(allocator: std.mem.Allocator) ![]u8 {
    var compilation = try checked(allocator, "broken.selka", "func main() -> int:\n    return absent_name()\n");
    defer compilation.deinit();
    return language.diagnostic_output.render(allocator, compilation.diagnostics.items[0], compilation.src, .json);
}

/// Record one hole with explicit findings, as an error union a test can match.
fn recordFindings(sink: *diagnostic.Sink, src: source.Source, at: source.Span, target: source.Span, findings: diagnostic.Findings) diagnostic.Error!void {
    return sink.recordHole(src, at, target, findings);
}

/// One candidate more than a snapshot retains, all naming the same usable binding.
fn candidateRow(at: source.Span) [diagnostic.max_obligation_bindings + 1]diagnostic.Candidate {
    var row: [diagnostic.max_obligation_bindings + 1]diagnostic.Candidate = undefined;
    for (&row) |*entry| entry.* = .{ .name = "x", .ty = "int", .declaration = at, .mutable = false, .usable = true };
    return row;
}

// spec: TYPED-HOLES-2
test "ordinary and uncalled generic holes retain their own bounded context snapshot" {
    var retired = try language.Compilation.init(t.allocator, "retired-snapshot.selka", snapshot_source);
    defer retired.deinit();
    try t.expectError(error.SourceError, retired.check());
    try t.expectEqualStrings("E_EFFECTS_REMOVED", retired.diagnostics.items[0].code);
    const modern_source = try std.mem.replaceOwned(u8, t.allocator, snapshot_source, " effects(mutation)", "");
    defer t.allocator.free(modern_source);
    var compilation = try checked(t.allocator, "snapshot.selka", modern_source);
    defer compilation.deinit();
    try t.expectEqual(@as(usize, 4), compilation.diagnostics.items.len);
    const ordinary = try obligationFor(&compilation, "ordinary");
    try t.expectEqual(diagnostic.obligation_version, ordinary.header.version);
    try t.expectEqualStrings("int", ordinary.declared.text);
    try t.expectEqualStrings("int", ordinary.expected.?.text);
    try t.expectEqualStrings("int", bindingType(ordinary, "x").?);
    try t.expectEqualStrings("int", bindingType(ordinary, "y").?);
    try t.expectEqual(@as(usize, 0), ordinary.requirements.len);
    try t.expectEqualStrings("none", ordinary.contract.mutation.?.text);
    const maybe = try obligationFor(&compilation, "maybe");
    try t.expectEqualStrings("bool", bindingType(maybe, "flag").?);
    try t.expect(bindingType(maybe, "pending") == null);
    try t.expectEqual(@as(usize, 0), maybe.contract.unusable_bindings);
    const bounded = try obligationFor(&compilation, "bounded");
    try t.expectEqualStrings("mut(values)", bounded.contract.mutation.?.text);
    const generic = try obligationFor(&compilation, "template");
    try t.expectEqualStrings("T", generic.declared.text);
    try t.expectEqualStrings("T", generic.expected.?.text);
    try t.expectEqualStrings("T", bindingType(generic, "value").?);
    try t.expect(hasRequirement(generic, "T", "copy"));
    try t.expect(hasRequirement(generic, "T", "storable"));
    try t.expectEqual(@as(usize, 0), generic.header.omitted);
    try t.expect(ordinary.header.snapshot != generic.header.snapshot);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "caps.selka", "todo[int]()");
    var sink = diagnostic.Sink{ .allocator = arena.allocator() };
    defer sink.deinit();
    const at: source.Span = .{ .start = 0, .end = 4 };
    const target: source.Span = .{ .start = 5, .end = 8 };
    // One more candidate than a snapshot retains: the surplus is counted, not dropped silently.
    const surplus = candidateRow(at);
    try t.expectError(error.SourceError, recordFindings(&sink, src, at, target, .{ .candidates = &surplus }));
    const capped = sink.items.items[0].provenance.obligation.?;
    try t.expectEqual(@as(usize, 1), capped.header.omitted);
    try t.expectEqual(diagnostic.max_obligation_bindings, capped.bindings.len);
}

// spec: TYPED-HOLES-6
test "a separate invalid function keeps its own diagnostic without an obligation" {
    var compilation = try checked(t.allocator, "independent.selka", independent_source);
    defer compilation.deinit();
    try t.expectEqual(@as(usize, 2), compilation.diagnostics.items.len);
    const holed = try obligationFor(&compilation, "holed");
    try t.expectEqualStrings("int", bindingType(holed, "x").?);
    try t.expect(diagnostic.findObligation(compilation.diagnostics.items, .{ .snapshot = holed.header.snapshot, .site = holed.header.site }) != null);
    try t.expectEqualStrings("E_UNKNOWN_FUNCTION", compilation.diagnostics.items[0].code);
    try t.expect(compilation.diagnostics.items[0].related == null);
    try t.expect(compilation.diagnostics.items[0].provenance.obligation == null);
}

// spec: TYPED-HOLES-3
test "a hole publishes a versioned obligation in JSON and keeps every other diagnostic unchanged" {
    var compilation = try checked(t.allocator, "hole.selka", single_hole);
    defer compilation.deinit();
    const json = try language.diagnostic_output.render(t.allocator, compilation.diagnostics.items[0], compilation.src, .json);
    defer t.allocator.free(json);
    try t.expect(std.mem.indexOf(u8, json, "\"obligation\":{\"kind\":\"typed-hole-obligation\",\"version\":1,\"identity\":{\"snapshot\":\"") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"declared\":{\"text\":\"int\",\"location\":{\"path\":\"hole.selka\",\"start\":{\"line\":2,\"column\":17}") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"bindings\":[]") != null);
    try t.expect(std.mem.indexOf(u8, json, "\"unavailable\":[]") != null);
    const text = try language.diagnostic_output.render(t.allocator, compilation.diagnostics.items[0], compilation.src, .text);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "error[E_TYPED_HOLE]: unresolved implementation obligation; fill this hole before checking or execution") != null);
    try t.expect(std.mem.indexOf(u8, text, "note: hole.selka:2:17: required result type declared here") != null);
    try t.expect(std.mem.indexOf(u8, text, "snapshot") == null);
    try t.expect(std.mem.indexOf(u8, text, "bindings") == null);
    const other = try unrelatedJson(t.allocator);
    defer t.allocator.free(other);
    try t.expect(std.mem.indexOf(u8, other, "\"obligation\"") == null);
    try t.expect(std.mem.indexOf(u8, other, "\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\",\"diagnostic\":{\"code\":") != null);
}

// spec: TYPED-HOLES-4
test "a hole's snapshot and range identify it, a stale query rejects, and filling removes the obligation" {
    var first = try checked(t.allocator, "hole.selka", single_hole);
    defer first.deinit();
    const recorded = try obligationFor(&first, "first");
    const query: diagnostic.Query = .{ .snapshot = recorded.header.snapshot, .site = recorded.header.site };
    try t.expect(diagnostic.findObligation(first.diagnostics.items, query) != null);
    try t.expect(diagnostic.findObligation(first.diagnostics.items, .{ .snapshot = query.snapshot ^ 1, .site = query.site }) == null);
    try t.expect(diagnostic.findObligation(first.diagnostics.items, .{ .snapshot = query.snapshot, .site = .{ .start = query.site.start + 1, .end = query.site.end + 1 } }) == null);
    var moved = try checked(t.allocator, "hole.selka", moved_hole);
    defer moved.deinit();
    try t.expect(diagnostic.findObligation(moved.diagnostics.items, query) == null);
    const shifted = try obligationFor(&moved, "first");
    try t.expectEqual(query.site.start + 1, shifted.header.site.start);
    try t.expect(shifted.header.snapshot != query.snapshot);
    var filled = try checked(t.allocator, "hole.selka", filled_hole);
    defer filled.deinit();
    try t.expectEqual(@as(usize, 0), filled.diagnostics.items.len);
    try t.expect(diagnostic.findObligation(filled.diagnostics.items, query) == null);
    try t.expectError(error.MissingObligation, obligationFor(&filled, "first"));
    try t.expectEqual(@as(i64, 7), (try native.run(&filled)).value);
}

// spec: TYPED-HOLES-5
test "an unretainable snapshot still reports the hole and OutOfMemory is its only failure" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "hole.selka", "todo[int]()");
    const at: source.Span = .{ .start = 0, .end = 4 };
    const target: source.Span = .{ .start = 5, .end = 8 };
    var none = t.FailingAllocator.init(arena.allocator(), .{ .fail_index = 0 });
    var starved = diagnostic.Sink{ .allocator = none.allocator() };
    defer starved.deinit();
    try t.expectError(error.OutOfMemory, recordFindings(&starved, src, at, target, .{}));
    try t.expectEqual(@as(usize, 0), starved.items.items.len);
    var later = t.FailingAllocator.init(arena.allocator(), .{ .fail_index = 1 });
    var kept = diagnostic.Sink{ .allocator = later.allocator() };
    defer kept.deinit();
    try kept.items.append(kept.allocator, .{ .code = "E_TEST", .span = at, .message = "warm the diagnostic array" });
    kept.items.clearRetainingCapacity();
    try t.expectError(error.SourceError, recordFindings(&kept, src, at, target, .{}));
    try t.expectEqual(@as(usize, 1), kept.items.items.len);
    try t.expect(kept.items.items[0].provenance.obligation == null);
}
