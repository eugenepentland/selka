//! The edit check's impact step (EC2 of `docs/audits/edit-check-plan-2026-10-25.md`).
//!
//!     edit-check-impact --map MAP.json[.gz] --repo DIR [--importers direct|closure|reexport|none]
//!                       [--tests DIR] [--selection OUT] [--base COMMIT]
//!                       [--without outside,newfile,build,unmapped] [--new-files reach|everything]
//!
//! Compares the working tree of DIR with the commit the coverage map was built at (or with
//! `--base COMMIT`, for replaying an older edit; the map still supplies the function ids and
//! the tests), and prints every map function the edit impacts, with the reason. `--without`
//! switches off the named conservative rules below (measurement only; the default is all on).
//! The selection (the named
//! tests and unnamed-block sets that run the impacted code) goes to `--selection` as
//! tab-separated `root TAB kind TAB name TAB reason` lines, where kind is `named` or
//! `unnamed`. Rules:
//!
//! * a function whose tokens changed, or that was removed, impacts its map id;
//! * an added function impacts nothing by itself (it runs only through a changed caller);
//! * a changed or removed function the map does not list has no machine code in any test
//!   binary: it runs only at compile time (a table a container-level `const` fills, a
//!   `comptime` helper, a type-returning function) or nowhere. Its change impacts every
//!   function of its file and of its importers, as the next rule does, with the reason
//!   `unmapped function NAME`;
//! * a change outside every function of a file (types, constants, imports, `comptime`
//!   blocks, `usingnamespace`) impacts every function of that file and of its importers
//!   (`--importers reexport`, the default, follows an importer's importers only through an importer whose public value
//!   (`pub const`, `pub var`, a type alias) or `usingnamespace` re-exports the file it imports,
//!   `edit_check/reexport.zig`; a public function is not a re-export, rule 2 covers its compile-time calls. On the
//!   historical edits it costs about +28 named tests per edit over `direct`, which stops at the direct importers and
//!   misses a constant that an unchanged importer re-exports and a third file reads; `closure` follows every importer
//!   transitively);
//! * a changed or removed function that a compile-time item calls or evaluates impacts the file of that item as a change
//!   outside its functions (rule 4, `--without compile` switches it off, and rule 2 is part of it). A compile-time item is
//!   a container-level `const` or `var` initializer (a container's field defaults, member constants and `comptime`
//!   blocks; its functions are run-time code, as a file's are), a `comptime` block, a `usingnamespace`, or a function
//!   that returns a type. A bare alias (`const f = other.f;`, one line) is a rename, not a use: its name is carried on, so
//!   a compile-time use of the alias in an importer counts. The search is `compileTimeFiles` over tokens
//!   (`edit_check/reexport.zig`; strings and comments name nothing): from the changed function's file, through its
//!   importers, and through the names each file's tainted items define. An item counts when its evaluation runs a
//!   tainted function: it calls one, names a value whose evaluation does, or calls through a value that holds tainted
//!   functions; naming a type or listing a function in a table is no call. An importer reaches a file-level name only
//!   through its binding of the file (`output.render`, or an inline `@import`), a container member through any value
//!   (`.init(`, except a decl literal of a `std` field type), and a bare word only in the file that defines it (or in an
//!   importer that uses `usingnamespace`);
//! * rule 2: a change outside the functions of a file (rule 1) also impacts the functions of its direct importers, so
//!   a compile-time use of one of those functions, in an importer of an importer, makes that file a rest change too
//!   (the same search, seeded with the functions of the file and of its importers);
//! * a deleted Zig file impacts its map functions;
//! * a new `.zig` file (rule 2; the default `--new-files reach` selects the tests that the file's importers and the
//!   walkers of its directory reach, and `--new-files everything` selects every test, the rule before, see the G3 recall
//!   study in the edit-check notes) has no map id, so its own functions impact nothing; its tests are new names, which
//!   `--tests` selects. It reaches old code only through a changed line of a file that imports or embeds it (that file's
//!   own rules impact the reach) or through a test that walks a repository directory it is in: the walking file's
//!   functions and importers are impacted, with the reason `walks DIR: FILE`. Walks are the open calls of the working
//!   tree whose directory argument is a string literal (computed roots were checked call by call, assumption A1); the
//!   build's identity walk of `src/` feeds only cache keys. Under `tools/` or `scripts/` a new file selects nothing (no
//!   test root compiles it); under `selfhost/` a new file selects everything whatever the rule, since its component walks
//!   are not audited (A1 covers `src/` only);
//! * `build.zig`, `build_test_inputs.zig`, `build_coverage.zig`, `build_identity.zig`,
//!   `build_env.zig`, `build_verification.zig`, `build.zig.zon` and `.zigversion` select
//!   everything;
//! * a non-Zig file under `src/` that a Zig file names (`@embedFile`, an import or a path
//!   string) impacts every function of the naming files and their importers; a `src/` file
//!   no Zig file names falls back to the declared inputs of `build_test_inputs.zig`;
//! * any other non-Zig file that a Zig file names impacts those files as well, and a file
//!   covered by the declared input lists `unit`, `cli` or `core` selects every test of that
//!   root;
//! * with `--tests DIR` (the test names of each root's current binary), a named test the map
//!   does not know is new and is selected; a test that failed alone is always selected.
//!
//! Guest test files (E2, the `guests` root) are selected by file, not by test: a guest file runs when it executed an
//! impacted function, as a Zig test does. A changed or new `.selka` file under `tests/lang` selects itself and every guest
//! file that imports or names it, transitively; the C runtime (`src/core/runtime/`) and the Selka components
//! (`selfhost/`) run in every guest, so a change to either selects them all; any other change that no Zig file names
//! selects every guest file, except the documentation, experiment and tool trees (`guestIrrelevant`). A map with no
//! `guests` root selects every guest file as new, so the edit check then runs the whole guest suite.
//!
//! Comments and layout never count: function and file digests are token digests
//! (`edit_check/zig_functions.zig`). Output is text on standard output, one line per
//! impacted id; exit status 2 means the map or the arguments could not be used, and 3 that the map predates the
//! unrecorded list (refused: the edit check treats it as no map and refreshes it).
const std = @import("std");
const zig_functions = @import("edit_check/zig_functions.zig");
const reexport = @import("edit_check/reexport.zig");

/// Root names in the map; a root's index is its position here.
const root_names = [_][]const u8{ "units", "cli", "core", "guests" };
/// The root of the guest test files (`tests/lang`); its names are paths.
const guest_root = 3;
/// The directory of the guest test files, with its trailing slash.
const guest_directory = "tests/lang/";
/// The declared input lists of `build_test_inputs.zig` that name each Zig root's inputs, in `root_names` order.
const root_lists = [_][]const u8{ "unit", "cli", "core" };
/// Files whose change affects every test of every root.
const everything_files = [_][]const u8{ "build.zig", "build_test_inputs.zig", "build_coverage.zig", "build_identity.zig", "build_env.zig", "build_verification.zig", "build.zig.zon", ".zigversion" };

/// How far a change outside a file's functions reaches through the import graph.
pub const Importers = enum { direct, closure, reexport, none };

/// The exit status of a map the tool refuses because it predates the unrecorded list (see `loadMap`).
pub const refused_map_status = 3;

/// The command line.
pub const Options = struct {
    map: []const u8,
    repo: []const u8,
    importers: Importers = .reexport,
    /// How a new `.zig` file is treated (`--new-files`): `reach` (the default; the G3 recall study killed 24 mutants with no
    /// miss) or `everything` (the rule before the reach rule: every test).
    new_files: NewFiles = .reach,
    /// The commit to compare the working tree with, instead of the map's commit (`--base`).
    base: ?[]const u8 = null,
    /// The three conservative rules this run switches off (`--without`).
    without: Without = .{},
    /// The files the edit check reads and writes: the test lists and the selection.
    output: Output = .{},
};

/// The new-file rule: `reach` (a new file's tests are new names; it reaches old code only through the files that
/// import it, and through a test that walks a repository directory it is in) or `everything` (the rule before).
pub const NewFiles = enum { reach, everything };

/// The test lists a run reads (`--tests`) and the selection it writes (`--selection`).
pub const Output = struct {
    tests: ?[]const u8 = null,
    selection: ?[]const u8 = null,
};

/// The conservative rules a run switches off. All are on by default; a run with one off measures what that rule adds.
pub const Without = struct {
    /// Rule 1: a change outside every function of a file impacts the functions of that file and its importers.
    outside: bool = false,
    /// Rule 2: a new `.zig` file reaches the walking files (`--new-files reach`), or with `everything` selects everything.
    newfile: bool = false,
    /// Rule 3: a build input selects everything.
    build: bool = false,
    /// The compile-time rule for a changed function the map does not list. Off reproduces the unsound
    /// behaviour that skipped such functions; for measuring the rule's cost only.
    unmapped: bool = false,
    /// Rule 4: a changed function that a compile-time item calls (a container-level initializer, a comptime block, a type
    /// builder), in its file or in an importer's, makes that file a rest change; rule 2 does the same for the functions of
    /// the importers of a file whose rest changed (`compileTimeFiles`).
    compile: bool = false,
};

/// The status of a changed path relative to the commit.
pub const Status = enum { added, deleted, modified };

/// A changed path.
pub const Change = struct {
    path: []const u8,
    status: Status,
};

/// A test of a root, by root and name (the name is empty for a root's unnamed blocks).
pub const TestRef = struct {
    root: []const u8,
    name: []const u8,
};

/// A coverage map (`edit-check-coverage-map-v1`) with its indexes.
pub const Map = struct {
    /// The commit the map was built at, without any `-dirty` suffix.
    commit: []const u8,
    /// Whether the map was built from uncommitted sources.
    dirty: bool,
    /// Function id to its file, name and ordinal.
    file: [][]const u8,
    name: [][]const u8,
    ordinal: []u32,
    /// `file NUL name NUL ordinal` to the function id.
    id_of: std.StringHashMapUnmanaged(u32) = .empty,
    /// Function id to the ids of the functions of its file.
    file_ids: std.StringHashMapUnmanaged([]const u32) = .empty,
    /// Named tests: root, name, and the function ids they ran.
    test_root: [][]const u8,
    test_name: [][]const u8,
    test_ids: [][]u32,
    /// The tests of function id `i` are `tests_flat[tests_start[i]..tests_start[i + 1]]`.
    tests_start: []u32,
    tests_flat: []u32,
    /// Per root, the ids its unnamed test blocks ran.
    unnamed: [root_names.len][]const u32 = .{ &.{}, &.{}, &.{}, &.{} },
    /// Tests that failed when they ran alone.
    failed: []const []const u8,
    /// Tests that started an instrumented process which left no hit set: selected whatever the edit (the map's
    /// `unrecorded` list; an empty name selects the whole root, for an unnamed block).
    unrecorded: []const TestRef = &.{},
};

/// The decisions of one analysis.
pub const Analysis = struct {
    /// Impacted function id to the first reason that impacted it.
    impacted: std.AutoArrayHashMapUnmanaged(u32, []const u8) = .empty,
    /// Selected entries keyed by `root TAB kind TAB name`, valued by the reason.
    selected: std.StringArrayHashMapUnmanaged([]const u8) = .empty,
    /// The reason that selects every test of a root, by root index.
    root_all: [root_names.len]?[]const u8 = .{ null, null, null, null },
    /// The reason that selects every test of every root.
    everything: ?[]const u8 = null,
    /// Changed files that no Zig test reads.
    unrouted: std.ArrayList([]const u8) = .empty,
    /// Facts the report shows, such as a test list that was missing.
    notes: std.ArrayList([]const u8) = .empty,
    /// The new `.zig` files of the edit: their tests are new names (`namedByNewFile`).
    new_files: std.ArrayList([]const u8) = .empty,
};

/// Entry point.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = parseArgs(args) catch {
        std.debug.print("usage: edit-check-impact --map MAP --repo DIR [--importers direct|closure|reexport|none] [--tests DIR] [--selection OUT] [--base COMMIT] [--without outside,newfile,build,unmapped] [--new-files reach|everything]\n", .{});
        std.process.exit(2);
    };
    var out_buffer: [16 * 1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &out_buffer);
    const out = &stdout.interface;
    defer out.flush() catch {};
    const map = loadMap(arena, init.io, options.map) catch |err| {
        try out.print("edit-check-impact: cannot use the map {s}: {t}\n", .{ options.map, err });
        out.flush() catch {};
        // A map that predates the unrecorded list is refused with its own status (3), which the edit check reads as
        // "no usable map" and answers with a refresh; any other failure is 2.
        std.process.exit(if (err == error.MapPredatesUnrecorded) refused_map_status else 2);
    };
    const analysis = try analyze(arena, init.io, options, map);
    try report(arena, init.io, out, options, map, analysis);
}

/// Parse the command line, whose first argument is the program name.
pub fn parseArgs(args: []const []const u8) error{Usage}!Options {
    var options: Options = .{ .map = "", .repo = "." };
    var index: usize = 1;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len) return error.Usage;
        const flag = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, flag, "--map")) {
            options.map = value;
        } else if (std.mem.eql(u8, flag, "--repo")) {
            options.repo = value;
        } else if (std.mem.eql(u8, flag, "--importers")) {
            options.importers = std.meta.stringToEnum(Importers, value) orelse return error.Usage;
        } else if (std.mem.eql(u8, flag, "--tests")) {
            options.output.tests = value;
        } else if (std.mem.eql(u8, flag, "--selection")) {
            options.output.selection = value;
        } else if (std.mem.eql(u8, flag, "--new-files")) {
            options.new_files = std.meta.stringToEnum(NewFiles, value) orelse return error.Usage;
        } else if (std.mem.eql(u8, flag, "--base")) {
            options.base = value;
        } else if (std.mem.eql(u8, flag, "--without")) {
            options.without = try parseWithout(value);
        } else return error.Usage;
    }
    if (options.map.len == 0) return error.Usage;
    return options;
}

/// Parse a comma-separated list of rule names (`outside`, `newfile`, `build`) into the rules a run switches off.
pub fn parseWithout(value: []const u8) error{Usage}!Without {
    var without: Without = .{};
    var names = std.mem.splitScalar(u8, value, ',');
    while (names.next()) |name| {
        if (std.mem.eql(u8, name, "outside")) {
            without.outside = true;
        } else if (std.mem.eql(u8, name, "newfile")) {
            without.newfile = true;
        } else if (std.mem.eql(u8, name, "build")) {
            without.build = true;
        } else if (std.mem.eql(u8, name, "unmapped")) {
            without.unmapped = true;
        } else if (std.mem.eql(u8, name, "compile")) {
            without.compile = true;
        } else return error.Usage;
    }
    return without;
}

/// The commit the working tree is compared with: `--base` when given, otherwise the map's commit.
fn baseOf(options: Options, map: Map) []const u8 {
    return options.base orelse map.commit;
}

/// Read the map (gzip-compressed when the path ends in `.gz`) and build its indexes.
pub fn loadMap(arena: std.mem.Allocator, io: std.Io, path: []const u8) !Map {
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(512 << 20));
    const bytes = if (std.mem.endsWith(u8, path, ".gz")) try gunzip(arena, raw) else raw;
    const document = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
    const object = document.object;
    const label = jsonString(object.get("commit") orelse return error.MissingCommit);
    const dirty = std.mem.endsWith(u8, label, "-dirty");
    const commit = if (dirty) label[0 .. label.len - "-dirty".len] else label;

    const functions = (object.get("functions") orelse return error.MissingFunctions).array.items;
    var map: Map = .{
        .commit = commit,
        .dirty = dirty,
        .file = try arena.alloc([]const u8, functions.len),
        .name = try arena.alloc([]const u8, functions.len),
        .ordinal = try arena.alloc(u32, functions.len),
        .tests_start = try arena.alloc(u32, functions.len + 1),
        .tests_flat = &.{},
        .test_root = &.{},
        .test_name = &.{},
        .test_ids = &.{},
        .failed = &.{},
    };
    for (functions, 0..) |entry, id| {
        const fields = entry.array.items;
        map.file[id] = jsonString(fields[0]);
        map.name[id] = jsonString(fields[1]);
        map.ordinal[id] = @intCast(fields[2].integer);
        try map.id_of.put(arena, try functionKey(arena, map.file[id], map.name[id], map.ordinal[id]), @intCast(id));
        const slot = try map.file_ids.getOrPut(arena, map.file[id]);
        if (!slot.found_existing) slot.value_ptr.* = &.{};
        slot.value_ptr.* = try appendId(arena, slot.value_ptr.*, @intCast(id));
    }

    const tests = (object.get("tests") orelse return error.MissingTests).array.items;
    map.test_root = try arena.alloc([]const u8, tests.len);
    map.test_name = try arena.alloc([]const u8, tests.len);
    map.test_ids = try arena.alloc([]u32, tests.len);
    const counts = try arena.alloc(u32, functions.len);
    @memset(counts, 0);
    for (tests, 0..) |entry, index| {
        const fields = entry.array.items;
        map.test_root[index] = jsonString(fields[0]);
        map.test_name[index] = jsonString(fields[1]);
        map.test_ids[index] = try idList(arena, fields[2].array.items);
        for (map.test_ids[index]) |id| counts[id] += 1;
    }
    var total: u32 = 0;
    for (counts, 0..) |count, id| {
        map.tests_start[id] = total;
        total += count;
    }
    map.tests_start[functions.len] = total;
    map.tests_flat = try arena.alloc(u32, total);
    const fill = try arena.alloc(u32, functions.len);
    @memcpy(fill, map.tests_start[0..functions.len]);
    for (map.test_ids, 0..) |ids, index| {
        for (ids) |id| {
            map.tests_flat[fill[id]] = @intCast(index);
            fill[id] += 1;
        }
    }

    const unnamed = object.get("unnamed") orelse return error.MissingUnnamed;
    for (root_names, 0..) |root, index| {
        if (unnamed.object.get(root)) |ids| map.unnamed[index] = try idList(arena, ids.array.items);
    }
    var failed: std.ArrayList([]const u8) = .empty;
    for ((object.get("failed") orelse return error.MissingFailed).array.items) |item| {
        try failed.append(arena, jsonString(item));
    }
    map.failed = try failed.toOwnedSlice(arena);
    // A map without the list predates the rule that selects the tests of unrecorded processes: it is refused, not
    // read as "none of its tests started one".
    var unrecorded: std.ArrayList(TestRef) = .empty;
    for ((object.get("unrecorded") orelse return error.MapPredatesUnrecorded).array.items) |item| {
        try unrecorded.append(arena, .{ .root = jsonString(item.array.items[0]), .name = jsonString(item.array.items[1]) });
    }
    map.unrecorded = try unrecorded.toOwnedSlice(arena);
    return map;
}

fn gunzip(arena: std.mem.Allocator, compressed: []const u8) ![]const u8 {
    var input = std.Io.Reader.fixed(compressed);
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var decompress = std.compress.flate.Decompress.init(&input, .gzip, &window);
    return decompress.reader.allocRemaining(arena, .unlimited);
}

fn jsonString(value: std.json.Value) []const u8 {
    return value.string;
}

fn idList(arena: std.mem.Allocator, values: []const std.json.Value) ![]u32 {
    const ids = try arena.alloc(u32, values.len);
    for (values, 0..) |value, index| ids[index] = @intCast(value.integer);
    return ids;
}

fn appendId(arena: std.mem.Allocator, existing: []const u32, id: u32) ![]const u32 {
    const grown = try arena.alloc(u32, existing.len + 1);
    @memcpy(grown[0..existing.len], existing);
    grown[existing.len] = id;
    return grown;
}

/// The map key of a function: its file, name and ordinal, separated by NUL bytes.
pub fn functionKey(arena: std.mem.Allocator, file: []const u8, name: []const u8, ordinal: u32) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}\x00{s}\x00{d}", .{ file, name, ordinal });
}

/// The key of a selection entry.
fn selectionKey(arena: std.mem.Allocator, root: []const u8, kind: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}\t{s}\t{s}", .{ root, kind, name });
}

/// Compare the working tree with the map's commit (or `--base`) and decide what the edit impacts.
pub fn analyze(arena: std.mem.Allocator, io: std.Io, options: Options, map: Map) !Analysis {
    var analysis: Analysis = .{};
    const changes = try changedFiles(arena, io, options.repo, baseOf(options, map));
    const graph = try importGraph(arena, io, options.repo);
    const walks = try walksOf(arena, graph);
    for (changes) |change| {
        if (selectsEveryGuest(change.path)) {
            const reason = try std.fmt.allocPrint(arena, "guest dependency {s}", .{change.path});
            try selectAllGuests(arena, &analysis, graph.guests, reason);
        }
        if (!std.mem.endsWith(u8, change.path, ".zig")) {
            try analyzeOther(arena, io, options, map, graph, &analysis, change);
            continue;
        }
        if (isEverythingFile(change.path)) {
            if (!options.without.build) analysis.everything = try std.fmt.allocPrint(arena, "build input {s}", .{change.path});
            continue;
        }
        switch (change.status) {
            .added => {
                if (std.mem.startsWith(u8, change.path, "tools/") or std.mem.startsWith(u8, change.path, "scripts/")) {
                    try analysis.unrouted.append(arena, change.path);
                } else if (options.new_files == .everything or std.mem.startsWith(u8, change.path, "selfhost/")) {
                    // A new file under selfhost/ is routed to everything whatever the rule: its component walks (selfhost/components.zig,
                    // component_files.zig) are not audited (A1 covers the src/ walks only), so the reach rule cannot vouch for them.
                    if (!options.without.newfile) analysis.everything = try std.fmt.allocPrint(arena, "new Zig file {s}", .{change.path});
                } else {
                    try impactNewFile(arena, options, map, graph, walks, &analysis, change.path);
                }
            },
            .deleted => {
                const reason = try std.fmt.allocPrint(arena, "deleted {s}", .{change.path});
                for (map.file_ids.get(change.path) orelse &.{}) |id| try impact(arena, &analysis, id, reason);
            },
            .modified => try analyzeModified(arena, io, options, map, graph, &analysis, change),
        }
    }
    try expandSelection(arena, map, &analysis);
    if (analysis.everything) |reason| try selectAllGuests(arena, &analysis, graph.guests, reason);
    if (options.output.tests) |directory| try addNewTests(arena, io, directory, map, &analysis);
    return analysis;
}

/// Whether a change to `path` reaches every guest file through a process the coverage map does not record: the C
/// runtime each guest links, and the Selka components its guests run (`selfhost/`).
fn selectsEveryGuest(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "src/core/runtime/") or std.mem.startsWith(u8, path, "selfhost/");
}

/// Whether a changed file that no Zig file names is one a guest test program never reads: documentation, the
/// experiment, script, benchmark and tool trees, the shard plans, the Python drivers under `tests/`, and the root
/// Markdown files. Any other unnamed input selects every guest file.
fn guestIrrelevant(path: []const u8) bool {
    const trees = [_][]const u8{ "docs/", "experiments/", "scripts/", "velocity/", "bench/", "benchmarks/", "examples/", "proofs/", "tools/", "tests/shard-plans/" };
    for (trees) |tree| if (std.mem.startsWith(u8, path, tree)) return true;
    if (std.mem.startsWith(u8, path, "tests/") and std.mem.endsWith(u8, path, ".py")) return true;
    if (std.mem.indexOfScalar(u8, path, '/') == null and std.mem.endsWith(u8, path, ".md")) return true;
    return std.mem.eql(u8, path, ".gitignore");
}

/// Select one guest file, keeping the first reason given.
fn selectGuest(arena: std.mem.Allocator, analysis: *Analysis, path: []const u8, reason: []const u8) !void {
    const key = try selectionKey(arena, root_names[guest_root], "named", path);
    if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, reason);
}

/// Select every guest file of the working tree, for `reason`.
fn selectAllGuests(arena: std.mem.Allocator, analysis: *Analysis, guests: []const Source, reason: []const u8) !void {
    for (guests) |guest| try selectGuest(arena, analysis, guest.path, reason);
}

/// Impact a file under `tests/lang`: a guest test file selects itself, and the guest files that import or name it
/// select themselves too, through the files they import in turn. A file that no guest names and that is not a module
/// (a README, a fixture read by name) selects every guest file, as an unnamed input does.
fn analyzeGuestFile(arena: std.mem.Allocator, graph: ImportGraph, analysis: *Analysis, change: Change) !void {
    const path = change.path;
    const module = std.mem.endsWith(u8, path, ".selka");
    if (module and change.status != .deleted) {
        const reason = if (change.status == .added) "new guest file" else "changed guest file";
        try selectGuest(arena, analysis, path, reason);
    }
    const importers = try selectImporters(arena, analysis, graph.guests, path);
    if (!module and importers == 0) {
        const reason = try std.fmt.allocPrint(arena, "unnamed guest input {s}", .{path});
        try selectAllGuests(arena, analysis, graph.guests, reason);
    }
}

/// Select every guest file that imports or names `path`, and then the guest files that import those, and so on.
/// Returns how many guest files it selected in this call.
fn selectImporters(arena: std.mem.Allocator, analysis: *Analysis, guests: []const Source, path: []const u8) !usize {
    var frontier: std.ArrayList([]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    try frontier.append(arena, path);
    try seen.put(arena, path, {});
    var selected: usize = 0;
    var next: usize = 0;
    while (next < frontier.items.len) : (next += 1) {
        const target = frontier.items[next];
        const stem = moduleStem(target);
        for (guests) |guest| {
            if (seen.contains(guest.path)) continue;
            if (!mentionsModule(guest.text, stem) and !namesFile(guest.text, target)) continue;
            try seen.put(arena, guest.path, {});
            try frontier.append(arena, guest.path);
            const reason = try std.fmt.allocPrint(arena, "imports or names {s}", .{target});
            try selectGuest(arena, analysis, guest.path, reason);
            selected += 1;
        }
    }
    return selected;
}

/// The module name of a `.selka` file: its basename without the extension.
pub fn moduleStem(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    return if (std.mem.endsWith(u8, base, ".selka")) base[0 .. base.len - ".selka".len] else base;
}

/// Whether `text` contains `stem` as a whole word, such as an `import` of a module of that name. A mention in a
/// comment or inside a longer dotted path also counts: that only widens the selection.
pub fn mentionsModule(text: []const u8, stem: []const u8) bool {
    if (stem.len == 0) return true;
    var search: usize = 0;
    while (std.mem.indexOfPos(u8, text, search, stem)) |at| {
        search = at + 1;
        const end = at + stem.len;
        const starts_word = at == 0 or !isIdentifierByte(text[at - 1]);
        const ends_word = end >= text.len or !isIdentifierByte(text[end]);
        if (starts_word and ends_word) return true;
    }
    return false;
}

/// The files that differ between the commit and the working tree, including untracked files.
fn changedFiles(arena: std.mem.Allocator, io: std.Io, repo: []const u8, commit: []const u8) ![]Change {
    var list: std.ArrayList(Change) = .empty;
    const diff = try git(arena, io, repo, &.{ "diff", "--no-renames", "--name-status", commit, "--" });
    var lines = std.mem.splitScalar(u8, diff, '\n');
    while (lines.next()) |line| {
        if (line.len < 3) continue;
        const status: Status = switch (line[0]) {
            'A' => .added,
            'D' => .deleted,
            else => .modified,
        };
        try list.append(arena, .{ .path = line[2..], .status = status });
    }
    const untracked = try git(arena, io, repo, &.{ "ls-files", "--others", "--exclude-standard" });
    var more = std.mem.splitScalar(u8, untracked, '\n');
    while (more.next()) |path| {
        if (path.len == 0) continue;
        try list.append(arena, .{ .path = path, .status = .added });
    }
    return list.toOwnedSlice(arena);
}

/// Run git in `repo` and return its standard output; a non-zero exit is an error.
fn git(arena: std.mem.Allocator, io: std.Io, repo: []const u8, args: []const []const u8) ![]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ "git", "-C", repo });
    try argv.appendSlice(arena, args);
    const result = try std.process.run(arena, io, .{ .argv = argv.items });
    switch (result.term) {
        .exited => |code| if (code == 0) return result.stdout,
        else => {},
    }
    return error.GitFailed;
}

/// The bytes of `path` at `commit`, or null when the commit has no such file.
fn committedFile(arena: std.mem.Allocator, io: std.Io, repo: []const u8, commit: []const u8, path: []const u8) !?[]const u8 {
    const spec = try std.fmt.allocPrint(arena, "{s}:{s}", .{ commit, path });
    return git(arena, io, repo, &.{ "show", spec }) catch null;
}

fn isEverythingFile(path: []const u8) bool {
    for (everything_files) |name| if (std.mem.eql(u8, path, name)) return true;
    return false;
}

/// Impact a Zig file that existed at the commit and still exists.
fn analyzeModified(arena: std.mem.Allocator, io: std.Io, options: Options, map: Map, graph: ImportGraph, analysis: *Analysis, change: Change) !void {
    const path = change.path;
    const old_bytes = (try committedFile(arena, io, options.repo, baseOf(options, map), path)) orelse {
        analysis.everything = try std.fmt.allocPrint(arena, "Zig file {s} has no committed version", .{path});
        return;
    };
    const new_bytes = std.Io.Dir.cwd().readFileAlloc(io, try joinPath(arena, options.repo, path), arena, .limited(64 << 20)) catch {
        analysis.everything = try std.fmt.allocPrint(arena, "Zig file {s} cannot be read", .{path});
        return;
    };
    var old_file = zig_functions.parse(arena, old_bytes) catch {
        analysis.everything = try std.fmt.allocPrint(arena, "Zig file {s} did not parse at the commit", .{path});
        return;
    };
    defer old_file.deinit(arena);
    var new_file = zig_functions.parse(arena, new_bytes) catch {
        analysis.everything = try std.fmt.allocPrint(arena, "Zig file {s} does not parse", .{path});
        return;
    };
    defer new_file.deinit(arena);
    const comparison = try zig_functions.compare(arena, old_file, new_file);
    defer arena.free(comparison.items);
    // Rule 4: a changed function that a compile-time item calls makes the file of that item a rest change.
    if (!options.without.compile) {
        var changed: std.ArrayList(CompileSeed) = .empty;
        var names: std.ArrayList(reexport.Name) = .empty;
        const defined = try functionNamesOf(arena, graph, path);
        for (comparison.items) |item| if (item.reason != .added) try names.append(arena, changedName(defined, item.name));
        if (names.items.len > 0) {
            try changed.append(arena, .{ .file = path, .names = names.items });
            const reason = try std.fmt.allocPrint(arena, "compile-time call of a changed function of {s}", .{path});
            for (try compileTimeFiles(arena, graph, changed.items)) |file| try impactRest(arena, map, graph, options.importers, file, analysis, reason);
        }
    }
    // A changed or removed function the map does not list has no machine code in any test binary, so it
    // runs only at compile time (a table filled by a container-level const, a comptime helper, a
    // type-returning function) or nowhere. Its change reaches the file's code as a change outside the
    // functions does (the compile-time rule of the plan's section 7).
    var unmapped: ?[]const u8 = null;
    for (comparison.items) |item| {
        if (item.reason == .added) continue;
        const key = try functionKey(arena, path, item.name, item.ordinal);
        const id = map.id_of.get(key) orelse {
            if (unmapped == null and !options.without.unmapped) unmapped = item.name;
            continue;
        };
        const reason = try std.fmt.allocPrint(arena, "{s} {s}", .{ @tagName(item.reason), item.name });
        try impact(arena, analysis, id, reason);
    }
    const outside: ?[]const u8 = if (unmapped) |name|
        try std.fmt.allocPrint(arena, "unmapped function {s}", .{name})
    else if (comparison.rest_changed and !options.without.outside)
        try std.fmt.allocPrint(arena, "outside the functions of {s}", .{path})
    else
        null;
    if (outside) |reason| {
        for (map.file_ids.get(path) orelse &.{}) |id| try impact(arena, analysis, id, reason);
        try impactImporters(arena, map, graph, options.importers, path, analysis, reason);
        // Rule 2: the functions of the importers of `path` are impacted, so a compile-time call of one of them, in a
        // container-level item of a file that imports it, makes that file a rest change too.
        if (!options.without.compile) {
            var seeds: std.ArrayList(CompileSeed) = .empty;
            try seeds.append(arena, .{ .file = path, .names = try functionNamesOf(arena, graph, path) });
            for (graph.importers.get(path) orelse &.{}) |importer| {
                try seeds.append(arena, .{ .file = importer, .names = try functionNamesOf(arena, graph, importer) });
            }
            const second = try std.fmt.allocPrint(arena, "compile-time call of a function impacted by a change outside the functions of {s}", .{path});
            for (try compileTimeFiles(arena, graph, seeds.items)) |file| try impactRest(arena, map, graph, options.importers, file, analysis, second);
        }
    }
}

/// The impact of a file whose code outside its functions changed: its functions and its importers, as rule 1 does it.
fn impactRest(arena: std.mem.Allocator, map: Map, graph: ImportGraph, mode: Importers, file: []const u8, analysis: *Analysis, reason: []const u8) !void {
    for (map.file_ids.get(file) orelse &.{}) |id| try impact(arena, analysis, id, reason);
    try impactImporters(arena, map, graph, mode, file, analysis, reason);
}

/// A changed function's name as a compile-time search looks for it: a file-level function when the working tree defines
/// it only at file level, otherwise (a container member, or a function the working tree no longer defines) a member,
/// which any qualifier reaches.
fn changedName(defined: []const reexport.Name, name: []const u8) reexport.Name {
    var top_level = false;
    for (defined) |candidate| {
        if (!std.mem.eql(u8, candidate.text, name)) continue;
        if (!candidate.top_level) return .{ .text = name, .top_level = false, .kind = .function };
        top_level = true;
    }
    return .{ .text = name, .top_level = top_level, .kind = .function };
}

/// The functions `path` defines in the working tree (mapped or not), or none when it is not in the graph.
fn functionNamesOf(arena: std.mem.Allocator, graph: ImportGraph, path: []const u8) ![]const reexport.Name {
    const text = graph.texts.get(path) orelse return &.{};
    return reexport.functionNames(arena, text);
}

/// Impact a changed file that is not Zig: an input a Zig file names, a declared test input, or nothing.
fn analyzeOther(arena: std.mem.Allocator, io: std.Io, options: Options, map: Map, graph: ImportGraph, analysis: *Analysis, change: Change) !void {
    const path = change.path;
    if (isEverythingFile(path)) {
        if (!options.without.build) analysis.everything = try std.fmt.allocPrint(arena, "build input {s}", .{path});
        return;
    }
    if (std.mem.startsWith(u8, path, guest_directory)) return analyzeGuestFile(arena, graph, analysis, change);
    var named_by: std.ArrayList([]const u8) = .empty;
    for (graph.sources) |source| {
        if (namesFile(source.text, path)) try named_by.append(arena, source.path);
    }
    for (named_by.items) |source_path| {
        const reason = try std.fmt.allocPrint(arena, "named by {s}", .{source_path});
        for (map.file_ids.get(source_path) orelse &.{}) |id| try impact(arena, analysis, id, reason);
        try impactImporters(arena, map, graph, options.importers, source_path, analysis, reason);
    }
    // A `src/` input that some Zig file names is covered by that file; the `src/` entry of the
    // declared lists would select every unit test for it, so it is not routed further.
    if (named_by.items.len == 0 and !guestIrrelevant(path)) {
        // No Zig file names it, so no coverage records a guest reading it: every guest file may depend on it.
        const reason = try std.fmt.allocPrint(arena, "unnamed guest input {s}", .{path});
        try selectAllGuests(arena, analysis, graph.guests, reason);
    }
    if (named_by.items.len != 0 and std.mem.startsWith(u8, path, "src/")) return;
    const lists = try declaredLists(arena, io, options.repo);
    var routed = false;
    for (root_lists, 0..) |list_name, root| {
        for (lists.get(list_name) orelse &.{}) |entry| {
            if (!entryMatches(entry, path)) continue;
            routed = true;
            if (analysis.root_all[root] == null) {
                analysis.root_all[root] = try std.fmt.allocPrint(arena, "declared input {s} of {s}", .{ path, root_names[root] });
            }
            break;
        }
    }
    if (!routed and named_by.items.len == 0) try analysis.unrouted.append(arena, path);
}

/// A repository directory that a Zig file opens with a literal path, and the file that opens it.
const Walk = struct { root: []const u8, path: []const u8 };

/// Every open call of the working tree whose directory argument is a literal repository-relative path. A test that
/// walks such a directory observes which files are in it, so a new file there reaches that test.
fn walksOf(arena: std.mem.Allocator, graph: ImportGraph) ![]const Walk {
    var walks: std.ArrayList(Walk) = .empty;
    for (graph.sources) |source| {
        var rest = source.text;
        while (std.mem.indexOf(u8, rest, "openDir(")) |at| {
            rest = rest[at + "openDir(".len ..];
            const comma = std.mem.indexOfScalar(u8, rest, ',') orelse break;
            var cursor = comma + 1;
            while (cursor < rest.len and rest[cursor] == ' ') cursor += 1;
            if (cursor >= rest.len or rest[cursor] != '"') continue;
            const close = std.mem.indexOfScalarPos(u8, rest, cursor + 1, '"') orelse break;
            // A literal followed by `,` is the whole argument; `"a" ++ b` or `"a"[0..]` is not a literal root.
            if (close + 1 >= rest.len or rest[close + 1] != ',') continue;
            const root = std.mem.trimEnd(u8, rest[cursor + 1 .. close], "/");
            if (root.len == 0 or root[0] == '/' or std.mem.indexOf(u8, root, "..") != null) continue;
            try walks.append(arena, .{ .root = root, .path = source.path });
        }
    }
    return walks.toOwnedSlice(arena);
}

/// Whether `path` is `root` or lies inside the directory `root`.
pub fn pathUnder(path: []const u8, root: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    return path.len == root.len or path[root.len] == '/';
}

/// Whether a test name belongs to one of the new files: the test runner names a test `basename.test.title`, where
/// the basename is the file's name without `.zig`. An old test with the same name is selected too (over-selection).
pub fn namedByNewFile(name: []const u8, paths: []const []const u8) bool {
    for (paths) |path| {
        if (!std.mem.endsWith(u8, path, ".zig")) continue;
        const stem = std.fs.path.basename(path)[0 .. std.fs.path.basename(path).len - ".zig".len];
        if (std.mem.startsWith(u8, name, stem) and std.mem.startsWith(u8, name[stem.len..], ".test.")) return true;
    }
    return false;
}

/// Rule 2, the new-file rule. A new `.zig` file has no map id, so its own functions impact nothing, and its tests are
/// new names that `--tests` selects. Old code reaches it only through a changed line of an importer, which that
/// importer's rules impact, or through a test that walks a repository directory the file is in: then the walking
/// file's functions and its importers are impacted, with the reason `walks DIR: FILE`.
fn impactNewFile(arena: std.mem.Allocator, options: Options, map: Map, graph: ImportGraph, walks: []const Walk, analysis: *Analysis, path: []const u8) !void {
    try analysis.new_files.append(arena, path);
    if (options.without.newfile) return;
    for (walks) |walk| {
        if (!pathUnder(path, walk.root) or std.mem.eql(u8, walk.path, path)) continue;
        const reason = try std.fmt.allocPrint(arena, "walks {s}: {s}", .{ walk.root, path });
        for (map.file_ids.get(walk.path) orelse &.{}) |id| try impact(arena, analysis, id, reason);
        try impactImporters(arena, map, graph, options.importers, walk.path, analysis, reason);
    }
}

/// Impact a single map function, keeping the first reason given.
fn impact(arena: std.mem.Allocator, analysis: *Analysis, id: u32, reason: []const u8) !void {
    const slot = try analysis.impacted.getOrPut(arena, id);
    if (!slot.found_existing) slot.value_ptr.* = reason;
}

/// A file and the names of its functions that a compile-time call may reach (`compileTimeFiles`).
const CompileSeed = struct { file: []const u8, names: []const reexport.Name };

/// The files a compile-time call of the functions `seeds` name reaches: a file whose compile-time item uses one of them
/// (calls a function, names a value), in the seed's own file or in an importer (a file-level name through the importer's
/// bindings of that file, a member through any value), and then the importers of that file, through the names each
/// file's tainted items define (`reexport.reach`). A bare alias (`const f = a.f;`) is no use, so it only carries the
/// name on. Each file is searched again only for the names of a file it has not seen, so the search ends on a cycle of
/// imports and its memory is bounded by files times names. The reached files are rest changes: the caller impacts them
/// as `impactRest` does.
fn compileTimeFiles(arena: std.mem.Allocator, graph: ImportGraph, seeds: []const CompileSeed) ![]const []const u8 {
    var reached: std.StringArrayHashMapUnmanaged(void) = .empty;
    var frontier: std.ArrayList(CompileSeed) = .empty;
    for (seeds) |seed| {
        const text = graph.texts.get(seed.file) orelse continue;
        const own = try reexport.reach(arena, text, seed.names, .own);
        if (own.compile_time) try reached.put(arena, seed.file, {});
        var names: std.ArrayList(reexport.Name) = .empty;
        try names.appendSlice(arena, seed.names);
        try names.appendSlice(arena, own.names);
        try frontier.append(arena, .{ .file = seed.file, .names = names.items });
    }
    var propagated: std.StringHashMapUnmanaged(std.StringHashMapUnmanaged(void)) = .empty;
    // Each importer's vocabulary, read once: a name it never spells is no reference in it, so it is not searched for
    // there (rule 2 seeds every function of a file and its importers, members included: tens of thousands of names).
    var vocabularies: std.StringHashMapUnmanaged(reexport.Set) = .empty;
    var defined_roots: std.StringHashMapUnmanaged(*reexport.Set) = .empty;
    var next: usize = 0;
    while (next < frontier.items.len) : (next += 1) {
        const current = frontier.items[next];
        for (graph.importers.get(current.file) orelse &.{}) |importer| {
            const text = graph.texts.get(importer) orelse continue;
            const slot = try propagated.getOrPut(arena, importer);
            if (!slot.found_existing) slot.value_ptr.* = .empty;
            const words = try vocabularies.getOrPut(arena, importer);
            if (!words.found_existing) words.value_ptr.* = try reexport.vocabulary(arena, text);
            var fresh: std.ArrayList(reexport.Name) = .empty;
            for (current.names) |candidate| {
                if (!words.value_ptr.contains(candidate.text)) continue;
                // Seen per defining file: the same name of another file is reached through other qualifiers.
                const seen = try std.fmt.allocPrint(arena, "{s}\x00{s}", .{ current.file, candidate.text });
                if (slot.value_ptr.contains(seen)) continue;
                try slot.value_ptr.put(arena, seen, {});
                try fresh.append(arena, candidate);
            }
            if (fresh.items.len == 0) continue;
            // A file that uses `usingnamespace` may name the file's items bare: then it is searched as their own file.
            // An importer whose import spelling does not resolve here is searched with every name as a member, which
            // any qualifier reaches.
            const literals = try importLiterals(arena, graph, importer, current.file);
            if (literals.len == 0) {
                for (fresh.items) |*name| name.top_level = false;
            }
            const roots = try definedRootsOf(arena, &defined_roots, importer, text);
            const scope: reexport.Scope = if (std.mem.indexOf(u8, text, "usingnamespace") != null)
                .own
            else
                .{ .imported = .{ .allowed = try reexport.qualifiers(arena, text, literals), .excluded = roots } };
            const found = try reexport.reach(arena, text, fresh.items, scope);
            if (found.compile_time) try reached.put(arena, importer, {});
            if (found.names.len > 0) try frontier.append(arena, .{ .file = importer, .names = found.names });
        }
    }
    return reached.keys();
}

/// The roots `importer` defines (`reexport.definedRoots`), read once per run.
fn definedRootsOf(arena: std.mem.Allocator, cache: *std.StringHashMapUnmanaged(*reexport.Set), importer: []const u8, text: []const u8) !*const reexport.Set {
    const slot = try cache.getOrPut(arena, importer);
    if (!slot.found_existing) {
        slot.value_ptr.* = try arena.create(reexport.Set);
        slot.value_ptr.*.* = try reexport.definedRoots(arena, text);
    }
    return slot.value_ptr.*;
}

/// Impact every map function of the files that import `path`: the direct importers (`direct`), every
/// importer transitively (`closure`), or the importers transitively through the files that re-export
/// something from the file they import (`reexport`, EC2's re-export rule: `reexports`).
fn impactImporters(arena: std.mem.Allocator, map: Map, graph: ImportGraph, mode: Importers, path: []const u8, analysis: *Analysis, reason: []const u8) !void {
    if (mode == .none) return;
    var frontier: std.ArrayList([]const u8) = .empty;
    var impacted: std.StringHashMapUnmanaged(void) = .empty;
    var expanded: std.StringHashMapUnmanaged(void) = .empty;
    try frontier.append(arena, path);
    try expanded.put(arena, path, {});
    var next: usize = 0;
    while (next < frontier.items.len) : (next += 1) {
        const current = frontier.items[next];
        for (graph.importers.get(current) orelse &.{}) |importer| {
            if (!impacted.contains(importer)) {
                try impacted.put(arena, importer, {});
                const importer_reason = try std.fmt.allocPrint(arena, "{s} (imported by {s})", .{ reason, importer });
                for (map.file_ids.get(importer) orelse &.{}) |id| try impact(arena, analysis, id, importer_reason);
            }
            // Only a file that re-exports `current` passes a change of `current` on to its own importers.
            if (mode == .reexport and !try reexportsTarget(arena, graph, importer, current)) continue;
            if (expanded.contains(importer)) continue;
            try expanded.put(arena, importer, {});
            try frontier.append(arena, importer);
        }
        if (mode == .direct) break;
    }
}

/// Whether `importer` re-exports something from `target`: one of its top-level items that is `pub`, or a
/// `usingnamespace`, is tainted by an import of `target` (`edit_check/reexport.zig`). An importer whose text
/// is not in the graph counts as a re-exporter.
fn reexportsTarget(arena: std.mem.Allocator, graph: ImportGraph, importer: []const u8, target: []const u8) !bool {
    const text = graph.texts.get(importer) orelse return true;
    return reexport.reexports(text, try importLiterals(arena, graph, importer, target));
}

/// The exact `@import("...")` spellings in `importer` that resolve to `target` (a path, or a named module).
fn importLiterals(arena: std.mem.Allocator, graph: ImportGraph, importer: []const u8, target: []const u8) ![]const []const u8 {
    const text = graph.texts.get(importer) orelse return &.{};
    const directory = std.fs.path.dirname(importer) orelse "";
    var literals: std.ArrayList([]const u8) = .empty;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "@import(\"")) |at| {
        rest = rest[at + "@import(\"".len ..];
        const close = std.mem.indexOfScalar(u8, rest, '"') orelse break;
        const literal = rest[0..close];
        const resolved: []const u8 = if (std.mem.endsWith(u8, literal, ".zig") or std.mem.endsWith(u8, literal, ".zon"))
            try normalize(arena, directory, literal)
        else
            (graph.named.get(literal) orelse "");
        if (std.mem.eql(u8, resolved, target)) try literals.append(arena, try std.fmt.allocPrint(arena, "@import(\"{s}\")", .{literal}));
        rest = rest[close..];
    }
    return literals.items;
}

/// Add the tests that ran the impacted ids, the unnamed sets they belong to, the whole roots and
/// the whole suite that were decided, and the tests that failed when they ran alone.
fn expandSelection(arena: std.mem.Allocator, map: Map, analysis: *Analysis) !void {
    for (map.unrecorded) |entry| {
        if (entry.name.len == 0) {
            for (root_names, 0..) |root, root_index| {
                if (!std.mem.eql(u8, root, entry.root) or analysis.root_all[root_index] != null) continue;
                analysis.root_all[root_index] = try std.fmt.allocPrint(arena, "unrecorded process in an unnamed block of {s}", .{root});
            }
            continue;
        }
        for (map.test_name, map.test_root) |candidate, test_root| {
            if (!std.mem.eql(u8, candidate, entry.name) or !std.mem.eql(u8, test_root, entry.root)) continue;
            const key = try selectionKey(arena, test_root, "named", candidate);
            if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, "unrecorded process");
        }
    }
    for (analysis.impacted.keys(), analysis.impacted.values()) |id, reason| {
        for (testsOf(map, id)) |index| {
            const key = try selectionKey(arena, map.test_root[index], "named", map.test_name[index]);
            if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, reason);
        }
        for (root_names, 0..) |root, root_index| {
            if (!containsId(map.unnamed[root_index], id)) continue;
            const key = try selectionKey(arena, root, "unnamed", "");
            if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, reason);
        }
    }
    for (root_names, 0..) |root, root_index| {
        const whole = analysis.everything orelse analysis.root_all[root_index] orelse continue;
        for (map.test_name, map.test_root) |name, test_root| {
            if (!std.mem.eql(u8, test_root, root)) continue;
            const key = try selectionKey(arena, root, "named", name);
            if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, whole);
        }
        const key = try selectionKey(arena, root, "unnamed", "");
        if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, whole);
    }
    for (map.failed) |name| {
        for (map.test_name, map.test_root) |candidate, test_root| {
            if (!std.mem.eql(u8, candidate, name)) continue;
            const key = try selectionKey(arena, test_root, "named", name);
            if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, "failed when run alone");
        }
    }
}

/// The tests of a function id, as indexes into the map's test list.
pub fn testsOf(map: Map, id: u32) []const u32 {
    return map.tests_flat[map.tests_start[id]..map.tests_start[id + 1]];
}

fn containsId(ids: []const u32, id: u32) bool {
    for (ids) |candidate| if (candidate == id) return true;
    return false;
}

/// Add the named tests a root's current binary has and the map does not: new tests are always selected.
fn addNewTests(arena: std.mem.Allocator, io: std.Io, directory: []const u8, map: Map, analysis: *Analysis) !void {
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (map.test_root, map.test_name) |root, name| try known.put(arena, try selectionKey(arena, root, "named", name), {});
    for (root_names, 0..) |root, root_index| {
        const path = try std.fmt.allocPrint(arena, "{s}/tests-{s}.json", .{ directory, root });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(64 << 20)) catch {
            try analysis.notes.append(arena, try std.fmt.allocPrint(arena, "no test list for {s} at {s}", .{ root, path }));
            continue;
        };
        const names = try std.json.parseFromSliceLeaky(std.json.Value, arena, bytes, .{});
        const guest = root_index == guest_root;
        for (names.array.items) |item| {
            const name = jsonString(item);
            if (!guest and std.mem.find(u8, name, ".test.") == null) continue;
            const key = try selectionKey(arena, root, "named", name);
            if (known.contains(key) and !namedByNewFile(name, analysis.new_files.items)) continue;
            const reason = if (guest) "new guest file" else "new test";
            if (!analysis.selected.contains(key)) try analysis.selected.put(arena, key, reason);
        }
    }
}

/// The declared input lists of `build_test_inputs.zig` that name a root: `unit`, `cli` and `core`.
fn declaredLists(arena: std.mem.Allocator, io: std.Io, repo: []const u8) !std.StringHashMapUnmanaged([]const []const u8) {
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, try joinPath(arena, repo, "build_test_inputs.zig"), arena, .limited(4 << 20));
    const text = try stripLineComments(arena, raw);
    var lists: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    for (root_lists) |name| try lists.put(arena, name, try listEntries(arena, text, name));
    return lists;
}

/// `text` with every `//` comment removed (up to the end of its line), so that a `;` in a comment cannot end a list.
fn stripLineComments(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const cut = std.mem.indexOf(u8, line, "//") orelse line.len;
        try out.appendSlice(arena, line[0..cut]);
        try out.append(arena, '\n');
    }
    return out.toOwnedSlice(arena);
}

/// The string entries of one `pub const NAME = ... ;` list. A list that concatenates `unit`
/// (`core = unit ++ ...`) includes the entries of `unit`.
fn listEntries(arena: std.mem.Allocator, text: []const u8, name: []const u8) ![]const []const u8 {
    const header = try std.fmt.allocPrint(arena, "pub const {s} = ", .{name});
    const start = std.mem.indexOf(u8, text, header) orelse return &.{};
    const body_start = start + header.len;
    const end = std.mem.indexOfScalarPos(u8, text, body_start, ';') orelse text.len;
    const body = text[body_start..end];
    var entries: std.ArrayList([]const u8) = .empty;
    var quoted = std.mem.splitScalar(u8, body, '"');
    var inside = false;
    while (quoted.next()) |piece| {
        if (inside) try entries.append(arena, piece);
        inside = !inside;
    }
    if (!std.mem.eql(u8, name, "unit") and std.mem.indexOf(u8, body, "unit ++") != null) {
        try entries.appendSlice(arena, try listEntries(arena, text, "unit"));
    }
    return entries.toOwnedSlice(arena);
}

/// Whether `text` names the repository file `path` in a string literal: the whole path, or a trailing part of
/// it that starts after a `/` of the path, such as `stdlib/sort.selka` for `src/stdlib/sort.selka`. A bare basename
/// inside other words does not count.
pub fn namesFile(text: []const u8, path: []const u8) bool {
    var start: usize = 0;
    while (start < path.len) {
        if (namesSuffix(text, path[start..])) return true;
        const slash = std.mem.indexOfScalarPos(u8, path, start, '/') orelse break;
        start = slash + 1;
    }
    return false;
}

fn namesSuffix(text: []const u8, suffix: []const u8) bool {
    var search: usize = 0;
    while (std.mem.indexOfPos(u8, text, search, suffix)) |at| {
        search = at + 1;
        const end = at + suffix.len;
        if (at == 0 or end >= text.len or text[end] != '"') continue;
        if (text[at - 1] == '"' or text[at - 1] == '/') return true;
    }
    return false;
}

/// Whether one declared entry (`dir/`, `dir/*.ext`, `dir/**/*.ext` or a file) names `path`.
pub fn entryMatches(entry: []const u8, path: []const u8) bool {
    if (std.mem.endsWith(u8, entry, "/")) return std.mem.startsWith(u8, path, entry);
    if (std.mem.indexOf(u8, entry, "**/*.")) |split| {
        const prefix = entry[0..split];
        const suffix = entry[split + "**/*".len ..];
        return std.mem.startsWith(u8, path, prefix) and std.mem.endsWith(u8, path, suffix);
    }
    if (std.mem.indexOf(u8, entry, "/*.")) |split| {
        const directory = entry[0..split];
        const suffix = entry[split + "/*".len ..];
        const path_directory = std.fs.path.dirname(path) orelse "";
        return std.mem.eql(u8, path_directory, directory) and std.mem.endsWith(u8, path, suffix);
    }
    return std.mem.eql(u8, entry, path);
}

/// A Zig source of the working tree.
const Source = struct { path: []const u8, text: []const u8 };

/// The Zig sources of the working tree and which files import which, and the guest test files (E2).
const ImportGraph = struct {
    sources: []const Source,
    /// Target path to the paths of the files that import it.
    importers: std.StringHashMapUnmanaged([]const []const u8),
    /// Path to its text, for the re-export check.
    texts: std.StringHashMapUnmanaged([]const u8),
    /// The named modules of `build.zig` (`@import("NAME")`) to their root files.
    named: std.StringHashMapUnmanaged([]const u8),
    /// The `.selka` files under `tests/lang` of the working tree, with their text.
    guests: []const Source,
};

fn importGraph(arena: std.mem.Allocator, io: std.Io, repo: []const u8) !ImportGraph {
    const listing = try git(arena, io, repo, &.{ "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.zig" });
    var sources: std.ArrayList(Source) = .empty;
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |path| {
        if (path.len == 0) continue;
        const text = std.Io.Dir.cwd().readFileAlloc(io, try joinPath(arena, repo, path), arena, .limited(64 << 20)) catch continue;
        try sources.append(arena, .{ .path = path, .text = text });
    }
    const named = try namedModules(arena, io, repo);
    var collected: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    for (sources.items) |source| {
        var rest = source.text;
        while (std.mem.indexOf(u8, rest, "@import(\"")) |at| {
            rest = rest[at + "@import(\"".len ..];
            const close = std.mem.indexOfScalar(u8, rest, '"') orelse break;
            const target = rest[0..close];
            const resolved = if (std.mem.endsWith(u8, target, ".zig") or std.mem.endsWith(u8, target, ".zon"))
                try normalize(arena, std.fs.path.dirname(source.path) orelse "", target)
            else
                named.get(target) orelse continue;
            const slot = try collected.getOrPut(arena, resolved);
            if (!slot.found_existing) slot.value_ptr.* = .empty;
            try slot.value_ptr.append(arena, source.path);
        }
    }
    var importers: std.StringHashMapUnmanaged([]const []const u8) = .empty;
    var iterator = collected.iterator();
    while (iterator.next()) |entry| try importers.put(arena, entry.key_ptr.*, try entry.value_ptr.toOwnedSlice(arena));
    var texts: std.StringHashMapUnmanaged([]const u8) = .empty;
    for (sources.items) |source| try texts.put(arena, source.path, source.text);
    return .{ .sources = sources.items, .importers = importers, .texts = texts, .named = named, .guests = try guestSources(arena, io, repo) };
}

/// The `.selka` files under `tests/lang` of the working tree (tracked or not), with their text.
fn guestSources(arena: std.mem.Allocator, io: std.Io, repo: []const u8) ![]const Source {
    const listing = try git(arena, io, repo, &.{ "ls-files", "--cached", "--others", "--exclude-standard", "--", "tests/lang" });
    var guests: std.ArrayList(Source) = .empty;
    var lines = std.mem.splitScalar(u8, listing, '\n');
    while (lines.next()) |path| {
        if (!std.mem.endsWith(u8, path, ".selka")) continue;
        const text = std.Io.Dir.cwd().readFileAlloc(io, try joinPath(arena, repo, path), arena, .limited(64 << 20)) catch continue;
        try guests.append(arena, .{ .path = path, .text = text });
    }
    return guests.items;
}

/// Named modules that `build.zig` adds with `addImport("NAME", VAR)`, resolved to the root source of VAR.
fn namedModules(arena: std.mem.Allocator, io: std.Io, repo: []const u8) !std.StringHashMapUnmanaged([]const u8) {
    const build = try std.Io.Dir.cwd().readFileAlloc(io, try joinPath(arena, repo, "build.zig"), arena, .limited(16 << 20));
    var names: std.StringHashMapUnmanaged([]const u8) = .empty;
    var rest = build;
    while (std.mem.indexOf(u8, rest, "addImport(\"")) |at| {
        rest = rest[at + "addImport(\"".len ..];
        const close = std.mem.indexOfScalar(u8, rest, '"') orelse break;
        const name = rest[0..close];
        const comma = std.mem.indexOfScalarPos(u8, rest, close, ',') orelse break;
        var cursor = comma + 1;
        while (cursor < rest.len and rest[cursor] == ' ') cursor += 1;
        const variable_start = cursor;
        while (cursor < rest.len and isIdentifierByte(rest[cursor])) cursor += 1;
        const variable = rest[variable_start..cursor];
        if (variable.len == 0 or names.contains(name)) continue;
        if (rootSourceOf(build, variable)) |path| try names.put(arena, name, path);
    }
    return names;
}

/// The `b.path("...")` root source of the first statement that assigns `variable`, or null.
fn rootSourceOf(build: []const u8, variable: []const u8) ?[]const u8 {
    const marker = "root_source_file = b.path(\"";
    var search: usize = 0;
    while (std.mem.indexOfPos(u8, build, search, variable)) |at| {
        search = at + variable.len;
        if (at > 0 and (isIdentifierByte(build[at - 1]) or build[at - 1] == '.')) continue;
        var after = at + variable.len;
        while (after < build.len and build[after] == ' ') after += 1;
        if (after >= build.len or build[after] != '=') continue;
        if (after + 1 < build.len and build[after + 1] == '=') continue;
        const statement_end = std.mem.indexOfScalarPos(u8, build, after, ';') orelse build.len;
        const field = std.mem.indexOfPos(u8, build[0..statement_end], after, marker) orelse continue;
        const path_start = field + marker.len;
        const path_end = std.mem.indexOfScalarPos(u8, build, path_start, '"') orelse continue;
        return build[path_start..path_end];
    }
    return null;
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// Join `repo` and a repository-relative path.
fn joinPath(arena: std.mem.Allocator, repo: []const u8, path: []const u8) ![]const u8 {
    return std.fs.path.join(arena, &.{ repo, path });
}

/// Resolve `target`, relative to `directory` (both repository-relative), removing `.` and `..` segments.
pub fn normalize(arena: std.mem.Allocator, directory: []const u8, target: []const u8) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.splitScalar(u8, directory, '/');
    while (pieces.next()) |piece| try pushPart(arena, &parts, piece);
    var targets = std.mem.splitScalar(u8, target, '/');
    while (targets.next()) |piece| try pushPart(arena, &parts, piece);
    return std.mem.join(arena, "/", parts.items);
}

fn pushPart(arena: std.mem.Allocator, parts: *std.ArrayList([]const u8), piece: []const u8) !void {
    if (piece.len == 0 or std.mem.eql(u8, piece, ".")) return;
    if (std.mem.eql(u8, piece, "..")) {
        if (parts.items.len != 0) _ = parts.pop();
        return;
    }
    try parts.append(arena, piece);
}

/// Print the analysis: a summary, every impacted id with its reason, and the selection file.
fn report(arena: std.mem.Allocator, io: std.Io, out: *std.Io.Writer, options: Options, map: Map, analysis: Analysis) !void {
    try out.print("edit-check-impact: map {s}{s}, working tree {s}\n", .{ map.commit, if (map.dirty) " (dirty)" else "", options.repo });
    if (map.dirty) try out.writeAll("note: the map was built from uncommitted sources; impacts are relative to its commit\n");
    if (options.base) |base| try out.print("note: compared with {s} (--base), not the map's commit\n", .{base});
    if (options.without.outside or options.without.newfile or options.without.build or options.without.unmapped) {
        try out.print("note: rules switched off (--without): outside={} newfile={} build={} unmapped={}\n", .{ options.without.outside, options.without.newfile, options.without.build, options.without.unmapped });
    }
    if (analysis.everything) |reason| try out.print("everything: {s}\n", .{reason});
    for (analysis.notes.items) |note| try out.print("note: {s}\n", .{note});
    for (analysis.impacted.keys(), analysis.impacted.values()) |id, reason| {
        try out.print("impact {s} {s}#{d} :: {s}\n", .{ map.file[id], map.name[id], map.ordinal[id], reason });
    }
    for (analysis.unrouted.items) |path| try out.print("unrouted {s} (no Zig test reads it)\n", .{path});
    var selected_named: [root_names.len]usize = @splat(0);
    var selected_unnamed: [root_names.len]bool = @splat(false);
    var new_named: [root_names.len]usize = @splat(0);
    var lines: std.ArrayList(u8) = .empty;
    // The guest files the map does not know are counted in the total, whatever selected them (a map with no guest root).
    var known_guests: std.StringHashMapUnmanaged(void) = .empty;
    for (map.test_root, map.test_name) |root, name| {
        if (std.mem.eql(u8, root, root_names[guest_root])) try known_guests.put(arena, name, {});
    }
    for (analysis.selected.keys(), analysis.selected.values()) |key, reason| {
        var fields = std.mem.splitScalar(u8, key, '\t');
        const root = fields.next() orelse continue;
        const kind = fields.next() orelse continue;
        const name = fields.next() orelse "";
        for (root_names, 0..) |candidate, index| {
            if (!std.mem.eql(u8, candidate, root)) continue;
            if (std.mem.eql(u8, kind, "unnamed")) {
                selected_unnamed[index] = true;
            } else {
                selected_named[index] += 1;
                if (index == guest_root) {
                    if (!known_guests.contains(name)) new_named[index] += 1;
                } else if (std.mem.startsWith(u8, reason, "new ")) new_named[index] += 1;
            }
        }
        try lines.appendSlice(arena, try std.fmt.allocPrint(arena, "{s}\t{s}\n", .{ key, reason }));
    }
    var total_named: [root_names.len]usize = @splat(0);
    for (map.test_root) |root| {
        for (root_names, 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate, root)) total_named[index] += 1;
        }
    }
    for (root_names, 0..) |root, index| {
        try out.print("selected {s}: {d} of {d} named tests{s}\n", .{
            root,
            selected_named[index],
            total_named[index] + new_named[index],
            if (selected_unnamed[index]) ", plus the unnamed blocks" else "",
        });
    }
    if (options.output.selection) |path| {
        var file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        var buffer: [16 * 1024]u8 = undefined;
        var writer = file.writer(io, &buffer);
        try writer.interface.writeAll(lines.items);
        try writer.interface.flush();
    }
}

test "declared entries match directories, globs and files" {
    try std.testing.expect(entryMatches("src/", "src/core/root.zig"));
    try std.testing.expect(entryMatches("selfhost/*.zig", "selfhost/main.zig"));
    try std.testing.expect(!entryMatches("selfhost/*.zig", "selfhost/components/x.zig"));
    try std.testing.expect(entryMatches("docs/**/*.md", "docs/tooling/fix.md"));
    try std.testing.expect(entryMatches("tests/lang/memo_cache.selka", "tests/lang/memo_cache.selka"));
    try std.testing.expect(!entryMatches("tests/lang/memo_cache.selka", "tests/lang/other.selka"));
}

test "relative imports resolve against the importing directory" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectEqualStrings("src/core/driver.zig", try normalize(arena, "src/core/sub", "../driver.zig"));
    try std.testing.expectEqualStrings("src/memo.zig", try normalize(arena, "src", "./memo.zig"));
}

test "a file is named only by a string literal ending in its path" {
    try std.testing.expect(namesFile("@embedFile(\"stdlib/sort.selka\")", "src/stdlib/sort.selka"));
    try std.testing.expect(namesFile("x = \"src/core/runtime/core_rt.c\"", "src/core/runtime/core_rt.c"));
    try std.testing.expect(!namesFile("const mysort.selka = 1;", "src/stdlib/sort.selka"));
    try std.testing.expect(!namesFile("// sort.selka is discussed here", "src/stdlib/sort.selka"));
}

test "a named module resolves to the root source of the variable that defines it" {
    const build =
        \\const budget = b.createModule(.{ .root_source_file = b.path("src/memory_budget.zig") });
        \\unit.root_module.addImport("memory_budget", budget);
        \\const core = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("src/core/root.zig") }) });
        \\core.root_module.addImport("selka_core", core.root_module);
    ;
    try std.testing.expectEqualStrings("src/memory_budget.zig", rootSourceOf(build, "budget").?);
    try std.testing.expectEqualStrings("src/core/root.zig", rootSourceOf(build, "core").?);
    try std.testing.expect(rootSourceOf(build, "missing") == null);
}

test "declared lists include unit inside core and ignore semicolons in comments" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const raw =
        \\pub const unit = [_][]const u8{
        \\    "src/", // a comment; with a semicolon
        \\    "test/fixtures/",
        \\};
        \\pub const core = unit ++ [_][]const u8{ "test/", "tests/" };
    ;
    const text = try stripLineComments(arena, raw);
    const core = try listEntries(arena, text, "core");
    try std.testing.expectEqual(@as(usize, 4), core.len);
    try std.testing.expectEqualStrings("test/", core[0]);
    try std.testing.expectEqualStrings("tests/", core[1]);
    try std.testing.expectEqualStrings("src/", core[2]);
    try std.testing.expectEqualStrings("test/fixtures/", core[3]);
}

test "a module is mentioned as a whole word" {
    try std.testing.expect(mentionsModule("import helper\n", "helper"));
    try std.testing.expect(mentionsModule("dep.value()\n", "dep"));
    try std.testing.expect(!mentionsModule("import helpers\n", "helper"));
    try std.testing.expect(!mentionsModule("import my_helper\n", "helper"));
    try std.testing.expectEqualStrings("helper_two", moduleStem("tests/lang/helper_two.selka"));
}

test "guest files that import a changed module are selected, through the modules they import" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const guests = [_]Source{
        .{ .path = "tests/lang/a_test.selka", .text = "import helper_one\n\npublic func test_a() -> bool:\n    return true\n" },
        .{ .path = "tests/lang/b_test.selka", .text = "import helper_two\n\npublic func test_b() -> bool:\n    return true\n" },
        .{ .path = "tests/lang/c_test.selka", .text = "import strings\n\npublic func test_c() -> bool:\n    return true\n" },
        .{ .path = "tests/lang/helper_one.selka", .text = "import helper_two\n" },
        .{ .path = "tests/lang/helper_two.selka", .text = "public func value() -> int:\n    return 1\n" },
    };
    var analysis: Analysis = .{};
    const selected = try selectImporters(arena, &analysis, &guests, "tests/lang/helper_two.selka");
    try std.testing.expectEqual(@as(usize, 3), selected);
    try std.testing.expect(analysis.selected.contains("guests\tnamed\ttests/lang/a_test.selka"));
    try std.testing.expect(analysis.selected.contains("guests\tnamed\ttests/lang/b_test.selka"));
    try std.testing.expect(!analysis.selected.contains("guests\tnamed\ttests/lang/c_test.selka"));
}

test "guest-irrelevant files are documentation and tool trees, never a test program's input" {
    try std.testing.expect(guestIrrelevant("docs/tooling/fix.md"));
    try std.testing.expect(guestIrrelevant("scripts/edit_check.py"));
    try std.testing.expect(guestIrrelevant("CHANGES.md"));
    try std.testing.expect(!guestIrrelevant("src/stdlib/strings.selka"));
    try std.testing.expect(!guestIrrelevant("test/core/fixture.c"));
    try std.testing.expect(!guestIrrelevant("tests/lang/README.md"));
    try std.testing.expect(selectsEveryGuest("src/core/runtime/core_rt.c"));
    try std.testing.expect(selectsEveryGuest("selfhost/components.zig"));
    try std.testing.expect(!selectsEveryGuest("src/sema.zig"));
}

test "the report counts a selected guest file the map does not know in the total" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map: Map = .{
        .commit = "0123456",
        .dirty = false,
        .file = try arena.dupe([]const u8, &.{"src/a.zig"}),
        .name = try arena.dupe([]const u8, &.{"f"}),
        .ordinal = try arena.dupe(u32, &.{0}),
        .test_root = try arena.dupe([]const u8, &.{ "guests", "guests" }),
        .test_name = try arena.dupe([]const u8, &.{ "tests/lang/x.selka", "tests/lang/y.selka" }),
        .test_ids = &.{},
        .tests_start = try arena.dupe(u32, &.{ 0, 1 }),
        .tests_flat = try arena.dupe(u32, &.{0}),
        .failed = &.{},
    };
    var analysis: Analysis = .{};
    try analysis.impacted.put(arena, 0, "changed f");
    try analysis.selected.put(arena, "guests\tnamed\ttests/lang/z.selka", "build input build.zig");
    try expandSelection(arena, map, &analysis);
    var out: std.Io.Writer.Allocating = .init(arena);
    try report(arena, std.testing.io, &out.writer, .{ .map = "", .repo = "." }, map, analysis);
    try std.testing.expect(std.mem.indexOf(u8, out.written(), "selected guests: 2 of 3 named tests") != null);
}

test "a guest file is selected by name when it executed an impacted function" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map: Map = .{
        .commit = "0123456",
        .dirty = false,
        .file = try arena.dupe([]const u8, &.{"src/a.zig"}),
        .name = try arena.dupe([]const u8, &.{"f"}),
        .ordinal = try arena.dupe(u32, &.{0}),
        .test_root = try arena.dupe([]const u8, &.{ "guests", "guests" }),
        .test_name = try arena.dupe([]const u8, &.{ "tests/lang/x.selka", "tests/lang/y.selka" }),
        .test_ids = &.{},
        .tests_start = try arena.dupe(u32, &.{ 0, 1 }),
        .tests_flat = try arena.dupe(u32, &.{0}),
        .failed = &.{},
    };
    var analysis: Analysis = .{};
    try analysis.impacted.put(arena, 0, "changed f");
    try expandSelection(arena, map, &analysis);
    try std.testing.expect(analysis.selected.contains("guests\tnamed\ttests/lang/x.selka"));
    try std.testing.expect(!analysis.selected.contains("guests\tnamed\ttests/lang/y.selka"));
}

test "the measurement options parse, and an unknown rule name is a usage error" {
    const parsed = try parseArgs(&.{ "edit-check-impact", "--map", "m.json", "--base", "abc123", "--without", "outside,build" });
    try std.testing.expectEqualStrings("abc123", parsed.base.?);
    try std.testing.expect(parsed.without.outside);
    try std.testing.expect(!parsed.without.newfile);
    try std.testing.expect(parsed.without.build);
    try std.testing.expectError(error.Usage, parseArgs(&.{ "edit-check-impact", "--map", "m.json", "--without", "rule9" }));
}

test "the importers mode defaults to reexport" {
    const parsed = try parseArgs(&.{ "edit-check-impact", "--map", "m.json" });
    try std.testing.expectEqual(Importers.reexport, parsed.importers);
}

/// Run `git` in `repo` with a fixed author, failing the test on a non-zero exit.
fn gitIn(repo: []const u8, arguments: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(std.testing.allocator);
    try argv.appendSlice(std.testing.allocator, &.{ "git", "-C", repo, "-c", "user.name=edit-check", "-c", "user.email=edit-check@example.invalid" });
    try argv.appendSlice(std.testing.allocator, arguments);
    const result = try std.process.run(std.testing.allocator, std.testing.io, .{ .argv = argv.items });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

/// A map of one function, `f` in `a.zig`, that no test runs, built at `commit`.
fn oneFunctionMap(arena: std.mem.Allocator, commit: []const u8) !Map {
    var map: Map = .{
        .commit = commit,
        .dirty = false,
        .file = try arena.dupe([]const u8, &.{"a.zig"}),
        .name = try arena.dupe([]const u8, &.{"f"}),
        .ordinal = try arena.dupe(u32, &.{0}),
        .test_root = try arena.alloc([]const u8, 0),
        .test_name = try arena.alloc([]const u8, 0),
        .test_ids = try arena.alloc([]u32, 0),
        .tests_start = try arena.dupe(u32, &.{ 0, 0 }),
        .tests_flat = try arena.alloc(u32, 0),
        .failed = &.{},
    };
    try map.id_of.put(arena, try functionKey(arena, "a.zig", "f", 0), 0);
    try map.file_ids.put(arena, "a.zig", &.{0});
    return map;
}

test "--base replays an older edit, and --without switches rule 1 off" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "const k = 1;\nfn f() u32 { return k; }\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "const k = 2;\nfn f() u32 { return k; }\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try oneFunctionMap(arena, "HEAD");
    // The map's commit is the working tree, so nothing changed.
    const unchanged = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo }, map);
    try std.testing.expectEqual(@as(usize, 0), unchanged.impacted.count());
    // Replayed against HEAD~1 the constant's edit is outside every function: rule 1 impacts `f`.
    const replayed = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expectEqual(@as(usize, 1), replayed.impacted.count());
    // With rule 1 switched off the same replay impacts nothing.
    const without = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .without = .{ .outside = true } }, map);
    try std.testing.expectEqual(@as(usize, 0), without.impacted.count());
}

/// A map of one file whose functions `names` (each ordinal 0) are listed, each run by one unit test named `t_NAME`.
fn fixtureMap(arena: std.mem.Allocator, commit: []const u8, file: []const u8, names: []const []const u8) !Map {
    var map: Map = .{
        .commit = commit,
        .dirty = false,
        .file = try arena.alloc([]const u8, names.len),
        .name = try arena.dupe([]const u8, names),
        .ordinal = try arena.alloc(u32, names.len),
        .test_root = try arena.alloc([]const u8, names.len),
        .test_name = try arena.alloc([]const u8, names.len),
        .test_ids = try arena.alloc([]u32, names.len),
        .tests_start = try arena.alloc(u32, names.len + 1),
        .tests_flat = try arena.alloc(u32, names.len),
        .failed = &.{},
    };
    const ids = try arena.alloc(u32, names.len);
    for (names, 0..) |name, index| {
        const id: u32 = @intCast(index);
        ids[index] = id;
        map.file[index] = file;
        map.ordinal[index] = 0;
        map.test_root[index] = "units";
        map.test_name[index] = try std.fmt.allocPrint(arena, "t_{s}", .{name});
        map.test_ids[index] = try arena.dupe(u32, &.{id});
        map.tests_start[index] = id;
        map.tests_flat[index] = id;
        try map.id_of.put(arena, try functionKey(arena, file, name, 0), id);
    }
    map.tests_start[names.len] = @intCast(names.len);
    try map.file_ids.put(arena, file, ids);
    return map;
}

/// Commit a repository at `repo` in two commits: `one` has `table` and `use`, `two` edits `table` only.
fn unmappedRepo(temp: *std.testing.TmpDir, repo: []const u8) !void {
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "fn table() u32 { return 1; }\nfn use() u32 { return 2; }\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "fn table() u32 { return 3; }\nfn use() u32 { return 2; }\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });
}

test "a changed function the map does not list impacts its file: it runs at compile time" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try unmappedRepo(&temp, repo);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // The map lists `use` and its test, not `table`: `table` has no machine code (it fills a table at compile time).
    const map = try fixtureMap(arena, "HEAD", "a.zig", &.{"use"});
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expectEqual(@as(usize, 1), analysis.impacted.count());
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_use")));
    try std.testing.expectEqualStrings("unmapped function table", analysis.impacted.values()[0]);
}

/// Commit a repository in two commits: `one` has the chain `a.zig` (`pub const LIMIT`), `b.zig` (`b.L`, a
/// constant of `b` that reads `a.LIMIT`), and `c.zig` (`h` returns `b.L`); `two` edits `LIMIT` only.
fn twoHopRepo(temp: *std.testing.TmpDir, repo: []const u8, middle: []const u8) !void {
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub const LIMIT = 4;\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "b.zig", .data = middle });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "c.zig", .data = "const b = @import(\"b.zig\");\npub fn h() u32 {\n    return b.L;\n}\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub const LIMIT = 5;\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });
}

test "a re-exported constant reaches the importer's importer: the re-export rule selects its function, the direct rule does not" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try twoHopRepo(&temp, repo, "const a = @import(\"a.zig\");\npub const L = a.LIMIT * 2;\n");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMap(arena, "HEAD", "c.zig", &.{"h"});
    const direct = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .importers = .direct }, map);
    try std.testing.expectEqual(@as(usize, 0), direct.impacted.count());
    const reexported = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .importers = .reexport }, map);
    try std.testing.expectEqual(@as(usize, 1), reexported.impacted.count());
    try std.testing.expect(reexported.selected.contains(try selectionKey(arena, "units", "named", "t_h")));
    try std.testing.expectEqualStrings("outside the functions of a.zig (imported by c.zig)", reexported.impacted.values()[0]);
}

test "an importer's importer is not reached through a file whose public items do not use the constant" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try twoHopRepo(&temp, repo, "const a = @import(\"a.zig\");\nfn g() u32 {\n    return a.LIMIT * 2;\n}\npub const K = 7;\n");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMap(arena, "HEAD", "c.zig", &.{"h"});
    // `g` is private and `K` is public but unrelated to `a`: `b.zig` re-exports nothing, so `h` is not impacted.
    const reexported = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .importers = .reexport }, map);
    try std.testing.expectEqual(@as(usize, 0), reexported.impacted.count());
    const closure = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .importers = .closure }, map);
    try std.testing.expectEqual(@as(usize, 1), closure.impacted.count());
}

/// A map of several files: `names[i]` is a function (ordinal 0) of `files[i]`, run by one unit test named `t_NAME`.
fn fixtureMapFiles(arena: std.mem.Allocator, commit: []const u8, files: []const []const u8, names: []const []const u8) !Map {
    var map: Map = .{
        .commit = commit,
        .dirty = false,
        .file = try arena.alloc([]const u8, names.len),
        .name = try arena.dupe([]const u8, names),
        .ordinal = try arena.alloc(u32, names.len),
        .test_root = try arena.alloc([]const u8, names.len),
        .test_name = try arena.alloc([]const u8, names.len),
        .test_ids = try arena.alloc([]u32, names.len),
        .tests_start = try arena.alloc(u32, names.len + 1),
        .tests_flat = try arena.alloc(u32, names.len),
        .failed = &.{},
    };
    var per_file: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty;
    for (names, files, 0..) |name, file, index| {
        const id: u32 = @intCast(index);
        map.file[index] = file;
        map.ordinal[index] = 0;
        map.test_root[index] = "units";
        map.test_name[index] = try std.fmt.allocPrint(arena, "t_{s}", .{name});
        map.test_ids[index] = try arena.dupe(u32, &.{id});
        map.tests_start[index] = id;
        map.tests_flat[index] = id;
        try map.id_of.put(arena, try functionKey(arena, file, name, 0), id);
        const slot = try per_file.getOrPut(arena, file);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(arena, id);
    }
    map.tests_start[names.len] = @intCast(names.len);
    var iterator = per_file.iterator();
    while (iterator.next()) |entry| try map.file_ids.put(arena, entry.key_ptr.*, try entry.value_ptr.toOwnedSlice(arena));
    return map;
}

/// Commit a repository in two commits: `one` has `a.zig` (`pub fn f`, adding 1), `b.zig` (`middle`) and `c.zig` (`h`
/// returns `b.L`, or calls `b.g()` when `middle` has no `L`); `two` changes `f` to add 2.
fn compileTimeRepo(temp: *std.testing.TmpDir, repo: []const u8, middle: []const u8, caller: []const u8) !void {
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub fn f(x: u32) u32 {\n    return x + 1;\n}\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "b.zig", .data = middle });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "c.zig", .data = caller });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub fn f(x: u32) u32 {\n    return x + 2;\n}\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });
}

test "a changed function that a container-level constant of an importer calls at compile time reaches the constant's importer" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try compileTimeRepo(&temp, repo, "const a = @import(\"a.zig\");\npub const L = a.f(2);\n", "const b = @import(\"b.zig\");\npub fn h() u32 {\n    return b.L;\n}\n");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMapFiles(arena, "HEAD", &.{ "a.zig", "c.zig" }, &.{ "f", "h" });
    // `f`'s own test is selected by its id, and `h`'s by the constant `b.L` that calls `f` at compile time.
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_f")));
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_h")));
    // Measured without the rule (`--without compile`), `h` is missed: the miss this rule closes.
    const without = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .without = .{ .compile = true } }, map);
    try std.testing.expect(!without.selected.contains(try selectionKey(arena, "units", "named", "t_h")));
}

test "a changed function only called from function bodies adds no compile-time reach" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try compileTimeRepo(&temp, repo, "const a = @import(\"a.zig\");\npub fn g() u32 {\n    return a.f(2);\n}\n", "const b = @import(\"b.zig\");\npub fn h() u32 {\n    return b.g();\n}\n");
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMapFiles(arena, "HEAD", &.{ "a.zig", "c.zig" }, &.{ "f", "h" });
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expectEqual(@as(usize, 1), analysis.impacted.count());
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_f")));
    try std.testing.expect(!analysis.selected.contains(try selectionKey(arena, "units", "named", "t_h")));
}

test "a compile-time call of a function that a change outside functions impacts reaches the caller's file (rule 2)" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    // a.zig's constant changes; b.zig's public function g reads it (no re-export), and c.zig calls g at compile time.
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub const LIMIT = 4;\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "b.zig", .data = "const a = @import(\"a.zig\");\npub fn g() u32 {\n    return a.LIMIT * 2;\n}\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "c.zig", .data = "const b = @import(\"b.zig\");\nconst X = b.g();\npub fn h() u32 {\n    return X;\n}\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub const LIMIT = 5;\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMapFiles(arena, "HEAD", &.{ "b.zig", "c.zig" }, &.{ "g", "h" });
    for ([_]Importers{ .direct, .reexport }) |mode| {
        const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .importers = mode }, map);
        try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_h")));
    }
}

test "a function only aliased at container level and called at run time adds no file" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub fn f() u32 {\n    return 1;\n}\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "b.zig", .data = "const a = @import(\"a.zig\");\npub const g = a.f;\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "c.zig", .data = "const b = @import(\"b.zig\");\npub fn h() u32 {\n    return b.g();\n}\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "pub fn f() u32 {\n    return 2;\n}\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMapFiles(arena, "HEAD", &.{ "a.zig", "c.zig" }, &.{ "f", "h" });
    // `b.g` is a bare alias of `a.f`: `b.zig` calls nothing at compile time, and `c.zig`'s call is at run time (its
    // test runs `f` and is in the map). Only `f` itself is impacted.
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expectEqual(@as(usize, 1), analysis.impacted.count());
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_f")));
}

test "the compile-time search ends on a cycle of imports and reaches each file once per name" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "const b = @import(\"b.zig\");\npub fn f() u32 {\n    return 1;\n}\npub const K = b.L;\n" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "b.zig", .data = "const a = @import(\"a.zig\");\npub const L = a.f();\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "const b = @import(\"b.zig\");\npub fn f() u32 {\n    return 2;\n}\npub const K = b.L;\n" });
    try gitIn(repo, &.{ "commit", "-q", "-am", "two" });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMapFiles(arena, "HEAD", &.{ "a.zig", "b.zig" }, &.{ "f", "g" });
    // `f` changes, `b.L` calls it at compile time, and `a.K` names `b.L` back: the search must end, and `f` is selected.
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_f")));
}

test "a test that started a process with no hit set is selected whatever the edit" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "fn f() u32 {\n    return 1;\n}\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var map = try fixtureMap(arena, "HEAD", "a.zig", &.{"f"});
    map.unrecorded = &.{ .{ .root = "units", .name = "t_f" }, .{ .root = "cli", .name = "" } };
    // Nothing changed, and no function is impacted: the two tests are selected by the list alone.
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo }, map);
    try std.testing.expectEqual(@as(usize, 0), analysis.impacted.count());
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_f")));
    try std.testing.expect(analysis.root_all[1] != null);
}

test "--without unmapped restores the skipped function, for measuring the rule's cost" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try unmappedRepo(&temp, repo);
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMap(arena, "HEAD", "a.zig", &.{"use"});
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .without = .{ .unmapped = true } }, map);
    try std.testing.expectEqual(@as(usize, 0), analysis.impacted.count());
    try std.testing.expect(!analysis.selected.contains(try selectionKey(arena, "units", "named", "t_use")));
}

test "a new Zig file selects nothing by itself: its tests are new names and it reaches code through its importers" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "a.zig", .data = "fn use() u32 { return 2; }\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "b.zig", .data = "fn helper() u32 { return 7; }\ntest \"helper\" {}\n" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "two" });

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMap(arena, "HEAD", "a.zig", &.{"use"});
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1" }, map);
    try std.testing.expect(analysis.everything == null);
    try std.testing.expectEqual(@as(usize, 0), analysis.impacted.count());
    try std.testing.expectEqual(@as(usize, 1), analysis.new_files.items.len);
    // `--new-files everything` (the rule before) selects everything for the same edit.
    const before = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .new_files = .everything }, map);
    try std.testing.expect(before.everything != null);
}

test "a new file's tests are the names its basename starts, and walked directories match whole components" {
    try std.testing.expect(pathUnder("src/core/x.zig", "src"));
    try std.testing.expect(!pathUnder("srcx/a.zig", "src"));
    try std.testing.expect(namedByNewFile("b.test.helper", &.{"src/b.zig"}));
    try std.testing.expect(!namedByNewFile("bb.test.helper", &.{"src/b.zig"}));
    const parsed = try parseArgs(&.{ "edit-check-impact", "--map", "m.json", "--new-files", "everything" });
    try std.testing.expect(parsed.new_files == .everything);
    try std.testing.expectError(error.Usage, parseArgs(&.{ "edit-check-impact", "--map", "m.json", "--new-files", "some" }));
}

test "the default new-file rule is reach, and --new-files parses both values" {
    const defaults: Options = .{ .map = "m.json", .repo = "." };
    try std.testing.expect(defaults.new_files == .reach);
    const reach = try parseArgs(&.{ "edit-check-impact", "--map", "m.json", "--new-files", "reach" });
    try std.testing.expect(reach.new_files == .reach);
    const everything = try parseArgs(&.{ "edit-check-impact", "--map", "m.json", "--new-files", "everything" });
    try std.testing.expect(everything.new_files == .everything);
}

test "a new file under a directory a test walks impacts the walking file" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const repo = try temp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(repo);
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "build.zig", .data = "" });
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "walker.zig", .data = "fn check() u32 { _ = std.Io.Dir.cwd().openDir(io, \"src\", .{}); return 1; }\n" });
    try gitIn(repo, &.{ "init", "-q" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "one" });
    try temp.dir.createDirPath(std.testing.io, "src");
    try temp.dir.writeFile(std.testing.io, .{ .sub_path = "src/n.zig", .data = "fn n() u32 { return 3; }\n" });
    try gitIn(repo, &.{ "add", "." });
    try gitIn(repo, &.{ "commit", "-q", "-m", "two" });

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const map = try fixtureMap(arena, "HEAD", "walker.zig", &.{"check"});
    const analysis = try analyze(arena, std.testing.io, .{ .map = "", .repo = repo, .base = "HEAD~1", .new_files = .reach }, map);
    try std.testing.expectEqual(@as(usize, 1), analysis.impacted.count());
    try std.testing.expectEqualStrings("walks src: src/n.zig", analysis.impacted.values()[0]);
    try std.testing.expect(analysis.selected.contains(try selectionKey(arena, "units", "named", "t_check")));
}
