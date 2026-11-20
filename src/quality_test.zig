//! Tests resolved call reachability, module privacy, and quality report allocation cleanup.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const quality = language.quality;
fn index(c: *language.Compilation, name: []const u8) !usize {
    for (c.program.?.functions, 0..) |function, i| if (std.mem.eql(u8, function.name, name)) return i;
    return error.TestUnexpectedResult;
}
// migrate-embedded: skip retained legacy domain policy fixture
const graph =
    \\domain D: i64:
    \\    private func hidden() -> i64:
    \\        return 1
    \\
    \\
    \\func leaf(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\func a(n: i64) -> i64:
    \\    if n <= 0:
    \\        return 0
    \\    return b(n - 1)
    \\
    \\
    \\func b(n: i64) -> i64:
    \\    return a(n)
    \\
    \\
    \\func unused() -> i64:
    \\    return leaf(1)
    \\
    \\
    \\func main() -> i64:
    \\    if False:
    \\        _ = a(1)
    \\    return leaf(2) + leaf(3)
;
const modern_graph =
    \\record D:
    \\    value: i64
    \\
    \\func hidden() -> i64:
    \\    return 1
    \\
    \\
    \\func leaf(x: i64) -> i64:
    \\    return x
    \\
    \\
    \\func a(n: i64) -> i64:
    \\    if n <= 0:
    \\        return 0
    \\    return b(n - 1)
    \\
    \\
    \\func b(n: i64) -> i64:
    \\    return a(n)
    \\
    \\
    \\func unused() -> i64:
    \\    return leaf(1)
    \\
    \\
    \\func main() -> i64:
    \\    if False:
    \\        _ = a(1)
    \\    return leaf(2) + leaf(3)
;

// spec: TOOL-6
test "resolved reachability includes untaken call paths cycles and incoming sites from unreachable functions" {
    var c = try language.Compilation.init(t.allocator, "quality.selka", modern_graph);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{});
    defer result.deinit();
    try t.expect(result.functions[try index(&c, "a")].reachable);
    try t.expect(result.functions[try index(&c, "b")].reachable);
    try t.expect(!result.functions[try index(&c, "unused")].reachable);
    try t.expect(!result.functions[try index(&c, "hidden")].reachable);
    try t.expectEqual(@as(usize, 3), result.functions[try index(&c, "leaf")].incoming_sites);
    const rendered = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "private=false; reachable-from-main=false") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "Runtime coverage and assertions: not measured") != null);
    try t.expect(std.mem.indexOf(u8, rendered, "external entry policy") != null);
}

test "zero thresholds disable metric signals without hiding facts or changing source checking" {
    var c = try language.Compilation.init(t.allocator, "quality.selka",
        \\func main() -> i64:
        \\    if True:
        \\        return 1
        \\    return 0
    );
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{ .max_function_lines = 0, .max_parameters = 0, .max_nesting = 0, .max_decisions = 0, .max_line_bytes = 0 });
    defer result.deinit();
    const rendered = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "exceeds configured") == null);
    try t.expect(std.mem.indexOf(u8, rendered, "decision-points=1") != null);
}
fn allocationScenario(allocator: std.mem.Allocator, c: *language.Compilation) !void {
    var result = try quality.analyze(allocator, c.program.?, c.src, c.syntax.?, .{});
    defer result.deinit();
    const rendered = try quality.render(allocator, result, c.program.?, c.src);
    defer allocator.free(rendered);
    try t.expect(result.functions[try index(c, "leaf")].reachable);
}
test "quality traversal reachability and rendering release storage at every allocation failure" {
    var c = try language.Compilation.init(t.allocator, "quality.selka", modern_graph);
    defer c.deinit();
    try c.check();
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{&c});
}

test "static call reachability traverses a long chain without host recursion" {
    var output: std.Io.Writer.Allocating = .init(t.allocator);
    defer output.deinit();
    try writeCallChain(&output);
    const text = try output.toOwnedSlice();
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "chain.selka", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{});
    defer result.deinit();
    for (result.functions) |function| try t.expect(function.reachable);
    try t.expectEqual(@as(usize, 1), result.functions[try index(&c, "g2000")].incoming_sites);
}

test "explicit quality roots validate bounds and tolerate duplicate or empty roots" {
    var c = try language.Compilation.init(t.allocator, "roots.selka",
        \\func main() -> i64:
        \\    return 0
        \\
        \\
        \\func api() -> i64:
        \\    return 1
    );
    defer c.deinit();
    try c.check();
    var empty = try language.quality.analyzeWithExports(t.allocator, c.program.?, c.src, c.syntax.?, .{}, &.{});
    defer empty.deinit();
    try t.expect(empty.module_roots);
    try t.expect(empty.functions[0].reachable);
    try t.expect(!empty.functions[0].reachable_from_exports);
    var duplicate = try language.quality.analyzeWithExports(t.allocator, c.program.?, c.src, c.syntax.?, .{}, &.{ @fromBackingInt(1), @fromBackingInt(1) });
    defer duplicate.deinit();
    try t.expect(duplicate.functions[1].exported);
    try t.expect(duplicate.functions[1].reachable_from_exports);
    try t.expect(!duplicate.functions[1].reachable);
    try t.expectError(error.InvalidQualityRoot, language.quality.analyzeWithExports(t.allocator, c.program.?, c.src, c.syntax.?, .{}, &.{@fromBackingInt(2)}));
}

fn writeCallChain(output: *std.Io.Writer.Allocating) !void {
    for (0..2000) |i| try output.writer.print("func g{d}() -> i64:\n    return g{d}()\n\n\n", .{ i, i + 1 });
    try output.writer.writeAll(
        \\func g2000() -> i64:
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    return g0()
    );
}

test "structural metrics count branches loops short circuits nesting and physical source lines" {
    const text =
        \\func work(x: i64, flag: bool) -> i64:
        \\    mut n = x
        \\    if flag and n > 0:
        \\        while n > 0:
        \\            n -= 1
        \\    if flag:
        \\        return n
        \\    return x
        \\
        \\
        \\func main() -> i64:
        \\    return work(2, True)
    ;
    var c = try language.Compilation.init(t.allocator, "quality.selka", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{ .max_nesting = 1, .max_decisions = 3, .max_parameters = 1, .max_function_lines = 7 });
    defer result.deinit();
    const metrics = result.functions[try index(&c, "work")];
    try t.expectEqual(@as(usize, 8), metrics.structure.lines);
    try t.expectEqual(@as(usize, 2), metrics.structure.parameters);
    try t.expectEqual(@as(usize, 2), metrics.structure.nesting);
    try t.expectEqual(@as(usize, 4), metrics.structure.decisions);
    try t.expectEqual(@as(usize, "func work(x: i64, flag: bool) -> i64:".len), metrics.structure.longest_line);
    const first = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(first);
    const second = try quality.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
    for ([_][]const u8{ "function-lines 8 exceeds", "parameters 2 exceeds", "control-nesting 2 exceeds", "decision-points 4 exceeds" }) |part| try t.expect(std.mem.indexOf(u8, first, part) != null);
}

// spec: LINT-SIZE-1
test "the parameter budget counts data parameters, and a capability is not one" {
    const text =
        \\func six(a: int, b: int, c: int, d: int, e: int, f: int) -> int:
        \\    return a + b + c + d + e + f
        \\
        \\
        \\func capped(fs: Filesystem, a: int, b: int, c: int, d: int, e: int) -> int:
        \\    _ = fs.read_file("x")
        \\    return a + b + c + d + e
        \\
        \\
        \\func main() -> int:
        \\    return six(1, 2, 3, 4, 5, 6)
    ;
    var c = try language.Compilation.init(t.allocator, "quality.selka", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{});
    defer result.deinit();
    try t.expectEqual(@as(usize, 6), result.functions[try index(&c, "six")].structure.parameters);
    // One capability plus five data parameters measures five: authority is not data.
    try t.expectEqual(@as(usize, 5), result.functions[try index(&c, "capped")].structure.parameters);
    const defaults: quality.Options = .{};
    try t.expectEqual(@as(usize, 5), defaults.max_parameters);
    try t.expectEqual(@as(usize, 60), defaults.max_function_lines);
}

/// Control nesting of the named function in the checked program of `text`.
fn nestingOf(text: []const u8, name: []const u8) !usize {
    var c = try language.Compilation.init(t.allocator, "quality.selka", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{});
    defer result.deinit();
    return result.functions[try index(&c, name)].structure.nesting;
}

test "control nesting ignores a slice's bounds checks: one if after a slice measures one" {
    const text =
        \\func piece_then_branch(info: bytes) -> int:
        \\    const piece = info[0:2]
        \\    if len(info) == 3:
        \\        return len(piece)
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return piece_then_branch(b"abc")
    ;
    try t.expectEqual(@as(usize, 1), try nestingOf(text, "piece_then_branch"));
}

test "control nesting counts an if elif chain as one level however many arms it has" {
    const text =
        \\func classify(x: int) -> int:
        \\    if x == 1:
        \\        return 10
        \\    elif x == 2:
        \\        return 20
        \\    elif x == 3:
        \\        return 30
        \\    elif x == 4:
        \\        return 40
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return classify(3)
    ;
    try t.expectEqual(@as(usize, 1), try nestingOf(text, "classify"));
}

test "control nesting counts five nested ifs as five levels" {
    const text =
        \\func five(x: int) -> int:
        \\    if x > 0:
        \\        if x > 1:
        \\            if x > 2:
        \\                if x > 3:
        \\                    if x > 4:
        \\                        return 5
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return five(9)
    ;
    try t.expectEqual(@as(usize, 5), try nestingOf(text, "five"));
}

test "control nesting counts a for holding an if holding a match as three levels" {
    const text =
        \\func scan(n: int) -> int:
        \\    mut total = 0
        \\    for i in range(n):
        \\        if i > 0:
        \\            match i:
        \\                case 1:
        \\                    total += 1
        \\                case 2:
        \\                    total += 2
        \\                case _:
        \\                    total += 0
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return scan(3)
    ;
    try t.expectEqual(@as(usize, 3), try nestingOf(text, "scan"));
}

test "control nesting counts a literal-arm match on an int as one level" {
    const text =
        \\func label(x: int) -> int:
        \\    mut out = 0
        \\    match x:
        \\        case 1:
        \\            out = 10
        \\        case 2:
        \\            out = 20
        \\        case 3:
        \\            out = 30
        \\        case 4:
        \\            out = 40
        \\        case _:
        \\            out = 0
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    return label(1)
    ;
    try t.expectEqual(@as(usize, 1), try nestingOf(text, "label"));
}

test "control nesting ignores a slice inside a loop body, which adds no level" {
    const text =
        \\func chunks(info: bytes) -> int:
        \\    mut total = 0
        \\    for i in range(3):
        \\        const piece = info[0:2]
        \\        total += len(piece)
        \\    return total
        \\
        \\
        \\func main() -> int:
        \\    return chunks(b"abc")
    ;
    try t.expectEqual(@as(usize, 1), try nestingOf(text, "chunks"));
}

test "control nesting counts an if written inside an else block as a nested level" {
    const text =
        \\func nested(x: int) -> int:
        \\    if x == 1:
        \\        return 1
        \\    else:
        \\        if x == 2:
        \\            return 2
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return nested(2)
    ;
    try t.expectEqual(@as(usize, 2), try nestingOf(text, "nested"));
}

/// Decision points of the named function in the checked program of `text`.
fn decisionsOf(text: []const u8, name: []const u8) !usize {
    var c = try language.Compilation.init(t.allocator, "quality.selka", text);
    defer c.deinit();
    try c.check();
    var result = try quality.analyze(t.allocator, c.program.?, c.src, c.syntax.?, .{});
    defer result.deinit();
    return result.functions[try index(&c, name)].structure.decisions;
}

test "decision points ignore a slice's bounds checks: one if after a slice measures one" {
    const text =
        \\func piece_then_branch(info: bytes) -> int:
        \\    const piece = info[0:2]
        \\    if len(info) == 3:
        \\        return len(piece)
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    return piece_then_branch(b"abc")
    ;
    try t.expectEqual(@as(usize, 1), try decisionsOf(text, "piece_then_branch"));
}

test "decision points count each if and elif of a chain and not its else: four arms measure three" {
    const text =
        \\func classify(x: int) -> int:
        \\    if x == 1:
        \\        return 10
        \\    elif x == 2:
        \\        return 20
        \\    elif x == 3:
        \\        return 30
        \\    else:
        \\        return 0
        \\
        \\
        \\func main() -> int:
        \\    return classify(2)
    ;
    try t.expectEqual(@as(usize, 3), try decisionsOf(text, "classify"));
}

test "decision points count a match as its arms less one: three arms, a case _ included, measure two" {
    const text =
        \\func pick(x: int) -> int:
        \\    mut out = 0
        \\    match x:
        \\        case 1:
        \\            out = 10
        \\        case 2:
        \\            out = 20
        \\        case _:
        \\            out = 0
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    return pick(2)
    ;
    try t.expectEqual(@as(usize, 2), try decisionsOf(text, "pick"));
}

test "decision points count a literal-arm match by its arms less one: three cases and a case _ measure three" {
    const text =
        \\func label(x: int) -> int:
        \\    mut out = 0
        \\    match x:
        \\        case 1:
        \\            out = 10
        \\        case 2:
        \\            out = 20
        \\        case 3:
        \\            out = 30
        \\        case _:
        \\            out = 0
        \\    return out
        \\
        \\
        \\func main() -> int:
        \\    return label(1)
    ;
    try t.expectEqual(@as(usize, 3), try decisionsOf(text, "label"));
}

test "decision points count each written and or once: a and b or c measures two" {
    const text =
        \\func mixed(a: bool, b: bool, c: bool) -> bool:
        \\    return a and b or c
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try t.expectEqual(@as(usize, 2), try decisionsOf(text, "mixed"));
}

test "decision points count each written try as one: a try measures one" {
    const text =
        \\func parse(text: str) -> int fails str:
        \\    if text == "":
        \\        fail "empty"
        \\    return len(text)
        \\
        \\
        \\func doubled(text: str) -> int fails str:
        \\    mut n = try parse(text)
        \\    return n * 2
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    try t.expectEqual(@as(usize, 1), try decisionsOf(text, "doubled"));
    try t.expectEqual(@as(usize, 1), try decisionsOf(text, "parse"));
}

const unwrap_text =
    \\func a(x: int) -> int?:
    \\    if x > 100:
    \\        return None
    \\    return Some(x + 1)
    \\
    \\
    \\func six_binds(x: int) -> int:
    \\    const a1 = a(x) else:
    \\        return 0
    \\    const a2 = a(a1) else:
    \\        return 0
    \\    const a3 = a(a2) else:
    \\        return 0
    \\    const a4 = a(a3) else:
    \\        return 0
    \\    const a5 = a(a4) else:
    \\        return 0
    \\    const a6 = a(a5) else:
    \\        return 0
    \\    return a6
    \\
    \\
    \\func deep(x: int) -> int:
    \\    match a(x):
    \\        case Some(b):
    \\            match a(b):
    \\                case Some(c):
    \\                    match a(c):
    \\                        case Some(d):
    \\                            match a(d):
    \\                                case Some(e):
    \\                                    match a(e):
    \\                                        case Some(f):
    \\                                            return f
    \\                                        case None:
    \\                                            return 5
    \\                                case None:
    \\                                    return 4
    \\                        case None:
    \\                            return 3
    \\                case None:
    \\                    return 2
    \\        case None:
    \\            return 1
    \\
    \\
    \\func flat(x: int) -> int:
    \\    const b = a(x) else:
    \\        return 1
    \\    const c = a(b) else:
    \\        return 2
    \\    const d = a(c) else:
    \\        return 3
    \\    const e = a(d) else:
    \\        return 4
    \\    const f = a(e) else:
    \\        return 5
    \\    return f
    \\
    \\
    \\func tests(x: int) -> int:
    \\    mut n = x
    \\    while a(n) is Some(m):
    \\        if m > 50:
    \\            return m
    \\        n = m * 2
    \\    if x == 0:
    \\        return 0
    \\    elif a(x) is Some(y):
    \\        if y > 5:
    \\            return y
    \\    return n
    \\
    \\
    \\func main() -> int:
    \\    return six_binds(1) + deep(1) + flat(1) + tests(1)
;

test "control nesting counts a bind-or-else's else block as one level and the statements after it as none (F-70)" {
    try t.expectEqual(@as(usize, 1), try nestingOf(unwrap_text, "six_binds"));
    // the nest `selka fix` flattens (W_MATCH_ELSE) measures five before and one after
    try t.expectEqual(@as(usize, 5), try nestingOf(unwrap_text, "deep"));
    try t.expectEqual(@as(usize, 1), try nestingOf(unwrap_text, "flat"));
}

test "control nesting counts while and elif over a binding is test as the source writes them" {
    try t.expectEqual(@as(usize, 2), try nestingOf(unwrap_text, "tests"));
}
