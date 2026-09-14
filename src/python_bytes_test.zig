//! Integrated Python byte-string syntax, conversions, storage and rejections.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "bytes.my", source);
    defer c.deinit();
    const result = native.runWithOptions(&c, .{ .gc_stress = true }) catch |err| {
        for (c.diagnostics.items) |d| debug.print("{s}: {s} [{s}]\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    if (result.trapped()) debug.print("trap {s}: {s}\n", .{ result.trap.code, result.stderr });
    try t.expect(!result.trapped());
    try t.expectEqual(expected, result.value);
}

fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "bytes-trap.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expect(result.trapped());
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
    try rejected("def main() -> int:\n    values: dict[bytes, int] = {}\n    return len(values)\n", "E_DICT_KEY");
    try rejected("def main() -> int:\n    return len(bytes(\"ab\"))\n", "E_BYTES_CONVERSION");
    try rejected("def main() -> int:\n    return len(b\"ab\".encode())\n", "E_COLLECTION_METHOD");
    try rejected(
        "def build() -> int noalloc:\n    raw = b\"ab\"\n    return len(raw)\ndef main() -> int:\n    return build()\n",
        "E_EFFECT_BOUND",
    );
    try rejected(
        "def grow(a: bytes, b: bytes) -> int noalloc:\n    return len(a + b)\ndef main() -> int:\n    return grow(b\"a\", b\"b\")\n",
        "E_EFFECT_BOUND",
    );
    try rejected(
        "def cut(a: bytes) -> int noalloc:\n    return len(a[0:1])\ndef main() -> int:\n    return cut(b\"ab\")\n",
        "E_EFFECT_BOUND",
    );
}

// spec: PY-BYTES-4
test "PY-BYTES-4 byte strings are region allocated escaped and barrier checked under with arena" {
    try run(
        \\def main() -> int:
        \\    kept: bytes = b""
        \\    names: list[bytes] = []
        \\    with arena() as scratch:
        \\        parts = b"a,bb,ccc".split(b",")
        \\        kept = scratch.escape(parts[2] + b"!")
        \\        names = scratch.escape([parts[0], parts[1]])
        \\    return len(kept) * 10 + len(names[1])
    , 42);
    try rejected(
        \\def main() -> int:
        \\    outer: list[bytes] = []
        \\    with arena():
        \\        outer.append(b"x" + b"y")
        \\    return len(outer)
    , "E_ARENA_ESCAPE");
    try trapped(
        \\def stash(target: list[bytes], value: bytes):
        \\    target.append(value)
        \\
        \\def main() -> int:
        \\    outer: list[bytes] = []
        \\    with arena():
        \\        stash(outer, b"x" + b"y")
        \\    return len(outer)
    , "R_ARENA_ESCAPE");
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

// spec: PY-BYTES-5
test "PY-BYTES-5 the native backend lowers every byte-string operation" {
    const source =
        \\def parsed(digits: str) -> Result[bytes, str]:
        \\    return bytes.fromhex(digits)
        \\
        \\def main() -> int:
        \\    raw = b"a,b" + b",c"
        \\    parts = raw.split(b",")
        \\    if b",".join(parts) != raw or raw[0:1] != b"a":
        \\        return 1
        \\    if not raw.startswith(b"a") or raw.endswith(b"z") or raw.find(b"b") != 2:
        \\        return 2
        \\    if 97 not in raw or b"b," not in raw:
        \\        return 3
        \\    if bytes(raw.to_list()) != raw or raw.hex() != "612c622c63":
        \\        return 4
        \\    match raw.decode():
        \\        case Ok(text):
        \\            if text.encode() != raw:
        \\                return 5
        \\        case Err(message):
        \\            return 0 - len(message)
        \\    match parsed("612c"):
        \\        case Ok(value):
        \\            return len(value)
        \\        case Err(message):
        \\            return 0 - len(message)
    ;
    var compilation = try language.Compilation.init(t.allocator, "bytes-native.my", source);
    defer compilation.deinit();
    const manifest = compilation.emitQbe(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |d| debug.print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    defer t.allocator.free(manifest);
    for ([_][]const u8{ "myl_native_bytes_split", "myl_native_bytes_join", "myl_native_bytes_slice", "myl_qbe_bytes_decode", "myl_qbe_bytes_from_list" }) |symbol| {
        try t.expect(std.mem.indexOf(u8, manifest, symbol) != null);
    }
    try run(source, 2);
}
