//! Integrated Python byte-string syntax, conversions, storage and rejections.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");

fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "bytes.my", source);
    defer c.deinit();
    const result = c.executeWithOptions(t.allocator, .{ .memory = .{ .gc = .{ .stress = true } } }) catch |err| {
        for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    if (result == .trap) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.trap.message });
    try t.expect(result == .value);
    try t.expectEqual(expected, result.value);
}

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-trap.my", source);
    defer c.deinit();
    const result = try c.executeWithOptions(t.allocator, .{ .memory = .{ .gc = .{ .stress = true } } });
    try t.expect(result == .trap);
    try t.expectEqualStrings(code, result.trap.code);
}

fn rejected(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-reject.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    for (c.diagnostics.items) |d| if (std.mem.eql(u8, d.code, code)) return;
    for (c.diagnostics.items) |d| debug.print("{s}: {s}\n", .{ d.code, d.message });
    return t.expect(false);
}

// spec: PY-BYTES-1
test "PY-BYTES-1 byte literals index slice concatenate compare and iterate" {
    try run(
        \\def main() -> int:
        \\    raw = b"hi\x00\xff"
        \\    if len(raw) != 4:
        \\        return 1
        \\    if raw[0] != 104 or raw[-1] != 255 or raw[2] != 0:
        \\        return 2
        \\    if raw[1:3] != b"i\x00":
        \\        return 3
        \\    if raw[-99:99] != raw or raw[3:1] != b"":
        \\        return 4
        \\    if b"hi" + b"\x00\xff" != raw:
        \\        return 5
        \\    if raw == b"hi" or not (raw != b"hi"):
        \\        return 6
        \\    total = 0
        \\    for value in raw:
        \\        total += value
        \\    for index, value in enumerate(raw):
        \\        total += index
        \\    return total - 428
    , 42);
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 membership accepts a byte scalar or a contiguous subsequence" {
    try run(
        \\def main() -> int:
        \\    raw = b"alpha"
        \\    if 108 not in raw:
        \\        return 1
        \\    if 200 in raw:
        \\        return 2
        \\    if b"lph" not in raw:
        \\        return 3
        \\    if b"lhp" in raw:
        \\        return 4
        \\    if b"" not in raw:
        \\        return 5
        \\    if not raw.contains(97) or not raw.contains(b"pha"):
        \\        return 6
        \\    return 42
    , 42);
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 byte strings alias through helpers and survive collection stress" {
    try run(
        \\def widen(value: bytes) -> bytes:
        \\    return value + value
        \\def main() -> int:
        \\    seed = b"\x01"
        \\    grown = seed
        \\    for step in range(6):
        \\        grown = widen(grown)
        \\    holder: list[bytes] = []
        \\    for step in range(20):
        \\        holder.append(widen(seed))
        \\    if len(seed) != 1:
        \\        return 1
        \\    if len(holder[19]) != 2:
        \\        return 2
        \\    return len(grown) - 22
    , 42);
}

// spec: PY-BYTES-2
test "PY-BYTES-2 integer list text and hexadecimal conversions round trip" {
    try run(
        \\def decoded(raw: bytes) -> Result[str, str]:
        \\    return raw.decode()
        \\def parsed(digits: str) -> Result[bytes, str]:
        \\    return bytes.fromhex(digits)
        \\def main() -> int:
        \\    values: list[int] = [0, 65, 255]
        \\    raw = bytes(values)
        \\    if raw != b"\x00A\xff":
        \\        return 1
        \\    back = raw.to_list()
        \\    if len(back) != 3 or back[2] != 255:
        \\        return 2
        \\    if raw.hex() != "0041ff":
        \\        return 3
        \\    encoded = "hé".encode()
        \\    if len(encoded) != 3:
        \\        return 4
        \\    match decoded(encoded):
        \\        case Ok(value):
        \\            if value != "hé":
        \\                return 5
        \\        case Err(message):
        \\            return 0 - len(message)
        \\    match decoded(b"\xff\xfe"):
        \\        case Ok(value):
        \\            return 0 - len(value)
        \\        case Err(message):
        \\            if len(message) == 0:
        \\                return 6
        \\    match parsed("0041ff"):
        \\        case Ok(value):
        \\            if value != raw:
        \\                return 7
        \\        case Err(message):
        \\            return 0 - len(message)
        \\    match parsed("00g1"):
        \\        case Ok(value):
        \\            return 0 - len(value)
        \\        case Err(message):
        \\            return 42
    , 42);
}

// spec: PY-BYTES-3
test "PY-BYTES-3 split join prefix suffix search and container storage" {
    try run(
        \\class Packet:
        \\    tag: str
        \\    body: bytes
        \\def main() -> int:
        \\    line = b"a,bb,,c"
        \\    parts = line.split(b",")
        \\    if len(parts) != 4 or parts[2] != b"":
        \\        return 1
        \\    if b",".join(parts) != line:
        \\        return 2
        \\    if not line.startswith(b"a,") or not line.endswith(b",c"):
        \\        return 3
        \\    if line.startswith(b"b") or line.endswith(b"b"):
        \\        return 4
        \\    if line.find(b"bb") != 2 or line.find(b"zz") != -1:
        \\        return 5
        \\    packets: list[Packet] = [Packet(tag="first", body=parts[1])]
        \\    index: dict[str, bytes] = {}
        \\    for packet in packets:
        \\        index[packet.tag] = packet.body
        \\    if index["first"] != b"bb":
        \\        return 6
        \\    optional: Option[bytes] = Some(line)
        \\    match optional:
        \\        case Some(value):
        \\            if value != line:
        \\                return 7
        \\        case None:
        \\            return 8
        \\    return 35 + len(index["first"]) + len(parts) + len(packets)
    , 42);
}

// spec-case: PY-BYTES-3
test "PY-BYTES-3 generic bodies preserve managed byte-string identities" {
    try run(
        \\def pair[T:copy+storable](value: T) -> list[T]:
        \\    values: list[T] = [value]
        \\    values.append(value)
        \\    return values
        \\def main() -> int:
        \\    both = pair(b"ab")
        \\    if both[0] != both[1] or both[1] != b"ab":
        \\        return 1
        \\    return len(both[0]) + 40
    , 42);
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 out-of-range indexes ranges and separators trap with located codes" {
    try trapped("def main() -> int:\n    raw = b\"ab\"\n    return raw[2]\n", "R_LIST_BOUNDS");
    try trapped("def main() -> int:\n    raw = b\"ab\"\n    return raw[-3]\n", "R_LIST_BOUNDS");
    try trapped("def main() -> int:\n    return len(b\"ab\".split(b\"\"))\n", "R_EMPTY_SEPARATOR");
    try trapped("def main() -> int:\n    values: list[int] = [256]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
    try trapped("def main() -> int:\n    values: list[int] = [0 - 1]\n    return len(bytes(values))\n", "R_BYTE_RANGE");
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 byte strings are immutable and never convert through str" {
    try rejected("def main() -> int:\n    raw = b\"ab\"\n    raw[0] = 1\n    return 0\n", "E_COLLECTION_METHOD");
    try rejected("def main() -> int:\n    raw = b\"ab\"\n    raw.append(1)\n    return 0\n", "E_COLLECTION_METHOD");
    try rejected("def main() -> int:\n    return len(str(b\"ab\"))\n", "E_TEXT_CONVERSION");
    try rejected("def main() -> int:\n    raw = b\"ab\"\n    return len(raw - raw)\n", "E_TEXT_OPERATOR");
    try rejected("def main() -> int:\n    values: dict[bytes, int] = {}\n    return len(values)\n", "E_GENERIC_REQUIREMENT");
    try rejected("def main() -> int:\n    return len(bytes(\"ab\"))\n", "E_BYTES_CONVERSION");
    try rejected("def main() -> int:\n    return len(b\"ab\".encode())\n", "E_COLLECTION_METHOD");
}

// spec-case: PY-BYTES-3
test "PY-BYTES-3 byte strings are rejected at JSON and host boundaries like str" {
    try rejected(
        "host fn accept(value: bytes) -> i64 effects(host);\nfn main() -> i64 { return accept(b\"a\"); }\n",
        "E_HOST_SIGNATURE",
    );
    try rejected(
        "buffer Wire: u8;result Encoded{ok:Wire,err:i64}" ++
            "fn main(heap: allocator) -> i64 { let raw = b\"a\"; match json_encode::<Encoded>(heap, raw, 64) " ++
            "{ Encoded.ok(payload) => { discard payload; return 0; }, Encoded.err(code) => { return code; } } }",
        "E_JSON_CODEC",
    );
}

// spec-case: PY-BYTES-1
test "PY-BYTES-1 prefixed literals keep their array reading for readonly slice parameters" {
    try run(
        \\def total(view: &[]u8) -> i64 noalloc:
        \\    sum = 0
        \\    index = 0u64
        \\    while index < len_slice(view):
        \\        sum += cast<i64>(read_slice(view, index))
        \\        index += 1u64
        \\    return sum
        \\def main() -> int:
        \\    managed = b"\x01\x02"
        \\    if len(managed) != 2 or managed[1] != 2:
        \\        return 1
        \\    return total(b"\x14\x14") + managed[0] + 1
    , 42);
}
