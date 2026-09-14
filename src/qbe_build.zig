//! Native builds invoke the compiler, QBE and Zig directly; no Python is needed.
const std = @import("std");
const builtin = @import("builtin");
const bundled = @import("qbe_build_assets");
const fs = @import("qbe_build_io.zig");
const options = @import("qbe_build_options.zig");
const cache_api = @import("qbe_build_cache.zig");
const outputs = @import("qbe_build_outputs.zig");
const v = @import("qbe_build_value.zig");
/// Build errors include frontend transport, native tools and manifest validation.
pub const Error = fs.Error || std.json.ParseError(std.json.Scanner) || outputs.Error ||
    @import("qbe_build_embed.zig").Error || cache_api.Error ||
    @import("memory_budget").Error ||
    error{ UnsupportedNativeHost, ZigVersionMismatch, InvalidNativeManifest };
const abi = "mylang-qbe-native-v3";
const Record = struct { name: []const u8, symbol: []const u8, key: []const u8, object: []const u8, reused: bool };
/// Fixed runtime translation units archived together once per build environment.
const runtime_units = [_][]const u8{
    "qbe_runtime.c",   "native_heap.c",    "native_collections.c", "native_text.c",         "native_dictionary.c",
    "qbe_stack.c",     "qbe_providers.c",  "qbe_resources.c",      "native_equal.c",        "native_bytes.c",
    "qbe_bytes.c",     "native_regions.c", "qbe_arena.c",          "native_print.c",        "qbe_io.c",
    "native_scoped.c", "qbe_grants.c",     "qbe_files.c",          "native_text_methods.c",
};
/// Execute a native build using process-owned allocation and I/O policy.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(process.io, options.usage);
        return 0;
    }
    const parsed = options.parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, options.usage);
        return 2;
    };
    try checkHost(builtin.os.tag, builtin.cpu.arch);
    // Build scratch is freed here, not at process exit: a long-lived host that
    // rebuilds its guest on every reload must reclaim each build, so the context
    // owns a reclaiming arena over `gpa` rather than the process's own arena.
    var context = try fs.Context.init(process.gpa, process.io, process.environ_map);
    defer context.deinit();
    return build(context, parsed);
}
/// A resolved toolchain and object cache, reusable across many native builds.
pub const Prepared = struct { cache: cache_api.Cache, zig_version: []const u8 };
/// Resolve the native tools, publish the bundled runtime tree, and open the object cache.
/// The returned cache owns a private staging directory; release it with `context.remove`.
pub fn prepare(context: fs.Context, parsed: options.Options) Error!Prepared {
    const a = context.allocator;
    const zig = try context.executable(parsed.zig);
    const qbe = try context.executable(parsed.qbe);
    const version = try context.capture(&.{ zig, "version" });
    if (fs.exitCode(version.term) != 0) return error.NativeToolFailed;
    const zig_version = std.mem.trim(u8, version.stdout, "\r\n ");
    try checkVersion(zig_version);
    const directory = try context.absolute(parsed.cache);
    try context.mkdir(directory);
    const assets = try materialize(context, try runtimeRoot(context, parsed, directory));
    const temporary = try context.temporary(directory);
    const environment = try std.json.Stringify.valueAlloc(a, .{
        .version = "zig-qbe-build-v2",
        .abi = abi,
        .compiler = bundled.compiler_identity,
        .runtime = bundled.content_hash,
        .zig = try context.stamp(zig),
        .qbe = try context.stamp(qbe),
        .zig_version = zig_version,
        .mode = parsed.mode,
        .target = parsed.target,
    }, .{});
    return .{
        .cache = .{ .context = context, .directory = directory, .temporary = temporary, .assets = assets, .environment = environment, .zig = zig, .qbe = qbe, .mode = parsed.mode },
        .zig_version = zig_version,
    };
}
/// Validate one emitted manifest and link it into `output`, reporting whether the file changed.
pub fn assemble(cache: cache_api.Cache, parsed: options.Options, manifest: std.json.Value, output: []const u8) Error!bool {
    try validate(manifest);
    var state = State{ .context = cache.context, .cache = cache, .manifest = manifest };
    try state.compile(parsed);
    return state.link(parsed, output);
}
/// The frontend that emits a guest's QBE units. A host application is its own
/// frontend, so `/proc/self/exe emit-project-qbe` emits them; `MYLANG_HOST_COMPILER`
/// overrides that with an explicit compiler, which a host running from a binary
/// that is not itself a compiler — a Zig test binary — must supply.
fn frontendCompiler(context: fs.Context) fs.Error![]const u8 {
    if (context.environ.get("MYLANG_HOST_COMPILER")) |path| return context.allocator.dupe(u8, path);
    return std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", context.allocator);
}
fn build(context: fs.Context, parsed: options.Options) !u8 {
    const a = context.allocator;
    const compiler = try frontendCompiler(context);
    const prepared = prepare(context, parsed) catch |err| switch (err) {
        error.NativeToolFailed => return 2,
        else => return err,
    };
    const cache = prepared.cache;
    const temporary = cache.temporary;
    defer context.remove(temporary);
    const start = std.Io.Timestamp.now(context.io, .awake);
    const generated = try context.capture(&.{ compiler, if (parsed.project) "emit-project-qbe" else "emit-qbe", try context.absolute(parsed.source) });
    const code = fs.exitCode(generated.term);
    if (code != 0) return code;
    const manifest = (try std.json.parseFromSlice(std.json.Value, a, generated.stdout, .{ .allocate = .alloc_always })).value;
    try validate(manifest);
    const frontend = seconds(context, start);
    const native_start = std.Io.Timestamp.now(context.io, .awake);
    var state = State{ .context = context, .cache = cache, .manifest = manifest };
    const codegen_start = std.Io.Timestamp.now(context.io, .awake);
    try state.compile(parsed);
    const codegen = seconds(context, codegen_start);
    const link_start = std.Io.Timestamp.now(context.io, .awake);
    const output = if (parsed.run) try std.fs.path.join(a, &.{ temporary, "program" }) else try context.absolute(parsed.output);
    const changed = try state.link(parsed, output);
    if (parsed.report) {
        const report = try std.json.Stringify.valueAlloc(a, .{
            .version = "qbe-build-v1",
            .output = output,
            .output_changed = changed,
            .compiled_functions = state.records.items.len - state.reused,
            .reused_functions = state.reused,
            .runtime_reused = state.runtime.reused,
            .runtime_installed = state.runtime_installed,
            .metadata_reused = state.metadata_reused,
            .functions = state.records.items,
            .frontend_seconds = frontend,
            .codegen_seconds = codegen,
            .link_seconds = seconds(context, link_start),
            .native_seconds = seconds(context, native_start),
            .target = parsed.target,
            .mode = parsed.mode,
            .zig_version = prepared.zig_version,
            .artifact_kind = if (parsed.library) "shared-library" else "executable",
        }, .{});
        const stream = if (parsed.run) std.Io.File.stderr() else std.Io.File.stdout();
        try stream.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{report}));
    }
    if (parsed.run) return spawn(context, output, parsed);
    return 0;
}
/// The argument vector for one built program and the options it was given.
pub fn command(context: fs.Context, output: []const u8, arguments: []const []const u8) Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(context.allocator, output);
    try argv.appendSlice(context.allocator, arguments);
    return argv.items;
}
/// Translate a guest program's termination into the status its command reports.
pub fn status(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
}
/// The byte ceiling one guest process runs under: `--max-memory` first, then
/// `MYLANG_MEMORY_LIMIT`, then the single-guest default.
pub fn ceiling(context: fs.Context, parsed: options.Options) Error!*const std.process.Environ.Map {
    const budget = @import("memory_budget");
    return context.bounded(try budget.resolve(parsed.max_memory, context.environ, budget.variable, budget.run_default));
}
/// Run a built program with the arguments it was given, under its byte ceiling.
pub fn spawn(context: fs.Context, output: []const u8, parsed: options.Options) Error!u8 {
    var child = try std.process.spawn(context.io, .{
        .argv = try command(context, output, parsed.arguments),
        .environ_map = try ceiling(context, parsed),
    });
    return status(try child.wait(context.io));
}
/// The directory that holds the materialized runtime source trees. An explicit
/// `--cache-dir` keeps it hermetically under that directory; a default build shares
/// a user-level location (`$XDG_CACHE_HOME/mylang/runtime`, else `$HOME/.cache/...`)
/// so a fresh project reuses the tree another project already derived, and falls
/// back to the per-project cache when neither variable is set.
fn runtimeRoot(context: fs.Context, parsed: options.Options, directory: []const u8) fs.Error![]const u8 {
    const local = try std.fs.path.join(context.allocator, &.{ directory, "runtime" });
    if (!std.mem.eql(u8, parsed.cache, options.default_cache)) return local;
    return sharedRuntimeRoot(context) orelse local;
}
/// The user-level shared runtime location, or null when no home directory names it.
fn sharedRuntimeRoot(context: fs.Context) ?[]const u8 {
    const a = context.allocator;
    if (context.environ.get("XDG_CACHE_HOME")) |base| {
        if (base.len != 0 and std.fs.path.isAbsolute(base)) return std.fs.path.join(a, &.{ base, "mylang", "runtime" }) catch null;
    }
    if (context.environ.get("HOME")) |home| {
        if (home.len != 0 and std.fs.path.isAbsolute(home)) return std.fs.path.join(a, &.{ home, ".cache", "mylang", "runtime" }) catch null;
    }
    return null;
}
/// Publish the bundled runtime tree once per content hash and reuse it afterwards.
/// Concurrent builds stage into private directories and rename, so a shared cache
/// never observes a partial tree; a lost race simply reuses the winner's tree.
fn materialize(context: fs.Context, root: []const u8) ![]const u8 {
    const a = context.allocator;
    const directory = try std.fs.path.join(a, &.{ root, bundled.content_hash });
    if (context.exists(directory)) return directory;
    try context.mkdir(root);
    const staging = try context.temporary(root);
    for (bundled.files) |asset| {
        const path = try std.fs.path.join(a, &.{ staging, asset.path });
        try context.mkdir(std.fs.path.dirname(path).?);
        try context.write(path, asset.bytes);
    }
    context.rename(staging, directory) catch |err| {
        context.remove(staging);
        if (!context.exists(directory)) return err;
    };
    return directory;
}
/// The portable identity of a prebuilt runtime artifact: the runtime source content
/// hash, the pinned Zig version, the optimize mode and the target. It excludes the
/// tool file stamps the object cache keys on, so an archive installed at build time
/// still matches a later build that resolved its tools from a different path.
fn runtimeInstalledHash(a: std.mem.Allocator, kind: []const u8, mode: []const u8) fs.Error![]const u8 {
    const encoded = try std.json.Stringify.valueAlloc(a, .{ "mylang-runtime-installed-v1", kind, bundled.content_hash, bundled.zig_version, mode, "amd64_sysv" }, .{});
    return fs.hash(a, encoded);
}
/// Resolve a prebuilt runtime artifact installed under `<compiler>/../lib/mylang-runtime`.
/// Returns it only when the file exists and its stored fingerprint still matches, so a
/// removed, cross-target or corrupted install falls back to compiling from source.
fn installedRuntime(context: fs.Context, mode: []const u8, kind: []const u8, extension: []const u8) fs.Error!?cache_api.Object {
    const a = context.allocator;
    if (context.self_directory.len == 0) return null;
    const parent = std.fs.path.dirname(context.self_directory) orelse return null;
    const hash = try runtimeInstalledHash(a, kind, mode);
    const path = try std.fmt.allocPrint(a, "{s}/lib/mylang-runtime/{s}{s}", .{ parent, hash, extension });
    if (!validInstalled(context, path)) return null;
    return .{ .key = hash, .path = path, .reused = true };
}
/// A prebuilt artifact is trusted only when a fingerprint over its length and contents
/// matches the `.digest` published beside it, mirroring the object cache's own check.
fn validInstalled(context: fs.Context, path: []const u8) bool {
    const bytes = context.read(path) catch return false;
    if (bytes.len == 0) return false;
    const checksum = std.fmt.allocPrint(context.allocator, "{s}.digest", .{path}) catch return false;
    const stored = context.read(checksum) catch return false;
    const actual = fs.digest(context.allocator, bytes) catch return false;
    return std.mem.eql(u8, stored, actual);
}
/// Build the runtime archive and text-formatter object for each optimize mode and
/// publish them, hashed by their portable identity, into `--out` so `zig build` can
/// install them beside the compiler. `--work` names a scratch cache the step discards.
/// A later `mylang build` links a matching install directly instead of compiling it.
pub fn emitRuntime(process: std.process.Init, args: []const []const u8) Error!u8 {
    var context = try fs.Context.init(process.gpa, process.io, process.environ_map);
    defer context.deinit();
    const a = context.allocator;
    var zig_path: []const u8 = "zig";
    var qbe_path: []const u8 = "qbe";
    var out: []const u8 = "";
    var work: []const u8 = "";
    var index: usize = 0;
    while (index + 1 < args.len) : (index += 2) {
        const flag = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, flag, "--zig")) {
            zig_path = value;
        } else if (std.mem.eql(u8, flag, "--qbe")) {
            qbe_path = value;
        } else if (std.mem.eql(u8, flag, "--out")) {
            out = value;
        } else if (std.mem.eql(u8, flag, "--work")) {
            work = value;
        } else return 2;
    }
    if (out.len == 0 or work.len == 0) return 2;
    out = try context.absolute(out);
    try checkHost(builtin.os.tag, builtin.cpu.arch);
    for ([_][]const u8{ "Debug", "ReleaseFast" }) |mode| {
        const parsed: options.Options = .{ .source = "runtime", .output = "runtime", .zig = zig_path, .qbe = qbe_path, .cache = try std.fs.path.join(a, &.{ work, mode }), .mode = mode };
        const prepared = prepare(context, parsed) catch |err| switch (err) {
            error.NativeToolFailed => return 2,
            else => return err,
        };
        defer context.remove(prepared.cache.temporary);
        const archive = try prepared.cache.library("runtime", &runtime_units);
        try publishInstalled(context, archive.path, out, try runtimeInstalledHash(a, "archive", mode), ".a");
        const format = try prepared.cache.object("format", "native_format.zig", .zig_file);
        try publishInstalled(context, format.path, out, try runtimeInstalledHash(a, "format", mode), ".o");
    }
    return 0;
}
/// Copy one built artifact into the install-staging directory under its portable hash
/// and publish a fingerprint beside it, so a later build can trust the installed file.
fn publishInstalled(context: fs.Context, source: []const u8, out: []const u8, hash: []const u8, extension: []const u8) Error!void {
    const a = context.allocator;
    const bytes = try context.read(source);
    const dest = try std.fmt.allocPrint(a, "{s}/{s}{s}", .{ out, hash, extension });
    try context.write(dest, bytes);
    try context.atomic(try std.fmt.allocPrint(a, "{s}.digest", .{dest}), try fs.digest(a, bytes));
}
fn seconds(context: fs.Context, start: std.Io.Timestamp) f64 {
    return @as(f64, @floatFromInt(start.durationTo(std.Io.Timestamp.now(context.io, .awake)).nanoseconds)) / 1e9;
}
fn validate(manifest: std.json.Value) !void {
    if (!std.mem.eql(u8, v.text(v.get(manifest, "version")), "qbe-units-v1")) return error.InvalidNativeManifest;
    if (!std.mem.eql(u8, v.text(v.get(manifest, "abi")), abi)) return error.InvalidNativeManifest;
    const units = v.array(v.get(manifest, "functions"));
    var entry_found = false;
    for (units, 0..) |unit, index| {
        const symbol = v.text(v.get(unit, "symbol"));
        if (symbol.len == 0 or v.get(unit, "il") != .string) return error.InvalidNativeManifest;
        if (!std.ascii.isAlphabetic(symbol[0]) and symbol[0] != '_') return error.InvalidNativeManifest;
        for (symbol) |character| if (!std.ascii.isAlphanumeric(character) and character != '_') return error.InvalidNativeManifest;
        for (units[0..index]) |other| if (std.mem.eql(u8, symbol, v.text(v.get(other, "symbol")))) return error.InvalidNativeManifest;
        if (std.mem.eql(u8, symbol, v.text(v.get(manifest, "entry")))) entry_found = true;
    }
    if (!entry_found) return error.InvalidNativeManifest;
}
const State = struct {
    context: fs.Context,
    cache: cache_api.Cache,
    manifest: std.json.Value,
    objects: std.ArrayList([]const u8) = .empty,
    records: std.ArrayList(Record) = .empty,
    reused: usize = 0,
    runtime: cache_api.Object = undefined,
    metadata_reused: bool = false,
    runtime_installed: bool = false,
    fn add(self: *State, object: cache_api.Object) !void {
        try self.objects.append(self.context.allocator, object.path);
    }
    fn compile(self: *State, parsed: options.Options) !void {
        const a = self.context.allocator;
        const units = try a.dupe(std.json.Value, v.array(v.get(self.manifest, "functions")));
        std.mem.sort(std.json.Value, units, {}, less);
        for (units) |unit| {
            const object = try self.cache.object("function", v.text(v.get(unit, "il")), .qbe);
            try self.add(object);
            self.reused += @intFromBool(object.reused);
            try self.records.append(a, .{ .name = v.text(v.get(unit, "name")), .symbol = v.text(v.get(unit, "symbol")), .key = object.key, .object = object.path, .reused = object.reused });
        }
        const metadata = try self.cache.object("metadata", try outputs.metadata(a, self.manifest), .c_text);
        self.metadata_reused = metadata.reused;
        try self.add(metadata);
        const wrapper = if (parsed.library) try @import("qbe_build_embed.zig").libraryWrapper(a, self.manifest) else try outputs.entry(a, self.manifest, parsed.provider != null);
        try self.add(try self.cache.object("entry", wrapper, .c_text));
        if (v.boolean(v.get(self.manifest, "text_format"))) try self.add(try self.resolveFormat());
        // Linked last, so every object above can still pull the members it needs.
        self.runtime = try self.resolveRuntime();
    }
    /// Link the prebuilt runtime archive installed beside the compiler when its hash
    /// matches this build's runtime, mode and target; otherwise compile the archive
    /// from source. A matching install skips the whole runtime compile on a cold build.
    fn resolveRuntime(self: *State) !cache_api.Object {
        if (try installedRuntime(self.context, self.cache.mode, "archive", ".a")) |found| {
            self.runtime_installed = true;
            return found;
        }
        return self.cache.library("runtime", &runtime_units);
    }
    /// Use the prebuilt text-formatter object installed beside the compiler when it
    /// matches, else compile `native_format.zig` from the bundled runtime source.
    fn resolveFormat(self: *State) !cache_api.Object {
        if (try installedRuntime(self.context, self.cache.mode, "format", ".o")) |found| return found;
        return self.cache.object("format", "native_format.zig", .zig_file);
    }
    fn link(self: *State, parsed: options.Options, output: []const u8) !bool {
        const a = self.context.allocator;
        const temporary = try self.context.temporary(std.fs.path.dirname(output).?);
        defer self.context.remove(temporary);
        const candidate = try std.fs.path.join(a, &.{ temporary, "program" });
        if (parsed.provider) |provider_source| try self.provider(provider_source);
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(a, try self.cache.flags());
        if (parsed.library) try args.appendSlice(a, &library_link_arguments);
        try args.appendSlice(a, self.objects.items);
        try @import("native_link.zig").append(self.context, parsed.link_arguments, &args, false);
        // Unreferenced runtime sections leave with the archive members nothing pulled.
        try args.appendSlice(a, &.{ self.runtime.path, "-lm", "-Wl,--gc-sections", "-o", candidate });
        try self.context.command(args.items, null);
        if (parsed.run) return self.context.publish(candidate, output);
        const report = try std.json.Stringify.valueAlloc(a, .{ .version = "qbe-manifest-v1", .abi = abi, .entry = v.text(v.get(self.manifest, "entry")), .functions = self.records.items, .runtime_object = self.runtime.path }, .{});
        const sidecar = try std.fmt.allocPrint(a, "{s}.qbe-manifest.json", .{output});
        const staged = try std.fs.path.join(a, &.{ temporary, "manifest.json" });
        try self.context.write(staged, report);
        const changed = try self.context.publish(candidate, output);
        // The sidecar is descriptive, not an atomic transaction with the executable.
        try self.context.rename(staged, sidecar);
        return changed;
    }
    fn provider(self: *State, source: []const u8) !void {
        const a = self.context.allocator;
        var environment = try self.context.environ.clone(a);
        const temporary = self.cache.temporary;
        try environment.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(a, &.{ temporary, "provider-cache" }));
        try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ temporary, "provider-local-cache" }));
        const object = try std.fs.path.join(a, &.{ temporary, "provider.o" });
        try self.cache.compileC(try self.context.absolute(source), object, &environment);
        try self.objects.append(a, object);
    }
};
/// Shared-library link controls: bind the library's own descriptor references
/// internally so a guest object's non-PIC relocations resolve without symbol
/// interposition.
const library_link_arguments = [_][]const u8{ "-shared", "-Wl,-Bsymbolic" };
fn less(_: void, left: std.json.Value, right: std.json.Value) bool {
    return std.mem.lessThan(u8, v.text(v.get(left, "symbol")), v.text(v.get(right, "symbol")));
}

fn checkHost(os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) error{UnsupportedNativeHost}!void {
    if (os != .linux or arch != .x86_64) return error.UnsupportedNativeHost;
}
fn checkVersion(version: []const u8) error{ZigVersionMismatch}!void {
    if (!std.mem.eql(u8, version, bundled.zig_version)) return error.ZigVersionMismatch;
}
// spec: QBE-2
test "native build rejects incompatible tools targets and malformed manifests" {
    try std.testing.expectError(error.UnsupportedNativeHost, checkHost(.linux, .aarch64));
    try std.testing.expectError(error.ZigVersionMismatch, checkVersion("unrelated-version"));
    try std.testing.expectError(error.InvalidNativeManifest, validate(.null));
    const value = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"version":"qbe-units-v1","abi":"mylang-qbe-native-v3","entry":"1bad","functions":[{"symbol":"1bad","il":""}]}
    , .{});
    defer value.deinit();
    try std.testing.expectError(error.InvalidNativeManifest, validate(value.value));
}
// spec: QBE-HOST-COMPILER-1
test "the frontend honours an explicit host compiler over the running executable" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const own = try frontendCompiler(context);
    try std.testing.expect(own.len != 0);
    try environment.put("MYLANG_HOST_COMPILER", "/opt/mylang/bin/mylang");
    try std.testing.expectEqualStrings("/opt/mylang/bin/mylang", try frontendCompiler(context));
}
fn bundles(name: []const u8) bool {
    for (bundled.files) |asset| if (std.mem.eql(u8, asset.path, name)) return true;
    return false;
}
test "bundled build inputs carry only the native runtime, not compiler tests or guest fixtures" {
    try std.testing.expectEqual(@as(usize, 64), bundled.content_hash.len);
    try std.testing.expectEqual(@as(usize, 64), bundled.compiler_identity.len);
    for (bundled.files) |asset| {
        try std.testing.expect(!std.mem.endsWith(u8, asset.path, "_test.zig"));
        try std.testing.expect(!std.mem.endsWith(u8, asset.path, ".my") or std.mem.startsWith(u8, asset.path, "stdlib/"));
    }
    try std.testing.expect(bundles("qbe_runtime.c") and bundles("qbe_runtime.h") and bundles("native_heap.c"));
    try std.testing.expect(bundles("native_equal.c") and bundles("native_format.zig"));
    try std.testing.expect(!bundles("sema.zig") and !bundles("qbe_build.zig") and !bundles("json_document.zig"));
}
// spec: QBE-3
test "the runtime tree is published once per content hash and reused by later builds" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const cache = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const first = try materialize(context, cache);
    try std.testing.expect(std.mem.endsWith(u8, first, bundled.content_hash));
    try std.testing.expect(context.exists(try std.fs.path.join(context.allocator, &.{ first, "qbe_runtime.c" })));
    try std.testing.expect(!context.exists(try std.fs.path.join(context.allocator, &.{ first, "sema.zig" })));
    const marker = try std.fs.path.join(context.allocator, &.{ first, "reuse-marker" });
    try context.write(marker, "kept");
    try std.testing.expectEqualStrings(first, try materialize(context, cache));
    try std.testing.expectEqualStrings("kept", try context.read(marker));
}
// spec-case: QBE-3
test "a default build shares the runtime root while an explicit cache-dir keeps it local" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("XDG_CACHE_HOME", "/xdg");
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const shared = try runtimeRoot(context, .{ .cache = options.default_cache }, "/project/.mylang-cache/qbe");
    try std.testing.expectEqualStrings("/xdg/mylang/runtime", shared);
    const local = try runtimeRoot(context, .{ .cache = "/tmp/hermetic" }, "/tmp/hermetic");
    try std.testing.expectEqualStrings("/tmp/hermetic/runtime", local);
    try std.testing.expectEqualStrings("/xdg/mylang/runtime", sharedRuntimeRoot(context).?);
}
// spec: QBE-RUNTIME-INSTALLED-1
test "prebuilt runtime hashes separate kind and mode and stay stable, and misses fall back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const archive_debug = try runtimeInstalledHash(a, "archive", "Debug");
    const archive_release = try runtimeInstalledHash(a, "archive", "ReleaseFast");
    const format_debug = try runtimeInstalledHash(a, "format", "Debug");
    try std.testing.expectEqual(@as(usize, 64), archive_debug.len);
    try std.testing.expect(!std.mem.eql(u8, archive_debug, archive_release));
    try std.testing.expect(!std.mem.eql(u8, archive_debug, format_debug));
    try std.testing.expectEqualStrings(archive_debug, try runtimeInstalledHash(a, "archive", "Debug"));
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    context.self_directory = "";
    try std.testing.expectEqual(@as(?cache_api.Object, null), try installedRuntime(context, "Debug", "archive", ".a"));
    try std.testing.expect(!validInstalled(context, "/no/such/installed/runtime.a"));
}
// spec-case: QBE-2
test "shared library links bind their own data descriptor symbols" {
    try std.testing.expectEqual(@as(usize, 2), library_link_arguments.len);
    try std.testing.expectEqualStrings("-shared", library_link_arguments[0]);
    try std.testing.expectEqualStrings("-Wl,-Bsymbolic", library_link_arguments[1]);
}
