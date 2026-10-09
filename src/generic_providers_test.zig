//! Provider contracts must hold even for uncalled generic templates.
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
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{
        schema, "\n\n\n", body, "\n\n\n",
        \\func main() -> i64:
        \\    return 0
    });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.initTrusted(t.allocator, "generic-provider-invalid.my", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
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
    , "E_EFFECT_BOUND");
    try reject(
        \\func f[T](cap: Environment) -> i64 effects():
        \\    mut name: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    _ = environment_get[Env](cap, name)
        \\    return 0
    , "E_EFFECT_BOUND");
}

test "generic acquireResource and completeResource preserve kind byte request and ownership contracts" {
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
        \\func f[T](file: File) -> Finish:
        \\    _ = complete_resource[Finish](file)
        \\    return complete_resource[Finish](file)
    , "E_OWNED_CONSUMED");
    try reject(
        \\func f[T](cap: Filesystem) -> Open noio:
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return acquire_resource[Open](cap, empty)
    , "E_EFFECT_BOUND");
}

test "generic resourceIo checks mutation owner state byte values and fixed result payloads" {
    // A parameter now binds mutably, so the immutable owner a read must reject is
    // a match arm payload: those bindings stay immutable for the arm's lifetime.
    try reject(
        \\func f[T](r: Open) -> Read:
        \\    match r:
        \\        case Open.ok(file):
        \\            return read_resource[Read](file)
        \\        case Open.err(code):
        \\            return Err(code)
    , "E_IMMUTABLE");
    try reject(
        \\func f[T](input: File) -> Read:
        \\    mut file = input
        \\    _ = file
        \\    return read_resource[Read](file)
    , "E_OWNED_CONSUMED");
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
    try reject(
        \\func consume(file: File) -> FixedArray[u8, 0]:
        \\    _ = file
        \\    mut empty: FixedArray[u8, 0] = FixedArray[u8, 0]([])
        \\    return empty
        \\
        \\
        \\func f[T](input: File) -> Random:
        \\    mut file = input
        \\    return write_resource[Random](file, consume(file))
    , "E_OWNED_CONSUMED");
}
