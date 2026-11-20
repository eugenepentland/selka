//! Where the compiler keeps its stores and its temporary files, when a project's
//! `selka.json` says so (lane FR8, `experiments/audit-work-20261111/FR8.md`).
//!
//! Every store already takes its place from an environment variable
//! (`project_config.StorePlace.variable`). `apply` reads the `stores` object of the
//! command's project and sets each variable the caller's environment leaves unset,
//! in the command's own environment, before any store opens. So the precedence is
//! the one every reader already has: a flag, then the variable (set and empty still
//! decides: off), then the file, then the default; and a file never overrides what
//! the caller's environment says. The variables are placement
//! (`environment_identity.zon`), so no key moves with them.
//!
//! The variables the file set are named in `marker`, which the command's children
//! inherit with them: a child compiler (`selka test DIR` starts one per root) keeps
//! the decision its parent made, and `guestEnvironment` takes the file's variables out
//! again for a guest program, which sees the caller's environment unchanged.
const std = @import("std");
const product = @import("product.zig");
const config = @import("project_config.zig");
const shared = @import("shared_cache_policy.zig");

const Map = std.process.Environ.Map;
const Place = config.StorePlace;

/// Names the variables a project file set and the file, as
/// `names=XDG_CACHE_HOME,TMPDIR;file=/abs/selka.json` (`names=;file=` when the
/// command's project set none). Its presence means the decision is made.
pub const marker = "SELKA_STORE_SETTINGS";

/// What decided a place: the caller's environment, the project's file, or nothing.
pub const Origin = enum { environment, project, default };

/// Set, in `environ`, the variables the project of `target` (an entry or a
/// directory of entries) names in its `stores` object and the caller left unset,
/// make the temporary folder, and record the decision in `marker`. A project
/// that does not load is left to the command, which reports it as it does today.
/// Returns the rendered refusal of a store path, or null.
pub fn apply(allocator: std.mem.Allocator, io: std.Io, environ: *Map, target: []const u8) error{OutOfMemory}!?[]const u8 {
    if (environ.get(marker) != null) return null;
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(allocator);
    var file: []const u8 = "";
    const config_path = discover(allocator, io, target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    defer if (config_path) |path| allocator.free(path);
    var loaded: ?config.Config = null;
    if (config_path) |path| {
        var failure: config.Failure = .{};
        loaded = config.load(allocator, io, path, &failure) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
    }
    defer if (loaded) |*value| value.deinit();
    if (loaded) |*configured| {
        var stores = (config.storeSettings(allocator, configured.bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null) orelse config.Stores{};
        defer stores.deinit(allocator);
        file = configured.path;
        if (try decide(allocator, io, environ, configured.path, stores, &names)) |refusal| return refusal;
    }
    const value = try std.fmt.allocPrint(allocator, "names={s};file={s}", .{ names.items, if (names.items.len == 0) "" else file });
    defer allocator.free(value);
    try environ.put(marker, value);
    return null;
}

/// The refusal of the project file of `target` when it does not load, rendered as every command that reads the file
/// renders it (`project_entry.resolve`, `E_PROJECT_CONFIG` with the file, line and column); null when it loads or there
/// is none. `apply` leaves such a file to the command, so a command that reads nothing else (`selka cache where`) asks
/// here (FR18).
pub fn loadFailure(allocator: std.mem.Allocator, io: std.Io, target: []const u8) error{OutOfMemory}!?[]const u8 {
    const config_path = discover(allocator, io, target) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else null;
    const path = config_path orelse return null;
    defer allocator.free(path);
    var failure: config.Failure = .{};
    var loaded = config.load(allocator, io, path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const message = try std.fmt.allocPrint(allocator, "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: {s}\n", .{ failure.path, failure.location.line, failure.location.column, failure.detail });
            return message;
        },
    };
    loaded.deinit();
    return null;
}

/// The nearest `selka.json` of an entry, or of a directory of entries.
fn discover(allocator: std.mem.Allocator, io: std.Io, target: []const u8) config.Error!?[]const u8 {
    const stat = std.Io.Dir.cwd().statFile(io, target, .{}) catch return config.discover(allocator, io, target);
    if (stat.kind == .directory) return config.discoverDirectory(allocator, io, target);
    return config.discover(allocator, io, target);
}

/// Check every path the file names and set the variables of those the caller left unset.
fn decide(allocator: std.mem.Allocator, io: std.Io, environ: *Map, config_path: []const u8, stores: config.Stores, names: *std.ArrayList(u8)) error{OutOfMemory}!?[]const u8 {
    const project = std.fs.path.dirname(config_path) orelse ".";
    for (stores.values, 0..) |value, index| {
        const place: Place = @fromBackingInt(@intCast(index));
        const location = stores.locations[index];
        const resolved: []const u8 = switch (value) {
            .unset => continue,
            .off => "",
            .path => |text| expand(allocator, environ, project, text) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.NoHome => {
                    const message = try refuse(allocator, config_path, location, place, "starts with ~/ but HOME is not an absolute path");
                    return message;
                },
            },
        };
        if (value == .path and place.holdsRecords() and try inside(allocator, io, resolved, project)) {
            const message = try refuse(allocator, config_path, location, place, "lies inside the project that names it; a store must be outside the directory that holds selka.json");
            return message;
        }
        if (environ.get(place.variable()) != null) continue;
        if (place == .temporary) std.Io.Dir.cwd().createDirPath(io, resolved) catch {
            const message = try refuse(allocator, config_path, location, place, "names a folder that cannot be created");
            return message;
        };
        try environ.put(place.variable(), resolved);
        if (names.items.len != 0) try names.append(allocator, ',');
        try names.appendSlice(allocator, place.variable());
    }
    return null;
}

fn refuse(allocator: std.mem.Allocator, config_path: []const u8, location: config.Location, place: Place, why: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}:{d}:{d}: error[E_PROJECT_CONFIG]: stores.{s} {s}\n", .{ config_path, location.line, location.column, @tagName(place), why });
}

/// A path as the file spells it, made absolute: `~/` is `HOME`, an absolute path
/// is itself, and anything else is relative to the directory holding `selka.json`.
pub fn expand(allocator: std.mem.Allocator, environ: *const Map, project: []const u8, text: []const u8) error{ OutOfMemory, NoHome }![]const u8 {
    if (std.mem.startsWith(u8, text, "~/")) {
        const home = environ.get("HOME") orelse return error.NoHome;
        if (!std.fs.path.isAbsolute(home)) return error.NoHome;
        return std.fs.path.resolve(allocator, &.{ home, text[2..] });
    }
    return std.fs.path.resolve(allocator, &.{ project, text });
}

/// Whether `path` is `project` or lies beneath it, judged on real paths: the
/// longest existing prefix of `path` is resolved, so a symbolic link cannot hide
/// a folder of the project behind a name outside it.
fn inside(allocator: std.mem.Allocator, io: std.Io, path: []const u8, project: []const u8) error{OutOfMemory}!bool {
    const cwd = std.Io.Dir.cwd();
    const real_project = cwd.realPathFileAlloc(io, project, allocator) catch try allocator.dupe(u8, project);
    defer allocator.free(real_project);
    var existing = path;
    var rest: []const u8 = "";
    const real = while (true) {
        if (cwd.realPathFileAlloc(io, existing, allocator)) |found| break found else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
        const parent = std.fs.path.dirname(existing) orelse break try allocator.dupe(u8, existing);
        rest = std.mem.trimStart(u8, path[parent.len..], "/");
        existing = parent;
    };
    defer allocator.free(real);
    const whole = try std.fs.path.resolve(allocator, &.{ real, rest });
    defer allocator.free(whole);
    if (std.mem.eql(u8, whole, real_project)) return true;
    return whole.len > real_project.len and std.mem.startsWith(u8, whole, real_project) and whole[real_project.len] == std.fs.path.sep;
}

/// Take the variables the project file set, and `marker`, out of `guest`: the
/// environment a guest program or a test process starts with, copied from the
/// command's. What remains is the caller's environment as it was.
pub fn guestEnvironment(guest: *Map) void {
    const recorded = guest.get(marker) orelse return;
    var names = std.mem.splitScalar(u8, namesOf(recorded), ',');
    while (names.next()) |name| {
        if (name.len != 0) _ = guest.swapRemove(name);
    }
    _ = guest.swapRemove(marker);
}

fn namesOf(recorded: []const u8) []const u8 {
    const start = if (std.mem.startsWith(u8, recorded, "names=")) "names=".len else return "";
    const end = std.mem.indexOfScalarPos(u8, recorded, start, ';') orelse recorded.len;
    return recorded[start..end];
}

/// The configuration file `marker` names, or "".
fn fileOf(recorded: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, recorded, ";file=") orelse return "";
    return recorded[at + ";file=".len ..];
}

/// What decided the variable `name` in `environ`, and the file when it was the project's.
fn originOf(environ: *const Map, name: []const u8) struct { origin: Origin, file: []const u8 } {
    if (environ.get(name) == null) return .{ .origin = .default, .file = "" };
    const recorded = environ.get(marker) orelse return .{ .origin = .environment, .file = "" };
    var names = std.mem.splitScalar(u8, namesOf(recorded), ',');
    while (names.next()) |listed| if (std.mem.eql(u8, listed, name)) return .{ .origin = .project, .file = fileOf(recorded) };
    return .{ .origin = .environment, .file = "" };
}

/// The per-user object store a build uses: `SELKA_CORE_RUNTIME_CACHE` (empty: none,
/// the objects stay in the work directory), else `$XDG_CACHE_HOME/selka/core-runtime`
/// when that is absolute, else `$HOME/.cache/selka/core-runtime`, else none.
pub fn objectStore(allocator: std.mem.Allocator, environ: *const Map) error{OutOfMemory}!?[]const u8 {
    if (environ.get("SELKA_CORE_RUNTIME_CACHE")) |explicit| return if (explicit.len == 0) null else explicit;
    if (environ.get("XDG_CACHE_HOME")) |base| if (std.fs.path.isAbsolute(base)) {
        const directory = try std.fs.path.join(allocator, &.{ base, product.user_dir, "core-runtime" });
        return directory;
    };
    const home = environ.get("HOME") orelse return null;
    if (!std.fs.path.isAbsolute(home)) return null;
    const directory = try std.fs.path.join(allocator, &.{ home, ".cache", product.user_dir, "core-runtime" });
    return directory;
}

/// One line per place, for `selka cache where`: the place, where it resolved
/// ("off" for a store turned off), and what decided it. A place that the file and
/// the environment leave unset but that lies under `cache_home` says so.
pub fn describe(allocator: std.mem.Allocator, environ: *const Map) error{OutOfMemory}![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (std.enums.values(Place)) |place| {
        const resolved: ?[]const u8 = switch (place) {
            .cache_home => cacheHome(allocator, environ),
            .objects => try objectStore(allocator, environ),
            .compiler, .stages, .tests => if (try shared.resolve(allocator, environ, tierOf(place), null)) |selection| selection.path else null,
            .temporary => if (environ.get("TMPDIR")) |value| (if (value.len == 0) "/tmp" else value) else "/tmp",
        };
        const own = originOf(environ, place.variable());
        const decided = if (own.origin != .default or place == .cache_home or place == .temporary) own else originOf(environ, Place.cache_home.variable());
        const under = own.origin == .default and place != .cache_home and place != .temporary;
        try out.print(allocator, "{s:<11} {s}  (", .{ @tagName(place), resolved orelse "off" });
        if (under) try out.appendSlice(allocator, "under cache_home, ");
        switch (decided.origin) {
            .environment => try out.print(allocator, "environment {s}", .{if (under) Place.cache_home.variable() else place.variable()}),
            .project => try out.print(allocator, "selka.json {s}", .{decided.file}),
            .default => try out.appendSlice(allocator, "default"),
        }
        try out.appendSlice(allocator, ")\n");
    }
    return out.toOwnedSlice(allocator);
}

fn tierOf(place: Place) shared.Tier {
    return switch (place) {
        .compiler => .compiler,
        .stages => .stages,
        else => .tests,
    };
}

/// `XDG_CACHE_HOME` when it is absolute, else `$HOME/.cache`; null without either (`selka packages` keeps its stages
/// under it too).
pub fn cacheHome(allocator: std.mem.Allocator, environ: *const Map) ?[]const u8 {
    if (environ.get("XDG_CACHE_HOME")) |base| if (std.fs.path.isAbsolute(base)) return base;
    const home = environ.get("HOME") orelse return null;
    if (!std.fs.path.isAbsolute(home)) return null;
    return std.fs.path.join(allocator, &.{ home, ".cache" }) catch null;
}

// FR8: the decision a project file makes, the precedence, and the guest's environment.
test "project stores: a project's stores fill only the variables the caller left unset, and a guest sees the caller's environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.createDirPath(io, "project");
    try temporary.dir.writeFile(io, .{ .sub_path = "project/main.selka", .data = "func main() -> int:\n    return 0\n" });
    const json = try std.fmt.allocPrint(a, "{{\"version\": 1, \"stores\": {{\"cache_home\": \"{s}/xdg\", \"objects\": \"~/objects\", \"compiler\": false, \"stages\": \"{s}/stages\", \"temporary\": \"../tmp\"}}}}", .{ root, root });
    try temporary.dir.writeFile(io, .{ .sub_path = "project/selka.json", .data = json });
    const entry = try std.fs.path.join(a, &.{ root, "project", "main.selka" });
    var environ: Map = .init(a);
    try environ.put("HOME", try std.fs.path.join(a, &.{ root, "home" }));
    try environ.put("SELKA_STAGE_SHARED_CACHE", "");
    try std.testing.expect(try apply(a, io, &environ, entry) == null);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "xdg" }), environ.get("XDG_CACHE_HOME").?);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "home", "objects" }), environ.get("SELKA_CORE_RUNTIME_CACHE").?);
    try std.testing.expectEqualStrings("", environ.get("SELKA_COMPILER_SHARED_CACHE").?);
    // The caller's empty variable decides: the file's stage store is not used.
    try std.testing.expectEqualStrings("", environ.get("SELKA_STAGE_SHARED_CACHE").?);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "tmp" }), environ.get("TMPDIR").?);
    try temporary.dir.access(io, "tmp", .{});
    try std.testing.expect(environ.get("SELKA_TEST_SHARED_CACHE") == null);
    const described = try describe(a, &environ);
    try std.testing.expect(std.mem.indexOf(u8, described, "stages      off  (environment SELKA_STAGE_SHARED_CACHE)") != null);
    try std.testing.expect(std.mem.indexOf(u8, described, "compiler    off  (selka.json ") != null);
    try std.testing.expect(std.mem.indexOf(u8, described, "tests       ") != null);
    // A second decision in the same environment (a child compiler) keeps the first.
    try environ.put("XDG_CACHE_HOME", "/elsewhere");
    try std.testing.expect(try apply(a, io, &environ, entry) == null);
    try std.testing.expectEqualStrings("/elsewhere", environ.get("XDG_CACHE_HOME").?);
    var guest = try environ.clone(a);
    guestEnvironment(&guest);
    try std.testing.expect(guest.get("XDG_CACHE_HOME") == null);
    try std.testing.expect(guest.get("TMPDIR") == null);
    try std.testing.expect(guest.get(marker) == null);
    try std.testing.expectEqualStrings("", guest.get("SELKA_STAGE_SHARED_CACHE").?);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "home" }), guest.get("HOME").?);
}

// FR8: a store the project's own checkout could supply is refused, through a symbolic link too.
test "project stores: a store inside the project that names it is refused with its location" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.createDirPath(io, "project/stores");
    try temporary.dir.symLink(io, try std.fs.path.join(a, &.{ root, "project", "stores" }), "outside", .{ .is_directory = true });
    const json = try std.fmt.allocPrint(a, "{{\"version\": 1,\n \"stores\": {{\"objects\": \"{s}/outside/objects\"}}}}", .{root});
    try temporary.dir.writeFile(io, .{ .sub_path = "project/selka.json", .data = json });
    var environ: Map = .init(a);
    const refusal = (try apply(a, io, &environ, try std.fs.path.join(a, &.{ root, "project" }))).?;
    try std.testing.expect(std.mem.indexOf(u8, refusal, "selka.json:2:") != null);
    try std.testing.expect(std.mem.indexOf(u8, refusal, "error[E_PROJECT_CONFIG]: stores.objects lies inside the project") != null);
    try std.testing.expect(environ.get("SELKA_CORE_RUNTIME_CACHE") == null);
    // A project without a stores object decides nothing, and says so.
    try temporary.dir.writeFile(io, .{ .sub_path = "project/selka.json", .data = "{\"version\": 1}" });
    try std.testing.expect(try apply(a, io, &environ, try std.fs.path.join(a, &.{ root, "project" })) == null);
    try std.testing.expectEqualStrings("names=;file=", environ.get(marker).?);
    try std.testing.expectEqual(@as(usize, 1), environ.count());
}

// spec: STORE-WHERE-REFUSE-1
// FR18: a file the commands refuse is refused by `loadFailure` with the words `project_entry.resolve` prints.
test "project stores: a relative store makes the file fail to load, rendered with its file, line and column" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.createDirPath(io, "project");
    try temporary.dir.writeFile(io, .{ .sub_path = "project/selka.json", .data = "{\"version\": 1,\n \"stores\": {\"cache_home\": \"stores\"}}" });
    const project = try std.fs.path.join(a, &.{ root, "project" });
    const refusal = (try loadFailure(a, io, project)).?;
    try std.testing.expect(std.mem.startsWith(u8, refusal, try std.fs.path.join(a, &.{ project, "selka.json:2:" })));
    try std.testing.expect(std.mem.indexOf(u8, refusal, ": error[E_PROJECT_CONFIG]: a store must lie outside the project") != null);
    // A file that loads, and a directory with none, refuse nothing.
    try temporary.dir.writeFile(io, .{ .sub_path = "project/selka.json", .data = "{\"version\": 1}" });
    try std.testing.expect(try loadFailure(a, io, project) == null);
    try std.testing.expect(try loadFailure(a, io, try std.fs.path.join(a, &.{ root, "missing" })) == null);
}
