//! Command-line authority. `mylang run` and `run-project` grant every capability
//! by default, the way an ordinary interpreter does. `--restrict` switches the
//! command to deny-by-default, and only then do the `--allow-*` flags narrow
//! anything or can an entry point be refused for lack of a grant.
const std = @import("std");
const language = @import("mylang");

/// Most directory grants one command line may carry.
pub const max_directories = 8;
const clock_flag = "--allow-clock";
const random_flag = "--allow-random";
const environment_flag = "--allow-env";
const host_flag = "--allow-host";
/// The flag that turns the default grant of every capability into a denial.
pub const restrict_flag = "--restrict";
/// One requested directory grant, borrowed from argv for the process lifetime.
pub const Directory = struct { path: []const u8, writable: bool };

/// Parsed authority options. Without `--restrict` every capability is granted
/// and the `--allow-*` flags narrow nothing; `--allow-random=SEED` still pins the
/// entropy seed, because it selects a stream rather than withholding one.
pub const Config = struct {
    directories: [max_directories]Directory = @splat(.{ .path = "", .writable = false }),
    count: usize = 0,
    /// Absent for no grant, otherwise a comma-separated allowlist; empty means every name.
    environment: ?[]const u8 = null,
    /// Absent for no grant, otherwise an optional reproducible seed.
    entropy: ??u64 = null,
    clock: bool = false,
    /// Grant to make a foreign call under `--restrict`.
    host: bool = false,
    restricted: bool = false,

    /// Consume one recognized authority option, rejecting duplicates and empty paths.
    pub fn parse(self: *Config, argument: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, argument, restrict_flag)) {
            if (self.restricted) return error.Usage;
            self.restricted = true;
            return true;
        }
        inline for (.{ "--allow-read=", "--allow-write=" }, .{ false, true }) |prefix, writes| {
            if (std.mem.startsWith(u8, argument, prefix)) return self.directory(argument[prefix.len..], writes);
        }
        if (std.mem.eql(u8, argument, clock_flag)) {
            if (self.clock) return error.Usage;
            self.clock = true;
            return true;
        }
        if (std.mem.eql(u8, argument, host_flag)) {
            if (self.host) return error.Usage;
            self.host = true;
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
        const already = self.clock or self.host or self.entropy != null;
        if (already or self.environment != null or self.count != 0) return error.Usage;
        self.clock = true;
        self.host = true;
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
};

/// The flag that would grant one capability an entry point asked for.
pub fn flagFor(ty: language.values.Type) ?[]const u8 {
    return switch (ty) {
        .filesystem_cap => "--allow-read=DIR",
        .network_cap => "--allow-endpoint",
        .clock_cap => clock_flag,
        .random_cap => random_flag,
        .environment_cap => environment_flag,
        .host_cap => host_flag,
        else => null,
    };
}

/// Name the first entry parameter whose capability the command line did not
/// grant. Only `--restrict` can withhold one; the default grants them all.
pub fn ungranted(program: language.bytecode.Program, config: Config) ?[]const u8 {
    if (!config.restricted) return null;
    const entry = program.functions[@backingInt(program.main)];
    for (entry.scope.locals[0..entry.signature.parameter_count]) |parameter| {
        const granted = switch (parameter.ty) {
            .filesystem_cap => config.count != 0,
            .clock_cap => config.clock,
            .random_cap => config.entropy != null,
            .environment_cap => config.environment != null,
            .host_cap => config.host,
            else => true,
        };
        if (!granted) return flagFor(parameter.ty);
    }
    return null;
}
