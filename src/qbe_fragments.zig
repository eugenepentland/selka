//! Reuse of emitted QBE units across builds, keyed by what each unit's text
//! depends on rather than by where it sits in the program.
//!
//! A function's unit is a pure function of its own lowered body, the interface
//! of every function it names (signature, parameter locals, policy), the
//! complete schema of every nominal type it can reach, a handful of
//! whole-program switches, and — for the second emission pass only — whether
//! each named function can allocate and which parameters it writes. `Keys`
//! hashes exactly those inputs, with every compilation-local ordinal (a record
//! index, a function id) replaced by the canonical name it stands for and every
//! source position left out, so an edit elsewhere in the project that shifts
//! ids or offsets leaves an unchanged function's key unchanged.
//!
//! `Store` keeps the answers: each emitted unit's text under the digest of that
//! text, and per build a pack mapping keys to the unit digest and the facts the
//! manifest carries beside the text. A hit therefore needs neither lowering to
//! QBE nor the text itself: the native build reads the text only when its own
//! object cache misses.
const std = @import("std");
const bytecode = @import("bytecode_model.zig");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;
const test_dependencies = @import("native_test_dependencies.zig");
const Sha = std.crypto.hash.sha2.Sha256;

/// SHA-256 of a unit's canonical emission inputs, or of its emitted text.
pub const Digest = [32]u8;

/// Bumped whenever the canonical encoding below or the pack layout changes, so
/// an older store can never answer a newer compiler's question. The compiler
/// identity already partitions the store; this guards the encoding itself.
pub const format_version = "mylang-qbe-fragments-v1";

/// Whole-program switches that reach every unit's text.
pub const Flags = struct {
    step_checks: bool,
    frame_checks: bool,
    checks: bool,
    /// Any function opens an arena scope (`qbe_arena.present`).
    arenas: bool,
    /// This function is the program's entry.
    entry: bool,
};

/// One memoized canonical digest and the ordinals it named, in first-mention order.
const Summary = struct { digest: Digest, functions: []const u32, records: []const u32 };
/// One record schema's own digest and the records its schema names.
const RecordFact = struct { digest: Digest, children: []const u32 };

/// Canonical bytes of checked values. Records and functions are written as
/// their names and collected; spans are skipped; everything else is written
/// structurally, so two values with the same meaning encode identically in any
/// compilation.
const Canon = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    bytes: std.ArrayList(u8) = .empty,
    functions: std.ArrayList(u32) = .empty,
    records: std.ArrayList(u32) = .empty,

    fn raw(self: *Canon, data: []const u8) error{OutOfMemory}!void {
        try self.bytes.appendSlice(self.allocator, data);
    }
    fn text(self: *Canon, data: []const u8) error{OutOfMemory}!void {
        try self.put(@as(u64, data.len));
        try self.raw(data);
    }
    fn put(self: *Canon, value: anytype) error{OutOfMemory}!void {
        const T = @TypeOf(value);
        if (T == typed.Type) return self.putType(value);
        if (T == typed.FunctionId) return self.putFunction(value);
        // A position never enters a unit's text; including one would make every
        // function after an edit look changed.
        if (T == Span) return;
        // Quality counters: read by diagnostics, never by lowering or emission.
        if (T == typed.LocalUsage) return;
        // `default_value` indexes the checked expression table, which shifts with
        // unrelated edits; construction is already explicit in the lowered body.
        if (T == typed.Field) {
            try self.text(value.name);
            return self.putType(value.ty);
        }
        switch (@typeInfo(T)) {
            .void => {},
            .bool => try self.raw(&.{@intFromBool(value)}),
            .int, .float => try self.raw(std.mem.asBytes(&value)),
            .@"enum" => {
                const Tag = @typeInfo(T).@"enum".tag_type;
                const tag: Tag = @backingInt(value);
                try self.raw(std.mem.asBytes(&tag));
            },
            .optional => if (value) |payload| {
                try self.raw(&.{1});
                try self.put(payload);
            } else try self.raw(&.{0}),
            .array => for (value) |item| try self.put(item),
            .pointer => |pointer| switch (pointer.size) {
                .slice => {
                    try self.put(@as(u64, value.len));
                    if (pointer.child == u8) try self.raw(value) else for (value) |item| try self.put(item);
                },
                .one => try self.put(value.*),
                else => @compileError("no canonical encoding for " ++ @typeName(T)),
            },
            .@"struct" => |shape| inline for (shape.field_names) |name| try self.put(@field(value, name)),
            .@"union" => |shape| {
                const tag = std.meta.activeTag(value);
                try self.put(tag);
                inline for (shape.field_names) |name| {
                    if (std.mem.eql(u8, name, @tagName(tag))) try self.put(@field(value, name));
                }
            },
            else => @compileError("no canonical encoding for " ++ @typeName(T)),
        }
    }
    fn putType(self: *Canon, ty: typed.Type) error{OutOfMemory}!void {
        if (!ty.isAggregate() or ty.recordIndex() >= self.program.records.len) {
            try self.raw(&.{0});
            return self.put(@as(u64, @backingInt(ty)));
        }
        try self.raw(&.{1});
        try self.text(self.program.records[ty.recordIndex()].name);
        try self.records.append(self.allocator, @intCast(ty.recordIndex()));
    }
    fn putFunction(self: *Canon, id: typed.FunctionId) error{OutOfMemory}!void {
        const index = @backingInt(id);
        if (index >= self.program.functions.len) return self.put(@as(u64, std.math.maxInt(u64)));
        try self.text(self.program.functions[index].name);
        try self.functions.append(self.allocator, @intCast(index));
    }
    fn finish(self: *Canon) error{OutOfMemory}!Summary {
        var digest: Digest = undefined;
        Sha.hash(self.bytes.items, &digest, .{});
        self.bytes.clearRetainingCapacity();
        const functions = try unique(self.allocator, self.functions.items);
        errdefer self.allocator.free(functions);
        return .{ .digest = digest, .functions = functions, .records = try unique(self.allocator, self.records.items) };
    }
    fn deinit(self: *Canon) void {
        self.bytes.deinit(self.allocator);
        self.functions.deinit(self.allocator);
        self.records.deinit(self.allocator);
    }
};

/// The distinct ordinals in first-mention order.
fn unique(allocator: std.mem.Allocator, items: []const u32) error{OutOfMemory}![]const u32 {
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(allocator);
    var out: std.ArrayList(u32) = .empty;
    for (items) |item| {
        if ((try seen.getOrPut(allocator, item)).found_existing) continue;
        try out.append(allocator, item);
    }
    return out.toOwnedSlice(allocator);
}

/// Per-build memo of canonical digests. Every allocation belongs to the
/// caller's arena and lives exactly as long as one emission.
pub const Keys = struct {
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    bodies: []?Summary,
    interfaces: []?Summary,
    records: []?RecordFact,
    /// Per-record visit stamps for one closure walk, and the current stamp.
    closure: struct { stamps: []u32, current: u32 = 0 },

    /// Prepare empty memo tables for one lowered program.
    pub fn init(allocator: std.mem.Allocator, program: bytecode.Program) error{OutOfMemory}!Keys {
        const bodies = try allocator.alloc(?Summary, program.functions.len);
        errdefer allocator.free(bodies);
        @memset(bodies, null);
        const interfaces = try allocator.alloc(?Summary, program.functions.len);
        errdefer allocator.free(interfaces);
        @memset(interfaces, null);
        const records = try allocator.alloc(?RecordFact, program.records.len);
        errdefer allocator.free(records);
        @memset(records, null);
        const stamps = try allocator.alloc(u32, program.records.len);
        @memset(stamps, 0);
        return .{ .allocator = allocator, .program = program, .bodies = bodies, .interfaces = interfaces, .records = records, .closure = .{ .stamps = stamps } };
    }
    /// Release the memo tables and every summary they hold.
    pub fn deinit(self: *Keys) void {
        for (self.bodies) |known| if (known) |summary| self.release(summary);
        for (self.interfaces) |known| if (known) |summary| self.release(summary);
        for (self.records) |known| if (known) |fact| self.allocator.free(fact.children);
        self.allocator.free(self.bodies);
        self.allocator.free(self.interfaces);
        self.allocator.free(self.records);
        self.allocator.free(self.closure.stamps);
        self.* = undefined;
    }
    fn release(self: *Keys, summary: Summary) void {
        self.allocator.free(summary.functions);
        self.allocator.free(summary.records);
    }

    /// The first-pass key of function `index`: everything its unit text reads
    /// except the callee allocation facts, which the second pass adds.
    pub fn local(self: *Keys, index: usize, flags: Flags) error{OutOfMemory}!Digest {
        const own = try self.body(index);
        var canon: Canon = .{ .allocator = self.allocator, .program = self.program };
        defer canon.deinit();
        try canon.text(format_version);
        try canon.put(flags);
        try canon.raw(&own.digest);
        var reached: std.ArrayList(u32) = .empty;
        defer reached.deinit(self.allocator);
        try reached.appendSlice(self.allocator, own.records);
        for (own.functions) |callee| {
            const face = try self.interface(callee);
            try canon.raw(&face.digest);
            try reached.appendSlice(self.allocator, face.records);
        }
        try self.schemas(&canon, reached.items);
        var digest: Digest = undefined;
        Sha.hash(canon.bytes.items, &digest, .{});
        return digest;
    }

    /// Every function `index` names — callees, function values and inline
    /// origins — in first-mention order, without repeats.
    pub fn callees(self: *Keys, index: usize) error{OutOfMemory}![]const u32 {
        return (try self.body(index)).functions;
    }

    /// A function's own lowered content: policy, signature, locals and body.
    fn body(self: *Keys, index: usize) error{OutOfMemory}!Summary {
        if (self.bodies[index]) |known| return known;
        const function = self.program.functions[index];
        var canon: Canon = .{ .allocator = self.allocator, .program = self.program };
        defer canon.deinit();
        try canon.text("body");
        try canon.text(function.name);
        try canon.put(function.policy);
        try canon.put(function.signature);
        try canon.put(function.scope.locals);
        try canon.put(function.scope.instructions);
        const summary = try canon.finish();
        self.bodies[index] = summary;
        return summary;
    }

    /// What a caller's unit may read about function `index`: its name (and so
    /// its symbol), policy, signature and parameter locals.
    fn interface(self: *Keys, index: usize) error{OutOfMemory}!Summary {
        if (self.interfaces[index]) |known| return known;
        const function = self.program.functions[index];
        var canon: Canon = .{ .allocator = self.allocator, .program = self.program };
        defer canon.deinit();
        try canon.text("interface");
        try canon.text(function.name);
        try canon.put(function.policy);
        try canon.put(function.signature);
        const count = @min(function.signature.parameter_count, function.scope.locals.len);
        try canon.put(function.scope.locals[0..count]);
        // The interface names functions only through codec or owner types; its
        // records are what a caller must also see.
        canon.functions.clearRetainingCapacity();
        const summary = try canon.finish();
        self.interfaces[index] = summary;
        return summary;
    }

    /// One record's own schema, naming (not expanding) the records it reaches.
    fn record(self: *Keys, index: u32) error{OutOfMemory}!RecordFact {
        if (self.records[index]) |known| return known;
        var canon: Canon = .{ .allocator = self.allocator, .program = self.program };
        defer canon.deinit();
        try canon.text("record");
        try canon.put(self.program.records[index]);
        const summary = try canon.finish();
        self.allocator.free(summary.functions);
        const fact: RecordFact = .{ .digest = summary.digest, .children = summary.records };
        self.records[index] = fact;
        return fact;
    }

    /// Append every record reachable from `roots`, ordered by name, with its
    /// schema digest: the complete type information any unit text can read.
    fn schemas(self: *Keys, canon: *Canon, roots: []const u32) error{OutOfMemory}!void {
        self.closure.current +%= 1;
        if (self.closure.current == 0) {
            @memset(self.closure.stamps, 0);
            self.closure.current = 1;
        }
        var queue: std.ArrayList(u32) = .empty;
        defer queue.deinit(self.allocator);
        for (roots) |root| try self.visit(&queue, root);
        var cursor: usize = 0;
        while (cursor < queue.items.len) : (cursor += 1) {
            const fact = try self.record(queue.items[cursor]);
            for (fact.children) |child| try self.visit(&queue, child);
        }
        const Order = struct {
            records: []const typed.Record,
            fn less(context: @This(), left: u32, right: u32) bool {
                return std.mem.lessThan(u8, context.records[left].name, context.records[right].name);
            }
        };
        std.mem.sort(u32, queue.items, Order{ .records = self.program.records }, Order.less);
        try canon.put(@as(u64, queue.items.len));
        for (queue.items) |index| {
            try canon.text(self.program.records[index].name);
            try canon.raw(&(try self.record(index)).digest);
        }
    }
    fn visit(self: *Keys, queue: *std.ArrayList(u32), index: u32) error{OutOfMemory}!void {
        if (index >= self.closure.stamps.len or self.closure.stamps[index] == self.closure.current) return;
        self.closure.stamps[index] = self.closure.current;
        try queue.append(self.allocator, index);
    }
};

/// Hash of the sorted names of every function some instruction takes as a
/// value. An indirect call's checked dependency facts list all of them, so a
/// unit that invokes a function value depends on this set.
pub fn functionValueTargets(allocator: std.mem.Allocator, program: bytecode.Program) error{OutOfMemory}!Digest {
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);
    for (program.functions) |function| for (function.scope.instructions) |instruction| switch (instruction.op) {
        .function_value => |value| if (@backingInt(value.function) < program.functions.len) try names.append(allocator, program.functions[@backingInt(value.function)].name),
        else => {},
    };
    std.mem.sort([]const u8, names.items, {}, lessText);
    var hash = Sha.init(.{});
    for (names.items) |name| frame(&hash, name);
    return hash.finalResult();
}
fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
fn frame(hash: *Sha, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// The second-pass key: the first-pass key plus, for every named function, the
/// two facts the second pass reads about it — whether it can allocate, and
/// which of its parameters its body writes — and, for a unit that invokes a
/// function value, the program's function-value target set.
pub const Final = struct {
    hash: Sha,
    /// Start from the first-pass key.
    pub fn init(local_key: Digest) Final {
        var hash = Sha.init(.{});
        hash.update("final");
        hash.update(&local_key);
        return .{ .hash = hash };
    }
    /// Add one named function's allocation fact and parameter-write facts.
    pub fn callee(self: *Final, pure: bool, writes: []const bool) void {
        self.hash.update(&.{@intFromBool(pure)});
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, writes.len, .little);
        self.hash.update(&length);
        for (writes) |flag| self.hash.update(&.{@intFromBool(flag)});
    }
    /// Add the function-value target set an indirect call depends on.
    pub fn targets(self: *Final, digest: Digest) void {
        self.hash.update(&digest);
    }
    /// The finished key.
    pub fn finish(self: *Final) Digest {
        return self.hash.finalResult();
    }
};

/// The lines of a unit's text the native build reads without compiling it:
/// the `dbgfile` line that marks a frame-map unit, and every `# ` marker line
/// (frozen literal definitions). Everything else only matters to QBE.
pub fn facts(allocator: std.mem.Allocator, il: []const u8) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |line| {
        const keep = std.mem.startsWith(u8, line, "dbgfile ") or std.mem.startsWith(u8, line, "# ");
        if (!keep) continue;
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

/// One reusable second-pass answer: the digest of the unit text, the facts the
/// build reads without that text, and the unit's checked dependency facts.
pub const Unit = struct {
    il: Digest,
    facts: []const u8,
    dependencies: test_dependencies.Metadata,
};

/// How one emission uses a store: always consult and fill it, and with `lean`
/// hand the build each unit's digest and stored path instead of its text.
pub const Reuse = struct { store: *Store, lean: bool = false };

/// Reuse counters observed at the emission site.
pub const Statistics = struct {
    /// First-pass allocation facts answered from the store / computed.
    first_hits: usize = 0,
    first_misses: usize = 0,
    /// Units answered from the store / emitted.
    hits: usize = 0,
    misses: usize = 0,
};

const Entry = union(enum) { first: bool, unit: Unit };
const pack_magic = "MYLFRAG1";
/// Old entries a pack keeps beyond the ones the latest build used, as a
/// multiple of those: enough to switch between a few configurations of one
/// project without re-emitting, bounded so the pack cannot grow forever.
const carry_factor = 3;

/// A persistent fragment store: unit texts named by their digest, plus one
/// pack of key → answer entries per entry point. Every failure to read or
/// write degrades to a miss or a skipped store; nothing here fails a build.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    /// `<root>/<identity tag>`: texts under `il/`, packs under `packs/`.
    directory: []const u8,
    pack: []const u8,
    /// Entries loaded from the pack, and the entries this build used or made.
    entries: std.AutoHashMapUnmanaged(Digest, Entry) = .empty,
    used: std.array_hash_map.Auto(Digest, Entry) = .empty,
    statistics: Statistics = .{},

    /// Open the store under `root` for one compiler `identity` and load the
    /// pack named by `label` (for example the entry path and build policy).
    /// The allocator should be an arena that outlives the emission.
    pub fn open(allocator: std.mem.Allocator, io: std.Io, root: []const u8, identity: []const u8, label: []const u8) error{OutOfMemory}!Store {
        var name = Sha.init(.{});
        frame(&name, label);
        const pack = std.fmt.bytesToHex(name.finalResult(), .lower);
        var store: Store = .{
            .allocator = allocator,
            .io = io,
            .directory = try namespace(allocator, root, identity),
            .pack = try allocator.dupe(u8, &pack),
        };
        store.load() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => store.entries.clearRetainingCapacity(),
        };
        return store;
    }
    /// Release the in-memory tables and names. Loaded answers borrow the pack
    /// bytes, which belong to the arena the store was opened with.
    pub fn deinit(self: *Store) void {
        self.entries.deinit(self.allocator);
        self.used.deinit(self.allocator);
        self.allocator.free(self.directory);
        self.allocator.free(self.pack);
        self.* = undefined;
    }

    /// The digest of every unit text this process emitted or reused.
    pub fn texts(self: *const Store, allocator: std.mem.Allocator) error{OutOfMemory}![]const Digest {
        var out: std.ArrayList(Digest) = .empty;
        for (self.used.values()) |entry| if (entry == .unit) try out.append(allocator, entry.unit.il);
        return out.toOwnedSlice(allocator);
    }

    /// An answer this process already made or used, else one from the pack.
    fn lookup(self: *const Store, key: Digest) ?Entry {
        return self.used.get(key) orelse self.entries.get(key);
    }
    /// The stored first-pass allocation fact for `key`, if any.
    pub fn first(self: *Store, key: Digest) error{OutOfMemory}!?bool {
        const entry = self.lookup(key) orelse {
            self.statistics.first_misses += 1;
            return null;
        };
        if (entry != .first) return null;
        self.statistics.first_hits += 1;
        try self.used.put(self.allocator, key, entry);
        return entry.first;
    }
    /// Remember a freshly computed first-pass allocation fact.
    pub fn rememberFirst(self: *Store, key: Digest, allocates: bool) error{OutOfMemory}!void {
        try self.used.put(self.allocator, key, .{ .first = allocates });
    }
    /// The stored unit answer for `key`, if any and if its text is still on disk.
    pub fn unit(self: *Store, key: Digest) error{OutOfMemory}!?Unit {
        const entry = self.lookup(key) orelse {
            self.statistics.misses += 1;
            return null;
        };
        if (entry != .unit or !self.present(entry.unit.il)) {
            self.statistics.misses += 1;
            return null;
        }
        self.statistics.hits += 1;
        try self.used.put(self.allocator, key, entry);
        return entry.unit;
    }
    /// Store a freshly emitted unit text (if not already stored) and remember
    /// its answer under `key`. Returns the text's digest.
    pub fn remember(self: *Store, key: Digest, il: []const u8, dependencies: test_dependencies.Metadata) error{OutOfMemory}!Unit {
        var digest: Digest = undefined;
        Sha.hash(il, &digest, .{});
        const answer: Unit = .{ .il = digest, .facts = try facts(self.allocator, il), .dependencies = dependencies };
        self.writeText(digest, il) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // An unwritable store still answers this build from memory; the
            // next build simply misses.
            else => return answer,
        };
        try self.used.put(self.allocator, key, .{ .unit = answer });
        return answer;
    }
    /// The absolute or root-relative path of a stored unit text.
    pub fn path(self: *const Store, digest: Digest) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.directory, "il", &std.fmt.bytesToHex(digest, .lower) });
    }
    /// Read one stored unit text back, verifying it against its digest.
    pub fn read(self: *Store, digest: Digest) error{ OutOfMemory, FragmentMissing }![]u8 {
        const file = try self.path(digest);
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, file, self.allocator, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.FragmentMissing,
        };
        var actual: Digest = undefined;
        Sha.hash(bytes, &actual, .{});
        if (!std.mem.eql(u8, &actual, &digest)) return error.FragmentMissing;
        return bytes;
    }
    /// Publish this build's pack: every entry it used or made, then older
    /// entries up to a bounded multiple of that. Failures are ignored.
    pub fn flush(self: *Store) void {
        self.writePack() catch return;
    }

    fn present(self: *Store, digest: Digest) bool {
        const file = self.path(digest) catch return false;
        std.Io.Dir.cwd().access(self.io, file, .{}) catch return false;
        return true;
    }
    fn writeText(self: *Store, digest: Digest, il: []const u8) !void {
        if (self.present(digest)) return;
        const file = try self.path(digest);
        try atomicWrite(self.io, file, il);
    }
    fn packPath(self: *const Store) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.directory, "packs", self.pack });
    }
    fn load(self: *Store) !void {
        const file = try self.packPath();
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, file, self.allocator, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return,
        };
        if (bytes.len < pack_magic.len + 32 or !std.mem.eql(u8, bytes[0..pack_magic.len], pack_magic)) return error.Damaged;
        const body_end = bytes.len - 32;
        var checksum: Digest = undefined;
        Sha.hash(bytes[0..body_end], &checksum, .{});
        if (!std.mem.eql(u8, &checksum, bytes[body_end..])) return error.Damaged;
        var reader: PackReader = .{ .bytes = bytes[0..body_end], .at = pack_magic.len };
        const count = try reader.int(u32);
        // Every entry is at least a key, a kind byte and one payload byte.
        if (count > body_end / 34) return error.Damaged;
        try self.entries.ensureTotalCapacity(self.allocator, count);
        for (0..count) |_| {
            const key = try reader.digest();
            const entry: Entry = switch (try reader.int(u8)) {
                0 => .{ .first = (try reader.int(u8)) != 0 },
                1 => .{ .unit = try reader.unitAnswer(self.allocator) },
                else => return error.Damaged,
            };
            self.entries.putAssumeCapacity(key, entry);
        }
    }
    fn writePack(self: *Store) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);
        const a = self.allocator;
        try out.appendSlice(a, pack_magic);
        const limit = self.used.count() * (carry_factor + 1);
        var carried: std.ArrayList(Digest) = .empty;
        defer carried.deinit(a);
        var iterator = self.entries.iterator();
        while (iterator.next()) |item| {
            if (self.used.count() + carried.items.len >= limit) break;
            if (self.used.contains(item.key_ptr.*)) continue;
            try carried.append(a, item.key_ptr.*);
        }
        try appendInt(a, &out, u32, @intCast(self.used.count() + carried.items.len));
        for (self.used.keys(), self.used.values()) |key, entry| try appendEntry(a, &out, key, entry);
        for (carried.items) |key| try appendEntry(a, &out, key, self.entries.get(key).?);
        var checksum: Digest = undefined;
        Sha.hash(out.items, &checksum, .{});
        try out.appendSlice(a, &checksum);
        try atomicWrite(self.io, try self.packPath(), out.items);
    }
};

/// `<root>/<tag>`, the directory one compiler identity's store lives in.
fn namespace(allocator: std.mem.Allocator, root: []const u8, identity: []const u8) error{OutOfMemory}![]const u8 {
    var hash = Sha.init(.{});
    frame(&hash, format_version);
    frame(&hash, identity);
    const tag = std.fmt.bytesToHex(hash.finalResult(), .lower);
    return std.fs.path.join(allocator, &.{ root, &tag });
}

/// Where a store lives: the fragment root and the compiler identity that
/// partitions it.
pub const Place = struct { root: []const u8, identity: []const u8 };

/// A whole lean emission remembered under the exact inputs that produced it
/// (`EMIT-REPLAY-1`): the checked project's warnings and its manifest, plus the
/// digest of every unit text the manifest names. An unchanged project replays
/// them without checking, lowering or emitting anything.
pub const Replay = struct {
    warnings: []const u8,
    manifest: []const u8,

    const magic = "MYLREPL1";

    /// The remembered emission for `key`, or null when absent, damaged, or
    /// when any unit text it names has left the store.
    pub fn load(allocator: std.mem.Allocator, io: std.Io, place: Place, key: Digest) error{OutOfMemory}!?Replay {
        const directory = try namespace(allocator, place.root, place.identity);
        const file = try replayPath(allocator, directory, key);
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, file, allocator, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        if (bytes.len < magic.len + 32 or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
        const body_end = bytes.len - 32;
        var checksum: Digest = undefined;
        Sha.hash(bytes[0..body_end], &checksum, .{});
        if (!std.mem.eql(u8, &checksum, bytes[body_end..])) return null;
        var reader: PackReader = .{ .bytes = bytes[0..body_end], .at = magic.len };
        const warnings = reader.take(std.math.cast(usize, reader.int(u64) catch return null) orelse return null) catch return null;
        const manifest = reader.take(std.math.cast(usize, reader.int(u64) catch return null) orelse return null) catch return null;
        const count = reader.int(u32) catch return null;
        for (0..count) |_| {
            const text = reader.digest() catch return null;
            const path = try std.fs.path.join(allocator, &.{ directory, "il", &std.fmt.bytesToHex(text, .lower) });
            std.Io.Dir.cwd().access(io, path, .{}) catch return null;
        }
        return .{ .warnings = warnings, .manifest = manifest };
    }

    /// Remember one successful lean emission. Best effort.
    pub fn remember(allocator: std.mem.Allocator, io: std.Io, place: Place, key: Digest, answer: Replay, units: []const Digest) void {
        rememberAt(allocator, io, place, key, answer, units) catch return;
    }
    fn rememberAt(allocator: std.mem.Allocator, io: std.Io, place: Place, key: Digest, answer: Replay, units: []const Digest) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(allocator);
        try out.appendSlice(allocator, magic);
        try appendInt(allocator, &out, u64, answer.warnings.len);
        try out.appendSlice(allocator, answer.warnings);
        try appendInt(allocator, &out, u64, answer.manifest.len);
        try out.appendSlice(allocator, answer.manifest);
        try appendInt(allocator, &out, u32, @intCast(units.len));
        for (units) |unit_digest| try out.appendSlice(allocator, &unit_digest);
        var checksum: Digest = undefined;
        Sha.hash(out.items, &checksum, .{});
        try out.appendSlice(allocator, &checksum);
        const directory = try namespace(allocator, place.root, place.identity);
        try atomicWrite(io, try replayPath(allocator, directory, key), out.items);
    }
    fn replayPath(allocator: std.mem.Allocator, directory: []const u8, key: Digest) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(allocator, &.{ directory, "replay", &std.fmt.bytesToHex(key, .lower) });
    }
};

fn appendInt(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime T: type, value: T) error{OutOfMemory}!void {
    var buffer: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &buffer, value, .little);
    try out.appendSlice(allocator, &buffer);
}
fn appendText(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) error{OutOfMemory}!void {
    try appendInt(allocator, out, u32, @intCast(text.len));
    try out.appendSlice(allocator, text);
}
fn appendEntry(allocator: std.mem.Allocator, out: *std.ArrayList(u8), key: Digest, entry: Entry) error{OutOfMemory}!void {
    try out.appendSlice(allocator, &key);
    switch (entry) {
        .first => |allocates| {
            try out.append(allocator, 0);
            try out.append(allocator, @intFromBool(allocates));
        },
        .unit => |answer| {
            try out.append(allocator, 1);
            try out.appendSlice(allocator, &answer.il);
            try appendText(allocator, out, answer.facts);
            const deps = answer.dependencies;
            try appendText(allocator, out, deps.implementation_hash);
            try appendInt(allocator, out, u32, @intCast(deps.dependencies.len));
            for (deps.dependencies) |dependency| {
                try appendText(allocator, out, dependency.symbol);
                try out.append(allocator, @intCast(@backingInt(dependency.kind)));
            }
            try out.append(allocator, @intFromBool(deps.cacheable));
            try out.append(allocator, @intFromBool(deps.pure));
            try appendInt(allocator, out, u32, @intCast(deps.reasons.len));
            for (deps.reasons) |reason| try appendText(allocator, out, reason);
        },
    }
}

const PackReader = struct {
    bytes: []const u8,
    at: usize,
    fn take(self: *PackReader, count: usize) error{Damaged}![]const u8 {
        if (count > self.bytes.len - self.at) return error.Damaged;
        const slice = self.bytes[self.at .. self.at + count];
        self.at += count;
        return slice;
    }
    fn int(self: *PackReader, comptime T: type) error{Damaged}!T {
        return std.mem.readInt(T, (try self.take(@sizeOf(T)))[0..@sizeOf(T)], .little);
    }
    fn digest(self: *PackReader) error{Damaged}!Digest {
        return (try self.take(32))[0..32].*;
    }
    fn text(self: *PackReader) error{Damaged}![]const u8 {
        return self.take(try self.int(u32));
    }
    fn unitAnswer(self: *PackReader, allocator: std.mem.Allocator) error{ Damaged, OutOfMemory }!Unit {
        const il = try self.digest();
        const unit_facts = try self.text();
        const implementation = try self.text();
        const dependencies = try allocator.alloc(test_dependencies.Dependency, try self.int(u32));
        for (dependencies) |*dependency| {
            const symbol = try self.text();
            const kind = try self.int(u8);
            if (kind >= std.meta.tags(test_dependencies.Kind).len) return error.Damaged;
            dependency.* = .{ .symbol = symbol, .kind = @fromBackingInt(@intCast(kind)) };
        }
        const cacheable = (try self.int(u8)) != 0;
        const pure = (try self.int(u8)) != 0;
        const reasons = try allocator.alloc([]const u8, try self.int(u32));
        for (reasons) |*reason| reason.* = try self.text();
        return .{ .il = il, .facts = unit_facts, .dependencies = .{ .implementation_hash = implementation, .dependencies = dependencies, .cacheable = cacheable, .pure = pure, .reasons = reasons } };
    }
};

/// Write `bytes` to `file` through a uniquely named sibling and a rename, so a
/// concurrent reader sees either the old file or the whole new one.
fn atomicWrite(io: std.Io, file: []const u8, bytes: []const u8) !void {
    const directory = std.fs.path.dirname(file) orelse ".";
    try std.Io.Dir.cwd().createDirPath(io, directory);
    var nonce: [8]u8 = undefined;
    std.Io.random(io, &nonce);
    var buffer: [std.fs.max_path_bytes + 32]u8 = undefined;
    const staging = try std.fmt.bufPrint(&buffer, "{s}.{s}.tmp", .{ file, std.fmt.bytesToHex(nonce, .lower) });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = staging, .data = bytes });
    std.Io.Dir.rename(.cwd(), staging, .cwd(), file, io) catch |err| {
        // The rename failure is what the caller hears about; a staging file
        // that cannot be removed is only litter.
        std.Io.Dir.cwd().deleteFile(io, staging) catch |cleanup| switch (cleanup) {
            error.FileNotFound => {},
            else => {},
        };
        return err;
    };
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "atomicWrite reports a refused rename and leaves no staging file behind" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    // A non-empty directory where the file should go refuses the rename.
    const target = try std.fs.path.join(std.testing.allocator, &.{ root, "unit" });
    defer std.testing.allocator.free(target);
    const inside = try std.fs.path.join(std.testing.allocator, &.{ target, "occupied" });
    defer std.testing.allocator.free(inside);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, inside);
    try std.testing.expectError(error.IsDir, atomicWrite(std.testing.io, target, "text"));
    var names = try std.Io.Dir.cwd().openDir(std.testing.io, root, .{ .iterate = true });
    defer names.close(std.testing.io);
    var iterator = names.iterate();
    try std.testing.expectEqualStrings("unit", (try iterator.next(std.testing.io)).?.name);
    try std.testing.expectEqual(@as(?std.Io.Dir.Entry, null), try iterator.next(std.testing.io));
}
