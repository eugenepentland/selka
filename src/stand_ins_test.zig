//! Deterministic stand-in capabilities: they never reach a host resource, their
//! narrowings stay stand-ins, their misuse traps, and using one where no
//! parameter supplies the effect is not an effect of the function.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const effects = @import("effect_set.zig");

/// A program granted every host capability that also builds stand-ins, and
/// scores each way a stand-in could leak into, or read from, the host.
const isolation =
    \\module main
    \\import environment
    \\import filesystem
    \\import network
    \\import time
    \\
    \\def main(fs: Filesystem, env: Environment, clock: Clock, net: Network) -> int:
    \\    memory = filesystem.memory()
    \\    score = 0
    \\    if fs.exists("host.txt") and not memory.exists("host.txt"):
    \\        score += 1
    \\    _ = memory.write_text("made.txt", "x")
    \\    scoped = memory.dir("sub")
    \\    frozen = scoped.read_only()
    \\    _ = frozen.exists("made.txt")
    \\    if not fs.exists("made.txt") and memory.exists("made.txt"):
    \\        score += 2
    \\    fixed = environment.fixed({"ONLY": "stand-in"})
    \\    if env.get("HOME") is not None and fixed.get("HOME") is None and fixed.names() == ["ONLY"]:
    \\        score += 4
    \\    match time.advance(clock, time.nanoseconds(1)):
    \\        case Ok(_):
    \\            score += 100
    \\        case Err(message):
    \\            if message == "only a simulated clock can be advanced":
    \\                score += 8
    \\    stand_in = network.denied()
    \\    match network.connect(stand_in.host("127.0.0.1:9")):
    \\        case network.Connected.ok(_):
    \\            score += 100
    \\        case network.Connected.err(code):
    \\            if code == network.denied_here():
    \\                score += 16
    \\    _ = net.host("127.0.0.1:9")
    \\    return score
;

// spec: TEST-CAPS-2
test "stand-ins never read or write the host resources a program is granted" {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "host.txt", .data = "real" });
    const path = try temporary.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(path);
    var guest: std.process.Environ.Map = .init(t.allocator);
    defer guest.deinit();
    try guest.put("HOME", "/home/real");
    // The default mode grants every capability but the network, which needs an endpoint.
    const grant = [_][]const u8{"--allow-endpoint=127.0.0.1:9"};
    try fixture.expect(t.allocator, isolation, .{ .directory = path, .environment = &guest, .arguments = &grant }, 31);
    // The in-memory write left nothing behind in the granted directory.
    try t.expectError(error.FileNotFound, temporary.dir.access(t.io, "made.txt", .{}));
}

// spec-case: TEST-CAPS-2
test "a narrowed fixed environment refuses a name outside its scope" {
    try fixture.trap(t.allocator,
        \\module main
        \\import environment
        \\
        \\def main() -> int:
        \\    env = environment.fixed({"HOME": "/h", "PATH": "/bin"})
        \\    narrowed = env.only("HOME")
        \\    match narrowed.get("PATH"):
        \\        case Some(_):
        \\            return 1
        \\        case None:
        \\            return 2
    , .{}, "R_CAPABILITY");
}

// spec-case: TEST-CAPS-2
test "a fixed environment traps on a name the host environment could not hold" {
    try fixture.trap(t.allocator,
        \\module main
        \\import environment
        \\
        \\def main() -> int:
        \\    env = environment.fixed({"A=B": "x"})
        \\    return len(env.names())
    , .{}, "R_ENVIRONMENT");
}

/// Check that ordinary source spelling `body` inside `main` is refused as an
/// internal name.
fn rejectInternal(body: []const u8) !void {
    const text = try std.mem.concat(t.allocator, u8, &.{ "def main(clock: Clock) -> int:\n", body, "    return 0\n" });
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "main.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_INTERNAL_NAME", c.diagnostics.items[0].code);
}

// spec-case: TEST-CAPS-2
test "ordinary source cannot spell the stand-in intrinsics" {
    try rejectInternal("    clock = __stand_in[Clock](0)\n    _ = clock\n");
    try rejectInternal("    _ = __clock_advance(clock, 1)\n");
}

/// The inferred effect set of the entry module's function named `name`.
fn inferred(program: *const language.embedded_project.Program, name: []const u8) !effects.Mask {
    for (program.compilation.program.?.functions) |function| {
        if (std.mem.endsWith(u8, function.name, name)) return function.policy.effects;
    }
    return error.TestUnexpectedResult;
}

const contained =
    \\module main
    \\import filesystem
    \\import random
    \\import time
    \\
    \\def reading(clock: Clock) -> int:
    \\    match time.now(clock):
    \\        case Ok(instant):
    \\            return instant.unix_nanoseconds
    \\        case Err(_):
    \\            return -1
    \\
    \\def simulated() -> int:
    \\    memory = filesystem.memory()
    \\    _ = memory.write_text("a", "b")
    \\    match random.from_entropy(random.seeded_entropy(1)):
    \\        case Ok(_):
    \\            return reading(time.simulated_clock(time.from_unix_nanoseconds(5)))
    \\        case Err(_):
    \\            return 0
    \\
    \\def main() -> int:
    \\    return simulated()
;

// spec: TEST-CAPS-4
test "using a stand-in where no parameter supplies the effect is not an effect" {
    var entry: fixture.Entry = .{ .text = contained };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &entry, .read = fixture.Entry.read });
    defer program.deinit();
    const outside = effects.bit(.clock) | effects.bit(.random) | effects.bit(.filesystem);
    // `reading` has a Clock parameter, so reading it stays its effect.
    try t.expect(try inferred(&program, "reading") & effects.bit(.clock) != 0);
    // `simulated` holds only stand-ins, so none of their uses leaves it.
    try t.expectEqual(@as(effects.Mask, 0), try inferred(&program, "simulated") & outside);
    try t.expectEqual(@as(effects.Mask, 0), try inferred(&program, "main") & outside);
    try fixture.run(t.allocator, contained, 5);
}

// spec-case: TEST-CAPS-4
test "a Host parameter keeps a stand-in's use an effect of the function" {
    try fixture.run(t.allocator,
        \\module main
        \\import filesystem
        \\
        \\def touch() -> bool:
        \\    memory = filesystem.memory()
        \\    return memory.exists("x")
        \\
        \\def main() -> int:
        \\    if touch():
        \\        return 1
        \\    return 0
    , 0);
    try fixture.reject(t.allocator,
        \\module main
        \\import filesystem
        \\
        \\def touch(host: Host) -> bool:
        \\    _ = host
        \\    memory = filesystem.memory()
        \\    return memory.exists("x")
        \\
        \\def main(host: Host) -> int:
        \\    if touch(host):
        \\        return 1
        \\    return 0
    );
}
