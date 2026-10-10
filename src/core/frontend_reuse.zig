//! Reuse the shared front end's durable syntax, body and check-summary stores.
//! Builds need complete typed trees; validation-only checks may stand summaries
//! in for unchanged bodies. Both modes always validate fresh declarations.
const std = @import("std");
const language = @import("mylang");

/// Every production source, including core/runtime/property adapters, plus the
/// Zig version and compiler build mode participates in this generated identity.
pub const compiler_identity = @import("build_identity").compiler_identity;

/// Actual front-end work, available to checks and compiler profiling tools.
pub const Statistics = struct {
    checked: usize = 0,
    reused: usize = 0,
    summaries: usize = 0,
    syntax_hits: usize = 0,
    syntax_misses: usize = 0,
    stored: usize = 0,
    damaged: usize = 0,
};

/// Stores and borrowed request pointers for one stable-address front-end session.
pub const State = struct {
    semantic: language.semantic_cache.Cache,
    store: language.semantic_cache.Store,
    frontend: language.frontend_cache.Cache,
    request: language.semantic_summary.Request = .{ .body_policy = .concrete },
    contract: []const u8,
    identity: [32]u8,

    /// Open stores under the core cache root with a separate value-semantics
    /// contract. No persisted encoding changes; existing shared codecs are used.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, root: []const u8) error{OutOfMemory}!State {
        var contract = language.semantic_cache.Contract.default;
        contract.compiler_identity = compiler_identity;
        contract.flags = "core-value-semantics";
        const fingerprint = try contract.fingerprint(allocator);
        errdefer allocator.free(fingerprint);
        const body_root = try std.fs.path.join(allocator, &.{ root, "semantic" });
        errdefer allocator.free(body_root);
        const syntax_root = try std.fs.path.join(allocator, &.{ root, "frontend" });
        errdefer allocator.free(syntax_root);
        var identity: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(compiler_identity, &identity, .{});
        var store = language.semantic_cache.Store.init(allocator, io, body_root, contract, language.semantic_cache.mutation_contract_version);
        store.root.owned = true;
        var frontend = language.frontend_cache.Cache.init(allocator, io, syntax_root, "");
        frontend.root_owned = true;
        frontend.contract = contract;
        return .{
            .semantic = language.semantic_cache.Cache.initWithContract(allocator, 16 * 1024 * 1024, fingerprint),
            .store = store,
            .frontend = frontend,
            .contract = fingerprint,
            .identity = identity,
        };
    }

    /// Bind self-references only after the state reached its final address.
    pub fn bind(self: *State) void {
        self.semantic.context.persistent = &self.store;
        self.semantic.context.retain_summary_trees = true;
        self.frontend.identity = &self.identity;
    }

    /// Release retained bodies and owned store paths; durable entries stay.
    pub fn deinit(self: *State) void {
        self.semantic.deinit();
        self.frontend.finish();
        self.frontend.deinit();
        self.store.deinit();
        self.semantic.allocator.free(self.contract);
    }

    /// Attach summaries from this entry's last successful project check.
    pub fn begin(self: *State, project: *const language.project.Project, allocator: std.mem.Allocator) error{OutOfMemory}!void {
        self.frontend.fitProject(project.counts.bytes);
        fitBodyStore(&self.store.limits, project.counts.bytes);
        if (try self.frontend.lookupSummaries(project)) |bytes| {
            defer self.semantic.allocator.free(bytes);
            if (language.semantic_summary.decode(allocator, bytes)) |decoded| {
                const previous = try allocator.create(language.semantic_summary.Index);
                previous.* = decoded;
                self.request.previous = previous;
            }
        }
        self.semantic.context.summaries = &self.request;
    }

    /// Publish summaries only after the mandatory check succeeded.
    pub fn finish(self: *State, project: *const language.project.Project) error{OutOfMemory}!void {
        if (self.request.produced) |produced| {
            const bytes = try language.semantic_summary.encode(self.semantic.allocator, produced);
            defer self.semantic.allocator.free(bytes);
            try self.frontend.rememberSummaries(project, bytes);
        }
    }

    /// Counters come from cache lookup/check sites, never estimated reuse.
    pub fn statistics(self: *const State) Statistics {
        return .{
            .checked = self.semantic.statistics.checked,
            .reused = self.semantic.statistics.reused,
            .summaries = self.request.stood_in,
            .syntax_hits = self.frontend.statistics.syntax.hits,
            .syntax_misses = self.frontend.statistics.syntax.misses,
            .stored = self.store.statistics.stored,
            .damaged = self.store.statistics.damaged + self.frontend.statistics.damaged,
        };
    }
};

/// Typed trees are larger than source text. Fit durable retention to the loaded
/// project, with hard ceilings; this never changes the 16 MiB memory budget or
/// the single-body decoding bound. Eviction remains a correct cache miss.
pub fn fitBodyStore(limits: *@FieldType(language.semantic_cache.Store, "limits"), source_bytes: usize) void {
    limits.max_bytes = @min(@as(usize, 4) << 30, @max(limits.max_bytes, 64 *| source_bytes));
    limits.max_entries = @min(@as(usize, 1) << 20, @max(limits.max_entries, source_bytes));
}
