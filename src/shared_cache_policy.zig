//! Where the optional shared compiler-artifact, native test-receipt and stage
//! stores live. A configured location is explicit; an unset one resolves to a
//! per-user default only while `default_sharing` is on and the tier shares by
//! default (`Tier.sharedByDefault`). Sharing is same user, same machine.
const std = @import("std");
const product = @import("product.zig");

/// The rollout switch: false keeps sharing opt-in. Flipping it makes an unset
/// variable select the per-user default directory for both stores.
pub const default_sharing = true;

/// The three shared stores and the variable that configures each.
pub const Tier = enum {
    compiler,
    tests,
    stages,

    /// The environment variable that selects this store's root.
    pub fn variable(self: Tier) []const u8 {
        return switch (self) {
            .compiler => "SELKA_COMPILER_SHARED_CACHE",
            .tests => "SELKA_TEST_SHARED_CACHE",
            .stages => "SELKA_STAGE_SHARED_CACHE",
        };
    }

    /// Whether an unset variable selects this tier's per-user default. The stage store was opt-in until 3 November 2026: every
    /// save took one exclusive lock on its `sequence` file and rescanned the store while holding it, so every compiler on the machine
    /// queued behind one another (2026-10-28: a small build waited 39.9 s behind a gate's builds, against 0.03 s unshared). A save now
    /// refreshes the catalog before it takes the lock (`stage_pack.State.saveBatch`), the collector holds no lock a build waits for, and
    /// the store is bounded (`stage_collector.Policy`), so a fresh worktree starts from the records another worktree published.
    pub fn sharedByDefault(self: Tier) bool {
        _ = self;
        return true;
    }

    /// The directory under `$XDG_CACHE_HOME/selka` or `~/.cache/selka`.
    pub fn leaf(self: Tier) []const u8 {
        return switch (self) {
            .compiler => "compiler-artifacts",
            .tests => "native-tests",
            .stages => "stage-artifacts",
        };
    }
};

/// Whether a flag or variable named the store or the default switch chose it.
/// An unusable explicit store is an error; an unusable default one only warns.
pub const Origin = enum { explicit, default };

/// A resolved shared store root and how it was chosen.
pub const Selection = struct { path: []const u8, origin: Origin };

/// Resolve with the build's switch and the tier's own default; see `resolveWith`.
pub fn resolve(a: std.mem.Allocator, environment: *const std.process.Environ.Map, tier: Tier, requested: ?[]const u8) std.mem.Allocator.Error!?Selection {
    return resolveWith(a, environment, tier, requested, default_sharing and tier.sharedByDefault());
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

/// `$XDG_CACHE_HOME/selka/<leaf>` when that is absolute, else
/// `$HOME/.cache/selka/<leaf>` when HOME is absolute, else null.
pub fn defaultPath(a: std.mem.Allocator, environment: *const std.process.Environ.Map, tier: Tier) std.mem.Allocator.Error!?[]const u8 {
    if (environment.get("XDG_CACHE_HOME")) |base| if (std.fs.path.isAbsolute(base)) {
        const path = try std.fs.path.join(a, &.{ base, product.user_dir, tier.leaf() });
        return path;
    };
    const home = environment.get("HOME") orelse return null;
    if (!std.fs.path.isAbsolute(home)) return null;
    const path = try std.fs.path.join(a, &.{ home, ".cache", product.user_dir, tier.leaf() });
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
    try std.testing.expectEqualStrings("/home/user/.cache/selka/compiler-artifacts", compiler.path);
    try std.testing.expectEqual(Origin.default, compiler.origin);
    try environment.put("XDG_CACHE_HOME", "/xdg");
    try std.testing.expectEqualStrings("/xdg/selka/native-tests", (try resolveWith(a, &environment, .tests, null, true)).?.path);
    try environment.put("XDG_CACHE_HOME", "relative");
    try std.testing.expectEqualStrings("/home/user/.cache/selka/native-tests", (try resolveWith(a, &environment, .tests, null, true)).?.path);
    try environment.put("SELKA_COMPILER_SHARED_CACHE", "/configured");
    const configured = (try resolveWith(a, &environment, .compiler, null, false)).?;
    try std.testing.expectEqualStrings("/configured", configured.path);
    try std.testing.expectEqual(Origin.explicit, configured.origin);
    try std.testing.expectEqual(Origin.explicit, (try resolveWith(a, &environment, .compiler, null, true)).?.origin);
    try environment.put("SELKA_COMPILER_SHARED_CACHE", "");
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .compiler, null, true));
    try std.testing.expectEqualStrings("/flag", (try resolveWith(a, &environment, .tests, "/flag", true)).?.path);
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .tests, "", true));
    _ = environment.swapRemove("HOME");
    try std.testing.expectEqual(@as(?Selection, null), try resolveWith(a, &environment, .tests, null, true));
    try std.testing.expectEqual(@as(?Selection, null), try resolve(a, &environment, .compiler, null));
}

// spec: SHARED-STORE-4
test "the shared stage store shares by default like the others: an unset variable selects the per-user directory, an empty one disables it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("HOME", "/home/user");
    try std.testing.expect(Tier.stages.sharedByDefault());
    const unset = (try resolve(a, &environment, .stages, null)).?;
    try std.testing.expectEqualStrings("/home/user/.cache/selka/stage-artifacts", unset.path);
    try std.testing.expectEqual(Origin.default, unset.origin);
    try environment.put("XDG_CACHE_HOME", "/xdg");
    try std.testing.expectEqualStrings("/xdg/selka/stage-artifacts", (try resolve(a, &environment, .stages, null)).?.path);
    _ = environment.swapRemove("XDG_CACHE_HOME");
    try std.testing.expectEqual(default_sharing, (try resolve(a, &environment, .compiler, null)) != null);
    try std.testing.expectEqual(default_sharing, (try resolve(a, &environment, .tests, null)) != null);
    try environment.put("SELKA_STAGE_SHARED_CACHE", "/configured-stages");
    const stages = (try resolve(a, &environment, .stages, null)).?;
    try std.testing.expectEqualStrings("/configured-stages", stages.path);
    try std.testing.expectEqual(Origin.explicit, stages.origin);
    try environment.put("SELKA_STAGE_SHARED_CACHE", "");
    try std.testing.expectEqual(@as(?Selection, null), try resolve(a, &environment, .stages, null));
}
