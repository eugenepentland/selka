//! ThinLTO for an LLVM executable whose guest code carries frame-map positions
//! (LLVM-THINLTO-1). Full LTO merges every bitcode module into one and
//! optimizes and compiles it on one thread, which is most of a large
//! `--release` build. ThinLTO keeps the modules apart: LLD reads their
//! summaries, decides what each module imports and which symbols stay
//! internal, and optimizes and compiles the modules on as many threads as the
//! cores and free memory allow.
//!
//! The frame map needs each module's final assembly (QBE-FRAMEMAP-1), so LLD
//! emits one assembly file per module. It writes that file beside the module's
//! input path, so every input is linked under a private alias in this link's
//! own scratch directory, never beside a shared cached object. Each assembly
//! file is then annotated and assembled on worker threads, and the objects are
//! returned in name order for the native link.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const cache_api = @import("qbe_build_cache.zig");
const spawn = @import("qbe_build_spawn.zig");
const budget = @import("memory_budget");
const compile = @import("qbe_build_llvm_compile.zig");
const frame_map = @import("qbe_frame_map.zig");

const Allocator = std.mem.Allocator;
const Error = cache_api.Error;

/// The output LLD is given; each module's assembly is `program-lto.lto.<input>.s`.
const output_name = "program-lto";
/// Keep LLVM from merging identical code that came from different call sites.
/// A runtime helper inlined into guest code carries the position of the call
/// it replaced, and after a guest function is imported and inlined at several
/// sites, sinking common instructions or merging common block tails folds
/// those copies into one whose inline site is lost (`@ CALLER:0`), which the
/// frame map cannot attribute. The Lox port's ThinLTO build hit it; either
/// switch alone avoided it there, and both are off for margin.
const keep_call_sites = [_][]const u8{ "-mllvm", "-sink-common-insts=false", "-mllvm", "-enable-tail-merge=false" };

/// What one ThinLTO link reads: the build's cache (its context and tools),
/// LLD's optimization switches for the build's level, every input in link
/// order (native objects included, the runtime archive last), the scratch
/// directory it fills, and every guest unit's name by its probe GUID.
pub const Request = struct {
    cache: cache_api.Cache,
    level: []const []const u8,
    inputs: []const []const u8,
    directory: []const u8,
    known: *const frame_map.Names,
};

/// Optimize and compile the bitcode among the inputs module by module and
/// return the annotated, assembled objects in name order: everything the
/// bitcode contributes to the executable. The native inputs are only read.
pub fn link(request: Request) Error![]const []const u8 {
    const context = request.cache.context;
    const a = context.allocator;
    const staging = try std.fs.path.join(a, &.{ request.directory, "thin" });
    try context.mkdir(staging);
    const aliases = try a.alloc([]const u8, request.inputs.len);
    for (request.inputs, aliases, 0..) |input, *name, index| name.* = try alias(context, staging, .{ .input = input, .index = index });
    const shape: Shape = .{ .zig = request.cache.zig, .level = request.level, .jobs = workers(context, request.inputs.len), .output = try std.fs.path.join(a, &.{ staging, output_name }) };
    try context.command(try command(a, shape, aliases), null);
    return assembleAll(request, try assemblyFiles(context, staging));
}

/// What the LLD command reads besides its inputs: the Zig that runs it, the
/// optimization switches, how many modules it compiles at once and its output.
const Shape = struct { zig: []const u8, level: []const []const u8, jobs: usize, output: []const u8 };

/// The LLD command that optimizes and compiles every bitcode module among
/// `inputs` to its own assembly file, keeping each call site's position.
fn command(allocator: Allocator, shape: Shape, inputs: []const []const u8) Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ shape.zig, "ld.lld", "--error-limit=0", "-mllvm", "-float-abi=hard" });
    try argv.appendSlice(allocator, shape.level);
    try argv.appendSlice(allocator, &keep_call_sites);
    const jobs = try std.fmt.allocPrint(allocator, "--thinlto-jobs={d}", .{shape.jobs});
    try argv.appendSlice(allocator, &.{ "--lto-emit-asm", jobs, "-m", "elf_x86_64", "--entry", "main", "-o", shape.output });
    try argv.appendSlice(allocator, inputs);
    return argv.items;
}

/// One input to alias: its path and its place in the link order.
const Input = struct { input: []const u8, index: usize };

/// A private name for one input in the staging directory, numbered in link
/// order, so LLD writes that input's assembly beside the alias.
fn alias(context: fs.Context, staging: []const u8, input: Input) Error![]const u8 {
    const a = context.allocator;
    const name = try std.fmt.allocPrint(a, "{s}/{d:0>7}{s}", .{ staging, input.index, std.fs.path.extension(input.input) });
    std.Io.Dir.cwd().symLink(context.io, try context.absolute(input.input), name, .{}) catch return failed(context, "could not stage a ThinLTO input");
    return name;
}

/// How many modules to optimize, or files to assemble, at once.
fn workers(context: fs.Context, work: usize) usize {
    return budget.workers(.{ .programs = work, .cores = std.Thread.getCpuCount() catch 1, .free = budget.available(context.io), .ceiling = 0 });
}

/// Every assembly file LLD wrote into the staging directory, in name order.
fn assemblyFiles(context: fs.Context, staging: []const u8) Error![]const []const u8 {
    const a = context.allocator;
    var directory = std.Io.Dir.cwd().openDir(context.io, staging, .{ .iterate = true }) catch return failed(context, "could not list the ThinLTO assembly");
    defer directory.close(context.io);
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterate();
    while (iterator.next(context.io) catch return failed(context, "could not list the ThinLTO assembly")) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".s")) continue;
        try names.append(a, try std.fs.path.join(a, &.{ staging, entry.name }));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    return names.items;
}

fn failed(context: fs.Context, message: []const u8) Error {
    try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "mylang: {s}\n", .{message}));
    return error.NativeToolFailed;
}

/// Annotate and assemble every file on worker threads; the objects keep the
/// files' order. The first failure stops new work.
fn assembleAll(request: Request, files: []const []const u8) Error![]const []const u8 {
    const cache = request.cache;
    const context = cache.context;
    const a = context.allocator;
    const objects = try a.alloc([]const u8, files.len);
    for (files, objects) |file, *object| object.* = try std.fmt.allocPrint(a, "{s}.o", .{file});
    const assembler = try compile.Tool.probe(cache, .{ .flags = &.{ "-g0", "-c" }, .names = .{ "unit.s", "unit.o" }, .front = "-cc1as" });
    var queue: Queue = .{ .request = &request, .assembler = &assembler, .files = files, .objects = objects };
    const threads = try a.alloc(?std.Thread, workers(context, files.len));
    @memset(threads, null);
    // A worker that cannot be started leaves its share to the others.
    for (threads[1..]) |*thread| thread.* = std.Thread.spawn(.{}, Queue.work, .{&queue}) catch null;
    queue.work();
    for (threads) |thread| if (thread) |started| started.join();
    if (queue.failure) |message| return failed(context, message);
    return objects;
}

/// The shared list of assembly files the workers take from.
const Queue = struct {
    request: *const Request,
    assembler: *const compile.Tool,
    files: []const []const u8,
    objects: []const []const u8,
    next: std.atomic.Value(usize) = .init(0),
    mutex: std.Io.Mutex = .init,
    failure: ?[]const u8 = null,

    /// Take files until none is left or one has failed; each file's scratch
    /// lives in this worker's arena, reset after every file.
    fn work(self: *Queue) void {
        const context = self.request.cache.context;
        var scratch = std.heap.ArenaAllocator.init(context.parent);
        defer scratch.deinit();
        while (!self.stopped()) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.files.len) return;
            defer _ = scratch.reset(.retain_capacity);
            self.assembleOne(scratch.allocator(), index) catch |err| self.fail(@errorName(err));
        }
    }

    fn stopped(self: *Queue) bool {
        const io = self.request.cache.context.io;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.failure != null;
    }

    /// Record the first failure; later ones are consequences of stopping.
    fn fail(self: *Queue, message: []const u8) void {
        const io = self.request.cache.context.io;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.failure == null) self.failure = self.request.cache.context.allocator.dupe(u8, message) catch "out of memory while reporting a ThinLTO module";
    }

    /// Give one module's assembly its frame-map table and assemble it.
    fn assembleOne(self: *Queue, allocator: Allocator, index: usize) Error!void {
        var context = self.request.cache.context;
        context.allocator = allocator;
        const file = self.files[index];
        const text = try context.read(file);
        const annotated = try cache_api.annotateText(context, text, self.request.known);
        if (!std.mem.eql(u8, text, annotated)) try context.write(file, annotated);
        const finished = try spawn.run(allocator, .{ .argv = try self.assembler.command(allocator, file, self.objects[index]) });
        if (fs.exitCode(finished.term) != 0) {
            self.fail(try std.fmt.allocPrint(allocator, "the assembler rejected the ThinLTO module {s}:\n{s}", .{ std.fs.path.basename(file), finished.stderr }));
        }
    }
};

// spec-case: LLVM-THINLTO-1
test "the ThinLTO link emits per-module assembly on several threads and keeps call sites apart" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const shape: Shape = .{ .zig = "/zig", .level = &.{ "--lto-O3", "-O3" }, .jobs = 6, .output = "/w/thin/program-lto" };
    const argv = try command(arena.allocator(), shape, &.{ "/w/thin/0000000.o", "/w/thin/0000001.a" });
    const joined = try std.mem.join(arena.allocator(), " ", argv);
    try std.testing.expectEqualStrings("/zig", argv[0]);
    try std.testing.expect(std.mem.indexOf(u8, joined, "--lto-O3 -O3") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "--thinlto-jobs=6") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "--lto-emit-asm") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-mllvm -sink-common-insts=false -mllvm -enable-tail-merge=false") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "--lto-partitions") == null);
    try std.testing.expectEqualStrings("/w/thin/0000001.a", argv[argv.len - 1]);
}
