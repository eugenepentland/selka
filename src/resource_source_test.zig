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
    \\record Failure:
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
    \\record Authority:
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
    \\    return attempt(fs) * 100 + attempt(fs.read_only())
;
fn retryScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, module, retry);
    defer c.deinit();
    try c.check();
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
/// One completion per attempt: a full grant completes, a read-only one refuses
/// and hands the handle back inside its failure record.
const complete_once = declarations ++ helpers ++
    \\def attempt(fs: Filesystem) -> i64 effects(filesystem):
    \\    match acquire_resource[Open](fs, request()):
    \\        case Open.ok(file):
    \\            match complete_resource[Finish](file):
    \\                case Finish.ok(done):
    \\                    if done:
    \\                        return 7
    \\                    return 0
    \\                case Finish.err(failure):
    \\                    return failure.code
    \\        case Open.err(e):
    \\            return e
    \\
    \\
    \\def main(fs: Filesystem) -> i64 noalloc:
    \\    return attempt(fs) * 100 + attempt(fs.read_only())
;

test "RC completion takes its handle over whether the provider completes or refuses it" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run(module, complete_once);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 702), outcome.value);
}

test "RC moves a refused handle out of its failure record into a second completion" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    // `retry` completes `failure.resource` after a refusal: the field moves
    // out of the consumed record, so the record's cleanup cannot close it.
    const outcome = try box.run(module, retry);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 702), outcome.value);
}

test "ownExternal and source acquisition completion retry clean every allocation failure" {
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), retryScenario, .{});
}
const write_denial = declarations ++
    \\def writeRequest() -> [10]u8:
    \\    return [119u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\def acquires(fs: Filesystem) -> i64 effects(filesystem):
    \\    match acquire_resource[Open](fs, writeRequest()):
    \\        case Open.ok(file):
    \\            match complete_resource[Finish](file):
    \\                case Finish.ok(_):
    \\                    return 1
    \\                case Finish.err(_):
    \\                    return 0
    \\        case Open.err(_):
    \\            return 0
    \\
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    return acquires(fs) * 10 + acquires(fs.read_only())
;
// spec: CAPABILITY-METHOD-NARROWING-1
test "fs.read_only denies a write acquisition the full capability allows" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run("write-denial.my", write_denial);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 10), outcome.value);
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
    \\record Inner:
    \\    file: File
    \\
    \\
    \\record Pair:
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
    \\record Owned:
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
    try c.check();
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
    \\def narrow[G](cap: Filesystem) -> Filesystem:
    \\    return cap.read_only()
    \\
    \\
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
    \\    return attempt(cap) * 100 + attempt(narrow[bool](cap))
;
fn genericRetryScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-retry.my", generic_retry);
    defer c.deinit();
    try c.check();
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

const directory_scope = declarations ++ helpers ++
    \\def escapeRequest() -> [13]u8:
    \\    return [114u8, 58u8, 46u8, 46u8, 47u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8]
    \\
    \\
    \\def openAndFinish(d: Filesystem) -> i64 effects(filesystem):
    \\    match acquire_resource[Open](d, request()):
    \\        case Open.ok(file):
    \\            match complete_resource[Finish](file):
    \\                case Finish.ok(_):
    \\                    return 1
    \\                case Finish.err(_):
    \\                    return 0
    \\        case Open.err(code):
    \\            return code
    \\
    \\
    \\def escapeAndFinish(d: Filesystem) -> i64 effects(filesystem):
    \\    match acquire_resource[Open](d, escapeRequest()):
    \\        case Open.ok(file):
    \\            match complete_resource[Finish](file):
    \\                case Finish.ok(_):
    \\                    return 0
    \\                case Finish.err(_):
    \\                    return 1
    \\        case Open.err(code):
    \\            return code
    \\
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    d = fs.dir("nested")
    \\    return openAndFinish(d) * 100 + escapeAndFinish(d)
;
/// A granted directory with a nested subdirectory for `fs.dir` scope tests.
fn directorySandbox(box: *Sandbox) !void {
    try box.init(true);
    try box.temporary.dir.createDir(t.io, "nested", .default_dir);
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "data.bin", .data = "root" });
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "nested/data.bin", .data = "nested" });
}
// spec: FILESYSTEM-DIR-1
test "fs.dir confines a derived filesystem to its root and refuses escapes" {
    var box: Sandbox = undefined;
    try directorySandbox(&box);
    defer box.deinit();
    const outcome = try box.run("directory-scope.my", directory_scope);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 102), outcome.value);
}
const directory_lazy =
    \\def main(fs: Filesystem) -> i64 effects():
    \\    d = fs.dir("absent-directory")
    \\    _ = d
    \\    return 7
;
// spec-case: FILESYSTEM-DIR-1
test "fs.dir records a scope without opening the directory or adding an effect" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run("directory-lazy.my", directory_lazy);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 7), outcome.value);
}
const directory_readonly = declarations ++ helpers ++
    \\def main(fs: Filesystem) -> i64:
    \\    d = fs.dir("nested")
    \\    r = d.read_only()
    \\    match acquire_resource[Open](r, request()):
    \\        case Open.ok(file):
    \\            _ = file
    \\            return 1
    \\        case Open.err(code):
    \\            return code
;
/// A granted directory whose only fixture is the nested one, so a lost scope
/// cannot accidentally resolve `data.bin` at the root.
fn readOnlyScopeSandbox(box: *Sandbox) !void {
    try box.init(true);
    try box.temporary.dir.createDir(t.io, "nested", .default_dir);
    try box.temporary.dir.writeFile(t.io, .{ .sub_path = "nested/data.bin", .data = "nested" });
}
// spec-case: FILESYSTEM-DIR-1
test "fs.read_only preserves a dir scope while narrowing permissions" {
    var box: Sandbox = undefined;
    try readOnlyScopeSandbox(&box);
    defer box.deinit();
    const outcome = try box.run("directory-readonly.my", directory_readonly);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 1), outcome.value);
}
const dynamic_dir = declarations ++
    \\def main(fs: Filesystem) -> i64:
    \\    path = "nested"
    \\    d = fs.dir(path)
    \\    _ = d
    \\    return 0
;
const escaping_dir = declarations ++
    \\def main(fs: Filesystem) -> i64:
    \\    d = fs.dir("../escape")
    \\    _ = d
    \\    return 0
;
fn dirDiagnostic(name: []const u8, source: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, name, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    return compilation.diagnostics.items[0].code;
}
// spec-case: FILESYSTEM-DIR-1
test "fs.dir rejects a dynamic path and a path escaping the current root" {
    try t.expectEqualStrings("E_FILESYSTEM_DIR", try dirDiagnostic("dynamic-dir.my", dynamic_dir));
    try t.expectEqualStrings("E_FILESYSTEM_DIR", try dirDiagnostic("escaping-dir.my", escaping_dir));
}
const generic_dir = declarations ++ helpers ++
    \\def openIn[G](cap: Filesystem) -> Open effects(filesystem):
    \\    scoped = cap.dir("nested")
    \\    return acquire_resource[Open](scoped, request())
    \\
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    match openIn[bool](fs):
    \\        case Open.ok(file):
    \\            match complete_resource[Finish](file):
    \\                case Finish.ok(_):
    \\                    return 1
    \\                case Finish.err(_):
    \\                    return 0
    \\        case Open.err(code):
    \\            return code
;
fn genericDirScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-dir.my", generic_dir);
    defer c.deinit();
    try c.check();
}
// spec-case: FILESYSTEM-DIR-1
test "generic bodies derive a dir scope and resolve under it" {
    var box: Sandbox = undefined;
    try directorySandbox(&box);
    defer box.deinit();
    const outcome = try box.run("generic-dir.my", generic_dir);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 1), outcome.value);
    try genericDirScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericDirScenario, .{});
}
