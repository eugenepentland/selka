//! One `mylang-core build`: check, build the Core IR, compute facts (release),
//! emit LLVM IR and link. Every failure is rendered into `report`.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const build_ir = @import("build.zig");
const emit_llvm = @import("emit_llvm.zig");
const driver = @import("driver.zig");

/// What the command line asked for.
pub const Options = struct {
    zig: []const u8,
    output: []const u8 = "",
    release: bool = false,
    links: []const []const u8 = &.{},
    /// Also write the emitted LLVM IR here.
    emit_llvm: ?[]const u8 = null,
    cache: []const u8 = ".mylang-cache/core",
};

/// Why a build stopped after its report was written.
pub const Error = error{ SourceError, Unsupported, ToolFailed, WriteFailed, OutOfMemory };

/// Build `path` into `options.output`.
pub fn build(init: std.process.Init, path: []const u8, options: Options, report: *std.ArrayList(u8)) Error!u8 {
    const allocator = init.arena.allocator();
    const entry = frontend.entryOf(path);
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    const checked = session.checkFile(allocator, path, report) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.SourceError,
    };
    var refusal: build_ir.Refusal = .{};
    const module = build_ir.buildModule(allocator, checked.program, &refusal) catch |err| switch (err) {
        error.Unsupported => {
            const at = frontend.position(checked.src, .{ .start = refusal.span, .end = refusal.span });
            try report.print(allocator, "{s}:{d}:{d}: error[E_CORE_UNSUPPORTED]: the new core does not support {s} yet\n", .{ at.path, at.line, at.column, refusal.reason });
            return error.Unsupported;
        },
        else => |other| return other,
    };
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(init.io, path, allocator) catch path;
    const llvm = emit_llvm.emitModule(allocator, &module, .{
        .locator = .{ .context = &checked.src, .locate = locate },
        .source_path = absolute,
        .main_parameters = try mainParameters(allocator, checked.program),
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try report.print(allocator, "error[E_CORE_UNSUPPORTED]: LLVM emission failed: {s}\n", .{@errorName(err)});
            return error.Unsupported;
        },
    };
    if (options.emit_llvm) |where| std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = where, .data = llvm }) catch return error.WriteFailed;
    var digest: [8]u8 = undefined;
    std.crypto.hash.Blake3.hash(options.output, &digest, .{});
    const program = try std.fs.path.join(allocator, &.{ options.cache, try std.fmt.allocPrint(allocator, "{s}-{x}.ll", .{ std.fs.path.basename(options.output), digest }) });
    driver.link(allocator, init.io, init.environ_map, .{
        .zig = options.zig,
        .work = options.cache,
        .program = program,
        .output = options.output,
        .release = options.release,
        .links = options.links,
        .llvm = llvm,
    }, report) catch |err| return err;
    return 0;
}

fn locate(context: *const anyopaque, offset: u32) emit_llvm.Location {
    const src: *const language.source.Source = @ptrCast(@alignCast(context));
    const at = frontend.position(src.*, .{ .start = offset, .end = offset });
    return .{ .line = at.line, .column = at.column };
}

/// The names of `main`'s parameters, which pick stdout or stderr for a `Stream`.
fn mainParameters(allocator: std.mem.Allocator, program: language.typed.Program) std.mem.Allocator.Error![]const []const u8 {
    const main = program.functions[@backingInt(program.main)];
    const names = try allocator.alloc([]const u8, main.signature.parameter_count);
    for (names, main.scope.locals[0..names.len]) |*name, local| name.* = local.name;
    return names;
}
