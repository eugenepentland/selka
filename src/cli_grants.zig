//! Command-line authority. `mylang run` and `run-project` grant every capability
//! by default, the way an ordinary interpreter does. `--restrict` switches the
//! command to deny-by-default, and only then do the `--allow-*` flags narrow
//! anything or can an entry point be refused for lack of a grant.
const std = @import("std");

/// Most directory grants one command line may carry.
pub const max_directories = 8;
/// Most literal network-endpoint grants one command line may carry.
pub const max_endpoints = 8;
const clock_flag = "--allow-clock";
const random_flag = "--allow-random";
const environment_flag = "--allow-env";
const host_flag = "--allow-host";
const endpoint_prefix = "--allow-endpoint=";
/// The flag that turns the default grant of every capability into a denial.
pub const restrict_flag = "--restrict";
/// One requested directory grant, borrowed from argv for the process lifetime.
pub const Directory = struct { path: []const u8, writable: bool };

/// Boolean authority switches, grouped so the parsed `Config` stays narrow.
pub const Flags = struct {
    clock: bool = false,
    /// Grant to make a foreign call under `--restrict`.
    host: bool = false,
    restricted: bool = false,
    /// `--allow-all` granted every capability, including every literal endpoint.
    allow_all: bool = false,
};

/// Parsed authority options. Without `--restrict` every capability is granted
/// and the `--allow-*` flags narrow nothing; `--allow-random=SEED` still pins the
/// entropy seed, because it selects a stream rather than withholding one.
pub const Config = struct {
    directories: [max_directories]Directory = @splat(.{ .path = "", .writable = false }),
    count: usize = 0,
    /// Literal `IP:PORT` endpoints granted to the network provider, borrowed from
    /// argv for the process lifetime. Empty means no endpoint is reachable.
    endpoints: [max_endpoints][]const u8 = @splat(""),
    endpoint_count: usize = 0,
    /// Absent for no grant, otherwise a comma-separated allowlist; empty means every name.
    environment: ?[]const u8 = null,
    /// Absent for no grant, otherwise an optional reproducible seed.
    entropy: ??u64 = null,
    flags: Flags = .{},

    /// Consume one recognized authority option, rejecting duplicates and empty paths.
    pub fn parse(self: *Config, argument: []const u8) error{Usage}!bool {
        if (std.mem.eql(u8, argument, restrict_flag)) {
            if (self.flags.restricted) return error.Usage;
            self.flags.restricted = true;
            return true;
        }
        inline for (.{ "--allow-read=", "--allow-write=" }, .{ false, true }) |prefix, writes| {
            if (std.mem.startsWith(u8, argument, prefix)) return self.directory(argument[prefix.len..], writes);
        }
        if (std.mem.startsWith(u8, argument, endpoint_prefix)) return self.endpoint(argument[endpoint_prefix.len..]);
        if (std.mem.eql(u8, argument, clock_flag)) {
            if (self.flags.clock) return error.Usage;
            self.flags.clock = true;
            return true;
        }
        if (std.mem.eql(u8, argument, host_flag)) {
            if (self.flags.host) return error.Usage;
            self.flags.host = true;
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
        const already = self.flags.clock or self.flags.host or self.entropy != null;
        if (already or self.environment != null or self.count != 0 or self.endpoint_count != 0) return error.Usage;
        self.flags.allow_all = true;
        self.flags.clock = true;
        self.flags.host = true;
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
    /// Consume one literal `IP:PORT` endpoint grant, rejecting an empty, malformed
    /// or repeated value before the runtime ever sees it.
    fn endpoint(self: *Config, name: []const u8) error{Usage}!bool {
        if (name.len == 0 or self.endpoint_count == max_endpoints) return error.Usage;
        const address = std.Io.net.IpAddress.parseLiteral(name) catch return error.Usage;
        // The native provider dials IPv4 literals only, so reject anything else
        // here rather than forwarding a grant the runtime would refuse.
        if (address == .ip6 or address.getPort() == 0) return error.Usage;
        for (self.endpoints[0..self.endpoint_count]) |existing| {
            if (std.mem.eql(u8, existing, name)) return error.Usage;
        }
        self.endpoints[self.endpoint_count] = name;
        self.endpoint_count += 1;
        return true;
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

/// The flag that would grant one capability an entry point asked for. The
/// capability type is generic so this module stays independent of the checker.
pub fn flagFor(ty: anytype) ?[]const u8 {
    return switch (ty) {
        .filesystem_cap => "--allow-read=DIR",
        .network_cap => "--allow-endpoint=IP:PORT",
        .clock_cap => clock_flag,
        .random_cap => random_flag,
        .environment_cap => environment_flag,
        .host_cap => host_flag,
        else => null,
    };
}

/// Name the first entry parameter whose capability the command line did not
/// grant. Only `--restrict` can withhold one; the default grants them all.
pub fn ungranted(program: anytype, config: Config) ?[]const u8 {
    if (!config.flags.restricted) return null;
    const entry = program.functions[@backingInt(program.main)];
    for (entry.scope.locals[0..entry.signature.parameter_count]) |parameter| {
        const granted = switch (parameter.ty) {
            .filesystem_cap => config.count != 0,
            .network_cap => config.endpoint_count != 0 or config.flags.allow_all,
            .clock_cap => config.flags.clock,
            .random_cap => config.entropy != null,
            .environment_cap => config.environment != null,
            .host_cap => config.flags.host,
            else => true,
        };
        if (!granted) return flagFor(parameter.ty);
    }
    return null;
}

// spec: NETWORK-ENDPOINT-1
test "grant parsing accepts literal endpoints and rejects malformed or repeated ones" {
    var config: Config = .{};
    try std.testing.expect(try config.parse("--restrict"));
    try std.testing.expect(try config.parse("--allow-endpoint=127.0.0.1:8000"));
    try std.testing.expectEqual(@as(usize, 1), config.endpoint_count);
    try std.testing.expect(try config.parse("--allow-endpoint=127.0.0.1:8001"));
    try std.testing.expectEqual(@as(usize, 2), config.endpoint_count);
    try std.testing.expectError(error.Usage, config.parse("--allow-endpoint=127.0.0.1:8000"));
    try std.testing.expectError(error.Usage, config.parse("--allow-endpoint="));
    try std.testing.expectError(error.Usage, config.parse("--allow-endpoint=localhost:8000"));
    try std.testing.expectError(error.Usage, config.parse("--allow-endpoint=[::1]:8000"));
    try std.testing.expectError(error.Usage, config.parse("--allow-endpoint=127.0.0.1:0"));
}

// spec-case: NETWORK-ENDPOINT-1
test "an entry point requesting a Network names the endpoint grant that would satisfy it" {
    try std.testing.expectEqualStrings("--allow-endpoint=IP:PORT", flagFor(.network_cap).?);
    var empty: Config = .{ .flags = .{ .restricted = true } };
    try std.testing.expect(try empty.parse("--allow-all"));
    try std.testing.expect(empty.flags.allow_all);
}
