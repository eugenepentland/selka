//! Pins the opt-in friction log: record shape, path fidelity, privacy, and off
//! by default. The record shape is asserted field by field so a rename fails
//! here rather than silently changing what harvesters read.
const std = @import("std");
const t = std.testing;
const friction = @import("friction_log.zig");
const diagnostic = @import("diagnostic.zig");

/// The synthetic compiler digest every test writes, shaped like a real one.
const synthetic_sha = "2c2ed027cb810836101474ba91f929f0a710f6b34b9f19842eccd4bc659acd21";

/// A fixed build identity, so a record-shape failure names a stable value.
fn identity() friction.Compiler {
    return .{
        .compiler_sha256 = synthetic_sha,
        .zig_version = "0.17.0-dev.1683+5ceec001b",
        .architecture = "x86_64",
        .os = "linux",
        .abi = "gnu",
        .optimize = "Debug",
    };
}

/// Read a whole file as bytes.
fn readAll(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(t.io, path, allocator, .limited(1 << 20));
}

/// Copy the log's first line without its terminator.
fn firstLine(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const bytes = try readAll(allocator, path);
    defer allocator.free(bytes);
    const end = std.mem.indexOfScalar(u8, bytes, '\n') orelse bytes.len;
    return allocator.dupe(u8, bytes[0..end]);
}

/// Count the newline-terminated records in a log.
fn recordCount(allocator: std.mem.Allocator, path: []const u8) !usize {
    const bytes = try readAll(allocator, path);
    defer allocator.free(bytes);
    return std.mem.count(u8, bytes, "\n");
}

/// Count the newline-terminated records in a log, or zero when it is absent.
fn recordCountOrZero(allocator: std.mem.Allocator, path: []const u8) usize {
    return recordCount(allocator, path) catch 0;
}

/// Whether a readable regular file exists at `path`.
fn exists(path: []const u8) bool {
    const file = std.Io.Dir.cwd().openFile(t.io, path, .{}) catch return false;
    file.close(t.io);
    return true;
}

/// Require `object` to hold `name` as a string and return the value.
fn stringField(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.MissingField;
    if (std.meta.activeTag(value) != .string) return error.WrongFieldType;
    return value.string;
}

/// Require `object` to hold `name` as an integer and return the value.
fn integerField(object: std.json.ObjectMap, name: []const u8) !i64 {
    const value = object.get(name) orelse return error.MissingField;
    if (std.meta.activeTag(value) != .integer) return error.WrongFieldType;
    return value.integer;
}

/// Require `object` to hold `name` as an object and return the value.
fn objectField(object: std.json.ObjectMap, name: []const u8) !std.json.ObjectMap {
    const value = object.get(name) orelse return error.MissingField;
    if (std.meta.activeTag(value) != .object) return error.WrongFieldType;
    return value.object;
}

/// Require `object` to hold `name` as an array and return the value.
fn arrayField(object: std.json.ObjectMap, name: []const u8) !std.json.Array {
    const value = object.get(name) orelse return error.MissingField;
    if (std.meta.activeTag(value) != .array) return error.WrongFieldType;
    return value.array;
}

/// Require the element at `index` to be a JSON object and return it.
fn element(array: std.json.Array, index: usize) !std.json.ObjectMap {
    if (std.meta.activeTag(array.items[index]) != .object) return error.WrongFieldType;
    return array.items[index].object;
}

/// Assert that `text` does not contain `needle`, reporting the needle on failure.
fn expectAbsent(text: []const u8, needle: []const u8) !void {
    try t.expectEqual(@as(?usize, null), std.mem.indexOf(u8, text, needle));
}

// spec: FRICTION-LOG-2
test "friction record pins every JSON field name and type" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const log_path = try std.fs.path.join(t.allocator, &.{ root, "friction.jsonl" });
    defer t.allocator.free(log_path);
    var environ = std.process.Environ.Map.init(t.allocator);
    defer environ.deinit();
    const snapshot = try friction.snapshotHex(t.allocator, "func main() -> int:\n    return 0\n");
    defer t.allocator.free(snapshot);
    var recorder = friction.Recorder.init(t.allocator, t.io, &environ, .{
        .flag = log_path,
        .command = "check",
        .path = "sub/probe.my",
        .snapshot = snapshot,
        .compiler = identity(),
    }) orelse return error.RecorderRefused;
    defer recorder.deinit();
    recorder.addDiagnostic(.{
        .code = "E_ARITY",
        .severity = .err,
        .span = .{ .start = 12, .end = 15 },
        .message = "collection method argument count differs from its signature",
    });
    recorder.addDiagnostic(.{
        .code = "W_UNUSED_BINDING",
        .severity = .warning,
        .span = .{ .start = 40, .end = 42 },
        .message = "binding is never read",
    });
    recorder.finish(1, 3_450_000);
    const line = try firstLine(t.allocator, log_path);
    defer t.allocator.free(line);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, line, .{});
    defer parsed.deinit();
    const record = parsed.value.object;
    try t.expectEqual(@as(usize, 7), record.count());
    try t.expectEqualStrings(friction.version, try stringField(record, "version"));
    const invocation = try objectField(record, "invocation");
    try t.expectEqual(@as(usize, 2), invocation.count());
    try t.expectEqualStrings("check", try stringField(invocation, "command"));
    try t.expectEqualStrings("sub/probe.my", try stringField(invocation, "path"));
    const compiler = try objectField(record, "compiler");
    try t.expectEqual(@as(usize, 6), compiler.count());
    try t.expectEqualStrings(synthetic_sha, try stringField(compiler, "compiler_sha256"));
    try t.expectEqualStrings("0.17.0-dev.1683+5ceec001b", try stringField(compiler, "zig_version"));
    try t.expectEqualStrings("x86_64", try stringField(compiler, "architecture"));
    try t.expectEqualStrings("linux", try stringField(compiler, "os"));
    try t.expectEqualStrings("gnu", try stringField(compiler, "abi"));
    try t.expectEqualStrings("Debug", try stringField(compiler, "optimize"));
    try t.expectEqualStrings(snapshot, try stringField(record, "snapshot"));
    const findings = try arrayField(record, "diagnostics");
    try t.expectEqual(@as(usize, 2), findings.items.len);
    const first = try element(findings, 0);
    try t.expectEqual(@as(usize, 4), first.count());
    try t.expectEqualStrings("E_ARITY", try stringField(first, "code"));
    try t.expectEqualStrings("error", try stringField(first, "severity"));
    try t.expectEqual(@as(i64, 12), try integerField(first, "start"));
    try t.expectEqual(@as(i64, 15), try integerField(first, "end"));
    const second = try element(findings, 1);
    try t.expectEqualStrings("W_UNUSED_BINDING", try stringField(second, "code"));
    try t.expectEqualStrings("warning", try stringField(second, "severity"));
    try t.expectEqual(@as(i64, 1), try integerField(record, "status"));
    try t.expectEqual(@as(i64, 3_450_000), try integerField(record, "wall_ns"));
    try t.expectEqual(@as(usize, 1), try recordCount(t.allocator, log_path));
}

// spec-case: FRICTION-LOG-2
test "friction record readers reject a renamed or retyped field" {
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, "{\"version\":7,\"invocation\":[]}", .{});
    defer parsed.deinit();
    const object = parsed.value.object;
    try t.expectError(error.WrongFieldType, stringField(object, "version"));
    try t.expectError(error.WrongFieldType, integerField(object, "invocation"));
    try t.expectError(error.WrongFieldType, objectField(object, "invocation"));
    try t.expectError(error.WrongFieldType, arrayField(object, "version"));
    try t.expectError(error.MissingField, stringField(object, "snapshot"));
    try t.expectError(error.MissingField, integerField(object, "status"));
    try t.expectError(error.MissingField, objectField(object, "compiler"));
    try t.expectError(error.MissingField, arrayField(object, "diagnostics"));
    var later = try std.json.parseFromSlice(std.json.Value, t.allocator, "{\"diagnostics\":[1]}", .{});
    defer later.deinit();
    const findings = try arrayField(later.value.object, "diagnostics");
    try t.expectError(error.WrongFieldType, element(findings, 0));
}

// spec-case: FRICTION-LOG-2
test "friction record keeps a relative source path relative" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(cwd);
    const relative = try std.fs.path.relative(t.allocator, cwd, null, cwd, root);
    defer t.allocator.free(relative);
    const relative_log = try std.fs.path.join(t.allocator, &.{ relative, "relative.jsonl" });
    defer t.allocator.free(relative_log);
    const absolute_log = try std.fs.path.join(t.allocator, &.{ root, "relative.jsonl" });
    defer t.allocator.free(absolute_log);
    var environ = std.process.Environ.Map.init(t.allocator);
    defer environ.deinit();
    try environ.put(friction.variable, absolute_log);
    var recorder = friction.Recorder.init(t.allocator, t.io, &environ, .{
        .flag = relative_log,
        .command = "run",
        .path = "sub/main.my",
        .snapshot = synthetic_sha,
        .compiler = identity(),
    }) orelse return error.RecorderRefused;
    defer recorder.deinit();
    recorder.finish(0, 7);
    const line = try firstLine(t.allocator, absolute_log);
    defer t.allocator.free(line);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, line, .{});
    defer parsed.deinit();
    const invocation = try objectField(parsed.value.object, "invocation");
    try t.expectEqualStrings("sub/main.my", try stringField(invocation, "path"));
    try t.expect(!std.fs.path.isAbsolute(try stringField(invocation, "path")));
    try t.expect(exists(absolute_log));
    try expectAbsent(line, root);
    try expectAbsent(line, cwd);
    try expectAbsent(line, relative_log);
}

// spec: FRICTION-LOG-1
test "friction log stays off until a flag or the environment asks for it" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const log_path = try std.fs.path.join(t.allocator, &.{ root, "off.jsonl" });
    defer t.allocator.free(log_path);
    var environ = std.process.Environ.Map.init(t.allocator);
    defer environ.deinit();
    const request: friction.Request = .{
        .flag = null,
        .command = "check",
        .path = "probe.my",
        .snapshot = synthetic_sha,
        .compiler = identity(),
    };
    try t.expect(friction.Recorder.init(t.allocator, t.io, &environ, request) == null);
    try t.expect(friction.destination(null, &environ) == null);
    try environ.put(friction.variable, "");
    try t.expect(friction.Recorder.init(t.allocator, t.io, &environ, request) == null);
    try t.expect(friction.destination(null, &environ) == null);
    try environ.put(friction.variable, log_path);
    try t.expectEqualStrings(log_path, friction.destination(null, &environ).?);
    try t.expectEqualStrings("--flag-wins.jsonl", friction.destination("--flag-wins.jsonl", &environ).?);
    try t.expectEqualStrings(log_path, friction.destination(log_path, &environ).?);
    try t.expect(!exists(log_path));
    try t.expectEqual(@as(usize, 0), recordCountOrZero(t.allocator, log_path));
}

// spec: FRICTION-LOG-3
test "friction record never carries source text or environment values" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const source_path = try std.fs.path.join(t.allocator, &.{ root, "sentinel.my" });
    defer t.allocator.free(source_path);
    const log_path = try std.fs.path.join(t.allocator, &.{ root, "privacy.jsonl" });
    defer t.allocator.free(log_path);
    const sentinel = "SENTINEL-DO-NOT-LOG-9137";
    const secret = "SENTINEL-ENVIRONMENT-VALUE-4207";
    const text = try std.fmt.allocPrint(t.allocator, "\n\nfunc main() -> int:\n    mut x = \"{s}\"\n    return 0\n", .{sentinel});
    defer t.allocator.free(text);
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = source_path, .data = text });
    const bytes = try readAll(t.allocator, source_path);
    defer t.allocator.free(bytes);
    const snapshot = try friction.snapshotHex(t.allocator, bytes);
    defer t.allocator.free(snapshot);
    var environ = std.process.Environ.Map.init(t.allocator);
    defer environ.deinit();
    try environ.put(friction.variable, log_path);
    try environ.put("MYLANG_TEST_SECRET", secret);
    var recorder = friction.Recorder.init(t.allocator, t.io, &environ, .{
        .flag = null,
        .command = "check",
        .path = "sentinel.my",
        .snapshot = snapshot,
        .compiler = identity(),
    }) orelse return error.RecorderRefused;
    defer recorder.deinit();
    const message = try std.fmt.allocPrint(t.allocator, "cannot use \"{s}\" here", .{sentinel});
    defer t.allocator.free(message);
    recorder.addDiagnostic(.{ .code = "E_TYPE", .severity = .err, .span = .{ .start = 34, .end = 38 }, .message = message });
    recorder.finish(1, 12);
    const line = try firstLine(t.allocator, log_path);
    defer t.allocator.free(line);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, line, .{});
    defer parsed.deinit();
    try t.expectEqual(@as(usize, 64), (try stringField(parsed.value.object, "snapshot")).len);
    try t.expectEqualStrings(snapshot, try stringField(parsed.value.object, "snapshot"));
    try expectAbsent(line, sentinel);
    try expectAbsent(line, secret);
    try expectAbsent(line, source_path);
    try expectAbsent(line, root);
    try expectAbsent(line, log_path);
    try expectAbsent(line, "cannot use");
    try t.expectEqual(@as(usize, 1), try recordCount(t.allocator, log_path));
}

// spec-case: FRICTION-LOG-3
test "friction record drops a diagnostic message that quotes source" {
    var temp = t.tmpDir(.{});
    defer temp.cleanup();
    const root = try temp.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const log_path = try std.fs.path.join(t.allocator, &.{ root, "messages.jsonl" });
    defer t.allocator.free(log_path);
    var environ = std.process.Environ.Map.init(t.allocator);
    defer environ.deinit();
    var recorder = friction.Recorder.init(t.allocator, t.io, &environ, .{
        .flag = log_path,
        .command = "lint",
        .path = "ported.my",
        .snapshot = synthetic_sha,
        .compiler = identity(),
    }) orelse return error.RecorderRefused;
    defer recorder.deinit();
    var item: diagnostic.Diagnostic = .{
        .code = "E_UNKNOWN_NAME",
        .span = .{ .start = 3, .end = 9 },
        .message = "name 'SENTINEL-DO-NOT-LOG-9137' is not declared",
        .related = .{ .span = .{ .start = 0, .end = 3 }, .message = "SENTINEL-DO-NOT-LOG-9137 declared here" },
    };
    recorder.addDiagnostic(item);
    item.severity = .warning;
    item.code = "W_UNUSED_BINDING";
    recorder.addDiagnostic(item);
    recorder.finish(0, 99);
    const line = try firstLine(t.allocator, log_path);
    defer t.allocator.free(line);
    var parsed = try std.json.parseFromSlice(std.json.Value, t.allocator, line, .{});
    defer parsed.deinit();
    try t.expectEqual(@as(usize, 2), (try arrayField(parsed.value.object, "diagnostics")).items.len);
    try expectAbsent(line, "SENTINEL-DO-NOT-LOG-9137");
    try expectAbsent(line, "declared here");
    try expectAbsent(line, "is not declared");
    try t.expect(std.mem.indexOf(u8, line, "\"E_UNKNOWN_NAME\"") != null);
    try t.expect(std.mem.indexOf(u8, line, "\"W_UNUSED_BINDING\"") != null);
}
