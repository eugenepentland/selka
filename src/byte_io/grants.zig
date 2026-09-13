//! Explicit CLI authority; omitted grants never provision filesystem or network access.
const std = @import("std");
const language = @import("mylang");
const scoped = language.scoped_providers;

/// Arguments borrow argv bytes for the runner lifetime.
pub const Config = struct {
    directory: ?[]const u8 = null,
    writable: bool = false,
    endpoints: [16]scoped.Endpoint = undefined,
    count: usize = 0,
    /// Consume one recognized grant option; reject duplicate directories and malformed endpoints.
    pub fn parse(self: *Config, argument: []const u8) error{InvalidArguments}!bool {
        if (std.mem.startsWith(u8, argument, "--allow-dir=")) {
            const path = argument[12..];
            if (path.len == 0 or self.directory != null) return error.InvalidArguments;
            self.directory = path;
            return true;
        }
        if (std.mem.eql(u8, argument, "--allow-write")) {
            if (self.writable) return error.InvalidArguments;
            self.writable = true;
            return true;
        }
        if (std.mem.startsWith(u8, argument, "--allow-endpoint=")) {
            if (self.count == self.endpoints.len) return error.InvalidArguments;
            const name = argument[17..];
            const address = std.Io.net.IpAddress.parseLiteral(name) catch return error.InvalidArguments;
            if (address.getPort() == 0) return error.InvalidArguments;
            self.endpoints[self.count] = .{ .name = name, .address = address };
            self.count += 1;
            return true;
        }
        return false;
    }
};
/// Stable callback storage; deinitialize after the VM releases its resource stores.
pub const State = struct {
    context: scoped.Context,
    config: Config,
    roots: [1]scoped.Root = undefined,
    /// Open only the configured root directory. No guest file or endpoint is acquired here.
    pub fn init(self: *State, allocator: std.mem.Allocator, io: std.Io, config: Config) (std.Io.Dir.OpenError || error{InvalidArguments})!void {
        if (config.writable and config.directory == null) return error.InvalidArguments;
        self.* = .{ .context = .{ .allocator = allocator, .io = io }, .config = config };
        self.context.endpoints = self.config.endpoints[0..self.config.count];
        if (config.directory) |path| {
            self.roots[0] = .{ .dir = try std.Io.Dir.cwd().openDir(io, path, .{}), .writable = config.writable };
            self.context.roots = self.roots[0..1];
        }
    }
    /// Close resources before their borrowed directory grant.
    pub fn deinit(self: *State) void {
        self.context.deinit();
        for (self.context.roots) |root| root.dir.close(self.context.io);
    }
    /// Apply the CLI permission mask at capability provisioning as well as acquisition.
    pub fn options(self: *State) language.vm.Options {
        return .{
            .resources = .{
                .filesystem = if (self.context.roots.len != 0) self.context.filesystem() else null,
                .network = if (self.config.count != 0) self.context.network() else null,
                // Resource mask bits are read=1, write=2, complete=4.
                .filesystem_permissions = if (self.config.writable) 7 else 5,
            },
        };
    }
};
