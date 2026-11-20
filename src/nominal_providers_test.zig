//! Executed generic provider contracts and cleanup over a real granted directory.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("nominal_provider_fixture.zig");
const Sandbox = @import("io_files_test.zig").Sandbox;
const module = "nominal-providers.selka";
// The native provider reads "r:data.bin", creates "c:out.bin" and refuses
// "r:absent.bin"; every request is the mode byte, a colon and a relative path.
const helpers =
    \\func reading() -> FixedArray[u8, 10]:
    \\    return FixedArray[u8, 10]([114u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8])
    \\
    \\
    \\func creating() -> FixedArray[u8, 9]:
    \\    return FixedArray[u8, 9]([99u8, 58u8, 111u8, 117u8, 116u8, 46u8, 98u8, 105u8, 110u8])
    \\
    \\
    \\func missing() -> FixedArray[u8, 12]:
    \\    return FixedArray[u8, 12]([114u8, 58u8, 97u8, 98u8, 115u8, 101u8, 110u8, 116u8, 46u8, 98u8, 105u8, 110u8])
    \\
    \\
    \\func finish[T](own file: File) -> Finish[T]:
    \\    match complete_resource[Finish[T]](own file):
    \\        case ok(done):
    \\            return Ok(done)
    \\        case err(failure):
    \\            return complete_resource[Finish[T]](own failure.resource)
    \\
    \\
    \\
;
const program = fixture.declarations ++ helpers ++
    \\func work[T](fs: Filesystem) -> Status[T]:
    \\    mut file = try acquire_resource[Open[T]](fs, reading())
    \\    mut chunk = try read_resource[Read[T]](file)
    \\    mut second = try read_resource[Read[T]](file)
    \\    mut sink = try acquire_resource[Open[T]](fs, creating())
    \\    mut n = try write_resource[Written[T]](sink, singleton[u8](9u8))
    \\    mut payload: FixedArray[u8, 2] = FixedArray[u8, 2]([chunk.bytes[0], chunk.bytes[1]])
    \\    mut m = try write_resource[Written[T]](sink, payload)
    \\    match finish[T](own file):
    \\        case ok(done):
    \\            if not done:
    \\                return Err(91)
    \\        case err(failure):
    \\            return Err(failure.code)
    \\    match finish[T](own sink):
    \\        case ok(done):
    \\            if not done:
    \\                return Err(93)
    \\        case err(failure):
    \\            return Err(failure.code)
    \\    if chunk.eof or not second.eof:
    \\        return Err(92)
    \\    return Ok(i64(chunk.length) + i64(chunk.bytes[0]) + i64(chunk.bytes[1]) + i64(chunk.bytes[2]) + i64(chunk.bytes[3]) + i64(n) + i64(second.length) + i64(m))
    \\
    \\
    \\func restricted(fs: Filesystem) -> i64:
    \\    with fs.read_only() as readonly:
    \\        match acquire_resource[Open[bool]](readonly, reading()):
    \\            case ok(file):
    \\                match finish[bool](own file):
    \\                    case ok(done):
    \\                        if done:
    \\                            return 0
    \\                        return 1
    \\                    case err(failure):
    \\                        return failure.code
    \\            case err(e):
    \\                return e
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    match work[bool](fs):
    \\        case ok(n):
    \\            return n * 10 + restricted(fs)
    \\        case err(e):
    \\            return 0 - e
;
/// Grant a writable directory holding the three-byte `data.bin` fixture.
fn sandbox(box: *Sandbox) !void {
    try box.init(true);
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "\x00\xff\x07" });
}
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, module, program);
    defer compilation.deinit();
    try compilation.check();
}
// spec: NOMINAL-PROVIDER-1
test "nominal providers specialize named payloads byte inputs and completion retry ownership" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run(module, program);
    try t.expectEqualStrings("", outcome.trap.code);
    // Three bytes read with a zeroed tail, three bytes written, then a
    // capability narrowed to reads refuses both completion attempts.
    try t.expectEqual(@as(i64, (3 + 0 + 255 + 7 + 0 + 1 + 0 + 2) * 10 + 2), outcome.value);
    const written = try box.temporary.dir.readFileAlloc(t.io, "out.bin", t.allocator, .limited(16));
    defer t.allocator.free(written);
    try t.expectEqualSlices(u8, &.{ 9, 0, 255 }, written);
}
test "nominal providers unwind every compiler allocation failure" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
const failing = fixture.declarations ++ helpers ++
    \\func work[T](fs: Filesystem) -> Status[T]:
    \\    mut file = try acquire_resource[Open[T]](fs, reading())
    \\    mut absent = try acquire_resource[Open[T]](fs, missing())
    \\    _ = own file
    \\    _ = own absent
    \\    return Ok(0)
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
    \\    for index in range(2000):
    \\        match work[bool](fs):
    \\            case ok(value):
    \\                return 0 - value
    \\            case err(e):
    \\                if e != 3:
    \\                    return 0 - e
    \\        total = total + 1
    \\    return total
;
test "nominal providers propagate host failures and release acquired owners exactly once" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    // The provider holds 256 handles; two thousand refused pairs only finish
    // because every propagation released the one owner it had acquired.
    const outcome = try box.run("host-failure.selka", failing);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 2000), outcome.value);
}
const trapping = fixture.declarations ++ helpers ++
    \\func work[T](fs: Filesystem) -> Status[T]:
    \\    mut file = try acquire_resource[Open[T]](fs, reading())
    \\    mut chunk = try read_resource[Read[T]](file)
    \\    match finish[T](own file):
    \\        case ok(done):
    \\            if not done:
    \\                return Err(91)
    \\        case err(failure):
    \\            return Err(failure.code)
    \\    return Ok(i64(chunk.length))
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    match work[bool](fs):
    \\        case ok(n):
    \\            return n
    \\        case err(e):
    \\            return 0 - e
;
// spec-case: NATIVE-ARGV-1
// spec-case: QBE-STEP-ACCOUNTING-1
test "nominal providers unwind traps at every instruction including failed completion ownership transfer" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const options = box.options();
    // One instrumented executable serves every ceiling; ordinary compiled-in
    // first/last ceilings cross-check the runtime harness at both endpoints.
    var programs: native.Batch = .init(t.allocator);
    defer programs.deinit();
    try programs.budgetSweep("nominal-traps.selka", trapping, options, 110);
    const runs = try programs.run();
    try t.expectEqual(@as(i64, 3), runs[0].value);
    try native.expectBudgetSweep(runs);
}
