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
    \\func open(fs: Filesystem) -> Open:
    \\    return acquire_resource[Open](fs, request())
    \\
    \\
    \\func retry(own file: File) -> Finish:
    \\    match complete_resource[Finish](own file):
    \\        case ok(done):
    \\            return Ok(done)
    \\        case err(failure):
    \\            return complete_resource[Finish](own failure.resource)
    \\
    \\
++ helpers ++
    \\func attempt(fs: Filesystem) -> i64:
    \\    const auth = Authority(fs=fs)
    \\    match open(auth.fs):
    \\        case ok(file):
    \\            match retry(own file):
    \\                case ok(done):
    \\                    if done:
    \\                        return 7
    \\                    else:
    \\                        return 0
    \\                case err(failure):
    \\                    return failure.code
    \\        case err(e):
    \\            return e
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    with fs.read_only() as readonly:
    \\        return attempt(fs) * 100 + attempt(readonly)
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
    \\func attempt(fs: Filesystem) -> i64:
    \\    match acquire_resource[Open](fs, request()):
    \\        case ok(file):
    \\            match complete_resource[Finish](own file):
    \\                case ok(done):
    \\                    if done:
    \\                        return 7
    \\                    return 0
    \\                case err(failure):
    \\                    return failure.code
    \\        case err(e):
    \\            return e
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    with fs.read_only() as readonly:
    \\        return attempt(fs) * 100 + attempt(readonly)
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
    \\func acquires(fs: Filesystem) -> i64:
    \\    match acquire_resource[Open](fs, writeRequest()):
    \\        case ok(file):
    \\            match complete_resource[Finish](own file):
    \\                case ok(_):
    \\                    return 1
    \\                case err(_):
    \\                    return 0
    \\        case err(_):
    \\            return 0
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    with fs.read_only() as readonly:
    \\        return acquires(fs) * 10 + acquires(readonly)
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
    \\    _ = own a
    \\    _ = own b
    \\    return Ok(True)
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
    \\    for index in range(2000):
    \\        match work(fs):
    \\            case ok(done):
    \\                _ = done
    \\                return 1
    \\            case err(e):
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
    \\    const first = Inner(file=own first_file)
    \\    const second = try acquire_resource[Open](fs, request())
    \\    return Ok(Pair(first=own first, second=own second))
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
    \\    for index in range(1000):
    \\        match pair(fs):
    \\            case ok(value):
    \\                _ = own value
    \\            case err(e):
    \\                return 0 - e
    \\        total = total + 1
    \\    return total
;
// spec-case: NATIVE-ARGV-1
// spec-case: QBE-STEP-ACCOUNTING-1
test "nested resource wrappers release at scope exit and traps unwind every instruction" {
    var box: Sandbox = undefined;
    try sandbox(&box);
    defer box.deinit();
    const options = box.options();
    // One instrumented executable serves every ceiling; ordinary compiled-in
    // first/last ceilings cross-check the runtime harness at both endpoints.
    var programs: native.Batch = .init(t.allocator);
    defer programs.deinit();
    try programs.budgetSweep("wrappers.selka", wrappers, options, 90);
    const runs = try programs.run();
    try t.expectEqual(@as(i64, 1000), runs[0].value);
    try native.expectBudgetSweep(runs);
}

test "resource acquisition identity and cleanup contracts survive exact duplicate discovery" {
    const source = declarations ++
        \\func a(fs: Filesystem) -> Open:
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        \\    return acquire_resource[Open](fs, request)
        \\
        \\
        \\func b(dir: Filesystem) -> Open:
        \\    mut request: FixedArray[u8, 1] = FixedArray[u8, 1]([42u8])
        \\    return acquire_resource[Open](dir, request)
        \\
        \\
        \\func c(dir: Filesystem) -> Open:
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
        \\func recurse(own file: File) -> i64:
        \\    return recurse(own file)
        \\
        \\
        \\func main(fs: Filesystem) -> i64:
        \\    match acquire_resource[Open](fs, request()):
        \\        case ok(file):
        \\            return recurse(own file)
        \\        case err(e):
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
    \\func forward[T](own file: File) -> File:
    \\    return file
    \\
    \\
    \\func drop[T](own file: File) -> i64:
    \\    return 1
    \\
    \\
    \\func fields[T](own value: Owned) -> i64:
    \\    _ = own value
    \\    return 7
    \\
    \\
    \\func handle[T](own r: Open) -> i64:
    \\    match own r:
    \\        case ok(file):
    \\            return fields[bool](Owned(file=forward[bool](own file), code=7))
    \\        case err(code):
    \\            return code
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    mut total = 0
    \\    for index in range(1000):
    \\        mut first = handle[bool](acquire_resource[Open](fs, request()))
    \\        match acquire_resource[Open](fs, request()):
    \\            case ok(file):
    \\                total = first + drop[bool](own file)
    \\            case err(code):
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
    \\func open[G](cap: Filesystem) -> Open:
    \\    return acquire_resource[Open](cap, request())
    \\
    \\
    \\func finish[G](own file: File) -> Finish:
    \\    match complete_resource[Finish](own file):
    \\        case ok(done):
    \\            return Ok(done)
    \\        case err(failure):
    \\            return complete_resource[Finish](own failure.resource)
    \\
    \\
++ helpers ++
    \\func attempt[G](cap: Filesystem) -> i64:
    \\    match open[G](cap):
    \\        case ok(file):
    \\            match finish[G](own file):
    \\                case ok(_):
    \\                    return 7
    \\                case err(failure):
    \\                    return failure.code
    \\        case err(e):
    \\            return e
    \\
    \\
    \\func main(cap: Filesystem) -> i64:
    \\    with cap.read_only() as readonly:
    \\        return attempt[bool](cap) * 100 + attempt[bool](readonly)
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
    \\func openAndFinish(d: Filesystem) -> i64:
    \\    match acquire_resource[Open](d, request()):
    \\        case ok(file):
    \\            match complete_resource[Finish](own file):
    \\                case ok(_):
    \\                    return 1
    \\                case err(_):
    \\                    return 0
    \\        case err(code):
    \\            return code
    \\
    \\
    \\func escapeAndFinish(d: Filesystem) -> i64:
    \\    match acquire_resource[Open](d, escapeRequest()):
    \\        case ok(file):
    \\            match complete_resource[Finish](own file):
    \\                case ok(_):
    \\                    return 0
    \\                case err(_):
    \\                    return 1
    \\        case err(code):
    \\            return code
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    with fs.dir("nested") as d:
    \\        return openAndFinish(d) * 100 + escapeAndFinish(d)
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
    \\func main(fs: Filesystem) -> i64:
    \\    with fs.dir("absent-directory") as d:
    \\        _ = d
    \\        return 7
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
    \\    with fs.dir("nested") as d:
    \\        with d.read_only() as r:
    \\            match acquire_resource[Open](r, request()):
    \\                case ok(file):
    \\                    _ = own file
    \\                    return 1
    \\                case err(code):
    \\                    return code
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
test "a dynamic fs.dir path is refused with the run-time call to use instead" {
    var compilation = try language.Compilation.init(t.allocator, "dynamic-dir.selka", dynamic_dir);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_FILESYSTEM_DIR", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, "use `filesystem.dir_at(fs, path)`") != null);
}
// spec-case: FILESYSTEM-DIR-1
test "fs.dir rejects a dynamic path and a path escaping the current root" {
    try t.expectEqualStrings("E_FILESYSTEM_DIR", try dirDiagnostic("dynamic-dir.selka", dynamic_dir));
    try t.expectEqualStrings("E_FILESYSTEM_DIR", try dirDiagnostic("escaping-dir.selka", escaping_dir));
}
const generic_dir = declarations ++ helpers ++
    \\func openIn[G](cap: Filesystem) -> Open:
    \\    return acquire_resource[Open](cap, request())
    \\
    \\
    \\func main(fs: Filesystem) -> i64:
    \\    with fs.dir("nested") as scoped:
    \\        match openIn[bool](scoped):
    \\            case ok(file):
    \\                match complete_resource[Finish](own file):
    \\                    case ok(_):
    \\                        return 1
    \\                    case err(_):
    \\                        return 0
    \\            case err(code):
    \\                return code
;
fn genericDirScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-dir.selka", generic_dir);
    defer c.deinit();
    try c.check();
}
// spec-case: FILESYSTEM-DIR-1
test "generic acquisition resolves under a caller-scoped dir" {
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
        const input = if (path.valid and generic.len == 0)
            try std.fmt.allocPrint(t.allocator, "func scoped{s}(fs: Filesystem) -> Unit:\n    with fs.dir(\"{s}\") as directory:\n        _ = directory\n\nfunc main() -> int:\n    return 0\n", .{ generic, path.text })
        else
            try std.fmt.allocPrint(t.allocator, "func scoped{s}(fs: Filesystem) -> Unit:\n    _ = fs.dir(\"{s}\")\n\nfunc main() -> int:\n    return 0\n", .{ generic, path.text });
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
