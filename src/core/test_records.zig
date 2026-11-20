//! The test runner's planning records on the engine (spec §17.7, step G4e): a function's canonical facts and the chunks of callee
//! identities they point to (`test-facts`), and an entry's logical call graph with its chunks (`test-graph`). They were the stage
//! store's six test-runner scopes; the store now holds only the lowering and optimizer scopes.
//!
//! A record is addressed by the 32-byte key the runner computes (`stage_store.Store.key`, which carries the test-runner stage's
//! identity), is immutable except the graph's head (a newer generation replaces it), and is valid for as long as it exists: the
//! runner checks a chunk against the digest of its bytes and a fact against the function it describes when it loads them. A process
//! with no engine (`SELKA_ENGINE_SHADOW=0`, or one that could not start) records nothing and finds nothing, which only loses reuse.
//!
//! This file is a leaf: the facts and the graph are in the test-runner stage, whose identity must not move with the engine or the
//! emitter, so they reach the engine only through the `Vtable` the runner passes them (`test_runner_engine.planning`).
const std = @import("std");
const language = @import("selka");
const codec = language.persist_codec;
const stage = @import("stage_store.zig");

/// The records the runner keeps, one kind each: a function's facts and their chunks, and an entry's graph.
pub const Which = enum { facts, graph };

/// What the engine does for the runner, over an opaque context so that this file names none of the engine's code.
pub const Vtable = struct {
    /// The bytes recorded under `key`, in memory owned by `a`, or null.
    load: *const fn (context: *anyopaque, a: std.mem.Allocator, which: Which, key: *const [32]u8) ?[]const u8,
    /// Record `bytes` under `key`; `replace` makes them the record even when one is there. True when a record exists afterwards.
    save: *const fn (context: *anyopaque, which: Which, key: *const [32]u8, bytes: []const u8, replace: bool) bool,
};

/// Where one record goes: its kind, its key, and whether it replaces a record already there.
pub const Address = struct { which: Which, key: *const [32]u8, replace: bool = false };

/// The records of the engine a process attached, or none.
pub const Records = struct {
    context: ?*anyopaque = null,
    vtable: ?*const Vtable = null,

    /// No records: every load misses and every save is dropped.
    pub const none: Records = .{};

    /// The bytes recorded under `key`, in memory owned by `a`, or null.
    pub fn load(self: Records, a: std.mem.Allocator, which: Which, key: *const [32]u8) ?[]const u8 {
        const table = self.vtable orelse return null;
        return table.load(self.context.?, a, which, key);
    }

    /// Record `bytes` under `key`; `replace` makes them the record even when one is there. True when a record exists afterwards.
    pub fn save(self: Records, which: Which, key: *const [32]u8, bytes: []const u8, replace: bool) bool {
        const table = self.vtable orelse return false;
        return table.save(self.context.?, which, key, bytes, replace);
    }

    // twin-drift-ok: the same decode as stage_store.Store.loadValue, over bytes the engine holds instead of the stage store.
    /// The value of type `T` recorded under `key`, decoded into `arena`, or null when none is recorded or it does not decode.
    pub fn loadValue(self: Records, arena: std.mem.Allocator, scratch: std.mem.Allocator, which: Which, key: *const [32]u8, comptime T: type) error{OutOfMemory}!?T {
        const bytes = self.load(scratch, which, key) orelse return null;
        defer scratch.free(bytes);
        var reader = codec.Reader.init(arena, bytes);
        const value = reader.read(T) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        if (!reader.done()) return null;
        return value;
    }

    /// Encode `value` and record it at `address`.
    pub fn storeValue(self: Records, scratch: std.mem.Allocator, address: Address, comptime T: type, value: T) error{OutOfMemory}!void {
        var arena = std.heap.ArenaAllocator.init(scratch);
        defer arena.deinit();
        var writer = codec.Writer.init(arena.allocator());
        try writer.write(T, value);
        _ = self.save(address.which, address.key, writer.bytes.items, address.replace);
    }
};

/// Where the runner's planning records are addressed and where they are recorded: the store derives the keys (they carry the
/// test-runner stage's identity), the engine holds the records.
pub const Ledger = struct { store: *const stage.Store, records: Records };
