//! `selka packages lock|build`: offline local dependencies from explicit
//! namespaces and content-locked files.
//!
//! `lock CONFIG --output LOCK` reads `{"packages":[{"name":...,"root":...}]}`,
//! resolves each root, inventories its `.selka` sources with one SHA-256 each and
//! writes a `package-lock-v1` file. `build ENTRY --lock LOCK` re-inventories the
//! application directory and every locked package, refuses drift, collisions,
//! reserved names and symbolic links, copies the verified bytes into a private
//! staging directory, and runs this same executable's `project-dependencies`
//! and then one project command (`check-project` by default) over the staged
//! entry, so neither the application tree nor a shared checkout is ever compiled
//! in place. `build` and `test` (FR4) stage into a directory kept per
//! application, so their caches replay an unchanged snapshot. `fix ENTRY --lock
//! LOCK` verifies and stages the same way, runs `selka fix` over the staged
//! application (never a package's file) and copies back each application file it
//! changed, when that file still holds the bytes it was staged from. This replaced the
//! Python prototype `scripts/packages.py`; the lock and receipt formats are
//! unchanged.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// Format tag of the lock `lock` writes and `build` requires.
const lock_version = "package-lock-v1";
/// Format tag of the receipt `build --receipt` writes.
const receipt_version = "package-build-v1";
/// Most source bytes one inventory, one staged snapshot or one lock may hold.
const package_byte_budget: usize = 16 * 1024 * 1024;
/// Most directory entries one inventory walk may visit.
const max_entries: usize = 50_000;
/// Project commands `build --command` may run over the staged snapshot.
const commands = [_][]const u8{ "check-project", "run-project", "index-project", "build", "test", "api" };
/// Suffix of an entry's own cases file (`<stem>.cases.json`), which `test` stages beside its entry.
const cases_suffix = ".cases.json";
/// Suffix of a module's interface file (`<stem>.api`), which a snapshot of an application that sets `interface_files` holds beside it.
const interface_suffix = ".api";
/// The directory under the per-user cache that holds the kept stages of `build` and `test`.
const kept_stages = "packages-v1";
/// Refusal for a file that could not be opened, stated or read.
const unreadable = "cannot read {s}: {t}";
/// Refusal for a lock that is not a `package-lock-v1` document.
const unsupported_lock = "unsupported package lock: {s}";
/// Module source file suffix; nothing else is inventoried.
const source_suffix = product.source_suffix;
/// Prefix reserved for the standard modules the compiler embeds.
const reserved_prefix = "std_";
/// Where the per-user cache is (`cacheHome`), which holds the kept stages.
const store_settings = @import("compiler_root").compiler_language.store_settings;
/// The warnings display the staged command is told the locked packages through (`packages_option`).
const warning_display = @import("compiler_root").compiler_language.warning_display;
/// The embedded standard modules, whose names no package may take.
const standard_library = @import("compiler_root").compiler_language.standard_library;
/// The command-line parser `run-project` reads its options with, which says which word of a line it refuses.
const cli_args = @import("selka_core").cli_args;
/// The `selka fix` that `fix` runs over the staged application.
const fix_command = @import("fix_command.zig");
/// The project configuration copied into the staged snapshot.
const project_config = @import("compiler_root").compiler_language.project_config;
/// A package's devices: the files the lock records for each, and their staged copies.
const package_devices = @import("package_devices.zig");
const config_name = project_config.config_name;
/// The folders a walk leaves out, which `selka test DIR` leaves out too.
const release_project = @import("compiler_root").compiler_language.release_project;

/// Usage text for `selka packages --help` and a malformed command line.
const usage =
    \\usage: selka packages lock CONFIG.json --output LOCK.json
    \\       selka packages build ENTRY.selka|DIR --lock LOCK.json [--command check-project|run-project|index-project|build|test|api] [--receipt FILE] [-- FLAGS...]
    \\       selka packages fix ENTRY.selka|DIR --lock LOCK.json [--check] [--warnings] [--imports] [--report] [--diagnostics=text|json] [--no-cache]
    \\  lock inventories every package root CONFIG names ({"packages":[{"name":...,"root":...}]}) and
    \\  writes each module's SHA-256 into a package-lock-v1 file. build verifies the application
    \\  directory and every locked package against it, stages the verified bytes privately, and runs
    \\  project-dependencies and then the command over the staged entry; --receipt records the lock
    \\  and compiler identities with the dependency report. The command's exit status is forwarded
    \\  (for run-project, the program's own). A rejected lock or snapshot exits 2.
    \\  FLAGS go to the command after the staged entry: --command build -- -o BIN [--release ...] builds
    \\  a binary, --command test [-- --filter S --json ...] runs the tests of ENTRY.selka or of every entry
    \\  under DIR; both link the allowed packages' C and keep their stage, so an unchanged build replays.
    \\  --command api -- --write|--check [--json] runs `selka api` over the staged application; --write
    \\  copies the application's interface files back (a package's modules need none: the lock pins them).
    \\  fix verifies and stages as build does and runs `selka fix` with its own switches over the staged
    \\  application: it repairs the application's files only (a repair that edits a package's file is left
    \\  and counted) and writes back each file it changed, refusing one that changed since it was staged.
    \\
;

/// Failures a package command reports: a rejection whose message the session
/// holds, a malformed command line, or exhausted memory.
const Error = error{ Rejected, Usage, OutOfMemory };

/// One command invocation's allocator, I/O and the message of its rejection.
const Session = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    message: []const u8 = "",
    /// Every path staged so far, relative to the staging directory: what a kept stage keeps.
    placed: std.StringHashMapUnmanaged(void) = .empty,

    /// Record why the command refuses, for `run` to print, and fail.
    fn reject(self: *Session, comptime format: []const u8, arguments: anytype) error{Rejected} {
        self.message = std.fmt.allocPrint(self.allocator, format, arguments) catch "out of memory";
        return error.Rejected;
    }
};

/// One inventoried module: its path relative to the source root, `/`-separated,
/// and the lowercase hexadecimal SHA-256 of its bytes.
const Module = struct { path: []const u8, digest: []const u8 };
/// One C source a `selka.json` lists in `links`: its spelling there, its resolved path and its SHA-256.
const Link = struct { spelled: []const u8, path: []const u8, digest: []const u8 };
/// One verified source root, its sorted modules, the C sources its `selka.json` links, and its devices: null when
/// the lock records none of them (a lock written before it recorded a package's devices), so none was checked.
const Inventory = struct {
    root: []const u8,
    modules: []const Module,
    links: []const Link = &.{},
    name: []const u8 = "",
    devices: ?[]const package_devices.Device = null,
};
/// The parsed command line of either subcommand.
const Request = struct {
    positional: ?[]const u8 = null,
    output: ?[]const u8 = null,
    lock: ?[]const u8 = null,
    command: ?[]const u8 = null,
    receipt: ?[]const u8 = null,
    /// Every word after `--`, for the command; null without `--`.
    forwarded: ?[]const []const u8 = null,
};

/// Run `selka packages ARGS`, returning the process exit status. `identity` is
/// this compiler's own `compiler_sha256`, which the dependency report of the
/// staged snapshot must carry and the receipt records.
pub fn run(process: std.process.Init, args: []const []const u8, identity: []const u8) u8 {
    var session: Session = .{ .allocator = process.arena.allocator(), .io = process.io };
    return dispatch(&session, process, args, identity) catch |err| switch (err) {
        error.Rejected => report(process.io, session.allocator, session.message),
        error.OutOfMemory => report(process.io, session.allocator, "out of memory"),
        error.Usage => blk: {
            std.Io.File.stderr().writeStreamingAll(process.io, usage) catch break :blk 2;
            break :blk 2;
        },
    };
}

/// Print `packages: MESSAGE` on standard error and return the refusal status.
fn report(io: std.Io, allocator: std.mem.Allocator, message: []const u8) u8 {
    const line = std.fmt.allocPrint(allocator, "packages: {s}\n", .{message}) catch "packages: out of memory\n";
    std.Io.File.stderr().writeStreamingAll(io, line) catch return 2;
    return 2;
}

fn dispatch(session: *Session, process: std.process.Init, args: []const []const u8, identity: []const u8) Error!u8 {
    if (args.len == 1 and (std.mem.eql(u8, args[0], "--help") or std.mem.eql(u8, args[0], "-h"))) {
        std.Io.File.stdout().writeStreamingAll(process.io, usage) catch return 2;
        return 0;
    }
    if (args.len == 0) return error.Usage;
    if (std.mem.eql(u8, args[0], "fix")) return fixApplication(session, process, try parseFix(session.allocator, args[1..]));
    const request = try parse(args[1..]);
    const positional = request.positional orelse return error.Usage;
    if (std.mem.eql(u8, args[0], "lock")) {
        if (request.lock != null or request.command != null or request.receipt != null or request.forwarded != null) return error.Usage;
        try lock(session, positional, request.output orelse return error.Usage);
        return 0;
    }
    if (std.mem.eql(u8, args[0], "build")) {
        if (request.output != null) return error.Usage;
        const command = request.command orelse commands[0];
        if (!known(command)) return error.Usage;
        if (std.mem.eql(u8, command, "run-project")) try refuseStrayWord(session, request, positional);
        return build(session, process, .{
            .positional = positional,
            .lock = request.lock orelse return error.Usage,
            .command = command,
            .receipt = request.receipt,
            .forwarded = request.forwarded orelse &.{},
            .directory = try isDirectory(session, positional),
        }, identity);
    }
    return error.Usage;
}

/// Parse `--output`, `--lock`, `--command` and `--receipt` (each as `--flag
/// VALUE` or `--flag=VALUE`, at most once) around exactly one positional; every
/// word after `--` is the command's.
fn parse(args: []const []const u8) error{Usage}!Request {
    var request: Request = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) {
            request.forwarded = args[index + 1 ..];
            break;
        }
        if (!std.mem.startsWith(u8, arg, "--")) {
            if (request.positional != null) return error.Usage;
            request.positional = arg;
            continue;
        }
        const equals = std.mem.indexOfScalar(u8, arg, '=');
        const name = arg[0 .. equals orelse arg.len];
        const value = if (equals) |at| arg[at + 1 ..] else value: {
            index += 1;
            if (index >= args.len) return error.Usage;
            break :value args[index];
        };
        if (value.len == 0) return error.Usage;
        const slot: *?[]const u8 = if (std.mem.eql(u8, name, "--output"))
            &request.output
        else if (std.mem.eql(u8, name, "--lock"))
            &request.lock
        else if (std.mem.eql(u8, name, "--command"))
            &request.command
        else if (std.mem.eql(u8, name, "--receipt"))
            &request.receipt
        else
            return error.Usage;
        if (slot.* != null) return error.Usage;
        slot.* = value;
    }
    return request;
}

/// Whether the positional names a directory: `test` runs every entry under it.
fn isDirectory(session: *Session, positional: []const u8) Error!bool {
    const info = std.Io.Dir.cwd().statFile(session.io, positional, .{}) catch return false;
    return info.kind == .directory;
}

fn known(command: []const u8) bool {
    for (commands) |candidate| if (std.mem.eql(u8, candidate, command)) return true;
    return false;
}

/// `build --command run-project -- WORDS` hands WORDS to `selka run-project` as its options, and the program's own arguments need a
/// second `--`. A word that the command would refuse (a second file, an option it does not know) is named here, with the line that has
/// the second `--` before it, where the command alone would print its usage. Every other usage error is left to the command.
fn refuseStrayWord(session: *Session, request: Request, positional: []const u8) Error!void {
    const forwarded = request.forwarded orelse return;
    const allocator = session.allocator;
    const entry = [_][]const u8{"entry.selka"};
    const words = try std.mem.concat(allocator, []const u8, &.{ &entry, forwarded });
    var failure: cli_args.Failure = .usage;
    _ = cli_args.parse(allocator, .run, words, "zig", &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Usage => switch (failure) {
            // The staged command takes these two out of its line before it reads the rest (`warning_display.begin`).
            .refused => |at| if (at > 0 and !withheld(forwarded[at - 1])) return refusedWord(session, request, positional, at - 1),
            else => {},
        },
    };
}

/// Whether the staged command takes `word` out of its line before reading its options.
fn withheld(word: []const u8) bool {
    return std.mem.eql(u8, word, warning_display.packages_option) or std.mem.eql(u8, word, warning_display.package_fix_option);
}

/// The refusal that names `forwarded[at]` and shows the command line again with a second `--` before it.
fn refusedWord(session: *Session, request: Request, positional: []const u8, at: usize) Error {
    const allocator = session.allocator;
    const forwarded = request.forwarded.?;
    var line: std.ArrayList([]const u8) = .empty;
    try line.appendSlice(allocator, &.{ "selka", "packages", "build", positional, "--lock", request.lock.?, "--command", "run-project" });
    if (request.receipt) |receipt| try line.appendSlice(allocator, &.{ "--receipt", receipt });
    try line.append(allocator, "--");
    try line.appendSlice(allocator, forwarded[0..at]);
    try line.append(allocator, "--");
    try line.appendSlice(allocator, forwarded[at..]);
    var shown: std.ArrayList(u8) = .empty;
    for (line.items, 0..) |word, index| {
        if (index != 0) try shown.append(allocator, ' ');
        try shown.appendSlice(allocator, try shellWord(allocator, word));
    }
    return session.reject("`{s}` follows the first `--`, so run-project was given it as one of its own options and refused it; the program's own arguments follow a second `--`:\n  {s}", .{ forwarded[at], shown.items });
}

/// `word` as a shell would take it: bare when it holds only plain characters, else in single quotes.
fn shellWord(allocator: std.mem.Allocator, word: []const u8) error{OutOfMemory}![]const u8 {
    plain: {
        if (word.len == 0) break :plain;
        for (word) |character| if (!std.ascii.isAlphanumeric(character) and std.mem.indexOfScalar(u8, "_-./=:,@%+", character) == null) break :plain;
        return word;
    }
    return std.fmt.allocPrint(allocator, "'{s}'", .{try std.mem.replaceOwned(u8, allocator, word, "'", "'\\''")});
}

/// A package namespace: an ASCII identifier that does not start with the
/// reserved standard-module prefix.
fn validNamespace(name: []const u8) bool {
    if (name.len == 0 or std.mem.startsWith(u8, name, reserved_prefix)) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    for (name[1..]) |character| if (!std.ascii.isAlphanumeric(character) and character != '_') return false;
    return true;
}

/// Whether a module path belongs to package `name`: `name.selka` itself or any
/// source under `name/`.
fn inNamespace(name: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, name)) return false;
    const rest = path[name.len..];
    return std.mem.eql(u8, rest, source_suffix) or (rest.len > 0 and rest[0] == '/');
}

/// Whether a relative path names its parent directory anywhere.
fn climbs(path: []const u8) bool {
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "..")) return true;
    return false;
}

fn hexDigest(allocator: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![]const u8 {
    var digest: [32]u8 = undefined;
    Sha256.hash(bytes, &digest, .{});
    return allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// Read one regular file of at most `limit` bytes without following a symbolic
/// link at its last component; `shown` names it in a refusal.
fn boundedRead(session: *Session, directory: std.Io.Dir, sub_path: []const u8, shown: []const u8, limit: usize) Error![]const u8 {
    const io = session.io;
    const file = directory.openFile(io, sub_path, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.SymLinkLoop => return session.reject("symbolic-link sources are rejected: {s}", .{shown}),
        else => return session.reject(unreadable, .{ shown, err }),
    };
    defer file.close(io);
    const info = file.stat(io) catch |err| return session.reject(unreadable, .{ shown, err });
    if (info.kind != .file) return session.reject("{s} is not a regular file", .{shown});
    if (info.size > limit) return session.reject("{s} exceeds the {d}-byte source budget", .{ shown, package_byte_budget });
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(session.allocator, .limited(limit + 1)) catch |err| switch (err) {
        error.StreamTooLong => session.reject("{s} grew beyond the {d}-byte source budget", .{ shown, package_byte_budget }),
        error.OutOfMemory => error.OutOfMemory,
        else => session.reject(unreadable, .{ shown, err }),
    };
}

/// Whether a walked entry is a module source to inventory. A symbolic link named
/// like a source, one that leads to a directory, and a source that is not a
/// regular file are refused; every other entry is skipped.
fn sourceEntry(session: *Session, entry: std.Io.Dir.Walker.Entry) Error!bool {
    const named = std.mem.endsWith(u8, entry.basename, source_suffix);
    switch (entry.kind) {
        .directory => return false,
        .file => return named,
        .sym_link => {
            if (named) return session.reject("symbolic-link sources are rejected: {s}", .{entry.path});
            const target = entry.dir.statFile(session.io, entry.basename, .{}) catch return false;
            if (target.kind == .directory) return session.reject("symbolic-link directories are rejected: {s}", .{entry.path});
            return false;
        },
        else => {
            if (named) return session.reject("{s} is not a regular file", .{entry.path});
            return false;
        },
    }
}

/// Whether a walked entry is a regular `<stem>.cases.json` file.
fn casesEntry(entry: std.Io.Dir.Walker.Entry) bool {
    return entry.kind == .file and std.mem.endsWith(u8, entry.basename, cases_suffix);
}

/// Whether a walked entry is a regular `<stem>.api` interface file.
fn interfaceEntry(entry: std.Io.Dir.Walker.Entry) bool {
    return entry.kind == .file and std.mem.endsWith(u8, entry.basename, interface_suffix);
}

fn byPath(_: void, left: Module, right: Module) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

/// Every `.selka` source under `root`, sorted by path, with its SHA-256. The walk
/// visits at most `max_entries` entries and reads at most `package_byte_budget` bytes.
fn sources(session: *Session, root: []const u8) Error![]const Module {
    return inventoryFiles(session, root, false, false, &.{});
}

/// The files of one inventory: `.selka` sources, and with `cases` each entry's `<stem>.cases.json` too (an application's,
/// for `test`; a package's inventory and its lock hold sources only), and with `interfaces` each `<stem>.api` interface file (an
/// application's, when its configuration sets `interface_files`). The walk leaves out what `selka test DIR` leaves out
/// (`release_project.walkSkips`: folders named `.*`, `build`, `zig-out` and `node_modules`, the `--cache-dir` folder among the
/// `forwarded` words, and the `release.exclude` of the project's `selka.json`), so a link to a folder, or a source, in one of them is
/// never looked at; `tmp/` and every other folder are walked, and a link to a folder in them is refused.
fn inventoryFiles(session: *Session, root: []const u8, cases: bool, interfaces: bool, forwarded: []const []const u8) Error![]const Module {
    const io = session.io;
    const allocator = session.allocator;
    const walk = try walkOf(session, root, forwarded);
    var directory = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch |err| return session.reject("cannot open {s}: {t}", .{ root, err });
    defer directory.close(io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    var modules: std.ArrayList(Module) = .empty;
    var visited: usize = 0;
    var total: usize = 0;
    while (walker.next(io) catch |err| return session.reject("cannot walk {s}: {t}", .{ root, err })) |entry| {
        visited += 1;
        if (visited > max_entries) return session.reject("the sources under {s} exceed the {d}-entry walk budget", .{ root, max_entries });
        if (try release_project.walkSkips(allocator, walk, entry.basename, try std.fs.path.join(allocator, &.{ root, entry.path }))) {
            if (entry.kind == .directory) walker.leave(io);
            continue;
        }
        const wanted = try sourceEntry(session, entry) or (cases and casesEntry(entry)) or (interfaces and interfaceEntry(entry));
        if (!wanted) continue;
        const bytes = try boundedRead(session, entry.dir, entry.basename, entry.path, package_byte_budget - total);
        total += bytes.len;
        try modules.append(allocator, .{ .path = try allocator.dupe(u8, entry.path), .digest = try hexDigest(allocator, bytes) });
    }
    std.mem.sort(Module, modules.items, {}, byPath);
    return modules.items;
}

/// What a walk of `root` leaves out, as a directory test run leaves it out: the `release.exclude` of the nearest `selka.json` (one that
/// cannot be loaded excludes nothing here; the staged command reports it) and the `--cache-dir` among the `forwarded` words. `root`
/// itself is walked whatever it is called, as a directory test run walks the folder it is named.
fn walkOf(session: *Session, root: []const u8, forwarded: []const []const u8) Error!release_project.Walk {
    const allocator = session.allocator;
    const working = std.Io.Dir.cwd().realPathFileAlloc(session.io, ".", allocator) catch |err| return session.reject("cannot resolve the working directory: {t}", .{err});
    var walk: release_project.Walk = .{ .project_root = root, .working = working, .named = root };
    if (try applicationConfig(session, root)) |path| {
        walk.project_root = std.fs.path.dirname(path) orelse root;
        var failure: project_config.Failure = .{};
        if (project_config.load(allocator, session.io, path, &failure)) |loaded| walk.exclusions = loaded.releaseOptions().exclude else |_| {}
    }
    for (forwarded, 0..) |word, index| {
        const given = if (std.mem.eql(u8, word, "--cache-dir") and index + 1 < forwarded.len) forwarded[index + 1] else if (std.mem.startsWith(u8, word, "--cache-dir=")) word["--cache-dir=".len..] else continue;
        walk.cache = std.Io.Dir.cwd().realPathFileAlloc(session.io, given, allocator) catch try std.fs.path.resolve(allocator, &.{ working, given });
    }
    return walk;
}

/// Resolve one package's root against `base` and inventory it: the namespace
/// must be valid, the root must exist and hold at least one source, and every
/// source must sit inside the namespace.
fn packageFiles(session: *Session, name: []const u8, root: []const u8, base: []const u8) Error!Inventory {
    if (!validNamespace(name)) return session.reject("invalid or reserved package namespace: {s}", .{name});
    if (standard_library.source(try std.fmt.allocPrint(session.allocator, "{s}{s}", .{ name, source_suffix })) != null) return session.reject(
        "package {s} is named like the standard module `{s}`, which `import {s}` always loads: the package's `{s}.selka` would never be used. " ++
            "Rename the package (its namespace and its `{s}.selka` and `{s}/` files) and lock again",
        .{ name, name, name, name, name, name },
    );
    const joined = if (std.fs.path.isAbsolute(root)) root else try std.fs.path.join(session.allocator, &.{ base, root });
    const resolved = std.Io.Dir.cwd().realPathFileAlloc(session.io, joined, session.allocator) catch |err|
        return session.reject("package {s}: cannot resolve root {s}: {t}", .{ name, joined, err });
    const modules = try sources(session, resolved);
    if (modules.len == 0) return session.reject("empty dependency: {s}", .{name});
    for (modules) |module| {
        if (!inNamespace(name, module.path)) return outsideNamespace(session, name, root, module.path);
    }
    return .{ .root = resolved, .modules = modules };
}

/// The refusal for a source of package `name` that is neither `name.selka` nor under `name/`: the file as the configuration spells its
/// root, the rule, where the file moves to and the import its users write once it has moved (`numbers.selka` becomes `import numbers`).
fn outsideNamespace(session: *Session, name: []const u8, root: []const u8, path: []const u8) Error {
    const allocator = session.allocator;
    const module = try std.mem.replaceOwned(u8, allocator, path[0 .. path.len - source_suffix.len], "/", ".");
    const here = try std.fs.path.join(allocator, &.{ root, path });
    const there = try std.fs.path.join(allocator, &.{ root, name, path });
    return session.reject("package {s}: {s} is neither {s}.selka nor under {s}/, and every module of a package is one of the two: move it to {s} and import it as `import {s}.{s}`", .{ name, here, name, name, there, name, module });
}

/// The string field `key` of a JSON object, or null.
fn stringField(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const field = value.object.get(key) orelse return null;
    return if (field == .string) field.string else null;
}

/// The `packages` array of a configuration or lock document, or null.
fn packageList(document: std.json.Value) ?[]const std.json.Value {
    if (document != .object) return null;
    const list = document.object.get("packages") orelse return null;
    return if (list == .array) list.array.items else null;
}

/// The directory holding `path`, resolved.
fn parentOf(session: *Session, path: []const u8) Error![]const u8 {
    const resolved = try resolvedPath(session, path);
    return std.fs.path.dirname(resolved) orelse resolved;
}

/// `path` resolved to an absolute path without symbolic links.
fn resolvedPath(session: *Session, path: []const u8) Error![]const u8 {
    return std.Io.Dir.cwd().realPathFileAlloc(session.io, path, session.allocator) catch |err|
        session.reject("cannot resolve {s}: {t}", .{ path, err });
}

fn parseJson(session: *Session, bytes: []const u8, shown: []const u8) Error!std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, session.allocator, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => session.reject("{s} is not JSON: {t}", .{ shown, err }),
    };
}

/// `selka packages lock CONFIG --output LOCK`.
fn lock(session: *Session, config_path: []const u8, output: []const u8) Error!void {
    const allocator = session.allocator;
    const text = std.Io.Dir.cwd().readFileAlloc(session.io, config_path, allocator, .limited(package_byte_budget)) catch |err|
        return session.reject(unreadable, .{ config_path, err });
    const document = try parseJson(session, text, config_path);
    const entries = packageList(document) orelse
        return session.reject("{s} must be {{\"packages\":[{{\"name\":...,\"root\":...}}]}}", .{config_path});
    const base = try parentOf(session, config_path);
    var names: std.StringHashMapUnmanaged(void) = .empty;
    var packages = std.json.Array.init(allocator);
    for (entries) |entry| {
        const name = stringField(entry, "name") orelse return session.reject("{s}: every package needs a string name and root", .{config_path});
        const root = stringField(entry, "root") orelse return session.reject("{s}: every package needs a string name and root", .{config_path});
        if ((try names.getOrPut(allocator, name)).found_existing) return session.reject("duplicate package namespace: {s}", .{name});
        const inventory = try packageFiles(session, name, root, base);
        var files: std.json.ObjectMap = .empty;
        for (inventory.modules) |module| try files.put(allocator, module.path, .{ .string = module.digest });
        var package: std.json.ObjectMap = .empty;
        try package.put(allocator, "name", .{ .string = name });
        try package.put(allocator, "root", .{ .string = inventory.root });
        try package.put(allocator, "files", .{ .object = files });
        // A package's own `selka.json` may list C sources; the lock pins each one's bytes (absent when it lists none).
        const links = try configLinks(session, inventory.root);
        if (links.len != 0) try package.put(allocator, "links", try lockedLinks(allocator, links));
        // So are the files its devices name, the same way (absent when it describes none).
        const devices = try packageDevices(session, inventory.root);
        if (devices.len != 0) try package.put(allocator, "devices", try package_devices.lockValue(allocator, devices));
        // And the description of a device that has one (`memory`, `place`, `stack`, `boot`, `hooks`), which names no file.
        if (try package_devices.descriptionsValue(allocator, devices)) |described| try package.put(allocator, "device_descriptions", described);
        try packages.append(.{ .object = package });
    }
    var manifest: std.json.ObjectMap = .empty;
    try manifest.put(allocator, "version", .{ .string = lock_version });
    try manifest.put(allocator, "packages", .{ .array = packages });
    try writeJson(session, output, .{ .object = manifest });
}

fn writeJson(session: *Session, path: []const u8, value: std.json.Value) Error!void {
    const rendered = try std.json.Stringify.valueAlloc(session.allocator, value, .{ .whitespace = .indent_2 });
    const text = try std.fmt.allocPrint(session.allocator, "{s}\n", .{rendered});
    std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = path, .data = text }) catch |err|
        return session.reject("cannot write {s}: {t}", .{ path, err });
}

/// What `build` was asked for, once the command line checked: `forwarded` holds the words after `--`, and `directory`
/// says that the positional is a directory (a `test` of every entry under it) rather than an entry.
const Build = struct {
    positional: []const u8,
    lock: []const u8,
    command: []const u8,
    receipt: ?[]const u8,
    forwarded: []const []const u8,
    directory: bool,
};

/// Whether a re-inventoried package still has exactly the locked files.
fn unchanged(modules: []const Module, files: std.json.Value) bool {
    if (files != .object or files.object.count() != modules.len) return false;
    for (modules) |module| {
        const locked = files.object.get(module.path) orelse return false;
        if (locked != .string or !std.mem.eql(u8, locked.string, module.digest)) return false;
    }
    return true;
}

/// The application inventory first, then every locked package re-inventoried
/// and compared with its lock entry.
fn verify(session: *Session, request: Build, document: std.json.Value) Error![]const Inventory {
    const allocator = session.allocator;
    const packages = packageList(document) orelse return session.reject(unsupported_lock, .{request.lock});
    const app_root = if (request.directory) try resolvedPath(session, request.positional) else try parentOf(session, request.positional);
    const interfaces = std.mem.eql(u8, request.command, "api") or try interfaceKey(session, app_root);
    const app = try inventoryFiles(session, app_root, std.mem.eql(u8, request.command, "test"), interfaces, request.forwarded);
    const entry_name = std.fs.path.basename(request.positional);
    if (!request.directory) for (app) |module| {
        if (std.mem.eql(u8, module.path, entry_name)) break;
    } else return session.reject("entry is absent from application source inventory: {s}", .{request.positional});
    var inventories: std.ArrayList(Inventory) = .empty;
    try inventories.append(allocator, .{ .root = app_root, .modules = app });
    const base = try parentOf(session, request.lock);
    var names: std.StringHashMapUnmanaged(void) = .empty;
    for (packages) |package| {
        const name = stringField(package, "name") orelse return session.reject(unsupported_lock, .{request.lock});
        const root = stringField(package, "root") orelse return session.reject(unsupported_lock, .{request.lock});
        if ((try names.getOrPut(allocator, name)).found_existing) return session.reject("duplicate or incompatible package namespace: {s}", .{name});
        const inventory = try packageFiles(session, name, root, base);
        if (!unchanged(inventory.modules, package.object.get("files") orelse .null)) return session.reject("locked dependency changed: {s}", .{name});
        const links = try configLinks(session, inventory.root);
        if (!linksUnchanged(links, package.object.get("links") orelse .null)) return session.reject("locked dependency changed: {s} (its links)", .{name});
        // A lock that records the package's devices is checked as its links are; an older one is checked only when the
        // build uses one of them, and is then refused (`packageDevice`).
        var devices: ?[]const package_devices.Device = null;
        if (package.object.get("devices")) |locked| {
            devices = try packageDevices(session, inventory.root);
            const recorded: package_devices.Locked = .{ .files = locked, .descriptions = package.object.get("device_descriptions") orelse .null };
            if (try package_devices.changed(allocator, devices.?, recorded)) |what| return session.reject("locked dependency changed: {s} ({s})", .{ name, what });
        }
        try inventories.append(allocator, .{ .root = inventory.root, .modules = inventory.modules, .links = links, .name = name, .devices = devices });
    }
    return inventories.items;
}

/// The devices the `selka.json` at a package's root describes, each with the files it names; none without one.
fn packageDevices(session: *Session, root: []const u8) Error![]const package_devices.Device {
    const config = try std.fs.path.join(session.allocator, &.{ root, config_name });
    const info = std.Io.Dir.cwd().statFile(session.io, config, .{}) catch return &.{};
    if (info.kind != .file) return &.{};
    const bytes = try boundedRead(session, std.Io.Dir.cwd(), config, config, package_byte_budget);
    return readDevices(session, .{ .root = root, .config = config }, bytes);
}

/// `package_devices.read`, its refusal recorded as this command's.
fn readDevices(session: *Session, owner: package_devices.Owner, bytes: []const u8) Error![]const package_devices.Device {
    return package_devices.read(session.allocator, session.io, owner, bytes, &session.message);
}

/// The folder a package's device files are staged under: `.devices/PKG`, which a walk of the stage leaves out.
fn deviceFolder(allocator: std.mem.Allocator, package: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, ".devices/{s}", .{package});
}

/// The device a staged `selka build` builds for, once its files are staged: the name the staged configuration gives
/// it, its entry there (null for one of the application's own devices, which the staged copy keeps), and whether the
/// choice came from the words after `--` (`--device`), whose value then becomes the staged name.
const StagedDevice = struct { name: []const u8, entry: ?std.json.Value, forwarded: bool };

/// For `--command build` (not `--run`): stage the files of every device of the application's own configuration, and of
/// the package device it chooses (`"device": "PKG/NAME"` or `--device PKG/NAME` after `--`), after the checks that
/// device needs: the lock pins it, and the application allows the package's C (`allow_links`) when the device names files
/// (a device that only describes itself has no C to allow). Null when the build chooses no package device.
fn stageDevices(session: *Session, request: Build, directory: []const u8, inventories: []const Inventory) Error!?StagedDevice {
    const allocator = session.allocator;
    if (!std.mem.eql(u8, request.command, "build") or hasWord(request.forwarded, "--run")) return null;
    const config = (try applicationConfig(session, inventories[0].root)) orelse return null;
    const raw = try boundedRead(session, std.Io.Dir.cwd(), config, config, package_byte_budget);
    const folder = try resolvedPath(session, std.fs.path.dirname(config) orelse ".");
    for (try readDevices(session, .{ .root = folder, .config = config }, raw)) |device| {
        for (device.files) |file| try place(session, directory, file.path, file.bytes);
    }
    const forwarded = forwardedDevice(request.forwarded);
    const document = try parseJson(session, raw, config);
    const choice = forwarded orelse stringField(document, "device") orelse return null;
    const slash = std.mem.indexOfScalar(u8, choice, '/') orelse return null;
    const package = choice[0..slash];
    const name = choice[slash + 1 ..];
    const inventory = for (inventories[1..]) |inventory| {
        if (std.mem.eql(u8, inventory.name, package)) break inventory;
    } else return session.reject("device \"{s}\" is a device of package {s}, which {s} does not lock; add the package to packages.json and lock again", .{ choice, package, request.lock });
    const devices = inventory.devices orelse return session.reject(
        "package {s}: {s} records none of its devices (it was written before a lock recorded them); run `selka packages lock` again to build for \"{s}\"",
        .{ package, request.lock, choice },
    );
    const device = package_devices.named(devices, name) orelse
        return session.reject("package {s} has no device \"{s}\"; its devices are {s}", .{ package, name, try deviceNames(allocator, devices) });
    const allow = (if (document == .object) document.object.get("allow_links") else null) orelse .null;
    if (device.files.len != 0 and (allow != .array or !namesPackage(allow.array.items, package)))
        return session.reject(
            "device \"{s}\" builds with package {s}'s C and linker script ({d} files in {s}/{s}); to build it, add \"allow_links\": [\"{s}\"] to {s}",
            .{ choice, package, device.files.len, inventory.root, config_name, package, config },
        );
    const prefix = try deviceFolder(allocator, package);
    for (device.files) |file| try place(session, directory, try std.fs.path.join(allocator, &.{ prefix, file.path }), file.bytes);
    const staged = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ package, name });
    return .{ .name = staged, .entry = try package_devices.stagedEntry(allocator, device, prefix), .forwarded = forwarded != null };
}

/// The names of `devices`, for the refusal of a name that is not one ("none" when there are none).
fn deviceNames(allocator: std.mem.Allocator, devices: []const package_devices.Device) error{OutOfMemory}![]const u8 {
    if (devices.len == 0) return "none";
    var names: std.ArrayList([]const u8) = .empty;
    for (devices) |device| try names.append(allocator, device.name);
    return std.mem.join(allocator, ", ", names.items);
}

/// Whether `words` holds `word`.
fn hasWord(words: []const []const u8, word: []const u8) bool {
    for (words) |each| if (std.mem.eql(u8, each, word)) return true;
    return false;
}

/// The value of the last `--device` among the words after `--`, or null.
fn forwardedDevice(words: []const []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    for (words, 0..) |word, index| {
        if (std.mem.eql(u8, word, "--device") and index + 1 < words.len) found = words[index + 1];
    }
    return found;
}

/// The words after `--` with every `--device` value replaced by `name`: the staged name of the package device they chose.
fn renamedDevice(allocator: std.mem.Allocator, words: []const []const u8, name: []const u8) error{OutOfMemory}![]const []const u8 {
    const copy = try allocator.dupe([]const u8, words);
    for (copy, 0..) |word, index| {
        if (std.mem.eql(u8, word, "--device") and index + 1 < copy.len) copy[index + 1] = name;
    }
    return copy;
}

/// Whether the application's configuration sets `"interface_files": true`, so that the snapshot holds the `.api` files beside its
/// sources: the check the key asks for reads them, and the staged copy has no other place to find them.
fn interfaceKey(session: *Session, app_root: []const u8) Error!bool {
    const config = (try applicationConfig(session, app_root)) orelse return false;
    const document = try parseJson(session, try boundedRead(session, std.Io.Dir.cwd(), config, config, package_byte_budget), config);
    const value = (if (document == .object) document.object.get("interface_files") else null) orelse return false;
    return value == .bool and value.bool;
}

/// The `links` of the `selka.json` in `directory`, each resolved against it and read, with its SHA-256; none when the
/// directory has no configuration or it lists no C. A listed file that cannot be read is refused, naming the
/// configuration and the entry.
fn configLinks(session: *Session, directory: []const u8) Error![]const Link {
    const allocator = session.allocator;
    const config = try std.fs.path.join(allocator, &.{ directory, config_name });
    const info = std.Io.Dir.cwd().statFile(session.io, config, .{}) catch return &.{};
    if (info.kind != .file) return &.{};
    const document = try parseJson(session, try boundedRead(session, std.Io.Dir.cwd(), config, config, package_byte_budget), config);
    const listed = (if (document == .object) document.object.get("links") else null) orelse return &.{};
    if (listed != .array) return session.reject("{s}: links must be an array of paths", .{config});
    var links: std.ArrayList(Link) = .empty;
    for (listed.array.items) |item| {
        if (item != .string or item.string.len == 0) return session.reject("{s}: links must be an array of paths", .{config});
        const path = try std.fs.path.resolve(allocator, &.{ directory, item.string });
        const shown = try std.fmt.allocPrint(allocator, "{s}: links entry \"{s}\" ({s})", .{ config, item.string, path });
        const bytes = try boundedRead(session, std.Io.Dir.cwd(), path, shown, package_byte_budget);
        try links.append(allocator, .{ .spelled = item.string, .path = path, .digest = try hexDigest(allocator, bytes) });
    }
    return links.items;
}

/// The lock's record of a package's C sources: each one's spelling and SHA-256, in link order.
fn lockedLinks(allocator: std.mem.Allocator, links: []const Link) error{OutOfMemory}!std.json.Value {
    var array = std.json.Array.init(allocator);
    for (links) |link| {
        var object: std.json.ObjectMap = .empty;
        try object.put(allocator, "path", .{ .string = link.spelled });
        try object.put(allocator, "sha256", .{ .string = link.digest });
        try array.append(.{ .object = object });
    }
    return .{ .array = array };
}

/// Whether a package's C sources are still the ones its lock entry pinned, in the same order (`.null`: it pinned none).
fn linksUnchanged(links: []const Link, locked: std.json.Value) bool {
    if (locked == .null) return links.len == 0;
    if (locked != .array or locked.array.items.len != links.len) return false;
    for (links, locked.array.items) |link, entry| {
        const path = stringField(entry, "path") orelse return false;
        const digest = stringField(entry, "sha256") orelse return false;
        if (!std.mem.eql(u8, path, link.spelled) or !std.mem.eql(u8, digest, link.digest)) return false;
    }
    return true;
}

/// The nearest `selka.json` at or above the application root, or null: the configuration the snapshot is built under.
fn applicationConfig(session: *Session, app_root: []const u8) Error!?[]const u8 {
    var base: ?[]const u8 = app_root;
    while (base) |candidate| : (base = std.fs.path.dirname(candidate)) {
        const config = try std.fs.path.join(session.allocator, &.{ candidate, config_name });
        const info = std.Io.Dir.cwd().statFile(session.io, config, .{}) catch continue;
        if (info.kind == .file) return config;
    }
    return null;
}

/// The C sources the staged build links, in order: the application configuration's own `links`, then each package's,
/// which are used only when the application names that package in `allow_links`. A package that links C without that
/// entry is refused, naming the package and the entry to add.
fn snapshotLinks(session: *Session, app_root: []const u8, inventories: []const Inventory) Error![]const []const u8 {
    const allocator = session.allocator;
    const config = try applicationConfig(session, app_root);
    var allowed: []const std.json.Value = &.{};
    var links: std.ArrayList([]const u8) = .empty;
    if (config) |path| {
        const document = try parseJson(session, try boundedRead(session, std.Io.Dir.cwd(), path, path, package_byte_budget), path);
        const allow = (if (document == .object) document.object.get("allow_links") else null) orelse .null;
        if (allow == .array) allowed = allow.array.items;
        for (try configLinks(session, std.fs.path.dirname(path) orelse ".")) |link| try links.append(allocator, link.path);
    }
    for (inventories[1..]) |inventory| {
        if (inventory.links.len == 0) continue;
        const name = inventory.name;
        if (!namesPackage(allowed, name)) {
            const shown = config orelse try std.fs.path.join(allocator, &.{ app_root, config_name });
            return session.reject("package {s} links C ({d} sources in {s}/{s}); to build it, add \"allow_links\": [\"{s}\"] to {s}", .{ name, inventory.links.len, inventory.root, config_name, name, shown });
        }
        for (inventory.links) |link| try links.append(allocator, link.path);
    }
    return links.items;
}

fn namesPackage(allowed: []const std.json.Value, name: []const u8) bool {
    for (allowed) |entry| if (entry == .string and std.mem.eql(u8, entry.string, name)) return true;
    return false;
}

/// Copy every verified module into `stage`, re-reading and re-hashing its bytes.
/// A path two inventories share, a path that climbs out, and a module that would
/// replace a standard one are refused; so is a byte that changed since the walk.
fn stage(session: *Session, directory: []const u8, inventories: []const Inventory) Error!void {
    const allocator = session.allocator;
    var used: std.StringHashMapUnmanaged(void) = .empty;
    var total: usize = 0;
    for (inventories) |inventory| for (inventory.modules) |module| {
        if (std.fs.path.isAbsolute(module.path) or climbs(module.path) or (try used.getOrPut(allocator, module.path)).found_existing)
            return session.reject("duplicate or invalid module path: {s}", .{module.path});
        if (std.mem.startsWith(u8, std.fs.path.basename(module.path), reserved_prefix))
            return session.reject("application/dependency cannot replace a standard module: {s}", .{module.path});
        const source = try std.fs.path.join(allocator, &.{ inventory.root, module.path });
        const bytes = try boundedRead(session, std.Io.Dir.cwd(), source, module.path, package_byte_budget - total);
        total += bytes.len;
        if (!std.mem.eql(u8, try hexDigest(allocator, bytes), module.digest)) return session.reject("source changed during package snapshot: {s}", .{module.path});
        try place(session, directory, module.path, bytes);
    };
}

/// Write `bytes` at `relative` under `directory`, creating its parents. A file of a kept stage that already holds those
/// bytes is left alone, so its status stays and a replay that checks it by status sees it unchanged.
fn place(session: *Session, directory: []const u8, relative: []const u8, bytes: []const u8) Error!void {
    try session.placed.put(session.allocator, relative, {});
    const destination = try std.fs.path.join(session.allocator, &.{ directory, relative });
    if (std.Io.Dir.cwd().readFileAlloc(session.io, destination, session.allocator, .limited(bytes.len + 1))) |existing| {
        if (std.mem.eql(u8, existing, bytes)) return;
    } else |_| {}
    if (std.fs.path.dirname(destination)) |parent| std.Io.Dir.cwd().createDirPath(session.io, parent) catch |err|
        return session.reject("cannot stage {s}: {t}", .{ relative, err });
    std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = destination, .data = bytes }) catch |err|
        return session.reject("cannot stage {s}: {t}", .{ relative, err });
}

/// Mirror the nearest `selka.json` into the staged root, so the compiler's own
/// discovery and import-policy enforcement run against the snapshot. When the
/// configuration sits in the application directory its relative policy file
/// comes along; an ancestor's configuration is copied without its policy, so a
/// policy the snapshot cannot hold is reported missing rather than skipped.
fn copyProjectConfig(session: *Session, app_root: []const u8, directory: []const u8, device: ?StagedDevice) Error!void {
    var base: ?[]const u8 = app_root;
    while (base) |candidate| : (base = std.fs.path.dirname(candidate)) {
        const config = try std.fs.path.join(session.allocator, &.{ candidate, config_name });
        const info = std.Io.Dir.cwd().statFile(session.io, config, .{}) catch continue;
        if (info.kind != .file) continue;
        const raw = try boundedRead(session, std.Io.Dir.cwd(), config, config, package_byte_budget);
        try place(session, directory, config_name, try stagedConfig(session, raw, .{ .shown = config, .folder = candidate, .device = device }));
        if (!std.mem.eql(u8, candidate, app_root)) return;
        return copyPolicy(session, candidate, directory, raw);
    }
}

/// What the staged copy of a configuration changes: the configuration's path and folder, and the package device the
/// staged build chooses.
const Staging = struct { shown: []const u8, folder: []const u8, device: ?StagedDevice };

/// The staged copy of a configuration. It leaves out `links` and `allow_links`, whose C the staged build is given by
/// path (the staged copy's directory holds none of it); each relative `include` folder becomes its absolute path in the
/// application's folder; and a package device the build chooses joins `devices` under its staged name, with its files
/// under `.devices/PKG`. A configuration that needs none of this is copied byte for byte.
fn stagedConfig(session: *Session, raw: []const u8, staging: Staging) Error![]const u8 {
    const allocator = session.allocator;
    var document = try parseJson(session, raw, staging.shown);
    if (document != .object) return raw;
    var changed = document.object.orderedRemove("links");
    changed = document.object.orderedRemove("allow_links") or changed;
    if (document.object.getPtr("include")) |include| if (include.* == .array) for (include.array.items) |*folder| {
        if (folder.* != .string or std.fs.path.isAbsolute(folder.string)) continue;
        folder.* = .{ .string = try std.fs.path.resolve(allocator, &.{ staging.folder, folder.string }) };
        changed = true;
    };
    if (staging.device) |device| if (device.entry) |entry| {
        var devices: std.json.ObjectMap = .empty;
        if (document.object.get("devices")) |existing| if (existing == .object) {
            devices = try existing.object.clone(allocator);
        };
        try devices.put(allocator, device.name, entry);
        try document.object.put(allocator, "devices", .{ .object = devices });
        if (!device.forwarded) try document.object.put(allocator, "device", .{ .string = device.name });
        changed = true;
    };
    if (!changed) return raw;
    return std.json.Stringify.valueAlloc(allocator, document, .{});
}

fn copyPolicy(session: *Session, base: []const u8, directory: []const u8, raw: []const u8) Error!void {
    const document = std.json.parseFromSliceLeaky(std.json.Value, session.allocator, raw, .{}) catch return;
    const policy = stringField(document, "import_policy") orelse return;
    if (policy.len == 0 or std.fs.path.isAbsolute(policy) or climbs(policy)) return;
    const target = try std.fs.path.join(session.allocator, &.{ base, policy });
    const info = std.Io.Dir.cwd().statFile(session.io, target, .{}) catch return;
    if (info.kind != .file) return;
    try place(session, directory, policy, try boundedRead(session, std.Io.Dir.cwd(), target, policy, package_byte_budget));
}

/// A fresh private directory under `TMPDIR` (or the default scratch root).
fn makeStage(session: *Session, environ: *const std.process.Environ.Map) Error![]const u8 {
    const configured = environ.get("TMPDIR") orelse "";
    const parent = if (configured.len == 0) "/tmp" else configured;
    var random: [8]u8 = undefined;
    std.Io.random(session.io, &random);
    const name = try std.fmt.allocPrint(session.allocator, "selka-packages-{s}", .{std.fmt.bytesToHex(random, .lower)});
    const path = try std.fs.path.join(session.allocator, &.{ parent, name });
    std.Io.Dir.cwd().createDirPath(session.io, path) catch |err| return session.reject("cannot create staging directory {s}: {t}", .{ path, err });
    return path;
}

/// A staging directory that stays between runs, and the exclusive lock on it this run holds until its command ends.
const Kept = struct { path: []const u8, lock: std.Io.File };

/// Whether `command` stages into a kept directory: `build` and `test`, whose caches and replays name the staged files by
/// path. `run-project` keeps the private one, since a service it starts would hold the stage's lock while it runs.
fn keeps(command: []const u8) bool {
    return std.mem.eql(u8, command, "build") or std.mem.eql(u8, command, "test");
}

/// The kept stage of one application root, `selka/packages-v1/<digest of the root's path>` under the per-user cache, locked
/// for this run; null when no cache directory resolves, and the run then stages privately.
fn keptStage(session: *Session, environ: *const std.process.Environ.Map, app_root: []const u8) Error!?Kept {
    const allocator = session.allocator;
    const home = store_settings.cacheHome(allocator, environ) orelse return null;
    var digest: [32]u8 = undefined;
    Sha256.hash(app_root, &digest, .{});
    const parent = try std.fs.path.join(allocator, &.{ home, product.user_dir, kept_stages });
    const path = try std.fs.path.join(allocator, &.{ parent, &std.fmt.bytesToHex(digest[0..16].*, .lower) });
    std.Io.Dir.cwd().createDirPath(session.io, path) catch |err| return session.reject("cannot create staging directory {s}: {t}", .{ path, err });
    const lock_path = try std.fmt.allocPrint(allocator, "{s}.lock", .{path});
    const options: std.Io.Dir.CreateFileOptions = .{ .read = true, .truncate = false, .lock = .exclusive };
    const held = std.Io.Dir.cwd().createFile(session.io, lock_path, options) catch |err|
        return session.reject("cannot lock staging directory {s}: {t}", .{ path, err });
    return .{ .path = path, .lock = held };
}

/// Remove every file of a kept stage this run did not place, so a module the application or a package no longer has
/// cannot be imported from an earlier run's snapshot.
fn prune(session: *Session, directory: []const u8) Error!void {
    const io = session.io;
    var opened = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch |err| return session.reject("cannot open {s}: {t}", .{ directory, err });
    defer opened.close(io);
    var walker = try opened.walk(session.allocator);
    defer walker.deinit();
    var stale: std.ArrayList([]const u8) = .empty;
    while (walker.next(io) catch |err| return session.reject("cannot walk {s}: {t}", .{ directory, err })) |entry| {
        if (entry.kind == .directory or session.placed.contains(entry.path)) continue;
        try stale.append(session.allocator, try session.allocator.dupe(u8, entry.path));
    }
    for (stale.items) |path| opened.deleteFile(io, path) catch |err|
        return session.reject("cannot remove {s} from the staging directory {s}: {t}", .{ path, directory, err });
}

/// Remove the staging directory; a removal that fails leaves scratch under
/// `TMPDIR`, which is no reason to fail a build that already finished.
fn discard(io: std.Io, directory: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, directory) catch return;
}

fn status(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
}

/// `selka packages build ENTRY --lock LOCK [--command C] [--receipt FILE]`.
fn build(session: *Session, process: std.process.Init, request: Build, identity: []const u8) Error!u8 {
    const document = try readLock(session, request.lock);
    if (request.directory and !std.mem.eql(u8, request.command, "test"))
        return session.reject("{s} is a directory; only --command test takes one, the other commands an entry file", .{request.positional});
    const inventories = try verify(session, request, document);
    const kept = if (keeps(request.command)) try keptStage(session, process.environ_map, inventories[0].root) else null;
    const directory = if (kept) |held| held.path else try makeStage(session, process.environ_map);
    defer if (kept) |held| held.lock.close(session.io) else discard(session.io, directory);
    const links = try snapshotLinks(session, inventories[0].root, inventories);
    try stage(session, directory, inventories);
    const device = try stageDevices(session, request, directory, inventories);
    try copyProjectConfig(session, inventories[0].root, directory, device);
    if (kept != null) try prune(session, directory);
    var forwarded = request.forwarded;
    if (device) |chosen| if (chosen.forwarded) {
        forwarded = try renamedDevice(session.allocator, forwarded, chosen.name);
    };
    const entry = if (request.directory) directory else try std.fs.path.join(session.allocator, &.{ directory, std.fs.path.basename(request.positional) });
    const compiler = std.process.executablePathAlloc(session.io, session.allocator) catch |err|
        return session.reject("cannot locate this compiler: {t}", .{err});
    // A test entry needs no `main` and a directory has no one entry: `test` checks each entry itself, so it runs no
    // `project-dependencies` and its receipt records no dependency report. `api` reads declarations only, and runs none either.
    var report_value: std.json.Value = .null;
    if (!std.mem.eql(u8, request.command, "test") and !std.mem.eql(u8, request.command, "api")) {
        const dependencies = std.process.run(session.allocator, session.io, .{ .argv = &.{ compiler, "project-dependencies", entry } }) catch |err|
            return session.reject("cannot run project-dependencies: {t}", .{err});
        if (status(dependencies.term) != 0) {
            std.Io.File.stdout().writeStreamingAll(session.io, dependencies.stdout) catch return status(dependencies.term);
            std.Io.File.stderr().writeStreamingAll(session.io, dependencies.stderr) catch return status(dependencies.term);
            return status(dependencies.term);
        }
        report_value = try parseJson(session, dependencies.stdout, "the project-dependencies report");
        const implementation: std.json.Value = if (report_value == .object) report_value.object.get("implementation") orelse .null else .null;
        const checked_by = stringField(implementation, "compiler_sha256") orelse "";
        if (!std.mem.eql(u8, checked_by, identity)) return session.reject("the snapshot was checked by compiler {s}, not this one ({s})", .{ checked_by, identity });
    }
    if (request.receipt) |path| try writeReceipt(session, path, .{ .lock = document, .identity = identity, .dependencies = report_value });
    var names: std.ArrayList([]const u8) = .empty;
    for (inventories[1..]) |inventory| try names.append(session.allocator, inventory.name);
    const fix = try std.fmt.allocPrint(session.allocator, "{s} --lock {s}", .{ request.positional, request.lock });
    const ended = try runCommand(session, process, .{ .compiler = compiler, .command = request.command, .entry = entry, .links = links, .forwarded = forwarded, .packages = names.items, .fix = fix });
    if (ended == 0 and std.mem.eql(u8, request.command, "api") and writes(request.forwarded)) {
        try writeInterfaces(session, directory, inventories[0], if (request.directory) request.positional else std.fs.path.dirname(request.positional) orelse "");
    }
    return ended;
}

/// Whether the words after `--` ask `selka api` to write its files.
fn writes(forwarded: []const []const u8) bool {
    for (forwarded) |word| if (std.mem.eql(u8, word, "--write")) return true;
    return false;
}

/// The interface file of the module source `path` (`a/b.selka` is `a/b.api`).
fn interfacePath(session: *Session, path: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(session.allocator, "{s}{s}", .{ path[0 .. path.len - source_suffix.len], interface_suffix });
}

/// The bytes at `path`, or null when there is no such file.
fn readIfPresent(session: *Session, path: []const u8) Error!?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(session.io, path, session.allocator, .limited(package_byte_budget)) catch |err| switch (err) {
        error.FileNotFound => null,
        error.OutOfMemory => error.OutOfMemory,
        else => session.reject(unreadable, .{ path, err }),
    };
}

/// Copy into the application what `selka api --write` did to its interface files in the staging `directory`: the `<stem>.api` it wrote
/// or changed beside each module of the application, and the generated one it deleted. Nothing is written when a file
/// changed since the snapshot was taken (an interface file the inventory `app` held must still hold its bytes, and one it did not
/// hold must still be absent), so no edit of the user's is lost. `shown_root` is how the user spelled the application's directory.
fn writeInterfaces(session: *Session, directory: []const u8, app: Inventory, shown_root: []const u8) Error!void {
    const allocator = session.allocator;
    const Change = struct { path: []const u8, bytes: ?[]const u8 };
    var changes: std.ArrayList(Change) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (app.modules) |module| {
        const is_source = std.mem.endsWith(u8, module.path, source_suffix);
        if (!is_source and !std.mem.endsWith(u8, module.path, interface_suffix)) continue;
        const relative = if (is_source) try interfacePath(session, module.path) else module.path;
        if ((try seen.getOrPut(allocator, relative)).found_existing) continue;
        const staged = try readIfPresent(session, try std.fs.path.join(allocator, &.{ directory, relative }));
        const original = try std.fs.path.join(allocator, &.{ app.root, relative });
        const now = try readIfPresent(session, original);
        if (staged == null and now == null) continue;
        if (staged != null and now != null and std.mem.eql(u8, staged.?, now.?)) continue;
        const as_staged = if (digestOf(app, relative)) |digest| now != null and std.mem.eql(u8, try hexDigest(allocator, now.?), digest) else now == null;
        if (!as_staged) return session.reject("{s} changed while `selka packages build --command api` ran, so none of the interface files were written; run it again", .{try std.fs.path.join(allocator, &.{ shown_root, relative })});
        try changes.append(allocator, .{ .path = original, .bytes = staged });
    }
    for (changes.items) |change| {
        if (change.bytes) |bytes| {
            std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = change.path, .data = bytes }) catch |err| return session.reject("cannot write {s}: {t}", .{ change.path, err });
        } else std.Io.Dir.cwd().deleteFile(session.io, change.path) catch |err| return session.reject("cannot delete {s}: {t}", .{ change.path, err });
    }
}

/// The digest the inventory recorded for `path`, or null.
fn digestOf(inventory: Inventory, path: []const u8) ?[]const u8 {
    for (inventory.modules) |module| if (std.mem.eql(u8, module.path, path)) return module.digest;
    return null;
}

/// The lock at `path`, parsed: a `package-lock-v1` document, else refused.
fn readLock(session: *Session, path: []const u8) Error!std.json.Value {
    const document = try parseJson(session, try boundedRead(session, std.Io.Dir.cwd(), path, path, package_byte_budget), path);
    const version = stringField(document, "version") orelse "";
    if (!std.mem.eql(u8, version, lock_version)) return session.reject(unsupported_lock, .{path});
    return document;
}

/// What `fix` was asked for: the entry or directory and the lock as given, and `selka fix`'s own switches.
const Fix = struct { positional: []const u8, lock: []const u8, switches: []const []const u8 };

/// Parse `fix ENTRY --lock LOCK [SWITCHES...]`: one positional, `--lock` once (spaced or with `=`), and every other word starting
/// with `-` kept for `selka fix`, which checks them itself.
fn parseFix(allocator: std.mem.Allocator, args: []const []const u8) Error!Fix {
    var positional: ?[]const u8 = null;
    var lock_path: ?[]const u8 = null;
    var switches: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--lock") or std.mem.startsWith(u8, arg, "--lock=")) {
            const value = if (arg.len > "--lock".len) arg["--lock=".len..] else value: {
                index += 1;
                if (index >= args.len) return error.Usage;
                break :value args[index];
            };
            if (lock_path != null or value.len == 0) return error.Usage;
            lock_path = value;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try switches.append(allocator, arg);
        } else {
            if (positional != null) return error.Usage;
            positional = arg;
        }
    }
    return .{ .positional = positional orelse return error.Usage, .lock = lock_path orelse return error.Usage, .switches = switches.items };
}

/// `selka packages fix ENTRY|DIR --lock LOCK [SWITCHES]`: verify the lock as `build` does, stage the application and the packages
/// privately, run `selka fix` over the staged entry or directory with the packages' files set aside (`fix_command.Staged`), and copy
/// back the application files it changed (`writeBack`). The status is `selka fix`'s, or 2 when nothing could be written back.
fn fixApplication(session: *Session, process: std.process.Init, request: Fix) Error!u8 {
    const allocator = session.allocator;
    const document = try readLock(session, request.lock);
    const directory_run = try isDirectory(session, request.positional);
    const build_request: Build = .{ .positional = request.positional, .lock = request.lock, .command = "fix", .receipt = null, .forwarded = &.{}, .directory = directory_run };
    const inventories = try verify(session, build_request, document);
    const app_root = inventories[0].root;
    _ = try snapshotLinks(session, app_root, inventories);
    const created = try makeStage(session, process.environ_map);
    defer discard(session.io, created);
    const directory = std.Io.Dir.cwd().realPathFileAlloc(session.io, created, allocator) catch |err|
        return session.reject("cannot resolve staging directory {s}: {t}", .{ created, err });
    try stage(session, directory, inventories);
    try copyProjectConfig(session, app_root, directory, null);
    var packages: std.StringHashMapUnmanaged([]const u8) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    for (inventories[1..]) |inventory| {
        try names.append(allocator, inventory.name);
        for (inventory.modules) |module| try packages.put(allocator, try std.fs.path.join(allocator, &.{ directory, module.path }), inventory.name);
    }
    const target = if (directory_run) directory else try std.fs.path.join(allocator, &.{ directory, std.fs.path.basename(request.positional) });
    const fixed = fix_command.run(process, try std.mem.concat(allocator, []const u8, &.{ request.switches, &.{target} }), .{
        .directory = directory,
        .app_root = app_root,
        .packages = &packages,
        .namespaces = try std.mem.join(allocator, ",", names.items),
        .entry = request.positional,
        .lock = request.lock,
    });
    const shown_root = if (directory_run) request.positional else std.fs.path.dirname(request.positional) orelse "";
    try writeBack(session, directory, inventories[0], shown_root);
    return fixed;
}

/// Copy into the application each of its files that `selka fix` changed in the staging `directory`, and nothing else: no file of a
/// package, no file `fix` left as it was staged. Every such file must still hold the bytes it was staged from (its digest in the
/// inventory `app`); if one does not, it was edited while `fix` ran, and nothing is written, so no edit of the user's is lost.
/// `shown_root` is how the user spelled the application's directory, for the refusal.
fn writeBack(session: *Session, directory: []const u8, app: Inventory, shown_root: []const u8) Error!void {
    const allocator = session.allocator;
    const Changed = struct { path: []const u8, bytes: []const u8 };
    var changed: std.ArrayList(Changed) = .empty;
    for (app.modules) |module| {
        const staged = try std.fs.path.join(allocator, &.{ directory, module.path });
        const bytes = try boundedRead(session, std.Io.Dir.cwd(), staged, module.path, package_byte_budget);
        if (std.mem.eql(u8, try hexDigest(allocator, bytes), module.digest)) continue;
        const original = try std.fs.path.join(allocator, &.{ app.root, module.path });
        const shown = try std.fs.path.join(allocator, &.{ shown_root, module.path });
        const now = std.Io.Dir.cwd().readFileAlloc(session.io, original, allocator, .limited(package_byte_budget)) catch "";
        if (!std.mem.eql(u8, try hexDigest(allocator, now), module.digest))
            return session.reject("{s} changed while `selka packages fix` ran, so none of its repairs were written back; run it again", .{shown});
        try changed.append(allocator, .{ .path = original, .bytes = bytes });
    }
    for (changed.items) |file| std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = file.path, .data = file.bytes }) catch |err|
        return session.reject("cannot write {s}: {t}", .{ file.path, err });
}

/// The project command `build` runs over the staged entry, the C sources `run-project`, `build` and `test` link, the words after
/// `--` for the command, the namespaces of the locked packages (whose warnings the command counts and does not print) and the entry and
/// lock its closing line names `selka packages fix` with, in place of `selka fix` and the staged copy.
const Command = struct {
    compiler: []const u8,
    command: []const u8,
    entry: []const u8,
    links: []const []const u8,
    forwarded: []const []const u8,
    packages: []const []const u8,
    /// The entry and the lock as the user gave them, for the closing line that names `selka packages fix` (`package_fix_option`).
    fix: []const u8,
};

/// The receipt's three inputs.
const Receipt = struct { lock: std.json.Value, identity: []const u8, dependencies: std.json.Value };

/// Record the lock identity (SHA-256 of its compact JSON), this compiler's
/// identity and the staged snapshot's dependency report (null for `test`). It is written once
/// the snapshot has verified and checked, before the command runs: a
/// `run-project` program's exit status is its own and says nothing about
/// whether the locked inputs built.
fn writeReceipt(session: *Session, path: []const u8, receipt: Receipt) Error!void {
    const allocator = session.allocator;
    const compact = try std.json.Stringify.valueAlloc(allocator, receipt.lock, .{});
    var object: std.json.ObjectMap = .empty;
    try object.put(allocator, "version", .{ .string = receipt_version });
    try object.put(allocator, "lock_sha256", .{ .string = try hexDigest(allocator, compact) });
    try object.put(allocator, "compiler_sha256", .{ .string = receipt.identity });
    try object.put(allocator, "dependencies", receipt.dependencies);
    try writeJson(session, path, .{ .object = object });
}

/// Run the project command over the staged entry with inherited standard
/// streams and forward its exit status; `run-project` prints its result. The
/// command ends with this process (RUN-SIGNALS-1): a SIGTERM, SIGINT or SIGHUP sent to this
/// process alone is passed on while it waits, and a process killed outright takes the
/// command (and the program it runs) with it.
fn runCommand(session: *Session, process: std.process.Init, request: Command) Error!u8 {
    const run_signals = @import("compiler_root").compiler_language.run_signals;
    const waiting = run_signals.Waiting.begin();
    var ended: u32 = 0;
    defer waiting.finish(ended);
    const options: @import("selka_core").process_spawn.Options = .{
        .argv = try commandLine(session.allocator, request),
        .environment = .{ .map = process.environ_map },
        .stdin = .inherit,
        .die_with_parent = true,
    };
    var child = @import("selka_core").process_spawn.spawn(process.gpa, options) catch |err| return session.reject("cannot run {s}: {t}", .{ request.command, err });
    waiting.started(child.id.?);
    waiting.awaitEnd(child.id.?);
    const term = child.wait(session.io) catch |err| return session.reject("cannot wait for {s}: {t}", .{ request.command, err });
    ended = switch (term) {
        .signal => |signal| @backingInt(signal),
        else => 0,
    };
    return status(term);
}

/// The command line of the project command: the staged entry, `--print-result` for `run-project`, a `--link` for each C
/// source of a command that links, the packages and the `selka packages fix` words for a command whose diagnostics the display policy
/// covers (`warning_display.covered`; the child reads them there and no command sees them), then the words after `--`.
fn commandLine(allocator: std.mem.Allocator, request: Command) error{OutOfMemory}![]const []const u8 {
    const command = request.command;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ request.compiler, command, request.entry });
    if (std.mem.eql(u8, command, "run-project")) try argv.append(allocator, "--print-result");
    // Checking and indexing never compile the C; a run, a build and a test link it.
    if (std.mem.eql(u8, command, "run-project") or keeps(command)) {
        for (request.links) |link| try argv.appendSlice(allocator, &.{ "--link", link });
    }
    if (warning_display.covered(command)) {
        try argv.appendSlice(allocator, &.{ warning_display.packages_option, try std.mem.join(allocator, ",", request.packages) });
        try argv.appendSlice(allocator, &.{ warning_display.package_fix_option, request.fix });
    }
    try argv.appendSlice(allocator, request.forwarded);
    return argv.items;
}

/// A throwaway session over the testing allocator's arena.
fn testSession(arena: *std.heap.ArenaAllocator) Session {
    return .{ .allocator = arena.allocator(), .io = std.testing.io };
}

// spec-case: PACKAGES-LOCK-1
test "package namespaces are ASCII identifiers outside the reserved std_ prefix and own name.selka and name/" {
    try std.testing.expect(validNamespace("numbers"));
    try std.testing.expect(validNamespace("_private2"));
    try std.testing.expect(!validNamespace("std_numbers"));
    try std.testing.expect(!validNamespace("2numbers"));
    try std.testing.expect(!validNamespace("num-bers"));
    try std.testing.expect(!validNamespace(""));
    try std.testing.expect(inNamespace("numbers", "numbers.selka"));
    try std.testing.expect(inNamespace("numbers", "numbers/extra.selka"));
    try std.testing.expect(!inNamespace("numbers", "numbersextra.selka"));
    try std.testing.expect(!inNamespace("numbers", "other.selka"));
    try std.testing.expect(climbs("a/../b.selka"));
    try std.testing.expect(!climbs("a/..b.selka"));
}

// spec-case: PACKAGES-LOCK-1
test "a package inventory hashes sorted .selka sources and refuses symbolic-link sources and directories" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "lib/numbers");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/numbers/extra.selka", .data = "b" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/numbers.selka", .data = "a" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/notes.txt", .data = "ignored" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, "lib", session.allocator);
    const modules = try sources(&session, root);
    try std.testing.expectEqual(@as(usize, 2), modules.len);
    try std.testing.expectEqualStrings("numbers.selka", modules[0].path);
    try std.testing.expectEqualStrings("numbers/extra.selka", modules[1].path);
    try std.testing.expectEqualStrings(try hexDigest(session.allocator, "a"), modules[0].digest);
    try temporary.dir.symLink(std.testing.io, "numbers.selka", "lib/alias.selka", .{});
    try std.testing.expectError(error.Rejected, sources(&session, root));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "symbolic-link sources") != null);
    try temporary.dir.deleteFile(std.testing.io, "lib/alias.selka");
    try temporary.dir.symLink(std.testing.io, "numbers", "lib/linked", .{ .is_directory = true });
    try std.testing.expectError(error.Rejected, sources(&session, root));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "symbolic-link directories") != null);
}

// spec-case: PACKAGES-BUILD-1
test "package command lines take one positional and each flag once, spaced or with =" {
    const parsed = try parse(&.{ "app/main.selka", "--lock=l.json", "--command", "run-project", "--receipt", "r.json" });
    try std.testing.expectEqualStrings("app/main.selka", parsed.positional.?);
    try std.testing.expectEqualStrings("l.json", parsed.lock.?);
    try std.testing.expectEqualStrings("run-project", parsed.command.?);
    try std.testing.expectEqualStrings("r.json", parsed.receipt.?);
    try std.testing.expectError(error.Usage, parse(&.{ "a.selka", "b.selka" }));
    try std.testing.expectError(error.Usage, parse(&.{ "a.selka", "--lock", "x", "--lock=y" }));
    try std.testing.expectError(error.Usage, parse(&.{ "a.selka", "--compiler", "zig-out/bin/selka" }));
    try std.testing.expectError(error.Usage, parse(&.{ "a.selka", "--lock" }));
    try std.testing.expect(known("index-project"));
    try std.testing.expect(!known("run"));
    try std.testing.expect(!known("emit-project-qbe"));
}

// spec-case: PACKAGES-LOCK-1
test "a source outside the package namespace is refused with where it moves to and the import it becomes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    try std.testing.expectError(error.Rejected, @as(Error!void, outsideNamespace(&session, "rex", "../pkg", "inner.selka")));
    try std.testing.expectEqualStrings("package rex: ../pkg/inner.selka is neither rex.selka nor under rex/, and every module of a package is one of the two: move it to ../pkg/rex/inner.selka and import it as `import rex.inner`", session.message);
    try std.testing.expectError(error.Rejected, @as(Error!void, outsideNamespace(&session, "rex", "pkg", "util/text.selka")));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "move it to pkg/rex/util/text.selka and import it as `import rex.util.text`") != null);
}

// spec-case: PACKAGES-BUILD-1
test "a word run-project refuses after the first -- is named with the line that has a second --" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    const stray: Request = .{ .lock = "lock.json", .command = "run-project", .forwarded = &.{ "ing$", "file" } };
    try std.testing.expectError(error.Rejected, @as(Error!void, refusedWord(&session, stray, "main.selka", 0)));
    try std.testing.expectEqualStrings("`ing$` follows the first `--`, so run-project was given it as one of its own options and refused it; " ++
        "the program's own arguments follow a second `--`:\n  selka packages build main.selka --lock lock.json --command run-project -- -- 'ing$' file", session.message);
    const budget: Request = .{ .lock = "lock.json", .command = "run-project", .receipt = "r.json", .forwarded = &.{ "--max-steps", "5", "--bogus", "it's" } };
    try std.testing.expectError(error.Rejected, @as(Error!void, refusedWord(&session, budget, "main.selka", 2)));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "`--bogus` follows") != null);
    try std.testing.expect(std.mem.endsWith(u8, session.message, "--receipt r.json -- --max-steps 5 -- --bogus 'it'\\''s'"));
}

// spec-case: PACKAGES-BUILD-1
test "a word is shown to a shell bare when it is plain and quoted when it is not, and the staged command's own options are withheld" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("''", try shellWord(arena.allocator(), ""));
    try std.testing.expectEqualStrings("a/b-c.selka", try shellWord(arena.allocator(), "a/b-c.selka"));
    try std.testing.expectEqualStrings("'a b'", try shellWord(arena.allocator(), "a b"));
    try std.testing.expect(withheld("--package-namespaces") and withheld("--package-fix"));
    try std.testing.expect(!withheld("--max-steps"));
}

// spec-case: PACKAGES-BUILD-1
test "package build and test commands take the words after -- and link the allowed C, which checks never do" {
    const parsed = try parse(&.{ "app/main.selka", "--lock", "l.json", "--command", "build", "--", "-o", "app", "--lock", "--" });
    try std.testing.expectEqualStrings("build", parsed.command.?);
    try std.testing.expectEqual(@as(usize, 4), parsed.forwarded.?.len);
    try std.testing.expectEqualStrings("--lock", parsed.forwarded.?[2]);
    try std.testing.expect((try parse(&.{"app/main.selka"})).forwarded == null);
    try std.testing.expect(known("build") and known("test"));
    try std.testing.expect(keeps("build") and keeps("test"));
    try std.testing.expect(!keeps("run-project") and !keeps("check-project"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const links = [_][]const u8{"/lib/shim.c"};
    const flags = [_][]const u8{ "-o", "app" };
    const names = [_][]const u8{ "numbers", "shapes" };
    const built = try commandLine(allocator, .{ .compiler = "selka", .command = "build", .entry = "/stage/main.selka", .links = &links, .forwarded = &flags, .packages = &names, .fix = "main.selka --lock lock.json" });
    const built_text = try std.mem.join(allocator, " ", built);
    // The display policy's internal option comes after the links and before the words for the command.
    try std.testing.expectEqualStrings("selka build /stage/main.selka --link /lib/shim.c --package-namespaces numbers,shapes --package-fix main.selka --lock lock.json -o app", built_text);
    const ran = try commandLine(allocator, .{ .compiler = "selka", .command = "run-project", .entry = "/stage/main.selka", .links = &links, .forwarded = &.{}, .packages = &.{}, .fix = "main.selka --lock lock.json" });
    try std.testing.expectEqualStrings("selka run-project /stage/main.selka --print-result --link /lib/shim.c --package-namespaces  --package-fix main.selka --lock lock.json", try std.mem.join(allocator, " ", ran));
    const checked = try commandLine(allocator, .{ .compiler = "selka", .command = "check-project", .entry = "/stage/main.selka", .links = &links, .forwarded = &.{}, .packages = &names, .fix = "main.selka --lock lock.json" });
    try std.testing.expectEqualStrings("selka check-project /stage/main.selka --package-namespaces numbers,shapes --package-fix main.selka --lock lock.json", try std.mem.join(allocator, " ", checked));
    // `index-project` is outside the display policy: it is given no option.
    const indexed = try commandLine(allocator, .{ .compiler = "selka", .command = "index-project", .entry = "/stage/main.selka", .links = &links, .forwarded = &.{}, .packages = &names, .fix = "main.selka --lock lock.json" });
    try std.testing.expectEqualStrings("selka index-project /stage/main.selka", try std.mem.join(allocator, " ", indexed));
}

// spec-case: PACKAGES-BUILD-1
test "packages fix takes one entry, the lock once, and keeps every other switch for selka fix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const spaced = try parseFix(allocator, &.{ "--warnings", "app/main.selka", "--lock", "lock.json", "--check" });
    try std.testing.expectEqualStrings("app/main.selka", spaced.positional);
    try std.testing.expectEqualStrings("lock.json", spaced.lock);
    try std.testing.expectEqualStrings("--warnings --check", try std.mem.join(allocator, " ", spaced.switches));
    try std.testing.expectEqualStrings("l.json", (try parseFix(allocator, &.{ "app", "--lock=l.json" })).lock);
    try std.testing.expectError(error.Usage, parseFix(allocator, &.{"app/main.selka"}));
    try std.testing.expectError(error.Usage, parseFix(allocator, &.{ "a.selka", "b.selka", "--lock", "l.json" }));
    try std.testing.expectError(error.Usage, parseFix(allocator, &.{ "a.selka", "--lock", "l.json", "--lock", "m.json" }));
    try std.testing.expectError(error.Usage, parseFix(allocator, &.{ "a.selka", "--lock" }));
}

// spec-case: PACKAGES-BUILD-1
test "a kept stage lives under the per-user cache, one per application root, and keeps only what the run placed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    var environ: std.process.Environ.Map = .init(session.allocator);
    try std.testing.expect(try keptStage(&session, &environ, "/src/app1") == null);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", session.allocator);
    try environ.put("XDG_CACHE_HOME", root);
    const first = (try keptStage(&session, &environ, "/src/app1")).?;
    first.lock.close(std.testing.io);
    const again = (try keptStage(&session, &environ, "/src/app1")).?;
    again.lock.close(std.testing.io);
    const other = (try keptStage(&session, &environ, "/src/app2")).?;
    other.lock.close(std.testing.io);
    try std.testing.expectEqualStrings(first.path, again.path);
    try std.testing.expect(!std.mem.eql(u8, first.path, other.path));
    try std.testing.expect(std.mem.startsWith(u8, first.path, try std.fs.path.join(session.allocator, &.{ root, "selka", kept_stages })));
    try place(&session, first.path, "main.selka", "a");
    try place(&session, first.path, "numbers/extra.selka", "b");
    session.placed = .empty;
    try place(&session, first.path, "main.selka", "a");
    try prune(&session, first.path);
    const kept = try std.fs.path.join(session.allocator, &.{ first.path, "main.selka" });
    const gone = try std.fs.path.join(session.allocator, &.{ first.path, "numbers/extra.selka" });
    try std.testing.expectEqualStrings("a", try std.Io.Dir.cwd().readFileAlloc(std.testing.io, kept, session.allocator, .limited(16)));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, gone, .{}));
}

// spec-case: PACKAGES-FIX-1
test "packages fix writes back only the files fix changed, and nothing when one changed since it was staged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    const a = session.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const app = try std.fs.path.join(a, &.{ root, "app" });
    const staged = try std.fs.path.join(a, &.{ root, "stage" });
    for ([_][]const u8{ app, staged }) |directory| {
        try place(&session, directory, "main.selka", "old main");
        try place(&session, directory, "other.selka", "same");
    }
    const inventory: Inventory = .{ .root = app, .modules = &.{
        .{ .path = "main.selka", .digest = try hexDigest(a, "old main") },
        .{ .path = "other.selka", .digest = try hexDigest(a, "same") },
    } };
    const main_path = try std.fs.path.join(a, &.{ app, "main.selka" });
    // `fix` changed the staged main.selka, and the user edited it meanwhile: the run refuses, naming it, and writes nothing.
    try place(&session, staged, "main.selka", "fixed main");
    try place(&session, app, "main.selka", "user's edit");
    try std.testing.expectError(error.Rejected, writeBack(&session, staged, inventory, "app"));
    try std.testing.expectEqualStrings("app/main.selka changed while `selka packages fix` ran, so none of its repairs were written back; run it again", session.message);
    try std.testing.expectEqualStrings("user's edit", try std.Io.Dir.cwd().readFileAlloc(std.testing.io, main_path, a, .limited(64)));
    // Unedited, the changed file is written back and the unchanged one is left as it is.
    try place(&session, app, "main.selka", "old main");
    try writeBack(&session, staged, inventory, "app");
    try std.testing.expectEqualStrings("fixed main", try std.Io.Dir.cwd().readFileAlloc(std.testing.io, main_path, a, .limited(64)));
    const other = try std.fs.path.join(a, &.{ app, "other.selka" });
    try std.testing.expectEqualStrings("same", try std.Io.Dir.cwd().readFileAlloc(std.testing.io, other, a, .limited(64)));
}

// spec-case: PACKAGES-LOCK-1
test "a package named like a standard module is refused before its root is read, a name that is not one is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    try std.testing.expectError(error.Rejected, packageFiles(&session, "strings", "/nowhere", "/"));
    try std.testing.expect(std.mem.startsWith(u8, session.message, "package strings is named like the standard module `strings`, which `import strings` always loads"));
    try std.testing.expectError(error.Rejected, packageFiles(&session, "json", "/nowhere", "/"));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "standard module `json`") != null);
    // `strings_extra` is no standard module: the refusal is the unreadable root, not the name.
    try std.testing.expectError(error.Rejected, packageFiles(&session, "strings_extra", "/nowhere/at/all", "/"));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "cannot resolve root") != null);
}

// spec-case: API-FILE-3
test "packages api writes back the interface files it wrote, changed or deleted, and nothing when one changed since the snapshot" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    const a = session.allocator;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const app = try std.fs.path.join(a, &.{ root, "app" });
    const staged = try std.fs.path.join(a, &.{ root, "stage" });
    for ([_][]const u8{ app, staged }) |directory| {
        try place(&session, directory, "main.selka", "main");
        try place(&session, directory, "util.selka", "util");
        try place(&session, directory, "old.api", "generated, source gone");
        try place(&session, directory, "util.api", "util v1");
    }
    const inventory: Inventory = .{ .root = app, .modules = &.{
        .{ .path = "main.selka", .digest = try hexDigest(a, "main") },
        .{ .path = "old.api", .digest = try hexDigest(a, "generated, source gone") },
        .{ .path = "util.api", .digest = try hexDigest(a, "util v1") },
        .{ .path = "util.selka", .digest = try hexDigest(a, "util") },
    } };
    // `api --write` wrote main.api, changed util.api and deleted old.api in the stage; the user edited util.api meanwhile.
    try place(&session, staged, "main.api", "main v1");
    try place(&session, staged, "util.api", "util v2");
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try std.fs.path.join(a, &.{ staged, "old.api" }));
    try place(&session, app, "util.api", "the user's edit");
    try std.testing.expectError(error.Rejected, writeInterfaces(&session, staged, inventory, "app"));
    try std.testing.expectEqualStrings("app/util.api changed while `selka packages build --command api` ran, so none of the interface files were written; run it again", session.message);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, try std.fs.path.join(a, &.{ app, "main.api" }), .{}));
    // Unedited, all three changes are written back.
    try place(&session, app, "util.api", "util v1");
    try writeInterfaces(&session, staged, inventory, "app");
    try std.testing.expectEqualStrings("main v1", try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(a, &.{ app, "main.api" }), a, .limited(64)));
    try std.testing.expectEqualStrings("util v2", try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fs.path.join(a, &.{ app, "util.api" }), a, .limited(64)));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(std.testing.io, try std.fs.path.join(a, &.{ app, "old.api" }), .{}));
}
