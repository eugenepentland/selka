//! Source-level resource ownership against a real granted directory: delegated
//! authority, refused completion that hands the owner back, and cleanup order.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const Sandbox = @import("io_files_test.zig").Sandbox;
const module = "resources.selka";
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
    \\func request() -> FixedArray[u8, 10]:
    \\    return FixedArray[u8, 10]([114u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8])
    \\
    \\
    \\func missing() -> FixedArray[u8, 12]:
    \\    return FixedArray[u8, 12]([114u8, 58u8, 97u8, 98u8, 115u8, 101u8, 110u8, 116u8, 46u8, 98u8, 105u8, 110u8])
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
    \\func open(auth: Authority) -> Open effects(filesystem):
    \\    return acquire_resource[Open](auth.fs, request())
    \\
    \\
    \\func retry(file: File) -> Finish:
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            return Ok(done)
    \\        case Finish.err(failure):
    \\            return complete_resource[Finish](failure.resource)
    \\
    \\
++ helpers ++
    \\func attempt(fs: Filesystem) -> i64 effects(filesystem):
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
    \\func main(fs: Filesystem) -> i64 effects(filesystem):
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
    \\func attempt(fs: Filesystem) -> i64 effects(filesystem):
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
    \\func main(fs: Filesystem) -> i64 effects(filesystem):
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
    \\func writeRequest() -> FixedArray[u8, 10]:
    \\    return FixedArray[u8, 10]([119u8, 58u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8])
    \\
    \\
    \\func acquires(fs: Filesystem) -> i64 effects(filesystem):
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
    \\func main(fs: Filesystem) -> i64:
    \\    return acquires(fs) * 10 + acquires(fs.read_only())
;
// spec: CAPABILITY-METHOD-NARROWING-1
test "fs.read_only denies a write acquisition the full capability allows" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run("write-denial.selka", write_denial);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 10), outcome.value);
}
const partial = declarations ++ helpers ++
    \\func work(fs: Filesystem) -> Status:
    \\    mut a = try acquire_resource[Open](fs, request())
    \\    mut b = try acquire_resource[Open](fs, missing())
    \\    _ = a
    \\    _ = b
    \\    return Ok(True)
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
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
    const outcome = try box.run("partial.selka", partial);
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
    \\func pair(fs: Filesystem) -> PairResult:
    \\    const first_file = try acquire_resource[Open](fs, request())
    \\    const first = Inner(file=first_file)
    \\    const second = try acquire_resource[Open](fs, request())
    \\    return Ok(Pair(first=first, second=second))
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
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
    var options = box.options();
    // The unbounded run first, then one run per budget, all of one build and run
    // as one batch (NEW-CORE-S5-UNITS-BATCH-1).
    var programs: native.Batch = .init(t.allocator);
    defer programs.deinit();
    try programs.add("wrappers.selka", wrappers, options);
    // Every budget cuts the first pair at a different boundary; a leaked or
    // twice-released owner would abort instead of returning or trapping cleanly.
    // The exit status now carries the entry result, so a clean run is one that
    // either returned normally or trapped with a runtime `R_*` code.
    for (1..90) |budget| {
        options.max_steps = budget;
        try programs.again(0, options);
    }
    const runs = try programs.run();
    try t.expectEqual(@as(i64, 1000), runs[0].value);
    try native.expectEndedCleanly(runs[1..]);
}

test "resource acquisition identity and cleanup contracts survive exact duplicate discovery" {
    const source = declarations ++
        \\func a(fs: Filesystem) -> Open effects(filesystem):
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        \\    return acquire_resource[Open](fs, request)
        \\
        \\
        \\func b(dir: Filesystem) -> Open effects(filesystem):
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\func c(dir: Filesystem) -> Open effects(filesystem):
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([43u8])
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "duplicates.selka", source);
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
    var compilation = try language.Compilation.init(t.allocator, "recursive.selka", declarations ++ helpers ++
        \\func recurse(file: File) -> i64:
        \\    return recurse(file)
        \\
        \\
        \\func main(fs: Filesystem) -> i64:
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
    \\func forward[T](file: File) -> File effects(filesystem):
    \\    return file
    \\
    \\
    \\func drop[T](file: File) -> i64 effects(filesystem):
    \\    return 1
    \\
    \\
    \\func fields[T](value: Owned) -> i64 effects(filesystem):
    \\    _ = value
    \\    return 7
    \\
    \\
    \\func handle[T](r: Open) -> i64 effects(filesystem):
    \\    match r:
    \\        case Open.ok(file):
    \\            return fields[bool](Owned(file=forward[bool](file), code=7))
    \\        case Open.err(code):
    \\            return code
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
    \\    for index in range(1000):
    \\        mut first = handle[bool](acquire_resource[Open](fs, request()))
    \\        match acquire_resource[Open](fs, request()):
    \\            case Open.ok(file):
    \\                total = first + drop[bool](file)
    \\            case Open.err(code):
    \\                return 0 - code
    \\    return total
;
fn genericCleanupScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-cleanup.selka", generic_cleanup);
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
    const outcome = try box.run("generic-cleanup.selka", generic_cleanup);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 8), outcome.value);
    try genericCleanupScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericCleanupScenario, .{});
}

const generic_retry = declarations ++
    \\func open[G](cap: Filesystem) -> Open effects(filesystem):
    \\    return acquire_resource[Open](cap, request())
    \\
    \\
    \\func finish[G](file: File) -> Finish effects(filesystem):
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            return Ok(done)
    \\        case Finish.err(failure):
    \\            return complete_resource[Finish](failure.resource)
    \\
    \\
++ helpers ++
    \\func narrow[G](cap: Filesystem) -> Filesystem:
    \\    return cap.read_only()
    \\
    \\
    \\func attempt(cap: Filesystem) -> i64 effects(filesystem):
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
    \\func main(cap: Filesystem) -> i64:
    \\    return attempt(cap) * 100 + attempt(narrow[bool](cap))
;
fn genericRetryScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-retry.selka", generic_retry);
    defer c.deinit();
    try c.check();
}
test "generic resource acquisition and completion return ownership for retry under allocation failures" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run("generic-retry.selka", generic_retry);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 702), outcome.value);
    try genericRetryScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericRetryScenario, .{});
}

const directory_scope = declarations ++ helpers ++
    \\func escapeRequest() -> FixedArray[u8, 13]:
    \\    return FixedArray[u8, 13]([114u8, 58u8, 46u8, 46u8, 47u8, 100u8, 97u8, 116u8, 97u8, 46u8, 98u8, 105u8, 110u8])
    \\
    \\
    \\func openAndFinish(d: Filesystem) -> i64 effects(filesystem):
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
    \\func escapeAndFinish(d: Filesystem) -> i64 effects(filesystem):
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
    \\func main(fs: Filesystem) -> i64:
    \\    mut d = fs.dir("nested")
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
    const outcome = try box.run("directory-scope.selka", directory_scope);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 102), outcome.value);
}
const directory_lazy =
    \\func main(fs: Filesystem) -> i64 effects():
    \\    mut d = fs.dir("absent-directory")
    \\    _ = d
    \\    return 7
;
// spec-case: FILESYSTEM-DIR-1
test "fs.dir records a scope without opening the directory or adding an effect" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const outcome = try box.run("directory-lazy.selka", directory_lazy);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 7), outcome.value);
}
const directory_readonly = declarations ++ helpers ++
    \\func main(fs: Filesystem) -> i64:
    \\    mut d = fs.dir("nested")
    \\    mut r = d.read_only()
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
    const outcome = try box.run("directory-readonly.selka", directory_readonly);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 1), outcome.value);
}
const dynamic_dir = declarations ++
    \\func main(fs: Filesystem) -> i64:
    \\    mut path = "nested"
    \\    mut d = fs.dir(path)
    \\    _ = d
    \\    return 0
;
const escaping_dir = declarations ++
    \\func main(fs: Filesystem) -> i64:
    \\    mut d = fs.dir("../escape")
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
    try t.expectEqualStrings("E_FILESYSTEM_DIR", try dirDiagnostic("dynamic-dir.selka", dynamic_dir));
    try t.expectEqualStrings("E_FILESYSTEM_DIR", try dirDiagnostic("escaping-dir.selka", escaping_dir));
}
const generic_dir = declarations ++ helpers ++
    \\func openIn[G](cap: Filesystem) -> Open effects(filesystem):
    \\    mut scoped = cap.dir("nested")
    \\    return acquire_resource[Open](scoped, request())
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
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
    var c = try language.Compilation.init(allocator, "generic-dir.selka", generic_dir);
    defer c.deinit();
    try c.check();
}
// spec-case: FILESYSTEM-DIR-1
test "generic bodies derive a dir scope and resolve under it" {
    var box: Sandbox = undefined;
    try directorySandbox(&box);
    defer box.deinit();
    const outcome = try box.run("generic-dir.selka", generic_dir);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 1), outcome.value);
    try genericDirScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), genericDirScenario, .{});
}

const ScopedLiteralCase = struct { text: []const u8, valid: bool };

fn assertScopedLiteral(path: ScopedLiteralCase) !void {
    for ([_][]const u8{ "", "[T]" }) |generic| {
        const input = try std.fmt.allocPrint(t.allocator, "func scoped{s}(fs: Filesystem) -> Unit:\n    _ = fs.dir(\"{s}\")\n\nfunc main() -> int:\n    return 0\n", .{ generic, path.text });
        defer t.allocator.free(input);
        var compilation = try language.Compilation.init(t.allocator, "shared-dir.selka", input);
        defer compilation.deinit();
        if (path.valid) {
            try compilation.check();
        } else {
            try t.expectError(error.SourceError, compilation.check());
            try t.expectEqualStrings("E_FILESYSTEM_DIR", compilation.diagnostics.items[0].code);
            const text = compilation.src.text(compilation.diagnostics.items[0].span);
            try t.expectEqualStrings(path.text, text[1 .. text.len - 1]);
        }
    }
}

// spec-case: FILESYSTEM-DIR-1
test "shared dir validator agrees for concrete and unused generic literal paths" {
    const paths = [_]ScopedLiteralCase{
        .{ .text = "", .valid = true },
        .{ .text = "資料/λ", .valid = true },
        .{ .text = "../escape", .valid = false },
        .{ .text = "data/./raw", .valid = false },
        .{ .text = "data//raw", .valid = false },
        .{ .text = "/absolute", .valid = false },
    };
    for (paths) |path| try assertScopedLiteral(path);
}
