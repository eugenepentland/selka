//! Which locals a safepoint publishes as GC roots (`QBE-ROOTLIVE-1`).
//!
//! A safepoint used to push one root record for every traced local the frame
//! declares. The front end gives every `xs[...]` expression its own hidden
//! receiver temporary, so that was one record per list expression in the
//! function, most of them long dead. A root is needed only for a value some
//! later instruction reads, so a safepoint now publishes exactly the locals that
//! are *live* at it: read by the safepoint itself, or read by an instruction
//! reachable from it before any write of the same local.
//!
//! Soundness rests on one fact: after a collection the frame touches a heap
//! object only through a value it reads, and every such read is one of
//!
//!  1. a local read (`load_local`, `move_local`, a collection method's
//!     receiver, a resource or file method's handle) — a use below;
//!  2. an operand on the stack — rooted by the stack half of the push, which
//!     this analysis does not change;
//!  3. something reachable from 1 or 2 — traced through the root;
//!  4. an implicit read the lowering adds: a closing arena scope scans every
//!     local declared before it (a use of each at `end_arena`), the fused
//!     `src[a:b].decode()` hands the slice's receiver straight to the decode
//!     two instructions later (a use of that receiver at the decode), and the
//!     epilogue releases every local whose type owns something (such a local
//!     is *pinned*: published at every safepoint, exactly as before).
//!
//! A write kills: a whole-value `store_local`, the clearing `drop_local` of a
//! type that owns nothing, and a match arm's payload binding on the edge into
//! that arm. Every other instruction that names a local is a use, which only
//! keeps more roots. Liveness is answered over the same successor relation the
//! bytecode validator walks, so a loop keeps a value read at its head live
//! across the whole body, and a `?` keeps a value its error path reads live.
//! Unreachable instructions (no stack state) are never safepoints.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");

/// Per instruction, the locals a collection starting at that instruction must
/// see: those it reads itself and those live after it, plus every pinned local.
pub const Roots = struct {
    /// Machine words per instruction's row.
    words: usize,
    /// One row of `words` words per instruction, local `i` at bit `i`.
    bits: []const usize,

    /// Whether local `index` must be published at a safepoint at `pc`.
    pub fn has(self: Roots, pc: usize, index: usize) bool {
        const row = pc * self.words;
        if (row + index / 64 >= self.bits.len) return true;
        return self.bits[row + index / 64] >> @intCast(index % 64) & 1 != 0;
    }
};

/// What the analysis reads: the function, which instructions are reachable,
/// and which locals are published at every safepoint whatever their liveness.
pub const Input = struct {
    function: bytecode.Function,
    /// The validator's operand stack per instruction; null where unreachable.
    states: []const ?[]const typed.Type,
    /// Per local, whether the epilogue or an owning store reads its slot, so it
    /// is never dropped from the root set.
    pinned: []const bool,
};

/// The solved liveness of one function: per instruction, the locals live on
/// entry to it and the locals live when it has run (`OWNERSHIP-ANALYSIS-1`).
/// Root planning and the ownership analysis (`ownership.zig`) both read this
/// one solution, so a move the ownership analysis claims and a root the
/// safepoint drops rest on the same answer.
pub const Solution = struct {
    /// Machine words per instruction's row.
    words: usize,
    /// Per instruction, the locals live on entry (local `i` at bit `i`).
    live_in: []const usize,
    /// Per instruction, the locals live on entry to some successor, minus a
    /// match arm's binding on the edge that binds it.
    live_out: []const usize,

    /// Whether local `index` is read again after instruction `pc` runs, before
    /// being written. An unreachable instruction answers false.
    pub fn after(self: Solution, pc: usize, index: usize) bool {
        return bit(self.live_out, self.words, pc, index);
    }
    /// Whether local `index` is live on entry to instruction `pc`.
    pub fn before(self: Solution, pc: usize, index: usize) bool {
        return bit(self.live_in, self.words, pc, index);
    }
    /// Release both row tables.
    pub fn deinit(self: Solution, a: std.mem.Allocator) void {
        a.free(self.live_in);
        a.free(self.live_out);
    }
};

fn bit(rows: []const usize, words: usize, pc: usize, index: usize) bool {
    const at = pc * words + index / 64;
    if (index / 64 >= words or at >= rows.len) return false;
    return rows[at] >> @intCast(index % 64) & 1 != 0;
}

/// Solve liveness for every local of `input.function` over the bytecode's own
/// successor relation. The rows are allocated from `a` and owned by the caller.
pub fn solve(a: std.mem.Allocator, input: Input) error{OutOfMemory}!Solution {
    const code = input.function.scope.instructions;
    const words = (input.function.scope.locals.len + 63) / 64;
    const live = try a.alloc(usize, code.len * words);
    errdefer a.free(live);
    @memset(live, 0);
    const scratch = try a.alloc(usize, words);
    defer a.free(scratch);
    var changed = true;
    while (changed) {
        changed = false;
        var pc = code.len;
        while (pc > 0) {
            pc -= 1;
            if (pc >= input.states.len or input.states[pc] == null) continue;
            liveAfter(input, live, pc, scratch);
            transfer(input, pc, scratch);
            const row = live[pc * words ..][0..words];
            if (std.mem.eql(usize, row, scratch)) continue;
            @memcpy(row, scratch);
            changed = true;
        }
    }
    const out = try a.alloc(usize, code.len * words);
    @memset(out, 0);
    for (0..code.len) |pc| {
        if (pc >= input.states.len or input.states[pc] == null) continue;
        liveAfter(input, live, pc, out[pc * words ..][0..words]);
    }
    return .{ .words = words, .live_in = live, .live_out = out };
}

/// Answer, for every instruction, which locals a safepoint there publishes.
/// The rows are allocated from `a` and owned by the caller.
pub fn analyze(a: std.mem.Allocator, input: Input) error{OutOfMemory}!Roots {
    const solution = try solve(a, input);
    defer solution.deinit(a);
    return roots(a, input, solution);
}

/// The root rows of a solved function: per instruction, the locals it reads
/// itself, the locals live after it, and every pinned local.
pub fn roots(a: std.mem.Allocator, input: Input, solution: Solution) error{OutOfMemory}!Roots {
    const code = input.function.scope.instructions;
    const words = solution.words;
    const bits = try a.alloc(usize, code.len * words);
    @memset(bits, 0);
    for (0..code.len) |pc| {
        if (pc >= input.states.len or input.states[pc] == null) continue;
        const row = bits[pc * words ..][0..words];
        @memcpy(row, solution.live_out[pc * words ..][0..words]);
        uses(input, pc, row);
        for (input.pinned, 0..) |pinned, index| if (pinned) include(row, index);
    }
    return .{ .words = words, .bits = bits };
}

/// `into` = the union of what is live on entry to every successor of `pc`,
/// minus a match arm's binding on the edge that binds it.
fn liveAfter(input: Input, live: []const usize, pc: usize, into: []usize) void {
    @memset(into, 0);
    const code = input.function.scope.instructions;
    switch (code[pc].op) {
        .jump => |target| merge(live, target, into),
        .jump_if_false => |target| {
            merge(live, target, into);
            merge(live, pc + 1, into);
        },
        .try_result => |propagate| {
            merge(live, propagate.error_target, into);
            merge(live, pc + 1, into);
        },
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            const words = into.len;
            if (words == 0 or (arm.target + 1) * words > live.len) continue;
            const row = live[arm.target * words ..][0..words];
            const bound: ?usize = if (arm.slot) |slot| @backingInt(slot) else null;
            for (into, row, 0..) |*word, entering, at| {
                var bits = entering;
                if (bound) |index| if (index / 64 == at) {
                    bits &= ~(@as(usize, 1) << @intCast(index % 64));
                };
                word.* |= bits;
            }
        },
        .ret => {},
        else => merge(live, pc + 1, into),
    }
}

fn merge(live: []const usize, target: usize, into: []usize) void {
    const words = into.len;
    if (words == 0 or (target + 1) * words > live.len) return;
    for (into, live[target * words ..][0..words]) |*word, entering| word.* |= entering;
}

/// Turn what is live after `pc` into what is live before it: remove what the
/// instruction writes, then add what it reads.
fn transfer(input: Input, pc: usize, row: []usize) void {
    switch (input.function.scope.instructions[pc].op) {
        .store_local => |slot| exclude(row, @backingInt(slot)),
        // A clearing drop of a type that owns nothing zeroes the slot and reads
        // nothing; one that owns something is pinned and released through it.
        .drop_local => |slot| if (!pinnedLocal(input, @backingInt(slot))) exclude(row, @backingInt(slot)),
        else => {},
    }
    uses(input, pc, row);
}

/// Add every local the instruction at `pc` reads, explicitly or through the
/// lowering, to `row`.
fn uses(input: Input, pc: usize, row: []usize) void {
    const code = input.function.scope.instructions;
    switch (code[pc].op) {
        .load_local, .move_local => |slot| include(row, @backingInt(slot)),
        .drop_local => |slot| if (pinnedLocal(input, @backingInt(slot))) include(row, @backingInt(slot)),
        .buffer_operation => |operation| {
            include(row, @backingInt(operation.owner));
            // `src[a:b].decode()` fuses into one decode of the range: the
            // decode reads the slice's receiver, not the byte string the slice
            // would have built, so that receiver must survive to the decode.
            if (operation.kind == .decode and pc >= 2) switch (code[pc - 2].op) {
                .buffer_operation => |slice| if (slice.kind == .slice) include(row, @backingInt(slice.owner)),
                else => {},
            };
        },
        .resource_io => |operation| include(row, @backingInt(operation.owner)),
        .file_method => |method| include(row, @backingInt(method.owner)),
        // Closing a scope scans every binding declared before it through its
        // slot, looking for a reference into the region being freed.
        .end_arena => |watermark| {
            const scanned = @min(@backingInt(watermark), input.function.scope.locals.len);
            for (0..scanned) |index| include(row, index);
        },
        else => {},
    }
}

fn pinnedLocal(input: Input, index: usize) bool {
    return index < input.pinned.len and input.pinned[index];
}

fn include(bits: []usize, index: usize) void {
    if (index / 64 >= bits.len) return;
    bits[index / 64] |= @as(usize, 1) << @intCast(index % 64);
}

fn exclude(bits: []usize, index: usize) void {
    if (index / 64 >= bits.len) return;
    bits[index / 64] &= ~(@as(usize, 1) << @intCast(index % 64));
}
