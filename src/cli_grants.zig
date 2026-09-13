//! `--allow-*` command-line authority. A grant provisions a host provider; an
//! entry point that names a capability nobody granted is rejected before the
//! first guest instruction runs, with a diagnostic naming the missing flag.
const std = @import("std");
const language = @import("mylang");
const providers = @import("cli_providers.zig");
const scoped = language.scoped_providers;

/// Most directory grants one command line may carry.
pub const max_directories = 8;
const clock_flag = "--allow-clock";
const random_flag = "--allow-random";
const environment_flag = "--allow-env";
/// One requested directory grant, borrowed from argv for the process lifetime.
pub const Directory = struct { path: []const u8, writable: bool };

/// Parsed `--allow-*` options; every field defaults to no authority at all.
pub const Config = struct {
    directories: [max_directories]Directory = @splat(.{ .path = "", .writable = false }),
    count: usize = 0,
    /// Absent for no grant, otherwise a comma-separated allowlist; empty means every name.
    environment: ?[]const u8 = null,
    /// Absent for no grant, otherwise an optional reproducible seed.
    entropy: ??u64 = null,
    clock: bool = false,

    /// Consume one recognized grant option, rejecting duplicates and empty paths.
    pub fn parse(self: *Config, argument: []const u8) error{Usage}!bool {
        inline for (.{ "--allow-read=", "--allow-write=" }, .{ false, true }) |prefix, writes| {
            if (std.mem.startsWith(u8, argument, prefix)) return self.directory(argument[prefix.len..], writes);
        }
        if (std.mem.eql(u8, argument, clock_flag)) {
            if (self.clock) return error.Usage;
            self.clock = true;
            return true;
        }
        if (try self.optional(argument, random_flag)) |digits| {
            self.entropy = if (digits.len == 0) @as(?u64, null) else std.fmt.parseUnsigned(u64, digits, 10) catch return error.Usage;
            return true;
        }
        if (try self.optional(argument, environment_flag)) |names| {
            self.environment = names;
            return true;
        }
        if (!std.mem.eql(u8, argument, "--allow-all")) return false;
        if (self.clock or self.entropy != null or self.environment != null or self.count != 0) return error.Usage;
        self.clock = true;
        self.entropy = @as(?u64, null);
        self.environment = "";
        return self.directory(".", true);
    }
    /// Match a flag that may stand alone or carry a value, rejecting a repeat.
    fn optional(self: *Config, argument: []const u8, flag: []const u8) error{Usage}!?[]const u8 {
        const repeated = if (std.mem.eql(u8, flag, random_flag)) self.entropy != null else self.environment != null;
        if (std.mem.eql(u8, argument, flag)) {
            if (repeated) return error.Usage;
            return "";
        }
        if (!std.mem.startsWith(u8, argument, flag) or argument[flag.len] != '=') return null;
        if (repeated or argument.len == flag.len + 1) return error.Usage;
        return argument[flag.len + 1 ..];
    }
    fn directory(self: *Config, path: []const u8, writes: bool) error{Usage}!bool {
        if (path.len == 0 or self.count == max_directories) return error.Usage;
        for (self.directories[0..self.count]) |existing| {
            if (std.mem.eql(u8, existing.path, path) and existing.writable == writes) return error.Usage;
        }
        self.directories[self.count] = .{ .path = path, .writable = writes };
        self.count += 1;
        return true;
    }
    /// Whether any granted directory permits writing, creating or removing entries.
    pub fn anyWritable(self: Config) bool {
        for (self.directories[0..self.count]) |entry| if (entry.writable) return true;
        return false;
    }
};

/// The flag that would grant one capability an entry point asked for.
pub fn flagFor(ty: language.values.Type) ?[]const u8 {
    return switch (ty) {
        .filesystem_cap => "--allow-read=DIR",
        .network_cap => "--allow-endpoint",
        .clock_cap => clock_flag,
        .random_cap => random_flag,
        .environment_cap => environment_flag,
        else => null,
    };
}

/// Name the first entry parameter whose capability the command line did not grant.
pub fn ungranted(program: language.bytecode.Program, config: Config) ?[]const u8 {
    const entry = program.functions[@backingInt(program.main)];
    for (entry.scope.locals[0..entry.signature.parameter_count]) |parameter| {
        const granted = switch (parameter.ty) {
            .filesystem_cap => config.count != 0,
            .clock_cap => config.clock,
            .random_cap => config.entropy != null,
            .environment_cap => config.environment != null,
            else => true,
        };
        if (!granted) return flagFor(parameter.ty);
    }
    return null;
}

/// Stable provider storage; deinitialize only after the VM releases its stores.
pub const State = struct {
    context: scoped.Context,
    roots: [max_directories]scoped.Root = @splat(.{ .dir = undefined, .writable = false }),
    clock: providers.Clock,
    entropy: providers.Entropy,
    environment: providers.Environment,
    config: Config,

    /// Open every granted directory; no guest file is acquired here.
    pub fn init(self: *State, allocator: std.mem.Allocator, io: std.Io, request: Request) std.Io.Dir.OpenError!void {
        self.* = .{
            .context = .{ .allocator = allocator, .io = io },
            .clock = .{ .io = io },
            .entropy = .init(io, if (request.config.entropy) |seed| seed else null),
            .environment = .{ .environ = request.environ, .names = request.config.environment orelse "" },
            .config = request.config,
        };
        var opened: usize = 0;
        errdefer for (self.roots[0..opened]) |root| root.dir.close(io);
        while (opened < request.config.count) : (opened += 1) {
            const entry = request.config.directories[opened];
            self.roots[opened] = .{ .dir = try std.Io.Dir.cwd().openDir(io, entry.path, .{}), .writable = entry.writable };
        }
        self.context.roots = self.roots[0..opened];
    }
    /// Close acquired resources before the directory grants they borrow.
    pub fn deinit(self: *State) void {
        self.context.deinit();
        for (self.context.roots) |root| root.dir.close(self.context.io);
        self.context.roots = &.{};
    }
    /// Apply the granted authority to execution options, leaving budgets unchanged.
    pub fn apply(self: *State, base: language.vm.Options) language.vm.Options {
        var options = base;
        options.resources = .{
            .filesystem = if (self.context.roots.len != 0) self.context.filesystem() else null,
            // Resource mask bits are read=1, write=2, complete=4.
            .filesystem_permissions = if (self.config.anyWritable()) 7 else 5,
        };
        if (self.config.clock) options.external.clock = self.clock.provider();
        if (self.config.entropy != null) options.external.random = self.entropy.provider();
        if (self.config.environment != null) options.environment = self.environment.provider();
        return options;
    }
};

/// Borrowed grant configuration and the host environment it may expose.
pub const Request = struct { config: Config, environ: *const std.process.Environ.Map };
