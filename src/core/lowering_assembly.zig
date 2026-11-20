//! The assembly record of a lowering (part 2, G3g step 2): the program tables a lowering ended with, kept so that the next build
//! assembles them again instead of replaying every function.
//!
//! Lowering numbers three program-wide tables in first-use order (functions, compound types and strings; `op_log.zig`), so the
//! tables a build ends with depend on every function it lowered, in the order it found them. A warm edit build used to restore each
//! function from its stored artifact to get them back: one stored header read, one replay of its type operations and one execution of
//! its requests per function, 94-121 ms at 99k and 450-610 at 400k, to learn that nothing had changed. This record is the end state of
//! such a build (the tables, and for each lowered function the key its artifact is stored under, the digest of its effects on the
//! tables, and where its strings and callees sit), written when every function was restored from a header.
//!
//! The next build keys every function as before and compares. A function whose key is the record's is as it was. A function whose key
//! moved is lowered alone (`build.Standalone`, or read back from its stored header when the store holds it) and its effects digest
//! (`lowering_cache.effectsDigest`) compared with the record's: if they agree the edit left the tables as they were (a body that
//! calls what it called, makes the types it made and appends the strings it appended), so the record's tables are the tables a
//! full replay would end with, whatever the function now does. A disagreement, a function the record does not know, a function whose
//! finish would declare a helper, or anything missing sends the build back to the replay, which is the oracle: this file never
//! decides alone what a build must contain, it only declines to redo what an unchanged table already says.
//!
//! The record lives in `<cache>/lowering-assembly-v1/<key>`, one file per entry and mode that the last writer replaces whole. A damaged
//! or foreign file is a miss. It is written in two halves, the function table (`Head`) and then the compounds, strings and nominal
//! digests (`Tail`, most of the bytes): a build that declines the record has needed only the head, and decodes the tail only when it
//! assembles. The keys the attempt made are handed to the replay that follows a declined one (`lowering_cache.Handoff`).
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const codec = language.persist_codec;
const ir = @import("ir.zig");
const stage = @import("stage_store.zig");
const lowering = @import("lowering_cache.zig");
const demand_sources = @import("demand_sources.zig");

/// The directory of the records, under the work directory.
pub const directory = "lowering-assembly-v1";

/// What a record starts with; a record of another layout is a miss.
const magic = "selka-lowering-assembly-v2";

/// Where a lowered function's strings and callees sit in the tables: the strings it appended (where its artifact counts them from, where
/// they are, how many), the module's type for each local compound id and its function for each request.
pub const Slot = struct { old_strings: u64, new_strings: u64, string_count: u64, types: []const ir.Type, functions: []const u32 };

/// A lowered source function: the key its artifact is stored under, the digest of its effects on the tables, whether finishing its body
/// declares no helper, the largest source position it holds with the files they are in, where it sits, and whether it defines functions.
pub const Placed = struct { key: stage.Digest, effects: stage.Digest, plain: ?bool, source_max: ?u32, proofs: []const demand_sources.Proof, slot: Slot, defines: bool };

/// One entry of the function table: its name and signature as the tables ended, and for a lowered source function what is known of it.
pub const Entry = struct { name: []const u8, signature: ir.Signature, declared: bool, placed: ?Placed };

/// The first half of a record: the entry and the function table with what is known of each lowered function. A build reads this to key the
/// functions and to settle the ones whose key moved, which is all it needs to decline.
pub const Head = struct { magic: []const u8, entry: u32, entries: []const Entry };

/// The second half of a record: the compound types, the strings and the nominal digests the tables ended with. Only an assembly that
/// goes ahead reads it (`Held.tail`), so a build that replays instead never decodes it.
pub const Tail = struct { compounds: []const ir.Compound, strings: []const []const u8, nominal: []const ?[32]u8 };

/// The tables a lowering ended with, and the functions that made them.
pub const Record = struct { head: Head, tail: Tail };

/// A record read from its file: its head decoded, and the reader positioned at its tail.
pub const Held = struct {
    head: Head,
    reader: codec.Reader,

    /// Decode the tail. Null when it is damaged or the file holds anything after it.
    pub fn tail(self: *Held) std.mem.Allocator.Error!?Tail {
        const found = self.reader.read(Tail) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        return if (self.reader.done()) found else null;
    }
};

/// The file of the record for `identity`, a digest of what names the build (the entry, the mode and the compiler).
pub fn pathOf(a: std.mem.Allocator, store: *const stage.Store, identity: stage.Digest) std.mem.Allocator.Error!?[]const u8 {
    const root = std.fs.path.dirname(store.storage.config.root) orelse return null;
    const path = try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ root, directory, std.fmt.bytesToHex(identity, .lower) });
    return path;
}

/// The head of the record in `path`, decoded into `a`, with the rest left for `Held.tail`; null when there is none or its head is damaged.
pub fn read(a: std.mem.Allocator, io: std.Io, path: []const u8) std.mem.Allocator.Error!?Held {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1 << 30)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    var reader = codec.Reader.init(a, bytes);
    const head = reader.read(Head) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (!std.mem.eql(u8, head.magic, magic)) return null;
    return .{ .head = head, .reader = reader };
}

/// Replace the record in `path` by `record`. Best effort: a record that cannot be written costs the next build its warmth.
pub fn write(a: std.mem.Allocator, io: std.Io, path: []const u8, record: Record) void {
    var writer = codec.Writer.init(a);
    writer.write(Head, record.head) catch return;
    writer.write(Tail, record.tail) catch return;
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, std.fs.path.dirname(path).?) catch return;
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const partial = std.fmt.allocPrint(a, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return;
    cwd.writeFile(io, .{ .sub_path = partial, .data = writer.bytes.items }) catch return;
    cwd.rename(partial, cwd, path, io) catch cwd.deleteFile(io, partial) catch return;
}

/// The record of the tables `module` ended with, or null when this lowering cannot be assembled again: a source function with no
/// handle (it was lowered in place, not restored from a header), a source function that is not internal (an extern declaration), or
/// a name that spells a position (a lambda). `ids` maps each checked function the lowering declared to its place in the table;
/// `lazy` holds what the restores noted. Call before the deferred keys are mixed with the source (`Deferred.prepare`).
pub fn capture(a: std.mem.Allocator, module: *const ir.Module, lazy: *const lowering.Deferred, ids: *const std.AutoHashMapUnmanaged(usize, u32)) std.mem.Allocator.Error!?Record {
    const count = module.functions.items.len;
    const declared = try a.alloc(bool, count);
    @memset(declared, false);
    var found = ids.iterator();
    while (found.next()) |each| declared[each.value_ptr.*] = true;
    const tables = &lazy.tables;
    const entries = try a.alloc(Entry, count);
    for (module.functions.items, entries, 0..) |function, *entry, index| {
        entry.* = .{ .name = function.name, .signature = function.signature, .declared = declared[index], .placed = null };
        if (!declared[index]) continue;
        if (function.signature.linkage != .internal or std.mem.startsWith(u8, function.name, "lambda@")) return null;
        if (index >= tables.handles.items.len or index >= tables.finish.items.len) return null;
        const finish = tables.finish.items[index];
        const handle = tables.handles.items[index] orelse finish.fresh orelse return null;
        const key = tables.keys.items[index] orelse return null;
        entry.placed = .{
            .key = key,
            .effects = finish.effects orelse return null,
            .plain = finish.plain,
            .source_max = tables.source_max.items[index],
            .proofs = tables.sources.items[index],
            .slot = .{ .old_strings = handle.old_strings, .new_strings = handle.new_strings, .string_count = handle.string_count, .types = handle.places.types, .functions = handle.places.functions },
            .defines = finish.defines,
        };
    }
    return .{
        .head = .{ .magic = magic, .entry = module.entry, .entries = entries },
        .tail = .{ .compounds = module.compounds.items, .strings = module.strings.items, .nominal = module.nominal },
    };
}

/// The record held against the program being built: the checked function of each entry, the key each lowered function has now, and the
/// entries whose key moved.
pub const Plan = struct {
    head: Head,
    ids: []const typed.FunctionId,
    keyed: []const lowering.Keyed,
    changed: []const u32,
};

/// Hold `record` against `program`: find the checked function of each lowered entry by its name and key it. Null when the record does
/// not describe this program's lowering: a function it names is gone or ambiguous, the entry is not its entry, or a function cannot
/// be keyed. `session` keys the functions; `context` is the lowering context it keys in. Each key made is also put in `handed` at its
/// function's place (it is as long as the program has functions), so a build that declines the record does not key them again.
pub fn plan(a: std.mem.Allocator, head: Head, session: *lowering.Session, context: lowering.Context, handed: []?lowering.Keyed) std.mem.Allocator.Error!?Plan {
    const identities = &session.declarations.names;
    const program = context.input.program;
    if (head.entry >= head.entries.len or !head.entries[head.entry].declared) return null;
    const ids = try a.alloc(typed.FunctionId, head.entries.len);
    const keyed = try a.alloc(lowering.Keyed, head.entries.len);
    var changed: std.ArrayList(u32) = .empty;
    for (head.entries, ids, keyed, 0..) |entry, *id, *key, index| {
        id.* = @fromBackingInt(0);
        key.* = .{ .key = @splat(0), .body = @splat(0), .refs = .{} };
        const placed = entry.placed orelse continue;
        const at = identities.find(lowering.normalizedName(entry.name)) orelse return null;
        id.* = @fromBackingInt(at);
        key.* = session.key(context, program.functions[at]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return null,
        };
        handed[at] = key.*;
        // A function whose positions are in other files holds only while those files read as they did: one that no longer does is
        // lowered again, as a replay would, even though its key is the same.
        if (!std.mem.eql(u8, &key.key, &placed.key) or !try session.sources.matches(placed.proofs)) try changed.append(a, @intCast(index));
    }
    if (@backingInt(ids[head.entry]) != @backingInt(program.main)) return null;
    return .{ .head = head, .ids = ids, .keyed = keyed, .changed = changed.items };
}

/// What a function whose key moved turned out to be, when its effects digest is compared with the record's.
pub const Update = struct { entry: u32, effects: stage.Digest, string_start: u64, string_count: u64, source_max: ?u32, proofs: []const demand_sources.Proof };

/// The function table, tables and strings of the program `plan` describes, as the lowering that made the record ended with them:
/// each source function declared with its name and signature, its body left to the deferred table (`lazy`), which learns where it
/// sits. `updates` are the functions whose key moved and whose effects did not: their handles carry the new key, and the strings
/// of their new artifacts count from where those were lowered. Nothing is lowered or restored here.
pub fn assemble(a: std.mem.Allocator, built: Plan, tail: Tail, program: typed.Program, lazy: *lowering.Deferred, updates: []const Update) std.mem.Allocator.Error!ir.Module {
    const head = built.head;
    var module: ir.Module = .{};
    try module.compounds.appendSlice(a, tail.compounds);
    try module.strings.appendSlice(a, tail.strings);
    try module.functions.ensureTotalCapacity(a, head.entries.len);
    module.entry = head.entry;
    module.nominal = tail.nominal;
    var moved: usize = 0;
    for (head.entries, built.ids, built.keyed, 0..) |entry, id, key, index| {
        var function: ir.Function = .{ .name = entry.name, .signature = entry.signature };
        const placed = entry.placed orelse {
            module.functions.appendAssumeCapacity(function);
            continue;
        };
        const checked = program.functions[@backingInt(id)];
        function.name = checked.name;
        function.span = @intCast(checked.declaration.start);
        module.functions.appendAssumeCapacity(function);
        var known: lowering.Known = .{ .source_max = placed.source_max, .proofs = placed.proofs, .plain = placed.plain, .effects = placed.effects, .defines = placed.defines };
        var handle: lowering.Handle = .{
            .key = placed.key,
            .start = checked.declaration.start,
            .old_strings = @intCast(placed.slot.old_strings),
            .new_strings = @intCast(placed.slot.new_strings),
            .string_count = @intCast(placed.slot.string_count),
            .places = .{ .types = placed.slot.types, .functions = placed.slot.functions },
        };
        if (moved < updates.len and updates[moved].entry == index) {
            const update = updates[moved];
            moved += 1;
            handle.key = key.key;
            handle.old_strings = @intCast(update.string_start);
            known = .{ .source_max = update.source_max, .proofs = update.proofs, .plain = true, .effects = update.effects, .defines = placed.defines };
        }
        try lazy.record(index, handle.key, handle, known);
    }
    return module;
}

test "a record round trips through the codec" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = [_]Entry{
        .{
            .name = "main",
            .signature = .{ .params = &.{}, .ret = .i64 },
            .declared = true,
            .placed = .{
                .key = @splat(1),
                .effects = @splat(2),
                .plain = true,
                .source_max = 7,
                .proofs = &.{},
                .slot = .{ .old_strings = 3, .new_strings = 0, .string_count = 1, .types = &.{}, .functions = &.{0} },
                .defines = false,
            },
        },
        .{ .name = "myl_core_print_i64", .signature = .{ .params = &.{.i64}, .ret = .void, .linkage = .runtime_c }, .declared = false, .placed = null },
    };
    const record: Record = .{
        .head = .{ .magic = magic, .entry = 0, .entries = &entries },
        .tail = .{ .compounds = &.{}, .strings = &.{"x"}, .nominal = &.{} },
    };
    var writer = codec.Writer.init(a);
    try writer.write(Head, record.head);
    try writer.write(Tail, record.tail);
    var reader = codec.Reader.init(a, writer.bytes.items);
    const head = try reader.read(Head);
    // The head is read alone; the tail is decoded from where the head ended, and only then is the file consumed.
    try std.testing.expect(!reader.done());
    var held: Held = .{ .head = head, .reader = reader };
    const tail = (try held.tail()).?;
    try std.testing.expectEqualDeep(record.head, head);
    try std.testing.expectEqualDeep(record.tail, tail);
    // A file that holds anything after the tail has no tail.
    try writer.raw("x");
    var extra = codec.Reader.init(a, writer.bytes.items);
    var damaged: Held = .{ .head = try extra.read(Head), .reader = extra };
    try std.testing.expectEqual(@as(?Tail, null), try damaged.tail());
}
