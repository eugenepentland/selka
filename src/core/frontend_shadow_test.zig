//! The engine's shadow of the front end (`frontend_shadow.zig`) over a project on disk: a cold project is computed, an
//! unchanged one is served, an edit recomputes what it touched and no more, an edit that leaves a module's import list alone
//! leaves the graph served, a stale record is found and healed, and a session turns the shadow on through the environment.
const std = @import("std");
const language = @import("selka");
const frontend = @import("frontend.zig");
const shadow_rules = @import("frontend_shadow.zig");
const record_rules = @import("engine/record.zig");
const context_rules = @import("engine/context.zig");
const check_facts = @import("module_check_facts.zig");
const digest_rules = @import("engine/digest.zig");
const build = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const stage = @import("stage_store.zig");
const emit_units = @import("emit_units.zig");
const facts_shadow = @import("program_facts_shadow.zig");
const optimizer_shadow = @import("optimizer_shadow.zig");
const optimization = @import("optimization_cache.zig");
const ir_snapshot = @import("ir_snapshot.zig");
const passes = @import("passes.zig");
const pipeline = @import("pipeline.zig");
const Tally = shadow_rules.Tally;

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

/// A project in a temporary directory, a work directory beside it, and the environment that turns the shadow on.
const Project = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    root: []const u8,
    work: []const u8,
    log: []const u8,
    environment: std.process.Environ.Map,
    /// The arguments of the units the last lowering observation described, for a test to name one (their demand digest is part of it).
    units: std.ArrayList([]u8) = .empty,

    fn create(gpa: std.mem.Allocator) !*Project {
        const self = try gpa.create(Project);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        self.units = .empty;
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        const real = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", gpa);
        defer gpa.free(real);
        try self.temporary.dir.createDirPath(std.testing.io, "project");
        self.root = try std.fmt.allocPrint(gpa, "{s}/project", .{real});
        errdefer gpa.free(self.root);
        self.work = try std.fmt.allocPrint(gpa, "{s}/work", .{real});
        errdefer gpa.free(self.work);
        self.log = try std.fmt.allocPrint(gpa, "{s}/shadow.jsonl", .{real});
        errdefer gpa.free(self.log);
        self.environment = .init(gpa);
        errdefer self.environment.deinit();
        try self.environment.put(shadow_rules.switch_variable, "1");
        // The comparison tests watch the engine beside the front end; the deciding tests turn the decision on themselves.
        try self.environment.put(shadow_rules.decide_variable, "0");
        try self.environment.put(shadow_rules.log_variable, self.log);
        try self.write("main.selka", main_source);
        try self.write("model.selka", model_source);
        try self.write("other.selka", other_source);
        try self.write("shape.selka", shape_source);
        return self;
    }

    fn destroy(self: *Project) void {
        const gpa = self.gpa;
        self.forgetUnits();
        self.units.deinit(gpa);
        self.environment.deinit();
        gpa.free(self.log);
        gpa.free(self.work);
        gpa.free(self.root);
        self.temporary.cleanup();
        gpa.destroy(self);
    }

    fn forgetUnits(self: *Project) void {
        for (self.units.items) |argument| self.gpa.free(argument);
        self.units.clearRetainingCapacity();
    }

    /// Remember the arguments of the units `shadow` described.
    fn rememberUnits(self: *Project, shadow: *const shadow_rules.Shadow) !void {
        self.forgetUnits();
        for (shadow.answers.units) |unit| try self.units.append(self.gpa, try self.gpa.dupe(u8, unit.argument));
    }

    /// The argument of the unit observed last whose argument starts with `prefix`.
    fn unitStartingWith(self: *const Project, prefix: []const u8) ![]const u8 {
        for (self.units.items) |argument| if (std.mem.startsWith(u8, argument, prefix)) return argument;
        return error.TestUnexpectedResult;
    }

    /// `model.selka` with the body of `answer` and the head of `unused` as given.
    fn writeModel(self: *Project, answer_body: []const u8, unused_head: []const u8) !void {
        const text = try std.fmt.allocPrint(self.gpa, "\n\npublic record Point:\n    x: i64\n\n\npublic func answer() -> i64:\n    {s}\n\n\n{s}\n    return 1\n", .{ answer_body, unused_head });
        defer self.gpa.free(text);
        try self.write("model.selka", text);
    }

    fn write(self: *Project, name: []const u8, text: []const u8) !void {
        const path = try std.fmt.allocPrint(self.gpa, "project/{s}", .{name});
        defer self.gpa.free(path);
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = text });
    }
};

/// What one observation counted.
const Counts = [std.enums.values(Tally).len]u64;

fn counted(counts: Counts, which: Tally) u64 {
    return counts[@backingInt(which)];
}

fn admitsNothing(_: *const anyopaque, _: []const u8, _: [32]u8, _: [32]u8) bool {
    return false;
}

/// Check the project as a session does, with a fresh shadow (a new process over the same work directory), and return the
/// counts. When `tamper` names a module, its `module-syntax` record is replaced first by one that is valid and says something
/// else.
fn observe(project: *Project, tamper: ?[]const u8) !Counts {
    const gpa = project.gpa;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    // A lowering host that admits no stored artifact: the check then publishes its summaries on every run, as a build does.
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    if (tamper) |path| try replaceRecord(shadow, path);
    var report: std.ArrayList(u8) = .empty;
    _ = try session.check(arena.allocator(), "main", &report);
    return shadow.sink.tallies;
}

/// Replace the stored `module-syntax` record of `path` with one whose parts say another thing and whose reads are the same.
fn replaceRecord(shadow: *shadow_rules.Shadow, path: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(shadow.machine.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = shadow.runner.registry.entries[0];
    const key = digest_rules.key(entry.kind.name, entry.kind.identity, path);
    const file = try shadow.runner.store.recordPath(a, entry.directory, key);
    const bytes = (try shadow.runner.store.load(a, file)) orelse return error.TestUnexpectedResult;
    var found = try record_rules.decode(a, bytes);
    const lies = try a.dupe(record_rules.Part, found.parts);
    lies[0].digest[0] ^= 1;
    found.parts = lies;
    try std.testing.expect(try shadow.runner.store.publish(a, file, try record_rules.encode(a, found)));
}

test "a cold project is computed and a project nobody touched is served, with nothing found" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const cold = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .modules));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .syntax_recomputed));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .interface_recomputed));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .check_recomputed));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .program_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .graph_recomputed));
    const warm = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .syntax_served));
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .interface_served));
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .check_served));
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .passes_served));
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .program_served));
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .graph_served));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .syntax_recomputed) + counted(warm, .graph_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .findings) + counted(warm, .errors));
}

test "an edit inside a body recomputes that module and leaves the other module and the graph served" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observe(project, null);
    try project.writeModel("return 43", "public func unused() -> i64:");
    const after = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(after, .syntax_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(after, .syntax_served));
    try std.testing.expectEqual(@as(u64, 1), counted(after, .graph_served));
    // The early cutoff: the module's syntax was recomputed, but no declaration's head moved, so every interface, the edited
    // module's and each importer's, is served.
    try std.testing.expectEqual(@as(u64, 4), counted(after, .interface_served));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .interface_recomputed));
    // The same cutoff one level up: the edited module's bodies are checked again, and `main`, whose body calls the function
    // that was edited, is not: the name it looks up has the digest it had.
    try std.testing.expectEqual(@as(u64, 1), counted(after, .check_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(after, .check_served));
    // And the passes: the edited module's are asked again (its body key moved), nobody else's.
    try std.testing.expectEqual(@as(u64, 1), counted(after, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(after, .passes_served));
    // The program's diagnostics are assembled from the modules' warnings, and the edited module's did not change: served.
    try std.testing.expectEqual(@as(u64, 1), counted(after, .program_served));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .findings));
}

test "a module's warnings are published by its passes in the module's own coordinates, and an edit that adds one recomputes that module's passes alone" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const project = try Project.create(gpa);
    defer project.destroy();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    var report: std.ArrayList(u8) = .empty;
    _ = try session.check(a, "main", &report);
    const shadow = session.caches.shadow.?;
    const state = &session.caches.frontend.?;
    const flags = try check_facts.flagsOf(a, &session.project, .{ .build = state.semantic.context.contract, .mutation = state.semantic.context.mutation_contract });
    const argument = try check_facts.argumentOf(a, "other.selka", flags);
    const published = try shadow.runner.answer(&shadow.kinds.passes, argument);
    try std.testing.expect(std.mem.indexOf(u8, try published.result.payload(), "warning warning W_UNUSED_BINDING") != null);
    try std.testing.expect(std.mem.indexOf(u8, try published.result.payload(), "other.selka") != null);
    try std.testing.expect(context_rules.findPart(published.result.parts, "warnings") != null);
    // Another unused binding is a second warning in the same module: that module's passes are asked again, the others' are not.
    try project.write("other.selka", "\npublic func helper() -> i64:\n    const spare = 5\n    const second = 6\n    return 0\n");
    const after = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(after, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(after, .passes_served));
    // A warning more is a different program output: the assembly is asked again.
    try std.testing.expectEqual(@as(u64, 1), counted(after, .program_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .findings));
}

test "a program that fails its check is never served from a record, and the record of the program that passed is untouched" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observe(project, null);
    // The call has one argument too many: the body check refuses the program, so nothing past the bodies runs.
    try project.write("main.selka", "import model\nimport other\nimport shape\n\n\nfunc main() -> i64:\n    return model.answer(1) + other.helper() + shape.origin().x\n");
    try std.testing.expectError(error.SourceError, observe(project, null));
    // Nothing the shadow asks about a passing program is asked about a failing one, so none of it can be served.
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var report: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.SourceError, session.check(arena.allocator(), "main", &report));
    const shadow = session.caches.shadow.?;
    try std.testing.expectEqual(@as(u64, 0), shadow.tally(.program_served) + shadow.tally(.program_recomputed) + shadow.tally(.program_memo));
    try std.testing.expectEqual(@as(u64, 0), shadow.tally(.passes_served) + shadow.tally(.check_served));
    try std.testing.expectEqual(@as(u64, 0), shadow.tally(.findings));
    // The program that passed is still what its record says: put it back and it is served.
    try project.write("main.selka", main_source);
    const restored = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(restored, .program_served));
    try std.testing.expectEqual(@as(u64, 0), counted(restored, .findings));
}

/// `other.selka` with a promise that reaches into `model.selka`: `helper` promises `@noalloc` and calls `model.unused`.
const promising_other =
    \\import model
    \\
    \\
    \\@noalloc
    \\public func helper() -> i64:
    \\    return model.unused() + 1
    \\
;

test "a module that promises no allocation is recorded by the passes, and the promise is a query of its own" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.write("other.selka", promising_other);
    const cold = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .noalloc_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .noalloc_unrecorded) + counted(cold, .passes_unrecorded) + counted(cold, .program_unrecorded));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .program_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(cold, .errors));
    const warm = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .noalloc_served));
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .passes_served));
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .program_served));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .findings) + counted(warm, .errors));
}

test "an edit to a callee of a promise asks the promise again, and the verdict not moving leaves the promising module served" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.write("other.selka", promising_other);
    _ = try observe(project, null);
    // The callee's body changes in another module: its check is asked again, so is the promise (the callee is in its closure), and the
    // promise still holds, so the module that declares it is served whole.
    try project.write("model.selka", "\n\npublic record Point:\n    x: i64\n\n\npublic func answer() -> i64:\n    return 42\n\n\npublic func unused() -> i64:\n    return 2\n");
    const callee = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(callee, .noalloc_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(callee, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(callee, .passes_served));
    try std.testing.expectEqual(@as(u64, 1), counted(callee, .program_served));
    try std.testing.expectEqual(@as(u64, 0), counted(callee, .findings) + counted(callee, .errors));
    // A body outside the closure (`answer` is called by `main`, not by the promise) leaves the promise served.
    try project.writeModel("return 43", "public func unused() -> i64:");
    try project.write("model.selka", "\n\npublic record Point:\n    x: i64\n\n\npublic func answer() -> i64:\n    return 43\n\n\npublic func unused() -> i64:\n    return 2\n");
    const outside = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(outside, .noalloc_served));
    try std.testing.expectEqual(@as(u64, 0), counted(outside, .noalloc_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(outside, .findings) + counted(outside, .errors));
}

/// `other.selka` with a generic function that promises `@noalloc`: judged where it is instantiated, which `main` does.
const generic_other =
    \\@noalloc
    \\public func keep[T: integer](a: T, b: T) -> T:
    \\    if a <= b:
    \\        return a
    \\    return b
    \\
    \\
    \\public func helper() -> i64:
    \\    return keep(3, 4)
    \\
;

test "a generic function that promises no allocation is judged where it is instantiated, and the program reads that promise" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.write("other.selka", generic_other);
    const cold = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .noalloc_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .noalloc_unrecorded) + counted(cold, .passes_unrecorded) + counted(cold, .program_unrecorded));
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .program_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(cold, .errors));
    const warm = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .noalloc_served));
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .passes_served));
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .program_served));
    // The generic function's body moves: the instance's promise is asked again and the module's passes with it.
    try project.write("other.selka", "@noalloc\npublic func keep[T: integer](a: T, b: T) -> T:\n    if a < b:\n        return a\n    return b\n\n\npublic func helper() -> i64:\n    return keep(3, 4)\n");
    const edited = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(edited, .noalloc_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(edited, .findings) + counted(edited, .errors));
}

test "an edit to an import list recomputes the graph" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observe(project, null);
    try project.write("extra.selka", "\n\npublic func more() -> i64:\n    return 1\n");
    try project.write("model.selka", "import extra\n\npublic record Point:\n    x: i64\n\n\npublic func answer() -> i64:\n    return extra.more() + 41\n\n\npublic func unused() -> i64:\n    return 1\n");
    const after = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 5), counted(after, .modules));
    try std.testing.expectEqual(@as(u64, 1), counted(after, .graph_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .findings));
}

test "an edit to a declaration nobody names recomputes its module's interface and no importer's" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observe(project, null);
    try project.writeModel("return 42", "public func unused(extra: i64) -> i64:");
    const after = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(after, .interface_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(after, .interface_served));
    try std.testing.expectEqual(@as(u64, 1), counted(after, .check_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .findings));
}

test "an edit to a declaration an importer's signature names recomputes the importer's interface and nobody else's" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observe(project, null);
    try project.write("model.selka", "\n\npublic record Point:\n    x: i64\n    y: i64 = 0\n\n\npublic func answer() -> i64:\n    return 42\n\n\npublic func unused() -> i64:\n    return 1\n");
    const after = try observe(project, null);
    // model changed and shape's signature names model.Point; main's signature names nothing of model's, and other imports nothing.
    try std.testing.expectEqual(@as(u64, 2), counted(after, .interface_recomputed));
    try std.testing.expectEqual(@as(u64, 2), counted(after, .interface_served));
    // The bodies that look the changed names up are checked again: model's own, shape's, and main's, which calls shape.origin,
    // whose digest covers the record it returns. `other` looks up nothing that moved.
    try std.testing.expectEqual(@as(u64, 3), counted(after, .check_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(after, .check_served));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .findings));
}

/// A module two entries share, whose function names a type (`Result[bytes, str]`, which `bytes.fromhex` answers) that only one
/// of the entries also names in a declaration.
const shared_source =
    \\public func parse(text: str) -> bytes fails str:
    \\    return try bytes.fromhex(text)
    \\
;

/// An entry that names no `Result[bytes, str]` of its own: the type is first met while `shared.parse` is checked.
const plain_entry_source =
    \\import shared
    \\
    \\
    \\func main() -> int:
    \\    match shared.parse("00ff"):
    \\        case Ok(data):
    \\            return len(data)
    \\        case Err(_):
    \\            return 9
    \\
;

/// An entry whose declaration names `Result[bytes, str]`: the type exists before any body is checked.
const naming_entry_source =
    \\import shared
    \\
    \\
    \\func size(value: Result[bytes, str]) -> int:
    \\    match value:
    \\        case Ok(data):
    \\            return len(data)
    \\        case Err(_):
    \\            return 9
    \\
    \\
    \\func main() -> int:
    \\    return size(shared.parse("00ff"))
    \\
;

/// What one entry's check counted, and whether the front end's stand-in store may use the summary of `shared.parse`.
const Entry = struct { counts: Counts, parse_stubbable: bool, parse_standable: bool };

/// Check the entry `name` of `project` as a session does, and read the stand-in flag of `parse` from the summaries the check made.
fn observeEntry(project: *Project, name: []const u8) !Entry {
    const gpa = project.gpa;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    var report: std.ArrayList(u8) = .empty;
    _ = try session.check(arena.allocator(), name, &report);
    const produced = session.caches.frontend.?.request.produced orelse return error.TestUnexpectedResult;
    for (produced.summaries) |summary| {
        if (std.mem.indexOf(u8, summary.key, "parse") == null) continue;
        return .{ .counts = session.caches.shadow.?.sink.tallies, .parse_stubbable = summary.stubbable, .parse_standable = summary.notes.complete };
    }
    return error.TestUnexpectedResult;
}

test "a module two entries share is one record when the entries differ in the types they name: the front end's stand-in flag is no conclusion of the passes" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.write("shared.selka", shared_source);
    try project.write("plain.selka", plain_entry_source);
    try project.write("naming.selka", naming_entry_source);
    const plain = try observeEntry(project, "plain");
    try std.testing.expectEqual(@as(u64, 2), counted(plain.counts, .passes_recomputed));
    // The type is interned while the body is checked; the summary names it by its recipe, so the body stands in whole all the same (G2m).
    try std.testing.expect(plain.parse_stubbable);
    const naming = try observeEntry(project, "naming");
    // Declared by the entry, the type exists before any body is checked: the same body stands in for the same reason.
    try std.testing.expect(naming.parse_stubbable);
    // The shared module's checks are this entry's too, and so are its passes: the record made under the other entry is served and
    // is exactly what this entry computes, so nothing is found. The entry's own module is the one query asked again.
    try std.testing.expectEqual(@as(u64, 1), counted(naming.counts, .interface_served));
    try std.testing.expectEqual(@as(u64, 1), counted(naming.counts, .check_served));
    try std.testing.expectEqual(@as(u64, 1), counted(naming.counts, .passes_served));
    try std.testing.expectEqual(@as(u64, 1), counted(naming.counts, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(naming.counts, .findings));
    const again = try observeEntry(project, "plain");
    try std.testing.expectEqual(@as(u64, 2), counted(again.counts, .passes_served));
    try std.testing.expectEqual(@as(u64, 0), counted(again.counts, .findings));
    // The module-local part of the stand-in decision does not depend on the entry: both entries make it, and the record published
    // under either is the one the other computes.
    try std.testing.expect(plain.parse_standable and naming.parse_standable and again.parse_standable);
}

const entry_library_source = "import lower\n\n\npublic func helper() -> int:\n    return lower.three()\n\n\nfunc main() -> int:\n    assert helper() == 3\n    return 0\n";
const entry_lower_source = "public func three() -> int:\n    return 3\n";
const entry_user_source = "import library\n\n\nfunc main() -> int:\n    return library.helper()\n";

/// The engine's tallies of a check of the project's entry `name`, in the work directory every call shares.
fn observeCounts(project: *Project, name: []const u8) !Counts {
    const gpa = project.gpa;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var report: std.ArrayList(u8) = .empty;
    _ = try session.check(arena.allocator(), name, &report);
    return session.caches.shadow.?.sink.tallies;
}

// F40: a module that is one program's entry and another's library holds its `main` as the entry point in the first and as an
// ordinary function in the second, and the passes state the difference (the stand-in flag of that function).
test "a module that is the entry of one program is another query when another program imports it" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.write("library.selka", entry_library_source);
    try project.write("lower.selka", entry_lower_source);
    try project.write("user.selka", entry_user_source);
    const as_entry = try observeCounts(project, "library");
    try std.testing.expectEqual(@as(u64, 2), counted(as_entry, .passes_recomputed));
    // The same module, imported: its `main` is no entry point, so the record made as the entry says another thing and is not served.
    const as_library = try observeCounts(project, "user");
    try std.testing.expectEqual(@as(u64, 0), counted(as_library, .findings));
    try std.testing.expectEqual(@as(u64, 2), counted(as_library, .passes_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(as_library, .passes_served));
    // Built again, each program finds nothing wrong with what it is served, whichever program published the module's record last.
    const again = try observeCounts(project, "library");
    try std.testing.expectEqual(@as(u64, 0), counted(again, .findings));
    const user_again = try observeCounts(project, "user");
    try std.testing.expectEqual(@as(u64, 0), counted(user_again, .findings));
}

test "the stand-in decision a record states is the one the front end makes, whichever entry made the record first" {
    const gpa = std.testing.allocator;
    const first = try Project.create(gpa);
    defer first.destroy();
    try first.write("shared.selka", shared_source);
    try first.write("plain.selka", plain_entry_source);
    try first.write("naming.selka", naming_entry_source);
    const one_plain = try observeEntry(first, "plain");
    const one_naming = try observeEntry(first, "naming");
    const second = try Project.create(gpa);
    defer second.destroy();
    try second.write("shared.selka", shared_source);
    try second.write("plain.selka", plain_entry_source);
    try second.write("naming.selka", naming_entry_source);
    const two_naming = try observeEntry(second, "naming");
    const two_plain = try observeEntry(second, "plain");
    // Whether the entry declares the type or the body interns it no longer decides the whole stand-in: it is the same for both entries
    // and in either order (G2m), as the part the record states is.
    try std.testing.expectEqual(one_plain.parse_stubbable, two_plain.parse_stubbable);
    try std.testing.expectEqual(one_naming.parse_stubbable, two_naming.parse_stubbable);
    try std.testing.expectEqual(one_plain.parse_stubbable, one_naming.parse_stubbable);
    try std.testing.expect(one_plain.parse_standable and one_naming.parse_standable and two_naming.parse_standable and two_plain.parse_standable);
    // The second entry of either order is served the module the first one recorded, with nothing found.
    try std.testing.expectEqual(@as(u64, 1), counted(one_naming.counts, .passes_served));
    try std.testing.expectEqual(@as(u64, 1), counted(two_plain.counts, .passes_served));
    try std.testing.expectEqual(@as(u64, 0), counted(one_naming.counts, .findings) + counted(two_plain.counts, .findings));
}

/// How many functions a summary stood in for in a warm check of the project's entry `main`.
fn standIns(project: *Project) !usize {
    var arena: std.heap.ArenaAllocator = .init(project.gpa);
    defer arena.deinit();
    var session = frontend.Session.init(project.gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(project.gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    var report: std.ArrayList(u8) = .empty;
    _ = try session.check(arena.allocator(), "main", &report);
    return session.statistics().summaries;
}

test "the passes decision is on unless the environment turns it off, and it is what lets a foreign declaration's passes stand in" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expect(shadow_rules.decidesPasses(&environment));
    try environment.put(shadow_rules.passes_variable, "off");
    try std.testing.expect(!shadow_rules.decidesPasses(&environment));
    try environment.put(shadow_rules.passes_variable, "0");
    try std.testing.expect(!shadow_rules.decidesPasses(&environment));
    try environment.put(shadow_rules.passes_variable, "1");
    try std.testing.expect(shadow_rules.decidesPasses(&environment));
    const project = try Project.create(std.testing.allocator);
    defer project.destroy();
    try project.write("other.selka", "\nextern func scale(host: Host, n: i64) -> i64\n\n\npublic func helper() -> i64:\n    return 2\n");
    // The first check has nothing to stand in with; the second stands in for the functions that can, and for the declaration's passes.
    _ = try standIns(project);
    const on = try standIns(project);
    try project.environment.put(shadow_rules.passes_variable, "0");
    const off = try standIns(project);
    try std.testing.expectEqual(on, off + 1);
}

test "a stale record is found, logged, and healed" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observe(project, null);
    const stale = try observe(project, "model.selka");
    try std.testing.expectEqual(@as(u64, 1), counted(stale, .findings));
    const healed = try observe(project, null);
    try std.testing.expectEqual(@as(u64, 0), counted(healed, .findings));
    try std.testing.expectEqual(@as(u64, 4), counted(healed, .syntax_served));
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, project.log, arena.allocator(), .limited(1 << 20));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "\"class\":\"compiler\""));
    try std.testing.expect(std.mem.indexOf(u8, text, "module-syntax model.selka") != null);
}

test "the comparison is off unless the environment turns it on, and a session with neither comparison nor decision starts no engine" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expect(!shadow_rules.enabled(&environment));
    try environment.put(shadow_rules.switch_variable, "0");
    try std.testing.expect(!shadow_rules.enabled(&environment));
    try environment.put(shadow_rules.switch_variable, "off");
    try std.testing.expect(!shadow_rules.enabled(&environment));
    try environment.put(shadow_rules.switch_variable, "1");
    try std.testing.expect(shadow_rules.enabled(&environment));
    var off: std.process.Environ.Map = .init(std.testing.allocator);
    defer off.deinit();
    try off.put(shadow_rules.decide_variable, "0");
    try std.testing.expect(shadow_rules.begin(std.testing.allocator, std.testing.io, &off, "work", "root") == null);
}

test "a session observes its project through the shadow when the environment asks, overlaid sources included" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var report: std.ArrayList(u8) = .empty;
    try session.declare(a, "main", &report);
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u64, 4), shadow.tally(.modules));
    try std.testing.expectEqual(@as(u64, 0), shadow.tally(.findings));
    _ = try session.checkDeclared(a, &report);
    try std.testing.expectEqual(@as(u64, 4), shadow.tally(.interface_recomputed) + shadow.tally(.interface_served));
    var overlaid = frontend.Session.init(gpa, std.testing.io, project.root);
    defer overlaid.deinit();
    try overlaid.enableCache(gpa, project.work);
    try overlaid.enableSharedCache(&project.environment);
    overlaid.setProviders(&.{.{ .path = "model.selka", .text = model_source }});
    try overlaid.declare(a, "main", &report);
    // The engine's world reads `model.selka` as the session does, so the overlaid session is observed like any other.
    try std.testing.expectEqual(@as(u64, 4), overlaid.caches.shadow.?.tally(.modules));
    try std.testing.expectEqual(@as(u64, 0), overlaid.caches.shadow.?.tally(.findings) + overlaid.caches.shadow.?.tally(.errors));
}

/// Check the project as a session does with the engine deciding, one valid record in `sample` withheld from the front end and
/// compared with what it computes (`"0"`: none), and return the counts. When `tamper` names a module, its `module-check` record is
/// first replaced by one that is valid and holds `lie` as its payload.
fn decide(project: *Project, sample: []const u8, tamper: ?[2][]const u8) !Counts {
    const outcome = try decideOutcome(project, sample, tamper);
    try std.testing.expect(!outcome.failed);
    return outcome.counts;
}

/// What a deciding check counted, and whether the program was refused.
const Outcome = struct { counts: Counts, failed: bool, prepared: [32]u8 };

/// As `decide`, for a program the check may refuse (the keys are prepared, and recorded, either way).
fn decideOutcome(project: *Project, sample: []const u8, tamper: ?[2][]const u8) !Outcome {
    return decideSetup(project, sample, tamper, .{});
}

/// How a deciding session is set up: whether the engine decides (`SELKA_ENGINE_DECIDE_COMPILER`), and what it overlays.
const Setup = struct { decide: []const u8 = "1", providers: []const frontend.Provider = &.{}, suffix: []const u8 = "" };

/// `decideOutcome` for a session set up as `setup`, which also returns a digest of the facts the front end prepared.
fn decideSetup(project: *Project, sample: []const u8, tamper: ?[2][]const u8, setup: Setup) !Outcome {
    const gpa = project.gpa;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try project.environment.put(shadow_rules.decide_variable, setup.decide);
    try project.environment.put(shadow_rules.verify_variable, sample);
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    session.setProviders(setup.providers);
    session.entry.suffix = setup.suffix;
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    var report: std.ArrayList(u8) = .empty;
    try session.declare(a, "main", &report);
    if (tamper) |lie| try lieAbout(&session, shadow, a, lie[0], lie[1]);
    var failed = false;
    _ = session.checkDeclared(a, &report) catch |err| switch (err) {
        error.SourceError => failed = true,
        else => return err,
    };
    const prepared = session.caches.frontend.?.request.prepared orelse return .{ .counts = shadow.sink.tallies, .failed = failed, .prepared = @splat(0) };
    return .{ .counts = shadow.sink.tallies, .failed = failed, .prepared = preparedDigest(prepared) };
}

/// A digest of everything the front end prepared for a program: stable keys, contexts, region digests and the names they came from.
fn preparedDigest(prepared: language.semantic_key.Prepared) [32]u8 {
    var state = std.crypto.hash.Blake3.init(.{});
    for (prepared.keys, prepared.contexts, prepared.recalled.digests, prepared.recalled.names) |key, context, region, names| {
        state.update(key);
        state.update(&context);
        state.update(&region);
        for (names) |name| {
            state.update(name.text);
            state.update(name.owner orelse "\x00");
        }
    }
    var out: [32]u8 = undefined;
    state.final(&out);
    return out;
}

/// Replace the `module-check` record of `path` by one valid under the reads it has now whose payload is `payload`.
fn lieAbout(session: *frontend.Session, shadow: *shadow_rules.Shadow, a: std.mem.Allocator, path: []const u8, payload: []const u8) !void {
    const state = &session.caches.frontend.?;
    const flags = try check_facts.flagsOf(a, &session.project, .{ .build = state.semantic.context.contract, .mutation = state.semantic.context.mutation_contract });
    const argument = try check_facts.argumentOf(a, path, flags);
    try shadow.answers.maps.check.put(a, argument, .{ .payload = payload, .parts = &.{}, .lookups = &.{}, .files = &.{} });
    shadow.runner.forget(&shadow.kinds.check, argument);
    _ = try shadow.runner.answer(&shadow.kinds.check, argument);
}

/// Plant, as the `module-check` record of `path`, a valid record whose payload is stored as an object and then delete the object: the
/// record is served by validation, which reads no payload, and the payload can be neither read nor, in a session that decides, computed again.
fn plantUnreadable(project: *Project, path: []const u8) !void {
    const gpa = project.gpa;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try project.environment.put(shadow_rules.decide_variable, "1");
    try project.environment.put(shadow_rules.verify_variable, "0");
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    var report: std.ArrayList(u8) = .empty;
    try session.declare(a, "main", &report);
    const large = try a.alloc(u8, 4 * @import("engine/store.zig").object_threshold);
    @memset(large, 'x');
    try lieAbout(&session, shadow, a, path, large);
    const state = &session.caches.frontend.?;
    const flags = try check_facts.flagsOf(a, &session.project, .{ .build = state.semantic.context.contract, .mutation = state.semantic.context.mutation_contract });
    const argument = try check_facts.argumentOf(a, path, flags);
    const index = shadow.runner.registry.indexOf(&shadow.kinds.check) orelse return error.TestUnexpectedResult;
    const entry = shadow.runner.registry.entries[index];
    const file = try shadow.runner.store.recordPath(a, entry.directory, digest_rules.key(entry.kind.name, entry.kind.identity, argument));
    const found = try record_rules.decode(a, (try shadow.runner.store.load(a, file)) orelse return error.TestUnexpectedResult);
    switch (found.payload) {
        .object => |object| shadow.runner.store.remove(try shadow.runner.store.objectPath(a, object)),
        .inline_bytes => return error.TestUnexpectedResult,
    }
}

test "F47 a withheld record whose payload cannot be read is computed instead and never compared against a half-written copy" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    try plantUnreadable(project, "model.selka");
    const checked = try decide(project, "1", null);
    // The unreadable record is a failed read and the module's keys are computed; the three readable ones are withheld and compared.
    try std.testing.expectEqual(@as(u64, 1), counted(checked, .errors));
    try std.testing.expectEqual(@as(u64, 3), counted(checked, .decide_withheld));
    try std.testing.expectEqual(@as(u64, 1), counted(checked, .decide_computed));
    try std.testing.expectEqual(@as(u64, 0), counted(checked, .findings));
    const healed = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(healed, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(healed, .findings) + counted(healed, .errors));
}

test "the engine decides the keys of a cold project by computing them, and of an unchanged one by serving them" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const cold = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .modules));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .decide_computed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .decide_served));
    const warm = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .decide_computed));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .findings) + counted(warm, .errors) + counted(warm, .decide_rejected));
}

test "G4c a project at another root, with an empty work directory, is decided from the records the first one published to the compiler tier" {
    const gpa = std.testing.allocator;
    const first = try Project.create(gpa);
    defer first.destroy();
    const second = try Project.create(gpa);
    defer second.destroy();
    var store = std.testing.tmpDir(.{});
    defer store.cleanup();
    const directory = try store.dir.realPathFileAlloc(std.testing.io, ".", gpa);
    defer gpa.free(directory);
    try first.environment.put(language.shared_artifact_store.environment_variable, directory);
    try second.environment.put(language.shared_artifact_store.environment_variable, directory);
    const cold = try decide(first, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .decide_computed));
    // Another tree at another path: nothing in its work directory, every key the first one made served, and verified.
    const other = try decide(second, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(other, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(other, .decide_computed));
    try std.testing.expectEqual(@as(u64, 0), counted(other, .findings) + counted(other, .errors) + counted(other, .decide_rejected));
    // A third tree checks every shared record against the keys the front end computes before it trusts one: they agree.
    const third = try Project.create(gpa);
    defer third.destroy();
    try third.environment.put(language.shared_artifact_store.environment_variable, directory);
    const checked = try decide(third, "1", null);
    try std.testing.expectEqual(@as(u64, 4), counted(checked, .decide_withheld));
    try std.testing.expectEqual(@as(u64, 0), counted(checked, .findings) + counted(checked, .errors));
    // An edit in the second tree is computed there alone; the first tree's records are not touched by it.
    try second.writeModel("return 43", "public func unused() -> i64:");
    const edited = try decide(second, "0", null);
    try std.testing.expectEqual(@as(u64, 1), counted(edited, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(edited, .decide_served));
    const untouched = try decide(first, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(untouched, .decide_served));
}

test "F33 two trees holding two versions of a project are each decided from the records their own files published, and nothing is logged as a disagreement" {
    const gpa = std.testing.allocator;
    var store = std.testing.tmpDir(.{});
    defer store.cleanup();
    const directory = try store.dir.realPathFileAlloc(std.testing.io, ".", gpa);
    defer gpa.free(directory);
    const edit = .{ "return 43", "public func unused() -> i64:" };
    const old_a = try Project.create(gpa);
    defer old_a.destroy();
    const new_b = try Project.create(gpa);
    defer new_b.destroy();
    try old_a.environment.put(language.shared_artifact_store.environment_variable, directory);
    try new_b.environment.put(language.shared_artifact_store.environment_variable, directory);
    // The tree on the old version publishes first; the tree on the new version differs in one module, so that module's record under the
    // old tree's key does not hold for it: it computes that one and publishes it as another variant of the key.
    try std.testing.expectEqual(@as(u64, 4), counted(try decide(old_a, "0", null), .decide_computed));
    try new_b.writeModel(edit[0], edit[1]);
    const published = try decide(new_b, "0", null);
    try std.testing.expectEqual(@as(u64, 1), counted(published, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(published, .decide_served));
    // Fresh trees at either version, with empty work directories, are served every key from the tier, the new version's changed module
    // from the variant, and a tree's version never serves the other's.
    const new_c = try Project.create(gpa);
    defer new_c.destroy();
    const old_d = try Project.create(gpa);
    defer old_d.destroy();
    try new_c.environment.put(language.shared_artifact_store.environment_variable, directory);
    try old_d.environment.put(language.shared_artifact_store.environment_variable, directory);
    try new_c.writeModel(edit[0], edit[1]);
    const served_new = try decide(new_c, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(served_new, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(served_new, .decide_computed));
    const served_old = try decide(old_d, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(served_old, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(served_old, .decide_computed));
    try std.testing.expectEqual(@as(u64, 0), counted(served_new, .findings) + counted(served_new, .errors) + counted(served_old, .findings) + counted(served_old, .errors));
    const log = try std.fmt.allocPrint(gpa, "{s}/compiler-artifacts-v2/mismatches.log", .{directory});
    defer gpa.free(log);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(std.testing.io, log, .{}));
}

test "a body edit has the engine compute that module's keys and serve every other module's" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    try project.writeModel("return 43", "public func unused() -> i64:");
    const after = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 1), counted(after, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(after, .decide_served));
    // The edit is recorded: the same project again is served whole.
    const again = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(again, .decide_served));
}

test "a head edit has the engine compute the keys of the importers that look the changed names up and no others" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    try project.write("model.selka", "\n\npublic record Point:\n    x: i64\n    y: i64 = 0\n\n\npublic func answer() -> i64:\n    return 42\n\n\npublic func unused() -> i64:\n    return 1\n");
    const after = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 3), counted(after, .decide_computed));
    try std.testing.expectEqual(@as(u64, 1), counted(after, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .findings));
}

test "a program that fails its check still has its modules' keys recorded" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    try project.write("main.selka", "import model\nimport other\nimport shape\n\n\nfunc main() -> i64:\n    return model.answer(1) + other.helper() + shape.origin().x\n");
    const refused = try decideOutcome(project, "0", null);
    try std.testing.expect(refused.failed);
    try std.testing.expectEqual(@as(u64, 1), counted(refused.counts, .decide_computed));
    // The edited module's keys were prepared before the check refused it, so they were recorded: the failing text again is served.
    const again = try decideOutcome(project, "0", null);
    try std.testing.expect(again.failed);
    try std.testing.expectEqual(@as(u64, 4), counted(again.counts, .decide_served));
    // The record holds the text last prepared, so the text that passed is computed again and the others are served.
    try project.write("main.selka", main_source);
    const fixed = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 3), counted(fixed, .decide_served));
    try std.testing.expectEqual(@as(u64, 1), counted(fixed, .decide_computed));
}

test "sampling withholds a valid record, and a record that says another thing than the front end computes is found and healed" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    const checked = try decide(project, "1", null);
    try std.testing.expectEqual(@as(u64, 0), counted(checked, .errors));
    try std.testing.expectEqual(@as(u64, 4), counted(checked, .decide_withheld));
    try std.testing.expectEqual(@as(u64, 0), counted(checked, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(checked, .findings));
    const lied = try decide(project, "1", .{ "model.selka", "not the keys" });
    try std.testing.expectEqual(@as(u64, 1), counted(lied, .findings));
    const healed = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(healed, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(healed, .findings));
}

test "a record that does not describe the module's functions is rejected, replaced and not served again" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    const rejected = try decide(project, "0", .{ "model.selka", "not the keys" });
    try std.testing.expectEqual(@as(u64, 1), counted(rejected, .decide_rejected));
    try std.testing.expectEqual(@as(u64, 1), counted(rejected, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(rejected, .decide_served));
    // Every payload the decision read came out of its record: no query failed to give one.
    try std.testing.expectEqual(@as(u64, 0), counted(rejected, .errors));
    const healed = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(healed, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(healed, .decide_rejected));
}

test "the engine decides unless the environment turns it off" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expect(shadow_rules.decides(&environment));
    try environment.put(shadow_rules.decide_variable, "1");
    try std.testing.expect(shadow_rules.decides(&environment));
    try environment.put(shadow_rules.decide_variable, "off");
    try std.testing.expect(!shadow_rules.decides(&environment));
    try environment.put(shadow_rules.decide_variable, "0");
    try std.testing.expect(!shadow_rules.decides(&environment));
    // Off, the front end computes every module's keys and nobody keeps them: nothing is served, nothing is recorded.
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const first = try decideSetup(project, "0", null, .{ .decide = "0" });
    const second = try decideSetup(project, "0", null, .{ .decide = "0" });
    try std.testing.expectEqual(@as(u64, 0), counted(first.counts, .decide_computed) + counted(first.counts, .decide_served));
    try std.testing.expectEqual(@as(u64, 0), counted(second.counts, .decide_computed) + counted(second.counts, .decide_served));
    try std.testing.expectEqual(first.prepared, second.prepared);
}

test "an unset variable decides, and an ordinary session writes nothing to the log" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    inline for (.{ shadow_rules.switch_variable, shadow_rules.log_variable, shadow_rules.decide_variable, shadow_rules.verify_variable }) |name| _ = project.environment.swapRemove(name);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    {
        var session = frontend.Session.init(gpa, std.testing.io, project.root);
        defer session.deinit();
        try session.enableCache(gpa, project.work);
        try session.enableSharedCache(&project.environment);
        var admits: u8 = 0;
        session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
        var report: std.ArrayList(u8) = .empty;
        _ = try session.check(a, "main", &report);
        const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
        try std.testing.expect(shadow.deciding());
        try std.testing.expectEqual(@as(u64, 4), shadow.tally(.decide_computed));
    }
    const log = try std.fmt.allocPrint(a, "{s}/engine-v1/shadow.jsonl", .{project.work});
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().readFileAlloc(std.testing.io, log, a, .limited(1 << 20)));
}

test "a project served from the engine's records is prepared exactly as one computed fresh, and as one prepared with the engine off" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const off = try decideSetup(project, "0", null, .{ .decide = "0" });
    const cold = try decide(project, "0", null);
    _ = cold;
    const warm = try decideOutcome(project, "0", null);
    try std.testing.expectEqual(@as(u64, 4), counted(warm.counts, .decide_served));
    try std.testing.expectEqual(off.prepared, warm.prepared);
    // A body edit: one module computed, three served, and the result is what the engine-off front end prepares for the same text.
    try project.writeModel("return 43", "public func unused() -> i64:");
    const edited = try decideOutcome(project, "0", null);
    try std.testing.expectEqual(@as(u64, 3), counted(edited.counts, .decide_served));
    const fresh = try decideSetup(project, "0", null, .{ .decide = "0" });
    try std.testing.expectEqual(fresh.prepared, edited.prepared);
    // A head edit that moves a name the importers look up: the same, through the chain of importers.
    try project.write("model.selka", "\n\npublic record Point:\n    x: i64\n    y: i64 = 0\n\n\npublic func answer() -> i64:\n    return 42\n\n\npublic func unused() -> i64:\n    return 1\n");
    const retyped = try decideOutcome(project, "0", null);
    const refreshed = try decideSetup(project, "0", null, .{ .decide = "0" });
    try std.testing.expectEqual(refreshed.prepared, retyped.prepared);
    try std.testing.expect(!std.mem.eql(u8, &fresh.prepared, &retyped.prepared));
}

const edited_model =
    \\
    \\public record Point:
    \\    x: i64
    \\
    \\
    \\public func answer() -> i64:
    \\    return 44
    \\
    \\
    \\public func unused() -> i64:
    \\    return 1
    \\
;

test "a session that overlays a module is decided from the overlaid text, and the record of one text is never served for another" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    const providers = [_]frontend.Provider{.{ .path = "model.selka", .text = edited_model }};
    const overlaid = try decideSetup(project, "0", null, .{ .providers = &providers });
    // The overlaid text is not the disk's: that module is computed, and the three whose names it did not move are served.
    try std.testing.expectEqual(@as(u64, 4), counted(overlaid.counts, .modules));
    try std.testing.expectEqual(@as(u64, 1), counted(overlaid.counts, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(overlaid.counts, .decide_served));
    // The same overlay again is served whole, and every record is compared with what the front end computes when all are withheld.
    const again = try decideSetup(project, "1", null, .{ .providers = &providers });
    try std.testing.expectEqual(@as(u64, 4), counted(again.counts, .decide_withheld));
    try std.testing.expectEqual(@as(u64, 0), counted(again.counts, .findings) + counted(again.counts, .errors));
    try std.testing.expectEqual(overlaid.prepared, again.prepared);
    // The disk's text again: the overlay's record is not the module's now.
    const disk = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 1), counted(disk, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(disk, .decide_served));
}

test "an entry with a stub main appended is decided from the stub's text too" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try decide(project, "0", null);
    const stub = "\n\nfunc appended() -> i64:\n    return 7\n";
    const stubbed = try decideSetup(project, "0", null, .{ .suffix = stub });
    try std.testing.expectEqual(@as(u64, 1), counted(stubbed.counts, .decide_computed));
    try std.testing.expectEqual(@as(u64, 3), counted(stubbed.counts, .decide_served));
    const same = try decideSetup(project, "1", null, .{ .suffix = stub });
    try std.testing.expectEqual(@as(u64, 4), counted(same.counts, .decide_withheld));
    try std.testing.expectEqual(@as(u64, 0), counted(same.counts, .findings) + counted(same.counts, .errors));
    const plain = try decide(project, "0", null);
    try std.testing.expectEqual(@as(u64, 1), counted(plain, .decide_computed));
}

test "the decision samples as every engine does: the variable's number, else 64 in a Debug compiler and none in a release one" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.environment.put(shadow_rules.decide_variable, "1");
    const default = shadow_rules.begin(gpa, std.testing.io, &project.environment, project.work, project.root) orelse return error.TestUnexpectedResult;
    defer default.end();
    try std.testing.expectEqual(@import("engine/command.zig").verifyEvery(&project.environment), default.answers.decision.sample_every);
    try project.environment.put(shadow_rules.verify_variable, "7");
    const named = shadow_rules.begin(gpa, std.testing.io, &project.environment, project.work, project.root) orelse return error.TestUnexpectedResult;
    defer named.end();
    try std.testing.expectEqual(@as(u32, 7), named.answers.decision.sample_every);
}

/// Check the project as a session does, lower the program as a build does (the old lowering cache is the work directory's, so a
/// second run restores what the first stored) and tell the shadow what lowering did. When `tamper` names a unit, its stored
/// `unit-lower` record is replaced first by one that is valid and says something else.
fn observeLowered(project: *Project, tamper: ?[]const u8) !Counts {
    return observeBuilt(project, tamper, false);
}

/// `observeLowered`, and with `optimize` also run the optimizer over the lowered module and tell the shadow what it joined.
fn observeBuilt(project: *Project, tamper: ?[]const u8, optimize: bool) !Counts {
    return observeBuiltWith(project, tamper, optimize, false);
}

/// `observeBuilt`, and when `emit` is set the module's internal functions as one emitted module unit, keyed by a fixed input: the unit's
/// record is then valid exactly while the optimizer parts of its functions are.
fn observeBuiltWith(project: *Project, tamper: ?[]const u8, optimize: bool, emit: bool) !Counts {
    const gpa = project.gpa;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var session = frontend.Session.init(gpa, std.testing.io, project.root);
    defer session.deinit();
    try session.enableCache(gpa, project.work);
    try session.enableSharedCache(&project.environment);
    var admits: u8 = 0;
    session.configureDemand(.{ .context = &admits, .allow = admitsNothing });
    const shadow = session.caches.shadow orelse return error.TestUnexpectedResult;
    if (tamper) |argument| try replaceUnit(shadow, argument);
    var report: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "main", &report);
    var store = try stage.Store.init(gpa, std.testing.io, project.work);
    defer store.deinit();
    var cache = lowering.Cache.init(&store);
    var observed: lowering.Observed = .{ .arena = a };
    cache.engine.observed = &observed;
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutableCached(a, .{ .program = checked.program, .source = checked.src }, &refusal, &cache);
    try std.testing.expect(session.shadowsLowering());
    session.observeLowering(.{ .program = checked.program, .src = checked.src, .observed = observed.entries.items, .drop_debug = false, .entry = "", .built = cache.counts.lowered + cache.counts.reused });
    try std.testing.expect(ownNames(shadow, checked.program));
    try project.rememberUnits(shadow);
    if (!optimize) return shadow.sink.tallies;
    var joined: facts_shadow.Observed = .{ .arena = a };
    var made: optimizer_shadow.Observed = .{ .arena = a };
    var optimizer = optimization.Context.init(&store, try ir_snapshot.Context.init(a, &module, checked.src), pipeline.locator(&checked.src));
    optimizer.lazy.facts = &joined;
    optimizer.lazy.optimized = &made;
    _ = try passes.runCached(a, gpa, &module, .trusted, &optimizer);
    shadow.observeFacts(.{ .observed = &joined, .mode = "trusted", .facts_on = true, .entry = "main" });
    shadow.observeOptimized(.{ .observed = &made, .mode = "trusted", .entry = "main" });
    if (emit) {
        var held: std.ArrayList(u32) = .empty;
        for (module.functions.items, 0..) |function, index| if (function.signature.linkage == .internal) try held.append(a, @intCast(index));
        const unit: emit_units.Unit = .{ .name = "module-x", .source_path = "model.selka", .kind = .module, .llvm = "", .dependencies = .{}, .identity = .{ .input = @splat(9), .text = @splat(4), .functions = held.items } };
        shadow.observeEmitted(.{ .units = &.{unit}, .module = &module, .mode = "trusted", .entry = "main" });
    }
    return shadow.sink.tallies;
}

/// Whether every name the shadow keeps for a unit's functions is its own copy: the optimizer's shadow reads them after the front
/// end's session and the checked program are gone, so a name that aliases a checked function's name would dangle.
fn ownNames(shadow: *const shadow_rules.Shadow, program: language.typed.Program) bool {
    for (shadow.answers.units) |unit| {
        for (unit.names) |name| {
            for (program.functions) |function| if (name.ptr == function.name.ptr) return false;
        }
    }
    return true;
}

/// Replace the stored `unit-lower` record of `argument` with one whose parts say another thing and whose reads are the same.
fn replaceUnit(shadow: *shadow_rules.Shadow, argument: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(shadow.machine.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const entry = shadow.runner.registry.entries[shadow.runner.registry.indexOf(&shadow.kinds.lower).?];
    const key = digest_rules.key(entry.kind.name, entry.kind.identity, argument);
    const file = try shadow.runner.store.recordPath(a, entry.directory, key);
    const bytes = (try shadow.runner.store.load(a, file)) orelse return error.TestUnexpectedResult;
    var found = try record_rules.decode(a, bytes);
    const lies = try a.dupe(record_rules.Part, found.parts);
    lies[0].digest[0] ^= 1;
    found.parts = lies;
    try std.testing.expect(try shadow.runner.store.publish(a, file, try record_rules.encode(a, found)));
}

test "a lowering is described unit by unit, served when nothing changed, and recomputed for the module an edit touched" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    // main, answer, helper and origin are lowered (unused is not reached): one unit per module.
    const cold = try observeLowered(project, null);
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .lower_units));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .lower_unobserved));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .lower_recomputed));
    try std.testing.expectEqual(@as(u64, 4), counted(cold, .lower_lowered));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .lower_restored));
    // Nothing changed: the engine serves every unit, and the old cache restores every function it lowered.
    const warm = try observeLowered(project, null);
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .lower_served));
    try std.testing.expectEqual(@as(u64, 4), counted(warm, .lower_restored));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .lower_lowered) + counted(warm, .lower_recomputed) + counted(warm, .lower_ahead) + counted(warm, .lower_behind));
    // An edit inside a body: its module's unit is computed again, the others are served, and the old cache lowered exactly that
    // function.
    try project.writeModel("return 43", "public func unused() -> i64:");
    const edited = try observeLowered(project, null);
    try std.testing.expectEqual(@as(u64, 1), counted(edited, .lower_recomputed));
    try std.testing.expectEqual(@as(u64, 3), counted(edited, .lower_served));
    try std.testing.expectEqual(@as(u64, 1), counted(edited, .lower_lowered));
    try std.testing.expectEqual(@as(u64, 0), counted(edited, .lower_ahead) + counted(edited, .lower_behind));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(warm, .findings) + counted(edited, .findings) + counted(edited, .errors));
}

test "the units a lowering shadow describes own the names of their functions, which the optimizer's shadow reads after the checked program is gone" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const cold = try observeLowered(project, null);
    try std.testing.expect(counted(cold, .lower_units) >= 1);
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(cold, .errors));
}

test "the lowering and the optimizer are noted for a shadow that compares and not for one that only decides the keys" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    var comparing = frontend.Session.init(gpa, std.testing.io, project.root);
    defer comparing.deinit();
    try comparing.enableCache(gpa, project.work);
    try comparing.enableSharedCache(&project.environment);
    try project.environment.put(shadow_rules.decide_variable, "1");
    var deciding = frontend.Session.init(gpa, std.testing.io, project.root);
    defer deciding.deinit();
    try deciding.enableCache(gpa, project.work);
    try deciding.enableSharedCache(&project.environment);
    try std.testing.expect(comparing.caches.shadow.?.comparing());
    try std.testing.expect(comparing.shadowsLowering());
    try std.testing.expect(deciding.caches.shadow != null);
    try std.testing.expect(!deciding.caches.shadow.?.comparing());
    try std.testing.expect(!deciding.shadowsLowering());
}

test "an edit to a function the unit does not lower, in the unit's module, leaves the unit served" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observeLowered(project, null);
    // `unused` is in the module of `answer` and is never lowered: the module's text changed, no body the unit lowers did.
    try project.writeModel("return 42", "public func unused() -> i64:\n    const spare = 7");
    const after = try observeLowered(project, null);
    try std.testing.expectEqual(@as(u64, 4), counted(after, .lower_served));
    try std.testing.expectEqual(@as(u64, 0), counted(after, .lower_recomputed) + counted(after, .lower_lowered) + counted(after, .findings));
}

test "a stale lowering record is found, logged, and healed" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const project = try Project.create(gpa);
    defer project.destroy();
    _ = try observeLowered(project, null);
    const stale = try observeLowered(project, try project.unitStartingWith("module\x00model.selka\x00debug=1"));
    try std.testing.expectEqual(@as(u64, 1), counted(stale, .findings));
    const healed = try observeLowered(project, null);
    try std.testing.expectEqual(@as(u64, 0), counted(healed, .findings));
    try std.testing.expectEqual(@as(u64, 4), counted(healed, .lower_served));
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, project.log, arena.allocator(), .limited(1 << 20));
    try std.testing.expect(std.mem.indexOf(u8, text, "unit-lower module") != null);
}

test "a generic instance is a unit of its own, and an edit to the template's body recomputes it and not the module that instantiates it" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    try project.write("main.selka", "import generic\n\n\nfunc main() -> i64:\n    return generic.pick_first([1, 2, 3])\n");
    try project.write("generic.selka", "\npublic func pick_first[T](items: T[]) -> T:\n    return items[0]\n");
    const cold = try observeLowered(project, null);
    // main is the module unit of main.selka; pick_first[i64] is an instance unit of its own.
    try std.testing.expect(counted(cold, .lower_units) >= 2);
    try std.testing.expectEqual(counted(cold, .lower_units), counted(cold, .lower_recomputed));
    const warm = try observeLowered(project, null);
    try std.testing.expectEqual(counted(cold, .lower_units), counted(warm, .lower_served));
    try project.write("generic.selka", "\npublic func pick_first[T](items: T[]) -> T:\n    const first = items[0]\n    return first\n");
    const edited = try observeLowered(project, null);
    try std.testing.expect(counted(edited, .lower_recomputed) >= 1);
    try std.testing.expect(counted(edited, .lower_served) >= 1);
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(warm, .findings) + counted(edited, .findings) + counted(edited, .errors));
}

test "the optimizer's joins are asked of the engine as the program's facts, served when no unit changed and computed when a lowered function did" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const cold = try observeBuilt(project, null, true);
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .facts_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .facts_unobserved));
    const warm = try observeBuilt(project, null, true);
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .facts_served));
    // A function now returns another constant: its unit's artifacts changed, so the facts are computed again.
    try project.writeModel("return 43", "public func unused() -> i64:");
    const edited = try observeBuilt(project, null, true);
    try std.testing.expectEqual(@as(u64, 1), counted(edited, .facts_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(warm, .findings) + counted(edited, .findings) + counted(edited, .errors));
}

test "what the optimizer made of each unit is asked of the engine, served when nothing it read changed and computed when a function it inlined did" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const cold = try observeBuilt(project, null, true);
    try std.testing.expect(counted(cold, .optimize_units) >= 4);
    try std.testing.expectEqual(counted(cold, .optimize_units), counted(cold, .optimize_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .optimize_unowned));
    const warm = try observeBuilt(project, null, true);
    try std.testing.expectEqual(counted(cold, .optimize_units), counted(warm, .optimize_served));
    try std.testing.expectEqual(@as(u64, 0), counted(warm, .optimize_recomputed) + counted(warm, .optimize_ahead));
    // `answer` returns another constant: its unit is computed again, and so is every unit that inlines it.
    try project.writeModel("return 43", "public func unused() -> i64:");
    const edited = try observeBuilt(project, null, true);
    try std.testing.expect(counted(edited, .optimize_recomputed) >= 1);
    try std.testing.expect(counted(edited, .optimize_served) >= 1);
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(warm, .findings) + counted(edited, .findings) + counted(edited, .errors));
}

test "what the emitter made of a unit is asked of the engine, served when nothing it read changed and computed when a function it holds did" {
    const gpa = std.testing.allocator;
    const project = try Project.create(gpa);
    defer project.destroy();
    const cold = try observeBuiltWith(project, null, true, true);
    const warm = try observeBuiltWith(project, null, true, true);
    // `answer` returns another constant: the optimizer part of one function of the unit changed, so the unit's record is stale.
    try project.writeModel("return 43", "public func unused() -> i64:");
    const edited = try observeBuiltWith(project, null, true, true);
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .emit_units));
    try std.testing.expectEqual(@as(u64, 1), counted(cold, .emit_recomputed));
    try std.testing.expectEqual(@as(u64, 1), counted(warm, .emit_served));
    try std.testing.expectEqual(@as(u64, 1), counted(edited, .emit_recomputed));
    try std.testing.expectEqual(@as(u64, 0), counted(cold, .findings) + counted(warm, .findings) + counted(edited, .findings) + counted(edited, .errors));
}

/// Put `count` other keys in `map`, enough to make it grow and rehash the keys it already holds.
fn fillOtherKeys(map: *std.StringHashMapUnmanaged(u32), arena: std.mem.Allocator, count: u32) !void {
    for (0..count) |position| try shadow_rules.putOwned(map, arena, try std.fmt.allocPrint(arena, "src/other_{d}.selka", .{position}), 0);
}

test "a lazy answer is stored under a copy of the path the engine lent, so the key survives the lender reusing its memory (a cold check of 300 modules crashed in rehash)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var map: std.StringHashMapUnmanaged(u32) = .empty;
    var lent: [13]u8 = "src/a.selka.x".*;
    try shadow_rules.putOwned(&map, a, lent[0.."src/a.selka".len], 7);
    @memset(&lent, 'z');
    try fillOtherKeys(&map, a, 500);
    try std.testing.expectEqual(@as(?u32, 7), map.get("src/a.selka"));
    try shadow_rules.putOwned(&map, a, "src/a.selka", 9);
    try std.testing.expectEqual(@as(?u32, 9), map.get("src/a.selka"));
    try std.testing.expectEqual(@as(u32, 501), map.count());
}
