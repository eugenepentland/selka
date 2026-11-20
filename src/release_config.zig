//! Strict, owned configuration for checked project documentation.
const std = @import("std");
const product = @import("product.zig");

/// Project-relative release paths and entry selection; absent keys keep defaults.
pub const Options = struct {
    entries: []const []const u8 = &.{},
    exclude: []const []const u8 = &.{},
    overview: []const u8 = "OVERVIEW.md",
    decisions: []const u8 = "decisions",
    baseline: []const u8 = "release/baseline.txt",
    changes: []const u8 = "changes",
};

/// Invalid release configuration, including duplicate and unknown fields.
pub const Error = error{ InvalidRelease, DuplicateField, UnknownField, OutOfMemory };

/// Owned parse whose arena retains all configuration strings.
pub const Parsed = std.json.Parsed(Projection);

/// Extract only the release object, leaving unrelated configuration to its owner.
pub const Projection = struct {
    options: ?Options = null,

    /// Read a complete configuration, rejecting duplicate or malformed release keys.
    pub fn jsonParse(allocator: std.mem.Allocator, input: anytype, options: std.json.ParseOptions) !Projection {
        if (try input.next() != .object_begin) return error.UnexpectedToken;
        var result: Projection = .{};
        while (true) {
            const token = try input.nextAlloc(allocator, .alloc_always);
            const key = switch (token) {
                .object_end => return result,
                .allocated_string => |value| value,
                .string => |value| value,
                else => return error.UnexpectedToken,
            };
            if (std.mem.eql(u8, key, "release")) {
                if (result.options != null) return error.DuplicateField;
                result.options = try std.json.innerParse(Options, allocator, input, options);
            } else {
                try input.skipValue();
            }
        }
    }
};

/// Parse release settings from complete config bytes; returned strings are owned.
pub fn parseConfig(allocator: std.mem.Allocator, bytes: []const u8) Error!Parsed {
    const parsed = std.json.parseFromSlice(Projection, allocator, bytes, .{ .allocate = .alloc_always }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.UnknownField => return error.UnknownField,
        error.DuplicateField => return error.DuplicateField,
        else => return error.InvalidRelease,
    };
    errdefer parsed.deinit();
    if (parsed.value.options) |options| try validate(options);
    return parsed;
}

fn validate(options: Options) Error!void {
    for (options.entries) |path| {
        if (!relativePath(path) or !product.isSource(path)) return error.InvalidRelease;
    }
    for (options.exclude) |path| if (!relativePath(path)) return error.InvalidRelease;
    for ([_][]const u8{ options.overview, options.decisions, options.baseline, options.changes }) |path| {
        if (!relativePath(path) or std.mem.endsWith(u8, path, "/")) return error.InvalidRelease;
    }
}

/// Whether a configured path stays within its project and names a relative entry.
pub fn relativePath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path) or std.mem.indexOfScalar(u8, path, 0) != null) return false;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (std.mem.eql(u8, component, "..") or std.mem.eql(u8, component, ".")) return false;
    }
    return true;
}
