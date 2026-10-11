//! Moved task captures and group cleanup through the native task bridge.
const std = @import("std");
const program = @import("zero_rc_task_program.zig");
const support = @import("test_support.zig");
const driver = @import("driver.zig");
const emitter = @import("emit_llvm.zig");
const passes = @import("passes.zig");
const contract = @import("single_owner.zig");
const zero = @import("zero_rc.zig");
const io = std.testing.io;
const report = std.debug.print;
const Options = struct { implicit_exit: bool = false, release: bool = false, sanitized: bool = false, source_map: bool = false };

fn location(_: *const anyopaque, _: u32) emitter.Location {
    return .{ .path = "owned-tasks.my", .line = 1, .column = 1 };
}
fn matrix(parent: std.mem.Allocator, options: Options) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(io, ".", a);
    var module = if (options.source_map) try sourceMap(a) else try program.program(a, options.implicit_exit, false);
    try support.verified(a, &module, &.{});
    const result = if (options.release) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
    var failure: contract.Failure = .{};
    contract.verifyLowered(&module, &failure) catch |err| {
        report("{s}\n{s}\n", .{ failure.message, try @import("print.zig").module(a, &module) });
        return err;
    };
    const context: u8 = 0;
    const llvm = try emitter.emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = location },
        .source_path = "owned-tasks.my",
        .main = .{ .parameters = &.{"out"} },
        .verify = options.release,
        .counters = !options.sanitized,
        .analysis = support.analysis(&result),
    });
    try std.testing.expect(zero.emittedClean(llvm));
    var environment = try std.testing.environ.createMap(a);
    if (options.sanitized) try environment.put("MYLANG_CORE_SANITIZE", "thread");
    try environment.put("MYL_CORE_LEAKCHECK", "1");
    const counts = try std.fs.path.join(a, &.{ root, "counts.json" });
    try environment.put("MYLANG_COUNTERS", counts);
    const binary = try std.fs.path.join(a, &.{ root, "owned-tasks" });
    var log: std.ArrayList(u8) = .empty;
    _ = driver.link(a, io, &environment, .{
        .zig = environment.get("ZIG") orelse "zig",
        .work = root,
        .output = binary,
        .mode = if (options.release) .release else .debug,
        .links = &.{},
        .units = &.{driver.wholeUnit(llvm)},
    }, &log) catch |err| {
        report("{s}", .{log.items});
        return err;
    };
    for ([_][]const u8{ "1", "2", "8" }) |threads| {
        try environment.put("MYLANG_THREADS", threads);
        const ran = try std.process.run(a, io, .{ .argv = &.{binary}, .environ_map = &environment });
        if (ran.term != .exited or ran.term.exited != 0) report("{any}\n{s}\n{s}\n", .{ ran.term, ran.stdout, ran.stderr });
        try std.testing.expect(ran.term == .exited and ran.term.exited == 0);
        try std.testing.expectEqualStrings(if (options.source_map) "item-1 item-1! item-2!\nitem-1!\n" else if (options.implicit_exit) "0\n" else "1110\n", ran.stdout);
        try std.testing.expectEqualStrings("", ran.stderr);
        if (!options.sanitized) {
            const data = try directory.dir.readFileAlloc(io, "counts.json", a, .limited(4 << 20));
            try std.testing.expect(std.mem.indexOf(u8, data, "\"live_bytes_at_exit\":0") != null);
            try exportCounts(a, environment, options, threads, data);
        }
    }
    if (environment.get("MYLANG_ZERO_RC_TASK_OUTPUT")) |destination| {
        const name = try std.fmt.allocPrint(a, "{s}/{s}-{s}", .{ destination, if (options.implicit_exit) "exit" else "take", if (options.sanitized) "tsan" else if (options.release) "release" else "debug" });
        try std.Io.Dir.cwd().createDirPath(io, destination);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, binary, a, .limited(64 << 20));
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = name, .data = bytes, .flags = .{ .permissions = .fromMode(0o755) } });
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.ll", .{name}), .data = llvm });
    }
}
fn exportCounts(a: std.mem.Allocator, environment: std.process.Environ.Map, options: Options, threads: []const u8, data: []const u8) !void {
    const destination = environment.get("MYLANG_ZERO_RC_TASK_OUTPUT") orelse return;
    try std.Io.Dir.cwd().createDirPath(io, destination);
    const name = try std.fmt.allocPrint(a, "{s}/counts-{s}-{s}-{s}.json", .{ destination, if (options.implicit_exit) "exit" else "take", if (options.release) "release" else "debug", threads });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = name, .data = data });
}
// spec: NEW-CORE-ZERO-RC-TASKS-1
test "zero RC task groups move captures and results across joins at 1 2 8 threads" {
    try matrix(std.testing.allocator, .{});
    try matrix(std.testing.allocator, .{ .release = true });
}
// spec-case: NEW-CORE-ZERO-RC-TASKS-1
test "zero RC task groups join and destroy discarded results on implicit exit" {
    try matrix(std.testing.allocator, .{ .implicit_exit = true });
    try matrix(std.testing.allocator, .{ .implicit_exit = true, .release = true });
}
// spec-case: NEW-CORE-ZERO-RC-TASKS-1
test "zero RC task captures and results are free from ThreadSanitizer reports" {
    try matrix(std.testing.allocator, .{ .release = true, .sanitized = true });
    try matrix(std.testing.allocator, .{ .implicit_exit = true, .release = true, .sanitized = true });
}
// spec-case: NEW-CORE-ZERO-RC-TASKS-1
test "zero RC task boundary refuses reused captures and the borrowed legacy ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module = try program.program(a, false, true);
    _ = try passes.debug(a, &module);
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.verifyLowered(&module, &failure));
    try std.testing.expectEqualStrings("E_ZERO_RC_LOWERING", failure.code);
    try std.testing.expect(zero.contract("myl_core_task_submit") == null);
    try std.testing.expect(zero.contract("myl_core_task_result") == null);
}

const MapEntry = struct {
    /// Supply the entry source while standard imports use the embedded loader.
    pub fn read(_: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) @import("mylang").project.ReadError![]u8 {
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8,
            \\import parallel
            \\func transform(value: str) -> str:
            \\    return value + "!"
            \\func main(out: Stream) -> int:
            \\    mut source = ["item-" + str(1), "item-" + str(2)]
            \\    const result = parallel.map(source, transform)
            \\    out.print(source[0], result[0], result[1])
            \\    source.clear()
            \\    out.print(result[0])
            \\    return 0
        );
    }
};
fn sourceMap(a: std.mem.Allocator) !@import("ir.zig").Module {
    const language = @import("mylang");
    var context: u8 = 0;
    var project: language.embedded_project.Program = undefined;
    try project.init(a, .{ .context = &context, .read = MapEntry.read });
    const checked = project.compilation.program.?;
    var failure: contract.Failure = .{};
    try contract.checkMode(a, checked, &failure, true);
    var refusal: @import("build.zig").Refusal = .{};
    const module = try @import("build.zig").buildExecutable(a, .{ .program = checked, .source = project.compilation.src, .single_owner = true, .zero_rc = true }, &refusal);
    var found = false;
    for (module.functions.items) |function| {
        if (std.mem.eql(u8, function.name, "myl_core_owned_map")) found = true;
    }
    try std.testing.expect(found);
    return module;
}
// spec: NEW-CORE-ZERO-RC-TASKS-2
test "zero RC source map borrows inputs until joining and owns each result" {
    try matrix(std.testing.allocator, .{ .source_map = true });
    try matrix(std.testing.allocator, .{ .source_map = true, .release = true });
    try matrix(std.testing.allocator, .{ .source_map = true, .release = true, .sanitized = true });
}
