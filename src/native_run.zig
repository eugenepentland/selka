//! `mylang run` and `run-project`: build the checked program with the native
//! backend and execute it.
//!
//! The executable is published under the build cache by the identity of the QBE
//! units it was made from, so running an unchanged program spawns it instead of
//! rebuilding it, and `run` and `build` share one object cache. Guest standard
//! output and error pass straight through; the child's exit status is the
//! command's.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const builder = @import("qbe_build.zig");
const backend = @import("qbe_build_backend.zig");
const options = @import("qbe_build_options.zig");
const bundled = @import("qbe_build_assets");
const trap_detail = @import("native_trap_detail.zig");
/// Persistent checked-graph to emitted-manifest reuse used before lowering.
pub const manifest_cache = @import("native_run_cache.zig");

/// Native build, tool and child-process failures raised while running a program.
pub const Error = builder.Error;

/// One native run: the emitted units, and the build settings that also carry the
/// program's own arguments and its byte ceiling.
pub const Request = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    /// The `qbe-units-v1` manifest the frontend emitted for this program.
    manifest: []const u8,
    settings: options.Options = .{ .source = "", .run = true },
    /// `json` re-renders the runtime's trap text as `diagnostic-v1` records.
    diagnostics: Format = .text,
};

/// Terminal text, or one versioned JSON object per line on standard error.
pub const Format = enum { text, json };

/// Build the program when its units changed, then run it and return its exit status.
pub fn execute(allocator: std.mem.Allocator, request: Request) Error!u8 {
    var context = try fs.Context.init(allocator, request.io, request.environ);
    defer context.deinit();
    const path = try publish(context, request.settings, request.manifest);
    // Runtime options travel in `MYLANG_OPTIONS`; the program's argv is only
    // what followed `--` on this command line.
    const started = try builder.launch(context, path, request.settings.arguments, request.settings);
    var child = try std.process.spawn(context.io, .{
        .argv = started.argv,
        .environ_map = started.environ,
        .stderr = .pipe,
    });
    switch (request.diagnostics) {
        // Capture the whole stream so the structured record can be consumed and
        // re-rendered as `diagnostic-v1`. Standard output still streams through.
        .json => {
            var buffer: [4096]u8 = undefined;
            var reader = child.stderr.?.readerStreaming(context.io, &buffer);
            const captured = reader.interface.allocRemaining(context.allocator, .limited(4 * 1024 * 1024)) catch "";
            const outcome = builder.status(try child.wait(context.io));
            try translate(context, captured);
            return outcome;
        },
        // Stream line by line, dropping only the bounded machine record. The
        // human diagnostic text and its order are otherwise passed through.
        .text => {
            try filterText(context, &child);
            return builder.status(try child.wait(context.io));
        },
    }
}

/// Forward the child's stderr, omitting the one bounded trap-detail record line.
fn filterText(context: fs.Context, child: *std.process.Child) Error!void {
    var buffer: [65536]u8 = undefined;
    var reader = child.stderr.?.readerStreaming(context.io, &buffer);
    const stderr = std.Io.File.stderr();
    while (true) {
        const line = reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            // The bounded record never fills this buffer, so an oversized line is
            // ordinary output: forward the remainder unchanged.
            error.StreamTooLong => {
                const rest = reader.interface.allocRemaining(context.allocator, .limited(64 * 1024 * 1024)) catch break;
                try stderr.writeStreamingAll(context.io, rest);
                break;
            },
            error.ReadFailed => break,
        };
        if (std.mem.startsWith(u8, line, trap_detail.marker)) continue;
        try stderr.writeStreamingAll(context.io, line);
    }
}

/// One `path:line:column` locator the native runtime printed.
const Place = struct { path: []const u8, line: u64, column: u64 };

/// The `trap_detail` object. Optional numeric fields are omitted when absent, so
/// the JSON carries only values the runtime actually captured.
const JsonDetail = struct {
    version: u32,
    operation: []const u8,
    index: ?i64 = null,
    length: ?u64 = null,
    left: ?i128 = null,
    right: ?i128 = null,
    width: ?u64 = null,
};

/// Re-emit captured runtime diagnostics as `diagnostic-v1` JSON lines. Source
/// code, location and stack still come from the native text; numeric detail is
/// read from the bounded structured record rather than extracted from the
/// human message.
fn translate(context: fs.Context, text: []const u8) Error!void {
    const record = try renderJson(context, text) orelse return passthrough(context, text);
    try passthrough(context, try std.fmt.allocPrint(context.allocator, "{s}\n", .{record}));
}

/// Render one `diagnostic-v1` record, or null when `text` carries no located
/// guest trap the runtime can reinterpret.
fn renderJson(context: fs.Context, text: []const u8) Error!?[]u8 {
    var frames: std.ArrayList(struct { function: []const u8, location: Located }) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    const first = lines.first();
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "  in ")) continue;
        const split = std.mem.lastIndexOf(u8, line, " at ") orelse continue;
        const at = position(line[split + 4 ..]) orelse continue;
        try frames.append(context.allocator, .{ .function = line[5..split], .location = located(at) });
    }
    const marker = std.mem.indexOf(u8, first, ": error[") orelse return null;
    const rest = first[marker + 8 ..];
    const close = std.mem.indexOfScalar(u8, rest, ']') orelse return null;
    const at = position(first[0..marker]) orelse return null;
    const body = if (std.mem.indexOf(u8, rest[close..], "]: ")) |offset| rest[close + offset + 3 ..] else "native execution failed";
    const structured: ?JsonDetail = if (trap_detail.parse(context.allocator, text)) |value| .{
        .version = value.version,
        .operation = value.operation.name(),
        .index = if (value.has(trap_detail.present_index)) value.values.index else null,
        .length = if (value.has(trap_detail.present_length)) value.values.length else null,
        .left = if (value.has(trap_detail.present_left)) value.operand(value.values.left) else null,
        .right = if (value.has(trap_detail.present_right)) value.operand(value.values.right) else null,
        .width = if (value.has(trap_detail.present_width)) value.values.width else null,
    } else null;
    const code = rest[0..close];
    const record = try std.json.Stringify.valueAlloc(context.allocator, .{
        .version = "diagnostic-v1",
        .kind = "diagnostic",
        .diagnostic = .{
            .code = code,
            .severity = "error",
            .message = body,
            .location = located(at),
            .notes = &[_]u32{},
            .stack = .{ .frames = frames.items, .omitted = 0 },
            .trap_detail = structured,
            .contract = contractJson(context, code, text, if (frames.items.len > 1) frames.items[1].location else null),
        },
    }, .{ .emit_null_optional_fields = false });
    return record;
}

/// A violated contract's fields in a `diagnostic-v1` record; a broken
/// precondition also names its caller, the next frame out.
const ContractJson = struct {
    kind: []const u8,
    subject: []const u8,
    clause: []const u8,
    message: ?[]const u8 = null,
    caller: ?Located = null,
};

/// The `contract` object of one trap record, or null for any other trap.
fn contractJson(context: fs.Context, code: []const u8, text: []const u8, caller: ?Located) ?ContractJson {
    const found = trap_detail.contract(context.allocator, code, text) orelse return null;
    const requires = std.mem.eql(u8, found.kind, "requires");
    return .{ .kind = found.kind, .subject = found.subject, .clause = found.clause, .message = found.message, .caller = if (requires) caller else null };
}

/// The JSON location shape shared with source diagnostics; byte spans are the
/// frontend's, and the native runtime reports only lines and columns.
const Located = struct {
    path: []const u8,
    start: struct { line: u64, column: u64 },
    end: ?u8 = null,
    bytes: ?u8 = null,
};

fn located(at: Place) Located {
    return .{ .path = at.path, .start = .{ .line = at.line, .column = at.column } };
}

fn passthrough(context: fs.Context, text: []const u8) Error!void {
    if (text.len != 0) try std.Io.File.stderr().writeStreamingAll(context.io, text);
}

/// Split a trailing `path:line:column` locator, which paths may themselves contain colons.
fn position(text: []const u8) ?Place {
    const last = std.mem.lastIndexOfScalar(u8, text, ':') orelse return null;
    const previous = std.mem.lastIndexOfScalar(u8, text[0..last], ':') orelse return null;
    const line = std.fmt.parseInt(u64, text[previous + 1 .. last], 10) catch return null;
    const column = std.fmt.parseInt(u64, text[last + 1 ..], 10) catch return null;
    return .{ .path = text[0..previous], .line = line, .column = column };
}

/// Everything besides the program itself that decides an executable's bytes,
/// captured without running a tool: a warm run must not pay for a toolchain
/// probe it is about to skip. It names the native driver identity rather than the
/// whole compiler, matching the object cache: the program is already named by the
/// QBE units it was built from, so an unrelated compiler edit must not rebuild it.
fn buildEnvironment(context: fs.Context, settings: options.Options) Error![]const u8 {
    return std.json.Stringify.valueAlloc(context.allocator, .{
        .driver = bundled.driver_identity,
        .runtime = bundled.content_hash,
        .zig = try context.stamp(try context.executable(settings.zig)),
        .codegen = try codegenIdentity(context, settings),
        .mode = settings.mode,
        .target = settings.target,
    }, .{});
}

/// The run cache's view of the selected code generator. An explicit tool names
/// its own stamp, so a rebuilt one invalidates the program; an unnamed backend
/// is the QBE found beside the compiler or on `PATH` in either mode, and an
/// LLVM build names the built-in translator's identity (LLVM-ZIG-1), which the
/// object cache keys on too and which costs no file access at all.
fn codegenIdentity(context: fs.Context, settings: options.Options) Error![]const u8 {
    return switch (settings.codegen) {
        .qbe => |path| qbeIdentity(context, path),
        .llvm => |controls| llvmIdentity(context, controls, settings.mode),
        .auto => qbeIdentity(context, "qbe"),
    };
}

fn qbeIdentity(context: fs.Context, path: []const u8) Error![]const u8 {
    if (!backend.legacyLlvm(path)) {
        return std.json.Stringify.valueAlloc(context.allocator, .{ .backend = "qbe", .tool = try context.stamp(try context.executable(path)) }, .{});
    }
    return std.json.Stringify.valueAlloc(context.allocator, .{
        .backend = "llvm-legacy",
        .tool = backend.translatorIdentity(context.environ),
        .optimization = backend.legacyOptimization(context.environ) orelse "invalid",
        .lto = false,
    }, .{});
}

fn llvmIdentity(context: fs.Context, controls: options.Llvm, mode: []const u8) Error![]const u8 {
    return std.json.Stringify.valueAlloc(context.allocator, .{
        .backend = "llvm",
        .tool = backend.translatorIdentity(context.environ),
        .optimization = controls.optimization orelse if (std.mem.eql(u8, mode, "Debug")) "0" else "3",
        .lto = controls.lto,
    }, .{});
}

/// Name an executable by its build environment and the units it was made from.
fn identity(context: fs.Context, settings: options.Options, manifest: []const u8) Error![]const u8 {
    return fs.hash(context.allocator, try std.mem.concat(context.allocator, u8, &.{ try buildEnvironment(context, settings), manifest }));
}

/// The directory this compiler generation's programs live in: `run/<hash>` under
/// the cache root, named like the object cache's generations so a rebuilt
/// compiler evicts its predecessor's programs along with its objects. Naming the
/// directory costs no tool probe and creates nothing; only a cold build opens it.
fn home(context: fs.Context, settings: options.Options) Error![]const u8 {
    const root = try builder.cacheRoot(context, settings);
    return std.fs.path.join(context.allocator, &.{ root, "run", try fs.hash(context.allocator, builder.generation_identity) });
}

fn publish(context: fs.Context, settings: options.Options, manifest: []const u8) Error![]const u8 {
    const name = try identity(context, settings, manifest);
    const path = try std.fs.path.join(context.allocator, &.{ try home(context, settings), name });
    if (context.exists(path)) return path;
    const prepared = try builder.prepare(context, settings);
    defer context.remove(prepared.cache.temporary);
    // Opening this generation evicts every other generation's programs.
    const directory = try builder.generation(context, prepared.root, "run", builder.generation_identity);
    const document = try std.json.parseFromSlice(std.json.Value, context.allocator, manifest, .{ .allocate = .alloc_always });
    const published = try std.fs.path.join(context.allocator, &.{ directory, name });
    _ = try builder.assemble(prepared.cache, settings, document.value, published);
    return published;
}

test "a located runtime locator survives paths that carry colons" {
    const at = position("a:b/c.my:12:34").?;
    try std.testing.expectEqualStrings("a:b/c.my", at.path);
    try std.testing.expectEqual(@as(u64, 12), at.line);
    try std.testing.expectEqual(@as(u64, 34), at.column);
    try std.testing.expectEqual(@as(?Place, null), position("no location here"));
}

test "a run identity separates programs, toolchains and build modes" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const tool = try std.fs.path.join(context.allocator, &.{ root, "tool" });
    try context.write(tool, "#!/bin/sh\nexit 0\n");
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, tool, .executable_file, .{});
    // Pin both modes: the default is `ReleaseFast` now, so the test must name
    // the other mode rather than relying on the default being `Debug`.
    const settings: options.Options = .{ .source = "", .run = true, .zig = tool, .codegen = .{ .qbe = tool }, .mode = "Debug" };
    const first = try identity(context, settings, "{\"functions\":[]}");
    const second = try identity(context, settings, "{\"functions\":[1]}");
    var release = settings;
    release.mode = "ReleaseFast";
    try std.testing.expectEqual(@as(usize, 64), first.len);
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expect(!std.mem.eql(u8, first, try identity(context, release, "{\"functions\":[]}")));
    try std.testing.expectEqualStrings(first, try identity(context, settings, "{\"functions\":[]}"));
}

// spec-case: BUILD-BACKEND-2
test "run identity follows resolved QBE tools and effective LLVM settings" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const qbe = try std.fs.path.join(context.allocator, &.{ root, "qbe" });
    const zig = try std.fs.path.join(context.allocator, &.{ root, "zig" });
    try context.write(qbe, "#!/bin/sh\nexit 0\n");
    try context.write(zig, "#!/bin/sh\nexit 0\n");
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, qbe, .executable_file, .{});
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, zig, .executable_file, .{});
    try environment.put("PATH", root);
    context.self_directory = "";
    const debug: options.Options = .{ .source = "", .run = true, .zig = zig, .mode = "Debug" };
    // An unnamed backend is the same QBE in either mode; the mode keys the
    // program through its own field of the build environment.
    try std.testing.expectEqualStrings(try codegenIdentity(context, debug), try codegenIdentity(context, .{ .source = "", .run = true, .zig = zig, .mode = "ReleaseFast" }));
    const before = try context.allocator.dupe(u8, try codegenIdentity(context, debug));
    try context.write(qbe, "#!/bin/sh\nexit 22\n");
    const after = try codegenIdentity(context, debug);
    const llvm: options.Options = .{ .source = "", .run = true, .zig = zig, .codegen = .{ .llvm = .{ .optimization = "2" } } };
    var lto = llvm;
    lto.codegen.llvm.lto = .full;
    var optimize = llvm;
    optimize.codegen.llvm.optimization = "3";
    try std.testing.expect(!std.mem.eql(u8, before, after));
    try std.testing.expect(!std.mem.eql(u8, try codegenIdentity(context, llvm), try codegenIdentity(context, lto)));
    try std.testing.expect(!std.mem.eql(u8, try codegenIdentity(context, llvm), try codegenIdentity(context, optimize)));
}

// spec-case: QBE-GENERATION-1
test "run programs are published under one directory per compiler generation whatever the mode" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const cache = try std.fs.path.join(context.allocator, &.{ root, "cache" });
    const settings: options.Options = .{ .source = "", .run = true, .mode = "Debug", .cache = cache };
    const debug = try home(context, settings);
    var release = settings;
    release.mode = "ReleaseFast";
    const runs = try std.fs.path.join(context.allocator, &.{ cache, "run" });
    try std.testing.expectEqualStrings(runs, std.fs.path.dirname(debug).?);
    try std.testing.expectEqual(@as(usize, 64), std.fs.path.basename(debug).len);
    // Mode and tools stay in a program's own name, not in its generation, so
    // concurrent builds by one compiler never evict each other's programs.
    try std.testing.expectEqualStrings(debug, try home(context, release));
    try std.testing.expectEqualStrings(debug, try home(context, settings));
    // Naming a generation creates nothing: a warm run only looks for its program.
    try std.testing.expect(!context.exists(runs));
}

test "native JSON traps attach structured detail from the machine record" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const captured = "main.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 14, length 1)\n" ++
        "  in at at main.my:2:12\n" ++ trap_detail.marker ++ "{\"version\":1,\"operation\":\"index\",\"index\":14,\"length\":1}\n";
    const record = (try renderJson(context, captured)).?;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, record, .{});
    defer parsed.deinit();
    const diagnostic = parsed.value.object.get("diagnostic").?;
    try std.testing.expectEqualStrings("R_LIST_BOUNDS", diagnostic.object.get("code").?.string);
    const detail = diagnostic.object.get("trap_detail").?;
    try std.testing.expectEqualStrings("index", detail.object.get("operation").?.string);
    try std.testing.expectEqual(@as(i64, 14), detail.object.get("index").?.integer);
    try std.testing.expectEqual(@as(i64, 1), detail.object.get("length").?.integer);
    const frames = diagnostic.object.get("stack").?.object.get("frames").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), frames.len);
    try std.testing.expectEqualStrings("at", frames[0].object.get("function").?.string);
    // An absent numeric field is omitted, never serialized as zero.
    const without_index = (try renderJson(context, "main.my:3:12: error[R_LIST_BOUNDS]: native execution failed\n" ++ trap_detail.marker ++ "{\"version\":1,\"operation\":\"pop\",\"length\":0}\n")).?;
    var plain = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, without_index, .{});
    defer plain.deinit();
    const plain_detail = plain.value.object.get("diagnostic").?.object.get("trap_detail").?;
    try std.testing.expect(plain_detail.object.get("index") == null);
    try std.testing.expectEqual(@as(i64, 0), plain_detail.object.get("length").?.integer);
    // A runtime that emitted no record (or an older one) renders exactly the
    // pre-existing diagnostic shape: no trap_detail key at all.
    const legacy = (try renderJson(context, "main.my:2:12: error[R_LIST_BOUNDS]: native execution failed\n  in at at main.my:2:12\n")).?;
    var old = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, legacy, .{});
    defer old.deinit();
    try std.testing.expect(old.value.object.get("diagnostic").?.object.get("trap_detail") == null);
}
