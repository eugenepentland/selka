//! Independent native bootstrap coordinator for pinned Selka components.
//! Source/archive identities are separate from locally qualified binary digests.
const std = @import("std");
const builtin = @import("builtin");
const files = @import("component_files.zig");
const archive = @import("component_archive.zig");
const Value = std.json.Value;
const Field = files.Field;
const cwd = std.Io.Dir.cwd;

const Config = struct {
    root: []const u8,
    zig: []const u8,
    cache: []const u8,
    install: []const u8,
    seed_source: ?[]const u8 = null,
    uncached: bool = false,
    seed_only: bool = false,
};
const Context = struct {
    a: std.mem.Allocator,
    io: std.Io,
    environ: *const std.process.Environ.Map,
    message: ?[]const u8 = null,

    fn fail(self: *Context, message: []const u8) error{CoordinatorFailure} {
        self.message = message;
        return error.CoordinatorFailure;
    }
    fn path(self: *Context, parts: []const []const u8) ![]const u8 {
        return files.join(self.a, parts);
    }
    fn hashValue(self: *Context, path_name: []const u8) !Value {
        const digest = try files.digest(self.io, path_name);
        return files.string(try self.a.dupe(u8, &digest));
    }
    fn checked(self: *Context, argv: []const []const u8, directory: ?[]const u8, environ: ?*const std.process.Environ.Map) ![]const u8 {
        const result = try std.process.run(std.heap.page_allocator, self.io, .{
            .argv = argv,
            .cwd = if (directory) |path_name| .{ .path = path_name } else .inherit,
            .environ_map = environ,
            .stdout_limit = .limited(1 << 20),
            .stderr_limit = .limited(1 << 20),
        });
        defer std.heap.page_allocator.free(result.stdout);
        defer std.heap.page_allocator.free(result.stderr);
        if (result.stderr.len != 0) try std.Io.File.stderr().writeStreamingAll(self.io, result.stderr);
        switch (result.term) {
            .exited => |status| if (status != 0) {
                self.message = try std.fmt.allocPrint(self.a, "command failed (exit {d}): {s}", .{ status, argv[0] });
                return error.CoordinatorFailure;
            },
            else => return self.fail("command terminated before qualification"),
        }
        return self.a.dupe(u8, result.stdout);
    }
    fn metadata(self: *Context, path_name: []const u8) !Value {
        return files.readJson(self.a, self.io, path_name) catch return self.fail("malformed or unreadable receipt/manifest");
    }
};

fn get(value: Value, key: []const u8) !Value {
    if (value != .object) return error.MalformedReceipt;
    return value.object.get(key) orelse error.MalformedReceipt;
}
fn text(value: Value) ![]const u8 {
    return if (value == .string) value.string else error.MalformedReceipt;
}
fn equals(a: std.mem.Allocator, lhs: Value, rhs: Value) !bool {
    const left = try files.canonical(a, lhs);
    defer a.free(left);
    const right = try files.canonical(a, rhs);
    defer a.free(right);
    return std.mem.eql(u8, left, right);
}
fn digestEquals(io: std.Io, path_name: []const u8, expected: []const u8) !bool {
    const actual = files.digest(io, path_name) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return std.mem.eql(u8, &actual, expected);
}
fn quotedField(value: []const u8, name: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, value, name) orelse return error.ToolchainEnvironment;
    const rest = value[start + name.len ..];
    const quote = std.mem.indexOfScalar(u8, rest, '"') orelse return error.ToolchainEnvironment;
    const after = rest[quote + 1 ..];
    const end = std.mem.indexOfScalar(u8, after, '"') orelse return error.ToolchainEnvironment;
    return after[0..end];
}

const Seed = struct { binary: []const u8, qualification: Value };
fn qualifySeed(ctx: *Context, config: Config) !Seed {
    const pin = try ctx.metadata(try ctx.path(&.{ config.root, "selfhost", "component-seed.json" }));
    const expected_version = try text(try get(pin, "zig"));
    const version = try ctx.checked(&.{ config.zig, "version" }, null, null);
    if (!std.mem.eql(u8, std.mem.trim(u8, version, "\r\n \t"), expected_version)) return ctx.fail("seed requires the pinned Zig version");
    const environment = try ctx.checked(&.{ config.zig, "env" }, null, null);
    const library_path = try quotedField(environment, ".lib_dir");
    const target = try quotedField(environment, ".target");
    const library_digest = blk: {
        var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const identity = try files.tree(a, ctx.io, library_path);
        const canonical = try files.canonical(a, identity);
        break :blk files.textDigest(canonical);
    };
    const recipe = try files.object(ctx.a, &.{
        .{ .name = "pin", .value = pin },
        .{ .name = "zig_sha256", .value = try ctx.hashValue(config.zig) },
        .{ .name = "zig_library_sha256", .value = files.string(try ctx.a.dupe(u8, &library_digest)) },
        .{ .name = "target", .value = files.string(target) },
    });
    const recipe_text = try files.canonical(ctx.a, recipe);
    defer ctx.a.free(recipe_text);
    const key = files.textDigest(recipe_text);
    const directory = try ctx.path(&.{ config.cache, "seeds", &key });
    const source = try ctx.path(&.{ directory, "source" });
    const binary = try ctx.path(&.{ source, "zig-out", "focus", "mylang" });
    const receipt = try ctx.path(&.{ directory, "receipt.json" });
    if (try files.exists(ctx.io, receipt)) {
        const qualification = try ctx.metadata(receipt);
        if (!try equals(ctx.a, try get(qualification, "recipe"), recipe) or !try digestEquals(ctx.io, binary, try text(try get(qualification, "sha256")))) return ctx.fail("qualified seed digest mismatch; remove corrupt seed cache and rebuild");
        return .{ .binary = binary, .qualification = qualification };
    }
    try files.remove(ctx.io, directory);
    try cwd().createDirPath(ctx.io, source);
    errdefer files.discard(ctx.io, directory);
    const archive_path = try ctx.path(&.{ directory, "seed.tar" });
    if (config.seed_source) |supplied| {
        try files.copy(ctx.io, supplied, archive_path, 0o600);
    } else {
        const git = try findTool(ctx, "git");
        _ = try ctx.checked(&.{ git, "-C", config.root, "archive", try text(try get(pin, "commit")), "-o", archive_path }, null, null);
    }
    if (!try digestEquals(ctx.io, archive_path, try text(try get(pin, "archive_sha256")))) return ctx.fail("seed archive digest differs from immutable pin");
    try archive.extract(ctx.io, archive_path, source);
    const version_pin = try cwd().readFileAlloc(ctx.io, try ctx.path(&.{ source, ".zigversion" }), ctx.a, .limited(4096));
    if (!std.mem.eql(u8, std.mem.trim(u8, version_pin, "\r\n \t"), expected_version)) return ctx.fail("seed archive Zig pin mismatch");
    const guardian = try ctx.path(&.{ std.fs.path.dirname(config.root) orelse "/", "guardian-zig" });
    if (!try files.exists(ctx.io, guardian)) return ctx.fail("seed build requires sibling guardian-zig dependency");
    const guardian_real = try cwd().realPathFileAlloc(ctx.io, guardian, ctx.a);
    try cwd().symLink(ctx.io, guardian_real, try ctx.path(&.{ directory, "guardian-zig" }), .{ .is_directory = true });
    const output = try ctx.checked(&.{ config.zig, "build", "affected-compiler", "-Doptimize=ReleaseFast", "-j1" }, source, null);
    if (output.len != 0) try std.Io.File.stderr().writeStreamingAll(ctx.io, output);
    const qualification = try files.object(ctx.a, &.{
        .{ .name = "recipe", .value = recipe },
        .{ .name = "sha256", .value = try ctx.hashValue(binary) },
        .{ .name = "source_identity", .value = try files.tree(ctx.a, ctx.io, try ctx.path(&.{ source, "src" })) },
    });
    try files.atomicJson(ctx.a, ctx.io, receipt, qualification, 0o600);
    return .{ .binary = binary, .qualification = qualification };
}

fn nativeTarget(ctx: *Context) !Value {
    var fields: std.json.ObjectMap = .empty;
    const cpuinfo = if (builtin.os.tag == .linux) try files.firstBlock(ctx.a, ctx.io, "/proc/cpuinfo") else "";
    var lines = std.mem.splitScalar(u8, cpuinfo, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const wanted = [_][]const u8{ "vendor_id", "cpu family", "model", "model name", "stepping", "flags", "Features", "CPU implementer", "CPU part" };
        for (wanted) |candidate| if (std.mem.eql(u8, name, candidate)) {
            try fields.put(ctx.a, name, files.string(std.mem.trim(u8, line[colon + 1 ..], " \t")));
            break;
        };
    }
    if (builtin.os.tag == .linux and fields.count() == 0) return ctx.fail("native CPU metadata is empty; cannot qualify -march=native artifacts");
    return files.object(ctx.a, &.{
        .{ .name = "os", .value = files.string(@tagName(builtin.os.tag)) },
        .{ .name = "machine", .value = files.string(@tagName(builtin.cpu.arch)) },
        .{ .name = "cpu", .value = .{ .object = fields } },
    });
}

fn snapshot(ctx: *Context, source: []const u8, destination: []const u8) !void {
    try cwd().createDirPath(ctx.io, destination);
    const dir = try cwd().openDir(ctx.io, source, .{ .iterate = true });
    defer dir.close(ctx.io);
    var walker = try dir.walk(ctx.a);
    defer walker.deinit();
    while (try walker.next(ctx.io)) |entry| {
        const output = try ctx.path(&.{ destination, entry.path });
        switch (entry.kind) {
            .directory => try cwd().createDirPath(ctx.io, output),
            .file, .sym_link => {
                const input = try ctx.path(&.{ source, entry.path });
                const stat = try cwd().statFile(ctx.io, input, .{});
                if (stat.kind != .file) return ctx.fail("component sources must contain ordinary files and directories");
                try files.copy(ctx.io, input, output, 0o644);
            },
            else => return ctx.fail("component sources contain an unsupported file type"),
        }
    }
}

const Component = struct { source: []const u8, name: []const u8, entry: []const u8 = "main.my", protocol: i64 = 1, schema: i64 = 1 };
const components = [_]Component{
    .{ .source = "test_index", .name = "test-index" },
    .{ .source = "cache_plan", .name = "cache-plan", .protocol = 2, .schema = 2 },
    .{ .source = "lexer_pilot", .name = "lexer-pilot", .schema = 2 },
    .{ .source = "parser_pilot", .name = "parser-pilot", .entry = "full_adapter.my", .schema = 2 },
    .{ .source = "declaration_index", .name = "declaration-index" },
};

fn component(ctx: *Context, config: Config, seed: Seed, descriptor: Component) ![]const u8 {
    const sources = try ctx.path(&.{ config.root, "selfhost", "components", descriptor.source });
    const tool = try std.process.executablePathAlloc(ctx.io, ctx.a);
    var flags = std.json.Array.init(ctx.a);
    try flags.append(files.string("debug"));
    try flags.append(files.string("fresh-private-cache"));
    try flags.append(files.string("private-zig-global-v1"));
    const identity = try files.object(ctx.a, &.{
        .{ .name = "format", .value = files.integer(2) },
        .{ .name = "component", .value = files.string(descriptor.name) },
        .{ .name = "build_cache_root", .value = files.string(config.cache) },
        .{ .name = "protocol", .value = files.integer(descriptor.protocol) },
        .{ .name = "schema", .value = files.integer(descriptor.schema) },
        .{ .name = "target", .value = try nativeTarget(ctx) },
        .{ .name = "flags", .value = .{ .array = flags } },
        .{ .name = "seed", .value = seed.qualification },
        .{ .name = "sources", .value = try files.tree(ctx.a, ctx.io, sources) },
        .{ .name = "coordinator_sha256", .value = try ctx.hashValue(tool) },
    });
    const identity_text = try files.canonical(ctx.a, identity);
    defer ctx.a.free(identity_text);
    const key = files.textDigest(identity_text);
    const artifacts = try ctx.path(&.{ config.cache, "artifacts" });
    try cwd().createDirPath(ctx.io, artifacts);
    const stored = try ctx.path(&.{ artifacts, &key });
    const executable = try ctx.path(&.{ stored, descriptor.name });
    const receipt = try ctx.path(&.{ stored, "receipt.json" });
    const has_receipt = try files.exists(ctx.io, receipt);
    var metadata: Value = undefined;
    if (has_receipt) {
        metadata = try ctx.metadata(receipt);
        if (!try equals(ctx.a, try get(metadata, "identity"), identity) or !try digestEquals(ctx.io, executable, try text(try get(metadata, "sha256")))) return ctx.fail("component cache digest mismatch");
    }
    if (!has_receipt or config.uncached) {
        const build_name = try std.fmt.allocPrint(ctx.a, "{s}.build", .{key});
        const work = try ctx.path(&.{ artifacts, build_name });
        try files.remove(ctx.io, work);
        try cwd().createDirPath(ctx.io, work);
        defer files.discard(ctx.io, work);
        const copied = try ctx.path(&.{ work, "src" });
        try snapshot(ctx, sources, copied);
        if (!try equals(ctx.a, try files.tree(ctx.a, ctx.io, copied), try get(identity, "sources"))) return ctx.fail("component source changed during snapshot");
        const output = try ctx.path(&.{ work, descriptor.name });
        var environment = std.process.Environ.Map.init(ctx.a);
        defer environment.deinit();
        var iterator = ctx.environ.iterator();
        while (iterator.next()) |entry| {
            if (std.mem.startsWith(u8, entry.key_ptr.*, "MYLANG_") or std.mem.eql(u8, entry.key_ptr.*, "ZIG")) continue;
            try environment.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        try environment.put("MYLANG_ZIG", config.zig);
        try environment.put("MYLANG_CORE_RUNTIME_CACHE", "");
        // Shared Zig CRT objects retain the directory of their first compilation
        // in DWARF. A deterministic private cache makes every byte reproducible.
        try environment.put("ZIG_GLOBAL_CACHE_DIR", try ctx.path(&.{ work, "cache", "zig-global" }));
        const compile_output = try ctx.checked(&.{ seed.binary, "build", try ctx.path(&.{ copied, descriptor.entry }), "-o", output, "--cache-dir", try ctx.path(&.{ work, "cache" }) }, work, &environment);
        if (compile_output.len != 0) try std.Io.File.stderr().writeStreamingAll(ctx.io, compile_output);
        const fresh = try files.object(ctx.a, &.{ .{ .name = "identity", .value = identity }, .{ .name = "sha256", .value = try ctx.hashValue(output) } });
        if (has_receipt) {
            const expected_digest = try text(try get(metadata, "sha256"));
            const actual_digest = try text(try get(fresh, "sha256"));
            if (!std.mem.eql(u8, expected_digest, actual_digest)) {
                ctx.message = try std.fmt.allocPrint(ctx.a, "uncached {s} build is not reproducible: expected {s}, got {s}", .{ descriptor.name, expected_digest, actual_digest });
                return error.CoordinatorFailure;
            }
        } else {
            metadata = fresh;
            try files.atomicJson(ctx.a, ctx.io, try ctx.path(&.{ work, "receipt.json" }), metadata, 0o600);
            try files.remove(ctx.io, try ctx.path(&.{ work, "cache" }));
            try files.remove(ctx.io, copied);
            try files.remove(ctx.io, stored);
            try cwd().rename(work, cwd(), stored, ctx.io);
        }
    }
    try cwd().createDirPath(ctx.io, config.install);
    const expected = try text(try get(metadata, "sha256"));
    const name = try std.fmt.allocPrint(ctx.a, "{s}-{s}", .{ descriptor.name, expected });
    const installed = try ctx.path(&.{ config.install, name });
    if (try files.exists(ctx.io, installed)) {
        if (!try digestEquals(ctx.io, installed, expected)) return ctx.fail("installed component digest mismatch");
    } else try files.copy(ctx.io, executable, installed, 0o555);
    const manifest = try files.object(ctx.a, &.{
        .{ .name = "format", .value = files.integer(1) },                     .{ .name = "component", .value = files.string(descriptor.name) },
        .{ .name = "protocol", .value = files.integer(descriptor.protocol) }, .{ .name = "schema", .value = files.integer(descriptor.schema) },
        .{ .name = "artifact", .value = files.string(name) },                 .{ .name = "sha256", .value = files.string(expected) },
        .{ .name = "key", .value = files.string(try ctx.a.dupe(u8, &key)) },
    });
    try files.atomicJson(ctx.a, ctx.io, try ctx.path(&.{ config.install, try std.fmt.allocPrint(ctx.a, "{s}.json", .{descriptor.name}) }), manifest, 0o644);
    return ctx.a.dupe(u8, &key);
}

fn findTool(ctx: *Context, name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return cwd().realPathFileAlloc(ctx.io, name, ctx.a);
    var directories = std.mem.splitScalar(u8, ctx.environ.get("PATH") orelse "", std.fs.path.delimiter);
    while (directories.next()) |directory| {
        const candidate = try ctx.path(&.{ if (directory.len == 0) "." else directory, name });
        if (try files.exists(ctx.io, candidate)) return cwd().realPathFileAlloc(ctx.io, candidate, ctx.a);
    }
    return ctx.fail("required executable missing; use --zig or supply --seed-source for a seed without Git");
}
fn run(ctx: *Context, args: []const []const u8) !void {
    const current = try cwd().realPathFileAlloc(ctx.io, ".", ctx.a);
    var root: []const u8 = current;
    var zig: []const u8 = ctx.environ.get("MYLANG_ZIG") orelse "zig";
    var cache: ?[]const u8 = ctx.environ.get("MYLANG_COMPONENT_CACHE");
    var install: ?[]const u8 = null;
    var source_archive: ?[]const u8 = null;
    var uncached = false;
    var seed_only = false;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try std.Io.File.stdout().writeStreamingAll(ctx.io, "usage: selka-components [--root DIR] [--zig PATH] [--cache-dir DIR] [--install-dir DIR] [--seed-source TAR] [--uncached] [--seed-only]\n");
            return;
        }
        if (std.mem.eql(u8, arg, "--uncached")) {
            uncached = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--seed-only")) {
            seed_only = true;
            continue;
        }
        index += 1;
        if (index >= args.len) return ctx.fail("option requires a value");
        if (std.mem.eql(u8, arg, "--root")) root = args[index] else if (std.mem.eql(u8, arg, "--zig")) zig = args[index] else if (std.mem.eql(u8, arg, "--cache-dir")) cache = args[index] else if (std.mem.eql(u8, arg, "--install-dir")) install = args[index] else if (std.mem.eql(u8, arg, "--seed-source")) source_archive = args[index] else return ctx.fail("unknown coordinator option");
    }
    root = try cwd().realPathFileAlloc(ctx.io, root, ctx.a);
    const home = ctx.environ.get("HOME") orelse if (cache == null) return ctx.fail("HOME is unset; supply --cache-dir") else current;
    const config: Config = .{
        .root = root,
        .zig = try findTool(ctx, zig),
        .cache = try std.fs.path.resolve(ctx.a, &.{ current, cache orelse try ctx.path(&.{ home, ".cache", "mylang", "components" }) }),
        .install = try std.fs.path.resolve(ctx.a, &.{ current, install orelse try ctx.path(&.{ root, "zig-out", "libexec", "mylang", "components" }) }),
        .seed_source = if (source_archive) |path_name| try cwd().realPathFileAlloc(ctx.io, path_name, ctx.a) else null,
        .uncached = uncached,
        .seed_only = seed_only,
    };
    try cwd().createDirPath(ctx.io, config.cache);
    const lock = try cwd().createFile(ctx.io, try ctx.path(&.{ config.cache, "build.lock" }), .{ .truncate = false, .permissions = .fromMode(0o600) });
    defer lock.close(ctx.io);
    try lock.lock(ctx.io, .exclusive);
    defer lock.unlock(ctx.io);
    const seed = try qualifySeed(ctx, config);
    if (seed_only) {
        try std.Io.File.stdout().writeStreamingAll(ctx.io, seed.binary);
        try std.Io.File.stdout().writeStreamingAll(ctx.io, "\n");
    } else {
        for (components) |descriptor| {
            const output = try component(ctx, config, seed, descriptor);
            try std.Io.File.stdout().writeStreamingAll(ctx.io, output);
            try std.Io.File.stdout().writeStreamingAll(ctx.io, "\n");
        }
    }
}

fn diagnostic(io: std.Io, message: []const u8) void {
    const stderr = std.Io.File.stderr();
    stderr.writeStreamingAll(io, "components: ") catch std.process.exit(1);
    stderr.writeStreamingAll(io, message) catch std.process.exit(1);
    stderr.writeStreamingAll(io, "\n") catch std.process.exit(1);
}

/// Native entry point. Expected failures produce one concise diagnostic.
pub fn main(init: std.process.Init) void {
    var ctx: Context = .{ .a = init.arena.allocator(), .io = init.io, .environ = init.environ_map };
    const args = init.minimal.args.toSlice(ctx.a) catch {
        diagnostic(init.io, "cannot read arguments");
        std.process.exit(1);
    };
    run(&ctx, args) catch |err| {
        const message = ctx.message orelse switch (err) {
            error.MalformedReceipt => "malformed receipt; remove the invalid cache entry and rebuild",
            error.UnsafeSeedArchive => "seed archive contains unsafe paths or links",
            error.ToolchainEnvironment => "cannot identify pinned Zig library and native target",
            error.FileNotFound => "required file missing; verify --root, --zig and --seed-source",
            else => @errorName(err),
        };
        diagnostic(init.io, message);
        std.process.exit(1);
    };
}
