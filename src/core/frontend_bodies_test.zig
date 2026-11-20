//! What a unit's computation can rely on from the front end (G2j): the names a module's bodies are stated under and the keys of its
//! functions do not move when an unrelated edit does, and the bodies of one module can be asked for without checking the rest.
const std = @import("std");
const language = @import("selka");
const frontend = @import("frontend.zig");
const shadow_rules = @import("frontend_shadow.zig");
const digest_rules = @import("engine/digest.zig");

const main_source =
    \\import model
    \\import other
    \\import shape
    \\
    \\
    \\func main() -> i64:
    \\    return model.answer() + other.helper() + shape.origin().x
    \\
;

const model_source =
    \\
    \\public record Point:
    \\    x: i64
    \\
    \\
    \\public func answer() -> i64:
    \\    return 42
    \\
    \\
    \\public func unused() -> i64:
    \\    return 1
    \\
;

const other_source =
    \\
    \\public func helper() -> i64:
    \\    const spare = 5
    \\    return 0
    \\
;

const shape_source =
    \\import model
    \\
    \\
    \\public func origin() -> model.Point:
    \\    return model.Point(x=0)
    \\
;

/// A project in a temporary directory with a work directory beside it, and the environment of a session that compares the engine's
/// answers with the front end's (so the `module-check` answers of the session can be read).
const Project = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    root: []const u8,
    work: []const u8,
    environment: std.process.Environ.Map,

    fn create(gpa: std.mem.Allocator) !*Project {
        const self = try gpa.create(Project);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        const real = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", gpa);
        defer gpa.free(real);
        try self.temporary.dir.createDirPath(std.testing.io, "project");
        self.root = try std.fmt.allocPrint(gpa, "{s}/project", .{real});
        errdefer gpa.free(self.root);
        self.work = try std.fmt.allocPrint(gpa, "{s}/work", .{real});
        errdefer gpa.free(self.work);
        self.environment = .init(gpa);
        errdefer self.environment.deinit();
        try self.environment.put(shadow_rules.switch_variable, "1");
        try self.environment.put(shadow_rules.decide_variable, "0");
        try self.write("main.selka", main_source);
        try self.write("model.selka", model_source);
        try self.write("other.selka", other_source);
        try self.write("shape.selka", shape_source);
        return self;
    }

    fn destroy(self: *Project) void {
        const gpa = self.gpa;
        self.environment.deinit();
        gpa.free(self.work);
        gpa.free(self.root);
        self.temporary.cleanup();
        gpa.destroy(self);
    }

    fn write(self: *Project, name: []const u8, text: []const u8) !void {
        const path = try std.fmt.allocPrint(self.gpa, "project/{s}", .{name});
        defer self.gpa.free(path);
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = text });
    }
};

fn admitsNothing(_: *const anyopaque, _: []const u8, _: [32]u8, _: [32]u8) bool {
    return false;
}

/// What every module of the project states about its bodies, as one text per module path: the parts of its `module-check` answer (the
/// name of each body and the digest of the key, region and dependency context it was checked under) and the stable key of each of its
/// functions. Allocated in `arena`.
fn bodyNames(project: *Project, arena: std.mem.Allocator) !std.array_hash_map.String([]const u8) {
    var session = frontend.Session.init(project.gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(project.gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    var report: std.ArrayList(u8) = .empty;
    _ = try session.check(arena, "main", &report);
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    var out: std.array_hash_map.String([]const u8) = .empty;
    var answers = shadow.answers.maps.check.iterator();
    while (answers.next()) |entry| {
        const argument = entry.key_ptr.*;
        const path = try arena.dupe(u8, argument[0..std.mem.indexOfScalar(u8, argument, 0).?]);
        var text: std.ArrayList(u8) = .empty;
        for (entry.value_ptr.parts) |part| try text.print(arena, "{s} {s}\n", .{ part.name, digest_rules.hex(part.digest) });
        const keys = (try language.module_records.decodeKeys(arena, entry.value_ptr.payload)) orelse return error.TestUnexpectedResult;
        for (keys.functions) |function| try text.print(arena, "key {s}\n", .{function.key});
        try out.put(arena, path, text.items);
    }
    return out;
}

/// Every module's names but those of `changed` are as they were.
fn expectOthersStayed(before: std.array_hash_map.String([]const u8), after: std.array_hash_map.String([]const u8), changed: []const u8) !void {
    try std.testing.expectEqual(before.count(), after.count());
    for (before.keys(), before.values()) |path, text| {
        if (std.mem.eql(u8, path, changed)) continue;
        try std.testing.expectEqualStrings(text, after.get(path) orelse return error.TestUnexpectedResult);
    }
}

fn countLines(text: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| count += @intFromBool(line.len != 0);
    return count;
}

/// Every line of `before` is a line of `after`, and `after` has `extra` more.
fn expectGrewBy(before: []const u8, after: []const u8, extra: usize) !void {
    var lines = std.mem.splitScalar(u8, before, '\n');
    while (lines.next()) |line| try std.testing.expect(line.len == 0 or std.mem.indexOf(u8, after, line) != null);
    try std.testing.expectEqual(countLines(before) + extra, countLines(after));
}

test "a function or a record added to another module leaves every other body's name, digest and function key as they were" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    const before = try bodyNames(project, a);
    try project.write("other.selka", other_source ++ "\npublic func extra() -> i64:\n    return 9\n");
    const function_added = try bodyNames(project, a);
    try expectOthersStayed(before, function_added, "other.selka");
    // The module that gained a function keeps the name and digest of the one it had, and has one more body and one more key.
    try expectGrewBy(before.get("other.selka").?, function_added.get("other.selka").?, 2);
    try project.write("other.selka", other_source ++ "\npublic record Pair:\n    left: i64\n    right: i64\n");
    const record_added = try bodyNames(project, a);
    try expectOthersStayed(before, record_added, "other.selka");
    try std.testing.expectEqualStrings(before.get("other.selka").?, record_added.get("other.selka").?);
}

test "a comment that shifts the lines of a module, or the order of the entry's imports, moves no body's name, digest or function key" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    const before = try bodyNames(project, a);
    try project.write("model.selka", "# a comment above everything\n# and another\n" ++ model_source);
    const shifted = try bodyNames(project, a);
    try expectOthersStayed(before, shifted, "");
    try project.write("model.selka", model_source);
    try project.write("main.selka", "import shape\nimport other\nimport model\n\n\nfunc main() -> i64:\n    return model.answer() + other.helper() + shape.origin().x\n");
    const reordered = try bodyNames(project, a);
    try expectOthersStayed(before, reordered, "");
}

test "a module added to the project, or one dropped from it, moves no other module's body names" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    const before = try bodyNames(project, a);
    try project.write("extra.selka", "\npublic func more() -> i64:\n    return 1\n");
    try project.write("other.selka", "import extra\n" ++ other_source);
    const added = try bodyNames(project, a);
    try std.testing.expectEqual(before.count() + 1, added.count());
    try std.testing.expectEqualStrings(before.get("model.selka").?, added.get("model.selka").?);
    try std.testing.expectEqualStrings(before.get("shape.selka").?, added.get("shape.selka").?);
    try std.testing.expectEqualStrings(before.get("main.selka").?, added.get("main.selka").?);
    try project.write("other.selka", other_source);
    const dropped = try bodyNames(project, a);
    try expectOthersStayed(before, dropped, "");
}

/// What one `checkBodiesOf` did: the bodies it left out of the check, the ones the cache checked, the ones it did not have to check
/// (restored from the store or left out), and the modules the engine took the keys of from a valid record.
const Asked = struct { omitted: usize, checked: usize, reused: usize, keys_served: u64, asks_model: bool, asks_other: bool };

/// Ask a fresh session of the project (the engine deciding) for the bodies of the modules at `paths`.
fn askFor(project: *Project, paths: []const []const u8) !Asked {
    var arena: std.heap.ArenaAllocator = .init(project.gpa);
    defer arena.deinit();
    try project.environment.put(shadow_rules.decide_variable, "1");
    // No sampling: a Debug compiler withholds one valid record in 64 by a hash of the module's query, which changes with the compiler's
    // identity, so a count of the records served would depend on which module the hash picks.
    try project.environment.put(shadow_rules.verify_variable, "0");
    var session = frontend.Session.init(project.gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(project.gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var report: std.ArrayList(u8) = .empty;
    const bodies = try session.checkBodiesOf(arena.allocator(), "main", paths, &report);
    const work = session.statistics();
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    return .{ .omitted = bodies.omitted, .checked = work.checked, .reused = work.reused, .keys_served = shadow.tally(.decide_served), .asks_model = session.asks("model"), .asks_other = session.asks("other") };
}

test "the bodies of one module can be asked for without checking the others: an unchanged project leaves the other modules out" {
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    // The first check has no summaries to stand in with: every body is checked, whoever is asked for.
    const cold = try askFor(project, &.{"model.selka"});
    try std.testing.expectEqual(@as(usize, 0), cold.omitted);
    try std.testing.expectEqual(@as(usize, 5), cold.checked);
    // Unchanged, no body is checked again: the asked module's two bodies and the entry's are restored, and the two bodies of the other
    // modules are left out (neither checked nor decoded); the engine served all four modules' keys from their records.
    const warm = try askFor(project, &.{"model.selka"});
    try std.testing.expectEqual(@as(usize, 2), warm.omitted);
    try std.testing.expectEqual(@as(usize, 0), warm.checked);
    try std.testing.expectEqual(@as(usize, 5), warm.reused);
    try std.testing.expectEqual(@as(u64, 4), warm.keys_served);
    // The session remembers whom it was asked for, so a pass can leave the rest alone as the body policy does.
    try std.testing.expect(warm.asks_model);
    try std.testing.expect(!warm.asks_other);
    // Asked for the two modules the entry's other callees live in, the bodies of `model` are the ones left out.
    const others = try askFor(project, &.{ "other.selka", "shape.selka" });
    try std.testing.expectEqual(@as(usize, 2), others.omitted);
    try std.testing.expectEqual(@as(usize, 0), others.checked);
    // Every ask of an unchanged project is served all four modules' keys, whoever it asks for.
    try std.testing.expectEqual(@as(u64, 4), others.keys_served);
}

test "a module changed since the last check is checked whoever is asked for, and the unchanged ones stay out" {
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    _ = try askFor(project, &.{"model.selka"});
    try project.write("other.selka", "\npublic func helper() -> i64:\n    const spare = 5\n    return 2\n");
    const changed = try askFor(project, &.{"model.selka"});
    // `other.helper` changed, so it is checked although `other` was not asked for; `shape.origin` is the one body left out.
    try std.testing.expectEqual(@as(usize, 1), changed.omitted);
    try std.testing.expectEqual(@as(usize, 1), changed.checked);
    try std.testing.expectEqual(@as(u64, 3), changed.keys_served);
}

test "a path that names no module of the program is refused with a message" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    var session = frontend.Session.init(project.gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(project.gpa, project.work);
    var report: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.SourceError, session.checkBodiesOf(arena.allocator(), "main", &.{"missing.selka"}, &report));
    try std.testing.expect(std.mem.indexOf(u8, report.items, "has no module at missing.selka") != null);
}
