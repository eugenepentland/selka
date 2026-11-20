//! Coverage for `selka dump-syntax`: the frame, the layout description and the payload walker.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const codec = @import("persist_codec.zig");
const syntax_dump = language.syntax_dump;
const frontend_cache = language.frontend_cache;
const Subject = @import("syntax_dump_command.zig").Command(language);

const small_program = "func main() -> int:\n    return 0\n";

/// A program with records, enums, loops, text and arithmetic, so a corruption can land in many tables.
const richer_program =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\
    \\enum Shape:
    \\    dot
    \\    line(from: Point, to: Point)
    \\
    \\
    \\func total(values: int[]) -> int:
    \\    mut sum = 0
    \\    for v in values:
    \\        if v > 2:
    \\            sum += v * 2
    \\        else:
    \\            sum += v
    \\    return sum
    \\
    \\
    \\func reach(shape: Shape) -> int:
    \\    match shape:
    \\        case dot:
    \\            return 0
    \\        case line(from=a, to=b):
    \\            return b.x - a.x
    \\
    \\
    \\func main() -> int:
    \\    const p = Point(x=1, y=2)
    \\    const text = f"{p.x}-{p.y}"
    \\    return total([1, 2, 3]) + len(text) + reach(Shape.dot)
    \\
;

fn framed(arena: std.mem.Allocator, bytes: []const u8) !syntax_dump.Opened {
    const wire = try syntax_dump.frame(arena, "t.selka", bytes, .{});
    return syntax_dump.open(arena, wire);
}

fn payloadOf(arena: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var unit = try language.Compilation.init(arena, "t.selka", bytes);
    try unit.parse();
    return frontend_cache.encodeSyntax(arena, unit.syntax.?);
}

/// The offset of the first payload byte whose field path is `path`.
fn offsetOfPath(arena: std.mem.Allocator, payload: []const u8, path: []const u8) !?usize {
    var offset: usize = 0;
    while (offset < payload.len) : (offset += 1) {
        const stop = (try syntax_dump.fieldAt(arena, payload, offset)).?;
        if (std.mem.eql(u8, stop.path, path)) return offset;
    }
    return null;
}

/// How many corrupted payloads the walker and the codec judge differently.
fn disagreements(payload: []const u8) !usize {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const mutated = try t.allocator.dupe(u8, payload);
    defer t.allocator.free(mutated);
    var count: usize = 0;
    for (0..payload.len) |at| {
        for ([_]u8{ 0x00, 0x01, 0x02, 0x7f, 0xff }) |value| {
            mutated[at] = value;
            if (!try agrees(arena, mutated)) count += 1;
            mutated[at] = payload[at];
        }
        if (!try agrees(arena, payload[0..at])) count += 1;
        _ = state.reset(.retain_capacity);
    }
    return count;
}

/// Empty when the committed description is the generated one; otherwise the first
/// line that differs and the command that regenerates the file.
fn layoutDrift(arena: std.mem.Allocator, committed: []const u8, generated: []const u8) ![]const u8 {
    var left = std.mem.splitScalar(u8, committed, '\n');
    var right = std.mem.splitScalar(u8, generated, '\n');
    var number: usize = 1;
    while (true) : (number += 1) {
        const a = left.next();
        const b = right.next();
        if (a == null and b == null) return "";
        if (a != null and b != null and std.mem.eql(u8, a.?, b.?)) continue;
        const message = "ast.zig changed the syntax payload; line {d} of src/syntax_layout.txt is `{s}` but the generated line is `{s}`; " ++
            "regenerate with `selka dump-syntax --layout > src/syntax_layout.txt` and update the Selka side";
        return std.fmt.allocPrint(arena, message, .{ number, a orelse "<end>", b orelse "<end>" });
    }
}

fn encodeOnce(allocator: std.mem.Allocator, program: language.ast.Program) !void {
    const bytes = try frontend_cache.encodeSyntax(allocator, program);
    allocator.free(bytes);
}

fn agrees(arena: std.mem.Allocator, candidate: []const u8) !bool {
    const walker_accepts = (try syntax_dump.check(arena, candidate)) == null;
    var reader = codec.Reader.init(arena, candidate);
    const codec_accepts = if (reader.read(frontend_cache.StoredSyntax)) |_| reader.done() else |_| false;
    return walker_accepts == codec_accepts;
}

test "syntax dump: payload is the exact bytes the syntax cache stores" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const opened = try framed(arena, richer_program);
    const expected = try payloadOf(arena, richer_program);
    try t.expectEqual(syntax_dump.Mode.program, opened.mode);
    try t.expectEqual(syntax_dump.Outcome.parsed, opened.outcome);
    try t.expectEqualSlices(u8, expected, opened.payload);
    try t.expectEqual(@as(usize, 0), opened.diagnostics.len);
}

test "syntax dump: frame opens with magic, mode, trust, outcome and the payload length" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const wire = try syntax_dump.frame(arena, "t.selka", small_program, .{});
    const payload = try payloadOf(arena, small_program);
    try t.expectEqualStrings("SLKSYN01", wire[0..8]);
    try t.expectEqual(@as(u8, 0), wire[8]);
    try t.expectEqual(@as(u8, 0), wire[9]);
    try t.expectEqual(@as(u8, 0), wire[10]);
    try t.expectEqual(@as(u64, payload.len), std.mem.readInt(u64, wire[11..19], .little));
    try t.expectEqualSlices(u8, payload, wire[19..][0..payload.len]);
    try t.expectEqual(@as(u64, 0), std.mem.readInt(u64, wire[19 + payload.len ..][0..8], .little));
    try t.expectEqual(@as(usize, 27 + payload.len), wire.len);
}

test "syntax dump: is deterministic and does not depend on the path it is given" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const first = try syntax_dump.frame(arena, "a.selka", richer_program, .{});
    const second = try syntax_dump.frame(arena, "elsewhere/b.selka", richer_program, .{});
    try t.expectEqualSlices(u8, first, second);
}

test "syntax dump: a lexical error is a refused frame with the diagnostic and no payload" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const opened = try framed(state.allocator(), "x = $");
    try t.expectEqual(syntax_dump.Outcome.refused, opened.outcome);
    try t.expectEqual(@as(usize, 0), opened.payload.len);
    try t.expectEqual(@as(usize, 1), opened.diagnostics.len);
    const record = opened.diagnostics[0];
    try t.expectEqualStrings("E_TOKEN", record.code);
    try t.expectEqual(language.diagnostic.Severity.err, record.severity);
    try t.expectEqual(@as(usize, 4), record.span.start);
    try t.expectEqual(@as(usize, 5), record.span.end);
}

test "syntax dump: a module header is refused in module mode with its repair as an edit" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const opened = try framed(state.allocator(), "module main\n\nfunc f() -> int:\n    return 1\n");
    try t.expectEqual(syntax_dump.Mode.module, opened.mode);
    try t.expectEqual(syntax_dump.Outcome.refused, opened.outcome);
    try t.expectEqualStrings("E_MODULE_HEADER", opened.diagnostics[0].code);
    try t.expectEqual(@as(usize, 1), opened.diagnostics[0].fix.len);
    try t.expectEqualStrings("", opened.diagnostics[0].fix[0].text);
    try t.expectEqual(@as(usize, 0), opened.diagnostics[0].fix[0].span.start);
}

test "syntax dump: a file that opens with import is parsed as a module and the mode can be forced" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const imported = try framed(arena, "import helper\n\nfunc f() -> int:\n    return 1\n");
    try t.expectEqual(syntax_dump.Mode.module, imported.mode);
    try t.expectEqual(syntax_dump.Outcome.parsed, imported.outcome);
    const forced = try syntax_dump.open(arena, try syntax_dump.frame(arena, "t.selka", small_program, .{ .mode = .module }));
    try t.expectEqual(syntax_dump.Mode.module, forced.mode);
    try t.expectEqual(syntax_dump.Outcome.parsed, forced.outcome);
}

test "syntax dump: a frame with a wrong magic or trailing bytes does not open" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const wire = try syntax_dump.frame(arena, "t.selka", small_program, .{});
    const wrong = try arena.dupe(u8, wire);
    wrong[0] = 'X';
    try t.expectError(error.InvalidEncoding, syntax_dump.open(arena, wrong));
    const longer = try std.mem.concat(arena, u8, &.{ wire, "!" });
    try t.expectError(error.InvalidEncoding, syntax_dump.open(arena, longer));
}

const Shape = union(enum) { dot, line: struct { from: u32, to: u32 }, name: []const u8 };
const Drawing = struct { shapes: []const Shape, title: ?[]const u8, flag: bool };
const Drawing2 = struct { shapes: []const Shape, title: ?[]const u8, flag: bool, extra: u8 };
const Drawing3 = struct { shapes: []const Shape, flag: bool, title: ?[]const u8 };
const Drawing4 = struct { shapes: []const Shape, title: ?[]const u8, flag: u8 };
const Shape2 = union(enum) { line: struct { from: u32, to: u32 }, dot, name: []const u8 };
const Drawing5 = struct { shapes: []const Shape2, title: ?[]const u8, flag: bool };
const Colour = enum(u8) { red, green, blue };
const Palette = struct { main: Colour };
const Colour2 = enum(u8) { red, blue, green };
const Palette2 = struct { main: Colour2 };

test "syntax dump: the layout of a small type lists every field, tag and value in order" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const text = try syntax_dump.layoutOf(state.allocator(), Drawing, "Drawing");
    const expected = syntax_dump.layout_header ++
        "\nDrawing: struct\n  shapes: []syntax_dump_test.Shape\n  title: ?[]u8\n  flag: bool\n" ++
        "\nsyntax_dump_test.Shape: union, tag u2 in 1 byte(s)\n  0 dot: void\n  1 line: syntax_dump_test.Shape.line\n  2 name: []u8\n" ++
        "\nsyntax_dump_test.Shape.line: struct\n  from: u32\n  to: u32\n";
    try t.expectEqualStrings(expected, text);
}

test "syntax dump: an added, retyped, reordered or renumbered field changes the layout" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const base = try syntax_dump.layoutOf(arena, Drawing, "Drawing");
    const added = try syntax_dump.layoutOf(arena, Drawing2, "Drawing");
    const reordered = try syntax_dump.layoutOf(arena, Drawing3, "Drawing");
    const retyped = try syntax_dump.layoutOf(arena, Drawing4, "Drawing");
    const variants = try syntax_dump.layoutOf(arena, Drawing5, "Drawing");
    const colours = try syntax_dump.layoutOf(arena, Palette, "Palette");
    const swapped = try syntax_dump.layoutOf(arena, Palette2, "Palette");
    try t.expect(!std.mem.eql(u8, base, added));
    try t.expect(!std.mem.eql(u8, base, reordered));
    try t.expect(!std.mem.eql(u8, base, retyped));
    try t.expect(!std.mem.eql(u8, base, variants));
    try t.expect(!std.mem.eql(u8, colours, swapped));
    try t.expectEqualStrings(base, try syntax_dump.layoutOf(arena, Drawing, "Drawing"));
}

test "syntax dump: the committed layout description matches ast.zig, so a tree-shape change must update it" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const text = try syntax_dump.layout(arena);
    try t.expectEqualStrings("", try layoutDrift(arena, @embedFile("syntax_layout.txt"), text));
}

test "syntax dump: the walker accepts real payloads and agrees with the codec on every corruption" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const small = try payloadOf(arena, small_program);
    const rich = try payloadOf(arena, richer_program);
    try t.expect((try syntax_dump.check(arena, small)) == null);
    try t.expect((try syntax_dump.check(arena, rich)) == null);
    try t.expectEqual(@as(usize, 0), try disagreements(small));
}

test "syntax dump: a corrupted payload names the field path and the kind of damage" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const payload = try payloadOf(arena, richer_program);
    const tag = (try offsetOfPath(arena, payload, "nodes[2].data.@tag")).?;
    const damaged = try arena.dupe(u8, payload);
    damaged[tag] = 0xff;
    const stop = (try syntax_dump.check(arena, damaged)).?;
    try t.expectEqualStrings("nodes[2].data.@tag", stop.path);
    try t.expectEqual(syntax_dump.Kind.invalid, stop.kind);
    try t.expectEqual(tag, stop.offset);
    const cut = (try syntax_dump.check(arena, payload[0 .. payload.len - 1])).?;
    try t.expectEqual(syntax_dump.Kind.truncated, cut.kind);
    try t.expect(std.mem.startsWith(u8, cut.path, "docstrings"));
    const longer = try std.mem.concat(arena, u8, &.{ payload, "\x00" });
    const extra = (try syntax_dump.check(arena, longer)).?;
    try t.expectEqual(syntax_dump.Kind.trailing, extra.kind);
    try t.expectEqualStrings("@trailing", extra.path);
    try t.expectEqual(payload.len, extra.offset);
}

test "syntax dump: fieldAt names the field a payload byte belongs to" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const payload = try payloadOf(arena, small_program);
    const first = (try syntax_dump.fieldAt(arena, payload, 0)).?;
    try t.expectEqualStrings("types.resources.@len", first.path);
    try t.expectEqual(syntax_dump.Kind.located, first.kind);
    const name_start = (try offsetOfPath(arena, payload, "functions[0].name.start")).?;
    const middle = (try syntax_dump.fieldAt(arena, payload, name_start)).?;
    try t.expectEqualStrings("functions[0].name.start", middle.path);
    try t.expect((try syntax_dump.fieldAt(arena, payload, payload.len)) == null);
}

test "syntax dump: encodeSyntax reports a failed allocation and frees what it built" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    var unit = try language.Compilation.init(state.allocator(), "t.selka", small_program);
    try unit.parse();
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, frontend_cache.encodeSyntax(failing.allocator(), unit.syntax.?));
    try t.checkAllAllocationFailures(t.allocator, encodeOnce, .{unit.syntax.?});
}

const stand_in_program = "func main() -> int:\n    return clock_now[int](0)\n";

test "syntax dump: trusted parsing admits the reserved spellings that an untrusted parse refuses" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const plain = try syntax_dump.open(arena, try syntax_dump.frame(arena, "t.selka", stand_in_program, .{}));
    const trusted = try syntax_dump.open(arena, try syntax_dump.frame(arena, "t.selka", stand_in_program, .{ .trusted = true }));
    try t.expectEqual(syntax_dump.Outcome.refused, plain.outcome);
    try t.expectEqualStrings("E_INTERNAL_NAME", plain.diagnostics[0].code);
    try t.expect(!plain.trusted);
    try t.expectEqual(syntax_dump.Outcome.parsed, trusted.outcome);
    try t.expect(trusted.trusted);
}

fn differenceOf(arena: std.mem.Allocator, reference: []const u8, candidate: []const u8) ![]const u8 {
    return (try syntax_dump.difference(arena, reference, candidate)) orelse "";
}

test "syntax dump: difference is silent for equal frames and names the first difference otherwise" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const base = try syntax_dump.frame(arena, "t.selka", richer_program, .{});
    try t.expect((try syntax_dump.difference(arena, base, base)) == null);
    const module = try syntax_dump.frame(arena, "t.selka", richer_program, .{ .mode = .module });
    try t.expectEqualStrings("mode: reference program, candidate module", try differenceOf(arena, base, module));
    const trusted = try syntax_dump.frame(arena, "t.selka", richer_program, .{ .trusted = true });
    try t.expectEqualStrings("trusted: reference false, candidate true", try differenceOf(arena, base, trusted));
    const refused = try syntax_dump.frame(arena, "t.selka", "x = $", .{});
    try t.expectEqualStrings("outcome: reference parsed, candidate refused", try differenceOf(arena, base, refused));
    const other = try syntax_dump.frame(arena, "t.selka", "x = @", .{});
    const spans = try differenceOf(arena, refused, other);
    try t.expect(std.mem.startsWith(u8, spans, "diagnostic 0 differs in "));
    const truncated = try differenceOf(arena, base, base[0..20]);
    try t.expect(std.mem.startsWith(u8, truncated, "candidate frame does not open ("));
}

test "syntax dump: difference names the payload field of the first differing byte" {
    var state = std.heap.ArenaAllocator.init(t.allocator);
    defer state.deinit();
    const arena = state.allocator();
    const base = try syntax_dump.frame(arena, "t.selka", small_program, .{});
    const opened = try syntax_dump.open(arena, base);
    const at = (try offsetOfPath(arena, opened.payload, "functions[0].name.start")).?;
    const edited = try arena.dupe(u8, base);
    edited[19 + at] +%= 1;
    const told = try differenceOf(arena, base, edited);
    try t.expect(std.mem.startsWith(u8, told, try std.fmt.allocPrint(arena, "payload differs at byte {d} in functions[0].name.start", .{at})));
    const damaged = try arena.dupe(u8, base);
    damaged[19 + (try offsetOfPath(arena, opened.payload, "nodes[0].data.@tag")).?] = 0xff;
    const bad = try differenceOf(arena, base, damaged);
    try t.expect(std.mem.indexOf(u8, bad, "candidate payload is invalid at nodes[0].data.@tag") != null);
}

test "syntax dump: the command takes a file with flags in any order, --layout alone, and --diff with two files" {
    const dumped = Subject.parse(&.{ "a.selka", "--trusted", "--module" }).?.dump;
    try t.expectEqualStrings("a.selka", dumped.path);
    try t.expect(dumped.options.trusted);
    try t.expectEqual(syntax_dump.Mode.module, dumped.options.mode.?);
    try t.expect(Subject.parse(&.{"--layout"}).? == .layout);
    try t.expectEqualStrings("y", Subject.parse(&.{ "--diff", "x", "y" }).?.diff.candidate);
    try t.expect(Subject.parse(&.{}) == null);
    try t.expect(Subject.parse(&.{ "--layout", "a.selka" }) == null);
    try t.expect(Subject.parse(&.{ "a.selka", "b.selka" }) == null);
    try t.expect(Subject.parse(&.{ "--diff", "x" }) == null);
    try t.expect(Subject.parse(&.{ "a.selka", "--nope" }) == null);
}
