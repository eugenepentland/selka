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
const codec = @import("persist_codec.zig");
/// Every digest here is BLAKE3. On the pinned toolchain, std's SHA-256 takes its
/// SHA-NI path, which mixes AVX2 message loads with legacy-SSE SHA instructions and
/// runs at about 11 MB/s on this project's build hosts (one microcode assist per
/// instruction); BLAKE3 hashes the same unit texts two orders of magnitude faster.
const Sha = std.crypto.hash.Blake3;

/// SHA-256 of a unit's canonical emission inputs, or of its emitted text.
pub const Digest = [32]u8;

/// Bumped whenever the canonical encoding below or the pack layout changes, so
/// an older store can never answer a newer compiler's question. The compiler
/// identity already partitions the store; this guards the encoding itself.
pub const format_version = "mylang-qbe-fragments-v2";

/// Whole-program switches that reach every unit's text.
pub const Flags = struct {
    step_checks: bool,
    frame_checks: bool,
    /// Any function opens an arena scope (`qbe_arena.present`).
    arenas: bool,
    /// This function is the program's entry.
    entry: bool,
    /// The copy-on-write code the unit carries (`COW-UNIQUE-1`). Folded into
    /// a key only when it is on, so every other key is unchanged.
    cow: @import("cow_plan.zig").Mode = .off,
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

/// The distinct ordinals in first-mention order. A function names a handful,
/// so a short list is deduplicated in place of building a hash set.
fn unique(allocator: std.mem.Allocator, items: []const u32) error{OutOfMemory}![]const u32 {
    if (items.len <= 32) {
        var out: std.ArrayList(u32) = try .initCapacity(allocator, items.len);
        for (items) |item| {
            if (std.mem.indexOfScalar(u32, out.items, item) == null) out.appendAssumeCapacity(item);
        }
        return out.toOwnedSlice(allocator);
    }
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
    /// Canonical-encoding buffers kept from one key to the next, so keying
    /// every function of a large program does not grow fresh buffers for
    /// each one (every function is keyed on every build).
    spare: Spare = .{},

    const Spare = struct { bytes: std.ArrayList(u8) = .empty, functions: std.ArrayList(u32) = .empty, records: std.ArrayList(u32) = .empty };

    /// A canonical encoder over the kept buffers, or fresh ones while a caller
    /// further up is still using them.
    fn encoder(self: *Keys) Canon {
        const taken = self.spare;
        self.spare = .{};
        return .{ .allocator = self.allocator, .program = self.program, .bytes = taken.bytes, .functions = taken.functions, .records = taken.records };
    }
    /// Keep the larger of an encoder's buffers and the kept ones, emptied.
    fn recycle(self: *Keys, used: *Canon) void {
        used.bytes.clearRetainingCapacity();
        used.functions.clearRetainingCapacity();
        used.records.clearRetainingCapacity();
        if (used.bytes.capacity < self.spare.bytes.capacity) return used.deinit();
        var old: Canon = .{ .allocator = self.allocator, .program = self.program, .bytes = self.spare.bytes, .functions = self.spare.functions, .records = self.spare.records };
        old.deinit();
        self.spare = .{ .bytes = used.bytes, .functions = used.functions, .records = used.records };
    }

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
        var kept = self.encoder();
        kept.deinit();
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
        var canon = self.encoder();
        defer self.recycle(&canon);
        try canon.text(format_version);
        try canon.put(.{ .step_checks = flags.step_checks, .frame_checks = flags.frame_checks, .arenas = flags.arenas, .entry = flags.entry });
        if (flags.cow != .off) try canon.text(@tagName(flags.cow));
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
        var canon = self.encoder();
        defer self.recycle(&canon);
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
        var canon = self.encoder();
        defer self.recycle(&canon);
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
        var canon = self.encoder();
        defer self.recycle(&canon);
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
        const closure = try self.closureOf(roots);
        defer self.allocator.free(closure);
        try canon.put(@as(u64, closure.len));
        for (closure) |index| {
            try canon.text(self.program.records[index].name);
            try canon.raw(&(try self.record(index)).digest);
        }
    }
    /// Every record reachable from `roots`, ordered by name.
    fn closureOf(self: *Keys, roots: []const u32) error{OutOfMemory}![]u32 {
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
        return self.allocator.dupe(u32, queue.items);
    }
    fn visit(self: *Keys, queue: *std.ArrayList(u32), index: u32) error{OutOfMemory}!void {
        if (index >= self.closure.stamps.len or self.closure.stamps[index] == self.closure.current) return;
        self.closure.stamps[index] = self.closure.current;
        try queue.append(self.allocator, index);
    }

    /// EMIT-STANDIN-1: every record whose schema the first-pass key of
    /// function `index` covers, ordered by name.
    pub fn reach(self: *Keys, index: usize) error{OutOfMemory}![]u32 {
        const own = try self.body(index);
        var roots: std.ArrayList(u32) = .empty;
        defer roots.deinit(self.allocator);
        try roots.appendSlice(self.allocator, own.records);
        for (own.functions) |callee| try roots.appendSlice(self.allocator, (try self.interface(callee)).records);
        return self.closureOf(roots.items);
    }
    /// The digest of function `index`'s own lowered content.
    pub fn bodyDigest(self: *Keys, index: usize) error{OutOfMemory}!Digest {
        return (try self.body(index)).digest;
    }
    /// The digest of what a caller's unit reads about function `index`.
    pub fn interfaceDigest(self: *Keys, index: usize) error{OutOfMemory}!Digest {
        return (try self.interface(index)).digest;
    }
    /// The digest of record `index`'s own schema.
    pub fn recordDigest(self: *Keys, index: u32) error{OutOfMemory}!Digest {
        return (try self.record(index)).digest;
    }
};

/// Hash of the sorted names of every function some instruction takes as a
/// value, one name per such instruction, in any order (they are sorted in
/// place). An indirect call's checked dependency facts list all of them, so a
/// unit that invokes a function value depends on this set.
pub fn targetsDigest(names: [][]const u8) Digest {
    std.mem.sort([]const u8, names, {}, lessText);
    var hash = Sha.init(.{});
    for (names) |name| frame(&hash, name);
    return digestOf(&hash);
}
fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
/// The digest a finished hasher holds.
fn digestOf(hash: *const Sha) Digest {
    var out: Digest = undefined;
    hash.final(&out);
    return out;
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
        return digestOf(&self.hash);
    }
};

/// The key of a unit's metadata (`EMIT-META-1`) — its per-instruction source
/// positions, assertion messages and inline frames. Its second-pass key covers
/// everything about the lowered function except source positions, and every
/// position is a place in a source some instruction's span falls in, found
/// only from that source's bytes; so the key adds the path and bytes of each
/// such source, in first-use order. An edit that moves lines in one module
/// recomputes the metadata of the units whose instructions come from it, and
/// no other.
pub const MetaKey = struct {
    hash: Sha,
    /// Start from the unit's second-pass key.
    pub fn init(final_key: Digest) MetaKey {
        var hash = Sha.init(.{});
        hash.update("unit-meta-v1");
        hash.update(&final_key);
        return .{ .hash = hash };
    }
    /// Add one source the unit's positions fall in, by `sourceDigest`.
    pub fn source(self: *MetaKey, digest: Digest) void {
        self.hash.update(&digest);
    }
    /// The finished key.
    pub fn finish(self: *MetaKey) Digest {
        return digestOf(&self.hash);
    }
};

/// The digest one source contributes to a metadata key: its path and bytes.
pub fn sourceDigest(path_text: []const u8, bytes: []const u8) Digest {
    var hash = Sha.init(.{});
    frame(&hash, path_text);
    frame(&hash, bytes);
    return digestOf(&hash);
}

/// The lines of a unit's text the native build reads without compiling it:
/// the `dbgfile` line that marks a frame-map unit, every `# ` marker line
/// (frozen literal definitions), and every top-level `data` definition line,
/// which keeps a unit out of a shared QBE batch. Everything else only matters
/// to QBE.
pub fn facts(allocator: std.mem.Allocator, il: []const u8) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |line| {
        const keep = std.mem.startsWith(u8, line, "dbgfile ") or std.mem.startsWith(u8, line, "# ") or definesData(line);
        if (!keep) continue;
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

/// Whether one line opens a top-level `data` definition: it starts with a
/// letter, and `data` is one of its words before any `function` or `type`.
fn definesData(line: []const u8) bool {
    if (line.len == 0 or !std.ascii.isAlphabetic(line[0])) return false;
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "data")) return true;
        if (std.mem.eql(u8, token, "function") or std.mem.eql(u8, token, "type")) return false;
    }
    return false;
}

/// One reusable second-pass answer: the digest of the unit text, the facts the
/// build reads without that text, and the unit's checked dependency facts.
pub const Unit = struct {
    il: Digest,
    facts: []const u8,
    dependencies: test_dependencies.Metadata,
};

/// How one emission uses a store: always consult and fill it, and with `lean`
/// hand the build each unit's stored text and stored metadata by digest
/// instead of the text and positions themselves (`EMIT-META-1`). An
/// `executable` emission is for the native build of a program, which reads no
/// export, schema, wire, codec or test-dependency facts, so it writes none.
pub const Reuse = struct { store: *Store, lean: bool = false, executable: bool = false, standins: ?*Standins = null };

/// EMIT-STANDIN-1: an executable's lean emission that lowers only the
/// functions it has to. A function whose source identity has a record and
/// whose unit read nothing that changed is left unlowered and its unit is
/// taken from the record; every other function is lowered and emitted, and
/// leaves a fresh record.
pub const Standins = struct {
    /// Per function: the record its unit is reused from while it stays
    /// unselected, or null.
    records: []?*const Record,
    /// Per function: the key its record is stored under, or null for a
    /// function whose unit is never reused this way.
    keys: []?Digest,
    /// Per function: lowered and emitted by this emission.
    selected: []bool,
    /// Per function: its lowered body before inlining (empty until selected).
    pre: []bytecode.Function,
    /// Lowers every selected function whose `pre` body is still empty.
    lower: Lowering,
    /// Whether `debug` lines are dropped while lowering.
    drop_debug: bool = false,
};

/// A way to lower more functions into `Standins.pre` during one emission.
pub const Lowering = struct {
    context: *anyopaque,
    run: *const fn (context: *anyopaque, standins: *Standins) error{ OutOfMemory, InternalError }!void,
};

/// Reuse counters observed at the emission site.
pub const Statistics = struct {
    /// First-pass allocation facts answered from the store / computed.
    first_hits: usize = 0,
    first_misses: usize = 0,
    /// Units answered from the store / emitted.
    hits: usize = 0,
    misses: usize = 0,
    /// Unit metadata (positions, messages, inline frames) answered from the
    /// store / computed from the source (`EMIT-META-1`).
    meta: Count = .{},
    /// Texts this process wrote to the store, and texts a sweep removed
    /// (`FRAGMENT-SWEEP-1`).
    texts: Traffic = .{},
    /// Functions an executable's emission lowered, and units it took from
    /// records without lowering their functions (`EMIT-STANDIN-1`).
    standin: Standin = .{},
};
/// How many functions one emission lowered and how many it stood in for.
pub const Standin = struct { lowered: usize = 0, reused: usize = 0 };
/// How many answers a store gave, and how many it did not have.
pub const Count = struct { hits: usize = 0, misses: usize = 0 };
/// Texts written to a store and texts swept out of it.
pub const Traffic = struct { written: usize = 0, swept: usize = 0 };
/// The file under a store's directory counting the texts written since its
/// last sweep, and the fewest such texts that make a sweep worth its listing.
const written_name = ".written";
const sweep_floor: usize = 4096;
/// The file whose lock leases a store (`FRAGMENT-SWEEP-1`).
const lease_name = ".lease";

/// Take this process's shared lease on the store at `directory`, or null when
/// the filesystem cannot lock (the store then never sweeps).
fn lease(allocator: std.mem.Allocator, io: std.Io, directory: []const u8) error{OutOfMemory}!?std.Io.File {
    std.Io.Dir.cwd().createDirPath(io, directory) catch return null;
    const path = try std.fs.path.join(allocator, &.{ directory, lease_name });
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false, .read = true }) catch return null;
    if (file.tryLock(io, .shared) catch false) return file;
    file.close(io);
    return null;
}

/// The store's text directory, created and opened once, so each presence
/// check names one entry of it rather than walking a whole path; null when it
/// cannot be opened (checks then use the full path).
fn textDirectory(allocator: std.mem.Allocator, io: std.Io, directory: []const u8) error{OutOfMemory}!?std.Io.Dir {
    const path = try std.fs.path.join(allocator, &.{ directory, "il" });
    std.Io.Dir.cwd().createDirPath(io, path) catch return null;
    return std.Io.Dir.cwd().openDir(io, path, .{}) catch null;
}

/// Add to `live` every text a pack's entries name.
fn packTexts(allocator: std.mem.Allocator, bytes: []const u8, live: *std.AutoHashMapUnmanaged(Digest, void)) error{ OutOfMemory, Damaged }!void {
    var entries: std.AutoHashMapUnmanaged(Digest, Entry) = .empty;
    try readPack(allocator, bytes, &entries);
    var values = entries.valueIterator();
    while (values.next()) |entry| switch (entry.*) {
        .unit => |answer| try live.put(allocator, answer.il, {}),
        .meta => |digest| try live.put(allocator, digest, {}),
        .record => |stored| {
            try live.put(allocator, stored.unit.il, {});
            try live.put(allocator, stored.meta, {});
        },
        .first => {},
    };
}

/// Add to `live` every text a remembered emission names.
fn replayTexts(allocator: std.mem.Allocator, bytes: []const u8, live: *std.AutoHashMapUnmanaged(Digest, void)) error{ OutOfMemory, Damaged }!void {
    if (bytes.len < Replay.magic.len + 64 or !std.mem.eql(u8, bytes[0..Replay.magic.len], Replay.magic)) return error.Damaged;
    var reader: PackReader = .{ .bytes = bytes[0 .. bytes.len - 32], .at = Replay.magic.len + 32 };
    _ = try reader.take(std.math.cast(usize, try reader.int(u64)) orelse return error.Damaged);
    _ = try reader.take(std.math.cast(usize, try reader.int(u64)) orelse return error.Damaged);
    for (0..try reader.int(u32)) |_| try live.put(allocator, try reader.digest(), {});
}

/// Read a pack's entries into `entries`, refusing a damaged one.
fn readPack(allocator: std.mem.Allocator, bytes: []const u8, entries: *std.AutoHashMapUnmanaged(Digest, Entry)) error{ OutOfMemory, Damaged }!void {
    if (bytes.len < pack_magic.len + 32 or !std.mem.eql(u8, bytes[0..pack_magic.len], pack_magic)) return error.Damaged;
    const body_end = bytes.len - 32;
    var checksum: Digest = undefined;
    Sha.hash(bytes[0..body_end], &checksum, .{});
    if (!std.mem.eql(u8, &checksum, bytes[body_end..])) return error.Damaged;
    var reader: PackReader = .{ .bytes = bytes[0..body_end], .at = pack_magic.len };
    const count = try reader.int(u32);
    // Every entry is at least a key, a kind byte and one payload byte.
    if (count > body_end / 34) return error.Damaged;
    try entries.ensureTotalCapacity(allocator, count);
    for (0..count) |_| {
        const key = try reader.digest();
        const entry: Entry = switch (try reader.int(u8)) {
            0 => .{ .first = (try reader.int(u8)) != 0 },
            1 => .{ .unit = try reader.unitAnswer(allocator) },
            2 => .{ .meta = try reader.digest() },
            3 => .{ .record = try reader.record(allocator) },
            else => return error.Damaged,
        };
        entries.putAssumeCapacity(key, entry);
    }
}

const Entry = union(enum) { first: bool, unit: Unit, meta: Digest, record: *const Record };
const pack_magic = "MYLFRAG3";

/// EMIT-STANDIN-1: what one function's last emission leaves for a build that
/// reuses its unit without lowering the function. It is stored under a key of
/// the function's source identity (its declaration key, dependency context
/// and region digest, which fix its checked body) and the lowering policy;
/// `snapshot` covers everything else the unit and its metadata read, and a
/// build reuses the record only while that is unchanged.
pub const Record = struct {
    name: []const u8,
    /// The unit's stored answer and the digest of its stored metadata record.
    unit: Unit,
    meta: Digest,
    /// Digest of what the unit read outside the function's own source.
    snapshot: Digest,
    /// What other functions' units and the program read about this one.
    facts: Facts,
    /// What this function's unit read about the rest of the program.
    reads: Reads,
};

/// The facts a caller's unit or a whole-program pass reads about a function
/// without its body: its inline key (zero unless the inliner may splice it,
/// otherwise the digest of the body a caller splices), whether its own text
/// allocates, the functions it calls after inlining, which parameters it
/// writes, the functions it takes as values, and three program-wide marks.
pub const Facts = struct {
    inline_key: Digest = @splat(0),
    allocates: bool = false,
    calls: []const []const u8 = &.{},
    writes: []const bool = &.{},
    values: []const []const u8 = &.{},
    marks: Marks = .{},
};

/// Whether a function invokes a function value, opens an arena, or needs the
/// text runtime.
pub const Marks = struct { invokes: bool = false, arena: bool = false, text: bool = false };

/// What a unit read about the rest of the program: the functions it names, the
/// records whose schema it reaches, and the sources its positions fall in.
pub const Reads = struct { names: []const []const u8 = &.{}, records: []const []const u8 = &.{}, sources: []const []const u8 = &.{} };

/// The key a function's record is stored under: its source identity and
/// whether its `debug` lines were lowered. The emission switches are part of
/// every record's snapshot instead.
pub fn recordKey(source_identity: Digest, drop_debug: bool) Digest {
    var hash = Sha.init(.{});
    hash.update("standin-record-v1");
    hash.update(&source_identity);
    hash.update(&.{@intFromBool(drop_debug)});
    // VALUE-SEMANTICS-1: value semantics changes every lowered body.
    if (@import("value_semantics.zig").enabled()) hash.update("value-semantics");
    return digestOf(&hash);
}
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
    /// `<root>/<identity tag>`: texts under `il/`, packs under `packs/`,
    /// replays under `replay/`.
    directory: []const u8,
    /// This build's pack name, and its shared lease on the store.
    pack: Pack,
    /// Entries loaded from the pack, and the entries this build used or made.
    entries: std.AutoHashMapUnmanaged(Digest, Entry) = .empty,
    used: std.array_hash_map.Auto(Digest, Entry) = .empty,
    statistics: Statistics = .{},

    /// The pack a store answers from, and the open `.lease` file whose shared
    /// lock this process holds while it may write texts (`FRAGMENT-SWEEP-1`).
    /// And the open text directory, whose entries are checked by name.
    const Pack = struct { name: []const u8, lease: ?std.Io.File = null, texts: ?std.Io.Dir = null };

    /// Open the store under `root` for one compiler `identity` and load the
    /// pack named by `label` (for example the entry path and build policy).
    /// The allocator should be an arena that outlives the emission. The store
    /// is leased for as long as it is open.
    pub fn open(allocator: std.mem.Allocator, io: std.Io, root: []const u8, identity: []const u8, label: []const u8) error{OutOfMemory}!Store {
        var name = Sha.init(.{});
        frame(&name, label);
        const pack = std.fmt.bytesToHex(digestOf(&name), .lower);
        const directory = try namespace(allocator, root, identity);
        var store: Store = .{
            .allocator = allocator,
            .io = io,
            .directory = directory,
            .pack = .{ .name = try allocator.dupe(u8, &pack), .lease = try lease(allocator, io, directory), .texts = try textDirectory(allocator, io, directory) },
        };
        store.load() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => store.entries.clearRetainingCapacity(),
        };
        return store;
    }
    /// Release the in-memory tables, names and lease. Loaded answers borrow the
    /// pack bytes, which belong to the arena the store was opened with.
    pub fn deinit(self: *Store) void {
        if (self.pack.lease) |file| file.close(self.io);
        if (self.pack.texts) |listing| listing.close(self.io);
        self.entries.deinit(self.allocator);
        self.used.deinit(self.allocator);
        self.allocator.free(self.directory);
        self.allocator.free(self.pack.name);
        self.* = undefined;
    }

    /// FRAGMENT-SWEEP-1: once the texts written since the last sweep outnumber
    /// the texts this build names (and at least `sweep_floor`), delete every
    /// text in the store that no pack and no replay names. A sweep runs only
    /// under the store's exclusive lease: every process that may write a text
    /// holds the shared lease from `open` until it exits, so a text another
    /// process wrote but has not named in a pack yet is never taken, and a text
    /// named by a flushed pack or a replay — every text a manifest hands the
    /// native build — is never unnamed. Best effort: nothing here fails a build.
    pub fn sweep(self: *Store) void {
        self.sweepAt() catch return;
    }
    fn sweepAt(self: *Store) !void {
        const counter = try std.fs.path.join(self.allocator, &.{ self.directory, written_name });
        const pending = self.readCount(counter) +| self.statistics.texts.written;
        const named = self.texts(self.allocator) catch return;
        if (pending <= @max(sweep_floor, named.len)) return self.writeCount(counter, pending);
        const file = self.pack.lease orelse return self.writeCount(counter, pending);
        if (!(file.tryLock(self.io, .exclusive) catch false)) {
            // A failed conversion may have dropped the shared lock; take it back.
            _ = file.tryLock(self.io, .shared) catch false;
            return self.writeCount(counter, pending);
        }
        defer _ = file.tryLock(self.io, .shared) catch false;
        var live: std.AutoHashMapUnmanaged(Digest, void) = .empty;
        try self.namedBy("packs", &live, packTexts);
        try self.namedBy("replay", &live, replayTexts);
        try self.deleteUnnamed(&live);
        self.writeCount(counter, 0);
    }
    /// Add to `live` every text each file of `subdirectory` names, as `names` reads it.
    fn namedBy(self: *Store, subdirectory: []const u8, live: *std.AutoHashMapUnmanaged(Digest, void), comptime names: fn (std.mem.Allocator, []const u8, *std.AutoHashMapUnmanaged(Digest, void)) error{ OutOfMemory, Damaged }!void) !void {
        const where = try std.fs.path.join(self.allocator, &.{ self.directory, subdirectory });
        var directory = std.Io.Dir.cwd().openDir(self.io, where, .{ .iterate = true }) catch return;
        defer directory.close(self.io);
        var iterator = directory.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file) continue;
            const bytes = directory.readFileAlloc(self.io, entry.name, self.allocator, .unlimited) catch continue;
            names(self.allocator, bytes, live) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                // A damaged pack or replay answers nothing, so it names nothing.
                error.Damaged => continue,
            };
        }
    }
    /// Delete every file under `il/` that is not a text `live` names, including
    /// staging files a crashed writer left behind.
    fn deleteUnnamed(self: *Store, live: *const std.AutoHashMapUnmanaged(Digest, void)) !void {
        const where = try std.fs.path.join(self.allocator, &.{ self.directory, "il" });
        var directory = std.Io.Dir.cwd().openDir(self.io, where, .{ .iterate = true }) catch return;
        defer directory.close(self.io);
        var doomed: std.ArrayList([]const u8) = .empty;
        var iterator = directory.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file) continue;
            var digest: Digest = undefined;
            const text = entry.name.len == 64 and (std.fmt.hexToBytes(&digest, entry.name) catch null) != null;
            if (text and live.contains(digest)) continue;
            try doomed.append(self.allocator, try self.allocator.dupe(u8, entry.name));
        }
        for (doomed.items) |name| directory.deleteFile(self.io, name) catch continue;
        self.statistics.texts.swept += doomed.items.len;
    }
    fn readCount(self: *Store, counter: []const u8) usize {
        var buffer: [32]u8 = undefined;
        const bytes = std.Io.Dir.cwd().readFile(self.io, counter, &buffer) catch return 0;
        return std.fmt.parseUnsigned(usize, std.mem.trim(u8, bytes, " \n"), 10) catch 0;
    }
    fn writeCount(self: *Store, counter: []const u8, count: usize) void {
        if (count == self.readCount(counter)) return;
        var buffer: [32]u8 = undefined;
        atomicWrite(self.io, counter, std.fmt.bufPrint(&buffer, "{d}\n", .{count}) catch return) catch return;
    }

    /// The digest of every text this process emitted or reused: each unit's
    /// IL and each unit's stored metadata.
    pub fn texts(self: *const Store, allocator: std.mem.Allocator) error{OutOfMemory}![]const Digest {
        var out: std.ArrayList(Digest) = .empty;
        for (self.used.values()) |entry| switch (entry) {
            .unit => |answer| try out.append(allocator, answer.il),
            .meta => |digest| try out.append(allocator, digest),
            .record => |stored| try out.appendSlice(allocator, &.{ stored.unit.il, stored.meta }),
            .first => {},
        };
        return out.toOwnedSlice(allocator);
    }
    /// The record a function's last emission left under `key` (`EMIT-STANDIN-1`),
    /// kept in this build's pack once looked up.
    pub fn record(self: *Store, key: Digest) error{OutOfMemory}!?*const Record {
        const entry = self.lookup(key) orelse return null;
        if (entry != .record) return null;
        try self.used.put(self.allocator, key, entry);
        return entry.record;
    }
    /// Remember a freshly made record under `key`.
    pub fn rememberRecord(self: *Store, key: Digest, made: Record) error{OutOfMemory}!void {
        const stored = try self.allocator.create(Record);
        stored.* = made;
        try self.used.put(self.allocator, key, .{ .record = stored });
    }
    /// The directory every stored text lives in under its hex digest, which a
    /// lean manifest names once as its `store`.
    pub fn textRoot(self: *const Store) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.directory, "il" });
    }
    /// The digest of the stored metadata text for `key` (`EMIT-META-1`), if
    /// any and if that text is still on disk.
    pub fn meta(self: *Store, key: Digest) error{OutOfMemory}!?Digest {
        const entry = self.lookup(key) orelse {
            self.statistics.meta.misses += 1;
            return null;
        };
        if (entry != .meta or !self.present(entry.meta)) {
            self.statistics.meta.misses += 1;
            return null;
        }
        self.statistics.meta.hits += 1;
        try self.used.put(self.allocator, key, entry);
        return entry.meta;
    }
    /// Store a freshly rendered metadata text (if not already stored) and
    /// remember its digest under `key`. Returns the digest.
    pub fn rememberMeta(self: *Store, key: Digest, text: []const u8) error{OutOfMemory}!Digest {
        var digest: Digest = undefined;
        Sha.hash(text, &digest, .{});
        self.writeText(digest, text) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return digest,
        };
        try self.used.put(self.allocator, key, .{ .meta = digest });
        return digest;
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
        if (self.pack.texts) |listing| {
            listing.access(self.io, &std.fmt.bytesToHex(digest, .lower), .{}) catch return false;
            return true;
        }
        const file = self.path(digest) catch return false;
        std.Io.Dir.cwd().access(self.io, file, .{}) catch return false;
        return true;
    }
    fn writeText(self: *Store, digest: Digest, il: []const u8) !void {
        if (self.present(digest)) return;
        const file = try self.path(digest);
        try atomicWrite(self.io, file, il);
        self.statistics.texts.written += 1;
    }
    fn packPath(self: *const Store) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.directory, "packs", self.pack.name });
    }
    fn load(self: *Store) !void {
        const file = try self.packPath();
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.io, file, self.allocator, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return,
        };
        try readPack(self.allocator, bytes, &self.entries);
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
    const tag = std.fmt.bytesToHex(digestOf(&hash), .lower);
    return std.fs.path.join(allocator, &.{ root, &tag });
}

/// Where a store lives: the fragment root and the compiler identity that
/// partitions it.
pub const Place = struct { root: []const u8, identity: []const u8 };

/// Which remembered emission to look up: the `slot` one configuration of one
/// entry point keeps (so the store holds one replay per configuration, not one
/// per edit), and the `key` of the exact inputs it must have been made from.
pub const Ticket = struct { slot: Digest, key: Digest };

/// A whole lean emission remembered under the exact inputs that produced it
/// (`EMIT-REPLAY-1`): the checked project's warnings and its manifest, plus the
/// digest of every unit text the manifest names. An unchanged project replays
/// them without checking, lowering or emitting anything. Each slot holds only
/// its latest emission, which a later emission in the same slot replaces.
pub const Replay = struct {
    warnings: []const u8,
    manifest: []const u8,

    const magic = "MYLREPL2";

    /// The remembered emission for `ticket`, or null when absent, made from
    /// other inputs, damaged, or when any unit text it names has left the store.
    pub fn load(allocator: std.mem.Allocator, io: std.Io, place: Place, ticket: Ticket) error{OutOfMemory}!?Replay {
        const directory = try namespace(allocator, place.root, place.identity);
        const file = try replayPath(allocator, directory, ticket.slot);
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, file, allocator, .unlimited) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        if (bytes.len < magic.len + 64 or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
        if (!std.mem.eql(u8, bytes[magic.len..][0..32], &ticket.key)) return null;
        const body_end = bytes.len - 32;
        var checksum: Digest = undefined;
        Sha.hash(bytes[0..body_end], &checksum, .{});
        if (!std.mem.eql(u8, &checksum, bytes[body_end..])) return null;
        var reader: PackReader = .{ .bytes = bytes[0..body_end], .at = magic.len + 32 };
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

    /// Remember one successful lean emission in its slot. Best effort.
    pub fn remember(allocator: std.mem.Allocator, io: std.Io, place: Place, ticket: Ticket, answer: Replay, units: []const Digest) void {
        rememberAt(allocator, io, place, ticket, answer, units) catch return;
    }
    fn rememberAt(allocator: std.mem.Allocator, io: std.Io, place: Place, ticket: Ticket, answer: Replay, units: []const Digest) !void {
        // MANIFEST-STREAM-1: the record is written piece by piece around the
        // manifest instead of being assembled in one buffer, so remembering a
        // million-line build's ~100 MB manifest copies none of it.
        var head: std.ArrayList(u8) = .empty;
        defer head.deinit(allocator);
        try head.appendSlice(allocator, magic);
        try head.appendSlice(allocator, &ticket.key);
        try appendInt(allocator, &head, u64, answer.warnings.len);
        var middle: [8]u8 = undefined;
        std.mem.writeInt(u64, &middle, answer.manifest.len, .little);
        var tail: std.ArrayList(u8) = .empty;
        defer tail.deinit(allocator);
        try appendInt(allocator, &tail, u32, @intCast(units.len));
        for (units) |unit_digest| try tail.appendSlice(allocator, &unit_digest);
        const body = [_][]const u8{ head.items, answer.warnings, &middle, answer.manifest, tail.items };
        var hash = Sha.init(.{});
        for (body) |part| hash.update(part);
        var checksum: Digest = undefined;
        hash.final(&checksum);
        const directory = try namespace(allocator, place.root, place.identity);
        try atomicWriteParts(io, try replayPath(allocator, directory, ticket.slot), &(body ++ [_][]const u8{&checksum}));
    }
    fn replayPath(allocator: std.mem.Allocator, directory: []const u8, slot: Digest) error{OutOfMemory}![]const u8 {
        return std.fs.path.join(allocator, &.{ directory, "replay", &std.fmt.bytesToHex(slot, .lower) });
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
        .meta => |digest| {
            try out.append(allocator, 2);
            try out.appendSlice(allocator, &digest);
        },
        .record => |record| {
            try out.append(allocator, 3);
            var writer = codec.Writer.init(allocator);
            defer writer.deinit();
            try writer.write(Record, record.*);
            try appendInt(allocator, out, u32, @intCast(writer.bytes.items.len));
            try out.appendSlice(allocator, writer.bytes.items);
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
    fn record(self: *PackReader, allocator: std.mem.Allocator) error{ Damaged, OutOfMemory }!*const Record {
        const bytes = try self.take(try self.int(u32));
        var reader = codec.Reader.init(allocator, bytes);
        const value = reader.read(Record) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Damaged,
        };
        if (!reader.done()) return error.Damaged;
        const stored = try allocator.create(Record);
        stored.* = value;
        return stored;
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
    return atomicWriteParts(io, file, &.{bytes});
}
/// Stage `parts`, in order, as one file beside `file` and rename it into place.
fn atomicWriteParts(io: std.Io, file: []const u8, parts: []const []const u8) !void {
    const directory = std.fs.path.dirname(file) orelse ".";
    try std.Io.Dir.cwd().createDirPath(io, directory);
    var nonce: [8]u8 = undefined;
    std.Io.random(io, &nonce);
    var buffer: [std.fs.max_path_bytes + 32]u8 = undefined;
    const staging = try std.fmt.bufPrint(&buffer, "{s}.{s}.tmp", .{ file, std.fmt.bytesToHex(nonce, .lower) });
    try writeParts(io, staging, parts);
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

/// Write `parts` in order as the whole of `path`, removing it when a write fails.
fn writeParts(io: std.Io, path: []const u8, parts: []const []const u8) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    for (parts) |part| file.writeStreamingAll(io, part) catch |err| {
        std.Io.Dir.cwd().deleteFile(io, path) catch |cleanup| switch (cleanup) {
            error.FileNotFound => {},
            else => {},
        };
        return err;
    };
}

// spec-case: MANIFEST-STREAM-1
test "writeParts writes its parts in order and reports a place it cannot create" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root, "parts" });
    defer std.testing.allocator.free(path);
    try writeParts(std.testing.io, path, &.{ "head,", "", "body,", "tail" });
    const written = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(written);
    try std.testing.expectEqualStrings("head,body,tail", written);
    const missing = try std.fs.path.join(std.testing.allocator, &.{ root, "no-such-directory", "parts" });
    defer std.testing.allocator.free(missing);
    try std.testing.expectError(error.FileNotFound, writeParts(std.testing.io, missing, &.{"x"}));
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "a stored unit's facts keep the frame-map, literal and data lines and nothing else" {
    const il = "dbgfile \"myl_f_a\"\ntype :t = { l }\nexport data $d = { l 1 }\nexport function l $myl_f_a(l %ctx) {\n@start\n# myl-lit s e 1 2 0102\n ret 0\n}\n";
    const kept = try facts(std.testing.allocator, il);
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings("dbgfile \"myl_f_a\"\nexport data $d = { l 1 }\n# myl-lit s e 1 2 0102\n", kept);
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

// spec-case: QBE-FRAGMENT-REUSE-1
test "the ordinals a key names keep first-mention order without repeats, short or long" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualSlices(u32, &.{ 4, 1, 9 }, try unique(a, &.{ 4, 1, 4, 9, 1 }));
    var long: [100]u32 = undefined;
    for (&long, 0..) |*item, index| item.* = @intCast(index % 40);
    const deduplicated = try unique(a, &long);
    try std.testing.expectEqual(@as(usize, 40), deduplicated.len);
    try std.testing.expectEqual(@as(u32, 39), deduplicated[39]);
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "a store sees a text in its open text directory until the file is gone" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try Store.open(a, std.testing.io, root, "test-compiler", "main.my");
    defer store.deinit();
    try std.testing.expect(store.pack.texts != null);
    const digest = try store.rememberMeta(@splat(1), "{\"name\":\"f\"}");
    try std.testing.expect(store.present(digest));
    try std.Io.Dir.cwd().deleteFile(std.testing.io, try store.path(digest));
    try std.testing.expect(!store.present(digest));
}
