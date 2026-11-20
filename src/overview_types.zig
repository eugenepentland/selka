//! Stable overview-v1 facts: declarations only, with direct test edges.
const decisions = @import("release_decisions.zig");
const store = @import("overview_store.zig");

/// Counts of public function documentation.
pub const Functions = struct { total: usize = 0, with_examples: usize = 0, waived: usize = 0 };
/// Public interface edits since the latest baseline.
pub const ChangeCounts = struct { added: usize = 0, changed: usize = 0, removed: usize = 0, decisions: usize = 0 };
/// Project-wide counts; private function bodies contribute no facts.
pub const Counts = struct { modules: usize = 0, functions: Functions = .{}, types: usize = 0, tests: usize = 0, examples: usize = 0, holes: usize = 0, changes: ChangeCounts = .{} };
/// A capability parameter and its declared type.
pub const Parameter = struct { name: []const u8, type: []const u8 };
/// Declaration-level function facts, independent of successful body checking.
pub const Function = struct { writes: []const []const u8, authority: []const Parameter, tests: []const []const u8, fails: ?[]const u8, hole: bool, examples: usize, waiver: ?[]const u8 };
/// One public record or enum payload field, including its declared default.
pub const Field = struct { name: []const u8, type: []const u8, default: ?[]const u8 };
/// One enum case and its ordered payload fields.
pub const Case = struct { name: []const u8, fields: []const Field };
/// Extra declaration facts grouped without flattening unrelated kinds.
pub const Details = struct { contracts: []const []const u8 = &.{}, fields: []const Field = &.{}, cases: []const Case = &.{}, function: ?Function = null };
/// One published name, its exact interface block and human-authored docstring.
pub const Declaration = struct { name: []const u8, kind: []const u8, signature: []const u8, doc: []const u8, details: Details, decisions: []const usize };
/// One module in import-map order, with source-order public declarations.
pub const Module = struct { name: []const u8, path: []const u8, doc: []const u8, imports: []const []const u8, importers: []const []const u8, private_functions: usize, declarations: []const Declaration };
/// A tree occurrence; repeated modules are leaves pointing to their first visit.
pub const MapEntry = struct { name: []const u8, summary: []const u8, depth: usize, repeated: bool };
/// One changed public name and every pending explanation naming it.
pub const Change = struct { name: []const u8, kind: []const u8, decisions: []const usize };
/// A public capability type and sorted functions accepting it.
pub const Authority = struct { type: []const u8, functions: []const []const u8 };
/// Release metadata and pending changes shared by both output formats.
pub const Releases = struct { since: []const u8, changes: []const Change, decisions: []const decisions.Decision, history: []const store.Release, authority: []const Authority, overview_path: []const u8 = "OVERVIEW.md" };
/// The complete overview-v1 object; no host path, generation date or compiler id.
pub const Document = struct { version: []const u8 = "overview-v1", title: []const u8, summary: []const u8, counts: Counts, map: []const MapEntry, modules: []const Module, releases: Releases };
