//! Text passes over one function's emitted QBE IL, run after lowering: drop
//! labels nothing jumps to, elide or sink position stores no trap can observe,
//! position each call at its instruction, route failure paths to one halt, and
//! drop the root protocol, zero-filled slots and heap pointer a function turns
//! out not to need. They read and rewrite text only, so each is testable on a
//! string and none depends on the emitter.
const std = @import("std");
/// Failures an IL pass reports: the same set as `qbe.GenerateError`.
pub const GenerateError = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// The prologue call that computes the shared heap pointer.
const heap_call = " %heap =l call $myl_qbe_heap(l %ctx)";
/// The RC frame prologue call that reads the entry arena depth.
const region_call = " %rcregion =l call $myl_qbe_region_mark(l %ctx)";

/// The length of the instruction-label name starting at `text[0]`: `i`, or
/// the versioned loop's `fi` and `oi` (`QBE-LOOP-VERSION-1`), then at least one
/// digit. Zero when `text` does not start with one.
fn pcLabelName(text: []const u8) usize {
    var at: usize = 0;
    if (at < text.len and (text[at] == 'f' or text[at] == 'o')) at += 1;
    if (at >= text.len or text[at] != 'i') return 0;
    at += 1;
    const digits = at;
    while (at < text.len and std.ascii.isDigit(text[at])) at += 1;
    return if (at > digits) at else 0;
}

/// The name of a line that is exactly an instruction label (`@i12`, `@fi12`,
/// `@oi12`), or null when the line is anything else.
fn pcLabel(line: []const u8) ?[]const u8 {
    if (line.len < 3 or line[0] != '@') return null;
    const name = pcLabelName(line[1..]);
    if (name == 0 or name + 1 != line.len) return null;
    return line[1..];
}

/// Record every instruction label a line mentions. A definition line never
/// mentions itself, so callers skip labels before calling this.
fn collectLabelReferences(a: std.mem.Allocator, referenced: *std.StringHashMapUnmanaged(void), line: []const u8) GenerateError!void {
    var rest = line;
    while (std.mem.indexOfScalar(u8, rest, '@')) |at| {
        rest = rest[at + 1 ..];
        const name = pcLabelName(rest);
        if (name != 0) try referenced.put(a, rest[0..name], {});
    }
}

/// Drop the instruction labels no branch names. Straight-line instructions
/// share one block, and a block boundary forces QBE to materialize every live
/// value, so an unreferenced label costs exactly as much as a real one.
pub fn stripUnreferencedLabels(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var referenced: std.StringHashMapUnmanaged(void) = .empty;
    defer referenced.deinit(a);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    for (lines.items) |line| {
        if (pcLabel(line) != null) continue;
        try collectLabelReferences(a, &referenced, line);
    }
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    for (lines.items) |line| {
        if (pcLabel(line)) |digits| if (!referenced.contains(digits)) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// The prologue line that computes the frame position address every store uses.
/// The record temp differs per function, so this is a prefix.
const position_address = " %position =l add ";

/// The pc of a line that stores one instruction's frame position, or null when
/// the line is anything else. Every emitted instruction opens with one, so these
/// lines also delimit instruction bodies for `elideUnobservablePositions`.
pub fn positionStore(line: []const u8) ?[]const u8 {
    const prefix = " storel ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const rest = line[prefix.len..];
    const comma = std.mem.indexOf(u8, rest, ", %position") orelse return null;
    return rest[0..comma];
}

/// Whether a line defines one of the function-level labels the epilogue owns.
/// They end the last instruction's body: a `@failure` in the epilogue is not a
/// reason for the instruction before it to store a position.
pub fn functionLabel(line: []const u8) bool {
    inline for (.{ "@step_limit", "@failure", "@allocation_failure", "@entry_failure" }) |label| {
        if (std.mem.eql(u8, line, label)) return true;
    }
    return false;
}

/// Drop the frame-position store from instructions no diagnostic can observe.
/// The stored pc exists so a trap trace and an `assert` message name the right
/// instruction, so an instruction whose body cannot fail and is not a call site
/// does not need it: the next instruction that can be observed stores its own.
/// Bodies are delimited by the position stores themselves, which is why this
/// pass runs before unreferenced labels are stripped. In `fast` mode the sticky
/// test is gone, so a call — not the literal text `failure` — is what makes a
/// body observable: any callee can trap and will name this frame's call site.
pub fn elideUnobservablePositions(a: std.mem.Allocator, text: []const u8, fast: bool) GenerateError![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    // A body ends at the next store or at the epilogue, so the observable
    // instructions are known before any line is written.
    var observable: std.ArrayList(usize) = .empty;
    defer observable.deinit(a);
    var index: usize = 0;
    while (index < lines.items.len) : (index += 1) {
        if (positionStore(lines.items[index]) == null) continue;
        var end = index + 1;
        while (end < lines.items.len and positionStore(lines.items[end]) == null and !functionLabel(lines.items[end])) end += 1;
        for (lines.items[index..end]) |body| {
            if (std.mem.indexOf(u8, body, "failure") == null and !(fast and std.mem.indexOf(u8, body, "call $") != null)) continue;
            try observable.append(a, index);
            break;
        }
    }
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    for (lines.items, 0..) |line, at| {
        if (positionStore(line) != null) {
            if (std.mem.indexOfScalar(usize, observable.items, at) == null) continue;
        } else if (observable.items.len == 0 and std.mem.startsWith(u8, line, position_address)) {
            // The frame position has no other reader, so a function that stores
            // none does not need it computed either.
            continue;
        }
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Move each instruction's frame-position store off its hot path and into the
/// cold block that raises its own trap. A body that names a call other than a
/// `myl_qbe_fail_*` helper keeps its store at the top: a guest callee, runtime
/// helper or provider can trap on its own, and the trace it builds reads this
/// frame's position. A body whose only trap path is a `myl_qbe_fail_*` call gets
/// one store in front of each such call instead, so every pc a trace can name is
/// exactly the pc the store named before, and the loop body carries no store.
pub fn sinkPositions(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var index: usize = 0;
    while (index < lines.items.len) {
        const pc = positionStore(lines.items[index]) orelse {
            try kept.append(a, lines.items[index]);
            index += 1;
            continue;
        };
        var end = index + 1;
        while (end < lines.items.len and positionStore(lines.items[end]) == null and !functionLabel(lines.items[end])) end += 1;
        const body = lines.items[index + 1 .. end];
        var deferred = true;
        for (body) |line| {
            if (std.mem.indexOf(u8, line, "call $") == null) continue;
            if (std.mem.indexOf(u8, line, "call $myl_qbe_fail_") != null) continue;
            deferred = false;
        }
        if (!deferred) {
            try kept.append(a, lines.items[index]);
            try kept.appendSlice(a, body);
        } else {
            for (body) |line| {
                if (std.mem.indexOf(u8, line, "call $myl_qbe_fail_") != null) {
                    try kept.append(a, try std.fmt.allocPrint(a, " storel {s}, %position", .{pc}));
                }
                try kept.append(a, line);
            }
        }
        index = end;
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Whether one IL line is a call instruction, direct or indirect.
fn callLine(line: []const u8) bool {
    const trimmed = std.mem.trimStart(u8, line, " ");
    if (trimmed.len == 0 or trimmed[0] == '#') return false;
    return std.mem.indexOf(u8, trimmed, "call $") != null or std.mem.indexOf(u8, trimmed, "call %") != null;
}

/// QBE-FRAMEMAP-1: replace the frame-position stores with call-site positions.
/// The unit opens with `dbgfile "SYMBOL"`, every position store is dropped (it
/// only delimits instruction bodies), and every call is preceded by
/// `dbgloc PC+1` naming the instruction it belongs to — the position a trace
/// reports for a frame whose return address is that call. A call before the
/// first instruction (the prologue's accounting refusal, a heap frame's
/// allocation) reports pc 0, the position the linked record started at, and a
/// call the prologue already positioned (the entry guard) keeps its own.
pub fn callSitePositions(a: std.mem.Allocator, text: []const u8, unit_symbol: []const u8) GenerateError![]u8 {
    var out: std.Io.Writer.Allocating = .init(a);
    errdefer out.deinit();
    const w = &out.writer;
    w.print("dbgfile \"{s}\"\n", .{unit_symbol}) catch return error.OutOfMemory;
    var pc: []const u8 = "0";
    var previous: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (positionStore(line)) |digits| {
            pc = digits;
            continue;
        }
        if (!first) w.writeByte('\n') catch return error.OutOfMemory;
        first = false;
        if (callLine(line) and !std.mem.startsWith(u8, previous, " dbgloc ")) {
            const number = std.fmt.parseInt(u64, pc, 10) catch return error.InternalError;
            w.print(" dbgloc {d}\n", .{number + 1}) catch return error.OutOfMemory;
        }
        w.writeAll(line) catch return error.OutOfMemory;
        previous = line;
    }
    return out.toOwnedSlice() catch error.OutOfMemory;
}

/// QBE-NORETURN-1: end every failure path whose last call is a `myl_qbe_fail_*`
/// helper in `hlt` (LLVM's `unreachable`) instead of `jmp @failure`. Only the
/// fast protocol runs this: there the guest-stack trampoline has armed the
/// non-local exit before any guest instruction runs, and every such helper calls
/// the runtime's `fail`, which builds the trace and leaves through it, so the
/// jump after the call is dead. Keeping it anyway makes every check an edge into
/// the shared exit, which blocks inlining and merges the no-overflow facts of
/// every path. A build with step or frame accounting keeps the sticky return.
/// The value helpers `myl_qbe_int_neg` and `myl_qbe_int_binary` also compute
/// ordinary results, so their call ends a path only in the cold block the
/// checked negation and shift open for the one operand class that always traps.
pub fn haltFailurePaths(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    var block: []const u8 = "";
    var previous: []const u8 = "";
    while (scan.next()) |line| {
        const exits = std.mem.eql(u8, line, " jmp @failure") or std.mem.eql(u8, line, " jmp @entry_failure");
        try kept.append(a, if (exits and failingCall(block, previous)) " hlt" else line);
        if (std.mem.startsWith(u8, line, "@")) block = line;
        previous = line;
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Whether `call`, the last line of the block labelled `block`, is a call that
/// has already recorded a trap and left through the runtime's non-local exit.
fn failingCall(block: []const u8, call: []const u8) bool {
    if (std.mem.startsWith(u8, call, " call $myl_qbe_fail_")) return true;
    if (std.mem.startsWith(u8, call, " call $myl_qbe_int_neg(")) return std.mem.startsWith(u8, block, "@neg_overflow");
    if (std.mem.startsWith(u8, call, " call $myl_qbe_int_binary(")) return std.mem.startsWith(u8, block, "@shift_invalid");
    return false;
}

/// Whether a lowered body can leave `ctx->trap` set and fall through to the next
/// instruction. A `myl_qbe_fail_*` helper, and any call the body follows with the
/// `jmp @failure` that unwinds, fails the instruction outright; every other call
/// either returns with the trap set — a guest call, `myl_qbe_int_binary`, a
/// provider read — or is a helper that cannot set it at all.
pub fn stickyTrap(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, text, '\n');
    // A non-fail call whose very next line may be the `jmp @failure` that makes
    // it an outright failure rather than a returned one.
    var awaiting = false;
    var sticky = false;
    while (lines.next()) |line| {
        if (awaiting) {
            awaiting = false;
            if (std.mem.eql(u8, line, " jmp @failure")) continue;
        }
        const at = std.mem.indexOf(u8, line, "call $") orelse continue;
        const rest = line[at + "call $".len ..];
        const stop = std.mem.indexOfAny(u8, rest, "( \n") orelse rest.len;
        if (std.mem.startsWith(u8, rest[0..stop], "myl_qbe_fail_")) continue;
        sticky = true;
        awaiting = true;
    }
    return sticky;
}
/// Drop the root machinery and the local zero-fill from a function that never
/// pushes a root. With no actual safepoint, no collection can observe a slot,
/// and with no drop, nothing reads one before its first assignment, so both the
/// root mark and its restore, and every per-local `memset`, are dead. A function
/// that does push a root keeps all of them. An inner push is the only code that
/// computes a `%root{i}` field address. Remove only the frozen root-chain
/// offset, preserving RC bookkeeping and every other heap-field address.
pub fn dropUnusedRoots(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    if (std.mem.indexOf(u8, text, "=l add %root") != null) return a.dupe(u8, text);
    // A closing arena scope scans every local declared before it through its
    // slot, assigned or not, so the zero-fill is what it reads for one the
    // body has not reached yet (`QBE-ROOTLIVE-1`).
    const drops = std.mem.indexOf(u8, text, "myl_native_owned_drop") != null or
        std.mem.indexOf(u8, text, "myl_qbe_region_retains") != null;
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (std.mem.startsWith(u8, line, " %root_mark =l call $myl_qbe_root_mark")) continue;
        if (std.mem.startsWith(u8, line, " storel %root_mark, ")) continue;
        if (std.mem.endsWith(u8, line, "=l add %heap, 16")) continue;
        if (!drops and isLocalZero(line)) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}
/// Match the exact `%lN` zero-fill `initializeStorage` emits for a traced local.
fn isLocalZero(line: []const u8) bool {
    if (!std.mem.startsWith(u8, line, " call $memset(l %l")) return false;
    return std.mem.indexOf(u8, line, ", w 0, l ") != null;
}

/// RC-FLAG-PROMOTE-1: forward each `%vN =l copy %rcgP` or `%rcrP` address
/// copy into its uses. Every RC guard and role word is then loaded and stored
/// through its own frame slot, so QBE promotes each one no call can see to a
/// temporary and folds the drops a path has already decided.
pub fn forwardFlagCopies(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var names: std.StringHashMapUnmanaged([]const u8) = .empty;
    defer names.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| if (flagCopy(line)) |copy| try names.put(a, copy.temp, copy.slot);
    if (names.count() == 0) return a.dupe(u8, text);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    scan = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (scan.next()) |line| {
        if (flagCopy(line) != null) continue;
        if (!first) try out.append(a, '\n');
        first = false;
        var rest = line;
        while (std.mem.indexOf(u8, rest, "%v")) |at| {
            var end = at + 2;
            while (end < rest.len and std.ascii.isDigit(rest[end])) end += 1;
            try out.appendSlice(a, rest[0..at]);
            const slot = if (end > at + 2) names.get(rest[at + 1 .. end]) else null;
            if (slot) |name| {
                try out.append(a, '%');
                try out.appendSlice(a, name);
            } else try out.appendSlice(a, rest[at..end]);
            rest = rest[end..];
        }
        try out.appendSlice(a, rest);
    }
    return out.toOwnedSlice(a);
}
const FlagCopy = struct { temp: []const u8, slot: []const u8 };
/// A whole line ` %vN =l copy %rcgP` (guard) or ` %vN =l copy %rcrP` (role).
fn flagCopy(line: []const u8) ?FlagCopy {
    if (!std.mem.startsWith(u8, line, " %v")) return null;
    const marker = " =l copy %rc";
    const equals = std.mem.indexOf(u8, line, marker) orelse return null;
    const temp = line[2..equals];
    if (temp.len < 2 or !allDigits(temp[1..])) return null;
    const slot = line[equals + marker.len - 2 ..];
    if (!flagSlot(slot, 'g') and !flagSlot(slot, 'r')) return null;
    return .{ .temp = temp, .slot = slot };
}
fn allDigits(text: []const u8) bool {
    for (text) |byte| if (!std.ascii.isDigit(byte)) return false;
    return true;
}

/// RC-DEAD-DROPS-1: a guard word that nothing sets reads zero everywhere, so
/// the drops it guards are dead. A guard is live once any line stores a
/// nonzero or unknown value into it or hands its address to a call; every
/// other guard sees only `storew 0` and `loaduw`. A dead guard's drop sequences
/// (its load, branch, drop block and join label) are removed, its remaining
/// loads become `copy 0` and its stores go, so the slot itself is dropped
/// later. Role words that no remaining line reads lose their stores too.
pub fn elideDeadRcDrops(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var dead: std.StringHashMapUnmanaged(void) = .empty;
    defer dead.deinit(a);
    var live: std.StringHashMapUnmanaged(void) = .empty;
    defer live.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (slotDefinition(line)) |name| {
            if (flagSlot(name, 'g')) try dead.put(a, name, {});
            continue;
        }
        var rest = line;
        while (std.mem.indexOf(u8, rest, "%rcg")) |at| {
            const name = flagName(rest[at + 1 ..]);
            rest = rest[at + 1 + name.len ..];
            if (!flagSlot(name, 'g')) continue;
            if (!zeroOrLoad(line, name)) try live.put(a, name, {});
        }
    }
    var names = live.keyIterator();
    while (names.next()) |name| _ = dead.remove(name.*);
    const folded = try foldDeadGuards(a, text, &dead);
    defer a.free(folded);
    const unskipped = try dropEmptyExitSkips(a, folded);
    defer a.free(unskipped);
    return dropUnreadRoles(a, unskipped);
}
/// RC-EXIT-SKIP-1: an entry's return asks `myl_qbe_exit_skip` before its drops.
/// When every one of those drops was dead, the question guards nothing, so the
/// call and its two labels go too. The lines are the ones `qbe_rc_frame.zig`
/// writes: the mark comment, the call, the `jnz`, then the two labels.
fn dropEmptyExitSkips(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    var kept: std.ArrayList(u8) = .empty;
    errdefer kept.deinit(a);
    var index: usize = 0;
    while (index < lines.items.len) : (index += 1) {
        if (std.mem.eql(u8, lines.items[index], " # RC-EXIT-SKIP-1")) {
            if (emptyExitSkip(lines.items, index)) |end| {
                index = end;
                continue;
            }
        }
        try kept.appendSlice(a, lines.items[index]);
        try kept.append(a, '\n');
    }
    if (kept.items.len != 0) _ = kept.pop();
    return kept.toOwnedSlice(a);
}
/// The index of the closing `@rcexitdoneL` when the skip test opened at `index`
/// brackets nothing but comments, or null.
fn emptyExitSkip(lines: []const []const u8, index: usize) ?usize {
    if (index + 4 >= lines.len or !std.mem.containsAtLeast(u8, lines[index + 1], 1, "call $myl_qbe_exit_skip(")) return null;
    const branch = lines[index + 2];
    const at = std.mem.indexOf(u8, branch, ", @rcexitdone") orelse return null;
    const comma = std.mem.indexOfPos(u8, branch, at + 1, ", @rcexitdrop") orelse return null;
    const label = branch[at + ", @rcexitdone".len .. comma];
    if (!allDigits(label) or !std.mem.eql(u8, branch[comma + ", @rcexitdrop".len ..], label)) return null;
    const opened = lines[index + 3];
    if (!std.mem.startsWith(u8, opened, "@rcexitdrop") or !std.mem.eql(u8, opened["@rcexitdrop".len..], label)) return null;
    var end = index + 4;
    while (end < lines.len) : (end += 1) {
        const line = lines[end];
        if (std.mem.startsWith(u8, line, "@rcexitdone") and std.mem.eql(u8, line["@rcexitdone".len..], label)) return end;
        if (!std.mem.startsWith(u8, line, " #")) return null;
    }
    return null;
}
/// `%rcgN` / `%rcrN` exactly (`kind` 'g' or 'r').
fn flagSlot(name: []const u8, kind: u8) bool {
    return name.len > 3 and std.mem.startsWith(u8, name, "rc") and name[2] == kind and allDigits(name[3..]);
}
fn flagName(text: []const u8) []const u8 {
    var end: usize = 0;
    while (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) end += 1;
    return text[0..end];
}
/// ` storew 0, %name` or ` %vN =w loaduw %name`.
fn zeroOrLoad(line: []const u8, name: []const u8) bool {
    if (std.mem.startsWith(u8, line, zero_store) and std.mem.eql(u8, line[zero_store.len..], name)) return true;
    return loadOf(line, name) != null;
}
/// The prefix of a store that clears a guard word.
const zero_store = " storew 0, %";
/// The temporary a ` %vN =w loaduw %name` line defines, or null.
fn loadOf(line: []const u8, name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, " %v")) return null;
    const marker = " =w loaduw %";
    const at = std.mem.indexOf(u8, line, marker) orelse return null;
    if (!std.mem.eql(u8, line[at + marker.len ..], name)) return null;
    return line[1..at];
}
fn foldDeadGuards(a: std.mem.Allocator, text: []const u8, dead: *const std.StringHashMapUnmanaged(void)) GenerateError![]u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| try lines.append(a, line);
    var kept: std.ArrayList(u8) = .empty;
    errdefer kept.deinit(a);
    var index: usize = 0;
    while (index < lines.items.len) : (index += 1) {
        const line = lines.items[index];
        const guard = deadGuard(line, dead);
        if (guard) |name| {
            if (std.mem.startsWith(u8, line, zero_store)) continue;
            const temp = loadOf(line, name).?;
            if (dropSequence(lines.items, index, temp)) |end| {
                index = end;
                continue;
            }
            try kept.print(a, " {s} =w copy 0\n", .{temp});
            continue;
        }
        try kept.appendSlice(a, line);
        try kept.append(a, '\n');
    }
    if (kept.items.len != 0) _ = kept.pop();
    return kept.toOwnedSlice(a);
}
/// The dead guard a zero store or load line names, or null.
fn deadGuard(line: []const u8, dead: *const std.StringHashMapUnmanaged(void)) ?[]const u8 {
    const at = std.mem.indexOf(u8, line, "%rcg") orelse return null;
    const name = flagName(line[at + 1 ..]);
    if (!dead.contains(name) or !zeroOrLoad(line, name)) return null;
    return name;
}
/// The index of the join label closing the drop that begins with this load:
/// ` jnz %vN, @rcslotdropL, @rcslotdoneL`, `@rcslotdropL`, ..., `@rcslotdoneL`.
fn dropSequence(lines: []const []const u8, index: usize, temp: []const u8) ?usize {
    if (index + 2 >= lines.len) return null;
    const branch = lines[index + 1];
    const prefix = " jnz ";
    if (!std.mem.startsWith(u8, branch, prefix) or !std.mem.startsWith(u8, branch[prefix.len..], temp)) return null;
    const targets = branch[prefix.len + temp.len ..];
    const drop = ", @rcslotdrop";
    if (!std.mem.startsWith(u8, targets, drop)) return null;
    const comma = std.mem.indexOfPos(u8, targets, drop.len, ", @rcslotdone") orelse return null;
    const label = targets[drop.len..comma];
    if (!allDigits(label) or !std.mem.eql(u8, targets[comma + ", @rcslotdone".len ..], label)) return null;
    const opened = lines[index + 2];
    if (!std.mem.startsWith(u8, opened, "@rcslotdrop") or !std.mem.eql(u8, opened["@rcslotdrop".len..], label)) return null;
    var end = index + 3;
    while (end < lines.len) : (end += 1) {
        const line = lines[end];
        if (std.mem.startsWith(u8, line, "@rcslotdone") and std.mem.eql(u8, line["@rcslotdone".len..], label)) return end;
    }
    return null;
}
/// Drop every store into a role word that no remaining line reads or escapes.
fn dropUnreadRoles(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var read: std.StringHashMapUnmanaged(void) = .empty;
    defer read.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (slotDefinition(line) != null) continue;
        var rest = line;
        while (std.mem.indexOf(u8, rest, "%rcr")) |at| {
            const name = flagName(rest[at + 1 ..]);
            rest = rest[at + 1 + name.len ..];
            if (flagSlot(name, 'r') and roleStore(line, name) == null) try read.put(a, name, {});
        }
    }
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (std.mem.indexOf(u8, line, "%rcr")) |at| {
            const name = flagName(line[at + 1 ..]);
            if (flagSlot(name, 'r') and roleStore(line, name) != null and !read.contains(name)) continue;
        }
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}
/// A ` storew VALUE, %name` line whose value is a constant or temporary.
fn roleStore(line: []const u8, name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, " storew ")) return null;
    const comma = std.mem.indexOf(u8, line, ", %") orelse return null;
    if (!std.mem.eql(u8, line[comma + 3 ..], name)) return null;
    const value = line[" storew ".len..comma];
    if (std.mem.indexOfScalar(u8, value, ' ') != null or std.mem.indexOf(u8, value, "%rc") != null) return null;
    return value;
}

/// Drop a slot definition no instruction reads. Every `%scratch`, `%arguments`,
/// `%l{i}`, `%s{i}` and `%agg{pc}`/`%aux{pc}` temporary is declared in the entry
/// block, and QBE cannot remove an unused `alloc8` by itself: it lowers each one
/// to a stack adjustment and pointer move. A definition whose name appears once
/// in the unit is read nowhere, so removing it is free.
pub fn dropUnusedSlots(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    // One pass counts every name this unit defines, so the rewrite is O(text).
    // Rescanning the unit once per definition made a unit with many slots cost
    // its own length multiplied by its slot count, which dominated the frontend
    // of every build.
    var references: SlotReferences = .{};
    defer references.deinit(a);
    try references.count(a, text);
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (slotDefinition(line)) |name| if (references.of(name) == 1) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Whole-unit `%name` reference counts for the slot names one unit defines. A
/// definition is dropped when its name is referenced exactly once, which is the
/// definition itself. The table is keyed by slices of the counted text, so it
/// owns no key storage and must not outlive that text. Its domain is exactly the
/// names `slotDefinition` accepts: a `%v{d}` value temporary is not a slot, so
/// `of` reports nothing for it even though the unit mentions it.
const SlotReferences = struct {
    counts: std.StringHashMapUnmanaged(usize) = .empty,

    /// Release the count table; its key slices borrow the counted text.
    fn deinit(self: *SlotReferences, allocator: std.mem.Allocator) void {
        self.counts.deinit(allocator);
    }
    /// Count every `%name` reference for each name `text` defines as a slot. A
    /// name is an identifier run, so the reference it counts is a `%` followed
    /// by that whole run: exactly the pair `nameCount` requires.
    fn count(self: *SlotReferences, allocator: std.mem.Allocator, text: []const u8) GenerateError!void {
        var scan = std.mem.splitScalar(u8, text, '\n');
        while (scan.next()) |line| {
            const name = slotDefinition(line) orelse continue;
            try self.counts.put(allocator, name, 0);
        }
        if (self.counts.count() == 0) return;
        var index: usize = 0;
        while (std.mem.indexOfScalarPos(u8, text, index, '%')) |at| {
            const start = at + 1;
            var end = start;
            while (end < text.len and isNameByte(text[end])) end += 1;
            if (end > start) {
                if (self.counts.getPtr(text[start..end])) |slot| slot.* += 1;
            }
            index = end;
        }
    }
    /// How many whole `%name` references the unit holds, matching `nameCount`.
    fn of(self: *const SlotReferences, name: []const u8) usize {
        return self.counts.get(name) orelse 0;
    }
};

/// Whether one byte may continue a QBE identifier, which is the boundary
/// `nameCount` tests after a candidate reference.
fn isNameByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// The slot name a line defines, when it is a named `alloc8` or heap-frame slot
/// address. `%v{d}` value temporaries are never definitions of this shape.
pub fn slotDefinition(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, " %")) return null;
    const rest = line[2..];
    const equals = std.mem.indexOf(u8, rest, " =l ") orelse return null;
    const name = rest[0..equals];
    if (name.len == 0 or name[0] == 'v') return null;
    for (name) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return null;
    const tail = rest[equals..];
    if (std.mem.indexOf(u8, tail, " alloc8 ") == null and std.mem.indexOf(u8, tail, " add %frame_memory, ") == null) return null;
    return name;
}

/// Count whole `%name` references in the text, ignoring longer identifiers.
///
/// This is the reference implementation, not the hot path: `dropUnusedSlots`
/// asks `SlotReferences` for the same number in one pass, and every counting
/// test compares against this scan. It stays because it is the definition the
/// equivalence is stated in — one text rescan per name — so a later reader can
/// see what the map must reproduce. Do not call it once per definition from the
/// rewrite again.
fn nameCount(text: []const u8, name: []const u8) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, text, index, name)) |at| {
        const prefixed = at > 0 and text[at - 1] == '%';
        const after = at + name.len;
        const bounded = after >= text.len or (!std.ascii.isAlphanumeric(text[after]) and text[after] != '_');
        if (prefixed and bounded) count += 1;
        index = at + name.len;
    }
    return count;
}

// spec: QBE-PROMOTE-2
// spec-case: QBE-FRAMEMAP-1
test "callSitePositions positions each call at its instruction and frees a partial result" {
    const a = std.testing.allocator;
    const text = "export function l $f(l %ctx) {\n@entry\n call $myl_qbe_heap(l %ctx)\n@i3\n storel 3, %position\n %v1 =l call $g(l %ctx)\n ret 0\n}";
    const positioned = try callSitePositions(a, text, "myl_f_x");
    defer a.free(positioned);
    try std.testing.expect(std.mem.startsWith(u8, positioned, "dbgfile \"myl_f_x\"\n"));
    try std.testing.expect(std.mem.indexOf(u8, positioned, " dbgloc 1\n call $myl_qbe_heap") != null);
    try std.testing.expect(std.mem.indexOf(u8, positioned, " dbgloc 4\n %v1 =l call $g") != null);
    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, positioned, "%position"));
    try std.testing.expectError(error.OutOfMemory, callSitePositions(std.testing.failing_allocator, text, "myl_f_x"));
}
test "slot reference counting equals the per-name scan it replaces" {
    const text =
        " %l1 =l alloc8 16\n" ++
        " %l10 =l alloc8 16\n" ++
        " %scratch =l alloc8 8\n" ++
        " storel %l1, %l10\n" ++
        " %v3 =l add %scratch, 8\n" ++
        " %l1x =l alloc8 8\n" ++
        " %unused =l add %frame_memory, 0\n" ++
        " call $f(l %l10, l %l1x)\n" ++
        " storew 0, %%l1\n" ++
        " %tail =l add %frame_memory, 0\n";
    var references: SlotReferences = .{};
    defer references.deinit(std.testing.allocator);
    try references.count(std.testing.allocator, text);
    const names = [_][]const u8{ "l1", "l10", "l1x", "scratch", "unused", "tail", "l", "l1xx", "absent" };
    for (names) |name| try std.testing.expectEqual(nameCount(text, name), references.of(name));
    try std.testing.expectEqual(@as(usize, 3), references.of("l1"));
    try std.testing.expectEqual(@as(usize, 1), references.of("tail"));
    // `%v3` is a value temporary, not a slot definition: the unit mentions it
    // once, and the drop rule never asks about it.
    try std.testing.expectEqual(@as(usize, 1), nameCount(text, "v3"));
    try std.testing.expectEqual(@as(usize, 0), references.of("v3"));
}

// spec-case: QBE-PROMOTE-2
test "a slot name that prefixes another is neither counted nor dropped as it" {
    const text =
        " %l1 =l alloc8 16\n" ++
        " %l10 =l alloc8 16\n" ++
        " call $use(l %l10)\n";
    const kept = try dropUnusedSlots(std.testing.allocator, text);
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings(" %l10 =l alloc8 16\n call $use(l %l10)\n", kept);
}

// spec-case: QBE-PROMOTE-2
test "an unread slot definition is dropped and a read one is kept" {
    const text =
        " %unused =l alloc8 16\n" ++
        " %read =l alloc8 16\n" ++
        " storel %read, %read\n";
    const kept = try dropUnusedSlots(std.testing.allocator, text);
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings(" %read =l alloc8 16\n storel %read, %read\n", kept);
}

/// The pre-change rewrite, kept as the reference the single-pass counter is
/// tested against: it rescans the whole unit once per slot definition, which is
/// exactly the cost the pass removes. Output bytes must be identical.
fn referenceDropUnusedSlots(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (slotDefinition(line)) |name| if (nameCount(text, name) == 1) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

/// Compare every slot name a unit defines against the reference per-name scan,
/// so equivalence is checked over the names the unit actually declares rather
/// than only over hand-written cases.
fn expectSlotCountsMatchReference(text: []const u8, references: *const SlotReferences) !void {
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        const name = slotDefinition(line) orelse continue;
        try std.testing.expectEqual(nameCount(text, name), references.of(name));
    }
}

/// One real emitted unit, verbatim: `sexpr.parser::located` from the sexpr-port
/// project built at ReleaseFast. It declares eight slots in 1704 bytes, so the
/// per-name rescan used to walk its whole text eight times.
const recorded_unit =
    \\type :myl_slice = { l, l }
    \\type :t03f63d9a1a213b895a592d5f44a4804ce2a79a0be44ca138053f23212e67a8ff = align 8 { b 32 }
    \\type :t58a57a37ccc3996fdbd3dbe4ed5cc5eb56a0a9b47b95005d2e3ea6952a56cfc7 = align 8 { b 24 }
    \\export function :t03f63d9a1a213b895a592d5f44a4804ce2a79a0be44ca138053f23212e67a8ff $myl_f_b59e41fe30fc69ebc164c43506ed7df38506c00a2c95f0307df5a00a9552a34b(l %ctx, l %a0, l %a1) {
    \\@entry
    \\ %trap =l add %ctx, 32
    \\ %empty =l alloc8 32
    \\ call $memset(l %empty, w 0, l 32)
    \\ %l0 =l alloc8 24
    \\ %l1 =l alloc8 8
    \\ %s0 =l alloc8 8
    \\ %s1 =l alloc8 8
    \\ %s2 =l alloc8 8
    \\ %s3 =l alloc8 8
    \\ %agg7 =l alloc8 32
    \\ %v6 =l alloc8 32
    \\ %v5 =l add %ctx, 48
    \\ %v14 =l loadl %v5
    \\ storel %v14, %v6
    \\ %v15 =l add %v6, 8
    \\ storel extern $myl_f_b59e41fe30fc69ebc164c43506ed7df38506c00a2c95f0307df5a00a9552a34b_meta, %v15
    \\ %v16 =l add %v6, 16
    \\ storel 0, %v16
    \\ storel %v6, %v5
    \\ storel %a0, %l0
    \\ storel %a1, %l1
    \\ jmp @i0
    \\@i0
    \\ %v18 =l loadl %l1
    \\ storel %v18, %s0
    \\ %v19 =l loadl %l0
    \\ storel %v19, %s1
    \\ %v20 =l loadl %s1
    \\ %v21 =l add %v20, 0
    \\ %v22 =l loadl %v21
    \\ storel %v22, %s1
    \\ %v23 =l loadl %l0
    \\ storel %v23, %s2
    \\ %v24 =l loadl %s2
    \\ %v25 =l add %v24, 8
    \\ %v26 =l loadl %v25
    \\ storel %v26, %s2
    \\ %v27 =l loadl %l0
    \\ storel %v27, %s3
    \\ %v28 =l loadl %s3
    \\ %v29 =l add %v28, 16
    \\ %v30 =l loadl %v29
    \\ storel %v30, %s3
    \\ %v31 =l copy %agg7
    \\ %v32 =l add %v31, 0
    \\ %v33 =l loadl %s0
    \\ storel %v33, %v32
    \\ %v34 =l add %v31, 8
    \\ %v35 =l loadl %s1
    \\ storel %v35, %v34
    \\ %v36 =l add %v31, 16
    \\ %v37 =l loadl %s2
    \\ storel %v37, %v36
    \\ %v38 =l add %v31, 24
    \\ %v39 =l loadl %s3
    \\ storel %v39, %v38
    \\ storel %v31, %s0
    \\ %v40 =l loadl %s0
    \\ %v41 =l loadl %v6
    \\ storel %v41, %v5
    \\ ret %v40
    \\@failure
    \\ %v45 =l loadl %v6
    \\ storel %v45, %v5
    \\ ret %empty
    \\@entry_failure
    \\ ret %empty
    \\}
;

// spec-case: QBE-PROMOTE-2
test "a recorded unit is counted and rewritten exactly as the per-name scan did" {
    var references: SlotReferences = .{};
    defer references.deinit(std.testing.allocator);
    try references.count(std.testing.allocator, recorded_unit);
    try expectSlotCountsMatchReference(recorded_unit, &references);
    const rewritten = try dropUnusedSlots(std.testing.allocator, recorded_unit);
    defer std.testing.allocator.free(rewritten);
    const reference = try referenceDropUnusedSlots(std.testing.allocator, recorded_unit);
    defer std.testing.allocator.free(reference);
    try std.testing.expectEqualStrings(reference, rewritten);
}

/// Drop the `%heap` prologue call when nothing in the function reads it. QBE
/// cannot remove a call by itself, because a call may have effects, and this one
/// only computes `&ctx->heap`.
pub fn dropUnusedHeap(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    return dropUnusedRead(a, text, "%heap", heap_call);
}

/// RC-UNUSED-ENTRY-READS-1: drop the RC frame's `%rcregion` prologue call when
/// nothing in the function reads it. It only reads the arena depth, and the
/// transfers that would have read it may all have been proved unnecessary or
/// removed with a dead drop.
pub fn dropUnusedRegionMark(a: std.mem.Allocator, text: []const u8) GenerateError![]u8 {
    return dropUnusedRead(a, text, "%rcregion", region_call);
}

/// Drop the effect-free prologue `call` defining `name` when that definition
/// is the name's only occurrence.
fn dropUnusedRead(a: std.mem.Allocator, text: []const u8, name: []const u8, call: []const u8) GenerateError![]u8 {
    if (std.mem.count(u8, text, name) != 1) return a.dupe(u8, text);
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(a);
    var scan = std.mem.splitScalar(u8, text, '\n');
    while (scan.next()) |line| {
        if (std.mem.eql(u8, line, call)) continue;
        try kept.append(a, line);
    }
    return std.mem.join(a, "\n", kept.items);
}

// spec: RC-UNUSED-ENTRY-READS-1
test "RC prologue reads that only dead drops used are dropped after the drops go" {
    const a = std.testing.allocator;
    const text =
        \\ %rcg0 =l alloc8 8
        \\ %heap =l call $myl_qbe_heap(l %ctx)
        \\ %rcregion =l call $myl_qbe_region_mark(l %ctx)
        \\ storew 0, %rcg0
        \\ %v1 =w loaduw %rcg0
        \\ jnz %v1, @rcslotdrop2, @rcslotdone2
        \\@rcslotdrop2
        \\ storew 0, %rcg0
        \\ %v3 =l copy %heap
        \\ call $f(l %v3)
        \\@rcslotdone2
        \\ ret 0
    ;
    const elided = try elideDeadRcDrops(a, text);
    defer a.free(elided);
    const heap = try dropUnusedHeap(a, elided);
    defer a.free(heap);
    const region = try dropUnusedRegionMark(a, heap);
    defer a.free(region);
    try std.testing.expectEqualStrings(" %rcg0 =l alloc8 8\n ret 0", region);
    // A read the function still uses stays.
    const used = " %rcregion =l call $myl_qbe_region_mark(l %ctx)\n %v1 =l copy %rcregion\n ret %v1";
    const kept = try dropUnusedRegionMark(a, used);
    defer a.free(kept);
    try std.testing.expectEqualStrings(used, kept);
}

// spec: RC-FLAG-PROMOTE-1
test "RC flag address copies are forwarded into their loads and stores" {
    const a = std.testing.allocator;
    const text = " %rcg0 =l alloc8 8\n %v1 =l copy %rcg0\n storew 1, %v1\n %v12 =l copy %rcr0\n %v2 =w loaduw %v12\n %v123 =l copy %rcwork\n call $f(l %v1, l %v123)";
    const out = try forwardFlagCopies(a, text);
    defer a.free(out);
    try std.testing.expectEqualStrings(" %rcg0 =l alloc8 8\n storew 1, %rcg0\n %v2 =w loaduw %rcr0\n %v123 =l copy %rcwork\n call $f(l %rcg0, l %v123)", out);
    const plain = try forwardFlagCopies(a, " %v1 =l copy %rcregion\n ret %v1");
    defer a.free(plain);
    try std.testing.expectEqualStrings(" %v1 =l copy %rcregion\n ret %v1", plain);
}

// spec: RC-DEAD-DROPS-1
test "RC dead guards lose their drops loads and stores while live guards keep theirs" {
    const a = std.testing.allocator;
    const text =
        \\ %rcg0 =l alloc8 8
        \\ %rcr0 =l alloc8 8
        \\ %rcg1 =l alloc8 8
        \\ storew 0, %rcg0
        \\ storew 2, %rcr0
        \\ storew 0, %rcg1
        \\ storew 1, %rcg1
        \\ %v1 =w loaduw %rcg0
        \\ jnz %v1, @rcslotdrop2, @rcslotdone2
        \\@rcslotdrop2
        \\ storew 0, %rcg0
        \\ %v3 =w loaduw %rcr0
        \\ call $f(l %ctx)
        \\@rcslotdone2
        \\ %v4 =w loaduw %rcg0
        \\ %v5 =w loaduw %rcg1
        \\ ret %v5
    ;
    const out = try elideDeadRcDrops(a, text);
    defer a.free(out);
    try std.testing.expectEqualStrings(
        \\ %rcg0 =l alloc8 8
        \\ %rcr0 =l alloc8 8
        \\ %rcg1 =l alloc8 8
        \\ storew 0, %rcg1
        \\ storew 1, %rcg1
        \\ %v4 =w copy 0
        \\ %v5 =w loaduw %rcg1
        \\ ret %v5
    , out);
}

// spec-case: RC-DEAD-DROPS-1
test "RC flag passes report allocation failure without leaking a partial rewrite" {
    const text = " %rcg0 =l alloc8 8\n storew 0, %rcg0\n %v1 =w loaduw %rcg0\n jnz %v1, @rcslotdrop2, @rcslotdone2\n@rcslotdrop2\n storew 0, %rcg0\n@rcslotdone2\n %v3 =w loaduw %rcg0\n ret %v3";
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, foldDeadGuards(failing.allocator(), text, &dead_zero));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, rewriteAndFree, .{text});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, forwardAndFree, .{" %v1 =l copy %rcg0\n storew 1, %v1"});
}
const dead_zero: std.StringHashMapUnmanaged(void) = .empty;

// spec: RC-EXIT-SKIP-1
test "RC-EXIT-SKIP-1 the skip test goes when every drop it brackets was dead and stays otherwise" {
    const a = std.testing.allocator;
    const empty = " ret 0\n # RC-EXIT-SKIP-1\n %v7 =w call $myl_qbe_exit_skip(l %ctx)\n jnz %v7, @rcexitdone8, @rcexitdrop8\n@rcexitdrop8\n # RC-DICTIONARY-EMPTY-DROPS-1 slot 0\n@rcexitdone8\n ret %v1";
    const removed = try dropEmptyExitSkips(a, empty);
    defer a.free(removed);
    try std.testing.expectEqualStrings(" ret 0\n ret %v1", removed);
    const live = " # RC-EXIT-SKIP-1\n %v7 =w call $myl_qbe_exit_skip(l %ctx)\n jnz %v7, @rcexitdone8, @rcexitdrop8\n@rcexitdrop8\n call $f(l %ctx)\n@rcexitdone8\n ret %v1";
    const kept = try dropEmptyExitSkips(a, live);
    defer a.free(kept);
    try std.testing.expectEqualStrings(live, kept);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, dropEmptyExitSkips(failing.allocator(), live));
    try std.testing.checkAllAllocationFailures(a, skipAndFree, .{empty});
}
fn skipAndFree(a: std.mem.Allocator, text: []const u8) !void {
    a.free(try dropEmptyExitSkips(a, text));
}
fn rewriteAndFree(a: std.mem.Allocator, text: []const u8) !void {
    a.free(try elideDeadRcDrops(a, text));
}
fn forwardAndFree(a: std.mem.Allocator, text: []const u8) !void {
    a.free(try forwardFlagCopies(a, text));
}
