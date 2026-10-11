//! Actual two-root commands qualify immutable compiler artifacts independently
//! of private replay indexes and the existing native object store.
const std = @import("std");
const t = std.testing;
const tools = @import("core_test_options");
const io = t.io;
const cwd = std.Io.Dir.cwd();
const diagnostic = std.debug.print;
const shared_variable = "MYLANG_COMPILER_SHARED_CACHE";
const epoch_variable = "SOURCE_DATE_EPOCH";
const single_source = "single.my";
const configuration_file = "mylang.json";
const syntax_hits = "syntax_hits";
const no_cache = "--no-cache";

const app = "import dep\nfunc main(out: Stream) -> int:\n    out.print(dep.value())\n    return 0\n";
const dependency = "public func value() -> int effects():\n    return 3\n";
const changed_dependency = "public func value() -> int effects():\n    return 4\n";
const configuration = "{\"version\":2,\"budgets\":{}}";

const Outcome = struct { status: u8, stdout: []const u8, stderr: []const u8, report: std.json.Value };
const Invocation = struct { project: []const u8, source: []const u8 = "app.my", extra: []const []const u8 = &.{} };

const Projects = struct {
    arena: std.mem.Allocator,
    root: []const u8,
    environment: std.process.Environ.Map,

    fn init(a: std.mem.Allocator, root: []const u8) !Projects {
        var environment = try t.environ.createMap(a);
        errdefer environment.deinit();
        _ = environment.swapRemove("MYLANG_TEST_SHARED_CACHE");
        _ = environment.swapRemove("MYLANG_FRONTEND_CACHE");
        _ = environment.swapRemove(epoch_variable);
        _ = environment.swapRemove("ZERO_AR_DATE");
        var projects: Projects = .{ .arena = a, .root = root, .environment = environment };
        try projects.environment.put(shared_variable, try projects.path(&.{"shared"}));
        try projects.environment.put("MYLANG_CORE_RUNTIME_CACHE", try projects.path(&.{"objects"}));
        try projects.write("a", "app.my", app);
        try projects.write("b", "app.my", app);
        try projects.write("a", "dep.my", dependency);
        try projects.write("b", "dep.my", dependency);
        try projects.write("a", configuration_file, configuration);
        try projects.write("b", configuration_file, configuration);
        return projects;
    }

    fn path(self: Projects, parts: []const []const u8) ![]const u8 {
        const all = try std.mem.concat(self.arena, []const u8, &.{ &.{self.root}, parts });
        return std.fs.path.join(self.arena, all);
    }

    fn write(self: Projects, project: []const u8, name: []const u8, bytes: []const u8) !void {
        const destination = try self.path(&.{ project, name });
        try cwd.createDirPath(io, std.fs.path.dirname(destination).?);
        try cwd.writeFile(io, .{ .sub_path = destination, .data = bytes });
    }

    fn reset(self: Projects, project: []const u8) !void {
        try cwd.deleteTree(io, try self.path(&.{ project, "private" }));
    }

    fn run(self: *const Projects, invocation: Invocation) !Outcome {
        const executable = try cwd.realPathFileAlloc(io, tools.core_path, self.arena);
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(self.arena, &.{ executable, "build", try self.path(&.{ invocation.project, invocation.source }), "-o", try self.path(&.{ invocation.project, "program" }) });
        try arguments.appendSlice(self.arena, &.{ "--cache-dir", try self.path(&.{ invocation.project, "private" }), "--report" });
        try arguments.appendSlice(self.arena, invocation.extra);
        const result = try std.process.run(self.arena, io, .{ .argv = arguments.items, .environ_map = &self.environment, .cwd = .{ .path = try self.path(&.{invocation.project}) } });
        return parse(self.arena, result);
    }

    fn again(self: *const Projects, invocation: Invocation) !Outcome {
        try self.reset(invocation.project);
        return self.run(invocation);
    }

    fn check(self: *const Projects, invocation: Invocation) !Outcome {
        const executable = try cwd.realPathFileAlloc(io, tools.core_path, self.arena);
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(self.arena, &.{ executable, "check-project", try self.path(&.{ invocation.project, invocation.source }) });
        const cache = try std.fmt.allocPrint(self.arena, "--cache-dir={s}", .{try self.path(&.{ invocation.project, "private" })});
        try arguments.appendSlice(self.arena, &.{ cache, "--report" });
        try arguments.appendSlice(self.arena, invocation.extra);
        const result = try std.process.run(self.arena, io, .{ .argv = arguments.items, .environ_map = &self.environment, .cwd = .{ .path = try self.path(&.{invocation.project}) } });
        return parse(self.arena, result);
    }

    fn native(self: *const Projects, project: []const u8) !Outcome {
        const result = try std.process.run(self.arena, io, .{ .argv = &.{try self.path(&.{ project, "program" })}, .environ_map = &self.environment, .cwd = .{ .path = try self.path(&.{project}) } });
        return parse(self.arena, result);
    }
};

fn parse(a: std.mem.Allocator, result: std.process.RunResult) !Outcome {
    var report: std.json.Value = .null;
    var lines = std.mem.splitScalar(u8, result.stderr, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "{\"version\":\"cache-report-v1\"") and !std.mem.startsWith(u8, line, "{\"version\":\"frontend-cache-v1\"")) continue;
        report = try std.json.parseFromSliceLeaky(std.json.Value, a, line, .{});
    }
    return .{ .status = switch (result.term) {
        .exited => |code| code,
        else => 255,
    }, .stdout = result.stdout, .stderr = result.stderr, .report = report };
}

fn field(value: std.json.Value, name: []const u8) !std.json.Value {
    if (value != .object) return error.BadCacheReport;
    return value.object.get(name) orelse error.BadCacheReport;
}

fn number(value: std.json.Value, name: []const u8) !i64 {
    const found = try field(value, name);
    if (found != .integer) return error.BadCacheReport;
    return found.integer;
}

fn built(result: Outcome) !void {
    errdefer diagnostic("shared compiler command: {s}{s}\n", .{ result.stdout, result.stderr });
    try t.expectEqual(@as(u8, 0), result.status);
    try t.expect(result.report == .object);
}

fn sharedProgram(result: Outcome) !void {
    try built(result);
    try t.expect((try field(result.report, "program_shared")).bool);
    try t.expectEqualStrings("reused", (try field(result.report, "program")).string);
    try t.expectEqual(@as(i64, 0), try number(result.report, "processes"));
    try t.expectEqual(@as(i64, 0), try number(result.report, "compiled"));
    try t.expect(try number(result.report, "units") > 0);
}

fn freshProgram(result: Outcome) !void {
    try built(result);
    try t.expect(!(try field(result.report, "program_shared")).bool);
}

fn output(projects: *const Projects, project: []const u8, expected: []const u8) !void {
    const result = try projects.native(project);
    try t.expectEqual(@as(u8, 0), result.status);
    try t.expectEqualStrings(expected, result.stdout);
    try t.expectEqualStrings("", result.stderr);
}

fn frontend(result: Outcome) !std.json.Value {
    return field(try field(result.report, "stages"), "frontend");
}

// spec: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts restore frontend bodies and linked programs across independent roots" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const cold = try projects.run(.{ .project = "a" });
    try freshProgram(cold);
    try t.expect(try number(try frontend(cold), "checked") > 0);
    const warm = try projects.run(.{ .project = "b" });
    try sharedProgram(warm);
    try t.expectEqual(@as(i64, 2), try number(try frontend(warm), syntax_hits));
    try t.expect(try number(try frontend(warm), "reused") > 0);
    try output(&projects, "b", "3\n");
    const emitted = try projects.again(.{ .project = "b", .extra = &.{ "--emit-llvm", try projects.path(&.{ "b", "module.ll" }) } });
    try sharedProgram(emitted);
    try t.expectEqual(@as(i64, 2), try number(try frontend(emitted), syntax_hits));
    try t.expect(try number(try frontend(emitted), "reused") > 0);
    try t.expectError(error.FileNotFound, cwd.access(io, try projects.path(&.{ "shared", "compiler-artifacts-v1", "invalidation" }), .{}));
    try t.expectError(error.FileNotFound, cwd.access(io, try projects.path(&.{ "shared", "compiler-artifacts-v1", "replay-v1" }), .{}));
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts follow dependency edits and recover an immutable reverted program" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try built(try projects.run(.{ .project = "a" }));
    try projects.write("b", "dep.my", changed_dependency);
    const edited = try projects.run(.{ .project = "b" });
    try freshProgram(edited);
    try t.expect(try number(try frontend(edited), "checked") > 0);
    try output(&projects, "b", "4\n");
    try projects.write("b", "dep.my", dependency);
    try sharedProgram(try projects.again(.{ .project = "b" }));
    try output(&projects, "b", "3\n");
}

fn controls(projects: *Projects) !void {
    try freshProgram(try projects.run(.{ .project = "b", .extra = &.{"--release"} }));
    try sharedProgram(try projects.again(.{ .project = "a", .extra = &.{"--release"} }));
    try projects.environment.put("MYLANG_CORE_LAYOUT", "4");
    try freshProgram(try projects.again(.{ .project = "b" }));
    _ = projects.environment.swapRemove("MYLANG_CORE_LAYOUT");
    try sharedProgram(try projects.again(.{ .project = "b" }));
    try projects.environment.put(epoch_variable, "946684800");
    try freshProgram(try projects.again(.{ .project = "b" }));
    _ = projects.environment.swapRemove(epoch_variable);
    try sharedProgram(try projects.again(.{ .project = "b" }));
    try projects.write("b", configuration_file, "{\"version\":2,\"budgets\":{\"max_file_bytes\":16}}");
    const limited = try projects.again(.{ .project = "b" });
    try t.expectEqual(@as(u8, 1), limited.status);
    try t.expect(std.mem.indexOf(u8, limited.stderr, "E_PROJECT_BYTES") != null);
    try projects.write("b", configuration_file, configuration);
    try sharedProgram(try projects.again(.{ .project = "b" }));
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts bind native mode environment and enforce fresh project configuration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    _ = projects.environment.swapRemove("MYLANG_CORE_LAYOUT");
    try built(try projects.run(.{ .project = "a" }));
    try controls(&projects);
    try t.expect(projects.environment.get("MYLANG_CORE_LAYOUT") == null);
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts invalidate same-size embedded bytes and preserve exact path literals" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const embedded = "public func value() -> int:\n    return int(embed_bytes(\"data.bin\")[0])\n";
    try projects.write("a", "dep.my", embedded);
    try projects.write("b", "dep.my", embedded);
    try projects.write("a", "data.bin", "x");
    try projects.write("b", "data.bin", "y");
    try built(try projects.run(.{ .project = "a" }));
    try freshProgram(try projects.run(.{ .project = "b" }));
    try output(&projects, "b", "121\n");
    try projects.write("b", "data.bin", "x");
    try sharedProgram(try projects.again(.{ .project = "b" }));
    try output(&projects, "b", "120\n");
    const left = try projects.path(&.{"a"});
    const right = try projects.path(&.{"b"});
    const literal = "public func value() -> int:\n    if \"{s}\" == \"{s}\":\n        return 1\n    return 0\n";
    try projects.write("a", "dep.my", try std.fmt.allocPrint(arena.allocator(), literal, .{ left, left }));
    try projects.write("b", "dep.my", try std.fmt.allocPrint(arena.allocator(), literal, .{ right, left }));
    try built(try projects.again(.{ .project = "a" }));
    try freshProgram(try projects.again(.{ .project = "b" }));
    try output(&projects, "b", "0\n");
}

fn diagnostics(projects: *Projects) !void {
    const trap = "func main() -> int:\n    return divtrunc(1, 0)\n";
    try projects.write("a", single_source, trap);
    try projects.write("b", single_source, trap);
    try built(try projects.run(.{ .project = "a", .source = single_source }));
    try freshProgram(try projects.run(.{ .project = "b", .source = single_source }));
    const trapped = try projects.native("b");
    try t.expectEqual(@as(u8, 1), trapped.status);
    try t.expect(std.mem.indexOf(u8, trapped.stderr, try projects.path(&.{ "b", single_source })) != null);
    try t.expect(std.mem.indexOf(u8, trapped.stderr, try projects.path(&.{"a"})) == null);
    const broken = "func main() -> int:\n    return missing\n";
    try projects.write("a", single_source, broken);
    try projects.write("b", single_source, broken);
    const rejected_a = try projects.again(.{ .project = "a", .source = single_source });
    try t.expectEqual(@as(u8, 1), rejected_a.status);
    const rejected = try projects.again(.{ .project = "b", .source = single_source });
    try t.expectEqual(@as(u8, 1), rejected.status);
    try t.expect(std.mem.indexOf(u8, rejected.stderr, try projects.path(&.{ "b", single_source })) != null);
    try t.expect(std.mem.indexOf(u8, rejected.stderr, try projects.path(&.{"a"})) == null);
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts preserve receiving diagnostic and trap paths" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try diagnostics(&projects);
    try t.expect(projects.environment.get(shared_variable) != null);
}

fn damage(projects: Projects, tier: []const u8) !void {
    var directory = try cwd.openDir(io, try projects.path(&.{ "shared", "compiler-artifacts-v1", tier }), .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    var count: usize = 0;
    while (try iterator.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".blob")) continue;
        const bytes = try directory.readFileAlloc(io, entry.name, projects.arena, .unlimited);
        try t.expect(bytes.len > 0);
        bytes[bytes.len - 1] ^= 0xff;
        try directory.writeFile(io, .{ .sub_path = entry.name, .data = bytes });
        count += 1;
    }
    try t.expect(count > 0);
    try directory.writeFile(io, .{ .sub_path = "abandoned.tmp", .data = "partial publication" });
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts reject corruption and partial publication before verified refill" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try built(try projects.run(.{ .project = "a" }));
    try damage(projects, "syntax");
    try damage(projects, "typed");
    try damage(projects, "program");
    const recovered = try projects.run(.{ .project = "b" });
    try freshProgram(recovered);
    try t.expectEqual(@as(i64, 2), try number(try frontend(recovered), "syntax_misses"));
    try t.expect(try number(try frontend(recovered), "checked") > 0);
    try output(&projects, "b", "3\n");
    try sharedProgram(try projects.again(.{ .project = "b" }));
    try output(&projects, "b", "3\n");
}

fn suppression(projects: *Projects) !void {
    const uncached = try projects.run(.{ .project = "b", .extra = &.{no_cache} });
    try freshProgram(uncached);
    try t.expectEqual(@as(i64, 0), try number(try frontend(uncached), syntax_hits));
    try t.expectEqual(@as(i64, 0), try number(try frontend(uncached), "reused"));
    const verified = try projects.again(.{ .project = "b", .extra = &.{"--verify-cache"} });
    try freshProgram(verified);
    try t.expectEqual(@as(i64, 0), try number(try frontend(verified), syntax_hits));
    try t.expectEqual(@as(i64, 0), try number(try frontend(verified), "reused"));
    _ = projects.environment.swapRemove(shared_variable);
    const disabled = try projects.again(.{ .project = "b" });
    try freshProgram(disabled);
    try t.expectEqual(@as(i64, 0), try number(try frontend(disabled), syntax_hits));
    try t.expectEqual(@as(i64, 0), try number(try frontend(disabled), "reused"));
    try projects.environment.put(shared_variable, try projects.path(&.{"unused"}));
    try built(try projects.again(.{ .project = "b", .extra = &.{no_cache} }));
    try t.expectError(error.FileNotFound, cwd.access(io, try projects.path(&.{"unused"}), .{}));
    try built(try projects.again(.{ .project = "b", .extra = &.{"--verify-cache"} }));
    try t.expectError(error.FileNotFound, cwd.access(io, try projects.path(&.{"unused"}), .{}));
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts honor opt out no-cache and verification suppression" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try built(try projects.run(.{ .project = "a" }));
    try suppression(&projects);
    try t.expect(projects.environment.get(shared_variable) != null);
}

const Publisher = struct {
    projects: Projects,
    project: []const u8,
    storage: std.heap.ArenaAllocator,
    result: ?Outcome = null,
    failure: ?anyerror = null,

    fn start(self: *Publisher) void {
        self.projects.arena = self.storage.allocator();
        self.result = self.projects.run(.{ .project = self.project }) catch |err| {
            self.failure = err;
            return;
        };
    }
};

fn concurrent(projects: Projects, backing: std.mem.Allocator) !void {
    var left: Publisher = .{ .projects = projects, .project = "a", .storage = std.heap.ArenaAllocator.init(backing) };
    defer left.storage.deinit();
    var right: Publisher = .{ .projects = projects, .project = "b", .storage = std.heap.ArenaAllocator.init(backing) };
    defer right.storage.deinit();
    const first = try std.Thread.spawn(.{}, Publisher.start, .{&left});
    const second = spawn: {
        errdefer first.join();
        break :spawn try std.Thread.spawn(.{}, Publisher.start, .{&right});
    };
    first.join();
    second.join();
    try t.expectEqual(@as(?anyerror, null), left.failure);
    try t.expectEqual(@as(?anyerror, null), right.failure);
    try built(left.result.?);
    try built(right.result.?);
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler artifacts accept concurrent publishers and remain Python free under an empty PATH" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    const empty_path = try projects.path(&.{"empty-path"});
    try cwd.createDirPath(io, empty_path);
    try projects.environment.put("PATH", empty_path);
    try t.expect(projects.environment.get("MYLANG_ZIG") != null);
    try concurrent(projects, std.heap.page_allocator);
    const warm = try projects.again(.{ .project = "b" });
    try sharedProgram(warm);
    try t.expectEqual(@as(i64, 2), try number(try frontend(warm), syntax_hits));
    try t.expect(try number(try frontend(warm), "reused") > 0);
    try output(&projects, "b", "3\n");
}

fn frontendCommands(projects: *Projects) !void {
    const cold = try projects.check(.{ .project = "a" });
    try built(cold);
    try t.expectEqual(@as(i64, 2), try number(cold.report, "syntax_misses"));
    const warm = try projects.check(.{ .project = "b" });
    try built(warm);
    try t.expectEqual(@as(i64, 2), try number(warm.report, syntax_hits));
    try t.expectEqual(@as(i64, 0), try number(warm.report, "verdict_hits"));
    const private = try projects.check(.{ .project = "b" });
    try built(private);
    try t.expectEqual(@as(i64, 1), try number(private.report, "verdict_hits"));
    const marker = "compiler-artifacts-v1/format";
    const marker_path = try projects.path(&.{ "shared", marker });
    const original = try cwd.readFileAlloc(io, marker_path, projects.arena, .limited(128));
    const invalid = "unknown compiler artifact format";
    try projects.write("shared", marker, invalid);
    const refused = try projects.check(.{ .project = "b" });
    try t.expectEqual(@as(u8, 2), refused.status);
    try t.expect(std.mem.indexOf(u8, refused.stderr, "shared compiler cache") != null);
    const bypassed = try projects.check(.{ .project = "b", .extra = &.{no_cache} });
    try t.expectEqual(@as(u8, 0), bypassed.status);
    try t.expect(bypassed.report == .null);
    try t.expectEqualStrings(invalid, try cwd.readFileAlloc(io, marker_path, projects.arena, .limited(128)));
    try projects.write("shared", marker, original);
    const invalid_dependency = "public func value() -> int effects():\n    return True\n";
    try projects.write("a", "dep.my", invalid_dependency);
    try projects.write("b", "dep.my", invalid_dependency);
    try projects.reset("a");
    try projects.reset("b");
    try t.expectEqual(@as(u8, 1), (try projects.check(.{ .project = "a" })).status);
    const rejected = try projects.check(.{ .project = "b" });
    try t.expectEqual(@as(u8, 1), rejected.status);
    try t.expect(std.mem.indexOf(u8, rejected.stderr, "dep.my") != null);
    try t.expect(std.mem.indexOf(u8, rejected.stderr, try projects.path(&.{"a"})) == null);
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared compiler frontend commands reuse syntax and reject format before private verdict replay" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var projects = try Projects.init(arena.allocator(), try temporary.dir.realPathFileAlloc(io, ".", arena.allocator()));
    defer projects.environment.deinit();
    try frontendCommands(&projects);
    try t.expect(projects.environment.get(shared_variable) != null);
}
