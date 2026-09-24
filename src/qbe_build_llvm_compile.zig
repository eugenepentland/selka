//! The LLVM arm's object builds (LLVM-ZIG-1). Each guest unit that missed the
//! object cache is translated to LLVM IR in process (`qbe_build_llvm.zig`) on
//! a worker thread and compiled by the bundled clang, one content-addressed
//! object per unit, as many at once as the cores and free memory allow.
//!
//! No Python and no per-unit translator process is involved. The compile is
//! clang's own `-cc1` invocation, taken once per build from what `zig cc`
//! would run for the same flags (`-###`), so each unit costs one clang start
//! and not a `zig cc` driver with its host probes. A full-LTO unit is bitcode
//! the final link optimizes as a whole; without LTO a unit is assembled after
//! its frame-map annotation, exactly as before.
const std = @import("std");
const bundled = @import("qbe_build_assets");
const fs = @import("qbe_build_io.zig");
const cache_api = @import("qbe_build_cache.zig");
const lean = @import("qbe_build_units.zig");
const v = @import("qbe_build_value.zig");
const spawn = @import("qbe_build_spawn.zig");
const budget = @import("memory_budget");
const llvm = @import("qbe_build_llvm.zig");

const Allocator = std.mem.Allocator;
const Error = cache_api.Error;

/// The environment variable naming a directory that receives each translated
/// unit's input IL (`SYMBOL.ssa`), its LLVM IR (`SYMBOL.ll`) and the closure
/// signatures it read (`SYMBOL.sigs.json`). A diagnostic only: a warm object
/// cache translates nothing, so a dump wants a fresh `--cache-dir`.
pub const dump_variable = "MYLANG_LLVM_DUMP";

/// One unit that must be built: its manifest index and its object key.
pub const Miss = struct { unit: usize, key: []const u8 };

/// Everything one LLVM object build reads: the cache, every manifest unit
/// (the closure whose signatures a call site declares), the fragment store
/// lean units live in, and the units to build.
pub const Request = struct {
    cache: cache_api.Cache,
    units: []const std.json.Value,
    store: []const u8,
    misses: []const Miss,
};

/// Build every missed unit's object and return them in miss order. The first
/// failure stops new work; every failure is reported before returning.
pub fn build(request: Request) Error![]cache_api.Object {
    const context = request.cache.context;
    const a = context.allocator;
    const table = try a.create(llvm.RuntimeTable);
    table.* = try runtimeTable(a);
    const signatures = try a.create(llvm.Signatures);
    signatures.* = try closureSignatures(request);
    const compiler = try Compiler.probe(request.cache);
    const toggles = llvm.Toggles.read(context.environ);
    var failures: Failures = .{ .keep = a };
    var pool: Pool = .{
        .request = &request,
        .options = .{
            .signatures = signatures,
            .runtime = table,
            .target_cpu = request.cache.codegen.target_cpu,
            .target_features = request.cache.codegen.target_features,
            .alias = toggles.alias,
            .element_gep = toggles.element_gep,
            .sticky = toggles.sticky,
        },
        .compiler = &compiler,
        .dump = context.environ.get(dump_variable),
        .failures = &failures,
    };
    const workers = @max(1, budget.workers(.{ .programs = request.misses.len, .cores = std.Thread.getCpuCount() catch 1, .free = budget.available(context.io), .ceiling = 0 }));
    const threads = try a.alloc(?std.Thread, workers);
    @memset(threads, null);
    // A worker that cannot be started leaves its share to the others.
    for (threads[1..]) |*thread| thread.* = std.Thread.spawn(.{}, Pool.work, .{&pool}) catch null;
    pool.work();
    for (threads) |thread| if (thread) |started| started.join();
    if (failures.count.load(.monotonic) != 0) return failures.report(context);
    const objects = try a.alloc(cache_api.Object, request.misses.len);
    for (request.misses, objects) |miss, *object| object.* = .{ .key = miss.key, .path = try std.fmt.allocPrint(a, "{s}/{s}.o", .{ request.cache.directory, miss.key }), .reused = false };
    return objects;
}

/// The runtime helper registry, read from the bundled runtime tree's
/// top-level headers and Zig sources in name order.
fn runtimeTable(allocator: Allocator) Error!llvm.RuntimeTable {
    var sources: std.ArrayList(llvm.RuntimeSource) = .empty;
    for (bundled.files) |file| {
        if (std.mem.indexOfScalar(u8, file.path, '/') != null) continue;
        try sources.append(allocator, .{ .name = file.path, .bytes = file.bytes });
    }
    std.mem.sort(llvm.RuntimeSource, sources.items, {}, struct {
        fn less(_: void, left: llvm.RuntimeSource, right: llvm.RuntimeSource) bool {
            return std.mem.lessThan(u8, left.name, right.name);
        }
    }.less);
    return llvm.RuntimeTable.read(allocator, sources.items) catch |err| return translationError(err);
}

fn translationError(err: llvm.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.TranslationFailed => error.NativeToolFailed,
    };
}

/// The signatures every missed unit's call sites can consult: each miss's
/// own, and each unit of the closure a miss names by `$symbol`. A unit that
/// is only ever reused is never read.
fn closureSignatures(request: Request) Error!llvm.Signatures {
    const context = request.cache.context;
    const a = context.allocator;
    var units: std.StringHashMapUnmanaged(usize) = .empty;
    for (request.units, 0..) |unit, index| try units.put(a, v.text(v.get(unit, "symbol")), index);
    var table: llvm.Signatures = .empty;
    var needed: std.array_hash_map.String(void) = .empty;
    var scratch = std.heap.ArenaAllocator.init(context.parent);
    defer scratch.deinit();
    for (request.misses) |miss| {
        defer _ = scratch.reset(.retain_capacity);
        const text = try unitText(request, scratch.allocator(), miss.unit);
        try record(a, &table, try header(scratch.allocator(), text));
        var named: std.array_hash_map.String(void) = .empty;
        llvm.referencedSymbols(scratch.allocator(), text, &named) catch return error.OutOfMemory;
        for (named.keys()) |name| if (!needed.contains(name)) try needed.put(a, try a.dupe(u8, name), {});
    }
    for (needed.keys()) |name| {
        if (table.contains(name)) continue;
        const index = units.get(name) orelse continue;
        defer _ = scratch.reset(.retain_capacity);
        try record(a, &table, try header(scratch.allocator(), try unitText(request, scratch.allocator(), index)));
    }
    return table;
}

fn unitText(request: Request, allocator: Allocator, index: usize) Error![]const u8 {
    var reader = request.cache.context;
    reader.allocator = allocator;
    return lean.text(reader, request.store, request.units[index]) catch |err| switch (err) {
        error.InvalidNativeManifest => error.NativeToolFailed,
        else => |other| other,
    };
}

fn header(allocator: Allocator, text: []const u8) Error!llvm.Header {
    var diagnostic: llvm.Diagnostic = .{};
    return llvm.header(allocator, text, &diagnostic) catch |err| return translationError(err);
}

/// Copy one header's signature into the build's table.
fn record(allocator: Allocator, table: *llvm.Signatures, found: llvm.Header) Error!void {
    const parameters = try allocator.alloc([]const u8, found.signature.parameters.len);
    for (found.signature.parameters, parameters) |letter, *slot| slot.* = try allocator.dupe(u8, letter);
    const result = if (found.signature.result) |letter| try allocator.dupe(u8, letter) else null;
    try table.put(allocator, try allocator.dupe(u8, found.symbol), .{ .parameters = parameters, .result = result });
}

/// What to ask `zig cc -###` about: the driver flags placed before the input,
/// the input and output file names in a fresh work directory, and the front
/// end whose line is taken (`-cc1` for IR, `-cc1as` for assembly).
pub const Probe = struct {
    flags: []const []const u8,
    names: [2][]const u8,
    front: []const u8,
};

/// A clang front-end command as `zig cc` would run it, with the positions of
/// its input and output file to substitute for each file it is used on.
pub const Tool = struct {
    argv: []const []const u8,
    input: usize,
    output: usize,

    /// Ask `zig cc -###` which front-end command it would run for one file,
    /// so each later file costs one clang start and no driver.
    pub fn probe(cache: cache_api.Cache, asked: Probe) Error!Tool {
        const context = cache.context;
        const a = context.allocator;
        const work = try context.temporary(cache.temporary);
        defer context.remove(work);
        const input = try std.fs.path.join(a, &.{ work, asked.names[0] });
        const output = try std.fs.path.join(a, &.{ work, asked.names[1] });
        try context.write(input, "");
        var driver: std.ArrayList([]const u8) = .empty;
        try driver.appendSlice(a, &.{ cache.zig, "cc", "-###" });
        try driver.appendSlice(a, asked.flags);
        try driver.appendSlice(a, &.{ input, "-o", output });
        const result = try context.captureQuiet(driver.items);
        if (fs.exitCode(result.term) != 0) return probeFailed(context);
        const argv = (try commandLine(a, .{ .zig = cache.zig, .front = asked.front }, result.stderr)) orelse return probeFailed(context);
        const input_at = position(argv, input) orelse return probeFailed(context);
        const output_at = outputPosition(argv, output) orelse return probeFailed(context);
        return .{ .argv = argv, .input = input_at, .output = output_at };
    }

    /// The command for one file at `input`, writing `output`.
    pub fn command(self: *const Tool, allocator: Allocator, input: []const u8, output: []const u8) Error![]const []const u8 {
        const argv = try allocator.dupe([]const u8, self.argv);
        argv[self.input] = input;
        argv[self.output] = output;
        return argv;
    }
};

/// How one translated unit becomes an object: clang's `-cc1` command for the
/// build's flags, and whether its output is assembly to annotate and assemble.
const Compiler = struct {
    tool: Tool,
    /// Whether the command prints assembly the build annotates and assembles
    /// (no LTO), rather than emitting the bitcode object itself.
    assemble: bool,
    /// The file the unit's IR is written to, and the file clang writes.
    names: [2][]const u8,

    /// Ask `zig cc -###` which `-cc1` command it would run for one unit: full
    /// or thin bitcode under LTO, assembly without it.
    fn probe(cache: cache_api.Cache) Error!Compiler {
        const a = cache.context.allocator;
        const optimization = try std.fmt.allocPrint(a, "-O{s}", .{cache.codegen.optimization});
        if (cache.codegen.lto.flag()) |lto| {
            const names: [2][]const u8 = .{ "object.o.ll", "object.o" };
            const flags: []const []const u8 = &.{ "-c", lto, optimization, "-fPIC", "-g0" };
            return .{ .tool = try Tool.probe(cache, .{ .flags = flags, .names = names, .front = "-cc1" }), .assemble = false, .names = names };
        }
        const names: [2][]const u8 = .{ "unit.s.ll", "unit.s" };
        const flags: []const []const u8 = &.{ "-S", optimization, "-fPIC", "-g0" };
        return .{ .tool = try Tool.probe(cache, .{ .flags = flags, .names = names, .front = "-cc1" }), .assemble = true, .names = names };
    }
};

fn probeFailed(context: fs.Context) Error {
    try std.Io.File.stderr().writeStreamingAll(context.io, "mylang: Zig did not report the clang command for an LLVM unit\n");
    return error.NativeToolFailed;
}

fn position(argv: []const []const u8, wanted: []const u8) ?usize {
    for (argv, 0..) |argument, index| if (std.mem.eql(u8, argument, wanted)) return index;
    return null;
}

/// Where a front-end command names its output: the probe's own output path,
/// or else the argument after `-o`. For `-S` Zig's listing names `/dev/null`
/// there, because Zig collects the assembly itself; the `-cc1` command writes
/// it wherever that argument says.
pub fn outputPosition(argv: []const []const u8, output: []const u8) ?usize {
    if (position(argv, output)) |found| return found;
    const flag = position(argv, "-o") orelse return null;
    return if (flag + 1 < argv.len) flag + 1 else null;
}

/// Which line of a `-###` listing to take, and the Zig that runs it.
pub const Front = struct { zig: []const u8, front: []const u8 };

/// The line of a `-###` listing that runs the front end `wanted.front` (`-cc1`
/// or `-cc1as`), as `zig clang <front> ...`, or null.
pub fn commandLine(allocator: Allocator, wanted: Front, listing: []const u8) Error!?[]const []const u8 {
    const quoted = try std.fmt.allocPrint(allocator, "\"{s}\"", .{wanted.front});
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, quoted) == null) continue;
        const words = (try quotedWords(allocator, line)) orelse return null;
        if (words.len < 2 or !std.mem.eql(u8, words[1], wanted.front)) return null;
        const argv = try allocator.alloc([]const u8, words.len + 1);
        argv[0] = wanted.zig;
        argv[1] = "clang";
        @memcpy(argv[2..], words[1..]);
        return argv;
    }
    return null;
}

/// The double-quoted words of one `-###` line, with `\"` and `\\` unescaped.
fn quotedWords(allocator: Allocator, line: []const u8) Error!?[]const []const u8 {
    var words: std.ArrayList([]const u8) = .empty;
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, line, at, '"')) |open| {
        var word: std.ArrayList(u8) = .empty;
        var index = open + 1;
        while (index < line.len and line[index] != '"') : (index += 1) {
            if (line[index] == '\\' and index + 1 < line.len) index += 1;
            try word.append(allocator, line[index]);
        }
        if (index >= line.len) return null;
        try words.append(allocator, word.items);
        at = index + 1;
    }
    return words.items;
}

/// Why units failed to build, collected from every worker.
const Failures = struct {
    keep: Allocator,
    mutex: std.Io.Mutex = .init,
    list: std.ArrayList(Failure) = .empty,
    /// How many failures were added: a worker stops taking units once it is not zero.
    count: std.atomic.Value(usize) = .init(0),

    fn add(self: *Failures, io: std.Io, unit: usize, message: []const u8) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        _ = self.count.fetchAdd(1, .monotonic);
        const kept = self.keep.dupe(u8, message) catch "mylang: out of memory while reporting an LLVM unit failure\n";
        // A failure that cannot be listed still stops the build through `count`.
        self.list.append(self.keep, .{ .unit = unit, .message = kept }) catch return;
    }

    /// The failures in unit order, whatever order the workers met them in.
    fn ordered(self: *Failures) []const Failure {
        std.mem.sort(Failure, self.list.items, {}, struct {
            fn less(_: void, left: Failure, right: Failure) bool {
                return left.unit < right.unit;
            }
        }.less);
        return self.list.items;
    }

    /// Print every failure in unit order and return the build error.
    fn report(self: *Failures, context: fs.Context) Error {
        for (self.ordered()) |failure| try std.Io.File.stderr().writeStreamingAll(context.io, failure.message);
        return error.NativeToolFailed;
    }
};
const Failure = struct { unit: usize, message: []const u8 };

/// The shared queue the translation workers take missed units from.
const Pool = struct {
    request: *const Request,
    options: llvm.Options,
    compiler: *const Compiler,
    dump: ?[]const u8,
    failures: *Failures,
    next: std.atomic.Value(usize) = .init(0),

    /// Take units until none is left or one has failed. Each unit's
    /// translation, IR and tool scratch live in this worker's arena, which is
    /// reset after every unit.
    fn work(self: *Pool) void {
        const context = self.request.cache.context;
        var scratch = std.heap.ArenaAllocator.init(context.parent);
        defer scratch.deinit();
        while (self.failures.count.load(.monotonic) == 0) {
            const index = self.next.fetchAdd(1, .monotonic);
            if (index >= self.request.misses.len) return;
            defer _ = scratch.reset(.retain_capacity);
            const miss = self.request.misses[index];
            self.buildOne(scratch.allocator(), miss) catch |err| {
                const message = std.fmt.allocPrint(scratch.allocator(), "mylang: LLVM unit `{s}` failed: {s}\n", .{ symbolOf(self.request, miss), @errorName(err) }) catch "mylang: an LLVM unit failed\n";
                self.failures.add(context.io, miss.unit, message);
            };
        }
    }

    /// Translate one unit, compile it and publish its object.
    fn buildOne(self: *Pool, allocator: Allocator, miss: Miss) Error!void {
        var cache = self.request.cache;
        cache.context.allocator = allocator;
        const context = cache.context;
        const text = try unitText(self.request.*, allocator, miss.unit);
        var diagnostic: llvm.Diagnostic = .{ .unit = symbolOf(self.request, miss) };
        const translated = llvm.translate(allocator, text, self.options, &diagnostic) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.TranslationFailed => {
                self.failures.add(context.io, miss.unit, try std.fmt.allocPrint(allocator, "mylang: the LLVM backend refused {s}\n", .{diagnostic.message}));
                return;
            },
        };
        if (self.dump) |directory| try dumpUnit(context, .{ .directory = directory, .text = text, .translated = translated, .signatures = self.options.signatures });
        const staging = try context.temporary(cache.temporary);
        defer context.remove(staging);
        const input = try std.fs.path.join(allocator, &.{ staging, self.compiler.names[0] });
        const output = try std.fs.path.join(allocator, &.{ staging, self.compiler.names[1] });
        try context.write(input, translated);
        const finished = try spawn.run(allocator, .{ .argv = try self.compiler.tool.command(allocator, input, output) });
        if (fs.exitCode(finished.term) != 0) {
            self.failures.add(context.io, miss.unit, try std.fmt.allocPrint(allocator, "mylang: LLVM rejected the translated unit {s}:\n{s}\n", .{ diagnostic.unit, finished.stderr }));
            return;
        }
        const object = try std.fs.path.join(allocator, &.{ staging, "object.o" });
        if (self.compiler.assemble) {
            try cache.annotateAssembly(output);
            try context.command(&.{ cache.zig, "cc", "-g0", "-c", output, "-o", object }, null);
        }
        _ = try cache.keep(miss.key, object);
    }
};

fn symbolOf(request: *const Request, miss: Miss) []const u8 {
    return v.text(v.get(request.units[miss.unit], "symbol"));
}

/// One unit's dump: where it goes, its IL, its IR and the closure signatures.
const Dump = struct { directory: []const u8, text: []const u8, translated: []const u8, signatures: *const llvm.Signatures };

/// Write one unit's IL, IR and the closure signatures its text names, in the
/// adapter's sidecar format, for an equivalence check.
fn dumpUnit(context: fs.Context, dump: Dump) Error!void {
    const a = context.allocator;
    var diagnostic: llvm.Diagnostic = .{};
    const own = llvm.header(a, dump.text, &diagnostic) catch |err| return translationError(err);
    var named: std.array_hash_map.String(void) = .empty;
    llvm.referencedSymbols(a, dump.text, &named) catch return error.OutOfMemory;
    try named.put(a, own.symbol, {});
    const sorted = try a.dupe([]const u8, named.keys());
    std.mem.sort([]const u8, sorted, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    var json: std.Io.Writer.Allocating = .init(a);
    var writer: std.json.Stringify = .{ .writer = &json.writer, .options = .{ .whitespace = .indent_1 } };
    writer.beginObject() catch return error.OutOfMemory;
    for (sorted) |name| {
        const signature = dump.signatures.get(name) orelse continue;
        writer.objectField(name) catch return error.OutOfMemory;
        writer.write(.{ .parameters = signature.parameters, .result = signature.result }) catch return error.OutOfMemory;
    }
    writer.endObject() catch return error.OutOfMemory;
    try context.mkdir(dump.directory);
    const stem = try std.fs.path.join(a, &.{ dump.directory, own.symbol });
    try context.write(try std.fmt.allocPrint(a, "{s}.ssa", .{stem}), dump.text);
    try context.write(try std.fmt.allocPrint(a, "{s}.ll", .{stem}), dump.translated);
    try context.write(try std.fmt.allocPrint(a, "{s}.sigs.json", .{stem}), json.written());
}

// spec: BUILD-BACKEND-3
test "failed LLVM units stop new work and are reported in unit order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var failures: Failures = .{ .keep = arena.allocator() };
    // Workers meet failures in any order; the count is what stops new work.
    failures.add(std.testing.io, 7, "mylang: unit 7\n");
    failures.add(std.testing.io, 2, "mylang: unit 2\n");
    try std.testing.expectEqual(@as(usize, 2), failures.count.load(.monotonic));
    const ordered = failures.ordered();
    try std.testing.expectEqual(@as(usize, 2), ordered[0].unit);
    try std.testing.expectEqualStrings("mylang: unit 7\n", ordered[1].message);
}
