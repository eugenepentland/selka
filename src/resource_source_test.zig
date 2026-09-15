//! Source-level resource ownership against a real granted directory: delegated
//! authority, refused completion that hands the owner back, and cleanup order.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Sandbox = @import("io_files_test.zig").Sandbox;
const module = "resources.my";
const declarations =
    \\resource File: filesystem
    \\
    \\
    \\result Open:
    \\    ok: File,
    \\    err: i64
    \\
    \\
    \\class Failure:
    \\    code: i64
    \\    resource: File
    \\
    \\
    \\result Finish:
    \\    err: Failure,
    \\    ok: bool
    \\
    \\
    \\result Status:
    \\    ok: bool,
    \\    err: i64
    \\
    \\
    \\
;
// The native provider reads "r:data.bin" and refuses "r:absent.bin".
const helpers =
    \\def request() -> [10]u8:
    \\    return [114u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\def missing() -> [12]u8:
    \\    return [114u8, 58u8, 97u8, 98u8, 115u8, 101u8, 110u8, 116u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\
;
/// Grant a writable directory holding the `data.bin` fixture these programs open.
fn sandbox(box: *Sandbox) !void {
    try box.init(true);
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "\x00\xff\x07" });
}
const retry = declarations ++
    \\class Authority:
    \\    fs: Filesystem
    \\
    \\
    \\def open(auth: Authority) -> Open effects(filesystem):
    \\    return acquire_resource[Open](auth.fs, request())
    \\
    \\
    \\def retry(file: File) -> Finish:
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            return Ok(done)
    \\        case Finish.err(failure):
    \\            return complete_resource[Finish](failure.resource)
    \\
    \\
++ helpers ++
    \\def attempt(fs: Filesystem) -> i64 effects(filesystem):
    \\    match open(Authority(fs=fs)):
    \\        case Open.ok(file):
    \\            match retry(file):
    \\                case Finish.ok(done):
    \\                    if done:
    \\                        return 7
    \\                    else:
    \\                        return 0
    \\                case Finish.err(failure):
    \\                    return failure.code
    \\        case Open.err(e):
    \\            return e
    \\
    \\
    \\def main(fs: Filesystem) -> i64 noalloc:
    \\    return attempt(fs) * 100 + attempt(restrict_resource[read](fs))
;
fn retryScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, module, retry);
    defer c.deinit();
    try c.emit();
    const dump = try c.dump(allocator);
    defer allocator.free(dump);
    try t.expect(std.mem.indexOf(u8, dump, "COMPLETE_RESOURCE") != null);
    var discovery = try language.duplicates.discover(allocator, c.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
}
test "source acquisition delegates authority and failed completion returns owned resource for retry" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    try retryScenario(t.allocator);
    // A full grant completes on the first try; a capability narrowed to reads
    // refuses both attempts and hands the same owner back each time.
    const outcome = try box.run(module, retry);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 702), outcome.value);
}
test "ownExternal and source acquisition completion retry clean every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), retryScenario, .{});
}
const partial = declarations ++ helpers ++
    \\def work(fs: Filesystem) -> Status:
    \\    a = acquire_resource[Open](fs, request())?
    \\    b = acquire_resource[Open](fs, missing())?
    \\    _ = a
    \\    _ = b
    \\    return Ok(True)
    \\
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    total = 0
    \\    for index in range(2000):
    \\        match work(fs):
    \\            case Status.ok(done):
    \\                _ = done
    \\                return 1
    \\            case Status.err(e):
    \\                if e != 3:
    \\                    return 0 - e
    \\        total = total + 1
    \\    return total
;
// spec: OWN-9
test "partial source acquisition propagates failure and releases acquired resources once" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    // The provider holds 256 handles; two thousand refused pairs only finish
    // because each propagation released the one resource it had acquired.
    const outcome = try box.run("partial.my", partial);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 2000), outcome.value);
}
const wrappers = declarations ++ helpers ++
    \\class Inner:
    \\    file: File
    \\
    \\
    \\class Pair:
    \\    first: Inner
    \\    second: File
    \\
    \\
    \\result PairResult:
    \\    ok: Pair,
    \\    err: i64
    \\
    \\
    \\def pair(fs: Filesystem) -> PairResult:
    \\    return Ok(Pair(first=Inner(file=acquire_resource[Open](fs, request())?), second=acquire_resource[Open](fs, request())?))
    \\
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    total = 0
    \\    for index in range(1000):
    \\        match pair(fs):
    \\            case PairResult.ok(value):
    \\                _ = value
    \\            case PairResult.err(e):
    \\                return 0 - e
    \\        total = total + 1
    \\    return total
;
test "nested resource wrappers release at scope exit and traps unwind every instruction" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    var compilation = try language.Compilation.init(t.allocator, "wrappers.my", wrappers);
    defer compilation.deinit();
    var options = box.options();
    // Every budget cuts the first pair at a different boundary; a leaked or
    // twice-released owner would abort instead of returning or trapping cleanly.
    // The exit status now carries the entry result, so a clean run is one that
    // either returned normally or trapped with a runtime `R_*` code.
    for (1..90) |budget| {
        options.max_steps = budget;
        const outcome = try native.runWithOptions(&compilation, options);
        try t.expect(!outcome.trapped() or std.mem.startsWith(u8, outcome.trap.code, "R_"));
    }
    options.max_steps = null;
    try t.expectEqual(@as(i64, 1000), (try native.runWithOptions(&compilation, options)).value);
}
test "independent bytecode validation rejects suppressed cleanup effects and malformed resource results" {
    var c = try language.Compilation.init(t.allocator, "invalid.my", retry);
    defer c.deinit();
    try c.emit();
    const functions = @constCast(c.code.?.functions);
    const effects = functions[1].policy.effects;
    functions[1].policy.effects = 0;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    functions[1].policy.effects = effects;
    const instruction = try @import("instruction_test.zig").find(@constCast(functions[1].scope.instructions), .complete_resource);
    const original = instruction.*;
    instruction.op.complete_resource = .i64;
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, c.code.?));
    instruction.* = original;
    try language.bytecode.validate(t.allocator, c.code.?);
}

test "resource acquisition identity and cleanup contracts survive exact duplicate discovery" {
    const source = declarations ++
        \\def a(fs: Filesystem) -> Open effects(filesystem):
        \\    request: [1]u8 = [42u8]
        \\    return acquire_resource[Open](fs, request)
        \\
        \\
        \\def b(dir: Filesystem) -> Open effects(filesystem):
        \\    request: [1]u8 = [42u8]
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\def c(dir: Filesystem) -> Open effects(filesystem):
        \\    request: [1]u8 = [43u8]
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "duplicates.my", source);
    defer compilation.deinit();
    try compilation.check();
    var analysis = try language.duplicates.discover(t.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer analysis.deinit();
    try t.expectEqual(@as(usize, 1), analysis.groups.len);
    try t.expectEqual(@as(usize, 2), analysis.groups[0].members.len);
    try t.expect(compilation.code == null);
}
test "source frame traps release the resource moved through recursive calls" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    var compilation = try language.Compilation.init(t.allocator, "recursive.my", declarations ++ helpers ++
        \\def recurse(file: File) -> i64:
        \\    return recurse(file)
        \\
        \\
        \\def main(fs: Filesystem) -> i64:
        \\    match acquire_resource[Open](fs, request()):
        \\        case Open.ok(file):
        \\            return recurse(file)
        \\        case Open.err(e):
        \\            return e
    );
    defer compilation.deinit();
    var options = box.options();
    options.max_frames = 3;
    const outcome = try native.runWithOptions(&compilation, options);
    try t.expectEqualStrings("R_FRAME_LIMIT", outcome.trap.code);
    try t.expectEqual(@as(u8, 1), outcome.status);
}

const generic_cleanup = declarations ++ helpers ++
    \\class Owned:
    \\    file: File
    \\    code: i64
    \\
    \\
    \\def forward[T](file: File) -> File effects(filesystem):
    \\    return file
    \\
    \\
    \\def drop[T](file: File) -> i64 effects(filesystem):
    \\    return 1
    \\
    \\
    \\def fields[T](value: Owned) -> i64 effects(filesystem):
    \\    _ = value
    \\    return 7
    \\
    \\
    \\def handle[T](r: Open) -> i64 effects(filesystem):
    \\    match r:
    \\        case Open.ok(file):
    \\            return fields[bool](Owned(file=forward[bool](file), code=7))
    \\        case Open.err(code):
    \\            return code
    \\
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    total = 0
    \\    for index in range(1000):
    \\        first = handle[bool](acquire_resource[Open](fs, request()))
    \\        match acquire_resource[Open](fs, request()):
    \\            case Open.ok(file):
    \\                total = first + drop[bool](file)
    \\            case Open.err(code):
    \\                return 0 - code
    \\    return total
;
fn genericCleanupScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-cleanup.my", generic_cleanup);
    defer c.deinit();
    try c.emit();
    try t.expect(c.code.?.functions.len != 0);
}
// spec: GENERIC-CLEANUP-1
test "generic owned resources clean up explicit and implicit drops under allocation failure" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    // Two thousand owners pass through generic forwarding, an explicit drop and
    // an implicit scope exit; none of them may outlive its iteration.
    const outcome = try box.run("generic-cleanup.my", generic_cleanup);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 8), outcome.value);
    try genericCleanupScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericCleanupScenario, .{});
}

const generic_retry = declarations ++
    \\def open[G](cap: Filesystem) -> Open effects(filesystem):
    \\    return acquire_resource[Open](cap, request())
    \\
    \\
    \\def finish[G](file: File) -> Finish effects(filesystem):
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            return Ok(done)
    \\        case Finish.err(failure):
    \\            return complete_resource[Finish](failure.resource)
    \\
    \\
++ helpers ++
    \\def attempt(cap: Filesystem) -> i64 effects(filesystem):
    \\    match open[bool](cap):
    \\        case Open.ok(file):
    \\            match finish[bool](file):
    \\                case Finish.ok(_):
    \\                    return 7
    \\                case Finish.err(failure):
    \\                    return failure.code
    \\        case Open.err(e):
    \\            return e
    \\
    \\
    \\def main(cap: Filesystem) -> i64:
    \\    return attempt(cap) * 100 + attempt(restrict_resource[read](cap))
;
fn genericRetryScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-retry.my", generic_retry);
    defer c.deinit();
    try c.emit();
    try t.expect(c.code.?.functions.len != 0);
}
test "generic resource acquisition and completion return ownership for retry under allocation failures" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run("generic-retry.my", generic_retry);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 702), outcome.value);
    try genericRetryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericRetryScenario, .{});
}
