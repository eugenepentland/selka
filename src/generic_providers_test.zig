//! Provider operand and Result contracts hold even for uncalled generic templates.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const schema =
    \\result R:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\result Random:
    \\    ok: u64,
    \\    err: i64
    \\
    \\
    \\resource File: filesystem
    \\
    \\
    \\result Open:
    \\    ok: File,
    \\    err: i64
    \\
    \\
    \\record Failure:
    \\    resource: File
    \\    code: i64
    \\
    \\
    \\result Finish:
    \\    ok: bool,
    \\    err: Failure
    \\
    \\
    \\record Chunk:
    \\    bytes: FixedArray[u8, 4]
    \\    length: u64
    \\    eof: bool
    \\
    \\
    \\result Read:
    \\    ok: Chunk,
    \\    err: i64
    \\
    \\
    \\record Progress:
    \\    length: u64
    \\    eof: bool
    \\
    \\
    \\result Slice:
    \\    ok: Progress,
    \\    err: i64
    \\
    \\
    \\record Entry:
    \\    bytes: FixedArray[u8, 4]
    \\    length: u64
    \\    present: bool
    \\
    \\
    \\result Env:
    \\    ok: Entry,
    \\    err: i64
;
fn sourceText(body: []const u8) ![]u8 {
    return std.mem.concat(t.allocator, u8, &.{
        schema, "\n\n\n", body, "\n\n\n",
        \\func main() -> i64:
        \\    return 0
    });
}
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try sourceText(body);
    defer t.allocator.free(bytes);
    var c = try language.Compilation.initTrusted(t.allocator, "generic-provider-invalid.selka", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
fn accept(body: []const u8) !void {
    const bytes = try sourceText(body);
    defer t.allocator.free(bytes);
    var c = try language.Compilation.initTrusted(t.allocator, "generic-provider-template.selka", bytes);
    defer c.deinit();
    try c.check();
    try t.expectEqual(@as(usize, 0), c.diagnostics.items.len);
}

// spec: GENERIC-PROVIDER-1
test "generic externalValue and environmentValue enforce capability kinds and result shapes" {
    try reject(
        \\func f[T](cap: Entropy) -> R:
        \\    return clock_now[R](cap)
    , "E_GENERIC_TYPE");
    try reject(
        \\func f[T](cap: Clock) -> Random:
        \\    return clock_now[Random](cap)
    , "E_EXTERNAL_RESULT");
    try reject(
        \\func f[T](cap: Entropy) -> R:
        \\    return random_u64[R](cap)
    , "E_EXTERNAL_RESULT");
    try reject(
        \\func f[T](cap: Environment) -> R:
        \\    return environment_get[R](cap, [])
    , "E_ENVIRONMENT_RESULT");
    try reject(
        \\func f[T](cap: Clock) -> Env:
        \\    return environment_get[Env](cap, [])
    , "E_GENERIC_TYPE");
    try reject(
        \\func f[T](cap: Environment) -> Env:
        \\    return environment_get[Env](cap, [1])
    , "E_ENVIRONMENT_NAME");
    try reject(
        \\func f[T](cap: Entropy) -> i64 effects():
        \\    _ = random_u64[Random](cap)
        \\    return 0
    , "E_EFFECTS_REMOVED");
    try reject(
        \\func f[T](cap: Environment) -> i64 effects():
        \\    mut name: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    _ = environment_get[Env](cap, name)
        \\    return 0
    , "E_EFFECTS_REMOVED");
}

test "generic acquireResource and completeResource preserve kind byte request and Result contracts" {
    try reject(
        \\func f[T](cap: Filesystem) -> R:
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return acquire_resource[R](cap, empty)
    , "E_RESOURCE_RESULT");
    try reject(
        \\func f[T](cap: Network) -> Open:
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return acquire_resource[Open](cap, empty)
    , "E_GENERIC_TYPE");
    try reject(
        \\func f[T](cap: Filesystem) -> Open:
        \\    return acquire_resource[Open](cap, 0)
    , "E_RESOURCE_REQUEST");
    try reject(
        \\func f[T](file: File) -> R:
        \\    return complete_resource[R](file)
    , "E_COMPLETION_RESULT");
    try reject(
        \\func f[T]() -> Finish:
        \\    return complete_resource[Finish](0)
    , "E_GENERIC_TYPE");
    try reject(
        \\func f[T](cap: Filesystem) -> Open noio:
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return acquire_resource[Open](cap, empty)
    , "E_EFFECTS_REMOVED");
}

test "generic resourceIo checks byte values and fixed result payloads" {
    try reject(
        \\func f[T](input: i64) -> Read:
        \\    return read_resource[Read](input)
    , "E_RESOURCE_TYPE");
    try reject(
        \\func f[T](input: File) -> R:
        \\    mut file = input
        \\    return read_resource[R](file)
    , "E_RESOURCE_IO_RESULT");
    try reject(
        \\func f[T](input: File) -> Random:
        \\    mut file = input
        \\    return write_resource[Random](file, 1)
    , "E_RESOURCE_BYTES");
}

test "uncalled generic provider templates leave Core moves to concrete instances" {
    try accept(
        \\func repeat[T](file: File) -> Finish:
        \\    _ = complete_resource[Finish](file)
        \\    return complete_resource[Finish](file)
        \\
        \\
        \\func reuse[T](input: File) -> Read:
        \\    mut file = input
        \\    _ = file
        \\    return read_resource[Read](file)
        \\
        \\
        \\func consume(own file: File) -> FixedArray[u8, 0]:
        \\    _ = file
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return empty
        \\
        \\
        \\func argument[T](input: File) -> Random:
        \\    mut file = input
        \\    return write_resource[Random](file, consume(file))
    );
}

test "uncalled generic resource Results keep their handling obligations" {
    try reject(
        \\func f[T](r: Finish) -> Unit:
        \\    mut transferred = r
        \\    _ = r
        \\    _ = transferred
    , "E_RESULT_CONSUMED");
}

test "F3 uncalled generic provider record const field is immutable" {
    try reject("record Pair:\n    value: int\nfunc touch[T]():\n    const pair = Pair(value=1)\n    pair.value = 2\n", "E_IMMUTABLE");
}

test "F3 uncalled generic resource match payload keeps frontend writability" {
    try reject(
        // migrate-embedded: skip intentional uncalled immutable resource payload
        \\func read_payload[T](r: Open) -> Read:
        \\    match r:
        \\        case ok(file):
        \\            return read_resource[Read](file)
        \\        case err(code):
        \\            return Err(code)
    , "E_IMMUTABLE");
}
