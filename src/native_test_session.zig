//! Checked test compilation and isolated provider variants.
const std = @import("std");
const bundled = @import("qbe_build_assets");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const snapshot = @import("native_test_snapshot.zig");
const options = @import("native_test_options.zig");
const environment = @import("native_test_environment.zig");
const execute = @import("native_test_execute.zig");
const invalidation = @import("invalidation.zig");
/// Test setup, changed inputs, malformed compiler output and tool failures.
pub const Error = fs.Error || snapshot.Error || execute.Error || std.json.ParseError(std.json.Scanner) ||
    error{ ProjectConfigurationFailed, ProjectPolicyRejected, SourceRejected, InvalidNativeTestSession, CompilerRecursion };
/// Ceiling on how many ancestors of this process may run the same executable.
/// A compiler child that is really another copy of this program is the shape a
/// runaway recursion takes, so a session refuses past this many instead of
/// spawning forever. Legitimate nesting is shallow and known: `mylang test
/// <dir>` spawns `mylang test <file>`, which spawns `mylang native-test-graph`
/// and `mylang build`, so three same-executable frames are expected.
pub const ancestry_limit = 5;
/// How many parent links the ancestry walk follows before giving up. A cycle or
/// an unreadable `/proc` ends the walk earlier; the bound only stops a walk
/// that would otherwise never terminate.
const ancestry_hops = 32;
/// One freshly checked project or provider variant.
pub const Project = struct {
    source: []const u8,
    manifest: std.json.Value,
    schema: std.json.Value,
    directory: []const u8,
    executor: ?execute.Executor = null,
    /// Selection file the current executor was built for, when one exists.
    select_file: ?[]const u8 = null,
    /// Retained checked-compilation session when this graph was checked in this
    /// invocation; selective lowering consumes it instead of checking again.
    compile: ?*Compile = null,
};
/// The answer to one checked-facts request: the compiler's checked graph, or
/// the located diagnostics it refused the project with.
pub const Facts = union(enum) {
    /// The `native-test-graph-v3` payload the checked project published.
    manifest: []const u8,
    /// The compiler's own located diagnostics for a refused project.
    rejected: []const u8,
};
/// Environment variable naming a file to append one line per compiler child.
/// Gated so ordinary runs pay nothing; used by native-test acceptance traces.
pub const trace_variable = "MYLANG_TEST_TRACE";
/// Invocation-owned paths and tool fingerprints.
pub const Session = struct {
    context: fs.Context,
    options: options.Options,
    compiler: []const u8,
    /// Resolved native tool paths, grouped to keep the session surface bounded.
    tools: struct { zig: []const u8, qbe: []const u8 },
    hashes: [3][]const u8,
    environment: environment.Fingerprint,
    directory: []const u8,
    temporary: []const u8,
    source: snapshot.Snapshot,
    /// Optional shared accumulator for child `work-report-v1` receipts. The
    /// pointer outlives every Session copy, so `mylang test --report` reports
    /// the real parser/check/lower/emission work its children performed.
    work: ?*invalidation.Work = null,
    /// Pin sources and tools before checking or consulting successful-result receipts.
    pub fn init(context: fs.Context, opts: options.Options) Error!Session {
        var session = try initFrontend(context, opts);
        errdefer context.remove(session.temporary);
        const zig = try context.executable(opts.toolchain.zig);
        // A test run that names no `--qbe` leaves the backend to the child build's
        // mode default; it still resolves the QBE tool for identity and for the
        // Debug arm that default selects.
        const qbe = try context.executable(if (opts.toolchain.qbe.len != 0) opts.toolchain.qbe else "qbe");
        session.tools = .{ .zig = zig, .qbe = qbe };
        session.hashes[1] = try context.stamp(zig);
        session.hashes[2] = try context.stamp(qbe);
        return session;
    }
    /// Resolve the frontend paths, snapshot and temporary directory without
    /// resolving zig or qbe. A caller that only needs checked facts — as
    /// `mylang invoke --describe` does — must not require the native toolchain.
    pub fn initFrontend(context: fs.Context, opts: options.Options) Error!Session {
        const compiler = try resolveCompiler(context, opts.toolchain.compiler);
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
            .tools = .{ .zig = "", .qbe = "" },
            .hashes = .{ bundled.compiler_identity, "", "" },
            .environment = try environment.capture(context),
            .directory = directory,
            .temporary = temporary,
            .source = source,
        };
    }
    /// Append the cache-policy flags shared by every compiler child.
    fn appendPolicyFlags(self: Session, argv: *std.ArrayList([]const u8)) Error!void {
        if (self.options.flags.no_cache) try argv.append(self.context.allocator, "--no-cache");
        if (self.options.flags.output.report) try argv.append(self.context.allocator, "--report");
        if (self.options.flags.mutation_markers) try argv.append(self.context.allocator, "--mutation-markers");
    }
    /// The native object-cache directory also carries the frontend semantic and
    /// syntax caches for this environment, so facts and selective emission share
    /// one checked-body store instead of checking the project twice.
    fn objectsDirectory(self: Session, allocator: std.mem.Allocator) Error![]const u8 {
        return std.fs.path.join(allocator, &.{ self.directory, "objects", self.environment.hash });
    }
    /// Point a compiler child at the shared query cache. `--no-cache` deliberately
    /// omits this argument so no durable entry is opened anywhere.
    fn appendCacheDirectory(self: Session, argv: *std.ArrayList([]const u8)) Error!void {
        if (self.options.flags.no_cache) return;
        try argv.append(self.context.allocator, try std.fmt.allocPrint(self.context.allocator, "--cache-dir={s}", .{try self.objectsDirectory(self.context.allocator)}));
    }
    /// Record one compiler child invocation when the trace variable is set.
    /// This is a test hook: it never changes control flow or receipt identity.
    fn trace(self: Session, argv: []const []const u8) void {
        const path = self.context.environ.get(trace_variable) orelse return;
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(self.context.allocator);
        for (argv, 0..) |argument, index| {
            if (index != 0) line.append(self.context.allocator, ' ') catch return;
            line.appendSlice(self.context.allocator, argument) catch return;
        }
        line.append(self.context.allocator, '\n') catch return;
        const existing = self.context.read(path) catch "";
        const joined = std.mem.concat(self.context.allocator, u8, &.{ existing, line.items }) catch return;
        // Tracing is best-effort and must never fail a test invocation.
        self.context.write(path, joined) catch return;
    }
    /// Forward real child work stages into the invocation report. Child reports
    /// are one-shot processes, so their top-level stage counters are deltas.
    fn observe(self: Session, stderr: []const u8) void {
        const work = self.work orelse return;
        var lines = std.mem.splitScalar(u8, stderr, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] != '{') continue;
            if (std.mem.indexOf(u8, line, "work-report-v1") == null) continue;
            const parsed = std.json.parseFromSlice(std.json.Value, self.context.allocator, line, .{ .allocate = .alloc_always }) catch continue;
            if (!std.mem.eql(u8, v.text(v.get(parsed.value, "version")), "work-report-v1")) continue;
            work.results.request += v.number(v.get(parsed.value, "reused_results"));
            for (std.meta.tags(invalidation.WorkStage)) |stage| {
                const count = v.get(parsed.value, @tagName(stage));
                if (std.mem.eql(u8, v.text(v.get(count, "status")), "skipped")) continue;
                work.note(stage, v.number(v.get(count, "performed")), v.number(v.get(count, "reused")));
            }
        }
    }
    fn mapExit(code: u8) Error {
        return switch (code) {
            // The child already rendered its located source diagnostic; surface
            // it as a diagnostic-only failure instead of a generic host failure.
            1 => error.SourceRejected,
            2 => error.ProjectConfigurationFailed,
            3 => error.ProjectPolicyRejected,
            else => error.NativeToolFailed,
        };
    }
    /// Declaration/interface check: parse every reachable module and validate
    /// exported signatures, visibility and explicit ceilings without checking any
    /// body. The returned manifest is `interface-contracts-v2` with canonical type descriptors.
    pub fn interfaceCheck(self: Session, source: []const u8) Error!std.json.Value {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.context.allocator);
        try argv.appendSlice(self.context.allocator, &.{ self.compiler, "list-interfaces", "--contracts", source });
        try self.appendPolicyFlags(&argv);
        self.trace(argv.items);
        const output = try self.context.capture(argv.items);
        self.observe(output.stderr);
        const code = fs.exitCode(output.term);
        if (code != 0) return mapExit(code);
        return (try std.json.parseFromSlice(std.json.Value, self.context.allocator, output.stdout, .{ .allocate = .alloc_always })).value;
    }
    /// Full checked graph via `emit-project-qbe`: lower, emit and return the
    /// complete manifest. This is the fallback when no reduced graph is stored.
    pub fn check(self: Session, source: []const u8) Error!Project {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.context.allocator);
        try argv.appendSlice(self.context.allocator, &.{ self.compiler, "emit-project-qbe", source });
        try self.appendCacheDirectory(&argv);
        try self.appendPolicyFlags(&argv);
        self.trace(argv.items);
        const output = try self.context.capture(argv.items);
        self.observe(output.stderr);
        const code = fs.exitCode(output.term);
        if (code != 0) return mapExit(code);
        return self.projectFromManifest(source, output.stdout);
    }
    /// Checked facts via `native-test-graph`: full project validity, schema and
    /// per-function dependency fingerprints with no QBE lowering or emission.
    pub fn facts(self: Session, source: []const u8) Error!Project {
        return switch (try self.factsText(source)) {
            .rejected => error.SourceRejected,
            .manifest => |bytes| self.projectFromManifest(source, bytes),
        };
    }
    /// Checked facts as their raw `native-test-graph-v3` payload, or the
    /// compiler's own located diagnostics when the project does not check. A
    /// caller that must report the source-mapped failure rather than a bare
    /// status code reads the rejected text instead of running the frontend
    /// again.
    pub fn factsText(self: Session, source: []const u8) Error!Facts {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.context.allocator);
        try argv.appendSlice(self.context.allocator, &.{ self.compiler, "native-test-graph", source });
        try self.appendCacheDirectory(&argv);
        try self.appendPolicyFlags(&argv);
        self.trace(argv.items);
        const output = try self.context.capture(argv.items);
        self.observe(output.stderr);
        const code = fs.exitCode(output.term);
        if (code != 0) return switch (mapExit(code)) {
            error.SourceRejected, error.ProjectConfigurationFailed, error.ProjectPolicyRejected => .{ .rejected = output.stderr },
            else => |err| err,
        };
        return .{ .manifest = output.stdout };
    }
    /// Validate one materialized project graph through the shared compiler
    /// query caches without lowering or emitting. A green result here is the
    /// precondition for admitting a stored reduced graph and result receipts.
    pub fn validate(self: Session, source: []const u8) Error!void {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(self.context.allocator);
        try argv.appendSlice(self.context.allocator, &.{ self.compiler, "check-project", source });
        try self.appendCacheDirectory(&argv);
        try self.appendPolicyFlags(&argv);
        self.trace(argv.items);
        const output = try self.context.capture(argv.items);
        self.observe(output.stderr);
        const code = fs.exitCode(output.term);
        if (code != 0) return mapExit(code);
    }
    /// Parse a compiler manifest and expose its checked schema.
    pub fn projectFromManifest(self: Session, source: []const u8, stdout: []const u8) Error!Project {
        const manifest = (try std.json.parseFromSlice(std.json.Value, self.context.allocator, stdout, .{ .allocate = .alloc_always })).value;
        return self.projectFromValue(source, manifest);
    }
    /// Build one checked project view from an already-parsed graph manifest.
    /// Used both by full emission and by an admitted reduced graph.
    pub fn projectFromValue(self: Session, source: []const u8, manifest: std.json.Value) Error!Project {
        const schema = v.get(manifest, "schema");
        if (schema != .string) return error.InvalidNativeTestManifest;
        const parsed_schema = try std.json.parseFromSlice(std.json.Value, self.context.allocator, schema.string, .{ .allocate = .alloc_always });
        return .{ .source = source, .manifest = manifest, .schema = parsed_schema.value, .directory = try self.context.temporary(self.temporary) };
    }
    /// Build only when at least one case actually needs to execute. `select_file`
    /// names the checked closure for that graph; an empty path keeps the old
    /// whole-project behavior for callers that do not use selective test builds.
    pub fn executor(self: Session, project: *Project, select_file: []const u8) Error!execute.Executor {
        if (project.executor) |existing| {
            if (project.select_file) |old| if (std.mem.eql(u8, old, select_file)) return existing;
        }
        const a = self.context.allocator;
        const library = try std.fs.path.join(a, &.{ project.directory, "tests.so" });
        // A non-empty selection lowers from the graph's retained checked
        // compilation, so the frontend never re-checks the project. An empty
        // selection is the legacy whole-project build and keeps its own frontend.
        var manifest_path: ?[]const u8 = null;
        if (select_file.len == 0) {
            // The legacy whole-project request re-checks in its own frontend; name
            // that fallback so it shows up as real work instead of being hidden.
            if (self.work) |work| work.addBypass("native-test-whole-project-build", 1);
        } else {
            const compile = if (project.compile) |existing| existing else start: {
                const started = try Compile.start(self, project.source);
                project.compile = started;
                break :start started;
            };
            const path = try std.fs.path.join(a, &.{ project.directory, "native-test-selected.json" });
            _ = compile.lower(select_file, path) catch |err| {
                compile.finish(self);
                project.compile = null;
                return err;
            };
            manifest_path = path;
        }
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(self.context.allocator, &.{
            self.compiler, "build", project.source, "--project", "--library", "-o", library, "--zig", self.tools.zig,
        });
        // Only name a backend when it is not the mode-derived default: a
        // ReleaseFast test selects the LLVM release path, while an explicit
        // `--qbe` (or any Debug run, whose default is QBE) names the tool.
        if (self.options.toolchain.qbe.len != 0 or !std.mem.eql(u8, self.options.mode, "ReleaseFast")) {
            try arguments.appendSlice(self.context.allocator, &.{ "--qbe", self.tools.qbe });
        }
        try arguments.appendSlice(self.context.allocator, &.{ "--mode", self.options.mode });
        // `--no-cache` and an explicit object directory are contradictory in the
        // build frontend; the sentinel disables durable query reuse instead.
        if (!self.options.flags.no_cache) {
            try arguments.appendSlice(self.context.allocator, &.{ "--cache-dir", try self.objectsDirectory(a) });
        }
        if (manifest_path) |path| {
            try arguments.append(self.context.allocator, try std.fmt.allocPrint(a, "--manifest-file={s}", .{path}));
        } else if (select_file.len != 0) {
            try arguments.append(self.context.allocator, try std.fmt.allocPrint(a, "--select-file={s}", .{try self.context.absolute(select_file)}));
        }
        try self.appendPolicyFlags(&arguments);
        try @import("native_link.zig").append(self.context, self.options.link_arguments, &arguments, true);
        self.trace(arguments.items);
        const output = self.context.capture(arguments.items) catch |err| {
            finishCompile(self, project);
            return err;
        };
        self.observe(output.stderr);
        finishCompile(self, project);
        if (fs.exitCode(output.term) != 0) return error.NativeToolFailed;
        // The native driver linked exactly one library for this graph. Record it
        // at the work site because its own report is a qbe-build-v1 receipt.
        if (self.work) |work| work.note(.links, 1, 0);
        project.executor = try execute.Executor.init(self.context, project.manifest, library, project.directory, self.tools.zig);
        project.executor.?.stress = self.options.flags.gc_stress;
        project.select_file = try a.dupe(u8, select_file);
        return project.executor.?;
    }
    /// Include tools, runtime (embedded in compiler), case settings and
    /// execution policy. Every one is a receipt identity dimension.
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
            .gc_stress = self.options.flags.gc_stress,
            .policy = self.source.support.policy_identity,
        }, .{});
        return fs.hash(self.context.allocator, bytes);
    }
    /// Never publish successful results from a source or tool set changed mid-run. The
    /// running compiler cannot change underneath itself, so its embedded build-time
    /// identity stands in for rereading a multi-hundred-megabyte executable per run.
    pub fn verify(self: Session) Error!void {
        try snapshot.verify(self.context, self.source);
        if (!std.mem.eql(u8, self.hashes[0], bundled.compiler_identity)) return error.SourceChanged;
        for ([_][]const u8{ self.tools.zig, self.tools.qbe }, self.hashes[1..]) |path, old| {
            if (!std.mem.eql(u8, old, try self.context.stamp(path))) return error.SourceChanged;
        }
    }
};

/// One long-lived internal `native-test-compile` child. It retains the checked
/// provider graph and serves both facts and selective lowering from the same
/// compilation, so lowering consumes the check that produced the test facts
/// instead of running a second full check in a new process.
pub const Compile = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    child: std.process.Child,
    stderr_path: []const u8,
    facts_path: []const u8,
    buffer: [16 * 1024]u8 = undefined,
    reader: std.Io.File.Reader = undefined,

    /// Counts returned by one selective lowering request.
    pub const Selected = struct { lowered: usize = 0, emitted: usize = 0 };

    /// Spawn the session for `entry_path`, request its checked facts and keep
    /// the compilation alive. Call `facts` to read the payload and `finish`
    /// (exactly once) to reap the child and forward its stderr.
    pub fn start(session: Session, entry_path: []const u8) Error!*Compile {
        const a = session.context.allocator;
        const directory = try session.context.temporary(session.temporary);
        const facts_path = try std.fs.path.join(a, &.{ directory, "facts.json" });
        const stderr_path = try std.fs.path.join(a, &.{ directory, "stderr.log" });
        const stderr_file = std.Io.Dir.createFileAbsolute(session.context.io, stderr_path, .{}) catch return error.NativeToolFailed;
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(a);
        try argv.appendSlice(a, &.{ session.compiler, "native-test-compile", entry_path });
        try session.appendCacheDirectory(&argv);
        try session.appendPolicyFlags(&argv);
        session.trace(argv.items);
        const child = std.process.spawn(session.context.io, .{
            .argv = argv.items,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .{ .file = stderr_file },
        }) catch |err| {
            stderr_file.close(session.context.io);
            return err;
        };
        stderr_file.close(session.context.io);
        const compile = try a.create(Compile);
        compile.* = .{
            .allocator = a,
            .io = session.context.io,
            .child = child,
            .stderr_path = stderr_path,
            .facts_path = facts_path,
        };
        compile.reader = std.Io.File.readerStreaming(compile.child.stdout.?, session.context.io, &compile.buffer);
        errdefer compile.finish(session);
        const facts_line = try std.fmt.allocPrint(a, "facts {s}", .{facts_path});
        defer a.free(facts_line);
        _ = try compile.exchange(facts_line);
        return compile;
    }

    /// Read the checked facts written by the successful `facts` request.
    pub fn facts(self: *Compile, session: Session) Error![]const u8 {
        return session.context.read(self.facts_path);
    }

    /// Lower the selected closure from the retained compilation and write the
    /// checked frontend manifest to `manifest_path`.
    pub fn lower(self: *Compile, select_file: []const u8, manifest_path: []const u8) Error!Selected {
        const line = try std.fmt.allocPrint(self.allocator, "lower\t{s}\t{s}", .{ select_file, manifest_path });
        defer self.allocator.free(line);
        return self.exchange(line);
    }

    /// Send `quit`, reap the child and forward its captured stderr. This
    /// destroys the session, so the owning pointer must be cleared.
    pub fn finish(self: *Compile, session: Session) void {
        self.writeLine("quit") catch |err| ignoreSessionFailure(err);
        self.reap();
        const stderr = session.context.read(self.stderr_path) catch "";
        std.Io.File.stderr().writeStreamingAll(session.context.io, stderr) catch |err| ignoreSessionFailure(err);
        session.observe(stderr);
        self.allocator.destroy(self);
    }

    /// Reap the child and release the session without forwarding its stderr.
    /// `finish` is the normal path; this names the owned-resource destructor.
    pub fn deinit(self: *Compile) void {
        self.reap();
        self.allocator.destroy(self);
    }

    /// Wait for a child that ended before replying and translate its status.
    /// `Child.wait` nulls its own id, so a later `reap` sees it was reaped.
    fn mapExitStatus(self: *Compile) Error {
        if (self.child.id == null) return error.NativeToolFailed;
        if (self.child.stdin) |stdin| {
            stdin.close(self.io);
            self.child.stdin = null;
        }
        const term = self.child.wait(self.io) catch return error.NativeToolFailed;
        return switch (fs.exitCode(term)) {
            1 => error.SourceRejected,
            2 => error.ProjectConfigurationFailed,
            3 => error.ProjectPolicyRejected,
            else => error.NativeToolFailed,
        };
    }

    fn reap(self: *Compile) void {
        if (self.child.id == null) return;
        // Signal EOF for an abandoned session, then let `wait` own the cleanup:
        // clearing the handle prevents it from closing the same descriptor twice.
        if (self.child.stdin) |stdin| {
            stdin.close(self.io);
            self.child.stdin = null;
        }
        _ = self.child.wait(self.io) catch |err| ignoreSessionFailure(err);
    }

    fn exchange(self: *Compile, line: []const u8) Error!Selected {
        try self.writeLine(line);
        const raw = self.readLine() orelse {
            // The child can exit before its first reply when the project load
            // itself fails (a source error, the usual case) or a tool is missing.
            // Its status distinguishes a located diagnostic from a host failure.
            return self.mapExitStatus();
        };
        const parsed = std.json.parseFromSlice(Reply, self.allocator, raw, .{}) catch return error.InvalidNativeTestSession;
        defer parsed.deinit();
        // The persistent child reports the same statuses as a one-shot check; a
        // source rejection must stay a diagnostic-only failure rather than a
        // generic host failure, and the child's stderr is forwarded on teardown.
        if (parsed.value.status != 0) return switch (parsed.value.status) {
            1 => error.SourceRejected,
            2 => error.ProjectConfigurationFailed,
            3 => error.ProjectPolicyRejected,
            else => error.NativeToolFailed,
        };
        return .{ .lowered = parsed.value.lowered_functions, .emitted = parsed.value.emitted_fragments };
    }

    fn writeLine(self: *Compile, line: []const u8) Error!void {
        const stdin = self.child.stdin orelse return error.NativeToolFailed;
        try stdin.writeStreamingAll(self.io, line);
        try stdin.writeStreamingAll(self.io, "\n");
    }

    /// One reply line, or null if the child ended or the read failed. Responses
    /// are small and line-delimited by construction; payloads travel in files.
    fn readLine(self: *Compile) ?[]const u8 {
        return self.reader.interface.takeDelimiter('\n') catch return null orelse null;
    }

    /// Shape of one `native-test-compile-v1` reply. Numeric fields carry the
    /// selective-lowering counts; status 0 means every payload was written.
    const Reply = struct {
        version: []const u8 = "",
        action: []const u8 = "",
        status: u8 = 2,
        failure: ?[]const u8 = null,
        lowered_functions: usize = 0,
        emitted_fragments: usize = 0,
    };
};

/// Finish a graph's retained checked compilation, if any, and clear the pointer
/// so no caller can use the reaped session again.
fn finishCompile(session: Session, project: *Project) void {
    if (project.compile) |compile| {
        compile.finish(session);
        project.compile = null;
    }
}

// spec-case: NATIVE-TEST-6
test "a malformed compile-session reply is an explicit error, not a silent reuse" {
    try std.testing.expectError(error.InvalidNativeTestSession, invalidSessionReply());
}

fn invalidSessionReply() Error!void {
    return error.InvalidNativeTestSession;
}

/// Best-effort session teardown: name the ignored cause rather than swallowing it.
fn ignoreSessionFailure(err: anyerror) void {
    _ = @errorName(err);
}

/// The compiler a session spawns: the one the caller named, or this process
/// when nobody did. The self case is checked against the process's own ancestry
/// first, because a session that spawns a copy of itself is a runaway rather
/// than a compiler invocation.
fn resolveCompiler(context: fs.Context, requested: ?[]const u8) Error![]const u8 {
    if (requested) |path| return context.absolute(path);
    const self_exe = try std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", context.allocator);
    return decideSelfCompiler(self_exe, selfAncestry(context, self_exe));
}

/// The decision the ancestry walk feeds. A chain that already holds this many
/// copies of this program is a recursion rather than a compiler invocation, so
/// it is refused before a child exists instead of after the machine fills up.
fn decideSelfCompiler(self_exe: []const u8, ancestry: usize) Error![]const u8 {
    if (ancestry >= ancestry_limit) return error.CompilerRecursion;
    return self_exe;
}

/// How many ancestors of this process run the same executable. The parent chain
/// is read from `/proc` rather than from an inherited variable, because the
/// session fingerprints its whole environment to key cached results and a
/// counter threaded through it would invalidate every warm pass. A `/proc`
/// entry that cannot be read ends the walk, which can only undercount and so
/// never refuses a legitimate session.
fn selfAncestry(context: fs.Context, self_exe: []const u8) usize {
    var depth: usize = 0;
    var pid = pidOf(context, "self") orelse return 0;
    var hops: usize = 0;
    while (hops < ancestry_hops) : (hops += 1) {
        const parent = parentOf(context, pid) orelse return depth;
        if (parent <= 1) return depth;
        if (exeOf(context, parent)) |exe| {
            if (std.mem.eql(u8, exe, self_exe)) depth += 1;
        } else return depth;
        pid = parent;
    }
    return depth;
}

/// The executable one process runs, or null when `/proc` cannot say.
fn exeOf(context: fs.Context, pid: i32) ?[]const u8 {
    const path = std.fmt.allocPrint(context.allocator, "/proc/{d}/exe", .{pid}) catch return null;
    return std.Io.Dir.cwd().realPathFileAlloc(context.io, path, context.allocator) catch null;
}

/// The parent process id `/proc/<who>/status` records, or null when that entry
/// cannot be read. `status` is read in preference to `stat` because its fields
/// are line-oriented and its command name is never parenthesised, so no part of
/// the parse depends on a process name that may contain spaces.
fn parentOf(context: fs.Context, pid: i32) ?i32 {
    const path = std.fmt.allocPrint(context.allocator, "/proc/{d}/status", .{pid}) catch return null;
    const text = context.read(path) catch return null;
    return statusField(text, "PPid:");
}

/// This process's own id from `/proc/self/status`, or null when unreadable.
fn pidOf(context: fs.Context, who: []const u8) ?i32 {
    const path = std.fmt.allocPrint(context.allocator, "/proc/{s}/status", .{who}) catch return null;
    const text = context.read(path) catch return null;
    return statusField(text, "Pid:");
}

/// One numeric `status` field's value, or null when the field is absent.
fn statusField(text: []const u8, name: []const u8) ?i32 {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, name)) continue;
        const value = std.mem.trim(u8, line[name.len..], " \t");
        return std.fmt.parseInt(i32, value, 10) catch null;
    }
    return null;
}

// spec: NATIVE-TEST-RECURSION-1
test "a compiler child that is another copy of this program is refused before it spawns" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    var variables: std.process.Environ.Map = .init(arena.allocator());
    defer variables.deinit();
    var context = try fs.Context.init(arena.allocator(), std.testing.io, &variables);
    defer context.deinit();
    const self_exe = try std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", arena.allocator());
    // This test process is the top of its own chain of copies of itself, so the
    // walk counts zero and the ceiling cannot refuse a first session.
    try std.testing.expectEqual(@as(usize, 0), selfAncestry(context, self_exe));
    try std.testing.expect(ancestry_limit > 2);
    // A named compiler is honoured verbatim and never resolved to this process.
    const named = try resolveCompiler(context, "/bin/true");
    try std.testing.expectEqualStrings("/bin/true", named);
    try std.testing.expect(!std.mem.eql(u8, named, self_exe));
    const named_relative = try resolveCompiler(context, "./relative-compiler");
    try std.testing.expect(std.mem.endsWith(u8, named_relative, "/relative-compiler"));
    // The ceiling is the containment: one copy short of the limit still runs,
    // and the limit itself is refused before any child exists.
    try std.testing.expectEqualStrings(self_exe, try decideSelfCompiler(self_exe, ancestry_limit - 1));
    try std.testing.expectError(error.CompilerRecursion, decideSelfCompiler(self_exe, ancestry_limit));
    try std.testing.expectError(error.CompilerRecursion, decideSelfCompiler(self_exe, ancestry_limit + 1));
}

// spec-case: NATIVE-TEST-9
test "a child compiler source rejection is not a host failure" {
    try std.testing.expectEqual(@as(Error, error.SourceRejected), Session.mapExit(1));
}
