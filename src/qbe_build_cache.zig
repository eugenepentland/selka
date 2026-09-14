//! Content-addressed native objects and direct assembler/compiler invocations.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
/// Cache and native tool failures.
pub const Error = fs.Error || error{EmptyNativeObject};
/// Native compilation tools and invocation-local runtime source directory.
pub const Cache = struct {
    context: fs.Context,
    directory: []const u8,
    temporary: []const u8,
    assets: []const u8,
    environment: []const u8,
    zig: []const u8,
    qbe: []const u8,
    mode: []const u8,
    /// Cache hits are accepted only when their independent checksum matches.
    pub fn object(self: Cache, kind: []const u8, input: []const u8, flavor: Flavor) Error!Object {
        const key = try self.identity(kind, input);
        const path = try self.entry(key, ".o");
        if (self.valid(path, try self.entry(key, ".digest"))) return .{ .key = key, .path = path, .reused = true };
        const work = try self.context.temporary(self.temporary);
        defer self.context.remove(work);
        const candidate = try std.fs.path.join(self.context.allocator, &.{ work, "object.o" });
        try self.compile(.{ .work = work, .candidate = candidate, .input = input, .flavor = flavor });
        return self.store(key, path, candidate);
    }
    /// Publish the fixed runtime translation units as one archive whose single
    /// member merges every unit. `zig build-obj` compiles all C sources in one
    /// process — a cold build pays one toolchain start, not one per unit — and a
    /// relocatable link preserves each unit's function and data sections, so the
    /// final `--gc-sections` link still drops runtime a program never reaches. The
    /// linker verifies one archive entry instead of every runtime object.
    pub fn library(self: Cache, kind: []const u8, sources: []const []const u8) Error!Object {
        const a = self.context.allocator;
        const key = try self.identity(kind, try std.mem.join(a, "\x00", sources));
        const path = try self.entry(key, ".a");
        if (self.valid(path, try self.entry(key, ".digest"))) return .{ .key = key, .path = path, .reused = true };
        const work = try self.context.temporary(self.temporary);
        defer self.context.remove(work);
        const merged = try std.fs.path.join(a, &.{ work, "runtime.o" });
        try self.mergeC(sources, merged);
        const candidate = try std.fs.path.join(a, &.{ work, "runtime.a" });
        try self.context.command(&.{ self.zig, "ar", "rcs", candidate, merged }, null);
        return self.store(key, path, candidate);
    }
    /// Compile every runtime C source into one relocatable object with a single
    /// `zig build-obj`, then leave the merge command to run it.
    fn mergeC(self: Cache, sources: []const []const u8, output: []const u8) Error!void {
        try self.context.command(try self.mergeCommand(sources, output), null);
    }
    /// The single-invocation `zig build-obj` command that merges the runtime units.
    /// Per-unit optimization, section splitting and path mapping match the loose
    /// `zig cc` path so the merged member links identically, and one process start
    /// replaces one per unit on a cold build.
    fn mergeCommand(self: Cache, sources: []const []const u8, output: []const u8) Error![]const []const u8 {
        const a = self.context.allocator;
        const zig_mode = if (std.mem.eql(u8, self.mode, "Debug")) "-ODebug" else "-OReleaseFast";
        const optimization = if (std.mem.eql(u8, self.mode, "Debug")) "-O0" else "-O2";
        const shared = try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-runtime", .{self.assets});
        const shared_debug = try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-runtime", .{self.assets});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{
            self.zig,          "build-obj",  "-fPIC",      "-lc",
            zig_mode,          "-I",         self.assets,  "-cflags",
            "-std=c11",        optimization, "-fno-ident", "-ffunction-sections",
            "-fdata-sections", shared,       shared_debug, "-fdebug-compilation-dir=mylang-runtime",
            "--",
        });
        for (sources) |source| try argv.append(a, try std.fs.path.join(a, &.{ self.assets, source }));
        try argv.append(a, try std.fmt.allocPrint(a, "-femit-bin={s}", .{output}));
        return argv.items;
    }
    fn identity(self: Cache, kind: []const u8, input: []const u8) Error![]const u8 {
        const encoded = try std.json.Stringify.valueAlloc(self.context.allocator, .{ self.environment, kind, input }, .{});
        return fs.hash(self.context.allocator, encoded);
    }
    fn entry(self: Cache, key: []const u8, extension: []const u8) Error![]const u8 {
        return std.fmt.allocPrint(self.context.allocator, "{s}/{s}{s}", .{ self.directory, key, extension });
    }
    fn store(self: Cache, key: []const u8, path: []const u8, candidate: []const u8) Error!Object {
        const bytes = try self.context.read(candidate);
        const digest = try objectDigest(self.context.allocator, bytes);
        try self.context.rename(candidate, path);
        try self.context.atomic(try self.entry(key, ".digest"), digest);
        return .{ .key = key, .path = path, .reused = false };
    }
    fn valid(self: Cache, path: []const u8, checksum: []const u8) bool {
        const expected = self.context.read(checksum) catch return false;
        const bytes = self.context.read(path) catch return false;
        if (bytes.len == 0) return false;
        const actual = fs.digest(self.context.allocator, bytes) catch return false;
        return std.mem.eql(u8, expected, actual);
    }
    fn compile(self: Cache, task: Task) Error!void {
        const a = self.context.allocator;
        switch (task.flavor) {
            .qbe => {
                const source = try std.fs.path.join(a, &.{ task.work, "unit.ssa" });
                const assembly = try std.fs.path.join(a, &.{ task.work, "unit.s" });
                try self.context.write(source, task.input);
                try self.context.command(&.{ self.qbe, "-t", "amd64_sysv", "-o", assembly, source }, null);
                try self.context.command(&.{ self.zig, "cc", "-c", assembly, "-o", task.candidate }, null);
            },
            .c_text => {
                const source = try std.fs.path.join(a, &.{ task.work, "unit.c" });
                try self.context.write(source, task.input);
                try self.compileC(source, task.candidate, null);
            },
            .zig_file => try self.context.command(&.{ self.zig, "build-obj", try std.fs.path.join(a, &.{ self.assets, task.input }), "-lc", "-fPIC", "-O", self.mode, try std.fmt.allocPrint(a, "-femit-bin={s}", .{task.candidate}) }, null),
        }
    }
    /// Fresh provider compilations use private Zig caches to observe external inputs.
    pub fn compileC(self: Cache, source: []const u8, output: []const u8, environment: ?*const std.process.Environ.Map) Error!void {
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(self.context.allocator, try self.flags());
        try args.appendSlice(self.context.allocator, &.{ "-c", source, "-o", output });
        try self.context.command(args.items, environment);
    }
    /// Common native flags keep generated output independent of private directory names.
    pub fn flags(self: Cache) Error![]const []const u8 {
        const a = self.context.allocator;
        const optimization = if (std.mem.eql(u8, self.mode, "Debug")) "-O0" else "-O2";
        const files = try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-qbe", .{self.temporary});
        const debug = try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-qbe", .{self.temporary});
        const shared = try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-runtime", .{self.assets});
        const shared_debug = try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-runtime", .{self.assets});
        return a.dupe([]const u8, &.{
            self.zig,     "cc",                                 "-std=c11",            optimization,
            "-fno-ident", "-fPIC",                              "-ffunction-sections", "-fdata-sections",
            files,        "-fdebug-compilation-dir=mylang-qbe", debug,                 shared,
            shared_debug, "-I",                                 self.assets,
        });
    }
};
/// Ways to lower an object without routing a guest function through C.
pub const Flavor = enum { qbe, c_text, zig_file };
/// One validated object-cache result.
pub const Object = struct { key: []const u8, path: []const u8, reused: bool };
const Task = struct { work: []const u8, candidate: []const u8, input: []const u8, flavor: Flavor };

fn objectDigest(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    if (bytes.len == 0) return error.EmptyNativeObject;
    return fs.digest(allocator, bytes);
}
test "empty native tool output cannot enter the object cache" {
    try std.testing.expectError(error.EmptyNativeObject, objectDigest(std.testing.allocator, ""));
}
// spec: QBE-RUNTIME-MERGE-1
test "the runtime units merge in one build-obj invocation naming every source" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .qbe = "/qbe", .mode = "ReleaseFast" };
    const argv = try cache.mergeCommand(&.{ "qbe_runtime.c", "native_heap.c" }, "/tmp/out.o");
    const joined = try std.mem.join(context.allocator, " ", argv);
    try std.testing.expectEqualStrings("build-obj", argv[1]);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, joined, "build-obj"));
    try std.testing.expect(std.mem.indexOf(u8, joined, "/assets/qbe_runtime.c") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "/assets/native_heap.c") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-O2") != null);
    try std.testing.expectEqualStrings("-femit-bin=/tmp/out.o", argv[argv.len - 1]);
}
