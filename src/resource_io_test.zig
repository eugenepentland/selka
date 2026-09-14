//! Resource IO execution against a real granted directory: partial reads, EOF,
//! zero padding, actual write progress, and release at every trap boundary.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Sandbox = @import("io_files_test.zig").Sandbox;
const module = "io.my";
const declarations =
    \\resource File: filesystem
    \\
    \\
    \\result Open:
    \\    ok: File,
    \\    err: i64
    \\
    \\
    \\class Chunk:
    \\    eof: bool
    \\    bytes: [4]u8
    \\    length: u64
    \\
    \\
    \\result Read:
    \\    ok: Chunk,
    \\    err: i64
    \\
    \\
    \\result Written:
    \\    ok: u64,
    \\    err: i64
    \\
    \\
    \\class Failure:
    \\    resource: File
    \\    code: i64
    \\
    \\
    \\result Finish:
    \\    ok: bool,
    \\    err: Failure
    \\
    \\
    \\result Status:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\
;
// The native provider's request grammar is one mode byte, a colon and a
// relative path: "r:data.bin" reads, "c:out.bin" creates, "r:absent.bin" fails.
const requests =
    \\def reading() -> [10]u8:
    \\    return [114u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\def creating() -> [9]u8:
    \\    return [99u8, 58u8, 111u8, 117u8, 116u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\def absent() -> [12]u8:
    \\    return [114u8, 58u8, 97u8, 98u8, 115u8, 101u8, 110u8, 116u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\def finish(file: File) -> Status:
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            _ = done
    \\            return Ok(0)
    \\        case Finish.err(failure):
    \\            return Err(failure.code)
    \\
    \\
    \\
;
fn reject(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, module, text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
const source = declarations ++ requests ++
    \\def work(fs: filesystem_cap) -> Status:
    \\    file = acquire_resource[Open](fs, reading())?
    \\    first = read_resource[Read](file)?
    \\    second = read_resource[Read](file)?
    \\    _ = finish(file)?
    \\    sink = acquire_resource[Open](fs, creating())?
    \\    payload: [3]u8 = [7u8, 8u8, 9u8]
    \\    count = write_resource[Written](sink, payload)?
    \\    _ = finish(sink)?
    \\    if first.eof or not second.eof or second.length != 0u64:
    \\        return Err(99)
    \\    return Ok(i64(first.length) + i64(first.bytes[0]) + i64(first.bytes[1]) + i64(first.bytes[2]) + i64(first.bytes[3]) + i64(count))
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64 noalloc:
    \\    match work(fs):
    \\        case Status.ok(value):
    \\            return value
    \\        case Status.err(code):
    \\            return -code
;
/// Grant a writable directory holding the three-byte `data.bin` fixture.
fn sandbox(box: *Sandbox) !void {
    try box.init(true);
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "\x00\xff\x07" });
}
test "source resource reads expose partial data EOF and padding while writes report actual progress" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run(module, source);
    try t.expectEqualStrings("", outcome.trap.code);
    // Three bytes read, the fourth zeroed by the runtime, then three written.
    try t.expectEqual(@as(i64, 3 + 0 + 255 + 7 + 0 + 3), outcome.value);
    const written = try box.temporary.dir.readFileAlloc(t.io, "out.bin", t.allocator, .limited(16));
    defer t.allocator.free(written);
    try t.expectEqualSlices(u8, &.{ 7, 8, 9 }, written);
}
const cycles = declarations ++ requests ++
    \\def completed(fs: filesystem_cap) -> Status:
    \\    total = 0
    \\    for index in range(2000):
    \\        file = acquire_resource[Open](fs, reading())?
    \\        _ = finish(file)?
    \\        total = total + 1
    \\    return Ok(total)
    \\
    \\
    \\def dropped(fs: filesystem_cap) -> Status:
    \\    total = 0
    \\    for index in range(2000):
    \\        file = acquire_resource[Open](fs, reading())?
    \\        _ = file
    \\        total = total + 1
    \\    return Ok(total)
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64:
    \\    match completed(fs):
    \\        case Status.ok(value):
    \\            _ = value
    \\        case Status.err(code):
    \\            return -code
    \\    match dropped(fs):
    \\        case Status.ok(value):
    \\            return value
    \\        case Status.err(code):
    \\            return -code
;
test "resource owners are released exactly once by completion and by scope exit" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    // The provider holds 256 handles at once; four thousand acquisitions only
    // finish because completion and ordinary scope exit each release one.
    const outcome = try box.run("cycles.my", cycles);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 2000), outcome.value);
}
const failing = declarations ++ requests ++
    \\def work(fs: filesystem_cap) -> Status:
    \\    file = acquire_resource[Open](fs, absent())?
    \\    _ = finish(file)?
    \\    return Ok(1)
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64:
    \\    match work(fs):
    \\        case Status.ok(value):
    \\            return value
    \\        case Status.err(code):
    \\            return -code
;
test "a refused acquisition propagates its host category and leaves no owner behind" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    // A path that does not exist is the provider's `failed` category, code 3.
    const outcome = try box.run("failing.my", failing);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, -3), outcome.value);
}
const reading_only = declarations ++ requests ++
    \\def work(fs: filesystem_cap) -> Status:
    \\    file = acquire_resource[Open](fs, reading())?
    \\    chunk = read_resource[Read](file)?
    \\    _ = finish(file)?
    \\    return Ok(i64(chunk.length))
    \\
    \\
    \\def main(fs: filesystem_cap) -> i64:
    \\    match work(fs):
    \\        case Status.ok(value):
    \\            return value
    \\        case Status.err(code):
    \\            return -code
;
test "source IO traps at every instruction boundary release or complete exactly once" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    var compilation = try language.Compilation.init(t.allocator, "budgets.my", reading_only);
    defer compilation.deinit();
    var options = box.options();
    // Eighty-odd steps carry this program past its last instruction, so every
    // budget below that cuts it at a different boundary. An owner released
    // twice would abort the process rather than report a status of 0 or 1.
    for (1..85) |budget| {
        options.max_steps = budget;
        const outcome = try native.runWithOptions(&compilation, options);
        try t.expect(outcome.status <= 1);
    }
    options.max_steps = null;
    try t.expectEqual(@as(i64, 3), (try native.runWithOptions(&compilation, options)).value);
}
test "resource requests reject payloads that are not fixed byte arrays" {
    try reject(declarations ++
        \\def main(fs: filesystem_cap) -> i64:
        \\    match acquire_resource[Open](fs, b"r:data.bin"):
        \\        case Open.ok(file):
        \\            _ = file
        \\            return 0
        \\        case Open.err(code):
        \\            return code
    , "E_RESOURCE_REQUEST");
}
test "emission rejects forged resource IO metadata before provider callbacks" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", declarations ++
        \\def work(fs: filesystem_cap) -> Status:
        \\    request: [10]u8 = [114u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8]
        \\    file = acquire_resource[Open](fs, request)?
        \\    chunk = read_resource[Read](file)?
        \\    match complete_resource[Finish](file):
        \\        case Finish.ok(done):
        \\            _ = done
        \\        case Finish.err(failure):
        \\            return Err(failure.code)
        \\    return Ok(i64(chunk.length))
        \\
        \\
        \\def main(fs: filesystem_cap) -> i64:
        \\    match work(fs):
        \\        case Status.ok(value):
        \\            return value
        \\        case Status.err(code):
        \\            return -code
    );
    defer c.deinit();
    try c.emit();
    const instruction = try @import("instruction_test.zig").find(@constCast(c.code.?.functions[0].scope.instructions), .resource_io);
    const original = instruction.*;
    instruction.op.resource_io.owner = @fromBackingInt(std.math.maxInt(usize));
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    instruction.op.resource_io.output = .i64;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    try language.bytecode.validate(t.allocator, c.code.?);
}
