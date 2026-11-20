//! Native coordinator that builds the Selka components with the compiler `zig build` has just built (`--compiler`).
//! A component's cache key binds that compiler's digest, the Zig toolchain, the toolchain identity the compiler computes for it
//! (the system libraries built programs load, the CPU, the Zig distribution: `selka native show --digest`), the native
//! target and the component sources. A change of that identity, as a library update is, makes a new receipt.
const std = @import("std");
const builtin = @import("builtin");
const files = @import("component_files.zig");
const builder = @import("component_builder_identity.zig");
const Value = std.json.Value;
const Field = files.Field;
const cwd = std.Io.Dir.cwd;

const Config = struct {
    root: []const u8,
    zig: []const u8,
    /// The compiler that compiles the components; required by every mode but `--install-from`.
    compiler: []const u8,
    cache: []const u8,
    install: []const u8,
    uncached: bool = false,
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

/// The compiler that compiles the components, the SHA-256 of its bytes taken before the first use, and the Zig toolchain
/// it links with (`toolchainRecipe`), taken at the same time.
const Compiler = struct { binary: []const u8, sha256: []const u8, toolchain: Value };

/// The placement variables that name a store the component compiler's own builds open (`src/environment_identity.zon`):
/// the compiler store, the test store and the stage store's shared half. They pass through so that a request that gives
/// its workers stores of its own (the complete gate does) gives the component compiler the same, and that compiler never
/// opens the per-user ones behind its back. A store location never reaches a component's bytes (its objects are content-keyed).
/// Left out on purpose: `SELKA_CORE_RUNTIME_CACHE` (set empty below, so the object store is not used at all),
/// `SELKA_FRONTEND_CACHE` (the build's `--cache-dir` already holds the front end's caches), `SELKA_CORE_TEST_CACHE`
/// (only the core test harness reads it), `SELKA_VERIFICATION_SHARED_CACHE` (read by the verification scripts only),
/// `SELKA_STORE_SETTINGS` (records where a project's `selka.json` set a location, not a location) and
/// `SELKA_COMPONENT_DIR` (the installed components: the component compiler runs with the built-in implementations).
pub const store_location_variables = [_][]const u8{
    "SELKA_COMPILER_SHARED_CACHE",
    "SELKA_TEST_SHARED_CACHE",
    "SELKA_STAGE_SHARED_CACHE",
};

/// The environment the builder's children start from, made from PROCESS: every variable but `ZIG` and the `SELKA_` ones,
/// which are dropped on purpose (a hermetic build), plus the store locations in `store_location_variables` that PROCESS
/// names (an empty value, which disables a store, included).
pub fn inheritedEnvironment(a: std.mem.Allocator, process: *const std.process.Environ.Map) !std.process.Environ.Map {
    var environment = std.process.Environ.Map.init(a);
    errdefer environment.deinit();
    var iterator = process.iterator();
    while (iterator.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, "SELKA_") or std.mem.eql(u8, entry.key_ptr.*, "ZIG")) continue;
        try environment.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    for (store_location_variables) |name| {
        if (process.get(name)) |value| try environment.put(name, value);
    }
    return environment;
}

fn componentEnvironment(ctx: *Context, config: Config, work: []const u8) !std.process.Environ.Map {
    var environment = try inheritedEnvironment(ctx.a, ctx.environ);
    errdefer environment.deinit();
    try environment.put("SELKA_ZIG", config.zig);
    try environment.put("SELKA_CORE_RUNTIME_CACHE", "");
    // No cycle: the compiler that builds the components plans its build and indexes its tests with the built-in
    // implementations, never with a component.
    try environment.put("SELKA_CACHE_PLAN_MODE", "reference");
    try environment.put("SELKA_TEST_INDEX_MODE", "reference");
    try environment.put("ZIG_GLOBAL_CACHE_DIR", try ctx.path(&.{ work, "cache", "zig-global" }));
    try environment.put("ZIG_LOCAL_CACHE_DIR", try ctx.path(&.{ work, "cache", "zig-local" }));
    const temporary = try ctx.path(&.{ work, "tmp" });
    try environment.put("TMPDIR", temporary);
    return environment;
}

fn verifyCompiler(ctx: *Context, compiler: Compiler) !void {
    if (!try digestEquals(ctx.io, compiler.binary, compiler.sha256)) return ctx.fail("component compiler changed during component build");
}

/// Check that the compiler and the toolchain are still the ones the build began with.
fn verifyToolchain(ctx: *Context, config: Config, compiler: Compiler) !void {
    try verifyCompiler(ctx, compiler);
    if (!try equals(ctx.a, compiler.toolchain, try toolchainRecipe(ctx, config))) return ctx.fail("component toolchain inputs changed during build");
}

/// The Zig toolchain the compiler links the components with: its executable, its library tree and its native target.
fn toolchainRecipe(ctx: *Context, config: Config) !Value {
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
    return files.object(ctx.a, &.{
        .{ .name = "zig_sha256", .value = try ctx.hashValue(config.zig) },
        .{ .name = "zig_library_sha256", .value = files.string(try ctx.a.dupe(u8, &library_digest)) },
        .{ .name = "target", .value = files.string(target) },
        .{ .name = "build_environment", .value = files.string("private-local-and-tmp-v1") },
        .{ .name = "tool_identity", .value = try toolIdentity(ctx, config) },
    });
}

/// The toolchain identity the compiler computes for `config.zig` in the environment it will build in: the digest every
/// native key of the compiler holds, which moves when a system library the loader could load, the Zig distribution or the
/// CPU does. The bytes of a component depend on it (the runtime object's name takes it), so a receipt made under another
/// identity is another receipt, never one the rebuild is compared with.
fn toolIdentity(ctx: *Context, config: Config) !Value {
    var environment = try inheritedEnvironment(ctx.a, ctx.environ);
    defer environment.deinit();
    const printed = try ctx.checked(&.{ config.compiler, "native", "show", "--digest", "--zig", config.zig }, null, &environment);
    const line = std.mem.trimEnd(u8, printed, "\n");
    if (!validDigest(line)) return ctx.fail("the component compiler printed no toolchain identity (selka native show --digest)");
    return files.string(try ctx.a.dupe(u8, line));
}

/// The compiler named by `--compiler`, with the digest every later use is checked against.
fn compilerOf(ctx: *Context, config: Config) !Compiler {
    if (config.compiler.len == 0) return ctx.fail("--compiler is required: the compiler that compiles the components");
    const digest = files.digest(ctx.io, config.compiler) catch return ctx.fail("cannot read the component compiler");
    return .{ .binary = config.compiler, .sha256 = try ctx.a.dupe(u8, &digest), .toolchain = try toolchainRecipe(ctx, config) };
}

/// The CPU model the components are built for, spelled as the compiler's `--cpu` takes it: the AVX2 floor, never the machine
/// that builds them, so the bundle's components run on any AVX2 machine.
const component_cpu = "x86-64-v3";

/// The machine a component is built for: the operating system, the architecture and `component_cpu`. Not `/proc/cpuinfo`: the
/// bytes of a component no longer depend on the builder's CPU, so neither does its receipt's identity.
fn componentTarget(ctx: *Context) !Value {
    return files.object(ctx.a, &.{
        .{ .name = "os", .value = files.string(@tagName(builtin.os.tag)) },
        .{ .name = "machine", .value = files.string(@tagName(builtin.cpu.arch)) },
        .{ .name = "cpu", .value = files.string(component_cpu) },
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

const Component = struct { source: []const u8, name: []const u8 };
const components = [_]Component{
    .{ .source = "test_index", .name = "test-index" },
    .{ .source = "cache_plan", .name = "cache-plan" },
};

fn component(ctx: *Context, config: Config, compiler: Compiler, descriptor: Component) ![]const u8 {
    const version: i64 = if (std.mem.eql(u8, descriptor.name, "cache-plan")) 2 else 1;
    const sources = try ctx.path(&.{ config.root, "selfhost", "components", descriptor.source });
    var flags = std.json.Array.init(ctx.a);
    try flags.append(files.string("debug"));
    try flags.append(files.string("fresh-private-cache"));
    try flags.append(files.string("private-zig-global-v1"));
    try flags.append(files.string("stable-staging-v1"));
    try flags.append(files.string("zero-rc-v1"));
    try flags.append(files.string("checked-default-v1"));
    try flags.append(files.string("cpu-" ++ component_cpu));
    const identity = try files.object(ctx.a, &.{
        .{ .name = "format", .value = files.integer(6) },
        .{ .name = "component", .value = files.string(descriptor.name) },
        .{ .name = "build_cache_root", .value = files.string(config.cache) },
        .{ .name = "protocol", .value = files.integer(version) },
        .{ .name = "schema", .value = files.integer(version) },
        .{ .name = "target", .value = try componentTarget(ctx) },
        .{ .name = "flags", .value = .{ .array = flags } },
        .{ .name = "compiler", .value = files.string(compiler.sha256) },
        .{ .name = "toolchain", .value = compiler.toolchain },
        .{ .name = "sources", .value = try files.tree(ctx.a, ctx.io, sources) },
        .{ .name = "coordinator", .value = try builderIdentity(ctx) },
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
        // One staging path for every key and every worktree: the compiler embeds
        // the paths of the sources and caches it compiles in the component's
        // bytes, so a key-named or caller-named directory would make otherwise
        // identical builds differ. The builder lock serializes its use.
        const work = try ctx.path(&.{ config.cache, "staging", "component" });
        try files.remove(ctx.io, work);
        try cwd().createDirPath(ctx.io, work);
        defer files.discard(ctx.io, work);
        const copied = try ctx.path(&.{ work, "src" });
        try snapshot(ctx, sources, copied);
        if (!try equals(ctx.a, try files.tree(ctx.a, ctx.io, copied), try get(identity, "sources"))) return ctx.fail("component source changed during snapshot");
        const output = try ctx.path(&.{ work, descriptor.name });
        var environment = try componentEnvironment(ctx, config, work);
        defer environment.deinit();
        const temporary = try ctx.path(&.{ work, "tmp" });
        try cwd().createDirPath(ctx.io, temporary);
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(ctx.a, &.{ compiler.binary, "build", try ctx.path(&.{ copied, "main.selka" }), "-o", output, "--cpu", component_cpu, "--cache-dir", try ctx.path(&.{ work, "cache" }) });
        try verifyCompiler(ctx, compiler);
        const compile_output = try ctx.checked(arguments.items, work, &environment);
        if (compile_output.len != 0) try std.Io.File.stderr().writeStreamingAll(ctx.io, compile_output);
        try verifyToolchain(ctx, config, compiler);
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
            try files.remove(ctx.io, temporary);
            try files.remove(ctx.io, copied);
            try files.remove(ctx.io, stored);
            try cwd().rename(work, cwd(), stored, ctx.io);
        }
    }
    try verifyToolchain(ctx, config, compiler);
    try cwd().createDirPath(ctx.io, config.install);
    const expected = try text(try get(metadata, "sha256"));
    const name = try std.fmt.allocPrint(ctx.a, "{s}-{s}", .{ descriptor.name, expected });
    const installed = try ctx.path(&.{ config.install, name });
    if (try files.exists(ctx.io, installed)) {
        if (!try digestEquals(ctx.io, installed, expected)) return ctx.fail("installed component digest mismatch");
    } else try files.copy(ctx.io, executable, installed, 0o555);
    var manifest = try files.object(ctx.a, &.{
        .{ .name = "format", .value = files.integer(1) },                    .{ .name = "component", .value = files.string(descriptor.name) },
        .{ .name = "protocol", .value = files.integer(version) },            .{ .name = "schema", .value = files.integer(version) },
        .{ .name = "artifact", .value = files.string(name) },                .{ .name = "sha256", .value = files.string(expected) },
        .{ .name = "key", .value = files.string(try ctx.a.dupe(u8, &key)) }, .{ .name = "memory_mode", .value = files.string("zero-rc-v1") },
    });
    try manifest.object.put(ctx.a, "ownership_selection", files.string("checked-default-v1"));
    try files.atomicJson(ctx.a, ctx.io, try ctx.path(&.{ config.install, try std.fmt.allocPrint(ctx.a, "{s}.json", .{descriptor.name}) }), manifest, 0o644);
    return ctx.a.dupe(u8, &key);
}

/// The builder's location-free identity: its compiled source closure and the
/// toolchain, mode, backend and target that built it. It replaces the digest of
/// the builder executable, whose debug information names the worktree.
fn builderIdentity(ctx: *Context) !Value {
    const sources = builder.sourcesDigest();
    return files.object(ctx.a, &.{
        .{ .name = "domain", .value = files.string(builder.domain) },
        .{ .name = "sources_sha256", .value = files.string(try ctx.a.dupe(u8, &sources)) },
        .{ .name = "zig_version", .value = files.string(builder.zig_version) },
        .{ .name = "optimize", .value = files.string(builder.optimize) },
        .{ .name = "backend", .value = files.string(builder.backend) },
        .{ .name = "target", .value = files.string(builder.target) },
    });
}

// Native discovery is deliberately separate from the cached build: directory
// membership is discovered at make time, including added and deleted files.
// Keep this closure aligned with build_test_inputs.component_inputs.
fn componentInputs(ctx: *Context, root: []const u8) !Value {
    const directory = try ctx.path(&.{ root, "selfhost" });
    const dir = try cwd().openDir(ctx.io, directory, .{ .iterate = true });
    defer dir.close(ctx.io);
    var iterator = dir.iterate();
    var entries: std.json.ObjectMap = .empty;
    while (try iterator.next(ctx.io)) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig") and !std.mem.endsWith(u8, entry.name, ".json")) continue;
        const path_name = try ctx.path(&.{ directory, entry.name });
        const stat = try cwd().statFile(ctx.io, path_name, .{});
        if (stat.kind != .file) return ctx.fail("component inputs must be ordinary files");
        try entries.put(ctx.a, try ctx.a.dupe(u8, entry.name), try ctx.hashValue(path_name));
    }
    try entries.put(ctx.a, "components", try files.tree(ctx.a, ctx.io, try ctx.path(&.{ directory, "components" })));
    return .{ .object = entries };
}

fn inputIdentity(ctx: *Context, config: Config, compiler: Compiler) !Value {
    return files.object(ctx.a, &.{
        .{ .name = "format", .value = files.integer(4) },
        .{ .name = "inputs", .value = try componentInputs(ctx, config.root) },
        .{ .name = "compiler", .value = files.string(compiler.sha256) },
        .{ .name = "toolchain", .value = try toolchainRecipe(ctx, config) },
        .{ .name = "coordinator", .value = try builderIdentity(ctx) },
        .{ .name = "target", .value = try componentTarget(ctx) },
        .{ .name = "cache_root", .value = files.string(config.cache) },
    });
}

// Metadata grants authority only within one actual build. It is never written
// into the semantic input stamp or used as a content identity/cache key.
fn observePath(ctx: *Context, entries: *std.json.ObjectMap, path_name: []const u8) !void {
    const stat = try cwd().statFile(ctx.io, path_name, .{ .follow_symlinks = false });
    const value = try std.fmt.allocPrint(ctx.a, "{d}:{s}:{d}:{d}:{d}:{d}", .{
        stat.inode, @tagName(stat.kind), stat.size, stat.mtime.nanoseconds, stat.ctime.nanoseconds, stat.permissions.toMode(),
    });
    try entries.put(ctx.a, path_name, files.string(value));
    if (stat.kind == .sym_link) {
        const target = try cwd().statFile(ctx.io, path_name, .{});
        const target_value = try std.fmt.allocPrint(ctx.a, "{d}:{s}:{d}:{d}:{d}:{d}", .{
            target.inode, @tagName(target.kind), target.size, target.mtime.nanoseconds, target.ctime.nanoseconds, target.permissions.toMode(),
        });
        try entries.put(ctx.a, try std.fmt.allocPrint(ctx.a, "{s}/@target", .{path_name}), files.string(target_value));
    }
}

fn observeTree(ctx: *Context, entries: *std.json.ObjectMap, path_name: []const u8) !void {
    try observePath(ctx, entries, path_name);
    const directory = try cwd().openDir(ctx.io, path_name, .{ .iterate = true });
    defer directory.close(ctx.io);
    var walker = try directory.walk(ctx.a);
    defer walker.deinit();
    while (try walker.next(ctx.io)) |entry| try observePath(ctx, entries, try ctx.path(&.{ path_name, entry.path }));
}

fn inputAuthority(ctx: *Context, config: Config, compiler: Compiler) ![64]u8 {
    var entries: std.json.ObjectMap = .empty;
    const selfhost = try ctx.path(&.{ config.root, "selfhost" });
    try observePath(ctx, &entries, selfhost);
    const directory = try cwd().openDir(ctx.io, selfhost, .{ .iterate = true });
    defer directory.close(ctx.io);
    var iterator = directory.iterate();
    while (try iterator.next(ctx.io)) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        if (std.mem.endsWith(u8, entry.name, ".zig") or std.mem.endsWith(u8, entry.name, ".json"))
            try observePath(ctx, &entries, try ctx.path(&.{ selfhost, entry.name }));
    }
    try observeTree(ctx, &entries, try ctx.path(&.{ selfhost, "components" }));
    try observePath(ctx, &entries, compiler.binary);
    try observePath(ctx, &entries, config.zig);
    const environment = try ctx.checked(&.{ config.zig, "env" }, null, null);
    try observeTree(ctx, &entries, try quotedField(environment, ".lib_dir"));
    const canonical = try files.canonical(ctx.a, .{ .object = entries });
    return files.textDigest(canonical);
}

fn verifyInputs(ctx: *Context, config: Config, compiler: Compiler, expected: ?Value) !void {
    if (expected) |record| {
        if (!try equals(ctx.a, record, try inputIdentity(ctx, config, compiler))) return ctx.fail("component inputs changed after discovery");
    }
}

fn verifiedManifest(ctx: *Context, path_name: []const u8, expected: []const u8) !Value {
    const raw = try cwd().readFileAlloc(ctx.io, path_name, ctx.a, .limited(16 << 20));
    const actual = files.textDigest(raw);
    if (!std.mem.eql(u8, &actual, expected)) return ctx.fail("cached component manifest differs from completion stamp");
    return std.json.parseFromSliceLeaky(Value, ctx.a, raw, .{ .allocate = .alloc_always }) catch return ctx.fail("malformed cached component manifest");
}

// A cached output directory is accepted only after its manifests and binaries
// have been checked. Copying from a generated directory must never turn a
// corrupt cache entry into an installed component.
fn installFrom(ctx: *Context, config: Config, source: []const u8, stamp_path: []const u8) !void {
    const stamp = try ctx.metadata(stamp_path);
    var manifests: [components.len]Value = undefined;
    for (components, 0..) |descriptor, index| {
        const manifest_name = try std.fmt.allocPrint(ctx.a, "{s}.json", .{descriptor.name});
        const manifest_path = try ctx.path(&.{ source, manifest_name });
        const manifest = try verifiedManifest(ctx, manifest_path, try text(try get(stamp, descriptor.name)));
        manifests[index] = manifest;
        const artifact = try text(try get(manifest, "artifact"));
        const expected = try text(try get(manifest, "sha256"));
        const expected_name = try std.fmt.allocPrint(ctx.a, "{s}-{s}", .{ descriptor.name, expected });
        const version: i64 = if (std.mem.eql(u8, descriptor.name, "cache-plan")) 2 else 1;
        if (!validDigest(expected) or !validDigest(try text(try get(manifest, "key"))) or !std.mem.eql(u8, artifact, expected_name) or
            !std.mem.eql(u8, try text(try get(manifest, "component")), descriptor.name) or
            !try equals(ctx.a, try get(manifest, "format"), files.integer(1)) or
            !try equals(ctx.a, try get(manifest, "protocol"), files.integer(version)) or
            !try equals(ctx.a, try get(manifest, "schema"), files.integer(version)))
            return ctx.fail("invalid cached component manifest");
        const input = try ctx.path(&.{ source, artifact });
        if (!try digestEquals(ctx.io, input, expected)) return ctx.fail("cached component digest mismatch");
    }
    // Validate the entire set before publishing any part of it.
    for (components, manifests) |descriptor, manifest| {
        const manifest_name = try std.fmt.allocPrint(ctx.a, "{s}.json", .{descriptor.name});
        const artifact = try text(try get(manifest, "artifact"));
        const expected = try text(try get(manifest, "sha256"));
        const destination = try ctx.path(&.{ config.install, artifact });
        try cwd().createDirPath(ctx.io, config.install);
        if (!try installedValid(ctx, destination, expected))
            try files.copy(ctx.io, try ctx.path(&.{ source, artifact }), destination, 0o555);
        if (!try digestEquals(ctx.io, destination, expected)) return ctx.fail("component changed during installation");
        try files.atomicJson(ctx.a, ctx.io, try ctx.path(&.{ config.install, manifest_name }), manifest, 0o644);
    }
}

fn validDigest(value: []const u8) bool {
    if (value.len != 64) return false;
    for (value) |byte| if (!(byte >= '0' and byte <= '9') and !(byte >= 'a' and byte <= 'f')) return false;
    return true;
}

fn installedValid(ctx: *Context, path_name: []const u8, expected: []const u8) !bool {
    const stat = cwd().statFile(ctx.io, path_name, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return stat.kind == .file and (stat.permissions.toMode() & 0o7777) == 0o555 and try digestEquals(ctx.io, path_name, expected);
}

fn findTool(ctx: *Context, name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, name, '/') != null) return cwd().realPathFileAlloc(ctx.io, name, ctx.a);
    var directories = std.mem.splitScalar(u8, ctx.environ.get("PATH") orelse "", std.fs.path.delimiter);
    while (directories.next()) |directory| {
        const candidate = try ctx.path(&.{ if (directory.len == 0) "." else directory, name });
        if (try files.exists(ctx.io, candidate)) return cwd().realPathFileAlloc(ctx.io, candidate, ctx.a);
    }
    return ctx.fail("required executable missing; use --zig");
}

/// The default store: `SELKA_COMPONENT_CACHE`, else `selka/components` under `XDG_CACHE_HOME`, else under `~/.cache`.
fn defaultCache(ctx: *Context) ![]const u8 {
    if (ctx.environ.get("SELKA_COMPONENT_CACHE")) |directory| if (directory.len != 0) return directory;
    if (ctx.environ.get("XDG_CACHE_HOME")) |directory| if (std.fs.path.isAbsolute(directory)) return ctx.path(&.{ directory, "selka", "components" });
    const home = ctx.environ.get("HOME") orelse return ctx.fail("HOME is unset; supply --cache-dir");
    return ctx.path(&.{ home, ".cache", "selka", "components" });
}

fn run(ctx: *Context, args: []const []const u8) !void {
    const current = try cwd().realPathFileAlloc(ctx.io, ".", ctx.a);
    var root: []const u8 = current;
    var zig: []const u8 = ctx.environ.get("SELKA_ZIG") orelse "zig";
    var compiler: ?[]const u8 = null;
    var cache: ?[]const u8 = null;
    var install: ?[]const u8 = null;
    var uncached = false;
    var inputs_stamp: ?[]const u8 = null;
    var verify_inputs_stamp: ?[]const u8 = null;
    var output_stamp: ?[]const u8 = null;
    var install_from: ?[]const u8 = null;
    var install_stamp: ?[]const u8 = null;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try std.Io.File.stdout().writeStreamingAll(ctx.io, "usage: selka-components [--root DIR] [--zig PATH] --compiler PATH [--cache-dir DIR] [--install-dir DIR] [--uncached] [--inputs-stamp FILE] [--verify-inputs-stamp FILE] [--output-stamp FILE] [--install-from DIR --install-stamp FILE]\n");
            return;
        }
        if (std.mem.eql(u8, arg, "--uncached")) {
            uncached = true;
            continue;
        }
        index += 1;
        if (index >= args.len) return ctx.fail("option requires a value");
        if (std.mem.eql(u8, arg, "--root")) root = args[index] else if (std.mem.eql(u8, arg, "--zig")) zig = args[index] else if (std.mem.eql(u8, arg, "--compiler")) compiler = args[index] else if (std.mem.eql(u8, arg, "--cache-dir")) cache = args[index] else if (std.mem.eql(u8, arg, "--install-dir")) install = args[index] else if (std.mem.eql(u8, arg, "--inputs-stamp")) inputs_stamp = args[index] else if (std.mem.eql(u8, arg, "--verify-inputs-stamp")) verify_inputs_stamp = args[index] else if (std.mem.eql(u8, arg, "--output-stamp")) output_stamp = args[index] else if (std.mem.eql(u8, arg, "--install-from")) install_from = args[index] else if (std.mem.eql(u8, arg, "--install-stamp")) install_stamp = args[index] else return ctx.fail("unknown coordinator option");
    }
    root = try cwd().realPathFileAlloc(ctx.io, root, ctx.a);
    const config: Config = .{
        .root = root,
        .zig = try findTool(ctx, zig),
        .compiler = if (compiler) |path_name| cwd().realPathFileAlloc(ctx.io, path_name, ctx.a) catch return ctx.fail("cannot find the component compiler named by --compiler") else "",
        .cache = try std.fs.path.resolve(ctx.a, &.{ current, cache orelse try defaultCache(ctx) }),
        .install = try std.fs.path.resolve(ctx.a, &.{ current, install orelse try ctx.path(&.{ root, "zig-out", "libexec", "selka", "components" }) }),
        .uncached = uncached,
    };
    if (install_from) |source| {
        if (inputs_stamp != null or output_stamp != null or verify_inputs_stamp != null or uncached) return ctx.fail("install-from cannot be combined with a build mode");
        return installFrom(ctx, config, source, install_stamp orelse return ctx.fail("install-from requires a completion stamp"));
    }
    if (install_stamp != null) return ctx.fail("install-stamp requires install-from");
    try cwd().createDirPath(ctx.io, config.cache);
    const lock = try cwd().createFile(ctx.io, try ctx.path(&.{ config.cache, "build.lock" }), .{ .truncate = false, .permissions = .fromMode(0o600) });
    defer lock.close(ctx.io);
    try lock.lock(ctx.io, .exclusive);
    defer lock.unlock(ctx.io);
    const built_with = try compilerOf(ctx, config);
    if (inputs_stamp) |path_name| {
        if (output_stamp != null or install_from != null or install_stamp != null or verify_inputs_stamp != null or uncached) return ctx.fail("inputs stamp cannot be combined with a build or install mode");
        return files.atomicJson(ctx.a, ctx.io, path_name, try inputIdentity(ctx, config, built_with), 0o600);
    }
    if (output_stamp) |path_name| try files.remove(ctx.io, path_name);
    const expected_inputs = if (verify_inputs_stamp) |path_name| try ctx.metadata(path_name) else null;
    const authority = if (expected_inputs != null) try inputAuthority(ctx, config, built_with) else null;
    try verifyInputs(ctx, config, built_with, expected_inputs);
    var manifests: std.json.ObjectMap = .empty;
    for (components) |descriptor| {
        const output = try component(ctx, config, built_with, descriptor);
        const manifest = try ctx.path(&.{ config.install, try std.fmt.allocPrint(ctx.a, "{s}.json", .{descriptor.name}) });
        try manifests.put(ctx.a, descriptor.name, try ctx.hashValue(manifest));
        try std.Io.File.stdout().writeStreamingAll(ctx.io, output);
        try std.Io.File.stdout().writeStreamingAll(ctx.io, "\n");
    }
    try verifyInputs(ctx, config, built_with, expected_inputs);
    if (authority) |before| {
        const after = try inputAuthority(ctx, config, built_with);
        if (!std.mem.eql(u8, &before, &after)) return ctx.fail("component input metadata changed during build");
    }
    if (output_stamp) |path_name| try files.atomicJson(ctx.a, ctx.io, path_name, .{ .object = manifests }, 0o600);
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
            error.ToolchainEnvironment => "cannot identify the Zig library and native target",
            error.FileNotFound => "required file missing; verify --root, --zig and --compiler",
            else => @errorName(err),
        };
        diagnostic(init.io, message);
        std.process.exit(1);
    };
}
