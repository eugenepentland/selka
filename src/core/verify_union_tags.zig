//! The union-tag rule of the IR verifier (lane VL, F-VL-10): a union payload is read only under its own tag.
//!
//! Every `union_payload k` and `union_take k` of a value `x` in a reachable block must be one the tag facts justify: the set
//! of cases `x`'s tag can be where the read runs is within `{k}`. The facts are a forward must-analysis over the control-flow
//! graph:
//!
//! * a value is compared after following forwarding copies and `borrow` (an overlay is the same value at another type);
//! * a `union_make` of case `j` has the tag `j`, wherever it is read; a union of one case has that case;
//! * a tag is read by `union_tag y` (the tag of the value `y`) or by a `list_get_field` whose path ends at a union's tag (an
//!   integer register: the tag of a list element); each is a *key* the facts are about;
//! * on the edges out of a `branch` on `cmp eq|ne (tag, constant j)`, the tag is `j` on the side where the comparison holds
//!   and any other case on the other side;
//! * on the edge out of a `branch` on `cmp eq|ne (tag₁, tag₂)` where the two tags are equal, the two keys are equal from
//!   then on: what is known or learned of either is known of both (the lowering of `a == b` for unions, shape E);
//! * a block's entry facts are what every reached incoming edge gives (a value is known when every edge knows it, with the
//!   union of the cases); a block's own instructions end the facts about the values they define (a loop redefines them);
//! * a tag test counts only when its comparison is made in the branch's own block and each `union_tag` it reads is *fresh*:
//!   a must-fact of its own, made where a block lists the `union_tag` and ended where a block lists its value and not it
//!   (the value was made again after its tag was read), so the read holds the value's current tag; `record_get` reads are
//!   fresh the same way;
//! * a read of a value its own block defines has no entry fact;
//! * a `phi` is fresh while no block has made one of its operands again, and a read of a fresh `phi` is justified when each
//!   operand's facts justify it (shape P: an option tested `Some` on one path and made `Some` on the other);
//! * a read of a `record_get` of a fresh `record_set` of the same field takes the facts of the value stored (shape S);
//! * a read of a `record_get` value takes the facts of another fresh `record_get` of the same record and field (shape R:
//!   `if r.f is Some:` then a read of `r.f`, two reads of one field);
//! * a block where some value's tag can be no case is never entered, so its reads are justified.
//!
//! A read whose value is a `list_get` (shape M: a `match mut` on a list element tests the element's tag through
//! `list_get_field` and reads the payload through `list_get`) is not justified by these facts and is not refused: the gate
//! action counts those reads (`proofs/verify_ir`, `irverify`). A set of cases is a bit set of any width (`Bits`), so a union
//! of any number of cases has facts.
const std = @import("std");
const ir = @import("ir.zig");

/// The read the facts do not justify: its block and instruction (`none` when the facts did not settle).
pub const Site = struct { block: usize, ref: ir.Ref };

/// A set of cases: bit `k` of word `k / 64` is case `k`; words past the end are zero (the Lean copy's natural number).
const Bits = []const u64;

/// What a program point knows of one key: the cases its tag can be.
const Mask = struct { key: u32, mask: Bits };

/// Two keys whose tags are equal (`a < b`).
const Pair = struct { a: u32, b: u32 };

/// The facts at a program point: sets of cases, equal pairs, and the fresh projections (`union_tag` and `record_get` reads that
/// hold their operand's current tag or field).
const Facts = struct { masks: []const Mask = &.{}, pairs: []const Pair = &.{}, fresh: []const u32 = &.{} };

/// The most passes the facts take to settle; a function that needs more is refused at its entry.
const max_passes = 1000;

/// What the verifier does with a payload read the facts do not justify: refuse the function, or count the read and accept
/// it (the read is still reported by `selka verify-ir`, which always refuses).
pub const Mode = enum { refuse, count };

/// The mode of every build's verifier: count (the user's decision of 11 November, "Count for now"). The gate refuses
/// (`selka verify-ir` and `irverify` in the `verify-ir-proof` action). Builds refuse too once no unjustified read outside
/// shape M has shown in the gate's programs and the project sweep over the period DECISIONS.md states (D-VL-18), and the user
/// says so: that is this one value, `.refuse`, and the test "builds refuse an unjustified union payload read when the build
/// mode refuses" then runs instead of the counting one.
pub const build_mode: Mode = .count;

/// What one read is: justified by the facts, of shape M (a `list_get` value the facts do not justify: counted, never
/// refused), or unjustified (refused or counted, by `Mode`).
pub const Verdict = enum { justified, shape_m, unjustified };

/// The payload reads of a function by verdict, and the first unjustified one (`ref` none when the facts did not settle: the
/// function's entry, counted as one unjustified read).
pub const Reads = struct { justified: usize = 0, shape_m: usize = 0, unjustified: usize = 0, first: ?Site = null };

/// Every payload read of `f`'s reachable blocks (`reachable` is the verifier's reached set), by verdict.
pub fn countReads(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, reachable: []const bool) std.mem.Allocator.Error!Reads {
    var reads: Reads = .{};
    if (f.blocks.items.len == 0) return reads;
    var analysis = try Analysis.init(arena, module, f, reachable);
    if (!try analysis.settle()) return .{ .unjustified = 1, .first = .{ .block = 0, .ref = .none } };
    for (f.blocks.items, 0..) |block, b| {
        if (!reachable[b]) continue;
        for (block.insts.items) |ref| {
            const inst = f.inst(ref);
            if (inst.op != .union_payload and inst.op != .union_take) continue;
            switch (try analysis.verdict(b, inst)) {
                .justified => reads.justified += 1,
                .shape_m => reads.shape_m += 1,
                .unjustified => {
                    reads.unjustified += 1;
                    if (reads.first == null) reads.first = .{ .block = b, .ref = ref };
                },
            }
        }
    }
    return reads;
}

/// Follow forwarding copies and overlays (`borrow`) to the value they stand for; null for a chain that leaves the table.
fn canonical(f: *const ir.Function, raw: ir.Ref) ?ir.Ref {
    var current = raw;
    for (0..f.insts.items.len + 1) |_| {
        if (current == .none or current.index() >= f.insts.items.len) return null;
        const inst = f.inst(current);
        if (inst.op != .copy and inst.op != .borrow) return current;
        current = inst.a;
    }
    return null;
}

/// An operation whose result is made of its operands as they are (a tag, a field, a record with one field replaced): its
/// fresh results are a fact.
fn projection(op: ir.Op) bool {
    return op == .union_tag or op == .record_get or op == .record_set;
}

/// `home` of an instruction no block lists (a constant or parameter: never redefined).
const unlisted: u32 = std.math.maxInt(u32);
/// `home` of an instruction more than one block lists.
const many: u32 = std.math.maxInt(u32) - 1;

/// The cases `0 .. n-1`.
fn allCases(arena: std.mem.Allocator, n: usize) std.mem.Allocator.Error!Bits {
    const words = try arena.alloc(u64, (n + 63) / 64);
    @memset(words, std.math.maxInt(u64));
    if (n % 64 != 0) words[words.len - 1] = (@as(u64, 1) << @intCast(n % 64)) - 1;
    return words;
}

/// Case `k` of a union of `n` cases (nothing when `k` is no case).
fn caseMask(arena: std.mem.Allocator, n: usize, k: u64) std.mem.Allocator.Error!Bits {
    if (k >= n) return &.{};
    const words = try arena.alloc(u64, @intCast(k / 64 + 1));
    @memset(words, 0);
    words[words.len - 1] = @as(u64, 1) << @intCast(k % 64);
    return words;
}

fn bitsAnd(arena: std.mem.Allocator, a: Bits, b: Bits) std.mem.Allocator.Error!Bits {
    const words = try arena.alloc(u64, @min(a.len, b.len));
    for (words, 0..) |*w, i| w.* = a[i] & b[i];
    return words;
}

fn bitsOr(arena: std.mem.Allocator, a: Bits, b: Bits) std.mem.Allocator.Error!Bits {
    const words = try arena.alloc(u64, @max(a.len, b.len));
    for (words, 0..) |*w, i| w.* = (if (i < a.len) a[i] else 0) | (if (i < b.len) b[i] else 0);
    return words;
}

/// The cases of `a` not in `b`.
fn bitsMinus(arena: std.mem.Allocator, a: Bits, b: Bits) std.mem.Allocator.Error!Bits {
    const words = try arena.alloc(u64, a.len);
    for (words, 0..) |*w, i| w.* = a[i] & ~(if (i < b.len) b[i] else 0);
    return words;
}

fn bitsEmpty(a: Bits) bool {
    for (a) |w| if (w != 0) return false;
    return true;
}

/// Every case of `a` is in `b`.
fn bitsWithin(a: Bits, b: Bits) bool {
    for (a, 0..) |w, i| if (w & ~(if (i < b.len) b[i] else 0) != 0) return false;
    return true;
}

fn bitsEql(a: Bits, b: Bits) bool {
    return bitsWithin(a, b) and bitsWithin(b, a);
}

fn lookup(masks: []const Mask, key: u32) ?Bits {
    for (masks) |entry| if (entry.key == key) return entry.mask;
    return null;
}

fn paired(pairs: []const Pair, pair: Pair) bool {
    for (pairs) |p| if (p.a == pair.a and p.b == pair.b) return true;
    return false;
}

/// The blocks a block's terminator names (a jump's target, a branch's two), as the verifier reads them.
fn successorsOf(f: *const ir.Function, b: u32) [2]?u32 {
    const refs = f.blocks.items[b].insts.items;
    if (refs.len == 0) return .{ null, null };
    const ref = refs[refs.len - 1];
    if (ref == .none or ref.index() >= f.insts.items.len) return .{ null, null };
    const last = f.inst(ref);
    return switch (last.op) {
        .jump => .{ @truncate(last.data), null },
        .branch => blk: {
            const targets = ir.unpackTargets(last.data);
            break :blk .{ @intCast(targets.then.index()), @intCast(targets.otherwise.index()) };
        },
        else => .{ null, null },
    };
}

/// The end of a block, as a read there sees it: the block, its entry facts and the fresh reads after it.
const At = struct { block: usize, facts: Facts, fresh: []const u32 };

/// A key and the number of cases of its union.
const Key = struct { key: u32, cases: usize };

const Analysis = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    reachable: []const bool,
    /// The block that lists each instruction: `unlisted`, the block, or `many` when more than one does.
    home: []u32,
    /// Each block's entry facts, or null while no reached edge has entered it.
    entry: []?Facts,

    /// The analysis over `arena` (every allocation lives as long as the verifier's arena, so nothing is freed on failure).
    fn init(arena: std.mem.Allocator, module: *const ir.Module, f: *const ir.Function, reachable: []const bool) std.mem.Allocator.Error!Analysis {
        const home = try arena.alloc(u32, f.insts.items.len);
        errdefer arena.free(home);
        const entry = try arena.alloc(?Facts, f.blocks.items.len);
        const self: Analysis = .{ .arena = arena, .module = module, .f = f, .reachable = reachable, .home = home, .entry = entry };
        @memset(self.home, unlisted);
        @memset(self.entry, null);
        for (f.blocks.items, 0..) |block, b| for (block.insts.items) |ref| {
            if (ref == .none or ref.index() >= f.insts.items.len) continue;
            const here: u32 = @intCast(b);
            const slot = &self.home[ref.index()];
            slot.* = if (slot.* == unlisted or slot.* == here) here else many;
        };
        self.entry[0] = .{};
        return self;
    }

    /// The number of cases of a union type, or null for a type that is no union.
    fn unionCases(self: *const Analysis, raw: ir.Type) ?usize {
        const ty = self.module.storageType(raw);
        const is_union = ty.isCompound() and self.module.valid(ty) and self.module.kind(ty) == .@"union";
        if (!is_union) return null;
        return self.module.compound(ty).@"union".len;
    }

    /// The key a tag register reads: the union value of a `union_tag`, or a `list_get_field` of a union's tag itself.
    fn tagKey(self: *const Analysis, raw: ir.Ref) ?Key {
        const r = canonical(self.f, raw) orelse return null;
        const inst = self.f.inst(r);
        switch (inst.op) {
            .union_tag => {
                const x = canonical(self.f, inst.a) orelse return null;
                return .{ .key = @intCast(x.index()), .cases = self.unionCases(self.f.inst(x).ty) orelse return null };
            },
            .list_get_field => {
                const list = canonical(self.f, inst.a) orelse return null;
                const element = self.module.listElement(self.module.storageType(self.f.inst(list).ty)) orelse return null;
                const path = ir.FieldPath.unpack(inst.data);
                const target = self.module.pathTarget(element, path) orelse return null;
                if (target.tag_of == .void) return null;
                return .{ .key = @intCast(r.index()), .cases = self.unionCases(target.tag_of) orelse return null };
            },
            else => return null,
        }
    }

    /// The key of a tag the comparison in `p` reads, when it reads the key's current tag (`fresh`).
    fn freshKey(self: *const Analysis, fresh: []const u32, raw: ir.Ref) ?Key {
        const key = self.tagKey(raw) orelse return null;
        const r = canonical(self.f, raw).?;
        if (self.f.inst(r).op == .list_get_field) return key;
        return if (std.mem.indexOfScalar(u32, fresh, @intCast(r.index())) != null) key else null;
    }

    /// The cases a key's tag can be: what the facts say, and only its own case for a `union_make` (an empty set: no
    /// execution reaches the point).
    fn possible(self: *const Analysis, masks: []const Mask, key: u32, n: usize) std.mem.Allocator.Error!Bits {
        const inst = self.f.inst(@fromBackingInt(key));
        const all = try allCases(self.arena, n);
        const own = if (inst.op == .union_make) try bitsAnd(self.arena, try caseMask(self.arena, n, inst.data), all) else all;
        return bitsAnd(self.arena, own, lookup(masks, key) orelse all);
    }

    /// Narrow every key equal to `key` (by the pairs) to `mask`.
    fn narrow(self: *const Analysis, masks: *std.ArrayList(Mask), pairs: []const Pair, start: Key, mask: Bits) std.mem.Allocator.Error!void {
        var class: std.ArrayList(u32) = .empty;
        try class.append(self.arena, start.key);
        var i: usize = 0;
        while (i < class.items.len) : (i += 1) {
            for (pairs) |p| {
                const other = if (p.a == class.items[i]) p.b else if (p.b == class.items[i]) p.a else continue;
                if (std.mem.indexOfScalar(u32, class.items, other) == null) try class.append(self.arena, other);
            }
        }
        for (class.items) |key| {
            const value = try bitsAnd(self.arena, try self.possible(masks.items, key, start.cases), mask);
            for (masks.items) |*entry| {
                if (entry.key == key) {
                    entry.mask = value;
                    break;
                }
            } else try masks.append(self.arena, .{ .key = key, .mask = value });
        }
    }

    /// Whether block `p` (may) list instruction `key`: its execution redefines the value.
    fn listedIn(self: *const Analysis, p: usize, key: u32) bool {
        const home = self.home[key];
        return home == many or home == p;
    }

    /// The fresh projections after block `p`: those of the entry whose operand `p` does not make again, then the projections
    /// `p` lists (each reads its operand as `p` leaves it).
    fn freshOut(self: *const Analysis, p: usize, fresh: []const u32) std.mem.Allocator.Error![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        for (fresh) |u| if (self.operandsKept(p, @fromBackingInt(u))) try out.append(self.arena, u);
        for (self.f.blocks.items[p].insts.items) |ref| {
            if (ref == .none or ref.index() >= self.f.insts.items.len) continue;
            const op = self.f.inst(ref).op;
            const kept_phi = op == .phi and self.operandsKept(p, ref);
            if (!projection(op) and !kept_phi) continue;
            const u: u32 = @intCast(ref.index());
            if (std.mem.indexOfScalar(u32, out.items, u) == null) try out.append(self.arena, u);
        }
        return out.items;
    }

    /// Whether block `p` leaves every value a fresh read `u` reads as it was: the operand of a projection, each operand of
    /// a `phi` (a `phi` is fresh while it is one of its operands as they are now).
    fn operandsKept(self: *const Analysis, p: usize, u: ir.Ref) bool {
        const inst = self.f.inst(u);
        if (projection(inst.op)) {
            const x = canonical(self.f, inst.a) orelse return false;
            if (self.listedIn(p, @intCast(x.index()))) return false;
            if (inst.op != .record_set) return true;
            const w = canonical(self.f, inst.b) orelse return false;
            return !self.listedIn(p, @intCast(w.index()));
        }
        if (inst.op != .phi) return false;
        for (self.f.operands(inst.data)) |raw| {
            const x = canonical(self.f, raw) orelse return false;
            if (self.listedIn(p, @intCast(x.index()))) return false;
        }
        return true;
    }

    /// Whether block `p` lists `raw`'s canonical value: a tag test is read where it is made.
    fn testedHere(self: *const Analysis, p: usize, raw: ir.Ref) bool {
        const value = canonical(self.f, raw) orelse return false;
        return self.listedIn(p, @intCast(value.index()));
    }

    /// The facts on the edge from `p` (whose entry facts are `facts`) to its successor `s`.
    fn edge(self: *const Analysis, p: usize, facts: Facts, s: u32) std.mem.Allocator.Error!Facts {
        var masks: std.ArrayList(Mask) = .empty;
        for (facts.masks) |entry| if (!self.listedIn(p, entry.key)) try masks.append(self.arena, entry);
        var pairs: std.ArrayList(Pair) = .empty;
        for (facts.pairs) |pair| if (!self.listedIn(p, pair.a) and !self.listedIn(p, pair.b)) try pairs.append(self.arena, pair);
        const fresh = try self.freshOut(p, facts.fresh);
        const refs = self.f.blocks.items[p].insts.items;
        const last = self.f.inst(refs[refs.len - 1]);
        const targets = ir.unpackTargets(last.data);
        const then: u32 = @intCast(targets.then.index());
        if (last.op != .branch or then == targets.otherwise.index()) return .{ .masks = masks.items, .pairs = pairs.items, .fresh = fresh };
        // The comparison and the tags it reads are made in this block, so they read the values its successors see.
        if (!self.testedHere(p, last.a)) return .{ .masks = masks.items, .pairs = pairs.items, .fresh = fresh };
        const condition = self.f.inst(canonical(self.f, last.a).?);
        if (condition.op != .cmp or condition.data > 1) return .{ .masks = masks.items, .pairs = pairs.items, .fresh = fresh };
        // `ne` holds where the tags differ: the true side of the equality is its false edge.
        const holds = (s == then) == (condition.data == 0);
        const left = self.freshKey(fresh, condition.a);
        const right = self.freshKey(fresh, condition.b);
        if (left != null and right != null) {
            const l = left.?;
            const r = right.?;
            if (holds and l.cases == r.cases and l.key != r.key) {
                const pair: Pair = .{ .a = @min(l.key, r.key), .b = @max(l.key, r.key) };
                if (!paired(pairs.items, pair)) try pairs.append(self.arena, pair);
                const both = try bitsAnd(self.arena, try self.possible(masks.items, l.key, l.cases), try self.possible(masks.items, r.key, r.cases));
                try self.narrow(&masks, pairs.items, l, both);
            }
        } else if (left orelse right) |key| {
            const other = canonical(self.f, if (left != null) condition.b else condition.a) orelse return .{ .masks = masks.items, .pairs = pairs.items, .fresh = fresh };
            const constant = self.f.inst(other);
            if (constant.op == .iconst) {
                const all = try allCases(self.arena, key.cases);
                const on_true = try bitsAnd(self.arena, try caseMask(self.arena, key.cases, constant.data), all);
                try self.narrow(&masks, pairs.items, key, if (holds) on_true else try bitsMinus(self.arena, all, on_true));
            }
        }
        return .{ .masks = masks.items, .pairs = pairs.items, .fresh = fresh };
    }

    /// What every incoming edge gives: the keys all of them know, with the union of their cases, and the pairs all of them hold.
    fn meet(self: *const Analysis, a: Facts, b: Facts) std.mem.Allocator.Error!Facts {
        var masks: std.ArrayList(Mask) = .empty;
        for (a.masks) |entry| if (lookup(b.masks, entry.key)) |mask| try masks.append(self.arena, .{ .key = entry.key, .mask = try bitsOr(self.arena, entry.mask, mask) });
        var pairs: std.ArrayList(Pair) = .empty;
        for (a.pairs) |pair| if (paired(b.pairs, pair)) try pairs.append(self.arena, pair);
        var fresh: std.ArrayList(u32) = .empty;
        for (a.fresh) |u| if (std.mem.indexOfScalar(u32, b.fresh, u) != null) try fresh.append(self.arena, u);
        return .{ .masks = masks.items, .pairs = pairs.items, .fresh = fresh.items };
    }

    /// Iterate to the greatest fixed point; false when it does not settle in `max_passes`.
    fn settle(self: *Analysis) std.mem.Allocator.Error!bool {
        const blocks = self.f.blocks.items;
        for (0..max_passes) |_| {
            var changed = false;
            for (blocks, 0..) |_, s| {
                if (s == 0 or !self.reachable[s]) continue;
                var met: ?Facts = null;
                for (blocks[s].preds.items) |pred_id| {
                    const p = pred_id.index();
                    if (p >= blocks.len or !self.reachable[p]) continue;
                    const facts = self.entry[p] orelse continue;
                    const incoming = try self.edge(p, facts, @intCast(s));
                    met = if (met) |current| try self.meet(current, incoming) else incoming;
                }
                const new = met orelse continue;
                if (self.entry[s]) |old| if (sameFacts(old, new)) continue;
                self.entry[s] = new;
                changed = true;
            }
            if (!changed) return true;
        }
        return false;
    }

    /// Whether the facts justify the read, or it is of shape M (counted by the gate action, not refused).
    fn verdict(self: *const Analysis, b: usize, inst: ir.Inst) std.mem.Allocator.Error!Verdict {
        const value = canonical(self.f, inst.a) orelse return .unjustified;
        if (try self.byFacts(b, inst, value)) return .justified;
        return if (self.f.inst(value).op == .list_get) .shape_m else .unjustified;
    }

    /// Shape P: a fresh `phi` is one of its operands as they are now, so it is justified when what its operands can be is
    /// (the merge of an option tested `Some` on one path and made `Some` on the other, through `phi`s of `phi`s).
    fn phiJustified(self: *const Analysis, b: usize, facts: Facts, value: ir.Ref, n: usize, case: Bits) std.mem.Allocator.Error!bool {
        const at: At = .{ .block = b, .facts = facts, .fresh = try self.freshOut(b, facts.fresh) };
        const cases = try self.possibleAt(at, self.f.insts.items.len, @intCast(value.index()), n);
        return bitsWithin(cases, case);
    }

    /// The cases `x` can be at the end of block `b`: for a fresh `phi`, what any of its operands can be (`fuel` bounds the
    /// `phi`s followed); for any other value, its facts.
    fn possibleAt(self: *const Analysis, at: At, fuel: usize, x: u32, n: usize) std.mem.Allocator.Error!Bits {
        const inst = self.f.inst(@fromBackingInt(x));
        if (fuel == 0 or inst.op != .phi or std.mem.indexOfScalar(u32, at.fresh, x) == null) {
            const masks: []const Mask = if (self.listedIn(at.block, x)) &.{} else at.facts.masks;
            return self.possible(masks, x, n);
        }
        var cases: Bits = &.{};
        for (self.f.operands(inst.data)) |raw| {
            const operand = canonical(self.f, raw) orelse {
                cases = try bitsOr(self.arena, cases, try allCases(self.arena, n));
                continue;
            };
            cases = try bitsOr(self.arena, cases, try self.possibleAt(at, fuel - 1, @intCast(operand.index()), n));
        }
        return cases;
    }

    fn byFacts(self: *const Analysis, b: usize, inst: ir.Inst, value: ir.Ref) std.mem.Allocator.Error!bool {
        const facts = self.entry[b] orelse Facts{};
        // A key whose tag can be no case at the block's entry says no execution enters the block.
        for (facts.masks) |entry| if (bitsEmpty(entry.mask)) return true;
        const n = self.unionCases(self.f.inst(value).ty) orelse return false;
        const masks: []const Mask = if (self.listedIn(b, @intCast(value.index()))) &.{} else facts.masks;
        const case = try caseMask(self.arena, n, inst.data);
        if (bitsWithin(try self.possible(masks, @intCast(value.index()), n), case)) return true;
        const read = self.f.inst(value);
        if (read.op == .phi) return self.phiJustified(b, facts, value, n, case);
        if (read.op != .record_get) return false;
        if (try self.twinJustified(b, facts, value, n, case)) return true;
        return self.storeJustified(b, facts, value, n, case);
    }

    /// Shape R: a `record_get` reads the field another fresh `record_get` of the same record reads (`if r.f is Some:` then a
    /// read of `r.f`): both hold the record's current field, so the other's facts are the read value's.
    fn twinJustified(self: *const Analysis, b: usize, facts: Facts, value: ir.Ref, n: usize, case: Bits) std.mem.Allocator.Error!bool {
        const read = self.f.inst(value);
        const base = canonical(self.f, read.a) orelse return false;
        const out = try self.freshOut(b, facts.fresh);
        if (std.mem.indexOfScalar(u32, out, @intCast(value.index())) == null) return false;
        for (out) |u| {
            const twin = self.f.inst(@fromBackingInt(u));
            if (u == value.index() or twin.op != .record_get or twin.data != read.data or self.listedIn(b, u)) continue;
            if ((canonical(self.f, twin.a) orelse continue) != base) continue;
            if (bitsWithin(try self.possible(facts.masks, u, n), case)) return true;
        }
        return false;
    }

    /// Shape S: a `record_get` of a fresh `record_set` of the same field reads the value the `record_set` stored (`r.f =
    /// Some(...)` then `match mut r.f`), so that value's facts are the read value's.
    fn storeJustified(self: *const Analysis, b: usize, facts: Facts, value: ir.Ref, n: usize, case: Bits) std.mem.Allocator.Error!bool {
        const read = self.f.inst(value);
        const record = canonical(self.f, read.a) orelse return false;
        const store = self.f.inst(record);
        if (store.op != .record_set or store.data != read.data or canonical(self.f, store.a) == null) return false;
        const out = try self.freshOut(b, facts.fresh);
        if (std.mem.indexOfScalar(u32, out, @intCast(value.index())) == null) return false;
        if (std.mem.indexOfScalar(u32, out, @intCast(record.index())) == null) return false;
        const stored = canonical(self.f, store.b) orelse return false;
        const key: u32 = @intCast(stored.index());
        const masks: []const Mask = if (self.listedIn(b, key)) &.{} else facts.masks;
        return bitsWithin(try self.possible(masks, key, n), case);
    }
};

/// Whether two fact sets say the same (the same keys with the same masks and the same pairs, in any order).
fn sameFacts(a: Facts, b: Facts) bool {
    if (a.masks.len != b.masks.len or a.pairs.len != b.pairs.len or a.fresh.len != b.fresh.len) return false;
    for (a.fresh) |u| if (std.mem.indexOfScalar(u32, b.fresh, u) == null) return false;
    for (a.masks) |entry| if (!bitsEql(lookup(b.masks, entry.key) orelse return false, entry.mask)) return false;
    for (a.pairs) |pair| if (!paired(b.pairs, pair)) return false;
    return true;
}
