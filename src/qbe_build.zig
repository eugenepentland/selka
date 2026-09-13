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
    error{ UnsupportedNativeHost, ZigVersionMismatch, InvalidNativeManifest };
const abi = "mylang-qbe-native-v3";
const Record = struct { name: []const u8, symbol: []const u8, key: []const u8, object: []const u8, reused: bool };
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
    var context = try fs.Context.init(process.arena.allocator(), process.io, process.environ_map);
    defer context.deinit();
    return build(context, parsed);
}
fn build(context: fs.Context, parsed: options.Options) !u8 {
    const a = context.allocator;
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", a);
    const zig = try context.executable(parsed.zig);
    const qbe = try context.executable(parsed.qbe);
    const version = try context.capture(&.{ zig, "version" });
    if (fs.exitCode(version.term) != 0) return 2;
    const zig_version = std.mem.trim(u8, version.stdout, "\r\n ");
    try checkVersion(zig_version);
    const start = std.Io.Timestamp.now(context.io, .awake);
    const generated = try context.capture(&.{ compiler, if (parsed.project) "emit-project-qbe" else "emit-qbe", try context.absolute(parsed.source) });
    const code = fs.exitCode(generated.term);
    if (code != 0) return code;
    const manifest = (try std.json.parseFromSlice(std.json.Value, a, generated.stdout, .{ .allocate = .alloc_always })).value;
    try validate(manifest);
    const frontend = seconds(context, start);
    const native_start = std.Io.Timestamp.now(context.io, .awake);
    const directory = try context.absolute(parsed.cache);
    try context.mkdir(directory);
    const assets = try materialize(context, directory);
    const temporary = try context.temporary(directory);
    defer context.remove(temporary);
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
    const cache: cache_api.Cache = .{ .context = context, .directory = directory, .temporary = temporary, .assets = assets, .environment = environment, .zig = zig, .qbe = qbe, .mode = parsed.mode };
    var state = State{ .context = context, .cache = cache, .manifest = manifest };
    const codegen_start = std.Io.Timestamp.now(context.io, .awake);
    try state.compile();
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
            .metadata_reused = state.metadata_reused,
            .functions = state.records.items,
            .frontend_seconds = frontend,
            .codegen_seconds = codegen,
            .link_seconds = seconds(context, link_start),
            .native_seconds = seconds(context, native_start),
            .target = parsed.target,
            .mode = parsed.mode,
            .zig_version = zig_version,
            .artifact_kind = if (parsed.library) "shared-library" else "executable",
        }, .{});
        const stream = if (parsed.run) std.Io.File.stderr() else std.Io.File.stdout();
        try stream.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{report}));
    }
    if (parsed.run) return execute(context, output, parsed.arguments);
    return 0;
}
fn execute(context: fs.Context, output: []const u8, arguments: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(context.allocator, output);
    try argv.appendSlice(context.allocator, arguments);
    var child = try std.process.spawn(context.io, .{ .argv = argv.items });
    const term = try child.wait(context.io);
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
}
/// Publish the bundled runtime tree once per content hash and reuse it afterwards.
/// Concurrent builds stage into private directories and rename, so a shared cache
/// never observes a partial tree; a lost race simply reuses the winner's tree.
fn materialize(context: fs.Context, cache: []const u8) ![]const u8 {
    const a = context.allocator;
    const parent = try std.fs.path.join(a, &.{ cache, "runtime" });
    const directory = try std.fs.path.join(a, &.{ parent, bundled.content_hash });
    if (context.exists(directory)) return directory;
    try context.mkdir(parent);
    const staging = try context.temporary(parent);
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
    fn add(self: *State, object: cache_api.Object) !void {
        try self.objects.append(self.context.allocator, object.path);
    }
    fn compile(self: *State) !void {
        const a = self.context.allocator;
        const units = try a.dupe(std.json.Value, v.array(v.get(self.manifest, "functions")));
        std.mem.sort(std.json.Value, units, {}, less);
        for (units) |unit| {
            const object = try self.cache.object("function", v.text(v.get(unit, "il")), .qbe);
            try self.add(object);
            self.reused += @intFromBool(object.reused);
            try self.records.append(a, .{ .name = v.text(v.get(unit, "name")), .symbol = v.text(v.get(unit, "symbol")), .key = object.key, .object = object.path, .reused = object.reused });
        }
        self.runtime = try self.cache.object("runtime", "qbe_runtime.c", .c_file);
        try self.add(self.runtime);
        for ([_][]const u8{
            "native_heap.c",    "native_collections.c", "native_text.c",  "native_dictionary.c", "qbe_stack.c",
            "qbe_providers.c",  "qbe_resources.c",      "native_equal.c", "native_bytes.c",      "qbe_bytes.c",
            "native_regions.c", "qbe_arena.c",
        }) |source| try self.add(try self.cache.object("support", source, .c_file));
        const metadata = try self.cache.object("metadata", try outputs.metadata(a, self.manifest), .c_text);
        self.metadata_reused = metadata.reused;
        try self.add(metadata);
        if (v.boolean(v.get(self.manifest, "text_format"))) try self.add(try self.cache.object("format", "native_format.zig", .zig_file));
    }
    fn link(self: *State, parsed: options.Options, output: []const u8) !bool {
        const a = self.context.allocator;
        const temporary = try self.context.temporary(std.fs.path.dirname(output).?);
        defer self.context.remove(temporary);
        const candidate = try std.fs.path.join(a, &.{ temporary, "program" });
        const wrapper = try std.fs.path.join(a, &.{ self.cache.temporary, "entry.c" });
        const text = if (parsed.library) try @import("qbe_build_embed.zig").libraryWrapper(a, self.manifest) else try outputs.entry(a, self.manifest, parsed.provider != null);
        try self.context.write(wrapper, text);
        if (parsed.provider) |provider_source| try self.provider(provider_source);
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(a, try self.cache.flags());
        if (parsed.library) try args.append(a, "-shared");
        try args.append(a, wrapper);
        try args.appendSlice(a, self.objects.items);
        try @import("native_link.zig").append(self.context, parsed.link_arguments, &args, false);
        try args.appendSlice(a, &.{ "-lm", "-o", candidate });
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
    try std.testing.expect(!bundles("vm.zig") and !bundles("qbe_build.zig") and !bundles("json_document.zig"));
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
    try std.testing.expect(!context.exists(try std.fs.path.join(context.allocator, &.{ first, "vm.zig" })));
    const marker = try std.fs.path.join(context.allocator, &.{ first, "reuse-marker" });
    try context.write(marker, "kept");
    try std.testing.expectEqualStrings(first, try materialize(context, cache));
    try std.testing.expectEqualStrings("kept", try context.read(marker));
}
