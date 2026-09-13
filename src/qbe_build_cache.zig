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
        const encoded = try std.json.Stringify.valueAlloc(self.context.allocator, .{ self.environment, kind, input }, .{});
        const key = try fs.hash(self.context.allocator, encoded);
        const path = try std.fmt.allocPrint(self.context.allocator, "{s}/{s}.o", .{ self.directory, key });
        const checksum = try std.fmt.allocPrint(self.context.allocator, "{s}/{s}.sha256", .{ self.directory, key });
        if (self.valid(path, checksum)) return .{ .key = key, .path = path, .reused = true };
        const work = try self.context.temporary(self.temporary);
        defer self.context.remove(work);
        const candidate = try std.fs.path.join(self.context.allocator, &.{ work, "object.o" });
        try self.compile(.{ .work = work, .candidate = candidate, .input = input, .flavor = flavor });
        const bytes = try self.context.read(candidate);
        const digest = try objectDigest(self.context.allocator, bytes);
        try self.context.rename(candidate, path);
        try self.context.atomic(checksum, digest);
        return .{ .key = key, .path = path, .reused = false };
    }
    fn valid(self: Cache, path: []const u8, checksum: []const u8) bool {
        const expected = self.context.read(checksum) catch return false;
        const bytes = self.context.read(path) catch return false;
        if (bytes.len == 0) return false;
        const actual = fs.hash(self.context.allocator, bytes) catch return false;
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
            .c_file => try self.compileC(try std.fs.path.join(a, &.{ self.assets, task.input }), task.candidate, null),
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
        return a.dupe([]const u8, &.{
            self.zig,                             "cc",  "-std=c11", optimization, "-fno-ident", "-fPIC",
            "-fdebug-compilation-dir=mylang-qbe", files, debug,      "-I",         self.assets,
        });
    }
};
/// Ways to lower an object without routing a guest function through C.
pub const Flavor = enum { qbe, c_text, c_file, zig_file };
/// One validated object-cache result.
pub const Object = struct { key: []const u8, path: []const u8, reused: bool };
const Task = struct { work: []const u8, candidate: []const u8, input: []const u8, flavor: Flavor };

fn objectDigest(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    if (bytes.len == 0) return error.EmptyNativeObject;
    return fs.hash(allocator, bytes);
}
test "empty native tool output cannot enter the object cache" {
    try std.testing.expectError(error.EmptyNativeObject, objectDigest(std.testing.allocator, ""));
}
