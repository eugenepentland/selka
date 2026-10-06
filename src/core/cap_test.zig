//! Capability ABI and copied provider payload regression tests.
const std = @import("std");
const support = @import("test_support.zig");
const language = @import("mylang");
const build = @import("build.zig");
const print = @import("print.zig");

const raw_environment =
    \\record Entry:
    \\    present: bool
    \\    bytes: [4]u8
    \\    length: u64
    \\
    \\result Lookup:
    \\    err: int,
    \\    ok: Entry
    \\
    \\def main(env: Environment) -> int:
    \\    match environment_get[Lookup](env, [75u8]):
    \\        case Lookup.ok(entry):
    \\            return int(entry.length)
    \\        case Lookup.err(code):
    \\            return -code
;

// spec-case: NEW-CORE-S3-ABI-1
test "Core raw environment payload follows named field order and copies fixed octets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try trustedIrText(arena.allocator(), raw_environment);
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_environment_raw") != null);
    try std.testing.expect(std.mem.count(u8, text, "list_get") == 4);
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core Host extern authority is checked before its scalar erasing call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\extern def identity(host: Host, value: int) -> int effects(host)
        \\
        \\def main(host: Host) -> int:
        \\    return identity(host, 42)
    );
    const check = std.mem.indexOf(u8, text, "myl_core_host_check").?;
    const call = std.mem.indexOf(u8, text, "call i64 identity").?;
    try std.testing.expect(check < call);
}

// spec-case: NEW-CORE-S3-ABI-1
test "Core copied Host aggregate calls keep the runtime token out of value payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.irText(arena.allocator(),
        \\record Pair:
        \\    number: int
        \\    small: u8
        \\
        \\host def echo(host: Host, value: Pair) -> Pair effects(host)
        \\
        \\def main(host: Host) -> int:
        \\    return echo(host, Pair(number=42, small=7u8)).number
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "myl_core_host_invoke") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "box_make") != null);
}

fn trustedIrText(arena: std.mem.Allocator, source: []const u8) ![]u8 {
    var unit = try language.Compilation.initTrusted(arena, "cap_fixture.my", source);
    try unit.check();
    var refusal: build.Refusal = .{};
    const module = try build.buildModule(arena, unit.program.?, &refusal);
    try support.verified(arena, &module, &.{});
    return print.module(arena, &module);
}
