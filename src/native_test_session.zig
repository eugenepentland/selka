//! Checked test compilation and isolated provider variants.
const std = @import("std");
const bundled = @import("qbe_build_assets");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const snapshot = @import("native_test_snapshot.zig");
const options = @import("native_test_options.zig");
const environment = @import("native_test_environment.zig");
const execute = @import("native_test_execute.zig");
/// Test setup, changed inputs, malformed compiler output and tool failures.
pub const Error = fs.Error || snapshot.Error || execute.Error || std.json.ParseError(std.json.Scanner);
/// One freshly checked project or provider variant.
pub const Project = struct { source: []const u8, manifest: std.json.Value, schema: std.json.Value, directory: []const u8, executor: ?execute.Executor = null };
/// Invocation-owned paths and tool fingerprints.
pub const Session = struct {
    context: fs.Context,
    options: options.Options,
    compiler: []const u8,
    zig: []const u8,
    qbe: []const u8,
    hashes: [3][]const u8,
    environment: environment.Fingerprint,
    directory: []const u8,
    temporary: []const u8,
    source: snapshot.Snapshot,
    /// Pin sources and tools before checking or consulting successful-result receipts.
    pub fn init(context: fs.Context, opts: options.Options) Error!Session {
        const compiler = try std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", context.allocator);
        const zig = try context.executable(opts.zig);
        const qbe = try context.executable(opts.qbe);
        const directory = try context.absolute(opts.cache);
        // Capture before creating cache files beneath a test source directory.
        const source = try snapshot.captureExcluding(context, opts.source, directory);
        try context.mkdir(directory);
        const temporary = try context.temporary("/tmp");
        errdefer context.remove(temporary);
        return .{
            .context = context,
            .options = opts,
            .compiler = compiler,
            .zig = zig,
            .qbe = qbe,
            .hashes = .{ bundled.compiler_identity, try context.stamp(zig), try context.stamp(qbe) },
            .environment = try environment.capture(context),
            .directory = directory,
            .temporary = temporary,
            .source = source,
        };
    }
    /// Fresh semantic checking always precedes result reuse, including warm builds.
    pub fn check(self: Session, source: []const u8) Error!Project {
        const output = try self.context.capture(&.{ self.compiler, "emit-project-qbe", source });
        if (fs.exitCode(output.term) != 0) return error.NativeToolFailed;
        const manifest = (try std.json.parseFromSlice(std.json.Value, self.context.allocator, output.stdout, .{ .allocate = .alloc_always })).value;
        const schema = v.get(manifest, "schema");
        if (schema != .string) return error.InvalidNativeTestManifest;
        const parsed_schema = try std.json.parseFromSlice(std.json.Value, self.context.allocator, schema.string, .{ .allocate = .alloc_always });
        return .{ .source = source, .manifest = manifest, .schema = parsed_schema.value, .directory = try self.context.temporary(self.temporary) };
    }
    /// Build only when at least one case actually needs to execute.
    pub fn executor(self: Session, project: *Project) Error!execute.Executor {
        if (project.executor) |existing| return existing;
        const a = self.context.allocator;
        const library = try std.fs.path.join(a, &.{ project.directory, "tests.so" });
        const objects = try std.fs.path.join(a, &.{ self.directory, "objects", self.environment.hash });
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(self.context.allocator, &.{ self.compiler, "build", project.source, "--project", "--library", "-o", library, "--cache-dir", objects, "--zig", self.zig, "--qbe", self.qbe, "--mode", self.options.mode });
        try @import("native_link.zig").append(self.context, self.options.link_arguments, &arguments, true);
        try self.context.command(arguments.items, null);
        project.executor = try execute.Executor.init(self.context, project.manifest, library, project.directory, self.zig);
        return project.executor.?;
    }
    /// Include tools, runtime (embedded in compiler), case settings and execution policy.
    pub fn key(self: Session, settings: std.json.Value, function: std.json.Value) Error![]const u8 {
        const bytes = try std.json.Stringify.valueAlloc(self.context.allocator, .{
            .version = "native-test-context-v1",
            .environment = self.environment.hash,
            .tools = self.hashes,
            .entry = self.source.entry_path,
            .settings = settings,
            .parameters = v.get(function, "parameters"),
            .result = v.get(function, "result"),
            .reference = v.get(function, "return_reference"),
            .mode = self.options.mode,
            .limits = self.options.limits,
        }, .{});
        return fs.hash(self.context.allocator, bytes);
    }
    /// Never publish successful results from a source or tool set changed mid-run. The
    /// running compiler cannot change underneath itself, so its embedded build-time
    /// identity stands in for rereading a multi-hundred-megabyte executable per run.
    pub fn verify(self: Session) Error!void {
        try snapshot.verify(self.context, self.source);
        if (!std.mem.eql(u8, self.hashes[0], bundled.compiler_identity)) return error.SourceChanged;
        for ([_][]const u8{ self.zig, self.qbe }, self.hashes[1..]) |path, old| {
            if (!std.mem.eql(u8, old, try self.context.stamp(path))) return error.SourceChanged;
        }
    }
};
