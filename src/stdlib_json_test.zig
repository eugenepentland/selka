//! Standard JSON parses strict RFC 8259 text and renders it back without whitespace.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

// spec: STANDARD-JSON-1
test "standard json parses renders navigates and rejects noncompliant documents" {
    try fixture.run(t.allocator, @embedFile("stdlib/fixtures/json.my"), 42);
}

// spec-case: STANDARD-JSON-1
test "standard json scanner and writer lower scalar positions and buffered spans" {
    const language = @import("compiler.zig");
    var entry: fixture.Entry = .{ .text =
        \\module main
        \\import json
        \\def main() -> int:
        \\    match json.loads("[1,\"x\"]"):
        \\        case Ok(value):
        \\            return len(json.dumps(value))
        \\        case Err(_):
        \\            return 0
    };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = fixture.Entry.read });
    defer program.deinit();
    try expectScalarPosition(program.compilation.program.?.records);
    var integer_range = false;
    var float_range = false;
    var quoted = false;
    for (program.compilation.code.?.functions) |function| {
        const number = std.mem.endsWith(u8, function.name, "::read_number");
        const quote = std.mem.endsWith(u8, function.name, "::write_quoted");
        for (function.scope.instructions) |instruction| switch (instruction.op) {
            .buffer_operation => |operation| {
                if (number) {
                    integer_range = integer_range or operation.kind == .parse_int_range;
                    float_range = float_range or operation.kind == .parse_float_range;
                    try t.expect(operation.kind != .slice and operation.kind != .decode);
                }
                if (quote and operation.kind == .buffer_append_range) quoted = true;
            },
            else => {},
        };
    }
    try t.expect(integer_range and float_range and quoted);
    const emitted = try program.compilation.emitQbe(t.allocator);
    defer t.allocator.free(emitted);
    try t.expect(std.mem.indexOf(u8, emitted, "myl_native_bytes_buffer_append_range") != null);
}

/// The private scanner's position is a scalar; passing it to an inout callee
/// updates the caller's byte offset without allocating or copying a list cell.
fn expectScalarPosition(records: []const @import("typed.zig").Record) !void {
    for (records) |record| {
        if (!std.mem.endsWith(u8, record.name, "::Scanner")) continue;
        for (record.fields) |field| {
            if (!std.mem.eql(u8, field.name, "position")) continue;
            return t.expectEqual(@import("typed.zig").Type.i64, field.ty);
        }
    }
    return error.TestUnexpectedResult;
}

// spec-case: STANDARD-JSON-1
test "standard json keeps parsed values rooted under collection stress" {
    try fixture.stress(t.allocator, "module main\nimport json\n" ++
        "def main() -> int:\n" ++
        "    source = \"{\\\"rows\\\":[{\\\"n\\\":40},{\\\"n\\\":2}]}\"\n" ++
        "    match json.loads(source):\n" ++
        "        case Ok(document):\n" ++
        "            if json.dumps(document) != source:\n" ++
        "                return 1\n" ++
        "            return total(document)\n" ++
        "        case Err(_):\n" ++
        "            return 2\n" ++
        "def total(document: json.Json) -> int:\n" ++
        "    match json.get(document, \"rows\"):\n" ++
        "        case Some(rows):\n" ++
        "            return summed(rows)\n" ++
        "        case None:\n" ++
        "            return 3\n" ++
        "def summed(rows: json.Json) -> int:\n" ++
        "    sum = 0\n" ++
        "    index = 0\n" ++
        "    while index < 2:\n" ++
        "        match json.at(rows, index):\n" ++
        "            case Some(row):\n" ++
        "                sum += field(row)\n" ++
        "            case None:\n" ++
        "                return 4\n" ++
        "        index += 1\n" ++
        "    return sum\n" ++
        "def field(row: json.Json) -> int:\n" ++
        "    match json.get(row, \"n\"):\n" ++
        "        case Some(value):\n" ++
        "            match json.as_int(value):\n" ++
        "                case Some(count):\n" ++
        "                    return count\n" ++
        "                case None:\n" ++
        "                    return 0\n" ++
        "        case None:\n" ++
        "            return 0\n", 42);
}

// spec: STDLIB-ERROR-UNION-1
test "standard json error unions carry a matchable category and a message helper" {
    try fixture.run(t.allocator,
        \\module main
        \\import json
        \\
        \\
        \\union AppError:
        \\    Json: json.Error
        \\
        \\
        \\def size(source: str) -> Result[int, AppError]:
        \\    document = json.loads(source)?
        \\    return Ok(len(json.dumps(document)))
        \\
        \\
        \\def main() -> int:
        \\    match size("{}"):
        \\        case Ok(count):
        \\            if count != 2:
        \\                return 1
        \\        case Err(_):
        \\            return 2
        \\    match size("{bad}"):
        \\        case Ok(_):
        \\            return 3
        \\        case Err(error):
        \\            match error:
        \\                case AppError.Json(detail):
        \\                    if len(json.message(detail)) == 0:
        \\                        return 4
        \\                    return 42
    , 42);
}
