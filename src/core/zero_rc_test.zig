//! Source ownership, direct cleanup, and rejection boundaries for zero-RC stage 1.
const std = @import("std");

const language = @import("selka");
const contract = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC recursive copies preserve mixed children after original destruction" {
    try executes(std.testing.allocator,
        \\import lists
        \\import strings
        \\
        \\enum Tree:
        \\    leaf(items: dict[str, str[]])
        \\    node(child: Tree)
        \\func score(tree: Tree) -> int:
        \\    match tree:
        \\        case leaf(items=items):
        \\            return strings.char_count(items["key-1"][0])
        \\        case node(child=child):
        \\            return 1 + score(child)
        \\func main(out: Stream) -> int:
        \\    mut tree = Tree.leaf(items={"key-" + str(1): ["value-" + str(1)]})
        \\    for i in range(200):
        \\        tree = Tree.node(child=own tree)
        \\    mut original = [own tree]
        \\    const saved = copy(original)
        \\    lists.clear(mut original)
        \\    print(out, score(saved[0]))
        \\    return 0
    , "207\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC owned options deeply copy and pattern borrows cannot escape" {
    try executes(std.testing.allocator,
        \\import lists
        \\import strings
        \\
        \\func size(value: str?) -> int:
        \\    match value:
        \\        case Some(text):
        \\            return strings.char_count(text)
        \\        case None:
        \\            return 0
        \\func main(out: Stream) -> int:
        \\    mut values: str?[] = [Some("value-" + str(1)), None]
        \\    const saved = copy(values)
        \\    lists.clear(mut values)
        \\    print(out, size(saved[0]), size(saved[1]))
        \\    return 0
    , "7 0\n");
    // R3b: the refusal this case pinned is an accepted borrow now (see borrowed_return_test.zig).
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionary pop transfers owned values and defaults" {
    try executes(std.testing.allocator,
        \\import dicts
        \\import sets
        \\
        \\func main(out: Stream) -> int:
        \\    mut values = {1: "value-" + str(1), 2: "value-" + str(2)}
        \\    const first = dicts.pop(mut values, 1)
        \\    const second = dicts.pop_default(mut values, 2, "unused-" + str(3))
        \\    const missing = dicts.pop_default(mut values, 3, "fallback-" + str(4))
        \\    values[9] = "unused-" + str(9)
        \\    _ = dicts.pop(mut values, 9)
        \\    print(out, first, second, missing, len(values))
        \\    mut keys = {"key-" + str(1), "key-" + str(2)}
        \\    const key = sets.pop(mut keys)
        \\    sets.clear(mut keys)
        \\    print(out, key)
        \\    return 0
    , "value-1 value-2 fallback-4 0\nkey-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC recursive owned values borrow match payloads" {
    try executes(std.testing.allocator,
        \\enum Expr:
        \\    text(value: str)
        \\    add(left: Expr, right: Expr)
        \\func evaluate(e: Expr) -> int:
        \\    match e:
        \\        case text(value=v):
        \\            return strings.char_count(v)
        \\        case add(left=l, right=r):
        \\            return evaluate(l) + evaluate(r)
        \\func main(out: Stream) -> int:
        \\    const tree = Expr.add(left=Expr.text(value="one-" + str(1)), right=Expr.text(value="two-" + str(2)))
        \\    print(out, evaluate(tree))
        \\    return 0
    , "10\n");
}

// spec: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionaries grow replace and deeply copy managed entries" {
    try executes(std.testing.allocator,
        \\import dicts
        \\
        \\func main(out: Stream) -> int:
        \\    mut values: dict[str, str[]] = {}
        \\    for i in range(40):
        \\        values["key-" + str(i)] = ["value-" + str(i)]
        \\    mut saved = copy(values)
        \\    values["key-1"] = ["changed"]
        \\    print(out, values["key-1"][0], saved["key-1"][0], len(saved))
        \\    dicts.clear(mut values)
        \\    print(out, saved["key-2"][0])
        \\    return 0
    , "changed value-1 40\nvalue-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionaries consume keys and values and reject borrowed extraction" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut values: dict[str, int] = {}
        \\    const key = "key-" + str(1)
        \\    values[own key] = 1
        \\    return strings.char_count(key)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = {1: "value-" + str(1)}
        \\    mut value = values[1]
        \\    value = value + "!"
        \\    return strings.char_count(value)
    , "E_SINGLE_OWNER_BORROW");
}

const ProjectEntry = struct {
    source: []const u8,
    /// Supply the entry module; embedded standard modules use the normal loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const entry: *ProjectEntry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, entry.source);
    }
};

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    if (support.needsModules(source)) {
        var entry: ProjectEntry = .{ .source = source };
        var project: language.embedded_project.Program = undefined;
        try project.init(a, .{ .context = &entry, .read = ProjectEntry.read });
        return project.compilation.program.?;
    }
    var unit = try language.Compilation.init(a, "zero-rc.selka", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s} at {d}: {s}\n", .{ diagnostic.code, diagnostic.span.start, diagnostic.message });
        return err;
    };
    return unit.program.?;
}

fn retiredSource(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    if (support.needsModules(source)) {
        const a = arena.allocator();
        var entry: ProjectEntry = .{ .source = source };
        var loaded = language.project.Project.init(a);
        defer loaded.deinit();
        try loaded.load(.{ .context = &entry, .read = ProjectEntry.read }, "main", .{});
        var index = language.interfaces.build(&loaded) catch |err| {
            if (err != error.SourceError) return err;
            try std.testing.expect(loaded.problem != null);
            try std.testing.expectEqualStrings(code, loaded.problem.?.code);
            return;
        };
        var unit = try language.project_compile.Compilation.init(&index);
        try std.testing.expectError(error.SourceError, unit.check());
        try std.testing.expect(unit.diagnostics.items.items.len > 0);
        for (unit.diagnostics.items.items) |item| try std.testing.expectEqualStrings(code, item.code);
        return;
    }
    var unit = try language.Compilation.init(arena.allocator(), "retired-zero-rc.selka", source);
    try std.testing.expectError(error.SourceError, unit.check());
    try std.testing.expect(unit.diagnostics.items.len > 0);
    for (unit.diagnostics.items) |item| try std.testing.expectEqualStrings(code, item.code);
}

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    return refusesOwnership(parent, source, code, null);
}

fn refusesOwnership(parent: std.mem.Allocator, source: []const u8, code: []const u8, rule: ?language.ownership_rules.Rule) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(arena.allocator(), try checked(arena.allocator(), source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    if (rule) |expected| try std.testing.expectEqual(expected, failure.rule.?);
}

/// `refuses` with `code` first, the rule `P3`, the declaration's name as the position, and `message` in full.
fn refusesWithMessage(parent: std.mem.Allocator, source: []const u8, code: []const u8, message: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(arena.allocator(), try checked(arena.allocator(), source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.P3, failure.rule.?);
    try std.testing.expectEqualStrings(message, failure.message);
}

/// Check `source` and require the zero-RC ownership contract to accept it.
fn accepts(parent: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    contract.check(arena.allocator(), try checked(arena.allocator(), source), &failure) catch |err| {
        report("zero-RC source: {s}: {s} at {d}\n", .{ failure.code, failure.message, failure.span.start });
        return err;
    };
}

/// Refuse `source` at the checker, before the ownership pass, with `code` first.
fn refusedAtCheck(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const outcome = try support.checkSource(arena.allocator(), source);
    try std.testing.expect(!outcome.passed);
    try std.testing.expect(outcome.diagnostics.len != 0);
    try std.testing.expectEqualStrings(code, outcome.diagnostics[0].code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var program = try checked(a, source);
    return executeChecked(a, &program, expected);
}

/// Run one program checked as an embedded project, so it may import a standard
/// module; a single-unit compilation cannot carry an `import`.
fn executesProject(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var entry: Entry = .{ .text = source };
    var project: language.embedded_project.Program = undefined;
    try project.init(a, .{ .context = &entry, .read = Entry.read });
    var program = project.compilation.program.?;
    return executeChecked(a, &program, expected);
}

/// The zero-RC contract and native run both executables share, for one checked program.
fn executeChecked(a: std.mem.Allocator, program: *language.typed.Program, expected: []const u8) !void {
    var failure: contract.Failure = .{};
    contract.check(a, program.*, &failure) catch |err| {
        report("zero-RC source: {s} at {d}\n", .{ failure.message, failure.span.start });
        return err;
    };
    const main_fn = program.functions[@backingInt(program.main)];
    const parameter_names = try a.alloc([]const u8, main_fn.signature.parameter_count);
    const capabilities = try a.alloc(u8, parameter_names.len);
    for (parameter_names, capabilities, main_fn.scope.locals[0..parameter_names.len]) |*name, *cap, local| {
        name.* = local.name;
        cap.* = local.ty.capabilityIndex() orelse 255;
    }
    inline for (.{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = build.buildExecutable(a, .{ .program = program.* }, &refusal) catch |err| {
            report("zero-RC builder: {s}\n", .{refusal.reason});
            return err;
        };
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);

        // Before the catch below: a skip must not reach it, since the catch prints the whole module on any error.
        if (optimized) try support.requireRelease();
        const run = support.runOwned(a, &module, .{ .own = false, .release = optimized, .verify = optimized, .analysis = support.analysis(&result), .main = .{ .parameters = parameter_names, .capabilities = capabilities } }) catch |err| {
            report("zero-RC execution (optimized={}):\n{s}\n", .{ optimized, try @import("print.zig").module(a, &module) });
            return err;
        };
        if (run.status != 0) report("zero-RC run:\n{s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(zero.emittedClean(run.llvm));
    }
}

// spec: NEW-CORE-ZERO-RC-1
test "a zero-RC contract violation is rejected by executeChecked before either executable is built" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a,
        \\func main() -> int:
        \\    const text = "x" + str(7)
        \\    const saved = own text
        \\    return strings.char_count(saved) + strings.char_count(text)
    );
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(a, program, &failure));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_MOVED", failure.code);
}

// spec: NEW-CORE-ZERO-RC-1
test "zero RC string and byte ownership rejects aliases and undeclared borrowed returns" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const text = "x" + str(7)
        \\    const saved = own text
        \\    return strings.char_count(saved) + strings.char_count(text)
    , "E_SINGLE_OWNER_MOVED");
    try refusesDeclaration(std.testing.allocator,
        \\func keep(text: str) -> str:
        \\    return text
        \\func main() -> int:
        \\    return strings.char_count(keep("x"))
    , " from text");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const data = bytes(byte_buffer([1, 2]))
        \\    const saved = own data
        \\    return len(saved) + len(data)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\import buffers
        \\
        \\func main() -> int:
        \\    mut data = byte_buffer([1, 2])
        \\    const saved = own data
        \\    _ = buffers.append_byte(mut data, 3)
        \\    return len(saved)
    , "E_SINGLE_OWNER_MOVED");
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC strings reject overlapping mutation and record field escapes" {
    try refuses(std.testing.allocator,
        \\func combine(text: str, mut target: str):
        \\    target += text
        \\func main() -> int:
        \\    mut text = "x"
        \\    combine(text, mut text)
        \\    return strings.char_count(text)
    , "E_SINGLE_OWNER_OVERLAP");
    // R3b: a field of a record parameter returned is an accepted borrow (see tests/lang/borrowed_results.selka).
}

// spec-case: NEW-CORE-ZERO-RC-1
test "checked ownership refuses retained byte views" {
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip original retained byte-view spelling refusal witness
        \\func main() -> int:
        \\    const values = bytes(byte_buffer([1, 2]))
        \\    const saved = values.view(0, 1)
        \\    return len(saved)
    , "E_BORROW_VIEWS_REMOVED");
}

// spec: NEW-CORE-ZERO-RC-2
test "zero RC text growth copies slices and static ASCII characters execute" {
    try executes(std.testing.allocator,
        \\func segment(text: str) -> str from text:
        \\    return strings.char_slice(text, 2, 5)
        \\func main(out: Stream) -> int:
        \\    mut text = ""
        \\    for i in range(200):
        \\        text += "aλz"
        \\    const old = copy(text)
        \\    const part = copy(segment(text))
        \\    text += text
        \\    const first = strings.char_at(part, 0)
        \\    const second = strings.char_at(part, 2)
        \\    print(out, strings.char_count(old), strings.char_count(text), first, second, ord(first))
        \\    return 0
    , "600 1200 z λ 122\n");
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC nested records deeply copy text bytes buffers and arrays" {
    try executes(std.testing.allocator,
        \\import buffers
        \\import lists
        \\
        \\record Row:
        \\    text: str
        \\    data: bytes
        \\    buffer: byte_buffer
        \\    names: FixedArray[str, 2]
        \\func main(out: Stream) -> int:
        \\    const row = Row(text="row:" + str(7), data=bytes(byte_buffer([8])), buffer=byte_buffer([9]), names=FixedArray[str, 2](["a", "b"]))
        \\    mut rows = [own row]
        \\    mut saved = copy(rows)
        \\    lists.clear(mut rows)
        \\    _ = buffers.append_byte(mut saved[0].buffer, 10)
        \\    print(out, saved[0].text, len(saved[0].data), len(saved[0].buffer), saved[0].names[1])
        \\    return 0
    , "row:7 1 2 b\n");
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC buffer and bytes copies preserve independent storage" {
    try executes(std.testing.allocator,
        \\import buffers
        \\
        \\func grow(mut target: byte_buffer):
        \\    _ = buffers.append_byte(mut target, 7)
        \\func main(out: Stream) -> int:
        \\    mut buffer = byte_buffer([1, 2])
        \\    const old = bytes(buffer)
        \\    const data = copy(old)
        \\    mut copied = copy(buffer)
        \\    grow(mut buffer)
        \\    buffers.append_utf8(mut copied, "λ")
        \\    print(out, len(old), len(data), len(buffer), len(copied))
        \\    return 0
    , "2 2 3 4\n");
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC mut text replacement early returns and loop moves execute" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\func grow(mut text: str):
        \\    text += "λ"
        \\func select(flag: bool) -> str:
        \\    mut text = "value:" + str(9)
        \\    grow(mut text)
        \\    if flag:
        \\        return text
        \\    text = "other"
        \\    return text
        \\func main(out: Stream) -> int:
        \\    mut values: str[] = []
        \\    for i in range(4):
        \\        const text = select(i == 0)
        \\        append(mut values, own text)
        \\    const last = lists.pop(mut values)
        \\    print(out, values[0], last)
        \\    return 0
    , "value:9λ other\n");
}

// spec: NEW-CORE-ZERO-RC-3
test "zero RC runtime admission and emitted count operations fail closed" {
    try std.testing.expect(zero.contract("myl_core_str_chars") != null);
    try std.testing.expect(zero.contract("myl_core_task_submit") == null);
    try std.testing.expect(zero.contract("foreign_alloc") == null);
    try std.testing.expect(!zero.emittedClean("  %c = load atomic i32, ptr %p unordered, align 8\n"));
    try std.testing.expect(!zero.emittedClean("  call void @myl_core_release(ptr %p)\n"));
    try std.testing.expect(!zero.emittedClean("  call preserve_mostcc void @myl_core_retain_slow(ptr %p)\n"));
    try std.testing.expect(zero.emittedClean("  call void @myl_core_drop_owned(ptr %p)\n"));
    // Rounding is now an audited scalar helper; keep the unknown-symbol
    // refusals above and exercise the admitted operation through native code.
    try executes(std.testing.allocator,
        \\func main() -> int:
        \\    const value = round(1.234, 2)
        \\    if value > 1.0:
        \\        return 0
        \\    return 1
    , "");
}

/// `emittedClean` as it was defined, line by line, for the test that the whole-text search agrees.
fn cleanByLine(text: []const u8) bool {
    const symbols = [_][]const u8{ "@myl_core_retain", "@myl_core_release", "@myl_core_share(", "@myl_core_free_block(" };
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "load atomic i32") != null) return false;
        if (std.mem.indexOf(u8, line, "store i32") != null and std.mem.indexOf(u8, line, "!tbaa !3") != null) return false;
        const declaration = std.mem.startsWith(u8, line, "declare ") or std.mem.startsWith(u8, line, "define ");
        if (!declaration and std.mem.indexOf(u8, line, "call ") == null) continue;
        for (symbols) |name| {
            if (std.mem.indexOf(u8, line, name) != null) return false;
        }
    }
    return true;
}

// spec-case: NEW-CORE-ZERO-RC-3
test "the emitted-code guard searches the whole text and agrees with its line by line definition" {
    const cases = [_][]const u8{
        "",
        "define i32 @f() {\n  ret i32 0\n}\n",
        "  %c = load atomic i32, ptr %p unordered, align 8",
        "  store i32 1, ptr %p, align 4\n  ret void\n",
        "  store i32 1, ptr %p, align 4, !tbaa !3\n",
        "  store i32 1, ptr %p\n  store i32 2, ptr %q, !tbaa !3",
        "  store i32 1, ptr %p\n!3 = !{!\"tbaa !3\"}\n  store i32 2, ptr %q, !tbaa !4\n",
        "declare void @myl_core_retain(ptr)\n",
        "define void @f() {\n  call void @myl_core_release(ptr %0)\n}\n",
        "  ; @myl_core_retain is only mentioned in a comment\n",
        "@table = global ptr @myl_core_free_block\n",
        "  %x = tail call i64 @myl_core_share(ptr %p)\n",
        "  %x = call i64 @myl_core_share_other(ptr %p)\n",
        "  call void @myl_core_drop_owned(ptr %p)\n  call void @myl_core_free_block(ptr %p)",
        "  %y = call ptr @a()\n\n\n  store i32 3, ptr %z\nsuffix @myl_core_release(",
    };
    const expected = [_]bool{ true, true, false, true, false, false, true, false, false, true, true, false, true, false, true };
    var verdicts: [cases.len]bool = undefined;
    for (cases, 0..) |text, index| {
        verdicts[index] = zero.emittedClean(text);
        try std.testing.expectEqual(cleanByLine(text), verdicts[index]);
    }
    try std.testing.expectEqualSlices(bool, &expected, &verdicts);
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-1
test "zero RC task item diagnostics do not transfer managed ownership" {
    const marker = zero.contract("myl_core_task_item").?;
    try std.testing.expectEqual(@as(u64, 0), marker.owned);
    try std.testing.expectEqual(@as(u64, 0), marker.views);
    try std.testing.expectEqual(.scalar, marker.result);
    try std.testing.expect(zero.contract("myl_core_task_submit") == null);
}

fn resultEntryCase(parent: std.mem.Allocator, mode: support.RunOptions, failed: bool, direct: bool) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const source = if (failed)
        \\func main(args: str[]) -> Result[int, str]:
        \\    return Err("failure-" + str(len(args)))
    else
        \\func main(args: str[]) -> Result[int, str]:
        \\    return Ok(len(args))
    ;
    var program = try checked(a, source);
    // Source compilation normally synthesizes an integer-returning wrapper.
    // Also exercise the emitter's direct Core Result entry, used by IR clients.
    if (direct) for (program.functions) |function| {
        if (language.typed.resultShape(function.signature.return_type, program.records) != null) {
            program.main = function.id;
            break;
        }
    };
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    const result = if (mode.own) try passes.run(a, &module, if (mode.verify) .verify else .trusted) else try passes.debug(a, &module);

    const run = try support.runOwned(a, &module, .{
        .own = false,
        .release = mode.release,
        .verify = mode.verify,
        .analysis = support.analysis(&result),
        .main = .{ .parameters = &.{"args"}, .result = .{ .ok_tag = 0, .error_tag = 1 } },
    });
    try std.testing.expectEqual(@as(u8, if (failed) 1 else 0), run.status);
    try std.testing.expectEqualStrings("", run.stdout);
    if (failed) {
        try std.testing.expect(std.mem.startsWith(u8, run.stderr, "error: failure-0\n"));
        if (direct) try std.testing.expect(std.mem.indexOf(u8, run.llvm, "call void @myl_core_drop_owned(ptr %error)") != null);
    } else try std.testing.expectEqualStrings("", run.stderr);
    try std.testing.expect(std.mem.indexOf(u8, run.stderr, "leak") == null);
    try std.testing.expect(zero.emittedClean(run.llvm));
}

fn resultEntryModes(parent: std.mem.Allocator) !void {
    const modes = [_]support.RunOptions{
        .{ .own = false },
        .{},
        .{ .release = true },
        .{ .release = true, .verify = true },
        .{ .release = true, .own = false },
    };
    for (modes) |mode| {
        try resultEntryCase(parent, mode, false, false);
        try resultEntryCase(parent, mode, true, false);
        try resultEntryCase(parent, mode, false, true);
        try resultEntryCase(parent, mode, true, true);
    }
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC Result main destroys text errors and borrowed argv in five modes" {
    try resultEntryModes(std.testing.allocator);
}

// spec-case: NEW-CORE-ZERO-RC-3
test "zero RC test transport borrows writes and returns independent decoded blocks" {
    try std.testing.expectEqual(.fresh, zero.contract("myl_core_test_read_text").?.result);
    try std.testing.expectEqual(.fresh, zero.contract("myl_core_test_read_bytes").?.result);
    try std.testing.expectEqual(@as(u64, 0), zero.contract("myl_core_test_write_text").?.owned);
    try std.testing.expectEqual(@as(u64, 0), zero.contract("myl_core_test_open").?.owned);
    try std.testing.expectEqual(.scalar, zero.contract("myl_core_test_register").?.result);
    try std.testing.expect(zero.contract("myl_core_test_unreviewed") == null);
}

// spec-case: NEW-CORE-ZERO-RC-3
test "zero RC encoded span offsets borrow octets and return a scalar" {
    const signature = zero.contract("myl_core_span_bytes_index_offset").?;
    try std.testing.expectEqual(@as(u64, 1), signature.views);
    try std.testing.expectEqual(@as(u64, 0), signature.owned);
    try std.testing.expectEqual(.scalar, signature.result);
    try std.testing.expect(zero.contract("myl_core_span_bytes_index_offset_other") == null);
}

// spec-case: DICT-VIEWS-1
test "zero RC immediate dictionary snapshots own keys values and item children" {
    try executes(std.testing.allocator,
        \\import dicts
        \\
        \\func main(out: Stream) -> int:
        \\    mut source = {"key-" + str(1): ["value-" + str(1)]}
        \\    const keys = list(dicts.keys(source))
        \\    const values = list(dicts.values(source))
        \\    const items = list(dicts.items(source))
        \\    dicts.clear(mut source)
        \\    print(out, keys[0], values[0][0], items[0].key, items[0].value[0])
        \\    mut scalar_keys = {7: ["saved-" + str(2)]}
        \\    const first = list(dicts.items(scalar_keys))
        \\    dicts.clear(mut scalar_keys)
        \\    mut scalar_values = {"saved-" + str(3): 9}
        \\    const second = list(dicts.items(scalar_values))
        \\    dicts.clear(mut scalar_values)
        \\    const scalars = list(dicts.items({4: 5}))
        \\    print(out, first[0].key, first[0].value[0], second[0].key, second[0].value)
        \\    print(out, scalars[0].key, scalars[0].value)
        \\    return 0
    , "key-1 value-1 key-1 value-1\n7 saved-2 saved-3 9\n4 5\n");
}

// spec-case: NEW-CORE-ZERO-RC-RESOURCE-SCOPES-1
test "zero RC fallible file scopes borrow named helper providers through propagation" {
    try executes(std.testing.allocator,
        \\import strings
        \\import filesystem
        \\func read(fs: Filesystem, path: str, fail: bool) -> int fails str:
        \\    with try fs.open(path, "rb") as file:
        \\        if fail:
        \\            fail "inside"
        \\        return len(file.read(16))
        \\func nested(fs: Filesystem) -> int fails str:
        \\    with try fs.open("outer", "w") as outer:
        \\        _ = outer.write("saved")
        \\        with try fs.open("missing", "r") as inner:
        \\            return strings.char_count(inner.read())
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    with fs.open("data", "w") as file:
        \\        _ = file.write("abc")
        \\    match read(fs, "data", False):
        \\        case Ok(size):
        \\            print(out, size)
        \\        case Err(message):
        \\            print(out, message)
        \\    match read(fs, "data", True):
        \\        case Ok(size):
        \\            print(out, size)
        \\        case Err(message):
        \\            print(out, message)
        \\    match nested(fs):
        \\        case Ok(size):
        \\            print(out, size)
        \\        case Err(message):
        \\            print(out, "missing")
        \\    with fs.open("outer", "r") as outer:
        \\        print(out, outer.read())
        \\    return 0
    , "3\ninside\nmissing\nsaved\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionary parameter mutation and key iteration borrow their owner" {
    try executes(std.testing.allocator,
        \\func replace(mut values: dict[str, str[]], key: str):
        \\    values[copy(key)] = ["replacement-" + str(7)]
        \\    _ = append(mut values["key-1"], "second-" + str(8))
        \\
        \\func score(values: dict[str, str[]]) -> int:
        \\    mut total = 0
        \\    for key in values:
        \\        total += len(values[key])
        \\    return total
        \\
        \\func main(out: Stream) -> int:
        \\    mut values = {"key-" + str(1): ["initial-" + str(2)]}
        \\    replace(mut values, "key-1")
        \\    print(out, score(values), values["key-1"][0], values["key-1"][1])
        \\    return 0
    , "2 replacement-7 second-8\n");
}

// spec-case: NEW-CORE-ZERO-RC-RESOURCES-1
test "zero RC entry provider cleanup directly destroys the root capability" {
    try executes(std.testing.allocator,
        \\func main(fs: Filesystem) -> int:
        \\    with fs.read_only() as readonly:
        \\        assert True
        \\    return 0
    , "");
}

// spec: NEW-CORE-ZERO-RC-RESOURCES-1
test "zero RC scoped files keep a local provider alive through early return" {
    try executes(std.testing.allocator,
        \\import filesystem
        \\func my_write(fs: Filesystem, fail: bool) -> int fails str:
        \\    with fs.open("log.txt", "w") as file:
        \\        _ = file.write("saved")
        \\        if fail:
        \\            fail "failed"
        \\        return 7
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    match my_write(fs, True):
        \\        case Ok(value):
        \\            print(out, value)
        \\        case Err(message):
        \\            print(out, message)
        \\    with fs.open("log.txt", "r") as file:
        \\        print(out, file.read())
        \\    return 0
    , "failed\nsaved\n");
}

// spec: NEW-CORE-ZERO-RC-RESOURCE-SCOPES-1
test "zero RC scoped capabilities (5C) return narrowed handles and close nested files" {
    // A narrowing is a new handle: it may leave its `with` scope or be made without one, and it stays narrow.
    try executes(std.testing.allocator,
        \\import filesystem
        \\func scoped(fs: Filesystem) -> Filesystem:
        \\    with fs.dir("logs") as child:
        \\        return child
        \\func plain(fs: Filesystem) -> Filesystem:
        \\    return fs.dir("logs")
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    _ = fs.mkdir("logs")
        \\    _ = fs.write_text("top.txt", "outside")
        \\    _ = scoped(fs).write_text("one.txt", "inside")
        \\    print(out, fs.exists("logs/one.txt"), plain(fs).exists("one.txt"), plain(fs).exists("top.txt"))
        \\    return 0
    , "True True False\n");
    try executes(std.testing.allocator,
        \\import strings
        \\import filesystem
        \\func run(fs: Filesystem) -> int fails str:
        \\    _ = fs.mkdir("logs")
        \\    with fs.dir("logs") as logs:
        \\        with logs.open("one.txt", "w") as file:
        \\            _ = file.write("saved")
        \\        with logs.read_only() as readonly:
        \\            with readonly.open("one.txt", "r") as file:
        \\                assert file.read() == "saved"
        \\                _ = try fs.read_text("missing.txt")
        \\        return 1
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    match run(fs):
        \\        case Ok(value):
        \\            print(out, value)
        \\        case Err(message):
        \\            print(out, strings.char_count(message) > 0)
        \\    print(out, fs.exists("logs/one.txt"))
        \\    return 0
    , "True\nTrue\n");
}

// spec-case: NEW-CORE-ZERO-RC-RESOURCES-1
test "zero RC foreign scalar calls carry no managed ownership" {
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip intentional original effect/noalloc retirement diagnostic
        \\extern func labs(host: Host, value: i64) -> i64 effects(host)
        \\func main(host: Host, out: Stream) -> int:
        \\    print(out, labs(host, -17))
        \\    return 0
    , "E_EFFECTS_REMOVED");
    try executes(std.testing.allocator,
        \\extern func labs(host: Host, value: i64) -> i64
        \\func main(host: Host, out: Stream) -> int:
        \\    print(out, labs(host, -17))
        \\    return 0
    , "17\n");
}

// spec: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC library text helpers preserve independent results" {
    try executesProject(std.testing.allocator,
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    mut source = "  aλb-" + str(7) + "  "
        \\    const trimmed = copy(strings.strip(source))
        \\    const upper = strings.upper(trimmed)
        \\    const changed = strings.replace(trimmed, "b", "B")
        \\    const words = strings.split(trimmed, "λ")
        \\    const joined = strings.join(words, "/")
        \\    const spaced = strings.words((trimmed + "\t" + trimmed))
        \\    const lines = strings.lines(trimmed + "\r\n" + trimmed)
        \\    const reverse = strings.char_stride(trimmed, None, None, -1)
        \\    source = "changed"
        \\    print(out, trimmed, upper, changed, joined, reverse)
        \\    print(out, len(spaced), len(lines), strings.zfill("7", 3), chr(955), ord(chr(955)))
        \\    print(out, strings.lower("Ab"), strings.is_digit("123"), strings.is_alpha("Ab"), strings.is_space(" \t"))
        \\    print(out, strings.char_find(trimmed, "b"), strings.char_rfind(trimmed, "b"), strings.count(trimmed, "λ"))
        \\    print(out, f"{trimmed:>6}")
        \\    return 0
    , "aλb-7 AλB-7 aλB-7 a/b-7 7-bλa\n2 2 007 λ 955\nab True True True\n2 2 1\n aλb-7\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC library byte helpers preserve independent results" {
    try executesProject(std.testing.allocator,
        \\import bytes
        \\import hex
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    mut source = strings.encode(" λ-7 ")
        \\    const trimmed = bytes.strip(source)
        \\    const saved = hex.encode(trimmed)
        \\    const tail = trimmed[1:]
        \\    const decoded = strings.decode(trimmed)
        \\    const parsed = hex.decode(saved)
        \\    source = b"changed"
        \\    print(out, saved, hex.encode(tail), bytes.find(trimmed, b"-"))
        \\    match decoded:
        \\        case Ok(text):
        \\            print(out, text)
        \\        case Err(error):
        \\            print(out, error)
        \\    match parsed:
        \\        case Ok(data):
        \\            print(out, hex.encode(data))
        \\        case Err(error):
        \\            print(out, error)
        \\    match strings.decode(b"\xff"):
        \\        case Ok(text):
        \\            print(out, text)
        \\        case Err(error):
        \\            print(out, strings.char_count(error) > 0)
        \\    return 0
    , "cebb2d37 bb2d37 2\nλ-7\ncebb2d37\nTrue\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC library environment preserve independent results" {
    try executes(std.testing.allocator,
        \\import dicts
        \\import environment
        \\func main(out: Stream) -> int:
        \\    mut values = {"NAME": "value-" + str(7)}
        \\    const env = environment.fixed(values)
        \\    dicts.clear(mut values)
        \\    print(out, len(env.names()))
        \\    match env.get("NAME"):
        \\        case Some(value):
        \\            print(out, value)
        \\        case None:
        \\            print(out, "missing")
        \\    return 0
    , "1\nvalue-7\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC explicit value copies support generic records and scalar values" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\record Item:
        \\    texts: str[]
        \\func clone[T: copy + storable](value: T) -> T:
        \\    return copy(value)
        \\func main(out: Stream) -> int:
        \\    mut item = Item(texts=["value-" + str(7)])
        \\    const saved = clone(item)
        \\    lists.clear(mut item.texts)
        \\    print(out, len(item.texts), saved.texts[0], clone(42))
        \\    return 0
    , "0 value-7 42\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC indexed writes permit bounds reads and copies of indexed text" {
    try removedNegativeIndexesThenExecutes(std.testing.allocator,
        // migrate-embedded: skip intentional pre-removal source; repair is tested below
        \\import lists
        \\import strings
        \\record State:
        \\    values: str[]
        \\func update(mut s: State):
        \\    s.values[-1] = copy(s.values[0])
        \\func encoded() -> bytes:
        \\    return strings.encode("abc")
        \\func main(out: Stream) -> int:
        \\    mut s = State(values=["value-" + str(7), "other"])
        \\    update(mut s)
        \\    const saved = copy(s.values[-1])
        \\    lists.clear(mut s.values)
        \\    print(out, saved, len(encoded()))
        \\    return 0
    , "value-7 3\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC encoding borrowed text allocates independent owned bytes" {
    try executes(std.testing.allocator,
        \\import hex
        \\import strings
        \\
        \\func encoded_size(text: str) -> int:
        \\    const data = strings.encode(text)
        \\    return len(data)
        \\func encode(text: str) -> bytes:
        \\    return strings.encode(text)
        \\func main(out: Stream) -> int:
        \\    mut text = "key-" + str(7)
        \\    print(out, encoded_size(text), text)
        \\    const saved = encode(text)
        \\    text = "replacement-" + str(8)
        \\    print(out, hex.encode(saved), text)
        \\    return 0
    , "5 key-7\n6b65792d37 replacement-8\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC direct enum and fixed array copies keep their owned children" {
    try executes(std.testing.allocator,
        \\enum Value:
        \\    text(value: str)
        \\func clone(value: Value) -> Value:
        \\    return copy(value)
        \\func show(out: Stream, value: Value):
        \\    match value:
        \\        case text(value=text):
        \\            print(out, text)
        \\func main(out: Stream) -> int:
        \\    mut source = Value.text(value="value-" + str(7))
        \\    const saved = clone(source)
        \\    source = Value.text(value="other")
        \\    show(out, saved)
        \\    mut array = FixedArray[str, 2](["first-" + str(1), "second"])
        \\    const copied = copy(array)
        \\    array[0] = "changed"
        \\    print(out, copied[0], array[0])
        \\    return 0
    , "value-7\nfirst-1 changed\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC keyed sort copies nested values and text keys independently" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\record Item:
        \\    name: str
        \\    values: int[]
        \\func key(item: Item) -> str:
        \\    return copy(item.name)
        \\func main(out: Stream) -> int:
        \\    mut values = [Item(name="b-" + str(1), values=[2]), Item(name="a-" + str(1), values=[1])]
        \\    const ordered = sorted(values, key=key)
        \\    lists.clear(mut values)
        \\    print(out, ordered[0].name, ordered[0].values[0], ordered[1].values[0])
        \\    return 0
    , "a-1 1 2\n");
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-2
test "zero RC source map rejects a callback returning a borrowed owner" {
    // `alias` returns a valid text view, so Core refuses its owned function value.
    try refusesOwnership(std.testing.allocator,
        \\import parallel
        \\func alias(value: str) -> str from value:
        \\    return value[0:len(value)]
        \\func main() -> int:
        \\    const result = parallel.map(["item-" + str(1)], alias)
        \\    return len(result)
    , "E_VIEW_FUNCTION_VALUE", .V4);
}

test "zero RC source map keeps an invalid borrowed callback body refusal" {
    try refusesOwnership(std.testing.allocator,
        \\import parallel
        \\func alias(value: str) -> str:
        \\    return value
        \\func main() -> int:
        \\    const result = parallel.map(["item-" + str(1)], alias)
        \\    return len(result)
    , "E_BORROW_UNDECLARED", .R4);
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC copies recursive list and dictionary graphs without compiler expansion" {
    try executes(std.testing.allocator,
        \\enum Tree:
        \\    leaf(value: str)
        \\    branch(children: Tree[])
        \\    mapping(children: dict[str, Tree])
        \\func score(value: Tree) -> int:
        \\    match value:
        \\        case leaf(value=text):
        \\            return strings.char_count(text)
        \\        case branch(children=children):
        \\            return 1 + score(children[0])
        \\        case mapping(children=children):
        \\            return 1 + score(children["next"])
        \\func main(out: Stream) -> int:
        \\    mut value = Tree.leaf(value="value-" + str(7))
        \\    for i in range(200):
        \\        value = Tree.branch(children=[Tree.mapping(children={"next": own value})])
        \\    const saved = copy(value)
        \\    value = Tree.leaf(value="replaced")
        \\    print(out, score(saved))
        \\    return 0
    , "407\n");
}

test "zero RC function values with capability signatures are stored, read and called" {
    try executes(std.testing.allocator,
        \\import filesystem
        \\
        \\record Evaluator:
        \\    depth: int
        \\    read: func(mut state: Evaluator, fs: Filesystem, n: int) -> int fails str
        \\
        \\record Holder:
        \\    label: str
        \\    make: func(path: str) -> Filesystem
        \\
        \\func read_size(mut state: Evaluator, fs: Filesystem, n: int) -> int fails str:
        \\    state.depth += n
        \\    const text = try fs.read_text("data.txt")
        \\    return len(text) + state.depth
        \\
        \\func memory(path: str) -> Filesystem:
        \\    return filesystem.memory()
        \\
        \\func apply(hook: func(mut state: Evaluator, fs: Filesystem, n: int) -> int fails str, mut state: Evaluator, fs: Filesystem, n: int) -> int fails str:
        \\    return try hook(mut state, fs, n)
        \\
        \\func main(out: Stream) -> int:
        \\    mut ev = Evaluator(depth=0, read=read_size)
        \\    const fs = filesystem.memory()
        \\    _ = fs.write_text("data.txt", "hello")
        \\    const holder = Holder(label="memory", make=memory)
        \\    const make = holder.make
        \\    const made = make("unused")
        \\    _ = made.write_text("data.txt", "hi")
        \\    match apply(read_size, mut ev, fs, 3):
        \\        case Ok(value):
        \\            print(out, value, holder.label, made.exists("data.txt"))
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    , "8 memory True\n");
}

test "zero RC still refuses owners and slices stored beyond capability signatures" {
    // A capability is a scalar handle (5C): an enum case may hold one.
    try executes(std.testing.allocator,
        \\import filesystem
        \\
        \\enum Slot:
        \\    held(fs: Filesystem)
        \\    empty
        \\
        \\func main(out: Stream) -> int:
        \\    const slot = Slot.held(fs=filesystem.memory())
        \\    match slot:
        \\        case held(fs):
        \\            print(out, fs.exists("x"))
        \\        case empty:
        \\            pass
        \\    return 0
    , "False\n");
    try refuses(std.testing.allocator,
        \\import filesystem
        \\
        \\record Reader:
        \\    read: func(own file: TextFile) -> int
        \\
        \\func count(own file: TextFile) -> int:
        \\    return 0
        \\
        \\func main() -> int:
        \\    const reader = Reader(read=count)
        \\    return 0
    , "E_WITH_RESOURCE");
    try refuses(std.testing.allocator,
        \\record Keep:
        \\    parts: str[]
        \\
        \\func main() -> int:
        \\    const text = "abcdef"
        \\    const keep = Keep(parts=[text[0:2]])
        \\    return len(keep.parts)
    , "E_SLICE_ESCAPES");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC copied records preserve function values without owning them" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\record Item:
        \\    text: str
        \\    read: func(int) -> int
        \\func twice(value: int) -> int:
        \\    return value * 2
        \\func main(out: Stream) -> int:
        \\    mut items = [Item(text="item-" + str(7), read=twice)]
        \\    const saved = copy(items)
        \\    lists.clear(mut items)
        \\    const function = saved[0].read
        \\    print(out, saved[0].text, function(21))
        \\    return 0
    , "item-7 42\n");
}

// spec: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer preserves recursive success errors and mutable writebacks" {
    try executes(std.testing.allocator,
        \\enum Tree:
        \\    leaf(items: dict[str, str[]])
        \\    node(child: Tree)
        \\func score(tree: Tree) -> int:
        \\    match tree:
        \\        case leaf(items=items):
        \\            return strings.char_count(items["key-1"][0])
        \\        case node(child=child):
        \\            return 1 + score(child)
        \\func make(mut count: int, fail: bool) -> Tree fails str:
        \\    count += 1
        \\    if fail:
        \\        fail "failure-" + str(count)
        \\    mut tree = Tree.leaf(items={"key-" + str(1): ["value-" + str(1)]})
        \\    for i in range(40):
        \\        tree = Tree.node(child=own tree)
        \\    return tree
        \\func forward(mut count: int, fail: bool) -> Tree fails str:
        \\    const tree = try make(mut count, fail)
        \\    return tree
        \\func run(mut count: int, fail: bool) -> int fails str:
        \\    const tree = try forward(mut count, fail)
        \\    const saved = copy(tree)
        \\    return score(tree) + score(saved)
        \\func main(out: Stream) -> int:
        \\    mut count = 0
        \\    for i in range(3):
        \\        match run(mut count, i == 1):
        \\            case Ok(value):
        \\                print(out, value)
        \\            case Err(message):
        \\                print(out, message)
        \\    print(out, count)
        \\    return 0
    , "94\nfailure-2\n94\n3\n");
}

// spec-case: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer handles wide option values phis and discarded owners" {
    try executes(std.testing.allocator,
        \\record Wide:
        \\    a: str
        \\    b: str
        \\    c: str
        \\    d: str
        \\    e: str
        \\func make(n: int) -> Wide?:
        \\    if n == 0:
        \\        return None
        \\    return Some(Wide(a="a-" + str(n), b="b-" + str(n), c="c-" + str(n), d="d-" + str(n), e="e-" + str(n)))
        \\func forward(n: int) -> Wide?:
        \\    mut result = make(n)
        \\    if n > 2:
        \\        result = make(n + 1)
        \\    const value = try own result
        \\    return Some(own value)
        \\func discard(n: int) -> int?:
        \\    _ = try make(n)
        \\    return Some(7)
        \\func main(out: Stream) -> int:
        \\    for i in range(4):
        \\        match forward(i):
        \\            case Some(value):
        \\                print(out, value.a, value.e)
        \\            case None:
        \\                print(out, "none")
        \\        match discard(i):
        \\            case Some(value):
        \\                print(out, value)
        \\            case None:
        \\                print(out, "empty")
        \\    return 0
    , "none\nempty\na-1 e-1\n7\na-2 e-2\n7\na-4 e-4\n7\n");
}

// spec: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers success errors callbacks and popped payloads" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\func make(mut count: int, fail: bool) -> str[] fails str:
        \\    count += 1
        \\    if fail:
        \\        fail "error-" + str(count)
        \\    return ["item-" + str(count)]
        \\func forward(mut count: int, fail: bool) -> str[] fails str:
        \\    match make(mut count, fail):
        \\        case Ok(items):
        \\            return items
        \\        case Err(message):
        \\            fail message
        \\func text(n: int) -> str?:
        \\    if n == 0:
        \\        return None
        \\    return Some("text-" + str(n))
        \\func invoke(f: func(int) -> str?, n: int) -> str:
        \\    match f(n):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            return "none"
        \\func main(out: Stream) -> int:
        \\    mut count = 0
        \\    mut saved: str[] = []
        \\    for i in range(3):
        \\        match forward(mut count, i == 1):
        \\            case Ok(items):
        \\                saved = own items
        \\            case Err(message):
        \\                append(mut saved, own message)
        \\        print(out, saved[0], len(saved))
        \\    mut values: str?[] = [text(7)]
        \\    match lists.pop(mut values):
        \\        case Some(value):
        \\            append(mut saved, own value)
        \\        case None:
        \\            assert False
        \\    print(out, saved[0], saved[1], invoke(text, 0), invoke(text, 8), count)
        \\    return 0
    , "item-1 1\nitem-1 2\nitem-3 1\nitem-3 text-7 none text-8 3\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match rejects repeated moves and keeps named matches borrowed" {
    try refuses(std.testing.allocator,
        \\func make() -> str?:
        \\    return Some("item-" + str(1))
        \\func main() -> int:
        \\    match make():
        \\        case Some(value):
        \\            const saved = own value
        \\            return strings.char_count(saved) + strings.char_count(value)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_MOVED");
    // A named match lends its payload; putting it in owning storage is refused (a bare `mut moved = value` read alone
    // borrows it since D4, so the binding is given a fresh value too).
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const saved: str? = Some("item-" + str(1))
        \\    match saved:
        \\        case Some(value):
        \\            mut moved = value
        \\            moved = moved + "!"
        \\            return strings.char_count(moved)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match still borrows projected unions" {
    try refuses(std.testing.allocator,
        \\record Holder:
        \\    value: str?
        \\func make() -> Holder:
        \\    return Holder(value=Some("item-" + str(1)))
        \\func main() -> int:
        \\    match make().value:
        \\        case Some(value):
        \\            mut moved = value
        \\            moved = moved + "!"
        \\            return strings.char_count(moved)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values: str?[] = [Some("item-" + str(1))]
        \\    match values[0]:
        \\        case Some(value):
        \\            mut moved = value
        \\            moved = moved + "!"
        \\            return strings.char_count(moved)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match moves explicit copies independently and discards unused cases" {
    try executes(std.testing.allocator,
        \\func make(n: int) -> str[]?:
        \\    return Some(["item-" + str(n)])
        \\func main(out: Stream) -> int:
        \\    mut original = make(1)
        \\    mut saved: str[] = []
        \\    match copy(original):
        \\        case Some(value):
        \\            saved = own value
        \\        case None:
        \\            assert False
        \\    original = make(2)
        \\    match make(3):
        \\        case Some(_):
        \\            print(out, saved[0], len(saved))
        \\        case None:
        \\            assert False
        \\    match make(4):
        \\        case Some(unused):
        \\            print(out, saved[0], len(saved))
        \\        case None:
        \\            assert False
        \\    match original:
        \\        case Some(value):
        \\            print(out, value[0])
        \\        case None:
        \\            assert False
        \\    return 0
    , "item-1 1\nitem-1 1\nitem-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers constructed unions through loop exits" {
    try executes(std.testing.allocator,
        \\enum Item:
        \\    text(value: str[])
        \\func forward(n: int) -> str[] fails str:
        \\    if n == 0:
        \\        return []
        \\    if n == 1:
        \\        fail "error-" + str(n)
        \\    return ["item-" + str(n)]
        \\func main(out: Stream) -> int:
        \\    mut saved: str[] = []
        \\    for i in range(4):
        \\        match forward(i):
        \\            case Ok(items):
        \\                if len(items) == 0:
        \\                    continue
        \\                saved = own items
        \\                break
        \\            case Err(message):
        \\                print(out, message)
        \\    match Item.text(value=["extra-" + str(7)]):
        \\        case text(value=items):
        \\            print(out, saved[0], items[0])
        \\    return 0
    , "error-1\nitem-2 extra-7\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers decoded text bytes and validation errors" {
    try executesProject(std.testing.allocator,
        \\import bytes
        \\import strings
        \\
        \\func decode(data: bytes) -> str:
        \\    match strings.decode(data):
        \\        case Ok(text):
        \\            return text
        \\        case Err(message):
        \\            return message
        \\func hex(text: str) -> bytes fails str:
        \\    match bytes.fromhex(text):
        \\        case Ok(data):
        \\            return data
        \\        case Err(message):
        \\            fail message
        \\func count(data: bytes) -> str:
        \\    match bytes.scalar_count(data):
        \\        case Ok(size):
        \\            return str(size)
        \\        case Err(message):
        \\            return message
        \\func main(out: Stream) -> int:
        \\    print(out, decode(bytes([97, 98])), decode(bytes([255])))
        \\    print(out, count(bytes([97, 98])), count(bytes([255])))
        \\    match hex("6162"):
        \\        case Ok(data):
        \\            print(out, decode(data))
        \\        case Err(message):
        \\            print(out, message)
        \\    match hex("z"):
        \\        case Ok(data):
        \\            print(out, decode(data))
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    , "ab invalid UTF-8 in byte string\n2 invalid UTF-8 in byte string\nab\nhexadecimal text requires an even number of hex digits\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match JSON decoding and rendering return owned strings" {
    try executes(std.testing.allocator,
        \\import json
        \\func main(out: Stream) -> int:
        \\    match json.loads("\"item\""):
        \\        case Ok(value):
        \\            print(out, json.dumps(value))
        \\        case Err(_):
        \\            assert False
        \\    return 0
    , "\"item\"\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC JSON lookup copies only selected values and preserves independent results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try std.fs.path.join(a, &.{ @import("core_test_options").fixtures, "zero_rc_json_lookup.selka" });
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 20));
    try executes(a, source, json_lookup_output);
}

const json_lookup_output =
    "null 2\n" ++
    "[{\"nested\":\"value-7\"}] {\"nested\":[\"value-9\"]}\n" ++
    "[{\"nested\":\"value-7\"}] {\"nested\":[\"value-9\"]}\n" ++
    "{\"target\":\"changed\"} [\"changed\"]\n";

// spec: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC affine resource parameters and local matches transfer owners" {
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip intentional original effect/noalloc retirement diagnostic
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\record Owned:
        \\    file: File
        \\    code: int
        \\func forward(file: File) -> File effects(filesystem):
        \\    return file
        \\func fields(value: Owned) -> int effects(filesystem):
        \\    _ = value
        \\    return 7
        \\func handle(result: Open) -> int effects(filesystem):
        \\    match result:
        \\        case ok(file):
        \\            return fields(Owned(file=forward(file), code=7))
        \\        case err(code):
        \\            return code
        \\func open(fs: Filesystem) -> Open:
        \\    const request = FixedArray[u8, 6]([114u8, 58u8, 100u8, 97u8, 116u8, 97u8])
        \\    return acquire_resource[Open](fs, request)
        \\func main(out: Stream) -> int:
        \\    const original = filesystem.memory()
        \\    mut fs = original
        \\    with fs.open("data", "w") as file:
        \\        _ = file.write("abc")
        \\    print(out, handle(open(fs)))
        \\    fs = filesystem.memory()
        \\    print(out, fs.exists("data"))
        \\    return 0
    , "E_EFFECTS_REMOVED");
    try executes(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\record Owned:
        \\    file: File
        \\    code: int
        \\func forward(own file: File) -> File:
        \\    return file
        \\func fields(own value: Owned) -> int:
        \\    _ = own value
        \\    return 7
        \\func handle(own result: Open) -> int:
        \\    match own result:
        \\        case ok(file):
        \\            return fields(Owned(file=forward(own file), code=7))
        \\        case err(code):
        \\            return code
        \\func open(fs: Filesystem) -> Open:
        \\    const request = FixedArray[u8, 6]([114u8, 58u8, 100u8, 97u8, 116u8, 97u8])
        \\    return acquire_resource[Open](fs, request)
        \\func main(out: Stream) -> int:
        \\    const original = filesystem.memory()
        \\    mut fs = own original
        \\    with fs.open("data", "w") as file:
        \\        _ = file.write("abc")
        \\    print(out, handle(open(fs)))
        \\    fs = filesystem.memory()
        \\    print(out, fs.exists("data"))
        \\    return 0
    , "7\nFalse\n");
}

// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC dependent resource returns reject local and ambiguous providers" {
    try refuses(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func escape(unused: Filesystem) -> Open:
        \\    _ = unused.exists("unused")
        \\    const local = filesystem.memory()
        \\    return acquire_resource[Open](local, FixedArray[u8, 0]([]))
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ESCAPE");
    try refuses(std.testing.allocator,
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func ambiguous(first: Filesystem, second: Filesystem) -> Open:
        \\    _ = second.exists("unused")
        \\    return acquire_resource[Open](first, FixedArray[u8, 0]([]))
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN");
}

// R3-RESORIGIN (friction F-3), RES-ORIGIN-2 (FR90): a function that returns a resource without exactly one input its result can come
// from is refused with the inputs it counted, in source order, and what to write; a `Clock` and a provider of the other kind are not
// counted, and a resource whose operations take it `own` (a `Poller`) is not told to take it `mut`.
test "zero RC a resource result names the inputs it counted and what to write for a network, a file and a poller" {
    try refusesWithMessage(std.testing.allocator,
        \\import network
        \\import time
        \\func on_event(mut held: network.Poller, clock: Clock, net: Network) -> network.Polling:
        \\    _ = time.monotonic(clock)
        \\    return network.open_client_poller(net)
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN", "`on_event` returns a resource, so it takes exactly one input the result can come from (a `Network` or a " ++
        "resource), and it takes 2: `held: network.Poller`, `net: Network`. Take `held` as `own`: an `own` input of the result's type " ++
        "is the one it comes from, and the providers beside it are not counted.");
    try refusesWithMessage(std.testing.allocator,
        \\import network
        \\func two(net: Network, other: Network) -> network.Polling:
        \\    _ = other.host("127.0.0.1:9")
        \\    return network.open_client_poller(net)
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN", "`two` returns a resource, so it takes exactly one input the result can come from (a `Network` or a " ++
        "resource), and it takes 2: `net: Network`, `other: Network`. Keep the one the result comes from and take the others out of the " ++
        "parameters: do the work that needs `net` and `other` together in a function that returns a `bool` or an `int`, which may take " ++
        "any number of inputs.");
    try refusesWithMessage(std.testing.allocator,
        \\func pick(own first: File, own second: File) -> File:
        \\    return first
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN", "`pick` returns a resource, so it takes exactly one input the result can come from (a `Filesystem` or a " ++
        "resource), and it takes 2: `first: File`, `second: File`. Keep the one the result comes from and take the others out of the " ++
        "parameters: do the work that needs `first` and `second` together in a function that returns a `bool` or an `int`, which may " ++
        "take any number of inputs (take `first` and `second` as `mut`).");
    try refusesWithMessage(std.testing.allocator,
        \\import network
        \\func pick(own first: network.Poller, own second: network.Poller, root: Filesystem) -> network.Poller:
        \\    _ = own second
        \\    _ = root.exists("x")
        \\    return first
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN", "`pick` returns a resource, so it takes exactly one input the result can come from (a `Network` or a " ++
        "resource), and it takes 2: `first: network.Poller`, `second: network.Poller`. Keep the one the result comes from and take the " ++
        "others out of the parameters: do the work that needs `first` and `second` together in a function that returns a `bool` or an " ++
        "`int`, which may take any number of inputs: that function takes `first` and `second` as `own`, which every operation on a " ++
        "resource can use, and keeps the other work there.");
    try refusesWithMessage(std.testing.allocator,
        \\func reopen(mut file: File, root: Filesystem) -> File fails str:
        \\    _ = file.read()
        \\    return try root.open("x", "rb")
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN", "`reopen` returns a resource, so it takes exactly one input the result can come from (a `Filesystem` or a " ++
        "resource), and it takes 2: `file: File`, `root: Filesystem`. Take `file` as `own`: an `own` input of the result's type is the " ++
        "one it comes from, and the providers beside it are not counted.");
    try refusesWithMessage(std.testing.allocator,
        \\resource Ticket: filesystem
        \\result Open:
        \\    ok: Ticket,
        \\    err: int
        \\func make() -> Open:
        \\    return Open.err(1)
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ORIGIN", "`make` returns a resource, so it takes exactly one input the result can come from (a `Filesystem` or a " ++
        "resource), and it takes none: add as its one input the provider the resource is acquired from, or the resource it continues");
    try accepts(std.testing.allocator,
        \\import network
        \\func on_event(own held: network.Poller, now: int) -> network.Poller:
        \\    _ = now
        \\    return held
        \\func dial_slot(mut live: network.Poller, net: Network, mut outcome: network.Outcome) -> bool:
        \\    network.dial(mut live, net, mut outcome)
        \\    return outcome.code == network.OUTCOME_OK
        \\func main() -> int:
        \\    return 0
    );
}

// RES-ORIGIN-2 (FR90): the shapes four programs first wrote are accepted; the origin is still read from the signature alone,
// and a body that returns a resource from an input that is not the origin is still refused at its `return`.
test "zero RC a resource result's origin is its own input of that type or its one provider of that kind" {
    try accepts(std.testing.allocator,
        \\import network
        \\import time
        \\record Conn:
        \\    id: int
        \\    size: int = 0
        \\record Run:
        \\    events: int = 0
        \\func step(own live: network.Poller, root: Filesystem) -> network.Poller:
        \\    _ = root.exists("x")
        \\    return live
        \\func advance(own poller: network.Poller, id: int, mut conn: Conn, root: Filesystem) -> network.Poller:
        \\    if root.exists("x"):
        \\        conn.size = 1
        \\    mut outcome = network.new_outcome()
        \\    return network.port(own poller, id, mut outcome)
        \\func on_event(own held: network.Poller, mut st: Run, clock: Clock) -> network.Poller:
        \\    if time.monotonic(clock) >= 0:
        \\        st.events += 1
        \\    return held
        \\func dial_slot(own live: network.Poller, net: Network, other: Network) -> network.Poller:
        \\    mut outcome = network.new_outcome()
        \\    network.dial_to(mut live, net, "127.0.0.1:9", mut outcome)
        \\    _ = other.host("127.0.0.1:9")
        \\    return live
        \\func open_server(net: Network, fs: Filesystem, clock: Clock) -> network.Polling:
        \\    _ = fs.exists("config")
        \\    _ = time.monotonic(clock)
        \\    return network.open_client_poller(net)
        \\func reopen(own file: File, root: Filesystem) -> File fails str:
        \\    _ = root.exists("x")
        \\    return file
        \\func serve(net: Network, root: Filesystem, clock: Clock) -> int:
        \\    match open_server(net, root, clock):
        \\        case ok(opened):
        \\            mut live = own opened
        \\            mut conn = Conn(id=0)
        \\            mut st = Run()
        \\            for _ in range(3):
        \\                live = step(own live, root)
        \\                live = advance(own live, 0, mut conn, root)
        \\                live = on_event(own live, mut st, clock)
        \\                live = dial_slot(own live, net, net)
        \\            _ = own live
        \\            return st.events
        \\        case err(code):
        \\            return code
        \\func main() -> int:
        \\    return 0
    );
    // A function the count before RES-ORIGIN-2 accepted keeps its one input as the origin, though a `Clock` is not counted now.
    try accepts(std.testing.allocator,
        \\import network
        \\func none_yet(clock: Clock) -> network.Polling:
        \\    _ = clock
        \\    return Err(1)
        \\func main() -> int:
        \\    return 0
    );
    try refusesOwnership(std.testing.allocator,
        \\import network
        \\func dial_slot(own live: network.Poller, net: Network) -> network.Polling:
        \\    _ = own live
        \\    return network.open_client_poller(net)
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ESCAPE", .P3);
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC scalar text conversions and characters have fresh receiver origins" {
    try executes(std.testing.allocator,
        \\import strings
        \\
        \\func main(out: Stream) -> int:
        \\    mut total = 0
        \\    for value in [0.1, 2.5]:
        \\        const encoded = strings.encode(str(value))
        \\        total += len(encoded)
        \\    mut gather_result_172: str[] = []
        \\    for letter in strings.chars("abc"):
        \\        const gather_value_172: str = own letter
        \\        append(mut gather_result_172, own gather_value_172)
        \\    const letters = gather_result_172
        \\    print(out, total, letters[1])
        \\    return 0
    , "6 b\n");
}

// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC affine resource cleanup covers completion propagation and loop exits" {
    try executes(std.testing.allocator,
        \\import filesystem
        \\
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\record Failure:
        \\    resource: File
        \\    code: int
        \\result Finish:
        \\    ok: bool,
        \\    err: Failure
        \\func request() -> FixedArray[u8, 6]:
        \\    return FixedArray[u8, 6]([114u8, 58u8, 100u8, 97u8, 116u8, 97u8])
        \\func open(fs: Filesystem) -> Open:
        \\    return acquire_resource[Open](fs, request())
        \\func finish(own file: File) -> Finish:
        \\    return complete_resource[Finish](own file)
        \\func attempt(fs: Filesystem) -> int:
        \\    match open(fs):
        \\        case ok(file):
        \\            match finish(own file):
        \\                case ok(done):
        \\                    if done:
        \\                        return 7
        \\                    return 0
        \\                case err(failure):
        \\                    const code = failure.code
        \\                    return code
        \\        case err(code):
        \\            return code
        \\func partial(fs: Filesystem) -> int fails int:
        \\    const first = try open(fs)
        \\    const second = try acquire_resource[Open](fs, FixedArray[u8, 3]([114u8, 58u8, 120u8]))
        \\    _ = own first
        \\    _ = own second
        \\    return 1
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    with fs.open("data", "w") as file:
        \\        _ = file.write("abc")
        \\    print(out, attempt(fs))
        \\    with fs.read_only() as readonly:
        \\        print(out, attempt(readonly))
        \\        _ = open(readonly)
        \\    match partial(fs):
        \\        case Ok(code):
        \\            print(out, code)
        \\        case Err(code):
        \\            print(out, code)
        \\    for i in range(20):
        \\        _ = open(fs)
        \\        if i < 3:
        \\            continue
        \\        break
        \\    _ = open(fs)
        \\    fs = filesystem.memory()
        \\    print(out, fs.exists("data"))
        \\    return 0
    , "7\n2\n3\nFalse\n");
}

// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC affine resources (5C) survive replacing their provider's binding" {
    // A capability is a handle the runtime keeps until the process ends, so a live resource still reaches the provider
    // it came from after the binding names another one, and releasing it needs no check.
    try executes(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func open(fs: Filesystem) -> Open:
        \\    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    const live = open(fs)
        \\    fs = filesystem.memory()
        \\    _ = own live
        \\    print(out, fs.exists("x"))
        \\    return 0
    , "False\n");
}

// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC affine resources reject scoped provider escape" {
    try refuses(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func open(fs: Filesystem) -> Open:
        \\    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
        \\func main() -> int:
        \\    const fs = filesystem.memory()
        \\    mut saved: Open = Err(0)
        \\    _ = own saved
        \\    with fs.read_only() as readonly:
        \\        saved = open(readonly)
        \\    _ = own saved
        \\    return 0
    , "E_RESOURCE_ESCAPE");
}

// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC affine resources (5C) let a sibling rebind the scalar provider handle" {
    try executes(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func open(fs: Filesystem) -> Open:
        \\    return acquire_resource[Open](fs, FixedArray[u8, 0]([]))
        \\record Owned:
        \\    child: Open
        \\    code: int
        \\func replace(mut fs: Filesystem) -> int:
        \\    fs = filesystem.memory()
        \\    return 1
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    const carrier = Owned(child=open(fs), code=replace(mut fs))
        \\    _ = own carrier
        \\    print(out, "rebound", fs.exists("x"))
        \\    return 0
    , "rebound False\n");
}

// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC builtin file results preserve named provider origins through helpers" {
    try refuses(std.testing.allocator,
        \\import filesystem
        \\func escape(fs: Filesystem) -> TextFile fails str:
        \\    _ = fs.exists("unused")
        \\    const local = filesystem.memory()
        \\    return try local.open("data", "w")
        \\func main() -> int:
        \\    return 0
    , "E_RESOURCE_ESCAPE");
    try executes(std.testing.allocator,
        \\import strings
        \\import filesystem
        \\@ensures(True)
        \\func opened(fs: Filesystem) -> TextFile fails str:
        \\    return try fs.open("data", "w")
        \\func my_write(fs: Filesystem, fail: bool) -> int fails str:
        \\    with try opened(fs) as file:
        \\        _ = file.write("hello")
        \\        if fail:
        \\            fail "early"
        \\    const text = try fs.read_text("data")
        \\    return strings.char_count(text)
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    match my_write(fs, False):
        \\        case Ok(size):
        \\            print(out, size)
        \\        case Err(message):
        \\            print(out, message)
        \\    match my_write(fs, True):
        \\        case Ok(size):
        \\            print(out, size)
        \\        case Err(message):
        \\            print(out, message)
        \\    return 0
    , "5\nearly\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC optional narrowing preserves hidden payload availability and mutation" {
    // A non-empty literal is a new value beside the borrow (R5); `return []` is neutral since 4e.
    try refuses(std.testing.allocator,
        \\func escape(value: int[]?) -> int[] from value:
        \\    if value is None:
        \\        return [0]
        \\    return value
        \\func main() -> int:
        \\    return len(escape(Some([1])))
    , "E_BORROW_MIXED");
    try executes(std.testing.allocator,
        \\record Node:
        \\    items: int[]
        \\    next: Node?
        \\func size(node: Node) -> int:
        \\    mut child = copy(node.next)
        \\    if child is None:
        \\        return len(node.items)
        \\    append(mut child.items, 9)
        \\    return len(node.items) + size(child)
        \\func main(out: Stream) -> int:
        \\    const root = Node(items=[1], next=Some(Node(items=[2], next=None)))
        \\    print(out, size(root), size(root))
        \\    return 0
    , "3 3\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionary default explicit copies select before the owning join" {
    try executes(std.testing.allocator,
        \\import dicts
        \\import strings
        \\
        \\enum Choice:
        \\    numbers(value: int[])
        \\    text(value: str)
        \\func fallback(mut calls: int, value: str) -> bytes:
        \\    calls += 1
        \\    return strings.encode(value)
        \\func main(out: Stream) -> int:
        \\    mut mapping = {"hit": b"stored"}
        \\    mut calls = 0
        \\    const hit = copy(dicts.get(mapping, "hit", fallback(mut calls, "ignored")))
        \\    const miss = copy(dicts.get(mapping, "miss", fallback(mut calls, "chosen")))
        \\    mut supplied = b"caller"
        \\    const independent = copy(dicts.get(mapping, "absent", supplied))
        \\    const nested = copy(dicts.get(mapping, "absent", dicts.get(mapping, "hit", supplied)))
        \\    dicts.clear(mut mapping)
        \\    supplied = b"changed"
        \\    assert calls == 2
        \\    assert hit == b"stored" and miss == b"chosen"
        \\    assert independent == b"caller" and nested == b"stored"
        \\    mut choices = {"hit": Choice.numbers(value=[1, 2])}
        \\    const selected = copy(dicts.get(choices, "hit", Choice.text(value="unused")))
        \\    dicts.clear(mut choices)
        \\    match selected:
        \\        case numbers(value=values):
        \\            print(out, len(values))
        \\        case text(value=value):
        \\            print(out, strings.char_count(value))
        \\    return 0
    , "2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC setdefault copies borrowed hit and inserted payloads independently" {
    // The borrowed result may be bound, but keeps the dictionary loan live.
    try refusesOwnership(std.testing.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut mapping = {"a": [1]}
        \\    const borrowed = dicts.setdefault(mut mapping, "a", [99])
        \\    dicts.clear(mut mapping)
        \\    return borrowed[0]
    , "E_SINGLE_OWNER_OVERLAP", .R2);
    try executes(std.testing.allocator,
        \\import dicts
        \\
        \\func fallback(mut calls: int, value: int) -> int[]:
        \\    calls += 1
        \\    return [value]
        \\func key(mut calls: int, value: str) -> str:
        \\    calls += 1
        \\    return copy(value)
        \\func main(out: Stream) -> int:
        \\    mut mapping = {"a": [1]}
        \\    mut key_calls = 0
        \\    mut value_calls = 0
        \\    const hit = copy(dicts.setdefault(mut mapping, key(mut key_calls, "a"), fallback(mut value_calls, 99)))
        \\    const added = copy(dicts.setdefault(mut mapping, key(mut key_calls, "b"), fallback(mut value_calls, 2)))
        \\    assert key_calls == 2
        \\    assert value_calls == 2
        \\    for i in range(40):
        \\        const grown = copy(dicts.setdefault(mut mapping, str(i), [i]))
        \\        assert grown[0] == i
        \\    _ = dicts.pop(mut mapping, "5")
        \\    const after_hole = copy(dicts.setdefault(mut mapping, "again-" + str(5), [5]))
        \\    assert after_hole[0] == 5
        \\    for i in range(30):
        \\        _ = dicts.pop_default(mut mapping, str(i), [])
        \\    for i in range(30):
        \\        const compacted = copy(dicts.setdefault(mut mapping, "new-" + str(i), [i]))
        \\        assert compacted[0] == i
        \\    dicts.clear(mut mapping)
        \\    print(out, hit[0], added[0])
        \\    return 0
    , "1 2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC conditional branch storage transfers owners instead of receiver loans" {
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip original R2 diagnostic, syntax-recognition or exact-output fixture; see L01 r2-preservation classification
        \\func main(args: str[]) -> int:
        \\    const owner = "value-" + str(len(args))
        \\    const selected = if (len(args) == 0) then (owner) else ("!")
        \\    return len(owner) + len(selected)
    , "E_CONDITIONAL_EXPRESSION_REMOVED");
    try refuses(std.testing.allocator,
        \\func main(args: str[]) -> int:
        \\    const owner = "value-" + str(len(args))
        \\    mut selected: str
        \\    if len(args) == 0:
        \\        selected = own owner
        \\    else:
        \\        selected = "!"
        \\    return strings.char_count(owner) + strings.char_count(selected)
    , "E_SINGLE_OWNER_MOVED");
    try executes(std.testing.allocator,
        \\func identity(text: str) -> str:
        \\    return copy(text)
        \\func called(text: str, take: bool) -> str:
        \\    const ch = strings.char_at(text, 0)
        \\    const result = identity(ch)
        \\    if take:
        \\        return result
        \\    return "!"
        \\func main(out: Stream) -> int:
        \\    print(out, called("éz", True), called("éz", False))
        \\    return 0
    , "é !\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC rejects shallow managed container copies in IR and emission" {
    const ir = @import("ir.zig");
    const verify = @import("verify_ir.zig");
    for (0..3) |shape| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module: ir.Module = .{};
        const ty = try module.intern(a, switch (shape) {
            0 => .{ .list = .str },
            1 => .{ .dict = .{ .key = .i64, .value = .str } },
            else => .{ .dict = .{ .key = .str, .value = .i64 } },
        });
        var h = try support.Hand.init(a, &module, "main", .{ .params = &.{}, .ret = .i64 });
        const source = try h.emit(.{ .op = if (shape == 0) .list_new else .dict_new, .ty = ty, .a = try h.int(.u64, 0) });
        _ = try h.emit(.{ .op = if (shape == 0) .list_copy else .dict_copy, .ty = ty, .a = source });
        _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
        _ = try h.finish();
        var failure: verify.Failure = .{};
        try std.testing.expectError(error.InvalidIr, verify.verifyModule(a, &module, &failure));
        try std.testing.expect(std.mem.indexOf(u8, failure.reason, "shallow container copy") != null);
        try std.testing.expectError(error.UnsupportedInstruction, support.runOwned(a, &module, .{ .own = false, .check_ir = false, .main = .{} }));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC receiver preparation preserves parent identity across sibling borrows" {
    const ir = @import("ir.zig");
    const flags = @import("flags.zig");
    for ([_]bool{ false, true }) |release| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var module: ir.Module = .{};
        const row = try module.intern(a, .{ .list = .i64 });
        const rows = try module.intern(a, .{ .list = row });
        var h = try support.Hand.init(a, &module, "main", .{ .params = &.{.cap}, .ret = .i64 });
        const zero_index = try h.int(.u64, 0);
        const one = try h.int(.u64, 1);
        const empty = try h.emit(.{ .op = .list_new, .ty = rows, .a = try h.int(.u64, 2) });
        const left = try h.emit(.{ .op = .list_new, .ty = row, .a = zero_index });
        const right = try h.emit(.{ .op = .list_new, .ty = row, .a = zero_index });
        const first = try h.emit(.{ .op = .list_push, .ty = rows, .a = empty, .b = left });
        const parent = try h.emit(.{ .op = .list_push, .ty = rows, .a = first, .b = right });
        const borrowed = try h.emit(.{ .op = .list_get, .ty = row, .a = parent, .b = one, .check = .exact });
        const prepared = try h.emit(.{ .op = .list_copy, .ty = rows, .a = parent, .data = flags.place_copy });
        const target = try h.emit(.{ .op = .list_get, .ty = row, .a = prepared, .b = zero_index, .data = flags.place_read, .check = .exact });
        const grown = try h.emit(.{ .op = .list_push, .ty = row, .a = target, .b = try h.int(.i64, 42) });
        const length = try h.emit(.{ .op = .list_len, .ty = .u64, .a = borrowed });
        const updated = try h.emit(.{ .op = .list_set, .ty = rows, .a = prepared, .b = zero_index, .data = try h.extra(&.{grown}), .check = .exact });
        const selected = try h.emit(.{ .op = .list_get, .ty = row, .a = updated, .b = zero_index, .check = .exact });
        const value = try h.emit(.{ .op = .list_get, .ty = .i64, .a = selected, .b = zero_index, .check = .exact });
        try h.printValues(try h.param(0), &.{ length, value });
        _ = try h.emit(.{ .op = .ret, .ty = .void, .a = try h.int(.i64, 0) });
        _ = try h.finish();
        const result = try support.runOwned(a, &module, .{ .release = release });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("0 42\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expect(zero.emittedClean(result.llvm));
    }
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC list extension refuses recursive ancestor sources" {
    try refuses(std.testing.allocator,
        \\import lists
        \\record Node:
        \\    value: int
        \\    children: Node[]
        \\func main() -> int:
        \\    mut tree = Node(value=0, children=[Node(value=1, children=[])])
        \\    lists.extend(mut tree.children[0].children, tree.children)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\import lists
        \\record Node:
        \\    value: int
        \\    children: Node[]
        \\func main(args: str[]) -> int:
        \\    mut tree = Node(value=0, children=[Node(value=1, children=[])])
        \\    const index = len(args) % 1
        \\    lists.extend(mut tree.children[index].children, tree.children)
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC list extension accepts independent copies of recursive ancestors" {
    try executes(std.testing.allocator,
        \\import lists
        \\
        \\record Node:
        \\    value: int
        \\    children: Node[]
        \\func main(out: Stream) -> int:
        \\    mut tree = Node(value=0, children=[Node(value=1, children=[]), Node(value=2, children=[])])
        \\    lists.extend(mut tree.children[1].children, copy(tree.children))
        \\    print(out, len(tree.children[1].children), len(tree.children[1].children[1].children))
        \\    mut items = [1, 2]
        \\    lists.extend(mut items, items)
        \\    print(out, len(items), items[2])
        \\    return 0
    , "2 0\n4 1\n");
}

// spec-case: NEW-CORE-U2-BORROW-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC scalar field snapshots do not borrow a later loop owner" {
    try executes(std.testing.allocator,
        \\record Marks:
        \\    seen: int[]
        \\    generation: int
        \\func visit(mut marks: Marks, n: int) -> int:
        \\    marks.generation += 1
        \\    const generation = marks.generation
        \\    marks.seen[0] = generation
        \\    mut next = 0
        \\    while next < n:
        \\        marks.seen[next % len(marks.seen)] = generation
        \\        next += 1
        \\    return marks.seen[0]
        \\func main(args: str[], out: Stream) -> int:
        \\    mut marks = Marks(seen=[0, 0], generation=0)
        \\    print(out, visit(mut marks, len(args) + 2))
        \\    print(out, marks.seen[0], marks.seen[1])
        \\    return 0
    , "1\n1 1\n");
}

// spec-case: DICT-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC single dictionary items borrow one entry and copies stay independent" {
    try executes(std.testing.allocator,
        \\import dicts
        \\import strings
        \\
        \\func score(values: dict[str, int[]]) -> int:
        \\    mut total = 0
        \\    for item in dicts.items(values):
        \\        total += strings.char_count(item.key) + item.value[0]
        \\    return total
        \\func main(out: Stream) -> int:
        \\    mut values = {"key-" + str(1): [7, 9], "key-" + str(2): [11]}
        \\    print(out, score(values))
        \\    mut saved: int[][] = []
        \\    mut pairs: DictItem[str, int[]][] = []
        \\    for item in dicts.items(values):
        \\        append(mut saved, copy(item.value))
        \\        append(mut pairs, copy(item))
        \\    dicts.clear(mut values)
        \\    print(out, saved[0][0], saved[1][0])
        \\    print(out, pairs[0].key, pairs[1].value[0])
        \\    return 0
    , "28\n7 11\nkey-1 11\n");
}

// spec-case: DICT-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC single dictionary items cannot escape or invalidate their owner" {
    // A non-empty literal is a new value beside the borrow (R5); `return []` is neutral since 4e.
    try refuses(std.testing.allocator,
        \\import dicts
        \\
        \\func escape(values: dict[str, int[]]) -> int[] from values:
        \\    for item in dicts.items(values):
        \\        return item.value
        \\    return [0]
        \\func main() -> int:
        \\    return 0
    , "E_BORROW_MIXED");
    try refuses(std.testing.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut values = {"key": [7]}
        \\    for item in dicts.items(values):
        \\        dicts.clear(mut values)
        \\        return item.value[0]
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut values = {"key": [7]}
        \\    for item in dicts.items(values):
        \\        values["key"] = [9]
        \\        return item.value[0]
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: DICT-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC single dictionary items preserve enumeration and unit members" {
    try executes(std.testing.allocator,
        \\import dicts
        \\
        \\func main(out: Stream) -> int:
        \\    const values = {"key-" + str(1): [7], "key-" + str(2): [11]}
        \\    for index, item in enumerate(dicts.items(values)):
        \\        print(out, index, item.key, item.value[0])
        \\    const empty_values: dict[str, Unit] = {"empty-" + str(3): ()}
        \\    for item in dicts.items(empty_values):
        \\        print(out, item.key)
        \\    const empty_keys: dict[Unit, str] = {(): "value-" + str(4)}
        \\    for item in dicts.items(empty_keys):
        \\        print(out, item.value)
        \\    return 0
    , "0 key-1 7\n1 key-2 11\nempty-3\nvalue-4\n");
}

// spec: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC borrowed defaults keep both roots through readonly and nested uses" {
    try executes(std.testing.allocator,
        \\import dicts
        \\import lists
        \\
        \\record Item:
        \\    values: int[]
        \\    label: str
        \\func fallback(mut calls: int, value: int) -> int[]:
        \\    calls += 1
        \\    return [value, value + 1]
        \\func score(value: int[]) -> int:
        \\    return value[0] + len(value)
        \\func main(out: Stream) -> int:
        \\    mut calls = 0
        \\    mut first = {"hit": [7]}
        \\    mut second = {"hit": [11, 12]}
        \\    mut backup = [17, 18, 19]
        \\    print(out, score(dicts.get(first, "hit", fallback(mut calls, 20))))
        \\    print(out, score(dicts.get(first, "miss", fallback(mut calls, 30))))
        \\    print(out, score(dicts.get(first, "miss", dicts.get(second, "hit", backup))))
        \\    print(out, score(dicts.get(first, "miss", dicts.get(second, "miss", backup))))
        \\    print(out, calls, backup[0], first["hit"][0], second["hit"][0])
        \\    const saved = copy(dicts.get(first, "miss", dicts.get(second, "miss", backup)))
        \\    lists.clear(mut backup)
        \\    dicts.clear(mut first)
        \\    dicts.clear(mut second)
        \\    print(out, saved[0], len(saved))
        \\    mut records = {1: Item(values=[3], label="item-" + str(1))}
        \\    const other = Item(values=[5, 6], label="other-" + str(2))
        \\    print(out, len(dicts.get(records, 1, other).values), len(dicts.get(records, 2, other).values))
        \\    return 0
    , "8\n32\n13\n20\n2 17 7 11\n17 3\n1 2\n");
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC borrowed defaults refuse mutation of either possible root" {
    const prefix =
        \\import dicts
        \\import lists
        \\func overwrite(mut values: int[]) -> int:
        \\    lists.clear(mut values)
        \\    return 0
        \\func replace(mut values: dict[str, int[]]) -> int:
        \\    dicts.clear(mut values)
        \\    return 0
        \\func use(values: int[], ignored: int) -> int:
        \\    return len(values)
        \\func main() -> int:
        \\    mut values = {"hit": [7]}
        \\    mut other = {"hit": [8]}
        \\    mut fallback = [9]
        \\
    ;
    inline for (.{
        "    return use(dicts.get(values, \"missing\", fallback), overwrite(mut fallback))\n",
        "    return use(dicts.get(values, \"hit\", fallback), replace(mut values))\n",
        "    return use(dicts.get(values, \"missing\", dicts.get(other, \"missing\", fallback)), overwrite(mut fallback))\n",
        "    return use(dicts.get(values, \"missing\", dicts.get(other, \"hit\", fallback)), replace(mut other))\n",
    }) |tail| try refuses(std.testing.allocator, prefix ++ tail, "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC borrowed defaults reject malformed and consuming IR markers" {
    const selections = @import("borrow_selection.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original_source =
        // migrate-embedded: skip intentional original effect/noalloc retirement diagnostic
        \\func size(values: dict[str, int[]], key: str, fallback: int[]) -> int noalloc:
        \\    return len(values.get(key, fallback))
        \\func main() -> int:
        \\    return size({"a": [1]}, "b", [2])
    ;
    try retiredSource(std.testing.allocator, original_source, "E_EFFECTS_REMOVED");
    const source =
        \\import dicts
        \\
        \\@noalloc
        \\func size(values: dict[str, int[]], key: str, own fallback: int[]) -> int:
        \\    return len(dicts.get(values, key, fallback))
        \\func main() -> int:
        \\    return size({"a": [1]}, "b", [2])
    ;
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    const program = unit.program.?;
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = program }, &refusal);
    var found = false;
    for (module.functions.items) |*function| {
        for (function.insts.items) |*instruction| {
            const selection = (try selections.call(&module, function, instruction.*)) orelse continue;
            found = true;
            try selections.validate(a, &module, function);
            // Public ownership/cache callers can supply a backing allocator.
            try @import("marker_validation.zig").validate(std.testing.allocator, &module, function);
            const original = instruction.*;
            instruction.data = std.math.maxInt(u64);
            try std.testing.expectError(error.UnsupportedInstruction, selections.validate(a, &module, function));
            try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, function, .{}));
            const violation = (try @import("allocation_contract.zig").validate(a, program, unit.src.?, &module)).?;
            try std.testing.expect(violation.unresolved);
            // A project program names its functions by module (`main::size`).
            try std.testing.expect(std.mem.endsWith(u8, violation.function, "size"));
            instruction.* = original;
            const declaration = &module.functions.items[instruction.a.index()];
            declaration.signature.passing.owned = 1;
            try std.testing.expectError(error.UnsupportedInstruction, selections.declaration(&module, declaration));
            declaration.signature.passing.owned = 0;
            declaration.signature.linkage = .extern_c;
            try std.testing.expectError(error.UnsupportedInstruction, selections.declaration(&module, declaration));
            declaration.signature.linkage = .runtime_c;
            const phi = selection.phi.?;
            const selected = function.insts.items[phi.index()];
            function.insts.items[phi.index()].data = std.math.maxInt(u64);
            try std.testing.expectError(error.UnsupportedInstruction, selections.validate(a, &module, function));
            function.insts.items[phi.index()] = selected;
            const incoming = @constCast(function.operands(selected.data));
            std.mem.swap(@import("ir.zig").Ref, &incoming[0], &incoming[1]);
            // Types and producer identities still match, but the hit value now
            // arrives on the miss edge where its definition does not dominate.
            try selections.validate(a, &module, function);
            try std.testing.expectError(error.UnsupportedInstruction, @import("marker_validation.zig").validate(std.testing.allocator, &module, function));
            try std.testing.expectError(error.Unsupported, @import("own.zig").function(a, &module, function, .{}));
            std.mem.swap(@import("ir.zig").Ref, &incoming[0], &incoming[1]);
            try function.insts.append(a, .{ .op = .ret, .ty = .void, .a = phi });
            try std.testing.expectError(error.UnsupportedInstruction, selections.validate(a, &module, function));
            function.insts.items.len -= 1;
            try selections.validate(a, &module, function);
            break;
        }
        if (found) break;
    }
    try std.testing.expect(found);
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC borrowed defaults release fresh fallback on success and error exits" {
    try executes(std.testing.allocator,
        \\import dicts
        \\import strings
        \\
        \\func inspect(values: dict[str, bytes], key: str) -> int fails str:
        \\    const size = len(dicts.get(values, key, strings.encode(("fallback-" + key))))
        \\    if key == "error":
        \\        fail "failure-" + str(size)
        \\    return size
        \\func outer(key: str) -> int fails str:
        \\    const values = {"hit": strings.encode(("value-" + str(7)))}
        \\    const size = try inspect(values, key)
        \\    return size + 1
        \\func main(out: Stream) -> int:
        \\    for key in ["hit", "miss", "error"]:
        \\        match outer(key):
        \\            case Ok(size):
        \\                print(out, size)
        \\            case Err(message):
        \\                print(out, message)
        \\    return 0
    , "8\n14\nfailure-14\n");
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC borrowed defaults preserve a 64-level shared-root selection chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try executes(a, try nestedDefaultSource(a, 64), "1 3\n");
}

test "zero RC generated 64-level borrowed defaults check and need no migration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try nestedDefaultSource(a, 64);
    const fixture_path = try std.fs.path.join(a, &.{ @import("core_test_options").fixtures, "borrowed_defaults_64.selka" });
    const fixture = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, fixture_path, a, .limited(1 << 20));
    try std.testing.expectEqualStrings(source, fixture);
    const outcome = try support.checkSource(a, source);
    try std.testing.expect(outcome.passed);
    try std.testing.expectEqual(@as(usize, 0), outcome.diagnostics.len);
    try nestedDefaultMigration(a, source);
}

fn nestedDefaultMigration(a: std.mem.Allocator, source: []const u8) !void {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const io = std.testing.io;
    try directory.dir.writeFile(io, .{ .sub_path = "main.selka", .data = source });
    const path = try directory.dir.realPathFileAlloc(io, "main.selka", a);
    const compiler = @import("core_test_options").corePath();
    const checked_source = try std.process.run(a, io, .{ .argv = &.{ compiler, "check", "--diagnostics=json", "--no-cache", path } });
    if (checked_source.term != .exited or checked_source.term.exited != 0)
        report("generated borrowed-default check:\n{s}{s}\n", .{ checked_source.stdout, checked_source.stderr });
    try std.testing.expect(checked_source.term == .exited);
    try std.testing.expectEqual(@as(u8, 0), checked_source.term.exited);
    try std.testing.expectEqualStrings("", checked_source.stdout);
    try std.testing.expectEqualStrings("", checked_source.stderr);
    for (0..2) |_| {
        const fixed = try std.process.run(a, io, .{ .argv = &.{ compiler, "fix", "--diagnostics=json", "--no-cache", path } });
        if (fixed.term != .exited or fixed.term.exited != 0)
            report("generated borrowed-default fix:\n{s}{s}\n", .{ fixed.stdout, fixed.stderr });
        try std.testing.expect(fixed.term == .exited);
        try std.testing.expectEqual(@as(u8, 0), fixed.term.exited);
        try std.testing.expectEqualStrings("fix: nothing to fix\n", fixed.stdout);
        try std.testing.expectEqualStrings("", fixed.stderr);
        try std.testing.expectEqualStrings(source, try directory.dir.readFileAlloc(io, "main.selka", a, .limited(1 << 20)));
    }
}

// Keep this generator canonical: the materialized fixture is checked byte-for-byte
// above, and the shared-root native test executes its exact output at both modes.
fn nestedDefaultSource(a: std.mem.Allocator, depth: usize) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    // migrate-embedded: skip generated fragment; test/core/borrowed_defaults_64.selka parity/check/fix/native coverage above
    try source.appendSlice(a, "import dicts\n\nfunc size(values: dict[int, int[]]) -> int:\n    return len(");
    for (0..depth) |index| try source.print(a, "dicts.get(values, {d}, ", .{index});
    try source.appendSlice(a, "[42]");
    for (0..depth) |_| try source.append(a, ')');
    // migrate-embedded: skip generated fragment; test/core/borrowed_defaults_64.selka parity/check/fix/native coverage above
    try source.appendSlice(a, ")\n\n\nfunc main(out: Stream) -> int:\n    print(out, size({}), size({31: [1, 2, 3]}))\n    return 0\n");
    return source.items;
}

// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC borrowed defaults cannot mutate the selected receiver" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const checked_unit = try support.checkSource(arena.allocator(),
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut values = {"hit": [7]}
        \\    mut fallback = [9]
        \\    append(mut dicts.get(values, "missing", fallback), 10)
        \\    return 0
    );
    try std.testing.expect(!checked_unit.passed);
    try std.testing.expectEqualStrings("E_MUTATION_MARKER", checked_unit.diagnostics[0].code);
    try refuses(std.testing.allocator,
        \\import dicts
        \\
        \\func main() -> int:
        \\    mut values = {"hit": [7]}
        \\    mut fallback = [9]
        \\    mut selected = dicts.get(values, "missing", fallback)
        \\    append(mut selected, 10)
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
// spec-case: TUPLE-3
// spec-case: PY-DESTRUCTURE-PLACE-1
test "zero RC tuple staging consumes whole owners before destination effects" {
    try executes(std.testing.allocator,
        // migrate-embedded: skip preserve written copies and explicit whole-owner disposal while adding four required named-transfer markers
        \\record Pair:
        \\    first: str
        \\    second: str
        \\record Owned:
        \\    text: str
        \\    items: int[]
        \\record UnitNumber:
        \\    ignored: Unit
        \\    number: int
        \\func pair(mut calls: int[]) -> Pair:
        \\    append(mut calls, 1)
        \\    return Pair(first="first-" + str(1), second="second-" + str(2))
        \\func at(mut calls: int[], value: int) -> int:
        \\    append(mut calls, value)
        \\    return 0
        \\func owned() -> Owned:
        \\    return Owned(text="owned-" + str(3), items=[4, 5])
        \\func early() -> str:
        \\    const whole = owned()
        \\    return copy(whole.text)
        \\func main(out: Stream) -> int:
        \\    mut words = ["a" + str(1), "b" + str(2)]
        \\    const swap_first = copy(words[1])
        \\    const swap_second = copy(words[0])
        \\    words[0] = own swap_first
        \\    words[1] = own swap_second
        \\    mut calls: int[] = []
        \\    const staged = pair(mut calls)
        \\    const first = copy(staged.first)
        \\    const second = copy(staged.second)
        \\    _ = staged
        \\    words[at(mut calls, 2)] = own first
        \\    words[at(mut calls, 3)] = own second
        \\    const complete = owned()
        \\    const text = copy(complete.text)
        \\    const items = copy(complete.items)
        \\    _ = complete
        \\    _ = owned()
        \\    const unit_number = UnitNumber(ignored=(), number=7)
        \\    const number = unit_number.number
        \\    print(out, words[0], words[1], len(calls), calls[0], calls[1], calls[2], text, items[0], early(), number)
        \\    return 0
    , "second-2 a1 3 1 2 3 owned-3 4 owned-3 7\n");
}

fn retiredTupleStagingSource(parent: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var unit = try language.Compilation.init(arena.allocator(), "retired-staging.selka", source);
    try std.testing.expectError(error.SourceError, unit.check());
    var errors: usize = 0;
    for (unit.diagnostics.items) |item| {
        if (item.severity != .err) continue;
        errors += 1;
        try std.testing.expectEqualStrings("E_TUPLE_REMOVED", item.code);
    }
    try std.testing.expect(errors > 0);
}

// spec-case: TUPLE-REMOVED-1
// spec-case: TUPLE-3
// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC tuple staging refuses borrowed whole tuples and reuse" {
    try retiredTupleStagingSource(std.testing.allocator,
        // migrate-embedded: skip preserved original borrowed-tuple diagnostic
        \\func consume(pair: tuple[str, int]) -> str:
        \\    const text, number = pair
        \\    return text
        \\func main() -> int:
        \\    return 0
    );
    try retiredTupleStagingSource(std.testing.allocator,
        // migrate-embedded: skip preserved original tuple-reuse diagnostic
        \\func main() -> int:
        \\    const pair = ("value-" + str(1), [2])
        \\    const first, items = pair
        \\    const again, second = pair
        \\    return strings.char_count(first) + strings.char_count(again)
    );
    // Current record staging must reach zero-RC ownership checking, not tuple retirement.
    // Moving a whole record twice must reach ownership checking after staging.
    try refuses(std.testing.allocator,
        \\record Pair:
        \\    text: str
        \\    items: int[]
        \\func main() -> int:
        \\    const pair = Pair(text="value-" + str(1), items=[2])
        \\    const first = own pair
        \\    const again = own pair
        \\    return strings.char_count(first.text) + strings.char_count(again.text)
    , "E_SINGLE_OWNER_MOVED");
}

// spec-case: TUPLE-3
// spec-case: PY-DESTRUCTURE-PLACE-1
test "zero RC tuple staging validates complete cached shape before lowering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip preserved original cached tuple-shape source
        \\func main(out: Stream) -> int:
        \\    const first, second = ("value-" + str(1), [2])
        \\    print(out, first, second[0])
        \\    return 0
    , "E_TUPLE_REMOVED");
    const program = try cachedTupleStaging(a);
    var healthy_failure: contract.Failure = .{};
    try contract.check(a, program, &healthy_failure);
    var healthy_refusal: build.Refusal = .{};
    var healthy_module = try build.buildExecutable(a, .{ .program = program }, &healthy_refusal);
    _ = try passes.debug(a, &healthy_module);

    const statement = try tupleStore(program);
    const original = statement.*;
    defer statement.* = original;
    const store = original.data.initialize;
    const wrong: [2]?language.typed.LocalId = .{ store.unpack.?[0], store.unpack.?[0] };
    for ([_][]const ?language.typed.LocalId{ store.unpack.?[0..1], &wrong, &.{ store.slot, store.unpack.?[1] } }) |slots| {
        statement.data.initialize.unpack = slots;
        var failure: contract.Failure = .{};
        try std.testing.expectError(error.Rejected, contract.check(a, program, &failure));
        var refusal: build.Refusal = .{};
        try std.testing.expectError(error.Unsupported, build.buildExecutable(a, .{ .program = program }, &refusal));
    }
    statement.* = original;
    statement.data = .{ .assign = store };
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, build.buildExecutable(a, .{ .program = program }, &refusal));
}

// spec-case: TUPLE-3
// spec-case: NEW-CORE-ZERO-RC-AFFINE-RESOURCES-1
test "zero RC tuple staging preserves dependent resource roots" {
    try retiredSource(std.testing.allocator,
        // migrate-embedded: skip intentional original tuple resource-lifetime diagnostic
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\func main() -> int:
        \\    mut fs = filesystem.memory()
        \\    match acquire_resource[Open](fs, FixedArray[u8, 0]([])):
        \\        case ok(file):
        \\            const pair = (file, 7)
        \\            const owner, code = pair
        \\            fs = filesystem.memory()
        \\            _ = owner
        \\            return code
        \\        case err(code):
        \\            return code
    , "E_TUPLE_REMOVED");
    // Replacing the provider binding while the record holds its file is accepted since 5C: the handle outlives it.
    try accepts(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\record FileAndCode:
        \\    owner: File
        \\    code: int
        \\func main() -> int:
        \\    mut fs = filesystem.memory()
        \\    match acquire_resource[Open](fs, FixedArray[u8, 0]([])):
        \\        case ok(file):
        \\            const code = 7
        \\            const pair = FileAndCode(owner=own file, code=code)
        \\            fs = filesystem.memory()
        \\            _ = own pair
        \\            return code
        \\        case err(code):
        \\            return code
    );
    try executes(std.testing.allocator,
        \\import filesystem
        \\resource File: filesystem
        \\result Open:
        \\    ok: File,
        \\    err: int
        \\record FileAndCode:
        \\    owner: File
        \\    code: int
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    _ = fs.write_text("x", "value")
        \\    match acquire_resource[Open](fs, FixedArray[u8, 3]([114u8, 58u8, 120u8])):
        \\        case ok(file):
        \\            const pair = FileAndCode(owner=own file, code=7)
        \\            const code = pair.code
        \\            print(out, code)
        \\        case err(code):
        \\            return code
        \\    return 0
    , "7\n");
}

// Construct the retained compiler-only staging format from a checked nominal record.
// No retired source tuple or destructuring is admitted by this fixture builder.
fn cachedTupleStaging(a: std.mem.Allocator) !language.typed.Program {
    const typed = language.typed;
    const program = try checked(a,
        \\record Pair:
        \\    first: str
        \\    second: int[]
        \\func main(out: Stream) -> int:
        \\    const whole = Pair(first="value-" + str(1), second=[2])
        \\    const first = ""
        \\    const second: int[] = []
        \\    print(out, first, second[0])
        \\    return 0
    );
    const function = program.functions[@backingInt(program.main)];
    var whole: ?typed.LocalId = null;
    var first: ?typed.LocalId = null;
    var second: ?typed.LocalId = null;
    for (function.scope.locals, 0..) |local, index| {
        const slot: typed.LocalId = @fromBackingInt(@intCast(index));
        if (std.mem.eql(u8, local.name, "whole")) whole = slot;
        if (std.mem.eql(u8, local.name, "first")) first = slot;
        if (std.mem.eql(u8, local.name, "second")) second = slot;
    }
    const owner = whole orelse return error.TestUnexpectedResult;
    const fields = try a.dupe(?typed.LocalId, &.{ first orelse return error.TestUnexpectedResult, second orelse return error.TestUnexpectedResult });
    const locals = @constCast(function.scope.locals);
    @constCast(program.records)[locals[@backingInt(owner)].ty.recordIndex()].shape.tuple = true;
    for ([_]typed.LocalId{ owner, fields[0].?, fields[1].? }) |slot| {
        locals[@backingInt(slot)].usage.temporary = true;
        locals[@backingInt(slot)].ownership.transfer_available = false;
    }
    var staged: ?typed.Store = null;
    for (@constCast(program.statements)) |*statement| {
        if (statement.data != .initialize) continue;
        const slot = statement.data.initialize.slot;
        if (slot == owner) {
            statement.data.initialize.unpack = fields;
            staged = statement.data.initialize;
        } else if (slot == fields[0].? or slot == fields[1].?) {
            statement.data = .{ .block = &.{} };
        }
    }
    _ = try @import("tuple_unpack.zig").fields(a, program, function, staged orelse return error.TestUnexpectedResult, true);
    return program;
}

fn tupleStore(program: language.typed.Program) !*language.typed.Statement {
    for (@constCast(program.statements)) |*candidate| {
        if (candidate.data == .initialize and candidate.data.initialize.unpack != null) return candidate;
    }
    return error.TestUnexpectedResult;
}

// spec-case: NEW-CORE-ZERO-RC-PROVIDER-FIELDS-1
// spec-case: NEW-CORE-ZERO-RC-ABI-1
test "zero RC aggregate provider markers reject malformed calls before ownership" {
    const ir = @import("ir.zig");
    const provider = @import("aggregate_provider.zig");
    const markers = @import("marker_validation.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ty = try module.intern(a, .{ .record = &.{ .capability, .str } });
    try module.functions.append(a, .{ .name = try support.fixtureName(a, provider.prefix, ty), .signature = .{ .params = &.{ty}, .ret = .void, .linkage = .runtime_c } });
    var function: ir.Function = .{ .name = "pin", .signature = .{ .params = &.{ty}, .ret = .void } };
    try function.insts.appendSlice(a, &.{
        .{ .op = .param, .ty = ty, .data = 0 },
        .{ .op = .call, .ty = .void, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 0, .len = 1 }).pack() },
        .{ .op = .ret, .ty = .void },
    });
    try function.extra.append(a, @fromBackingInt(0));
    var block: ir.Block = .{};
    try block.insts.appendSlice(a, &.{ @fromBackingInt(1), @fromBackingInt(2) });
    try function.blocks.append(a, block);
    try markers.validate(std.testing.allocator, &module, &function);
    const original = function.insts.items[1];
    const malformed = [_]ir.Inst{
        .{ .op = .call, .ty = .void, .a = @fromBackingInt(0), .data = std.math.maxInt(u64) },
        .{ .op = .call, .ty = .void, .a = @fromBackingInt(0), .data = (ir.ExtraSlice{ .start = 0, .len = 0 }).pack() },
        .{ .op = .call, .ty = .i64, .a = @fromBackingInt(0), .data = original.data },
        .{ .op = .call, .ty = .void, .a = .none, .data = original.data },
        .{ .op = .call, .ty = .void, .a = @fromBackingInt(100), .data = original.data },
    };
    for (malformed) |invalid| {
        function.insts.items[1] = invalid;
        try std.testing.expectError(error.UnsupportedInstruction, provider.call(&module, &function, invalid));
        try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
    }
    function.insts.items[1] = original;
    function.extra.items[0] = .none;
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
    function.extra.items[0] = @fromBackingInt(0);
    function.insts.items[0].ty = .str;
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
    function.insts.items[0].ty = ty;
    function.insts.items[0].op = .copy;
    function.insts.items[0].a = @fromBackingInt(0);
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
    function.insts.items[0] = .{ .op = .param, .ty = ty, .data = 0 };
    function.blocks.items[0].insts.items[1] = .none;
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
    function.blocks.items[0].insts.items[1] = @fromBackingInt(2);
    function.insts.items[2].ty = @fromBackingInt(std.math.maxInt(u32));
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
    function.insts.items[2].ty = .void;
    try module.functions.items[0].insts.append(a, .{ .op = .ret, .ty = .void });
    try std.testing.expectError(error.UnsupportedInstruction, provider.marker(&module, &module.functions.items[0]));
    try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, &function));
}

// spec-case: NEW-CORE-ZERO-RC-RESOURCE-SCOPES-1
// spec-case: NEW-CORE-ZERO-RC-DEFAULT-BORROWS-1
test "zero RC live file scopes and fresh selections clean up across loop exits" {
    try executes(std.testing.allocator, @embedFile("a07_lifecycle_fixture.selka"), "43 18\nscope-47 36\npayload\nFalse\n");
}

// spec-case: CAPABILITY-FIELD-METHOD-1
test "zero RC context-only markers reject malformed block references before verification" {
    const ir = @import("ir.zig");
    const contexts = @import("borrowed_provider.zig");
    const markers = @import("marker_validation.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const ty = try module.intern(a, .{ .record = &.{ .capability, .i64 } });
    const marker = try support.declareProvider(a, &module, ty);
    var hand = try support.Hand.init(a, &module, "context", .{ .params = &.{.capability}, .ret = .i64 });
    const value = try hand.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(marker), .data = try hand.extra(&.{ try hand.param(0), try hand.int(.i64, 7) }) });
    const scalar = try hand.emit(.{ .op = .record_get, .ty = .i64, .a = value, .data = 1 });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = scalar });
    const index = try hand.finish();
    const function = &module.functions.items[index];
    try markers.validate(std.testing.allocator, &module, function);
    const block = &function.blocks.items[0];
    const last = block.insts.items.len - 1;
    const original = block.insts.items[last];
    for ([_]ir.Ref{ .none, @fromBackingInt(@as(u32, @intCast(function.insts.items.len))) }) |invalid| {
        block.insts.items[last] = invalid;
        // The provider contract is valid; the shared boundary must reject the
        // unrelated malformed CFG before the general verifier follows it.
        try contexts.validate(std.testing.allocator, &module, function);
        try std.testing.expectError(error.UnsupportedInstruction, markers.validate(std.testing.allocator, &module, function));
    }
    block.insts.items[last] = original;
    try markers.validate(std.testing.allocator, &module, function);
}

/// Preserve the historical guest, require its removal fixes, then run the modern form.
fn removedNegativeIndexesThenExecutes(parent: std.mem.Allocator, original: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    // The fixture keeps a negative index on purpose; the repair for it writes an
    // offset from the length, and a length of a `str` is its scalar count, so the
    // derived modern program is the fixer's output after as many rounds as it
    // needs (`selka fix` then finds no text-scalar form left).
    var modern: std.ArrayList(u8) = .empty;
    try modern.appendSlice(a, original);
    var rounds: usize = 0;
    for (0..4) |_| {
        // The fixture may import a module, so the derived program is checked in
        // whichever mode its shape allows.
        const derived = try support.checkSource(a, modern.items);
        var edits: std.ArrayList(language.diagnostic.Edit) = .empty;
        for (derived.diagnostics) |item| {
            const removable = std.mem.eql(u8, item.code, "E_NEGATIVE_INDEX_REMOVED") or
                std.mem.eql(u8, item.code, "E_TEXT_SCALAR_FORM") or
                std.mem.eql(u8, item.code, "E_TEXT_ITERATION");
            if (!removable) continue;
            try std.testing.expect(item.provenance.fix != null);
            const fix = item.provenance.fix.?;
            for (0..fix.count()) |index| try edits.append(a, fix.at(index));
        }
        if (edits.items.len == 0) break;
        rounds += 1;
        std.mem.sort(language.diagnostic.Edit, edits.items, {}, struct {
            fn later(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
                return left.span.start > right.span.start;
            }
        }.later);
        var end = modern.items.len;
        for (edits.items) |edit| {
            if (edit.span.end > end) continue;
            try modern.replaceRange(a, edit.span.start, edit.span.end - edit.span.start, edit.text);
            end = edit.span.start;
        }
    }
    try std.testing.expect(rounds > 0);
    try executes(a, modern.items, expected);
}

/// An undeclared parameter borrow gets one complete declaration edit that checks.
fn refusesDeclaration(parent: std.mem.Allocator, source: []const u8, clause: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_BORROW_UNDECLARED", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R4, failure.rule.?);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 1), edits.len);
    try std.testing.expectEqualStrings(clause, edits[0].text);
    const edit = edits[0];
    const fixed = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    const repaired = try support.checkSource(a, fixed);
    try std.testing.expect(repaired.passed);
    failure = .{};
    try contract.checkWithSource(a, repaired.program.?, repaired.src.?, &failure);
}

/// A real local or storage escape keeps its expression-copy repair.
fn refusesCopy(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(arena.allocator(), try checked(arena.allocator(), source), &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.copy.span != null);
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "a slice stored in a record field or a list literal is refused with its copy repair" {
    try refusesCopy(std.testing.allocator,
        \\record Box:
        \\    value: str
        \\func store(text: str) -> int:
        \\    mut box = Box(value=copy(text))
        \\    box.value = text[0:2]
        \\    return len(box.value)
        \\func main() -> int:
        \\    return store("abc")
    , "E_SLICE_ESCAPES");
    try refusesCopy(std.testing.allocator,
        \\func collect(text: str) -> int:
        \\    const items = [text[0:2]]
        \\    return len(items)
        \\func main() -> int:
        \\    return collect("abc")
    , "E_SLICE_ESCAPES");
}

// spec: SLICE-ESCAPES-1
// spec-case: TEXT-SCALARS-2
test "a scalar slice helper is a view, so owning storage refuses it with its copy repair" {
    try refusesCopy(std.testing.allocator,
        \\record Box:
        \\    value: str
        \\func store(text: str) -> int:
        \\    mut box = Box(value=copy(text))
        \\    box.value = strings.char_slice(text, 0, 2)
        \\    return len(box.value)
        \\func main() -> int:
        \\    return store("abc")
    , "E_SLICE_ESCAPES");
    try refusesCopy(std.testing.allocator,
        \\func store(text: str) -> int:
        \\    const items = [strings.char_slice(text, 0, 2)]
        \\    return len(items)
        \\func main() -> int:
        \\    return store("abc")
    , "E_SLICE_ESCAPES");
}

test "the copy a scalar slice helper is written as, owned storage accepts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a,
        \\record Box:
        \\    value: str
        \\func store(text: str) -> int:
        \\    mut box = Box(value=copy(text))
        \\    box.value = copy(strings.char_slice(text, 0, 2))
        \\    const items = [copy(strings.char_slice(text, 0, 2))]
        \\    return len(box.value) + len(items)
        \\func main() -> int:
        \\    return store("abc")
    );
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "a parameter slice return needs a declaration and a local slice escape needs a copy" {
    try refusesDeclaration(std.testing.allocator,
        \\func pick(first: str, second: str) -> str:
        \\    return second[0:1]
        \\func main() -> int:
        \\    return len(pick("a", "b"))
    , " from second");
    try refusesCopy(std.testing.allocator,
        \\func head(text: str) -> str:
        \\    const copy = copy(text)
        \\    return copy[0:1]
        \\func main() -> int:
        \\    return len(head("abc"))
    , "E_SLICE_ESCAPES");
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "a declared slice of a parameter may be returned" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a,
        \\func head(text: str) -> str from text:
        \\    return text[0:2]
        \\func main() -> int:
        \\    return len(head("abc"))
    );
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
}

// spec: SLICE-ESCAPES-1
// spec-case: SLICE-ESCAPES-1
test "a byte slice stored in a record is refused with its copy repair too" {
    try refusesCopy(std.testing.allocator,
        \\record Held:
        \\    body: bytes
        \\func keep(data: bytes) -> int:
        \\    mut held = Held(body=copy(data))
        \\    held.body = data[1:3]
        \\    return len(held.body)
        \\func main() -> int:
        \\    return keep(b"abcd")
    , "E_SLICE_ESCAPES");
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "a match payload return needs its declaration or an explicit copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The payload borrows its parameter through the match. Declaring that root
    // admits the view; the separately written copy returns independent storage.
    try refusesDeclaration(a,
        \\enum Shape:
        \\    named(name: str)
        \\func first(sh: Shape) -> str:
        \\    match sh:
        \\        case named(name=value):
        \\            const piece = value[0:2]
        \\            return piece
        \\func main() -> int:
        \\    return len(first(Shape.named(name="abcd")))
    , " from sh");
    const repaired = try checked(a,
        \\enum Shape:
        \\    named(name: str)
        \\func first(sh: Shape) -> str:
        \\    match sh:
        \\        case named(name=value):
        \\            const piece = value[0:2]
        \\            return copy(piece)
        \\func main() -> int:
        \\    return len(first(Shape.named(name="abcd")))
    );
    var accepted: contract.Failure = .{};
    try contract.check(a, repaired, &accepted);
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "wave3 fixes: a mixed deferred const is owned and its slice copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // REGRESSION-R3: not a view on every path, so the binding is owned, and its
    // slice initialization is a copy that must be written (rule C, C1).
    const refused = try checked(a,
        \\func main() -> int:
        \\    const s = "hello"
        \\    const h: str
        \\    if len(s) > 3:
        \\        h = s[0:2]
        \\    else:
        \\        h = "zz"
        \\    return len(h)
    );
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(a, refused, &failure));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    try std.testing.expect(failure.copy.span != null);
    const repaired = try checked(a,
        \\func main() -> int:
        \\    const s = "hello"
        \\    const h: str
        \\    if len(s) > 3:
        \\        h = copy(s[0:2])
        \\    else:
        \\        h = "zz"
        \\    return len(h)
    );
    var accepted: contract.Failure = .{};
    try contract.check(a, repaired, &accepted);
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "wave3 fixes: two slices of one source merge as one view" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // REGRESSION-R3: a phi keeps both views of the same live source.
    const program = try checked(a,
        \\func main() -> int:
        \\    const s = "hello"
        \\    const h: str
        \\    if len(s) > 3:
        \\        h = s[0:2]
        \\    else:
        \\        h = s[1:3]
        \\    return len(h)
    );
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "wave3 fixes: a dead view does not block a loop mutation, a live one is a copy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // REGRESSION-R4: `k` is read before the loop mutates its source, so nothing
    // is refused and no loop-move error is reported.
    const program = try checked(a,
        \\func main() -> int:
        \\    mut s = "abc"
        \\    const k = s[1:3]
        \\    const before = len(k)
        \\    for i in range(3):
        \\        s += "x"
        \\    return before + len(s)
    );
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
    // REGRESSION-R4: a view read after the invalidating loop takes the copy
    // repair, never E_SINGLE_OWNER_LOOP.
    var refused_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer refused_arena.deinit();
    const ra = refused_arena.allocator();
    var refused: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.check(ra, try checked(ra,
        \\func main() -> int:
        \\    mut s = "abcdef"
        \\    const h = s[0:4]
        \\    for i in range(3):
        \\        s += "x"
        \\    return len(h)
    ), &refused));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", refused.code);
    try std.testing.expect(refused.copy.span != null);
}

// spec: SLICE-ESCAPES-1
// spec: NEW-CORE-S1-VIEW-6
// spec-case: SLICE-ESCAPES-1
// spec-case: NEW-CORE-S1-VIEW-6
test "a stored list slice needs a copy and a returned list slice needs its declaration" {
    // X3: the escape rule covers list slices too, so text, bytes and lists agree.
    try refusesCopy(std.testing.allocator,
        \\record Bag:
        \\    items: int[]
        \\func keep(xs: int[]) -> int:
        \\    const bag = Bag(items=xs[1:3])
        \\    return len(bag.items)
        \\func main() -> int:
        \\    return keep([1, 2, 3, 4])
    , "E_SLICE_ESCAPES");
    try refusesDeclaration(std.testing.allocator,
        \\func middle(xs: int[]) -> int[]:
        \\    return xs[1:3]
        \\func main() -> int:
        \\    return len(middle([1, 2, 3, 4]))
    , " from xs");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The repair builds: `.copy()` of a list slice is an owned list.
    const program = try checked(a,
        \\record Bag:
        \\    items: int[]
        \\func keep(xs: int[]) -> int:
        \\    const bag = Bag(items=copy(xs[1:3]))
        \\    return len(bag.items)
        \\func main() -> int:
        \\    return keep([1, 2, 3, 4])
    );
    var failure: contract.Failure = .{};
    try contract.check(a, program, &failure);
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "a bound bytes slice return materializes after a concatenated argument" {
    // These signatures return owned bytes, and both source forms explicitly copy
    // their views. Declaring `myl_core_view_copy_bytes` grows the module's function
    // table during lowering; storing completed work by index preserves it (B1).
    try executes(std.testing.allocator,
        \\func clean(source: bytes, start: int, stop: int) -> bytes:
        \\    const raw = source[start:stop]
        \\    return copy(raw)
        \\
        \\
        \\func inline_clean(source: bytes, start: int, stop: int) -> bytes:
        \\    return copy(source[start:stop])
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut data = b"abcd"
        \\    data = data + b"efgh"
        \\    const line = clean(data, 0, 8)
        \\    const straight = inline_clean(data, 0, 8)
        \\    print(out, len(line), len(straight))
        \\    return 0
    , "8 8\n");
}

test "zero RC clean text refuses a declaration or call of a counted runtime symbol and accepts a bare mention" {
    try std.testing.expect(zero.emittedClean("define void @f() {\n  ret void\n}\n"));
    try std.testing.expect(zero.emittedClean("  %p = bitcast ptr @myl_core_retain to ptr\n"));
    try std.testing.expect(!zero.emittedClean("declare void @myl_core_retain(ptr)\n"));
    try std.testing.expect(!zero.emittedClean("  call void @myl_core_release(ptr %p)\n"));
    try std.testing.expect(!zero.emittedClean("  call void @myl_core_share(ptr %p)\n"));
    try std.testing.expect(!zero.emittedClean("  call void @myl_core_free_block(ptr %p)\n"));
}
