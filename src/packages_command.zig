//! `mylang packages lock|build`: offline local dependencies from explicit
//! namespaces and content-locked files.
//!
//! `lock CONFIG --output LOCK` reads `{"packages":[{"name":...,"root":...}]}`,
//! resolves each root, inventories its `.my` sources with one SHA-256 each and
//! writes a `package-lock-v1` file. `build ENTRY --lock LOCK` re-inventories the
//! application directory and every locked package, refuses drift, collisions,
//! reserved names and symbolic links, copies the verified bytes into a private
//! staging directory, and runs this same executable's `project-dependencies`
//! and then one project command (`check-project` by default) over the staged
//! entry, so neither the application tree nor a shared checkout is ever compiled
//! in place. This replaced the Python prototype `scripts/packages.py`; the lock
//! and receipt formats are unchanged.
const std = @import("std");
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
const commands = [_][]const u8{ "check-project", "run-project", "index-project", "emit-project-qbe" };
/// Refusal for a file that could not be opened, stated or read.
const unreadable = "cannot read {s}: {t}";
/// Refusal for a lock that is not a `package-lock-v1` document.
const unsupported_lock = "unsupported package lock: {s}";
/// Module source file suffix; nothing else is inventoried.
const source_suffix = ".my";
/// Prefix reserved for the standard modules the compiler embeds.
const reserved_prefix = "std_";
/// The project configuration copied into the staged snapshot.
const config_name = @import("native_test_root").compiler_language.project_config.config_name;

/// Usage text for `mylang packages --help` and a malformed command line.
const usage =
    \\usage: mylang packages lock CONFIG.json --output LOCK.json
    \\       mylang packages build ENTRY.my --lock LOCK.json [--command check-project|run-project|index-project|emit-project-qbe] [--receipt FILE]
    \\  lock inventories every package root CONFIG names ({"packages":[{"name":...,"root":...}]}) and
    \\  writes each module's SHA-256 into a package-lock-v1 file. build verifies the application
    \\  directory and every locked package against it, stages the verified bytes privately, and runs
    \\  project-dependencies and then the command over the staged entry; --receipt records the lock
    \\  and compiler identities with the dependency report. The command's exit status is forwarded
    \\  (for run-project, the program's own). A rejected lock or snapshot exits 2.
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

    /// Record why the command refuses, for `run` to print, and fail.
    fn reject(self: *Session, comptime format: []const u8, arguments: anytype) error{Rejected} {
        self.message = std.fmt.allocPrint(self.allocator, format, arguments) catch "out of memory";
        return error.Rejected;
    }
};

/// One inventoried module: its path relative to the source root, `/`-separated,
/// and the lowercase hexadecimal SHA-256 of its bytes.
const Module = struct { path: []const u8, digest: []const u8 };
/// One verified source root and its sorted modules.
const Inventory = struct { root: []const u8, modules: []const Module };
/// The parsed command line of either subcommand.
const Request = struct {
    positional: ?[]const u8 = null,
    output: ?[]const u8 = null,
    lock: ?[]const u8 = null,
    command: ?[]const u8 = null,
    receipt: ?[]const u8 = null,
};

/// Run `mylang packages ARGS`, returning the process exit status. `identity` is
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
    const request = try parse(args[1..]);
    const positional = request.positional orelse return error.Usage;
    if (std.mem.eql(u8, args[0], "lock")) {
        if (request.lock != null or request.command != null or request.receipt != null) return error.Usage;
        try lock(session, positional, request.output orelse return error.Usage);
        return 0;
    }
    if (std.mem.eql(u8, args[0], "build")) {
        if (request.output != null) return error.Usage;
        const command = request.command orelse commands[0];
        if (!known(command)) return error.Usage;
        return build(session, process, .{ .positional = positional, .lock = request.lock orelse return error.Usage, .command = command, .receipt = request.receipt }, identity);
    }
    return error.Usage;
}

/// Parse `--output`, `--lock`, `--command` and `--receipt` (each as `--flag
/// VALUE` or `--flag=VALUE`, at most once) around exactly one positional.
fn parse(args: []const []const u8) error{Usage}!Request {
    var request: Request = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
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

fn known(command: []const u8) bool {
    for (commands) |candidate| if (std.mem.eql(u8, candidate, command)) return true;
    return false;
}

/// A package namespace: an ASCII identifier that does not start with the
/// reserved standard-module prefix.
fn validNamespace(name: []const u8) bool {
    if (name.len == 0 or std.mem.startsWith(u8, name, reserved_prefix)) return false;
    if (!std.ascii.isAlphabetic(name[0]) and name[0] != '_') return false;
    for (name[1..]) |character| if (!std.ascii.isAlphanumeric(character) and character != '_') return false;
    return true;
}

/// Whether a module path belongs to package `name`: `name.my` itself or any
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

fn byPath(_: void, left: Module, right: Module) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

/// Every `.my` source under `root`, sorted by path, with its SHA-256. The walk
/// visits at most `max_entries` entries and reads at most `package_byte_budget` bytes.
fn sources(session: *Session, root: []const u8) Error![]const Module {
    const io = session.io;
    const allocator = session.allocator;
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
        if (!try sourceEntry(session, entry)) continue;
        const bytes = try boundedRead(session, entry.dir, entry.basename, entry.path, package_byte_budget - total);
        total += bytes.len;
        try modules.append(allocator, .{ .path = try allocator.dupe(u8, entry.path), .digest = try hexDigest(allocator, bytes) });
    }
    std.mem.sort(Module, modules.items, {}, byPath);
    return modules.items;
}

/// Resolve one package's root against `base` and inventory it: the namespace
/// must be valid, the root must exist and hold at least one source, and every
/// source must sit inside the namespace.
fn packageFiles(session: *Session, name: []const u8, root: []const u8, base: []const u8) Error!Inventory {
    if (!validNamespace(name)) return session.reject("invalid or reserved package namespace: {s}", .{name});
    const joined = if (std.fs.path.isAbsolute(root)) root else try std.fs.path.join(session.allocator, &.{ base, root });
    const resolved = std.Io.Dir.cwd().realPathFileAlloc(session.io, joined, session.allocator) catch |err|
        return session.reject("package {s}: cannot resolve root {s}: {t}", .{ name, joined, err });
    const modules = try sources(session, resolved);
    if (modules.len == 0) return session.reject("empty dependency: {s}", .{name});
    for (modules) |module| {
        if (!inNamespace(name, module.path)) return session.reject("dependency source must declare its package namespace: {s}", .{module.path});
    }
    return .{ .root = resolved, .modules = modules };
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
    const resolved = std.Io.Dir.cwd().realPathFileAlloc(session.io, path, session.allocator) catch |err|
        return session.reject("cannot resolve {s}: {t}", .{ path, err });
    return std.fs.path.dirname(resolved) orelse resolved;
}

fn parseJson(session: *Session, bytes: []const u8, shown: []const u8) Error!std.json.Value {
    return std.json.parseFromSliceLeaky(std.json.Value, session.allocator, bytes, .{}) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => session.reject("{s} is not JSON: {t}", .{ shown, err }),
    };
}

/// `mylang packages lock CONFIG --output LOCK`.
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

/// What `build` was asked for, once the command line checked.
const Build = struct { positional: []const u8, lock: []const u8, command: []const u8, receipt: ?[]const u8 };

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
    const app_root = try parentOf(session, request.positional);
    const app = try sources(session, app_root);
    const entry_name = std.fs.path.basename(request.positional);
    for (app) |module| {
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
        try inventories.append(allocator, inventory);
    }
    return inventories.items;
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

/// Write `bytes` at `relative` under `directory`, creating its parents.
fn place(session: *Session, directory: []const u8, relative: []const u8, bytes: []const u8) Error!void {
    const destination = try std.fs.path.join(session.allocator, &.{ directory, relative });
    if (std.fs.path.dirname(destination)) |parent| std.Io.Dir.cwd().createDirPath(session.io, parent) catch |err|
        return session.reject("cannot stage {s}: {t}", .{ relative, err });
    std.Io.Dir.cwd().writeFile(session.io, .{ .sub_path = destination, .data = bytes }) catch |err|
        return session.reject("cannot stage {s}: {t}", .{ relative, err });
}

/// Mirror the nearest `mylang.json` into the staged root, so the compiler's own
/// discovery and import-policy enforcement run against the snapshot. When the
/// configuration sits in the application directory its relative policy file
/// comes along; an ancestor's configuration is copied without its policy, so a
/// policy the snapshot cannot hold is reported missing rather than skipped.
fn copyProjectConfig(session: *Session, app_root: []const u8, directory: []const u8) Error!void {
    var base: ?[]const u8 = app_root;
    while (base) |candidate| : (base = std.fs.path.dirname(candidate)) {
        const config = try std.fs.path.join(session.allocator, &.{ candidate, config_name });
        const info = std.Io.Dir.cwd().statFile(session.io, config, .{}) catch continue;
        if (info.kind != .file) continue;
        const raw = try boundedRead(session, std.Io.Dir.cwd(), config, config, package_byte_budget);
        try place(session, directory, config_name, raw);
        if (!std.mem.eql(u8, candidate, app_root)) return;
        return copyPolicy(session, candidate, directory, raw);
    }
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
    const parent = if (configured.len == 0) @import("qbe_build_io.zig").default_scratch_root else configured;
    var random: [8]u8 = undefined;
    std.Io.random(session.io, &random);
    const name = try std.fmt.allocPrint(session.allocator, "mylang-packages-{s}", .{std.fmt.bytesToHex(random, .lower)});
    const path = try std.fs.path.join(session.allocator, &.{ parent, name });
    std.Io.Dir.cwd().createDirPath(session.io, path) catch |err| return session.reject("cannot create staging directory {s}: {t}", .{ path, err });
    return path;
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

/// `mylang packages build ENTRY --lock LOCK [--command C] [--receipt FILE]`.
fn build(session: *Session, process: std.process.Init, request: Build, identity: []const u8) Error!u8 {
    const lock_bytes = try boundedRead(session, std.Io.Dir.cwd(), request.lock, request.lock, package_byte_budget);
    const document = try parseJson(session, lock_bytes, request.lock);
    const version = stringField(document, "version") orelse "";
    if (!std.mem.eql(u8, version, lock_version)) return session.reject(unsupported_lock, .{request.lock});
    const inventories = try verify(session, request, document);
    const directory = try makeStage(session, process.environ_map);
    defer discard(session.io, directory);
    try stage(session, directory, inventories);
    try copyProjectConfig(session, inventories[0].root, directory);
    const entry = try std.fs.path.join(session.allocator, &.{ directory, std.fs.path.basename(request.positional) });
    const compiler = std.process.executablePathAlloc(session.io, session.allocator) catch |err|
        return session.reject("cannot locate this compiler: {t}", .{err});
    const dependencies = std.process.run(session.allocator, session.io, .{ .argv = &.{ compiler, "project-dependencies", entry } }) catch |err|
        return session.reject("cannot run project-dependencies: {t}", .{err});
    if (status(dependencies.term) != 0) {
        std.Io.File.stdout().writeStreamingAll(session.io, dependencies.stdout) catch return status(dependencies.term);
        std.Io.File.stderr().writeStreamingAll(session.io, dependencies.stderr) catch return status(dependencies.term);
        return status(dependencies.term);
    }
    const report_value = try parseJson(session, dependencies.stdout, "the project-dependencies report");
    const implementation: std.json.Value = if (report_value == .object) report_value.object.get("implementation") orelse .null else .null;
    const checked_by = stringField(implementation, "compiler_sha256") orelse "";
    if (!std.mem.eql(u8, checked_by, identity)) return session.reject("the snapshot was checked by compiler {s}, not this one ({s})", .{ checked_by, identity });
    if (request.receipt) |path| try writeReceipt(session, path, .{ .lock = document, .identity = identity, .dependencies = report_value });
    return runCommand(session, compiler, request.command, entry);
}

/// The receipt's three inputs.
const Receipt = struct { lock: std.json.Value, identity: []const u8, dependencies: std.json.Value };

/// Record the lock identity (SHA-256 of its compact JSON), this compiler's
/// identity and the staged snapshot's dependency report. It is written once
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
/// streams and forward its exit status; `run-project` prints its result.
fn runCommand(session: *Session, compiler: []const u8, command: []const u8, entry: []const u8) Error!u8 {
    const printing = std.mem.eql(u8, command, "run-project");
    const with_result = [_][]const u8{ compiler, command, entry, "--print-result" };
    const argv: []const []const u8 = if (printing) &with_result else with_result[0..3];
    var child = std.process.spawn(session.io, .{ .argv = argv }) catch |err| return session.reject("cannot run {s}: {t}", .{ command, err });
    const term = child.wait(session.io) catch |err| return session.reject("cannot wait for {s}: {t}", .{ command, err });
    return status(term);
}

/// A throwaway session over the testing allocator's arena.
fn testSession(arena: *std.heap.ArenaAllocator) Session {
    return .{ .allocator = arena.allocator(), .io = std.testing.io };
}

// spec-case: PACKAGES-LOCK-1
test "package namespaces are ASCII identifiers outside the reserved std_ prefix and own name.my and name/" {
    try std.testing.expect(validNamespace("numbers"));
    try std.testing.expect(validNamespace("_private2"));
    try std.testing.expect(!validNamespace("std_numbers"));
    try std.testing.expect(!validNamespace("2numbers"));
    try std.testing.expect(!validNamespace("num-bers"));
    try std.testing.expect(!validNamespace(""));
    try std.testing.expect(inNamespace("numbers", "numbers.my"));
    try std.testing.expect(inNamespace("numbers", "numbers/extra.my"));
    try std.testing.expect(!inNamespace("numbers", "numbersextra.my"));
    try std.testing.expect(!inNamespace("numbers", "other.my"));
    try std.testing.expect(climbs("a/../b.my"));
    try std.testing.expect(!climbs("a/..b.my"));
}

// spec-case: PACKAGES-LOCK-1
test "a package inventory hashes sorted .my sources and refuses symbolic-link sources and directories" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var session = testSession(&arena);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "lib/numbers");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/numbers/extra.my", .data = "b" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/numbers.my", .data = "a" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/notes.txt", .data = "ignored" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, "lib", session.allocator);
    const modules = try sources(&session, root);
    try std.testing.expectEqual(@as(usize, 2), modules.len);
    try std.testing.expectEqualStrings("numbers.my", modules[0].path);
    try std.testing.expectEqualStrings("numbers/extra.my", modules[1].path);
    try std.testing.expectEqualStrings(try hexDigest(session.allocator, "a"), modules[0].digest);
    try temporary.dir.symLink(std.testing.io, "numbers.my", "lib/alias.my", .{});
    try std.testing.expectError(error.Rejected, sources(&session, root));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "symbolic-link sources") != null);
    try temporary.dir.deleteFile(std.testing.io, "lib/alias.my");
    try temporary.dir.symLink(std.testing.io, "numbers", "lib/linked", .{ .is_directory = true });
    try std.testing.expectError(error.Rejected, sources(&session, root));
    try std.testing.expect(std.mem.indexOf(u8, session.message, "symbolic-link directories") != null);
}

// spec-case: PACKAGES-BUILD-1
test "package command lines take one positional and each flag once, spaced or with =" {
    const parsed = try parse(&.{ "app/main.my", "--lock=l.json", "--command", "run-project", "--receipt", "r.json" });
    try std.testing.expectEqualStrings("app/main.my", parsed.positional.?);
    try std.testing.expectEqualStrings("l.json", parsed.lock.?);
    try std.testing.expectEqualStrings("run-project", parsed.command.?);
    try std.testing.expectEqualStrings("r.json", parsed.receipt.?);
    try std.testing.expectError(error.Usage, parse(&.{ "a.my", "b.my" }));
    try std.testing.expectError(error.Usage, parse(&.{ "a.my", "--lock", "x", "--lock=y" }));
    try std.testing.expectError(error.Usage, parse(&.{ "a.my", "--compiler", "zig-out/bin/mylang" }));
    try std.testing.expectError(error.Usage, parse(&.{ "a.my", "--lock" }));
    try std.testing.expect(known("emit-project-qbe"));
    try std.testing.expect(!known("run"));
}
