//! Stored syntax v2: a module's declaration part and body sections reassemble to the parse, a function whose tree is not an interval of
//! its own keeps it in the declaration part, and a damaged section is found.
const std = @import("std");
const product = @import("product.zig");
const t = std.testing;
const ast = @import("ast.zig");
const source = @import("source.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const diagnostic = @import("diagnostic.zig");
const codec = @import("persist_codec.zig");
const store = @import("syntax_store.zig");
const store_check = @import("syntax_store_check.zig");
const frontend_cache = @import("frontend_cache.zig");
const syntax_dump = @import("syntax_dump.zig");

const fixture =
    \\const BASE: int = 8
    \\const SKIP: int = ord("a")
    \\
    \\
    \\record Point:
    \\    x: int = 0
    \\    y: int = 8
    \\
    \\
    \\enum Status:
    \\    ok
    \\    missing
    \\    failed
    \\
    \\
    \\@requires(n > 0, "n is positive")
    \\public func scale(n: int, factor: int = 2) -> int:
    \\    mut total = 0
    \\    for k in range(n):
    \\        total = total + k * factor
    \\    return total
    \\
    \\
    \\func classify(ch: int) -> int:
    \\    match ch:
    \\        case ord("+") | ord("-"):
    \\            return 1
    \\        case 0x30 | SKIP:
    \\            return 2
    \\        case _:
    \\            return 0
    \\
    \\
    \\func status(code: int) -> Status:
    \\    if code == 0:
    \\        return Status.ok
    \\    return Status.failed
    \\
    \\
    \\func main() -> int:
    \\    const point = Point(x=1)
    \\    return scale(BASE) + classify(point.x) + len("text")
    \\
;

/// Parse `bytes` as a module the way `selka dump-syntax --module` does; null when it does not parse.
fn parseModule(scratch: std.mem.Allocator, path: []const u8, bytes: []const u8) !?ast.Program {
    const src = try source.Source.init(scratch, path, bytes);
    var sink: diagnostic.Sink = .{ .allocator = scratch };
    const tokens = lexer.lex(scratch, src.bytes, &sink) catch return null;
    var reading: parser.Parser = .{ .src = src, .storage = scratch, .tokens = tokens, .sink = &sink };
    return reading.parseModule() catch null;
}

fn indexOf(src: source.Source, program: ast.Program, name: []const u8) !usize {
    for (program.functions, 0..) |function, index| if (std.mem.eql(u8, src.text(function.name), name)) return index;
    return error.TestUnexpectedResult;
}

/// The encoded bytes of a body, to compare two bodies by value.
fn bodyBytes(allocator: std.mem.Allocator, body: store.Body) ![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write(store.Body, body);
    return writer.bytes.toOwnedSlice(allocator);
}

fn fixtureProgram(arena: std.mem.Allocator) !ast.Program {
    return (try parseModule(arena, "fixture.selka", fixture)) orelse error.TestUnexpectedResult;
}

fn fixtureSource(arena: std.mem.Allocator) !source.Source {
    return source.Source.init(arena, "fixture.selka", fixture);
}

test "a module reassembles from its declaration part and its body sections" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try fixtureProgram(arena);
    const summary = try store_check.check(arena, try fixtureSource(arena), program);
    // The six functions are the two constants, whose trees stay with the declarations, and four lazy bodies.
    try t.expectEqual(@as(usize, 4), summary.lazy);
    try t.expectEqual(@as(usize, 2), summary.eager);
    const entry = try store.encode(arena, try fixtureSource(arena), program);
    const rebuilt = try store.reassemble(arena, entry);
    const expected = try frontend_cache.encodeSyntax(arena, program);
    const actual = try frontend_cache.encodeSyntax(arena, rebuilt);
    try t.expectEqualSlices(u8, expected, actual);
}

test "the declaration part is read without a body section and a body alone from its own" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try fixtureProgram(arena);
    const entry = try store.encode(arena, try fixtureSource(arena), program);
    const header = try store.Header.parse(entry);
    // Only the header, the declaration part and the extent table are given.
    const declarations = try store.decodeDeclarations(arena, entry[0..@intCast(header.prefixLen())]);
    try t.expectEqual(@as(usize, 4), declarations.bodies.len);
    try t.expectEqual(program.nodes.items.len, declarations.header.node_count);
    const reference = declarations.bodies[1];
    const body = try store.decodeBody(arena, declarations, 1, try declarations.section(entry, 1));
    const wanted = try bodyBytes(arena, store.bodyOfParse(program, reference));
    const got = try bodyBytes(arena, body);
    try t.expectEqualSlices(u8, wanted, got);
    // The section is not in the prefix.
    try t.expectError(error.Truncated, declarations.section(entry[0..@intCast(header.prefixLen())], 1));
}

test "a function whose tree another function shares keeps its tree in the declaration part" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var program = try fixtureProgram(arena);
    const src = try source.Source.init(arena, "fixture.selka", fixture);
    const functions = try arena.dupe(ast.Function, program.functions);
    functions[try indexOf(src, program, "status")].body = functions[try indexOf(src, program, "classify")].body;
    program.functions = functions;
    const summary = try store_check.check(arena, try fixtureSource(arena), program);
    // `classify` and `status` now reach the same statements, so both give way.
    try t.expectEqual(@as(usize, 2), summary.lazy);
    try t.expectEqual(@as(usize, 4), summary.eager);
}

test "a damaged body section is found and the body comes from a re-parse" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try fixtureProgram(arena);
    const entry = try arena.dupe(u8, try store.encode(arena, try fixtureSource(arena), program));
    const declarations = try store.decodeDeclarations(arena, entry);
    const section = try declarations.section(entry, 2);
    entry[@intCast(section.ptr - entry.ptr + section.len / 2)] ^= 0x40;
    try t.expectError(error.Damaged, store.reassemble(arena, entry));
    try t.expectError(error.Damaged, store.decodeBody(arena, declarations, 2, try declarations.section(entry, 2)));
    // The module's bytes are in memory: parsing them again gives the same ids, so the same body.
    const again = (try parseModule(arena, "fixture.selka", fixture)).?;
    const recovered = try bodyBytes(arena, store.bodyOfParse(again, declarations.bodies[2]));
    const original = try bodyBytes(arena, store.bodyOfParse(program, declarations.bodies[2]));
    try t.expectEqualSlices(u8, original, recovered);
}

test "a damaged declaration part or header is refused" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try fixtureProgram(arena);
    const entry = try arena.dupe(u8, try store.encode(arena, try fixtureSource(arena), program));
    const damaged = try arena.dupe(u8, entry);
    damaged[store.Header.size + 5] ^= 1;
    try t.expectError(error.Damaged, store.decodeDeclarations(arena, damaged));
    const foreign = try arena.dupe(u8, entry);
    foreign[0] ^= 1;
    try t.expectError(error.InvalidEncoding, store.decodeDeclarations(arena, foreign));
    try t.expectError(error.Truncated, store.decodeDeclarations(arena, entry[0 .. store.Header.size - 1]));
}

/// Encode, reassemble and compare every `.selka` module under `directories` that parses; the count of those that did.
fn checkCorpus(directories: []const []const u8) !usize {
    var checked: usize = 0;
    for (directories) |directory| {
        var opened = std.Io.Dir.cwd().openDir(t.io, directory, .{ .iterate = true }) catch continue;
        defer opened.close(t.io);
        var walker = try opened.walk(t.allocator);
        defer walker.deinit();
        while (try walker.next(t.io)) |entry| {
            if (entry.kind != .file or !product.isSource(entry.path)) continue;
            var arena_state = std.heap.ArenaAllocator.init(t.allocator);
            defer arena_state.deinit();
            const arena = arena_state.allocator();
            const bytes = try opened.readFileAlloc(t.io, entry.path, arena, .limited(8 * 1024 * 1024));
            const program = (try parseModule(arena, entry.path, bytes)) orelse continue;
            _ = try store_check.check(arena, try source.Source.init(arena, entry.path, bytes), program);
            checked += 1;
        }
    }
    return checked;
}

test "every module of the repository reassembles from its parts" {
    const checked = try checkCorpus(&.{ "src", "examples", "test/fixtures" });
    try t.expect(checked >= 40);
}

test "dump-syntax can check a module's stored encoding and leaves its ordinary frame alone" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const verdict = try syntax_dump.storeCheck(arena, "fixture.selka", fixture, .{ .mode = .module });
    try t.expect(verdict.ok);
    try t.expect(std.mem.startsWith(u8, verdict.line, "store-check ok "));
    try t.expect(std.mem.indexOf(u8, verdict.line, "lazy=4 eager=2") != null);
    const refused = try syntax_dump.storeCheck(arena, "broken.selka", "func (", .{ .mode = .module });
    try t.expect(refused.ok);
    try t.expectEqualStrings("store-check refused\n", refused.line);
    // The frame `selka dump-syntax` prints is still the parse-order tables.
    const frame = try syntax_dump.frame(arena, "fixture.selka", fixture, .{ .mode = .module });
    const program = try fixtureProgram(arena);
    const tables = try frontend_cache.encodeSyntax(arena, program);
    try t.expect(std.mem.indexOf(u8, frame, tables) != null);
}

test "an entry carries the literals the catalog registers and the retired constructs a rejection looks for" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try fixtureProgram(arena);
    const src = try fixtureSource(arena);
    const entry = try store.encode(arena, src, program);
    const declarations = try store.decodeDeclarations(arena, entry);
    // The fixture's text literals, in node order (`ord("a")`, the two alternatives of a case and `len("text")`); nothing in it is retired.
    try t.expectEqual(@as(usize, 4), declarations.facts.literals.len);
    try t.expectEqualStrings("\"text\"", src.text(declarations.facts.literals[3].span));
    try t.expect(@import("ast_literals.zig").same(declarations.facts.literals, try @import("ast_literals.zig").scan(arena, src, program)));
    try t.expect(!declarations.facts.retired.any());
    const retired_text = "func pair() -> int:\n    const both = (1, 2)\n    return 0\n";
    const retired_program = (try parseModule(arena, "retired.selka", retired_text)).?;
    const retired_src = try source.Source.init(arena, "retired.selka", retired_text);
    const stored = try store.decodeDeclarations(arena, try store.encode(arena, retired_src, retired_program));
    try t.expect(stored.facts.retired.tuple);
    try t.expect(!stored.facts.retired.arena_scope and !stored.facts.retired.wrap);
    // The fact is what a scan of the tables finds.
    try t.expectEqual(ast.Retired{ .tuple = true }, (try store.factsOf(arena, retired_src, retired_program)).retired);
}
