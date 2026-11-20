//! Reuse construction of closed native test fixtures, never their executions.
//! The approved guest-tool closure and all depfile headers are checked before
//! reuse/publication. Executables are verified and copied to private run trees.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const objects = @import("unit_cache.zig");
const tools = @import("tool_identity.zig");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();
const Digest = objects.Digest;
const printDiagnostics = std.debug.print;
/// The compiler flags of a fixture that names none: optimized, with debug information.
pub const default_flags = [_][]const u8{ "-O2", "-g", "-std=c11", "-pthread" };

/// One closed C program: the runtime text and the source text written into `root`
/// under the names the source includes, the flags it is compiled with, and where
/// the binary goes. Everything the binary depends on is in this value, the tool
/// identity and the headers the depfile names.
pub const Program = struct {
    root: []const u8,
    binary: []const u8,
    runtime: []const u8,
    source: []const u8,
    runtime_name: []const u8 = "core_rt_all.c",
    source_name: []const u8 = "fixture.c",
    flags: []const []const u8 = &default_flags,
};

/// A reusable build accepts a self-contained source: the only file it includes by
/// quoted name is the runtime text written beside it, so the bytes the key covers
/// are every byte the compiler reads outside the toolchain's own headers (which the
/// depfile check covers). A source that includes anything else compiles privately.
pub fn supported(source: []const u8, runtime_name: []const u8) bool {
    if (std.mem.indexOf(u8, source, "#include_next") != null or std.mem.indexOf(u8, source, "#embed") != null) return false;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const text = std.mem.trimStart(u8, line, " \t");
        if (!std.mem.startsWith(u8, text, "#")) continue;
        const directive = std.mem.trimStart(u8, text[1..], " \t");
        if (!std.mem.startsWith(u8, directive, "include")) continue;
        const operand = std.mem.trimStart(u8, directive["include".len..], " \t");
        if (operand.len == 0 or operand[0] == '<') continue;
        if (operand[0] != '"') return false;
        const close = std.mem.indexOfScalarPos(u8, operand, 1, '"') orelse return false;
        if (!std.mem.eql(u8, operand[1..close], runtime_name)) return false;
    }
    return true;
}

/// Bind the complete generated C bytes, their names, the flags, instrumentation, tool and target.
pub fn key(program: Program, tool: tools.Identity, sanitized: bool, epoch: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    for ([_][]const u8{ "native-fixture-v2", program.runtime_name, program.runtime, program.source_name, program.source, &tool.digest, &tool.native_target, epoch }) |part| objects.field(&hash, part);
    var count: [8]u8 = undefined;
    std.mem.writeInt(u64, &count, program.flags.len, .little);
    objects.field(&hash, &count);
    for (program.flags) |flag| objects.field(&hash, flag);
    objects.field(&hash, "-ffile-prefix-map=PRIVATE=.");
    objects.field(&hash, if (sanitized) "-fsanitize=thread" else "unsanitized");
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}

fn binaryKey(input: Digest, dependencies: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    objects.field(&hash, &input);
    objects.field(&hash, dependencies);
    var result: Digest = undefined;
    hash.final(&result);
    return result;
}

fn copyVerified(a: std.mem.Allocator, from: objects.Found, to: []const u8) !bool {
    const bytes = cwd.readFileAlloc(io, from.path, a, .limited(64 << 20)) catch return false;
    var digest: Digest = undefined;
    fast_blake3.hash(bytes, &digest);
    if (!std.mem.eql(u8, &digest, &from.digest)) return false;
    try cwd.writeFile(io, .{ .sub_path = to, .data = bytes });
    try cwd.setFilePermissions(io, to, .executable_file, .{});
    return true;
}

fn restore(a: std.mem.Allocator, store: objects.Store, input: Digest, binary: []const u8) !bool {
    const manifest = try store.lookup(a, io, input, ".deps") orelse return false;
    const bytes = cwd.readFileAlloc(io, manifest.path, a, .limited(2 << 20)) catch return false;
    var digest: Digest = undefined;
    fast_blake3.hash(bytes, &digest);
    if (!std.mem.eql(u8, &digest, &manifest.digest)) return false;
    const parsed = std.json.parseFromSlice([]objects.Dependency, a, bytes, .{}) catch return false;
    const dependencies = parsed.value;
    // Serialized stamps are never trusted to skip hashing a header.
    for (dependencies) |*dependency| dependency.stamp = null;
    if (!try objects.unchanged(a, io, dependencies)) return false;
    const found = try store.lookup(a, io, binaryKey(input, bytes), ".bin") orelse return false;
    if (!try copyVerified(a, found, binary)) return false;
    return objects.unchanged(a, io, dependencies);
}

fn headers(a: std.mem.Allocator, depfile: []const u8, program: Program, since: i96) !?[]const objects.Dependency {
    const bytes = try cwd.readFileAlloc(io, depfile, a, .limited(2 << 20));
    const inputs = try objects.depfileInputs(a, bytes);
    var result: std.ArrayList(objects.Dependency) = .empty;
    const source = try std.fs.path.join(a, &.{ program.root, program.source_name });
    const runtime = try std.fs.path.join(a, &.{ program.root, program.runtime_name });
    for (inputs) |path| {
        const absolute = try cwd.realPathFileAlloc(io, path, a);
        if (std.mem.eql(u8, absolute, source) or std.mem.eql(u8, absolute, runtime)) continue;
        const digest = try objects.fileDigest(a, io, absolute) orelse return null;
        const after = try cwd.statFile(io, absolute, .{});
        if (after.ctime.nanoseconds >= since or after.mtime.nanoseconds >= since) return null;
        try result.append(a, .{ .path = absolute, .digest = digest });
    }
    if (!try objects.unchanged(a, io, result.items)) return null;
    return result.items;
}

/// Compile or restore one binary; true means no C compiler process was started.
/// `directory` stores construction artifacts only. `root` and `binary` stay private.
pub fn build(a: std.mem.Allocator, environment: *std.process.Environ.Map, request: Request) Error!bool {
    return prepare(a, environment, request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        printDiagnostics("native fixture construction failed: {s}\n", .{@errorName(err)});
        return error.FixtureBuildFailed;
    };
}

/// Construction failures, including unstable inputs and failed C compilation.
pub const Error = error{ OutOfMemory, FixtureBuildFailed };
/// A closed fixture's immutable inputs and private output/cache placement.
pub const Request = struct {
    program: Program,
    sanitized: bool,
    directory: []const u8,
    reuse: bool,
};

fn removePartial(path: []const u8) void {
    cwd.deleteFile(io, path) catch return;
}

fn prepare(a: std.mem.Allocator, environment: *std.process.Environ.Map, request: Request) !bool {
    const program = request.program;
    const root = program.root;
    const binary = program.binary;
    const sanitized = request.sanitized;
    const directory = request.directory;
    const resources: tools.Request = .{ .arena = a, .io = io, .environment = environment, .executable = environment.get("ZIG") orelse "zig", .cache = directory };
    const tool = try tools.capture(resources);
    const eligible = request.reuse and supported(program.source, program.runtime_name) and tool.cacheable;
    const store: objects.Store = .{ .directory = directory };
    const input = key(program, tool, sanitized, environment.get("SOURCE_DATE_EPOCH") orelse "");
    var claim = if (eligible) try @import("selka").native_cache_work.Claim.acquire(a, io, directory, input) else null;
    defer if (claim) |*held| held.deinit();
    if (eligible and try restore(a, store, input, binary)) {
        if (!try tools.unchanged(resources, tool)) return error.SourceChanged;
        return true;
    }
    const source_path = try std.fs.path.join(a, &.{ root, program.source_name });
    const depfile = try std.fs.path.join(a, &.{ root, "fixture.d" });
    const marker = try std.fs.path.join(a, &.{ root, "compile-start" });
    try cwd.writeFile(io, .{ .sub_path = marker, .data = "" });
    const started = try cwd.statFile(io, marker, .{});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ tool.path, "cc" });
    try argv.appendSlice(a, program.flags);
    try argv.append(a, try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=.", .{root}));
    try argv.appendSlice(a, &.{ "-MD", "-MF", depfile, source_path, "-o", binary });
    if (sanitized) try argv.append(a, "-fsanitize=thread");
    if (!tool.cacheable) try environment.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(a, &.{ root, "zig-global" }));
    const built = try std.process.run(a, io, .{ .argv = argv.items, .environ_map = environment });
    try std.testing.expectEqualStrings("", built.stderr);
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    if (!try tools.unchanged(resources, tool)) return error.SourceChanged;
    if (!eligible) return false;
    const dependencies = try headers(a, depfile, program, started.ctime.nanoseconds) orelse return false;
    const manifest = try std.json.Stringify.valueAlloc(a, dependencies, .{});
    const artifact_key = binaryKey(input, manifest);
    const staged = try store.partial(a, io, artifact_key, ".bin");
    defer removePartial(staged);
    if (!try copyVerified(a, try objects.found(a, io, binary), staged)) return error.SourceChanged;
    _ = try store.publish(a, io, artifact_key, ".bin", staged);
    const staged_manifest = try store.partial(a, io, input, ".deps");
    defer removePartial(staged_manifest);
    try cwd.writeFile(io, .{ .sub_path = staged_manifest, .data = manifest });
    _ = try store.publish(a, io, input, ".deps", staged_manifest);
    return false;
}
