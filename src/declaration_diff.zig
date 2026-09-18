//! Map a checked declaration's merged source span back to its own module file
//! and original line range, and intersect that range with a working-tree diff.
//!
//! The commit-time lint rule and `mylang test --affected` both judge a diff
//! against the current declarations, so both read the mapping from here instead
//! of keeping their own copy.
const std = @import("std");
const interfaces = @import("interfaces.zig");
const ref_diff = @import("ref_diff.zig");
const source = @import("source.zig");

/// One declaration's merged-source span mapped back to its declaring module
/// and the inclusive one-based line range it occupies in that module's source.
pub const DeclarationSite = struct { module: usize, first_line: usize, last_line: usize };

/// Map one merged-source span to the module that declares it and the line range
/// the declaration currently occupies there. Returns null for a span that does
/// not map back to a loaded module, which keeps an unknown location unchanged
/// rather than reported.
pub fn declarationSite(index: *interfaces.Index, src: source.Source, span: source.Span) ?DeclarationSite {
    const original = src.originalSpan(span) catch return null;
    const modules = index.project.modules.items;
    if (original.input >= modules.len) return null;
    const module = modules[original.input];
    const first = module.src.physicalLocation(original.span.start).line;
    const last_offset = if (original.span.end > original.span.start) original.span.end - 1 else original.span.start;
    const last = module.src.physicalLocation(last_offset).line;
    return .{ .module = original.input, .first_line = first, .last_line = last };
}

/// One module's diff evidence: the changed line ranges `git` reported and a
/// line shift from the checked source to the original file. The shift is zero
/// for every ordinary module; a test snapshot that prepends a module header to
/// a header-less entry shifts its declarations down by the prefix line count.
pub const ModuleDiff = struct { ranges: ?[]const ref_diff.LineRange = null, shift: isize = 0 };

/// One diff query: the reference, the checked project it is judged against, and
/// the per-module changed-line cache shared across every declaration consulted.
/// Each entry is filled lazily; a module `git` cannot diff contributes an empty
/// range set, so a missing repository leaves the caller quiet instead of
/// flagging everything. `git` is spawned once per module.
pub const Diff = struct {
    memory: std.mem.Allocator,
    io: std.Io,
    repo_root: []const u8,
    reference: []const u8,
    index: *interfaces.Index,
    src: source.Source,
    cache: []ModuleDiff,

    /// Whether one merged-source declaration intersects the working-tree
    /// changes since this query's reference.
    pub fn changed(self: Diff, span: source.Span) error{OutOfMemory}!bool {
        const site = declarationSite(self.index, self.src, span) orelse return false;
        const modules = self.index.project.modules.items;
        if (site.module >= self.cache.len) return false;
        const entry = &self.cache[site.module];
        if (entry.ranges == null) {
            entry.ranges = ref_diff.changedLines(self.memory, self.io, self.repo_root, self.reference, modules[site.module].src.path) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.GitFailed => &[_]ref_diff.LineRange{},
            };
        }
        const first = @as(isize, @intCast(site.first_line - 1)) + entry.shift;
        const last = @as(isize, @intCast(site.last_line - 1)) + entry.shift;
        if (last < 0) return false;
        return ref_diff.intersects(entry.ranges.?, @intCast(@max(first, 0)), @intCast(last));
    }
};
