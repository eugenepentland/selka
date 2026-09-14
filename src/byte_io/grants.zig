//! Explicit CLI authority; omitted grants never provision filesystem or network access.
const std = @import("std");

/// Arguments borrow argv bytes for the runner lifetime.
pub const Config = struct {
    directory: ?[]const u8 = null,
    writable: bool = false,
    endpoints: [16][]const u8 = undefined,
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
            if (std.mem.indexOfScalar(u8, name, ',') != null) return error.InvalidArguments;
            self.endpoints[self.count] = name;
            self.count += 1;
            return true;
        }
        return false;
    }
    /// Describe this authority to the trusted provider linked into the guest.
    /// A grant the command line never asked for leaves no variable behind, so
    /// the provider supplies no capability at all rather than an empty one.
    pub fn install(self: Config, allocator: std.mem.Allocator, environment: *std.process.Environ.Map) std.mem.Allocator.Error!void {
        if (self.directory) |path| try environment.put("MYLANG_BYTE_IO_DIR", path);
        if (self.writable) try environment.put("MYLANG_BYTE_IO_WRITABLE", "1");
        if (self.count == 0) return;
        const names = try std.mem.join(allocator, ",", self.endpoints[0..self.count]);
        try environment.put("MYLANG_BYTE_IO_ENDPOINTS", names);
    }
};
