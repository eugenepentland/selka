//! Immutable constants fold scalars and retain managed literals before publication.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const print = std.debug.print;
fn scenario(allocator: std.mem.Allocator) !void {
    const text =
        \\const ANSWER: i64 = BASE * 2
        \\
        \\
        \\const BASE: i64 = 21
        \\
        \\
        \\const MIN: i64 = -9223372036854775808
        \\
        \\
        \\const SAFE: bool = False and 1 // 0 == 1
        \\
        \\
        \\const WIDTH: u8 = u8(BASE)
        \\
        \\
        \\func work[T]() -> i64:
        \\    if SAFE:
        \\        return MIN
        \\    return ANSWER + i64(WIDTH)
        \\
        \\
        \\func main() -> i64:
        \\    return work[bool]()
    ;
    var compilation = try language.Compilation.init(allocator, "constants.selka", text);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 63), (try native.run(&compilation)).value);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 63), (try native.run(&again)).value);
}
// spec: CONSTANT-1
test "scalar constants support forward dependencies checked widths short circuit and generic uses" {
    try scenario(t.allocator);
}
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const text = if (std.mem.eql(u8, path, "main.selka"))
        \\import constants
        \\
        \\
        \\func main() -> i64:
        \\    return constants.VALUE
    else if (std.mem.eql(u8, path, "constants.selka"))
        \\
        \\
        \\public const VALUE: i64 = FACTOR * 6
        \\
        \\
        \\const FACTOR: i64 = 7
    else
        return error.NotFound;
    return allocator.dupe(u8, text);
}
test "exported constants retain module identity and private initializer dependencies" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&program.compilation)).value);
}

fn sameNameProvider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const text = if (std.mem.eql(u8, path, "main.selka"))
        \\import left
        \\import right
        \\
        \\
        \\func main() -> i64:
        \\    return left.VALUE * 10 + right.VALUE
    else if (std.mem.eql(u8, path, "left.selka"))
        \\public const VALUE: i64 = 4
    else if (std.mem.eql(u8, path, "right.selka"))
        \\public const VALUE: i64 = 2
    else
        return error.NotFound;
    return allocator.dupe(u8, text);
}

test "constants with one name in two modules resolve by module identity" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = sameNameProvider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&program.compilation)).value);
}

const managed_literals =
    \\type Text = str
    \\type Octets = bytes
    \\const TEXT: Text = "hé🙂\n\0"
    \\const DATA: Octets = b"\x00\xff\n"
    \\const EMPTY_TEXT: str = ""
    \\const EMPTY_DATA: bytes = b""
    \\func read[T]() -> int:
    \\    return strings.char_count(TEXT) + len(DATA) + strings.char_count(EMPTY_TEXT) + len(EMPTY_DATA)
    \\func main() -> int:
    \\    if TEXT != "hé🙂\n\0" or DATA != b"\x00\xff\n":
    \\        return 1
    \\    return read[bool]() + read[int]() + DATA[1]
;
// spec: CONSTANT-2
test "managed constants preserve literal content aliases generic reads effects and formatting" {
    var compilation = try language.Compilation.init(t.allocator, "managed-constants.selka", managed_literals);
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 271), (try native.run(&compilation)).value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var again = try language.Compilation.init(t.allocator, "formatted.selka", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 271), (try native.run(&again)).value);
}

fn acceptConstant(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "valid-constant.selka", text);
    defer compilation.deinit();
    try compilation.check();
}

fn rejectConstant(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-constant.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec-case: CONSTANT-2
test "managed constants reject nonliteral initializers even when unused" {
    for ([_][]const u8{
        "const S: str = make()\nfunc make() -> str:\n    return \"x\"\n",
        "const B: bytes = make()\nfunc make() -> bytes:\n    return b\"x\"\n",
        "const S: str = \"x\" * 2\n",
        "const B: bytes = b\"x\" - b\"y\"\n",
        "const S: str = str(42)\n",
        "const B: bytes = bytes.fromhex(\"ff\")\n",
        "const S: str = OTHER + str(1)\nconst OTHER: str = \"x\"\n",
        "const B: bytes = OTHER + b\"y\"\nconst OTHER: bytes = embed_bytes(\"none.bin\")\n",
        "const S: str = f\"value {42}\"\n",
        "const S: str = f\"value {OTHER}\"\nconst OTHER: str = \"x\"\n",
        "const S: str = \"xy\"[0]\n",
        "const B: bytes = b\"xy\"[0:1]\n",
    }) |declaration| {
        const text = try std.mem.concat(t.allocator, u8, &.{ declaration, "func main() -> int:\n    return 0\n" });
        defer t.allocator.free(text);
        try rejectConstant(text, "E_CONSTANT_EXPRESSION");
    }
}

// F-54: a str or bytes constant joins literals and constants of its type with `+`, folded into one literal.
test "a text constant joined from literals and constants folds into the literal it spells" {
    try acceptConstant("const S: str = \"x\" + \"y\"\nfunc main() -> int:\n    return 0\n");
    try acceptConstant("const B: bytes = OTHER\nconst OTHER: bytes = b\"x\"\nfunc main() -> int:\n    return 0\n");
    var compilation = try language.Compilation.init(t.allocator, "joined-constants.selka",
        \\const SELECTOR: str = "#" + NAME + "-" + NAME
        \\const NAME: str = "ab"
        \\const RAW: bytes = b"\x00" + MAGIC
        \\const MAGIC: bytes = b"MY"
        \\
        \\
        \\func main() -> int:
        \\    return len(SELECTOR) * 10 + len(RAW)
        \\
    );
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 63), (try native.run(&compilation)).value);
}

// F-54: what a joined constant may not hold says what it may, and a cycle names its constants.
test "a joined text constant refuses a cycle, the other type and a scalar constant with their reasons" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const tail = "func main() -> int:\n    return 0\n";
    try expectConstantMessage(arena.allocator(), "const A: str = B + \"x\"\nconst B: str = \"y\" + A\n" ++ tail, "E_CONSTANT_CYCLE", "`A` -> `B` -> `A`");
    try expectConstantMessage(arena.allocator(), "const A: str = A + \"x\"\n" ++ tail, "E_CONSTANT_CYCLE", "`A` is built from itself");
    try expectConstantMessage(arena.allocator(), "const A: str = \"x\" + b\"y\"\n" ++ tail, "E_TYPE", "this literal is bytes");
    try expectConstantMessage(arena.allocator(), "const A: str = N + \"x\"\nconst N: int = 3\n" ++ tail, "E_TYPE", "`N` is not a str constant");
    try expectConstantMessage(arena.allocator(), "const A: str = \"x\" * 2\n" ++ tail, "E_CONSTANT_EXPRESSION", "joined with `+`");
    // Doubling joins are bounded: by the octets a constant holds, and by the operands a fold visits.
    const wide: [4096]u8 = @splat('x');
    const literal = try std.fmt.allocPrint(arena.allocator(), "\"{s}\"", .{&wide});
    try expectConstantMessage(arena.allocator(), try doublings(arena.allocator(), literal, 10), "E_CONSTANT_LIMIT", "more than 1 MiB");
    try expectConstantMessage(arena.allocator(), try doublings(arena.allocator(), literal, 10), "E_CONSTANT_LIMIT", "read it with embed_str");
    try expectConstantMessage(arena.allocator(), try doublings(arena.allocator(), "\"\"", 20), "E_CONSTANT_LIMIT", "more than 65,536 literals");
}

/// A program whose constant `C{count}` doubles `C0` (spelled `first`) `count` times by joining the one before it twice.
/// The largest is declared first, so it is the first one checked and no large literal is built before it fails.
fn doublings(allocator: std.mem.Allocator, first: []const u8, count: usize) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    var index = count;
    while (index > 0) : (index -= 1) try text.print(allocator, "const C{d}: str = C{d} + C{d}\n", .{ index, index - 1, index - 1 });
    try text.print(allocator, "const C0: str = {s}\nfunc main() -> int:\n    return len(C{d})\n", .{ first, count });
    return text.items;
}

fn expectConstantMessage(allocator: std.mem.Allocator, text: []const u8, code: []const u8, fragment: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "joined-constant.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
    const message = try allocator.dupe(u8, compilation.diagnostics.items[0].message);
    try t.expect(std.mem.indexOf(u8, message, fragment) != null);
}

// spec-case: CONSTANT-2
test "managed constants require matching literal types and keep byte or generic reads allocating" {
    try rejectConstant("const S: str = b\"x\"\nfunc main() -> int:\n    return 0\n", "E_TYPE");
    try rejectConstant("const B: bytes = \"x\"\nfunc main() -> int:\n    return 0\n", "E_TYPE");
    // A non-generic str constant read is a compile-time scalar, so an explicit
    // noalloc ceiling accepts it; a bytes constant, and any generic body that
    // returns one, still contributes managed_allocation.
    try acceptConstant("const S: str = \"x\"\n@noalloc\nfunc main() -> int:\n    return strings.char_count(S)\n");
    try rejectConstant("const B: bytes = b\"x\"\nfunc main() -> int effects():\n    return len(B)\n", "E_EFFECTS_REMOVED");
    try rejectConstant("const S: str = \"x\"\nfunc unused[T]() -> str effects():\n    return S\nfunc main() -> int:\n    return 0\n", "E_EFFECTS_REMOVED");
    try rejectConstant("const B: bytes = b\"x\"\nfunc unused[T]() -> bytes effects():\n    return B\nfunc main() -> int:\n    return 0\n", "E_EFFECTS_REMOVED");
}

// spec-case: CONST-FLOAT-1
test "float constants reject overflowing literals and mismatched declared types" {
    try rejectConstant("const BAD: float = 1e309\nfunc main() -> int:\n    return 0\n", "E_FLOAT_RANGE");
    try rejectConstant("const BAD: int = 3.14\nfunc main() -> int:\n    return 0\n", "E_TYPE");
    try rejectConstant("const BAD: float = True\nfunc main() -> int:\n    return 0\n", "E_TYPE");
}

// spec-case: CONST-FLOAT-2
test "float constants reject integer-only operators and float source calls" {
    try rejectConstant("const BAD: float = 1.0 & 2.0\nfunc main() -> int:\n    return 0\n", "E_FLOAT_OPERATION");
    try rejectConstant("const BAD: float = source()\nfunc source() -> float:\n    return 1.0\nfunc main() -> int:\n    return 0\n", "E_CONSTANT_TYPE");
}

// spec-case: CONST-FLOAT-3
test "constant float integer conversions reject nonfinite and width boundaries" {
    for ([_][]const u8{
        "int(0.0 / 0.0)",              "int(1.0 / 0.0)",    "int(-1.0 / 0.0)",
        "i8(128.0)",                   "i8(-129.0)",        "u8(256.0)",
        "u8(-1.0)",                    "i16(32768.0)",      "u16(65536.0)",
        "i32(2147483648.0)",           "u32(4294967296.0)", "i64(9223372036854775808.0)",
        "u64(18446744073709551616.0)",
    }) |conversion| {
        const ty = conversion[0..std.mem.indexOfScalar(u8, conversion, '(').?];
        const text = try std.fmt.allocPrint(t.allocator, "const BAD: {s} = {s}\nfunc main() -> int:\n    return 0\n", .{ ty, conversion });
        defer t.allocator.free(text);
        try rejectConstant(text, "E_CONSTANT_ARITHMETIC");
    }
}

// ACM-2, the bytes half: a module constant is not a list, record, option or union, and its type error says what it may be.
test "a module constant of a list, record or option type is E_CONSTANT_TYPE and the message says a table is bytes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const tail = "func main() -> int:\n    return 0\n";
    for ([_][]const u8{
        "const A: int[] = [1, 2]\n",
        "const A: float[] = [1.5]\n",
        "const FIRST: str[] = [\"Kor\", \"Mal\"]\n",
        "const A: int[][] = [[1]]\n",
        "record Row:\n    a: int\n\nconst A: Row = Row(a=1)\n",
        "const A: int? = 1\n",
    }) |declaration| {
        const text = try std.mem.concat(arena.allocator(), u8, &.{ declaration, tail });
        try expectConstantMessage(arena.allocator(), text, "E_CONSTANT_TYPE", "a table of numbers is a `bytes` constant");
        try expectConstantMessage(arena.allocator(), text, "E_CONSTANT_TYPE", "`bytes.read_u32_le`");
        try expectConstantMessage(arena.allocator(), text, "E_CONSTANT_TYPE", "are not constants yet");
    }
}

const crc_program =
    \\import buffers
    \\import bytes
    \\
    \\const CRC: bytes = crc_table()
    \\const CLAMPED: bytes = clamped(300)
    \\
    \\func crc_table() -> bytes:
    \\    mut table = buffers.empty()
    \\    for index in range(256):
    \\        mut value = index
    \\        for step in range(8):
    \\            if bit_and(value, 1) == 1:
    \\                value = bit_xor(shift_right(value, 1), 3988292384)
    \\            else:
    \\                value = shift_right(value, 1)
    \\        for part in range(4):
    \\            _ = buffers.append_byte(mut table, bit_and(shift_right(value, part * 8), 255))
    \\    return bytes(table)
    \\
    \\func clamped(count: int) -> bytes:
    \\    mut table = buffers.empty()
    \\    for index in range(count):
    \\        _ = buffers.append_byte(mut table, index)
    \\    return bytes(table)
    \\
    \\func main() -> int:
    \\    if len(CRC) != 1024 or bytes.read_u32_le(CRC, 4 * 255) != 755167117u32:
    \\        return 1
    \\    return len(CLAMPED) - 214
;
// ACM-2: a source function builds the octets, an octet outside 0 to 255 appends nothing (as at run time), and the program runs.
test "a bytes constant built by a source function holds the octets it computed" {
    try fixture.expect(t.allocator, crc_program, .{}, 42);
}

/// Check `text` as a project and require its first diagnostic to carry `code` and a message with `fragment`.
fn expectProjectMessage(arena: std.mem.Allocator, text: []const u8, code: []const u8, fragment: []const u8) !void {
    const checked = try fixture.check(arena, text);
    try t.expect(!checked.passed);
    try t.expectEqualStrings(code, checked.diagnostics[0].code);
    try t.expect(std.mem.indexOf(u8, checked.diagnostics[0].message, fragment) != null);
}

// ACM-2: what a table function may hold is the closed set of the guide; each form outside it is refused where it stands.
test "a table function refuses what the guide does not list" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const head = "import buffers\nimport bytes\n\nconst B: bytes = make()\n\n";
    const tail = "\n\nfunc main() -> int:\n    return 0\n";
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "func make() -> bytes:\n    return b\"x\"", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    mut xs: int[] = []\n    return b\"x\"", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    mut table = buffers.empty()\n    buffers.append(mut table, b\"x\")\n    return bytes(table)", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    _ = buffers.empty()\n    return b\"x\"", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    mut table = buffers.empty()\n    return table", .code = "E_TYPE" },
        .{ .body = "func make() -> bytes:\n    mut table = buffers.empty()\n    mut other = table\n    return bytes(other)", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    mut table = buffers.empty()\n    if len(table) == 0:\n        return bytes(table)\n    return bytes(table)", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    mut table = buffers.empty()\n    put(mut table)\n    return bytes(table)\n\n\nfunc put(mut table: byte_buffer):\n    _ = buffers.append_byte(mut table, 1)", .code = "E_CONSTANT_EXPRESSION" },
        .{ .body = "func make() -> bytes:\n    mut table = buffers.empty()\n    _ = buffers.append_byte(mut table, 1)", .code = "E_CONSTANT_RETURN" },
        .{ .body = "func make() -> int:\n    return 1", .code = "E_CONSTANT_TYPE" },
    };
    // A parameter that is not an integer or a bool has no value to pass.
    try fixture.rejectsWith(arena.allocator(), "import buffers\n\nconst B: bytes = make(1.5)\n\nfunc make(ratio: float) -> bytes:\n    return b\"x\"" ++ tail, "E_CONSTANT_TYPE");
    for (cases) |case| {
        const text = try std.mem.concat(arena.allocator(), u8, &.{ head, case.body, tail });
        fixture.rejectsWith(arena.allocator(), text, case.code) catch |err| {
            print("case did not give {s}:\n{s}\n", .{ case.code, case.body });
            return err;
        };
    }
}

// ACM-2: a str constant is still a literal, a join or an embed, so a call for one stays refused with the same code.
test "a str constant built by a call and a call that is not a source function stay E_CONSTANT_EXPRESSION" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(), "import bytes\nconst B: bytes = bytes.fromhex(\"ff\")\nfunc main() -> int:\n    return 0\n", "E_CONSTANT_EXPRESSION");
    try fixture.rejectsWith(arena.allocator(), "const S: str = make()\nfunc make() -> str:\n    return \"x\"\nfunc main() -> int:\n    return 0\n", "E_CONSTANT_EXPRESSION");
}

/// A program whose table constant is built by `body` (the statements that append octets to `table`).
fn tableProgram(allocator: std.mem.Allocator, body: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "import buffers\n\nconst B: bytes = make()\n\n\nfunc make() -> bytes:\n    mut table = buffers.empty()\n{s}    return bytes(table)\n\n\nfunc main() -> int:\n    return len(B)\n", .{body});
}

// ACM-2, rule 3: a table has a size limit and a work limit, and `E_CONSTANT_LIMIT` names the one it hit.
test "a table constant over its size limit or its work limit is E_CONSTANT_LIMIT and names the limit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const over = try tableProgram(arena.allocator(), "    for index in range(262145):\n        _ = buffers.append_byte(mut table, 7)\n");
    const checked = try fixture.check(arena.allocator(), over);
    try t.expectEqualStrings("E_CONSTANT_LIMIT", checked.diagnostics[0].code);
    try t.expect(std.mem.indexOf(u8, checked.diagnostics[0].message, "size limit of 262,144 octets") != null);
    try t.expect(std.mem.indexOf(u8, checked.diagnostics[0].message, "embed_bytes") != null);
    // Reading a constant costs a unit for each function in the program, so this loop reaches the limit in few steps.
    const endless = try std.mem.concat(arena.allocator(), u8, &.{ try tableProgram(arena.allocator(), "    mut count = 0\n    while True:\n        count += ONE\n"), "\n\nconst ONE: int = 1\n" });
    try expectProjectMessage(arena.allocator(), endless, "E_CONSTANT_LIMIT", "work limit of 33,554,432 units");
    // A scalar constant keeps its own limit.
    const scalar = "const N: int = spin()\nfunc spin() -> int:\n    mut count = 0\n    while True:\n        count += 1\n    return count\n";
    try expectConstantMessage(arena.allocator(), scalar ++ "func main() -> int:\n    return N\n", "E_CONSTANT_LIMIT", "exceeds nesting or work budget");
}

// ACM-2, rule 4: a table constant is read and never written; the refusals are the ones a constant already has.
test "a table constant cannot be written, moved with own, or passed as mut" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const head = "import buffers\n\nconst TABLE: bytes = make()\n\n\nfunc make() -> bytes:\n    mut table = buffers.empty()\n    _ = buffers.append_byte(mut table, 1)\n    return bytes(table)\n\n\n";
    try fixture.rejectsWith(arena.allocator(), head ++ "func main() -> int:\n    TABLE[0] = 3\n    return 0\n", "E_UNKNOWN_NAME");
    try fixture.rejectsWith(arena.allocator(), head ++ "func main() -> int:\n    buffers.append(mut TABLE, b\"x\")\n    return 0\n", "E_UNKNOWN_NAME");
    try fixture.accept(arena.allocator(), head ++ "func main() -> int:\n    return len(TABLE) - 1\n");
}

/// Serves `main.selka` and a `buffers.selka` beside it, and every other standard module from the compiler's own text: the way `--local-stdlib`,
/// or `check` of a standard-named file such as `src/stdlib/flate.selka`, reads the library from source beside the entry.
const Beside = struct {
    entry: []const u8,
    buffers: []const u8,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Beside = @ptrCast(@alignCast(context.?));
        const text = if (std.mem.eql(u8, path, "main.selka")) self.entry else if (std.mem.eql(u8, path, "buffers.selka")) self.buffers else language.standard_library.source(path) orelse return error.NotFound;
        if (text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, text);
    }
};

/// The first error of checking `entry` with the standard library read from source beside it (`buffers` served as `buffers`), or null when it checks.
fn checkBeside(arena: std.mem.Allocator, entry: []const u8, buffers: []const u8) !?language.diagnostic.Diagnostic {
    var served: Beside = .{ .entry = entry, .buffers = buffers };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &served, .read = Beside.read }, "main", .{ .standard = .{ .from_provider = true } });
    // A source the parser refuses (a `builtin func` outside the library) stops the index: `project.problem` is its diagnostic.
    var index = language.interfaces.build(&project) catch |failure| switch (failure) {
        error.SourceError => {
            const problem = project.problem orelse return error.TestUnexpectedResult;
            return .{ .code = problem.code, .span = problem.site.span, .message = problem.message };
        },
        else => return failure,
    };
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.check() catch |failure| switch (failure) {
        error.SourceError => {
            for (compilation.diagnostics.items.items) |item| if (item.severity == .err) return item;
            return error.TestUnexpectedResult;
        },
        else => return failure,
    };
    return null;
}

/// Require that `entry` checks with the standard library read from source beside it, naming its first error otherwise.
fn expectBesideAccepted(arena: std.mem.Allocator, entry: []const u8, buffers: []const u8) !void {
    const found = try checkBeside(arena, entry, buffers);
    if (found) |item| print("{s}: {s}\n", .{ item.code, item.message });
    try t.expect(found == null);
}

// ACM-2, rule 2: the standard library's `buffers` calls are the table function's operations when the library is read from source beside
// the entry, as `scripts/check_programs.py` checks `src/stdlib/flate.selka`; the path of the module is not what tells.
test "a table function's buffers calls are the standard library's when it is read from source beside the entry" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const entry = try std.mem.concat(arena.allocator(), u8, &.{ language.standard_library.source("flate.selka").?, "\n\nfunc main() -> int:\n    return 0\n" });
    try expectBesideAccepted(arena.allocator(), entry, language.standard_library.source("buffers.selka").?);
}

// ACM-2, rule 2: a module of the user's own that is called `buffers` is not the standard library, because its bytes are not the
// compiler's own `buffers.selka`: its `empty` is called as the function it is.
test "a module called buffers that is not the standard library is an ordinary module in a constant" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const entry = "import buffers\n\nconst N: int = buffers.empty() + 5\n\n\nfunc main() -> int:\n    return N - 12\n";
    try expectBesideAccepted(arena.allocator(), entry, "public func empty() -> int:\n    return 7\n");
    // An edited copy of the library is no longer the library: it may not declare `builtin func`, and a table function is not run against it.
    const edited = try std.mem.concat(arena.allocator(), u8, &.{ language.standard_library.source("buffers.selka").?, "\n# edited\n" });
    const found = try checkBeside(arena.allocator(), "import buffers\n\nfunc main() -> int:\n    return 0\n", edited);
    try t.expectEqualStrings("E_BUILTIN_DECLARATION", found.?.code);
}

/// The dependency context `prepare` gives the function `read` of `entry`, with the standard library read beside it.
fn readerContext(arena: std.mem.Allocator, entry: []const u8) ![32]u8 {
    var served: Beside = .{ .entry = entry, .buffers = language.standard_library.source("buffers.selka").? };
    var project = language.project.Project.init(arena);
    try project.load(.{ .context = &served, .read = Beside.read }, "main", .{ .standard = .{ .from_provider = true } });
    var index = try language.interfaces.build(&project);
    const compilation = try language.project_compile.Compilation.init(&index);
    const prepared = try language.semantic_key.prepare(arena, compilation.src, compilation.syntax, .{ .build = "test", .mutation = "test" }, &index, null);
    for (compilation.syntax.functions, 0..) |function, at| {
        if (std.mem.eql(u8, compilation.src.text(function.name), "read")) return prepared.contexts[at];
    }
    return error.TestUnexpectedResult;
}

/// A table built by `squares`, whose body `step` is, and a reader of one of its octets.
fn tableEntry(arena: std.mem.Allocator, step: []const u8) ![]const u8 {
    return std.mem.concat(arena, u8, &.{
        "import buffers\n\nconst SQUARES: bytes = squares(4)\n\n\nfunc squares(count: int) -> bytes:\n    mut table = buffers.empty()\n",
        "    for index in range(count):\n        _ = buffers.append_byte(mut table, ",
        step,
        ")\n    return bytes(table)\n\n\n",
        "func read() -> int:\n    return int(SQUARES[3])\n\n\nfunc main() -> int:\n    return read()\n",
    });
}

// CONSTSTALE: a reader folds what a table holds, so its key holds the table's octets: an edit of the function that builds the table
// changes the reader's dependency context when the octets change, and leaves it as it was when they do not.
test "a reader of a table constant is keyed on the table's octets, not on the body that builds them" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const before = try readerContext(a, try tableEntry(a, "index * index"));
    const changed = try readerContext(a, try tableEntry(a, "index * index + 1"));
    const same = try readerContext(a, try tableEntry(a, "1 + index * index"));
    try t.expect(!std.mem.eql(u8, &before, &changed));
    try t.expectEqualSlices(u8, &changed, &same);
}
