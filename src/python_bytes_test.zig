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
