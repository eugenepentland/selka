//! Build one checked guest natively and run it in a private child process.
//! A Zig host application owns no interpreter: it compiles its guest and a
//! trusted C provider into a single executable, hands that executable one
//! invocation's bytes through private files, and reads the result back.
const std = @import("std");
const qbe_build = @import("qbe_build");
const tools = @import("host_tools");
/// Build, transport and guest-outcome failures of one native invocation.
pub const Error = qbe_build.Error || std.Io.Dir.CreateDirError || error{ GuestTrap, InvalidGuestResult, InvalidBuildConfiguration };
/// Bound on what one child may leave on a captured stream before publication.
pub const stream_limit = 256 * 1024 * 1024;
/// The step budget a host application gives one guest invocation that carries
/// instruction accounting. Host guests parse and render whole documents, so it
/// is far above an ordinary `run`.
pub const step_budget = "--max-steps=100000000";
/// The call-depth ceiling a host application gives one guest invocation. It is
/// the number of frame slots the runtime tracks for an unbounded run anyway, so
/// naming it costs neither address space nor a wider execution stack, and it
/// turns runaway recursion into a deterministic `R_FRAME_LIMIT`.
pub const frame_budget = "--max-frames=1024";
/// The wall-clock ceiling a host application gives one guest invocation. One
/// armed monotonic timer at start-up bounds a guest that counts no
/// instructions; it is the runaway guard that instruction accounting used to
/// be, at no measurable cost to an honest render.
pub const wall_clock_budget = "--timeout=60";
/// What one host application asks the runtime to enforce on its guest, and
/// therefore the accounting that guest's build must carry. Instruction
/// accounting triples the render time of an optimized guest, so a host that
/// does not need an exact instruction ceiling chooses `.frames`.
pub const Accounting = enum {
    /// Count instructions: build with `--step-accounting` and run under
    /// `step_budget`, which a guest without that accounting would refuse.
    steps,
    /// Count call depth only: build with `frame_budget`, and bound one
    /// invocation with that ceiling and the wall clock. The byte ceiling and
    /// the native stack floor stay in force either way.
    frames,
    /// The runtime ceilings that match this policy. One invocation is bounded
    /// by exactly what its build can enforce, so a host can never hand a guest
    /// a ceiling whose accounting the build dropped.
    pub fn bounds(self: Accounting) []const []const u8 {
        return switch (self) {
            .steps => &.{step_budget},
            .frames => &.{ frame_budget, wall_clock_budget },
        };
    }
};
/// Private per-invocation build products and transport files.
const Files = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    fn absolute(self: Files, path: []const u8) Error![]const u8 {
        const cwd = try std.Io.Dir.cwd().realPathFileAlloc(self.io, ".", self.allocator);
        return std.fs.path.resolve(self.allocator, &.{ cwd, path });
    }
    fn temporary(self: Files, parent: []const u8) Error![]const u8 {
        try std.Io.Dir.cwd().createDirPath(self.io, parent);
        var random: [16]u8 = undefined;
        std.Io.random(self.io, &random);
        const name = try std.fmt.allocPrint(self.allocator, ".guest-{s}", .{std.fmt.bytesToHex(random, .lower)});
        const path = try std.fs.path.join(self.allocator, &.{ parent, name });
        try std.Io.Dir.cwd().createDir(self.io, path, .default_dir);
        return path;
    }
    fn remove(self: Files, path: []const u8) void {
        std.Io.Dir.cwd().deleteTree(self.io, path) catch return;
    }
};
/// What one host application asks the native build driver to produce.
pub const Request = struct {
    project: []const u8,
    provider: []const u8,
    build: BuildOptions = .{},
};
/// Native backend selected by an embedding host. `.qbe` pins QBE and names the
/// tool; `.llvm` asks the driver for the release code generator and pins no
/// assembler, so the driver's own backend policy decides the rest.
pub const Backend = enum { qbe, llvm };
/// Controls for the qualified LLVM adapter. A null value leaves the driver's
/// own default in place rather than restating it here.
pub const Llvm = struct {
    adapter: ?[]const u8 = null,
    optimization: ?[]const u8 = null,
    lto: bool = false,
};
/// Native guest build controls shared by host applications.
pub const BuildOptions = struct {
    cache: ?[]const u8 = null,
    qbe: []const u8 = "qbe",
    zig: []const u8 = "zig",
    backend: Backend = .qbe,
    llvm: Llvm = .{},
    accounting: Accounting = .steps,
    /// Apply these controls to one project and trusted provider.
    pub fn request(self: BuildOptions, project: []const u8, provider: []const u8) Request {
        return .{ .project = project, .provider = provider, .build = self };
    }
};
/// One built guest executable and the private directory that holds it.
pub const Program = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    environment: std.process.Environ.Map,
    directory: []const u8,
    path: []const u8,
    /// Compile the checked guest and the trusted provider into one executable.
    /// The host's own environment is inherited so the provider can be told where
    /// this invocation's bytes live without spending the guest's command line.
    pub fn build(process: std.process.Init, request: Request) Error!Program {
        try validateBuild(request.build);
        const files: Files = .{ .allocator = process.arena.allocator(), .io = process.io };
        const cache = try cacheDirectory(files, process.environ_map, request.build.cache);
        const directory = try files.temporary(cache);
        errdefer files.remove(directory);
        var environment = try process.environ_map.clone(files.allocator);
        errdefer environment.deinit();
        var program: Program = .{
            .allocator = files.allocator,
            .io = files.io,
            .environment = environment,
            .directory = directory,
            .path = try std.fs.path.join(files.allocator, &.{ directory, "program" }),
        };
        try program.link(process, request, cache);
        return program;
    }
    fn link(self: *Program, process: std.process.Init, request: Request, cache: []const u8) Error!void {
        const files: Files = .{ .allocator = self.allocator, .io = self.io };
        const source = try self.file("provider.c");
        try self.write(source, request.provider);
        const entry = try std.fs.path.join(self.allocator, &.{ try files.absolute(request.project), "main.my" });
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(self.allocator, &.{
            entry,   "--project",                                           "--provider", source, "-o", self.path, "--cache-dir", cache,
            "--zig", located(self.io, request.build.zig, "zig", tools.zig),
        });
        try arguments.appendSlice(self.allocator, try policyArguments(self.allocator, self.io, request.build));
        const status = try qbe_build.run(process, arguments.items);
        if (status != 0) return error.NativeToolFailed;
    }
    /// Remove every private file; nothing one host invocation produced outlives it.
    pub fn deinit(self: *Program) void {
        self.environment.deinit();
        const files: Files = .{ .allocator = self.allocator, .io = self.io };
        files.remove(self.directory);
    }
    /// Tell the trusted provider one thing about this invocation.
    pub fn set(self: *Program, name: []const u8, value: []const u8) Error!void {
        try self.environment.put(name, value);
    }
    /// Tell the trusted provider one decimal budget or count.
    pub fn setNumber(self: *Program, name: []const u8, value: u64) Error!void {
        try self.set(name, try std.fmt.allocPrint(self.allocator, "{d}", .{value}));
    }
    /// Name one private transport file beside the built executable.
    pub fn file(self: Program, name: []const u8) Error![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.directory, name });
    }
    /// Write one transport input the trusted provider will read back.
    pub fn write(self: Program, path: []const u8, data: []const u8) Error!void {
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = data });
    }
    /// Read one file the guest produced; bytes have this invocation's lifetime.
    pub fn read(self: Program, path: []const u8) Error![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(self.io, path, self.allocator, .unlimited);
    }
    /// Run the guest once and report its entry-point result. A trapped or
    /// otherwise failing child leaves its diagnostics on the host's stderr.
    pub fn invoke(self: *Program, arguments: []const []const u8) Error!i64 {
        try qbe_build.runtime_options.apply(self.allocator, &self.environment, try command(self.allocator, arguments));
        const result = try std.process.run(self.allocator, self.io, .{
            .argv = &.{self.path},
            .environ_map = &self.environment,
            .stdout_limit = .limited(stream_limit),
            .stderr_limit = .limited(stream_limit),
        });
        try std.Io.File.stderr().writeStreamingAll(self.io, result.stderr);
        // The entry result is now the process exit status, so a nonzero status no
        // longer means a trap: a host reads the full result from the printed line
        // instead. A native runtime failure ends the process by signal or writes a
        // diagnostic to stderr, neither of which a clean run produces.
        if (result.term != .exited or result.stderr.len != 0) return error.GuestTrap;
        return outcome(result.stdout);
    }
};
/// The build arguments that carry one host's policy: which accounting the guest
/// must enforce, and which code generator produces it. Only a QBE build names
/// `--qbe`, because an explicit assembler pins the backend the driver would
/// otherwise resolve from the optimize mode.
fn policyArguments(allocator: std.mem.Allocator, io: std.Io, build: BuildOptions) Error![]const []const u8 {
    var args: std.ArrayList([]const u8) = .empty;
    switch (build.accounting) {
        .steps => try args.append(allocator, "--step-accounting"),
        .frames => try args.append(allocator, frame_budget),
    }
    if (build.backend == .qbe) {
        try args.appendSlice(allocator, &.{ "--qbe", located(io, build.qbe, "qbe", tools.qbe) });
        return args.toOwnedSlice(allocator);
    }
    try args.appendSlice(allocator, &.{ "--backend", "llvm" });
    if (build.llvm.adapter) |path| {
        try args.appendSlice(allocator, &.{ "--llvm-adapter", path });
    } else if (!installedAdapter(allocator, io)) {
        try args.appendSlice(allocator, &.{ "--llvm-adapter", tools.llvm_adapter });
    }
    if (build.llvm.optimization) |opt| try args.appendSlice(allocator, &.{ "--llvm-opt", opt });
    if (build.llvm.lto) try args.append(allocator, "--lto");
    return args.toOwnedSlice(allocator);
}
fn validateBuild(build: BuildOptions) error{InvalidBuildConfiguration}!void {
    if (build.backend == .qbe and (build.llvm.adapter != null or build.llvm.optimization != null or build.llvm.lto)) return error.InvalidBuildConfiguration;
}
fn installedAdapter(allocator: std.mem.Allocator, io: std.Io) bool {
    const executable = std.Io.Dir.cwd().realPathFileAlloc(io, "/proc/self/exe", allocator) catch return false;
    defer allocator.free(executable);
    const directory = std.fs.path.dirname(executable) orelse return false;
    const candidate = std.fs.path.resolve(allocator, &.{ directory, "../lib/mylang-llvm/qbe_llvm.py" }) catch return false;
    defer allocator.free(candidate);
    std.Io.Dir.cwd().access(io, candidate, .{ .execute = true }) catch return false;
    return true;
}
/// A host application runs from an arbitrary working directory, so its shared
/// object cache lives with the user's other caches rather than beside the guest.
fn cacheDirectory(files: Files, environ: *const std.process.Environ.Map, chosen: ?[]const u8) Error![]const u8 {
    if (chosen) |path| return files.absolute(path);
    if (environ.get("XDG_CACHE_HOME")) |base| return std.fs.path.join(files.allocator, &.{ base, "mylang-hosts" });
    const home = environ.get("HOME") orelse return files.absolute(".mylang-cache/qbe");
    return std.fs.path.join(files.allocator, &.{ home, ".cache", "mylang-hosts" });
}
/// Prefer an explicitly named tool, then the one this build produced, so an
/// uninstalled host still links a guest and an installed one still uses `PATH`.
fn located(io: std.Io, chosen: []const u8, name: []const u8, fallback: []const u8) []const u8 {
    if (!std.mem.eql(u8, chosen, name)) return chosen;
    std.Io.Dir.cwd().access(io, fallback, .{ .execute = true }) catch return chosen;
    return fallback;
}
/// The runtime options for one guest invocation, which travel in
/// `MYLANG_OPTIONS` rather than on the guest's command line. A native
/// executable reports its entry result only when asked, and a host application
/// always needs it.
pub fn command(allocator: std.mem.Allocator, arguments: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    var options: std.ArrayList([]const u8) = .empty;
    try options.append(allocator, "--print-result");
    try options.appendSlice(allocator, arguments);
    return options.toOwnedSlice(allocator);
}

/// A native executable reports its entry-point result as its final output line.
pub fn outcome(stdout: []const u8) error{InvalidGuestResult}!i64 {
    const trimmed = std.mem.trimEnd(u8, stdout, "\n");
    const start = if (std.mem.lastIndexOfScalar(u8, trimmed, '\n')) |index| index + 1 else 0;
    return std.fmt.parseInt(i64, trimmed[start..], 10) catch error.InvalidGuestResult;
}

test "QBE host builds reject LLVM-only controls" {
    try std.testing.expectError(error.InvalidBuildConfiguration, validateBuild(.{ .llvm = .{ .optimization = "3" } }));
    try std.testing.expectError(error.InvalidBuildConfiguration, validateBuild(.{ .llvm = .{ .lto = true } }));
    try validateBuild(.{ .backend = .llvm, .llvm = .{ .optimization = "3", .lto = true } });
}

/// One policy's build arguments as a single string, for the assertions below.
fn joinedPolicy(allocator: std.mem.Allocator, build: BuildOptions) ![]const u8 {
    const args = try policyArguments(allocator, std.testing.io, build);
    defer allocator.free(args);
    return std.mem.join(allocator, " ", args);
}

// spec: HOST-GUEST-POLICY-1
test "a host names its guest's accounting and pins an assembler only for QBE" {
    const allocator = std.testing.allocator;
    const bounded_qbe = try joinedPolicy(allocator, .{ .qbe = "/tools/qbe" });
    defer allocator.free(bounded_qbe);
    try std.testing.expectEqualStrings("--step-accounting --qbe /tools/qbe", bounded_qbe);
    const release = try joinedPolicy(allocator, .{ .backend = .llvm, .accounting = .frames, .llvm = .{ .adapter = "/adapter.py", .optimization = "3" } });
    defer allocator.free(release);
    try std.testing.expectEqualStrings("--max-frames=1024 --backend llvm --llvm-adapter /adapter.py --llvm-opt 3", release);
    try std.testing.expectEqualDeep(@as([]const []const u8, &.{step_budget}), Accounting.steps.bounds());
    try std.testing.expectEqualDeep(@as([]const []const u8, &.{ frame_budget, wall_clock_budget }), Accounting.frames.bounds());
}

// spec-case: HOST-GUEST-POLICY-1
test "an explicit host LLVM adapter carries optimization and LTO to the driver" {
    const allocator = std.testing.allocator;
    const joined = try joinedPolicy(allocator, .{
        .backend = .llvm,
        .llvm = .{ .adapter = "/adapter.py", .optimization = "3", .lto = true },
    });
    defer allocator.free(joined);
    try std.testing.expectEqualStrings("--step-accounting --backend llvm --llvm-adapter /adapter.py --llvm-opt 3 --lto", joined);
}
