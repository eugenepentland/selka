//! JSON contracts shared by Juice commands; independent of collectors and hosts.
const std = @import("std");
/// Shared JSON field spelling for timeout seconds.
pub const key_timeout_seconds = "timeout_seconds";
/// Shared JSON field spelling for exit code.
pub const key_exit_code = "exit_code";
/// Shared JSON field spelling for functions.
pub const key_functions = "functions";
/// Shared JSON field spelling for instructions.
pub const key_instructions = "instructions";
/// Public Juice failures; host details are retained in the command diagnostic.
pub const Error = error{ OutOfMemory, InvalidExperiment, FileNotFound, NotDir };
/// Convert host/parser failures to a diagnosed experiment failure.
pub fn failure(c: ?*Context, err: anyerror) Error {
    switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return error.FileNotFound,
        error.NotDir => return error.NotDir,
        error.InvalidExperiment => return error.InvalidExperiment,
        else => {
            if (c) |ctx| {
                if (ctx.message.len == 0) ctx.message = @errorName(err);
            }
            return error.InvalidExperiment;
        },
    }
}
/// Dynamic versioned documents, preserving unknown explanatory fields.
pub const Value = std.json.Value;
/// Per-command arena and I/O, with a diagnostic for invalid experiments.
pub const Context = struct {
    a: std.mem.Allocator,
    io: std.Io,
    env: *const std.process.Environ.Map,
    self: []const u8,
    message: []const u8 = "",

    /// Diagnose an invalid experiment without producing a passing measurement.
    pub fn fail(c: *Context, message: []const u8) error{InvalidExperiment} {
        c.message = message;
        return error.InvalidExperiment;
    }
    /// Parse a bounded JSON document into the command's arena.
    pub fn parse(c: *Context, text: []const u8) Error!Value {
        return parseImpl(c, text) catch |err| failure(c, err);
    }
    fn parseImpl(c: *Context, text: []const u8) !Value {
        return (std.json.parseFromSlice(Value, c.a, text, .{ .allocate = .alloc_always }) catch return c.fail("invalid JSON document")).value;
    }
    /// Convert a typed literal to the common document representation.
    pub fn value(c: *Context, literal: anytype) Error!Value {
        return valueImpl(c, literal) catch |err| failure(c, err);
    }
    fn valueImpl(c: *Context, literal: anytype) !Value {
        return c.parse(try std.json.Stringify.valueAlloc(c.a, literal, .{}));
    }
    /// Read a document from disk; never interpret a missing record as zero work.
    pub fn read(c: *Context, path: []const u8) Error!Value {
        return readImpl(c, path) catch |err| failure(c, err);
    }
    fn readImpl(c: *Context, path: []const u8) !Value {
        return c.parse(try c.readBytes(path));
    }
    /// Read bounded artifact bytes.
    pub fn readBytes(c: *Context, path: []const u8) Error![]const u8 {
        return readBytesImpl(c, path) catch |err| failure(c, err);
    }
    fn readBytesImpl(c: *Context, path: []const u8) ![]const u8 {
        const stat = try std.Io.Dir.cwd().statFile(c.io, path, .{});
        if (stat.kind != .file) return c.fail("expected a regular file");
        var file = try std.Io.Dir.cwd().openFile(c.io, path, .{});
        defer file.close(c.io);
        var buffer: [65536]u8 = undefined;
        var reader = file.readerStreaming(c.io, &buffer);
        // procfs reports size zero; avoid file-size shortcuts in sendFile.
        reader.mode = .streaming_simple;
        return reader.interface.allocRemaining(c.a, .limited(256 << 20));
    }
    /// Join path components using the host's path convention.
    pub fn join(c: *Context, parts: []const []const u8) Error![]const u8 {
        return joinImpl(c, parts) catch |err| failure(c, err);
    }
    fn joinImpl(c: *Context, parts: []const []const u8) ![]const u8 {
        return std.fs.path.join(c.a, parts);
    }
    /// Create a directory and its missing parents.
    pub fn mkdir(c: *Context, path: []const u8) Error!void {
        return mkdirImpl(c, path) catch |err| failure(c, err);
    }
    fn mkdirImpl(c: *Context, path: []const u8) !void {
        try std.Io.Dir.cwd().createDirPath(c.io, path);
    }
    /// Replace a report atomically after writing its full contents.
    pub fn write(c: *Context, path: []const u8, document: Value) Error!void {
        return writeImpl(c, path, document) catch |err| failure(c, err);
    }
    fn writeImpl(c: *Context, path: []const u8, document: Value) !void {
        const bytes = try std.json.Stringify.valueAlloc(c.a, document, .{ .whitespace = .indent_2 });
        try c.writeBytes(path, try std.fmt.allocPrint(c.a, "{s}\n", .{bytes}));
    }
    /// Write through a sibling temporary file, then rename over the destination.
    pub fn writeBytes(c: *Context, path: []const u8, bytes: []const u8) Error!void {
        return writeBytesImpl(c, path, bytes) catch |err| failure(c, err);
    }
    fn writeBytesImpl(c: *Context, path: []const u8, bytes: []const u8) !void {
        try c.mkdir(std.fs.path.dirname(path) orelse ".");
        const temporary = try std.fmt.allocPrint(c.a, "{s}.tmp", .{path});
        try std.Io.Dir.cwd().writeFile(c.io, .{ .sub_path = temporary, .data = bytes });
        try std.Io.Dir.cwd().rename(temporary, .cwd(), path, c.io);
    }
    /// SHA-256 of a file, streaming rather than retaining large executables.
    pub fn fileHash(c: *Context, path: []const u8) Error!Value {
        return fileHashImpl(c, path) catch |err| failure(c, err);
    }
    fn fileHashImpl(c: *Context, path: []const u8) !Value {
        const stat = try std.Io.Dir.cwd().statFile(c.io, path, .{});
        if (stat.kind != .file) return c.fail("expected a regular file");
        var file = try std.Io.Dir.cwd().openFile(c.io, path, .{});
        defer file.close(c.io);
        var buffer: [65536]u8 = undefined;
        var reader = file.reader(c.io, &buffer);
        var sha = std.crypto.hash.sha2.Sha256.init(.{});
        while (true) {
            const bytes = reader.interface.peekGreedy(1) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            sha.update(bytes);
            reader.interface.toss(bytes.len);
        }
        return string(try c.a.dupe(u8, &std.fmt.bytesToHex(sha.finalResult(), .lower)));
    }
    /// Hash sorted JSON with an explicit native identity domain.
    pub fn hash(c: *Context, document: Value) Error!Value {
        return hashImpl(c, document) catch |err| failure(c, err);
    }
    fn hashImpl(c: *Context, document: Value) !Value {
        const sorted = try canonical(c, document);
        return c.hashBytes(try std.json.Stringify.valueAlloc(c.a, sorted, .{}));
    }
    /// SHA-256 for source and correctness bytes.
    pub fn hashBytes(c: *Context, bytes: []const u8) Error!Value {
        return hashBytesImpl(c, bytes) catch |err| failure(c, err);
    }
    fn hashBytesImpl(c: *Context, bytes: []const u8) !Value {
        var result: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &result, .{});
        return string(try c.a.dupe(u8, &std.fmt.bytesToHex(result, .lower)));
    }
};
/// An empty object, allocated lazily.
pub fn object() Value {
    return .{ .object = .empty };
}
/// An empty array, allocated lazily.
pub fn array(c: *Context) Value {
    return .{ .array = .init(c.a) };
}
/// A borrowed string for the lifetime of its command arena.
pub fn string(s: []const u8) Value {
    return .{ .string = s };
}
/// Return a string or fail instead of silently coercing another JSON type.
pub fn str(v: Value) Error![]const u8 {
    return strImpl(v) catch |err| failure(null, err);
}
fn strImpl(v: Value) ![]const u8 {
    return if (v == .string) v.string else error.InvalidExperiment;
}
/// Read an optional object member.
pub fn get(v: Value, key: []const u8) Value {
    return if (v == .object) v.object.get(key) orelse .null else .null;
}
/// Read a required object member.
pub fn req(v: Value, key: []const u8) Error!Value {
    return reqImpl(v, key) catch |err| failure(null, err);
}
fn reqImpl(v: Value, key: []const u8) !Value {
    const result = get(v, key);
    return if (result == .null) error.InvalidExperiment else result;
}
/// Read a finite number, retaining JSON's distinction between numbers and booleans.
pub fn num(v: Value) Error!f64 {
    return numImpl(v) catch |err| failure(null, err);
}
fn numImpl(v: Value) !f64 {
    const n: f64 = switch (v) {
        .integer => @floatFromInt(v.integer),
        .float => v.float,
        .number_string => try std.fmt.parseFloat(f64, v.number_string),
        else => return error.InvalidExperiment,
    };
    return if (std.math.isFinite(n)) n else error.InvalidExperiment;
}
/// Read an array without allowing missing or mistyped data.
pub fn items(v: Value) Error![]Value {
    return itemsImpl(v) catch |err| failure(null, err);
}
fn itemsImpl(v: Value) ![]Value {
    return if (v == .array) v.array.items else error.InvalidExperiment;
}
/// Append a member using the command arena, including objects initially empty.
pub fn put(c: *Context, v: *Value, key: []const u8, member: Value) Error!void {
    return putImpl(c, v, key, member) catch |err| failure(c, err);
}
fn putImpl(c: *Context, v: *Value, key: []const u8, member: Value) !void {
    if (v.* != .object) return c.fail("expected an object");
    try v.object.put(c.a, key, member);
}
/// Append an array item using the command arena.
pub fn add(c: *Context, v: *Value, member: Value) Error!void {
    return addImpl(c, v, member) catch |err| failure(c, err);
}
fn addImpl(c: *Context, v: *Value, member: Value) !void {
    if (v.* != .array) return c.fail("expected an array");
    v.array.allocator = c.a;
    try v.array.append(member);
}
/// Fill a default only when the member is absent.
pub fn default(c: *Context, v: *Value, key: []const u8, member: Value) Error!void {
    return defaultImpl(c, v, key, member) catch |err| failure(c, err);
}
fn defaultImpl(c: *Context, v: *Value, key: []const u8, member: Value) !void {
    if (get(v.*, key) == .null) try put(c, v, key, member);
}
/// Match a string exactly.
pub fn is(v: Value, text: []const u8) bool {
    return v == .string and std.mem.eql(u8, v.string, text);
}
/// Compare documents structurally, independent of object insertion order.
pub fn equal(a: Value, b: Value) bool {
    if (a == .integer or a == .float) return (num(a) catch return false) == (num(b) catch return false);
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => a.bool == b.bool,
        .string => std.mem.eql(u8, a.string, b.string),
        .number_string => std.mem.eql(u8, a.number_string, b.number_string),
        .array => blk: {
            if (a.array.items.len != b.array.items.len) break :blk false;
            for (a.array.items, b.array.items) |x, y| if (!equal(x, y)) break :blk false;
            break :blk true;
        },
        .object => blk: {
            if (a.object.count() != b.object.count()) break :blk false;
            var it = a.object.iterator();
            while (it.next()) |e| if (!equal(e.value_ptr.*, b.object.get(e.key_ptr.*) orelse break :blk false)) break :blk false;
            break :blk true;
        },
        else => false,
    };
}
/// Object keys in deterministic lexical order.
pub fn keys(c: *Context, v: Value) Error![][]const u8 {
    return keysImpl(c, v) catch |err| failure(c, err);
}
fn keysImpl(c: *Context, v: Value) ![][]const u8 {
    if (v != .object) return c.fail("expected an object");
    const result = try c.a.dupe([]const u8, v.object.keys());
    std.mem.sort([]const u8, result, {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return result;
}
fn canonical(c: *Context, v: Value) anyerror!Value {
    if (v == .object) {
        var result = object();
        for (try keys(c, v)) |k| try put(c, &result, k, try canonical(c, get(v, k)));
        return result;
    }
    if (v == .array) {
        var result = array(c);
        for (v.array.items) |x| try add(c, &result, try canonical(c, x));
        return result;
    }
    return v;
}
/// Copy an object without aliasing its member storage.
pub fn clone(c: *Context, v: Value) Error!Value {
    return cloneImpl(c, v) catch |err| failure(c, err);
}
fn cloneImpl(c: *Context, v: Value) !Value {
    var result = object();
    for (try keys(c, v)) |k| try put(c, &result, k, get(v, k));
    return result;
}
/// Positive finite quantities such as work units, timeouts and weights.
pub fn positive(v: Value) Error!f64 {
    return positiveImpl(v) catch |err| failure(null, err);
}
fn positiveImpl(v: Value) !f64 {
    const n = try num(v);
    return if (n > 0) n else error.InvalidExperiment;
}
/// Safe cache/record identifier.
pub fn identifier(s: []const u8) bool {
    if (s.len == 0 or s.len > 64 or !std.ascii.isAlphanumeric(s[0])) return false;
    for (s) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '-' and ch != '_') return false;
    return true;
}
/// Reject paths escaping a project or colliding with its root.
pub fn relative(s: []const u8) Error!void {
    return relativeImpl(s) catch |err| failure(null, err);
}
fn relativeImpl(s: []const u8) !void {
    if (s.len == 0 or std.fs.path.isAbsolute(s) or std.mem.eql(u8, s, ".")) return error.InvalidExperiment;
    var parts = std.mem.splitScalar(u8, s, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..")) return error.InvalidExperiment;
}
/// Expand only documented tokens, leaving unrelated application braces intact.
pub fn expand(c: *Context, argv: Value, values: Value) Error![][]const u8 {
    return expandImpl(c, argv, values) catch |err| failure(c, err);
}
fn expandImpl(c: *Context, argv: Value, values: Value) ![][]const u8 {
    const result = try c.a.alloc([]const u8, (try items(argv)).len);
    for (try items(argv), result) |arg, *out| {
        out.* = try str(arg);
        for (try keys(c, values)) |key| out.* = try std.mem.replaceOwned(u8, c.a, out.*, try std.fmt.allocPrint(c.a, "{{{s}}}", .{key}), try str(get(values, key)));
    }
    return result;
}
/// Median and observed repeat spread, not statistical confidence.
pub fn summary(c: *Context, values: []const f64) Error!Value {
    return summaryImpl(c, values) catch |err| failure(c, err);
}
fn summaryImpl(c: *Context, values: []const f64) !Value {
    if (values.len == 0) return c.fail("empty measurement series");
    const sorted = try c.a.dupe(f64, values);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const mid = sorted.len / 2;
    const median = if (sorted.len % 2 == 0) (sorted[mid - 1] + sorted[mid]) / 2 else sorted[mid];
    return c.value(.{ .samples = values, .median = median, .min = sorted[0], .max = sorted[sorted.len - 1], .spread = if (median > 0) (sorted[sorted.len - 1] - sorted[0]) / median else 0 });
}
