//! A generic instance is keyed by the definitions of its type arguments, every type they are made of (the stage-instance-keys
//! fix, experiments/stage-instance-keys-20261105). The repro: `gen.same[V]` compares two values of an enum whose case holds a
//! record of another module. Growing that record by a field edits no text of the enum, the instantiating module or the generic
//! module, and the instance's stored lowering still compared the old field list: a build after the edit answered `True` where
//! a cold build answers `False`. Each test builds, edits, rebuilds, and requires the rebuilt program to be the `--no-cache`
//! build of the same sources, byte for byte in LLVM and in what it prints.
//!
//! The tests near the end (NO-CACHE-COLD-1) are about `--no-cache`: a cold build neither reads nor publishes the shared stage store. The
//! store is made to hold a stale instance (the instance-key sabotage), so a build that read it would print `True` where a cold one
//! prints `False`, and the store's files are compared before and after.
//!
//! The numbering tests come from experiments/verify-cache-served-20261106: a unit that an emission receipt serves keeps the text
//! of the build that rendered it, so that text must not hold a name the build's type table decides. `--verify-cache` found one.
const std = @import("std");
const tools = @import("core_test_options");

const Outcome = struct { status: u8, stdout: []const u8, stderr: []const u8 };

/// The record the edit grows. It lives in a module of its own, two modules away from the generic function.
const record_module =
    \\public record S0:
    \\    a: float
    \\    n: int
    \\
    \\
    \\public record Big:
    \\    s0: S0
    \\    s1: S0
    \\
;

/// The enum whose case holds the record, and the function that builds a value of it.
const enum_module =
    \\import mod_a as a
    \\
    \\public enum Value:
    \\    nil
    \\    big(value: a.Big)
    \\
    \\
    \\public func make(n: int) -> Value:
    \\    return Value.big(value=a.Big(s0=a.S0(a=1.0, n=1), s1=a.S0(a=2.0, n=n)))
    \\
;

/// The generic function: its instance at `Value` compares every field of every record the enum holds.
const generic_module =
    \\public func same[V: equality](left: V, right: V) -> bool:
    \\    return left == right
    \\
;

const main_program =
    \\import gen
    \\import mod_b as b
    \\
    \\func main(out: Stream) -> int:
    \\    const x = b.make(1)
    \\    const y = b.make(2)
    \\    print(out, gen.same(x, y))
    \\    return 0
    \\
;

/// `record_module` with a third field, which `edited_enum_module` fills so that the two values differ in it alone.
const edited_record_module =
    \\public record S0:
    \\    a: float
    \\    n: int
    \\
    \\
    \\public record Big:
    \\    s0: S0
    \\    s1: S0
    \\    s2: S0
    \\
;

const edited_enum_module =
    \\import mod_a as a
    \\
    \\public enum Value:
    \\    nil
    \\    big(value: a.Big)
    \\
    \\
    \\public func make(n: int) -> Value:
    \\    return Value.big(value=a.Big(s0=a.S0(a=1.0, n=1), s1=a.S0(a=2.0, n=1), s2=a.S0(a=3.0, n=n)))
    \\
;

/// The non-generic analogue: a function of module C copies a `Value` of module B, whose payload record lives in module A.
const copy_module =
    \\import mod_b as b
    \\
    \\public func same_count(left: b.Value, right: b.Value) -> int:
    \\    if left == right:
    \\        return 1
    \\    return 0
    \\
;

const copy_program =
    \\import mod_b as b
    \\import mod_c as c
    \\
    \\func main(out: Stream) -> int:
    \\    const x = b.make(1)
    \\    const y = b.make(2)
    \\    print(out, c.same_count(x, y))
    \\    return 0
    \\
;

/// The numbering test: a generic table whose empty slot arrays are lists of its value type (the shape of the port's `ZigStrMap[V]`), and a
/// module of its own with an empty list of a record. Neither is touched by the edit, but the edit adds a record the program names before
/// them, so every one of their element types takes another place in the build's type table.
const table_module =
    \\public func same[V: equality](left: V, right: V) -> bool:
    \\    return left == right
    \\
    \\
    \\public record Table[V]:
    \\    keys: str[]
    \\    values: V?[]
    \\    size: int
    \\
    \\
    \\public func table_init[V]() -> Table[V]:
    \\    return Table[V](keys=[], values=[], size=0)
    \\
    \\
    \\public func table_size[V](self: Table[V]) -> int:
    \\    return self.size + len(self.keys) + len(self.values)
    \\
;

const rows_module =
    \\public record Item:
    \\    id: int
    \\    name: str
    \\
    \\
    \\public func none() -> Item[]:
    \\    mut items: Item[] = []
    \\    return items
    \\
    \\
    \\public func one() -> Item:
    \\    return Item(id=1, name="one")
    \\
;

const tables_program =
    \\import gen
    \\import mod_b as b
    \\import rows
    \\
    \\func main(out: Stream) -> int:
    \\    const x = b.make(1)
    \\    const y = b.make(2)
    \\    print(out, gen.same(x, y))
    \\    print(out, len(rows.none()))
    \\    const by_value: gen.Table[b.Value] = gen.table_init()
    \\    const by_item: gen.Table[rows.Item] = gen.table_init()
    \\    print(out, gen.table_size(by_value) + gen.table_size(by_item))
    \\    return 0
    \\
;

/// `record_module` with a record of a type the program has not had, which `Big` holds and `edited_kind_enum_module` fills.
const edited_kind_record_module =
    \\public record S0:
    \\    a: float
    \\    n: int
    \\
    \\
    \\public record Kind:
    \\    code: int
    \\    label: str
    \\
    \\
    \\public record Big:
    \\    s0: S0
    \\    s1: S0
    \\    kind: Kind
    \\
;

const edited_kind_enum_module =
    \\import mod_a as a
    \\
    \\public enum Value:
    \\    nil
    \\    big(value: a.Big)
    \\
    \\
    \\public func make(n: int) -> Value:
    \\    return Value.big(value=a.Big(s0=a.S0(a=1.0, n=1), s1=a.S0(a=2.0, n=n), kind=a.Kind(code=n, label="k")))
    \\
;

/// The lists test: `finder.find` takes a list of `Group` records and returns a copy of one. Its text names `Group` only in its signature, as
/// `a.Group[]` and `a.Group?`, and the edit changes no text of `finder.selka`; the records live in `mod_a.selka`, which the edit changes.
const lists_finder_module =
    \\import mod_a as a
    \\
    \\
    \\public func find(groups: a.Group[], name: bytes) -> a.Group?:
    \\    for g in groups:
    \\        if g.name == name:
    \\            return Some(copy(g))
    \\    return None
    \\
;

const lists_before_module =
    \\public record Member:
    \\    name: bytes
    \\    net: bytes
    \\
    \\
    \\public record Group:
    \\    name: bytes
    \\    interface: bytes
    \\    members: Member[]
    \\
    \\
    \\public func make() -> Group:
    \\    return Group(name=b"g", interface=b"i", members=[Member(name=b"m", net=b"n")])
    \\
;

/// `Group` gains a float field.
const lists_group_module =
    \\public record Member:
    \\    name: bytes
    \\    net: bytes
    \\
    \\
    \\public record Group:
    \\    name: bytes
    \\    interface: bytes
    \\    members: Member[]
    \\    speed_hz: float
    \\
    \\
    \\public func make() -> Group:
    \\    return Group(name=b"g", interface=b"i", members=[Member(name=b"m", net=b"n")], speed_hz=3.5)
    \\
;

fn listsProgram(comptime read: []const u8) []const u8 {
    return std.fmt.comptimePrint(
        \\import finder
        \\import mod_a as a
        \\
        \\func main(out: Stream) -> int:
        \\    const groups = [a.make()]
        \\    const found = finder.find(groups, b"g")
        \\    match found:
        \\        case Some(g):
        \\            print(out, {s})
        \\        case None:
        \\            print(out, -1)
        \\    return 0
        \\
    , .{read});
}

/// A temporary project directory and the compiler commands run in it.
const Project = struct {
    arena: std.mem.Allocator,
    root: []const u8,

    fn write(self: Project, name: []const u8, bytes: []const u8) !void {
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fs.path.join(self.arena, &.{ self.root, name }), .data = bytes });
    }

    fn read(self: Project, name: []const u8) ![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(self.arena, &.{ self.root, name }), self.arena, .limited(64 << 20));
    }

    /// The path of `name` under the project, which the shared stage store of a test names.
    fn path(self: Project, name: []const u8) ![]const u8 {
        return std.fs.path.join(self.arena, &.{ self.root, name });
    }

    /// The files and directories under `name` with the size and a digest of each file's bytes, one line each in path order, or "absent"
    /// when there is no such directory. Two equal results mean nothing in the tree was added, removed or rewritten.
    fn treeDigest(self: Project, name: []const u8) ![]const u8 {
        var directory = std.Io.Dir.cwd().openDir(std.testing.io, try self.path(name), .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return "absent",
            else => return err,
        };
        defer directory.close(std.testing.io);
        var lines: std.ArrayList([]const u8) = .empty;
        var iterator = try directory.walk(self.arena);
        defer iterator.deinit();
        while (try iterator.next(std.testing.io)) |entry| {
            if (entry.kind == .directory) {
                try lines.append(self.arena, try std.fmt.allocPrint(self.arena, "{s}/\n", .{entry.path}));
                continue;
            }
            const bytes = try directory.readFileAlloc(std.testing.io, entry.path, self.arena, .limited(256 << 20));
            try lines.append(self.arena, try std.fmt.allocPrint(self.arena, "{s} {d} {x}\n", .{ entry.path, bytes.len, std.hash.Wyhash.hash(0, bytes) }));
        }
        std.mem.sort([]const u8, lines.items, {}, struct {
            fn lessThan(_: void, left: []const u8, right: []const u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.lessThan);
        return std.mem.concat(self.arena, u8, lines.items);
    }

    /// Run the compiler with `args` in the project directory, with every shared store off except those `extra` names.
    fn compiler(self: Project, args: []const []const u8, extra: []const [2][]const u8) !Outcome {
        const executable = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, tools.corePath(), self.arena);
        const argv = try std.mem.concat(self.arena, []const u8, &.{ &.{executable}, args });
        var environment = try tools.privateEnvironment(self.arena);
        for (extra) |pair| try environment.put(pair[0], pair[1]);
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = argv, .cwd = .{ .path = self.root }, .environ_map = &environment });
        const status: u8 = switch (result.term) {
            .exited => |code| code,
            else => 255,
        };
        return .{ .status = status, .stdout = result.stdout, .stderr = result.stderr };
    }

    /// Run the program `name` the project built and return what it printed.
    fn run(self: Project, name: []const u8) ![]const u8 {
        const executable = try std.fs.path.join(self.arena, &.{ self.root, name });
        const result = try std.process.run(self.arena, std.testing.io, .{ .argv = &.{executable}, .cwd = .{ .path = self.root } });
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
        return result.stdout;
    }

    /// Write the base program: `record_module` grown by no field.
    fn writeBase(self: Project, program: []const u8, extra_module: ?[2][]const u8) !void {
        try self.write("mod_a.selka", record_module);
        try self.write("mod_b.selka", enum_module);
        try self.write("gen.selka", generic_module);
        try self.write("repro.selka", program);
        if (extra_module) |module| try self.write(module[0], module[1]);
    }

    /// Edit the base program the way the repro does: a third field of `Big`, which only the enum module's `make` fills.
    fn edit(self: Project) !void {
        try self.write("mod_a.selka", edited_record_module);
        try self.write("mod_b.selka", edited_enum_module);
    }

    /// Edit the base program so that a record gains a field of a type that is new to the program: `Big` holds a `Kind`.
    fn editNewType(self: Project) !void {
        try self.write("mod_a.selka", edited_kind_record_module);
        try self.write("mod_b.selka", edited_kind_enum_module);
    }

    /// Build `repro.selka` into `output` with `flags`, in the work directory `cache`, writing the LLVM to `llvm`.
    fn build(self: Project, output: []const u8, llvm: []const u8, cache: []const u8, flags: []const []const u8, extra: []const [2][]const u8) !Outcome {
        const args = try std.mem.concat(self.arena, []const u8, &.{ &.{ "build", "repro.selka", "-o", output, "--emit-llvm", llvm, "--cache-dir", cache }, flags });
        return self.compiler(args, extra);
    }
};

/// Build the base program, edit it, rebuild it with the stores the base build filled, and require the rebuild to be the
/// `--no-cache` build of the edited sources in LLVM and in output. `flags` selects the build mode.
fn expectRebuildIsCold(project: Project, flags: []const []const u8, extra: []const [2][]const u8) !void {
    const base = try project.build("base", "base.ll", "cache", flags, extra);
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try std.testing.expectEqualStrings("False\n", try project.run("base"));
    try project.edit();
    const warm = try project.build("warm", "warm.ll", "cache", flags, extra);
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    const clean_flags = try std.mem.concat(project.arena, []const u8, &.{ flags, &.{"--no-cache"} });
    const clean = try project.build("clean", "clean.ll", "cache-clean", clean_flags, &.{});
    try std.testing.expectEqual(@as(u8, 0), clean.status);
    try std.testing.expectEqualStrings("False\n", try project.run("clean"));
    try std.testing.expectEqualStrings("False\n", try project.run("warm"));
    try std.testing.expectEqualSlices(u8, try project.read("clean.ll"), try project.read("warm.ll"));
}

fn tmpProject(arena: *std.heap.ArenaAllocator, temporary: *std.testing.TmpDir) !Project {
    return .{ .arena = arena.allocator(), .root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena.allocator()) };
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "a generic instance of an enum is lowered again when the record in its payload gains a field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    try project.writeBase(main_program, null);
    try expectRebuildIsCold(project, &.{}, &.{});
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "the optimized whole-program build of the same edit is the cold build too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    try project.writeBase(main_program, null);
    try expectRebuildIsCold(project, &.{"--release"}, &.{});
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "the shared stage store does not serve the instance of another program's record to a work directory that edited it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    const shared = [_][2][]const u8{.{ "SELKA_STAGE_SHARED_CACHE", try project.path("shared") }};
    try project.writeBase(main_program, null);
    // One work directory builds the base program and publishes its stages; another builds the edited sources from nothing of its own.
    const base = try project.build("base", "base.ll", "cache-one", &.{}, &shared);
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try project.edit();
    const other = try project.build("other", "other.ll", "cache-two", &.{}, &shared);
    try std.testing.expectEqual(@as(u8, 0), other.status);
    const clean = try project.build("clean", "clean.ll", "cache-clean", &.{"--no-cache"}, &.{});
    try std.testing.expectEqual(@as(u8, 0), clean.status);
    try std.testing.expectEqualStrings("False\n", try project.run("other"));
    try std.testing.expectEqualSlices(u8, try project.read("clean.ll"), try project.read("other.ll"));
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "a function of a third module that copies the enum is lowered again when the record two modules away gains a field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    try project.writeBase(copy_program, .{ "mod_c.selka", copy_module });
    const base = try project.build("base", "base.ll", "cache", &.{}, &.{});
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try std.testing.expectEqualStrings("0\n", try project.run("base"));
    try project.edit();
    const warm = try project.build("warm", "warm.ll", "cache", &.{}, &.{});
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    const clean = try project.build("clean", "clean.ll", "cache-clean", &.{"--no-cache"}, &.{});
    try std.testing.expectEqual(@as(u8, 0), clean.status);
    try std.testing.expectEqualStrings("0\n", try project.run("clean"));
    try std.testing.expectEqualStrings("0\n", try project.run("warm"));
    try std.testing.expectEqualSlices(u8, try project.read("clean.ll"), try project.read("warm.ll"));
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "--verify-cache reports an instance the stage records serve stale, and passes when they do not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    // The sabotage keys the instance by the fields its records hold alone, as every build did before the fix: the rebuild is stale.
    const sabotage = [_][]const u8{"--sabotage-instance-keys"};
    try project.writeBase(main_program, null);
    const base = try project.build("base", "base.ll", "cache", &sabotage, &.{});
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try project.edit();
    const stale = try project.build("stale", "stale.ll", "cache", &sabotage, &.{});
    try std.testing.expectEqual(@as(u8, 0), stale.status);
    try std.testing.expectEqualStrings("True\n", try project.run("stale"));
    // `--verify-cache` recomputes the stage records it would serve and fails on the instance's unit.
    const verified = try project.build("verified", "verified.ll", "cache", &.{ "--sabotage-instance-keys", "--verify-cache" }, &.{});
    try std.testing.expect(verified.status != 0);
    try std.testing.expect(std.mem.indexOf(u8, verified.stderr, "error: --verify-cache: generic unit generic-") != null);
    try std.testing.expect(std.mem.indexOf(u8, verified.stderr, "(gen.selka)") != null);
    try std.testing.expect(std.mem.indexOf(u8, verified.stderr, "unit(s) built from the stage records differ from a fresh build") != null);
    // With the keys of the fix the same work directory verifies: the instance's key moved, so nothing stale is served.
    const sound = try project.build("sound", "sound.ll", "cache", &.{ "--verify-cache", "--report" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), sound.status);
    try std.testing.expectEqualStrings("False\n", try project.run("sound"));
    const output = try std.mem.concat(arena.allocator(), u8, &.{ sound.stdout, sound.stderr });
    try std.testing.expect(std.mem.indexOf(u8, output, "\"units_compared\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"units_compared\":0,") == null);
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "the engine's observed record of an instance is not served once the record in its payload has changed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    // The shadow compares what the engine would serve for each unit lowering produced with what lowering made. An interface part is
    // named by the bound name (`Big`), so a lookup of the checked name (`mod_a::Big`) read a part nothing publishes and the record of
    // `gen::same[Value]` stayed valid however the records in its type argument changed.
    const shadow = [_][2][]const u8{
        .{ "SELKA_ENGINE_SHADOW_COMPILER", "1" },
        .{ "SELKA_ENGINE_DECIDE_COMPILER", "0" },
        .{ "SELKA_ENGINE_SHADOW_LOG", try project.path("shadow.jsonl") },
    };
    try project.writeBase(main_program, null);
    const base = try project.build("base", "base.ll", "cache", &.{}, &shadow);
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try project.edit();
    const warm = try project.build("warm", "warm.ll", "cache", &.{}, &shadow);
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    const log = try project.read("shadow.jsonl");
    const last = log[std.mem.lastIndexOf(u8, log, "\"class\":\"compiler-summary\"").?..];
    try std.testing.expect(std.mem.indexOf(u8, last, "\"lower_served\":0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, last, "\"findings\":0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, log, "the engine served a record that is not what the front end computed") == null);
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "a comment in the module of a record a type argument reaches moves no instance's key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    try project.writeBase(main_program, null);
    const base = try project.build("base", "base.ll", "cache", &.{"--report"}, &.{});
    try std.testing.expectEqual(@as(u8, 0), base.status);
    // The key holds the records' declarations as checked, not their text or their positions: a comment above `Big` and one beside its
    // last field change the module's text and leave every function, the instance of `gen.same` included, restored.
    const commented = try std.mem.concat(project.arena, u8, &.{ "# a comment above the records\n", record_module });
    try project.write("mod_a.selka", commented);
    const warm = try project.build("warm", "warm.ll", "cache", &.{"--report"}, &.{});
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    const report = try std.mem.concat(project.arena, u8, &.{ warm.stdout, warm.stderr });
    try std.testing.expect(std.mem.indexOf(u8, report, "\"lowering\":{\"reused\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "\"lowered\":0,") != null);
    try std.testing.expectEqualStrings("False\n", try project.run("warm"));
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "--verify-cache passes after a record gains a field of a new type, and the rebuild is the cold build" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    // The edit changes no text of `gen` or `rows`, and their units are served from the stages of the first build. The new record moves the
    // type ordinal of `Item` and of the instances' element types, and the stages' text must not carry the ordinals of the build that made it:
    // the units a fresh build emits are the units the stage records serve (`error: --verify-cache: ... is emitted from the cached stages as text`).
    try project.writeBase(tables_program, .{ "rows.selka", rows_module });
    try project.write("gen.selka", table_module);
    const base = try project.build("base", "base.ll", "cache", &.{}, &.{});
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try std.testing.expectEqualStrings("False\n0\n0\n", try project.run("base"));
    try project.editNewType();
    const warm = try project.build("warm", "warm.ll", "cache", &.{}, &.{});
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    const clean = try project.build("clean", "clean.ll", "cache-clean", &.{"--no-cache"}, &.{});
    try std.testing.expectEqual(@as(u8, 0), clean.status);
    try std.testing.expectEqualStrings("False\n0\n0\n", try project.run("clean"));
    try std.testing.expectEqualStrings("False\n0\n0\n", try project.run("warm"));
    try std.testing.expectEqualSlices(u8, try project.read("clean.ll"), try project.read("warm.ll"));
    const verified = try project.build("verified", "verified.ll", "cache", &.{ "--verify-cache", "--report" }, &.{});
    try std.testing.expectEqualStrings("", try errorLines(arena.allocator(), verified.stderr));
    try std.testing.expectEqual(@as(u8, 0), verified.status);
    const output = try std.mem.concat(arena.allocator(), u8, &.{ verified.stdout, verified.stderr });
    try std.testing.expect(std.mem.indexOf(u8, output, "\"units_compared\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"units_compared\":0,") == null);
}

/// The lines of `text` that report a `--verify-cache` difference, for a failure message that names the units.
fn errorLines(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var kept: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "error: --verify-cache: ")) try kept.print(a, "{s}\n", .{line});
    }
    return kept.items;
}

/// Build the lists program, give `edited` to `mod_a.selka` and the program a line that reads the new field, and require the rebuild to be the
/// `--no-cache` build, to print `expected` and to pass `--verify-cache`.
fn expectListsRebuildIsCold(project: Project, edited: []const u8, read: []const u8, expected: []const u8) !void {
    try project.write("mod_a.selka", lists_before_module);
    try project.write("finder.selka", lists_finder_module);
    try project.write("repro.selka", listsProgram("len(g.members)"));
    const base = try project.build("base", "base.ll", "cache", &.{}, &.{});
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try std.testing.expectEqualStrings("1\n", try project.run("base"));
    try project.write("mod_a.selka", edited);
    try project.write("repro.selka", read);
    const warm = try project.build("warm", "warm.ll", "cache", &.{}, &.{});
    // A Debug compiler refuses the stale function as invalid Core IR; the failure message is the diagnostic it printed.
    try std.testing.expectEqualStrings("", if (warm.status == 0) "" else warm.stderr);
    try std.testing.expectEqualStrings(expected, try project.run("warm"));
    const clean = try project.build("clean", "clean.ll", "cache-clean", &.{"--no-cache"}, &.{});
    try std.testing.expectEqual(@as(u8, 0), clean.status);
    try std.testing.expectEqualStrings(expected, try project.run("clean"));
    try std.testing.expectEqualSlices(u8, try project.read("clean.ll"), try project.read("warm.ll"));
    const verified = try project.build("verified", "verified.ll", "cache", &.{ "--verify-cache", "--report" }, &.{});
    try std.testing.expectEqualStrings("", try errorLines(project.arena, verified.stderr));
    try std.testing.expectEqual(@as(u8, 0), verified.status);
}

// spec-case: NEW-CORE-STAGE-KEYS-1
test "a function that takes a list of records is lowered again when the record gains a field" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    // `finder.find` names `Group` in its signature only, as `a.Group[]`, so its dependency context held no declaration of `mod_a`: the
    // module's stored check was vouched for, its lowering kept the old element size, and the rebuild answered -1 where a cold build answers 3.5.
    try expectListsRebuildIsCold(project, lists_group_module, listsProgram("g.speed_hz"), "3.5\n");
}

/// The sabotage switch of the stale-instance tests: instances are keyed by the fields of their records alone, as every build did before the
/// fix, so the store's record of the base program's instance is the record the edited program's instance looks up.
const sabotage_keys = "--sabotage-instance-keys";

/// A project whose base program was built with the instance-key sabotage into the shared stage store `shared` (a directory of the
/// project) and then edited, so that the store holds an instance record that is stale for the sources now on disk. Returns the store's
/// digest (`treeDigest`).
fn fillStaleStore(project: Project, shared: []const [2][]const u8) ![]const u8 {
    try project.writeBase(main_program, null);
    const base = try project.build("base", "base.ll", "cache-base", &.{sabotage_keys}, shared);
    try std.testing.expectEqual(@as(u8, 0), base.status);
    try std.testing.expectEqualStrings("False\n", try project.run("base"));
    try project.edit();
    const filled = try project.treeDigest("shared");
    try std.testing.expect(std.mem.indexOf(u8, filled, "stage-artifacts-v1") != null);
    return filled;
}

/// Run `command` (`run`, `run-project` or `build ... --run`, then the entry) on the edited program with `--no-cache` and the sabotage,
/// in the work directory `work` and with the stale store `shared`, and return what the program printed.
fn coldRunOutput(project: Project, command: []const []const u8, work: []const u8, shared: []const [2][]const u8) ![]const u8 {
    const args = try std.mem.concat(project.arena, []const u8, &.{ command, &.{ "repro.selka", "--cache-dir", work, "--no-cache", sabotage_keys } });
    const ran = try project.compiler(args, shared);
    try std.testing.expectEqualStrings("", ran.stderr);
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    return ran.stdout;
}

// spec-case: NO-CACHE-COLD-1
test "build --no-cache neither reads nor publishes the shared stage store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    const shared = [_][2][]const u8{.{ "SELKA_STAGE_SHARED_CACHE", try project.path("shared") }};
    const filled = try fillStaleStore(project, &shared);
    // The cold build runs against the stale store: it prints what a cold build prints, and leaves every file of the store as it was.
    const cold = try project.build("cold", "cold.ll", "cache-cold", &.{ sabotage_keys, "--no-cache" }, &shared);
    try std.testing.expectEqual(@as(u8, 0), cold.status);
    try std.testing.expectEqualStrings("False\n", try project.run("cold"));
    try std.testing.expectEqualStrings(filled, try project.treeDigest("shared"));
    // The record is there to be read: a build that keeps the cache takes it from the same store and prints the stale answer.
    const warm = try project.build("warm", "warm.ll", "cache-warm", &.{sabotage_keys}, &shared);
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    try std.testing.expectEqualStrings("True\n", try project.run("warm"));
}

// spec-case: NO-CACHE-COLD-1
test "run, run-project and build --run with --no-cache neither read nor publish the shared stage store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    const shared = [_][2][]const u8{.{ "SELKA_STAGE_SHARED_CACHE", try project.path("shared") }};
    const filled = try fillStaleStore(project, &shared);
    try std.testing.expectEqualStrings("False\n", try coldRunOutput(project, &.{"run"}, "cache-run", &shared));
    try std.testing.expectEqualStrings("False\n", try coldRunOutput(project, &.{"run-project"}, "cache-run-project", &shared));
    try std.testing.expectEqualStrings("False\n", try coldRunOutput(project, &.{ "build", "--run" }, "cache-build-run", &shared));
    try std.testing.expectEqualStrings(filled, try project.treeDigest("shared"));
    // The same run without the switch reads the stale record, so the three answers above come from the switch.
    const warm = try project.compiler(&.{ "run", "repro.selka", "--cache-dir", "cache-warm", sabotage_keys }, &shared);
    try std.testing.expectEqual(@as(u8, 0), warm.status);
    try std.testing.expectEqualStrings("True\n", warm.stdout);
}

/// Whether the shared store directory `name` of the project exists.
fn storeExists(project: Project, name: []const u8) !bool {
    std.Io.Dir.cwd().access(std.testing.io, try project.path(name), .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

// spec-case: NO-CACHE-COLD-1
test "a --no-cache command does not even open the shared stage store, whichever build command it is" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    try project.writeBase(main_program, null);
    const store = [_][2][]const u8{.{ "SELKA_STAGE_SHARED_CACHE", try project.path("never") }};
    // `build` and `build -o ... --generic-vectors` (the developer build, which parses its own flags) and `run`.
    const built = try project.build("built", "built.ll", "cache-built", &.{"--no-cache"}, &store);
    try std.testing.expectEqual(@as(u8, 0), built.status);
    const developer = try project.build("developer", "developer.ll", "cache-developer", &.{ "--no-cache", "--generic-vectors" }, &store);
    try std.testing.expectEqual(@as(u8, 0), developer.status);
    const ran = try project.compiler(&.{ "run", "repro.selka", "--cache-dir", "cache-run", "--no-cache" }, &store);
    try std.testing.expectEqual(@as(u8, 0), ran.status);
    try std.testing.expectEqualStrings("False\n", ran.stdout);
    try std.testing.expect(!try storeExists(project, "never"));
    // An ordinary build with the same variable creates it.
    const ordinary = try project.build("ordinary", "ordinary.ll", "cache-ordinary", &.{}, &store);
    try std.testing.expectEqual(@as(u8, 0), ordinary.status);
    try std.testing.expect(try storeExists(project, "never"));
}

// spec-case: NO-CACHE-COLD-1
test "--verify-cache's fresh pass reads no shared stage record, so a stale one is reported" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const project = try tmpProject(&arena, &temporary);
    const shared = [_][2][]const u8{.{ "SELKA_STAGE_SHARED_CACHE", try project.path("shared") }};
    _ = try fillStaleStore(project, &shared);
    // The first pass serves the stale instance from the shared store, as an ordinary build does; the second recomputes every unit
    // without any store, so the two differ. A fresh pass that read the shared store would agree with the first and pass.
    const verified = try project.build("verified", "verified.ll", "cache-verify", &.{ sabotage_keys, "--verify-cache" }, &shared);
    try std.testing.expect(verified.status != 0);
    try std.testing.expect(std.mem.indexOf(u8, verified.stderr, "error: --verify-cache: generic unit generic-") != null);
}
