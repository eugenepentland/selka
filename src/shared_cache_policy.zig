//! Where the optional shared compiler-artifact and native test-receipt stores
//! live. A configured location is explicit; an unset one resolves to a per-user
//! default only while `default_sharing` is on. Sharing is same user, same machine.
const std = @import("std");

/// The rollout switch: false keeps sharing opt-in. Flipping it makes an unset
/// variable select the per-user default directory for both stores.
pub const default_sharing = false;

/// The two shared stores and the variable that configures each.
pub const Tier = enum {
    compiler,
    tests,

    /// The environment variable that selects this store's root.
    pub fn variable(self: Tier) []const u8 {
        return switch (self) {
            .compiler => "MYLANG_COMPILER_SHARED_CACHE",
            .tests => "MYLANG_TEST_SHARED_CACHE",
        };
    }

    /// The directory under `$XDG_CACHE_HOME/mylang` or `~/.cache/mylang`.
    pub fn leaf(self: Tier) []const u8 {
        return switch (self) {
            .compiler => "compiler-artifacts",
            .tests => "native-tests",
        };
    }
};

/// Whether a flag or variable named the store or the default switch chose it.
/// An unusable explicit store is an error; an unusable default one only warns.
pub const Origin = enum { explicit, default };

/// A resolved shared store root and how it was chosen.
pub const Selection = struct { path: []const u8, origin: Origin };

/// Resolve with the build's switch; see `resolveWith`.
pub fn resolve(a: std.mem.Allocator, environment: *const std.process.Environ.Map, tier: Tier, requested: ?[]const u8) std.mem.Allocator.Error!?Selection {
    return resolveWith(a, environment, tier, requested, default_sharing);
}

/// A requested path (a flag) wins, then the tier's variable; either one names an
/// explicit store, and an empty value disables sharing. Only when both are absent
/// and `sharing` is on does the per-user default apply.
pub fn resolveWith(a: std.mem.Allocator, environment: *const std.process.Environ.Map, tier: Tier, requested: ?[]const u8, sharing: bool) std.mem.Allocator.Error!?Selection {
    if (requested orelse environment.get(tier.variable())) |path| {
        return if (path.len == 0) null else .{ .path = path, .origin = .explicit };
    }
    if (!sharing) return null;
    const path = try defaultPath(a, environment, tier) orelse return null;
    return .{ .path = path, .origin = .default };
}

/// `$XDG_CACHE_HOME/mylang/<leaf>` when that is absolute, else
/// `$HOME/.cache/mylang/<leaf>` when HOME is absolute, else null.
pub fn defaultPath(a: std.mem.Allocator, environment: *const std.process.Environ.Map, tier: Tier) std.mem.Allocator.Error!?[]const u8 {
    if (environment.get("XDG_CACHE_HOME")) |base| if (std.fs.path.isAbsolute(base)) {
        const path = try std.fs.path.join(a, &.{ base, "mylang", tier.leaf() });
        return path;
    };
    const home = environment.get("HOME") orelse return null;
    if (!std.fs.path.isAbsolute(home)) return null;
    const path = try std.fs.path.join(a, &.{ home, ".cache", "mylang", tier.leaf() });
    return path;
}

// spec: SHARED-STORE-4
test "shared store resolution keeps explicit stores and applies defaults only behind the switch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("HOME", "/home/user");
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .compiler, null, false));
    const compiler = (try resolveWith(a, &environment, .compiler, null, true)).?;
    try std.testing.expectEqualStrings("/home/user/.cache/mylang/compiler-artifacts", compiler.path);
    try std.testing.expectEqual(Origin.default, compiler.origin);
    try environment.put("XDG_CACHE_HOME", "/xdg");
    try std.testing.expectEqualStrings("/xdg/mylang/native-tests", (try resolveWith(a, &environment, .tests, null, true)).?.path);
    try environment.put("XDG_CACHE_HOME", "relative");
    try std.testing.expectEqualStrings("/home/user/.cache/mylang/native-tests", (try resolveWith(a, &environment, .tests, null, true)).?.path);
    try environment.put("MYLANG_COMPILER_SHARED_CACHE", "/configured");
    const configured = (try resolveWith(a, &environment, .compiler, null, false)).?;
    try std.testing.expectEqualStrings("/configured", configured.path);
    try std.testing.expectEqual(Origin.explicit, configured.origin);
    try std.testing.expectEqual(Origin.explicit, (try resolveWith(a, &environment, .compiler, null, true)).?.origin);
    try environment.put("MYLANG_COMPILER_SHARED_CACHE", "");
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .compiler, null, true));
    try std.testing.expectEqualStrings("/flag", (try resolveWith(a, &environment, .tests, "/flag", true)).?.path);
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .tests, "", true));
    _ = environment.swapRemove("HOME");
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .tests, null, true));
    try std.testing.expectEqual(@as(?Selection, null), try resolve(a, &environment, .compiler, null));
}
