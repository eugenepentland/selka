//! Build the guest natively once; each invocation owns a fresh bounded byte-I/O session.
const std = @import("std");
const language = @import("mylang");
const native = @import("host_native");
const bridge = @import("host.zig");
/// Source loading, guest compilation and native build failures keep their identities.
pub const InitError = language.embedded_project.InitError || bridge.Error || native.Error;
/// Resource failures remain distinct from located DSL errors and guest traps.
pub const RunError = native.Error || error{ InvalidSchematic, GuestTrap };
/// The build policy this application ships. The guest is ordinary checked
/// mylang, so it is built the way `mylang build` builds a release program —
/// the LLVM code generator at `-O3` — rather than with the debug assembler an
/// explicit `--qbe` would pin. Full LTO is deliberately not requested: it
/// leaves this render's time unchanged and adds seconds to the relink every
/// invocation pays. Instruction accounting is not requested either: it triples
/// the render, and a call-depth ceiling, the wall clock and the byte ceiling
/// bound a runaway guest for nothing.
pub const release: native.BuildOptions = .{ .backend = .llvm, .llvm = .{ .optimization = "3" }, .accounting = .frames };
/// Owns one built guest and its transport files; initialize in its final address.
pub const App = struct {
    program: native.Program,
    bounds: []const []const u8,
    documents: [3][]const u8,
    published: []const u8,
    reported: []const u8,
    issue: ?bridge.Issue = null,
    /// Build the guest project at this root together with the trusted provider.
    /// Source diagnostics are reported before any native tool runs.
    pub fn initDisk(self: *App, process: std.process.Init, root: []const u8) InitError!void {
        return self.initDiskWithOptions(process, root, release);
    }
    /// Build the checked guest with an explicit native backend policy.
    pub fn initDiskWithOptions(self: *App, process: std.process.Init, root: []const u8, build: native.BuildOptions) InitError!void {
        // The frontend check needed only to read the guest's host declarations is
        // transient: a long-lived host reloading its guest reclaims it every time,
        // so it uses an arena over `gpa` rather than the process's own arena.
        var scratch = std.heap.ArenaAllocator.init(process.gpa);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        var loaded: language.embedded_project.Program = undefined;
        try loaded.initDisk(allocator, process.io, root);
        defer loaded.deinit();
        const names = try bridge.declared(allocator, try loaded.compilation.emitQbe(allocator));
        var program = try native.Program.build(process, build.request(root, bridge.provider));
        errdefer program.deinit();
        self.* = .{
            .program = program,
            .bounds = build.accounting.bounds(),
            .documents = .{ try program.file("source0"), try program.file("source1"), try program.file("source2") },
            .published = try program.file("output"),
            .reported = try program.file("issue"),
        };
        try self.describe(names);
    }
    fn describe(self: *App, names: []const u8) InitError!void {
        try self.program.set("MYLANG_SCHEMATIC_DECLARED", names);
        try self.program.set("MYLANG_SCHEMATIC_OUTPUT", self.published);
        try self.program.set("MYLANG_SCHEMATIC_ISSUE", self.reported);
        for (self.documents, 0..) |path, index| {
            const variable = try std.fmt.allocPrint(self.program.allocator, "MYLANG_SCHEMATIC_INPUT_{d}", .{index});
            try self.program.set(variable, path);
        }
    }
    /// Remove the built guest and every transport file it used.
    pub fn deinit(self: *App) void {
        self.program.deinit();
    }
    /// Return caller-owned SVG only on success; preserve a located issue on failure.
    /// A located issue outranks a nonzero result and a trap, because it names the
    /// guest's own reason rather than the consequence the host observed.
    /// The ceilings this guest was built to enforce are appended to `arguments`,
    /// so one invocation is always bounded and a caller that names a tighter
    /// ceiling of its own is the one the runtime reads first.
    pub fn run(self: *App, documents: *const [3][]const u8, arguments: []const []const u8) RunError![]const u8 {
        self.issue = null;
        if (bridge.validateDocuments(documents)) |issue| {
            self.issue = issue;
            return error.InvalidSchematic;
        }
        for (documents, self.documents) |bytes, path| try self.program.write(path, bytes);
        try self.program.write(self.reported, "");
        const bounded = try std.mem.concat(self.program.allocator, []const u8, &.{ arguments, self.bounds });
        const value = self.program.invoke(bounded) catch |err| return self.failed(err);
        if (self.located()) |issue| {
            self.issue = issue;
            return error.InvalidSchematic;
        }
        if (value != 0) {
            self.issue = .{ .code = 24, .file = 0, .position = 0 };
            return error.InvalidSchematic;
        }
        return self.program.read(self.published);
    }
    fn failed(self: *App, err: RunError) RunError {
        self.issue = self.located();
        return if (self.issue != null) error.InvalidSchematic else err;
    }
    fn located(self: *App) ?bridge.Issue {
        const bytes = self.program.read(self.reported) catch return null;
        return bridge.decode(bytes);
    }
};
