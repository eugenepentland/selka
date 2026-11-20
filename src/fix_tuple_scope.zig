//! Tuple migrations share a safety boundary whenever their user-source graphs
//! share a declaration file, including through another entry's graph.
const std = @import("std");

/// One entry's complete source closure and whether its check lacks tuple facts.
pub const Entry = struct { paths: []const []const u8, complete: bool, deferred: bool };

/// Why a certain tuple proposal cannot run in the current directory round.
pub const Reason = enum { incomplete, shared };

/// Connected user-source groups. Any incomplete graph preserves the original
/// directory-wide refusal; otherwise only groups missing facts are withheld.
pub const Groups = struct {
    parents: []usize,
    deferred: []bool,
    complete: bool = true,

    /// Connect entries sharing user sources, then propagate missing tuple facts
    /// to every entry of each connected group.
    pub fn init(allocator: std.mem.Allocator, entries: []const Entry) error{OutOfMemory}!Groups {
        const parents = try allocator.alloc(usize, entries.len);
        errdefer allocator.free(parents);
        const deferred = try allocator.alloc(bool, entries.len);
        errdefer allocator.free(deferred);
        var groups: Groups = .{
            .parents = parents,
            .deferred = deferred,
        };
        @memset(groups.deferred, false);
        for (groups.parents, 0..) |*parent, index| parent.* = index;
        var paths: std.StringHashMapUnmanaged(usize) = .empty;
        defer paths.deinit(allocator);
        for (entries, 0..) |entry, index| {
            groups.complete = groups.complete and entry.complete;
            for (entry.paths) |path| {
                const previous = try paths.getOrPut(allocator, path);
                if (previous.found_existing) {
                    groups.parents[groups.root(index)] = groups.root(previous.value_ptr.*);
                } else previous.value_ptr.* = index;
            }
        }
        for (entries, 0..) |entry, index| if (entry.deferred) {
            groups.deferred[groups.root(index)] = true;
        };
        return groups;
    }

    /// Return this entry's withholding reason, or null when its group is ready.
    pub fn reason(self: Groups, index: usize) ?Reason {
        if (!self.complete) return .incomplete;
        return if (self.deferred[self.root(index)]) .shared else null;
    }

    fn root(self: Groups, index: usize) usize {
        var current = index;
        while (self.parents[current] != current) current = self.parents[current];
        return current;
    }
};
