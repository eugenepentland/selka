//! Where copy-on-write code goes in one function (D9 stage 3b,
//! `COW-UNIQUE-1`, `COW-HOIST-1`, `COW-NESTED-1`).
//!
//! The ownership analysis (`ownership.zig`, `OWNERSHIP-ANALYSIS-1`) already
//! names every in-place write of a list, dictionary, set or byte buffer and
//! the loop entry a check there can move to. This plan turns those sites into
//! the checks the native emitter lowers, and adds what copy-on-write over the
//! tracing collector needs beyond them:
//!
//! - A write through a compiler temporary goes to a *place*: an element of a
//!   list, a value of a dictionary, or a field (through records and `class`
//!   bodies) of a local. The value is made unique where the temporary is
//!   filled, and a copy is written back into that place, so the write lands in
//!   the value its owner holds (`COW-NESTED-1`). Each level of a nested path
//!   is its own place, filled in order, so every level is unique before the
//!   next is read out of it.
//! - The payload a nested place is read out of is made unique first: a
//!   dictionary before its value is looked up, a list before its element is
//!   read.
//! - A loop whose checks all moved to its entry keeps its versioned copy
//!   (`QBE-LOOP-VERSION-1`); one with a check left inside does not, because a
//!   copy would move the storage the guard read.
//!
//! A `mut` parameter's payload needs no check: its caller made it unique and
//! pinned it for the call (`COW-PIN-1`). Nothing here changes a program the
//! switch is off for: the emitter asks for a plan only under it.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const ownership = @import("ownership.zig");
const buffer_operations = @import("buffer_operations.zig");

const Op = @FieldType(bytecode.Instruction, "op");
/// Which copy-on-write code a build emits: none, the checks and shares, or
/// those counting themselves too (`COW-STATS-1`).
pub const Mode = enum { off, checks, counting };
/// The absent local or pc.
pub const none = ownership.none;
/// The failures planning can meet.
pub const Error = error{ InternalError, OutOfMemory };

/// How a place temporary's value was read out of its parent.
pub const Step = enum(u8) {
    /// An element of the list local `parent` at the index the base read took.
    element,
    /// The value the dictionary local `parent` holds for the base read's key.
    entry,
    /// A dictionary reached through fields of the record local `parent`.
    entry_field,
    /// A field of the record or `class` local `parent`.
    field,
};

/// A compiler temporary a write goes through and the place its value was read
/// from: `parent`'s element, entry or field, then the fields the `get_field`
/// instructions between `base` and `fill` select.
pub const Place = struct {
    parent: u32,
    step: Step,
    /// The instruction reading out of `parent`: `buffer_operation` read,
    /// `get_index` or `load_local`.
    base: u32,
    /// The dictionary read for `entry_field` (the other steps use `base`).
    read: u32 = none,
    /// First instruction after the field chain for `entry_field`.
    fields_end: u32 = none,
    /// An Option local whose boxed payload was unwrapped into this field's
    /// parent; a replacement field must rebox that value before it is read.
    box: ?BoxOwner = null,
    /// The `store_local` that fills the temporary.
    fill: u32,
};

/// One payload a check makes unique: `local`'s, and, when it is not `none`,
/// the whole alias `alias` of it that must see the copy too.
pub const Unique = struct { local: u32, alias: u32 = none };

/// A check moved to a loop's entry edges: `local`'s payload, or every element
/// of the list `local` holds.
pub const Hoisted = struct { local: u32, elements: bool };

/// What the emitter does at one instruction, before lowering it.
pub const Site = struct {
    /// Payloads made unique first.
    unique: []const Unique = &.{},
    /// Make a dictionary held by record fields unique before its value read.
    unique_field: ?Place = null,
    /// Whether the instruction fills a place: the value it stores is made
    /// unique and written back into the place first.
    fill: bool = false,
    /// Whether the instruction is an element place's base read, whose index
    /// the fill's write-back needs.
    capture: bool = false,
    /// The operand depths whose payloads a transfer here shares (the stage
    /// 3a copy hook's sites, until that hook lands).
    shares: []const u8 = &.{},
    /// Pending dictionary reads captured before a key can run guest code.
    read_captures: []const u8 = &.{},
};

/// The loops checks moved to: per instruction, the checks its entry edges run
/// when it is a loop header, and the last back jump to it.
pub const Loops = struct {
    entries: []const []const Hoisted,
    back: []const u32,

    /// Whether `from` is outside the loop headed at `head`, so a jump from it
    /// to `head` enters the loop and runs its entry checks.
    pub fn enters(self: Loops, head: usize, from: usize) bool {
        if (head >= self.entries.len or self.entries[head].len == 0) return false;
        return from < head or from > self.back[head];
    }
};

/// The finished plan of one function.
pub const Plan = struct {
    /// Per local, the place it was read from, when it is a written place.
    places: []const ?Place = &.{},
    /// Per local, the local whose payload it names whole, or `none`.
    aliases: []const u32 = &.{},
    /// Per instruction, what runs before it.
    sites: []const Site = &.{},
    loops: Loops = .{ .entries = &.{}, .back = &.{} },
    /// Per instruction, whether a check runs there, which a versioned loop
    /// around it must not assume away.
    checked: []const bool = &.{},

    /// What runs before instruction `pc`.
    pub fn at(self: Plan, pc: usize) Site {
        return if (pc < self.sites.len) self.sites[pc] else .{};
    }
    /// The checks the entry edges of the loop headed at `pc` run.
    pub fn entry(self: Plan, pc: usize) []const Hoisted {
        return if (pc < self.loops.entries.len) self.loops.entries[pc] else &.{};
    }
    /// The place local `index` was read from, when it is a written place.
    pub fn place(self: Plan, index: usize) ?Place {
        return if (index < self.places.len) self.places[index] else null;
    }
    /// Whether a place's write-back stores into local `index`'s own slot: a
    /// field of the record it holds. Such a local is written in place, so it
    /// cannot name another local's slot (`QBE-MOVE-ELIDE-1`).
    pub fn writesSlot(self: Plan, index: usize) bool {
        for (self.places) |maybe| if (maybe) |found| if (found.step == .field and found.parent == index) return true;
        return false;
    }
    /// Whether the code at `pc` can replace `owner`'s payload or, when `heap`,
    /// a payload held inside an object: a check redirecting `owner`'s slot
    /// there or on the entry edges of a loop headed there, or any write-back
    /// of a copy. A local another one covers stops being covered there
    /// (`QBE-BORROW-ROOT-1`): the value it holds may be reachable from it
    /// alone.
    pub fn disturbs(self: Plan, owner: usize, pc: usize, heap: bool) bool {
        const site = self.at(pc);
        for (site.unique) |unique| if (unique.local == owner or unique.alias == owner) return true;
        for (self.entry(pc)) |check| if (check.local == owner or (heap and check.elements)) return true;
        if (!site.fill) return false;
        return heap or self.writesSlot(owner);
    }
    /// Whether any check or share needs the root protocol.
    pub fn active(self: Plan) bool {
        for (self.checked) |flag| if (flag) return true;
        for (self.sites) |site| if (site.shares.len != 0 or site.read_captures.len != 0) return true;
        return false;
    }
};

/// The temporary retaining a dictionary key until a nested write-back.
pub fn entryKey(place: Place, operands: []const ?[]const ownership.Source) ?usize {
    const read = switch (place.step) {
        .entry => place.base,
        .entry_field => place.read,
        else => return null,
    };
    const stack = operands[read] orelse return null;
    if (stack.len == 0) return null;
    const key = stack[stack.len - 1];
    return if (key.origin == .local and key.part == .whole and key.local != none) key.local else null;
}

/// What planning reads.
pub const Input = struct {
    program: bytecode.Program,
    function: bytecode.Function,
    states: []const ?[]const typed.Type,
    analysis: ownership.Analysis,
    /// Whether the plan marks the stage 2 copy transfers shared itself.
    shares: bool = true,
};

/// Whether a value of `ty` is one copy-on-write payload: a list, dictionary,
/// set or byte buffer. A text and a byte string are immutable, and a `class`
/// is a shared reference.
pub fn payloadType(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    if (!record.isCollection()) return false;
    return switch (record.collection.kind) {
        .list, .dictionary => true,
        .string => false,
        .bytes => !typed.isByteString(record),
    };
}

/// A local id as a 32-bit index.
fn li(slot: typed.LocalId) u32 {
    return @intCast(@backingInt(slot));
}

/// The planning state of one function.
const Planner = struct {
    a: std.mem.Allocator,
    input: Input,
    places: []?Place,
    aliases: []u32,
    unique: []std.ArrayList(Unique),
    sites: []Site,
    /// Per instruction: whether a check runs there, and whether a branch
    /// names it.
    marks: Marks,

    fn code(self: *const Planner) []const bytecode.Instruction {
        return self.input.function.scope.instructions;
    }
    fn reachable(self: *const Planner, pc: usize) bool {
        return pc < self.input.states.len and self.input.states[pc] != null;
    }
    fn local(self: *const Planner, index: u32) typed.Local {
        return self.input.function.scope.locals[index];
    }
    fn payload(self: *const Planner, index: u32) bool {
        return payloadType(self.input.program, self.local(index).ty);
    }
    fn role(self: *const Planner, index: u32) ownership.Role {
        return self.input.analysis.roles[index];
    }
    /// The local whose payload `index` names, through whole aliases.
    fn resolve(self: *const Planner, index: u32) u32 {
        var at = index;
        var guard: usize = 0;
        while (guard <= self.aliases.len and at < self.aliases.len and self.aliases[at] != none) : (guard += 1) at = self.aliases[at];
        return at;
    }
    fn addUnique(self: *Planner, pc: usize, unique: Unique) Error!void {
        for (self.unique[pc].items) |existing| if (existing.local == unique.local and existing.alias == unique.alias) return;
        try self.unique[pc].append(self.a, unique);
        self.marks.checked[pc] = true;
    }
};

/// Per-instruction flags planning builds.
const Marks = struct { checked: []bool, targets: []bool };

/// Plan the copy-on-write code of one function.
pub fn plan(a: std.mem.Allocator, input: Input) Error!Plan {
    const code = input.function.scope.instructions;
    const count = input.function.scope.locals.len;
    var planner: Planner = .{
        .a = a,
        .input = input,
        .places = try a.alloc(?Place, count),
        .aliases = try a.alloc(u32, count),
        .unique = try a.alloc(std.ArrayList(Unique), code.len),
        .sites = try a.alloc(Site, code.len),
        .marks = .{ .checked = try a.alloc(bool, code.len), .targets = try branchTargets(a, code) },
    };
    @memset(planner.places, null);
    @memset(planner.aliases, none);
    for (planner.unique) |*list| list.* = .empty;
    @memset(planner.sites, .{});
    @memset(planner.marks.checked, false);
    for (0..count) |index| try findPlace(&planner, @intCast(index));
    const written = try keepWritten(&planner);
    const loops = try placeStageTwo(&planner);
    try placePlaces(&planner);
    try placeShares(&planner, written);
    try placeReadOperands(&planner);
    for (planner.sites, planner.unique) |*site, *list| site.unique = try list.toOwnedSlice(a);
    return .{ .places = planner.places, .aliases = planner.aliases, .sites = planner.sites, .loops = loops, .checked = planner.marks.checked };
}

/// Whether local `index` is one the compiler made to name a place, not a
/// binding the program spelled or a loop variable.
pub fn temporary(function: bytecode.Function, index: u32) bool {
    if (index < function.signature.parameter_count) return false;
    const local = function.scope.locals[index];
    if (local.origin == .iteration) return false;
    return local.name.len == 0 or local.name[0] == '<';
}

/// A hidden managed iteration source preserves header identity, unlike a value snapshot.
pub fn iterationOwner(function: bytecode.Function, index: usize) bool {
    if (index >= function.scope.locals.len or !temporary(function, @intCast(index))) return false;
    for (function.scope.instructions) |instruction| {
        if (instruction.op != .buffer_operation) continue;
        const operation = instruction.op.buffer_operation;
        if (operation.kind == .iteration_check and li(operation.owner) == index) return true;
    }
    return false;
}

/// The one reachable store into `index`, or null. A terminal drop only ends
/// the place lifetime; named-argument evaluation emits that cleanup explicitly.
fn singleStore(planner: *const Planner, index: u32) ?usize {
    var found: ?usize = null;
    var ended = false;
    for (planner.code(), 0..) |instruction, pc| {
        if (!planner.reachable(pc)) continue;
        switch (instruction.op) {
            .store_local, .move_local => |slot| if (li(slot) == index) {
                if (instruction.op != .store_local or found != null) return null;
                found = pc;
            },
            .drop_local => |slot| if (li(slot) == index) {
                if (found == null) return null;
                ended = true;
            },
            .load_local => |slot| if (li(slot) == index and ended) return null,
            .switch_variant => |dispatch| for (dispatch.arms) |arm| if (arm.slot) |slot| if (li(slot) == index) return null,
            .ref_local => |slot| if (li(slot) == index) return null,
            else => {},
        }
    }
    return found;
}

/// Record local `index` as a place or a whole alias when it is a compiler
/// temporary filled once, in one straight run, by a read out of another local.
fn findPlace(planner: *Planner, index: u32) Error!void {
    const function = planner.input.function;
    if (!temporary(function, index) or !planner.payload(index)) return;
    const fill = singleStore(planner, index) orelse return;
    var pc = fill;
    var fields: usize = 0;
    while (pc > 0) {
        pc -= 1;
        if (!planner.reachable(pc) or planner.marks.targets[pc + 1]) return;
        switch (planner.code()[pc].op) {
            .get_field => fields += 1,
            .wrap_domain, .unwrap_domain => {},
            else => break,
        }
    }
    const base: u32 = @intCast(pc);
    const found: ?Place = switch (planner.code()[pc].op) {
        .load_local => |slot| if (fields == 0) {
            planner.aliases[index] = li(slot);
            return;
        } else .{ .parent = li(slot), .step = .field, .base = base, .fill = @intCast(fill) },
        .buffer_operation => |operation| if (operation.kind == .read and listType(planner, li(operation.owner))) .{ .parent = li(operation.owner), .step = .element, .base = base, .fill = @intCast(fill) } else null,
        .get_index => |access| if (dictionaryType(planner.input.program, access.ty)) try entryParent(planner, pc, fill) else try arrayParent(planner, pc, fill),
        else => null,
    };
    if (found) |place| {
        var answer = place;
        if (place.step == .field) if (boxedOwner(planner, place.parent, fill)) |box| {
            answer.box = box;
        };
        planner.places[index] = answer;
    }
}

/// A fixed-array access stays within its root's inline value. Follow its
/// operand's original read, retaining any outer list or dictionary place.
fn arrayParent(planner: *const Planner, pc: usize, fill: usize) Error!?Place {
    const states = planner.input.states[pc] orelse return null;
    const operands = planner.input.analysis.operands[pc] orelse return null;
    if (states.len < 2 or operands.len < 2) return null;
    const ty = states[states.len - 2];
    if (!arrayType(planner.input.program, ty)) return null;
    const source = operands[operands.len - 2];
    if (source.origin != .local or source.read == none or source.local == none) return null;
    const read = planner.code()[source.read].op;
    if (read == .buffer_operation and read.buffer_operation.kind == .read and listType(planner, source.local))
        return .{ .parent = source.local, .step = .element, .base = source.read, .fill = @intCast(fill) };
    if (read != .load_local) return null;
    const depth = (planner.input.states[source.read] orelse return null).len;
    for (source.read + 1..pc) |at| {
        const stack = planner.input.states[at] orelse continue;
        const op = planner.code()[at].op;
        if (op == .get_index and stack.len == depth + 2 and dictionaryType(planner.input.program, op.get_index.ty))
            return entryParent(planner, at, fill);
    }
    return .{ .parent = source.local, .step = .field, .base = source.read, .fill = @intCast(fill) };
}

const BoxOwner = struct { owner: u32, ty: typed.Type };

fn boxedOwner(planner: *const Planner, parent: u32, fill: usize) ?BoxOwner {
    const code = planner.code();
    var store = fill;
    while (store > 2) {
        store -= 1;
        if (code[store].op != .store_local or li(code[store].op.store_local) != parent) continue;
        if (code[store - 1].op != .get_field or code[store - 1].op.get_field != 0) return null;
        if (code[store - 2].op != .load_local) return null;
        const hidden = li(code[store - 2].op.load_local);
        const ty = planner.local(hidden).ty;
        if (!ty.isAggregate() or !planner.input.program.records[ty.recordIndex()].collection.box) return null;
        var switch_pc = store - 2;
        while (switch_pc > 0) {
            switch_pc -= 1;
            if (code[switch_pc].op != .switch_variant) continue;
            for (code[switch_pc].op.switch_variant.arms) |arm| if (arm.slot) |slot| if (li(slot) == hidden) {
                if (switch_pc == 0) return null;
                if (code[switch_pc - 1].op != .load_local) return null;
                return .{ .owner = li(code[switch_pc - 1].op.load_local), .ty = ty };
            };
        }
        return null;
    }
    return null;
}

/// The entry place a dictionary read at `pc` begins, when its dictionary
/// operand is a whole local's value its own `load_local` pushed.
fn entryParent(planner: *const Planner, pc: usize, fill: usize) Error!?Place {
    const operands = planner.input.analysis.operands[pc] orelse return null;
    if (operands.len < 2) return null;
    const source = operands[operands.len - 2];
    if (source.origin != .local or source.local == none or source.read == none) return null;
    switch (planner.code()[source.read].op) {
        .load_local => |slot| if (li(slot) != source.local) return null,
        else => return null,
    }
    if (source.part == .whole) return .{ .parent = source.local, .step = .entry, .base = @intCast(pc), .fill = @intCast(fill) };
    if (source.part != .field) return null;
    var end = source.read + 1;
    while (end < pc) : (end += 1) switch (planner.code()[end].op) {
        .get_field, .wrap_domain, .unwrap_domain => {},
        else => break,
    };
    if (end == source.read + 1) return null;
    return .{ .parent = source.local, .step = .entry_field, .base = source.read, .read = @intCast(pc), .fields_end = @intCast(end), .fill = @intCast(fill) };
}

/// Where the payload a place is read out of is made unique: before the load
/// that pushes a dictionary, before the read that loads a list itself.
fn rootPc(planner: *const Planner, found: Place) usize {
    if (found.step == .entry_field) return found.base;
    if (found.step != .entry) return found.base;
    const operands = planner.input.analysis.operands[found.base].?;
    return operands[operands.len - 2].read;
}

/// Per instruction, whether a branch names it.
fn branchTargets(a: std.mem.Allocator, code: []const bytecode.Instruction) Error![]bool {
    const targets = try a.alloc(bool, code.len + 1);
    @memset(targets, false);
    for (code) |instruction| switch (instruction.op) {
        .jump, .jump_if_false => |target| targets[target] = true,
        .try_result => |propagate| targets[propagate.error_target] = true,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            targets[arm.target] = true;
        },
        else => {},
    };
    return targets;
}

fn listType(planner: *const Planner, index: u32) bool {
    const ty = planner.local(index).ty;
    if (!ty.isAggregate()) return false;
    const record = planner.input.program.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .list;
}

fn dictionaryType(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    const record = program.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .dictionary;
}

fn arrayType(program: bytecode.Program, ty: typed.Type) bool {
    return ty.isAggregate() and program.records[ty.recordIndex()].shape.array != null;
}

/// Keep only the places a write goes through: the receiver of a writing
/// operation, and every place or alias another written place is read out of.
fn keepWritten(planner: *Planner) Error![]const bool {
    const written = try planner.a.alloc(bool, planner.places.len);
    @memset(written, false);
    for (planner.code(), 0..) |instruction, pc| {
        if (!planner.reachable(pc)) continue;
        switch (instruction.op) {
            .buffer_operation => |operation| if (writes(operation.kind)) {
                written[li(operation.owner)] = true;
            },
            else => {},
        }
    }
    // Spliced mut parameters may write only through a later call. They are
    // writing aliases too, even without a buffer operation in this body.
    for (planner.input.analysis.cows) |site| written[site.via] = true;
    var changed = true;
    while (changed) {
        changed = false;
        for (0..written.len) |index| {
            if (!written[index]) continue;
            const parent = if (planner.places[index]) |found| found.parent else if (planner.aliases[index] != none) planner.aliases[index] else continue;
            if (written[parent]) continue;
            written[parent] = true;
            changed = true;
        }
    }
    for (planner.places, written) |*found, flag| if (!flag) {
        found.* = null;
    };
    return written;
}

/// Whether a buffer operation changes the collection it is called on.
fn writes(kind: buffer_operations.Kind) bool {
    return kind.writesReceiver() or kind == .set_add or kind == .set_discard;
}

/// The stage 2 sites: an unhoisted check where it stands, a hoisted one on its
/// loop's entry edges. A write through a place is covered by the place's own
/// fill, and an element site by the fill of the place its read begins.
fn placeStageTwo(planner: *Planner) Error!Loops {
    const a = planner.a;
    const n = planner.code().len;
    var entries = try a.alloc(std.ArrayList(Hoisted), n);
    for (entries) |*list| list.* = .empty;
    const back = try loopBacks(planner);
    for (planner.input.analysis.cows) |site| {
        if (!site.needed or !planner.reachable(site.pc)) continue;
        if (site.hoisted != none) {
            if (planner.places[site.local] == null) try addHoisted(a, &entries[site.hoisted], .{ .local = site.local, .elements = site.elements });
            continue;
        }
        if (site.elements) continue;
        try stageTwoRoot(planner, site);
    }
    const lists = try a.alloc([]const Hoisted, n);
    for (entries, lists) |*list, *out| out.* = try list.toOwnedSlice(a);
    return .{ .entries = lists, .back = back };
}

fn addHoisted(a: std.mem.Allocator, list: *std.ArrayList(Hoisted), hoisted: Hoisted) Error!void {
    for (list.items) |existing| if (existing.local == hoisted.local and existing.elements == hoisted.elements) return;
    try list.append(a, hoisted);
}

/// One unhoisted stage 2 check of a root: the written local itself, or the
/// root a whole alias names.
fn stageTwoRoot(planner: *Planner, site: ownership.Cow) Error!void {
    const via = site.via;
    if (planner.places[via] != null) return;
    const root = planner.resolve(via);
    if (planner.places[root] != null or !planner.payload(root)) return;
    if (planner.role(root) == .mut_param and ownership.uniqueParameter(planner.input.function, root)) return;
    switch (planner.code()[site.pc].op) {
        .buffer_operation => |operation| if (!writes(operation.kind) and !rootNeedsCheck(planner, li(operation.owner))) return,
        else => {},
    }
    try planner.addUnique(site.pc, .{ .local = root, .alias = if (via != root) via else none });
}

/// Per instruction, the pc of the last jump back to it, or `none`.
fn loopBacks(planner: *const Planner) Error![]u32 {
    const back = try planner.a.alloc(u32, planner.code().len);
    @memset(back, none);
    for (planner.code(), 0..) |instruction, pc| switch (instruction.op) {
        .jump => |target| if (target <= pc and (back[target] == none or back[target] < pc)) {
            back[target] = @intCast(pc);
        },
        else => {},
    };
    return back;
}

/// The checks of every written place: its fill, and the payload its base read
/// comes out of when no stage 2 check already covers it.
fn placePlaces(planner: *Planner) Error!void {
    for (planner.places) |maybe| {
        const found = maybe orelse continue;
        if (found.step == .entry_field) {
            planner.sites[found.base].unique_field = found;
            planner.marks.checked[found.base] = true;
        }
        if (found.step == .element) planner.sites[found.base].capture = true;
        captureArrayIndices(planner, found);
        if (!elementsHoisted(planner, found)) {
            planner.sites[found.fill].fill = true;
            planner.marks.checked[found.fill] = true;
        }
        if (found.step == .field or found.step == .entry_field) continue;
        const root = planner.resolve(found.parent);
        if (planner.places[root] != null or !planner.payload(root)) continue;
        if (!rootNeedsCheck(planner, root) or rootCovered(planner, found, root)) continue;
        try planner.addUnique(rootPc(planner, found), .{ .local = root, .alias = if (found.parent != root) found.parent else none });
    }
}

/// Preserve each inline-array index across later index expressions in the
/// same path. The operand stack distinguishes the path from key evaluation.
fn captureArrayIndices(planner: *Planner, found: Place) void {
    const begin = found.base + 1;
    const first = planner.input.states[begin] orelse return;
    for (begin..found.fill) |pc| {
        const stack = planner.input.states[pc] orelse continue;
        const op = planner.code()[pc].op;
        if (op != .get_index or !arrayType(planner.input.program, op.get_index.ty) or stack.len != first.len + 1) continue;
        planner.sites[pc].capture = true;
    }
}

/// Whether a stage 2 elements site at the place's base moved to a loop entry,
/// which makes every element unique there instead of at the fill.
fn elementsHoisted(planner: *const Planner, found: Place) bool {
    if (found.step != .element) return false;
    for (planner.input.analysis.cows) |site| {
        if (site.pc == found.base and site.elements and site.needed and site.hoisted != none) return true;
    }
    return false;
}

/// Whether a stage 2 root site already makes `root` unique for the place:
/// at its base read, or at the load filling the whole alias it reads through.
fn rootCovered(planner: *const Planner, found: Place, root: u32) bool {
    for (planner.input.analysis.cows) |site| {
        if (site.local != root or site.elements or !site.needed) continue;
        if (site.pc == found.base) return true;
        if (found.parent != root and aliasFill(planner, found.parent) == site.pc) return true;
    }
    return false;
}

/// The `load_local` that fills whole alias `index`.
fn aliasFill(planner: *const Planner, index: u32) ?usize {
    const store = singleStore(planner, index) orelse return null;
    return if (store > 0) store - 1 else null;
}

/// The stage 3a hook's stand-in: every transfer the ownership analysis calls a
/// copy shares its payloads, except a store into a compiler temporary, which
/// names a place or is only read. A match binding shares the payload of the
/// scrutinee it binds.
fn placeShares(planner: *Planner, written: []const bool) Error!void {
    const a = planner.a;
    const lists = try a.alloc(std.ArrayList(u8), planner.sites.len);
    for (lists) |*list| list.* = .empty;
    for (planner.input.analysis.transfers) |transfer| {
        if (transfer.class != .copy) continue;
        if (!planner.input.shares) {
            const op = planner.code()[transfer.pc].op;
            if (op != .store_local) continue;
            const local = li(op.store_local);
            // A read capture can outlive a callback that mutates its source.
            // Unlike a pending writing place, it needs an independent value.
            if (!temporary(planner.input.function, local)) continue;
            if (written[local] or !planner.payload(local)) continue;
            if (iterationOwner(planner.input.function, local)) continue;
        }
        const operands = planner.input.analysis.operands[transfer.pc] orelse continue;
        const types = planner.input.states[transfer.pc] orelse continue;
        switch (planner.code()[transfer.pc].op) {
            .store_local => |slot| if (planner.input.shares and temporary(planner.input.function, li(slot))) continue,
            .call, .invoke => continue,
            .switch_variant => {
                try addDepth(a, &lists[transfer.pc], 0);
                continue;
            },
            else => {},
        }
        for (operands, types, 0..) |operand, ty, position| {
            if (!operand.eql(transfer.source) or !ty.isAggregate()) continue;
            try addDepth(a, &lists[transfer.pc], @intCast(operands.len - 1 - position));
        }
    }
    for (lists, planner.sites) |*list, *site| site.shares = try list.toOwnedSlice(a);
}

fn addDepth(a: std.mem.Allocator, list: *std.ArrayList(u8), depth: u8) Error!void {
    for (list.items) |existing| if (existing == depth) return;
    try list.append(a, depth);
}

/// Dictionary reads keep their receiver on the operand stack. Capture
/// it before a key callback, at the first state holding that dictionary value.
fn placeReadOperands(planner: *Planner) Error!void {
    if (planner.input.shares) return;
    const a = planner.a;
    const lists = try a.alloc(std.ArrayList(u8), planner.sites.len);
    for (lists) |*list| list.* = .empty;
    for (planner.code(), 0..) |instruction, pc| {
        if (!planner.reachable(pc) or instruction.op != .get_index) continue;
        const ty = instruction.op.get_index.ty;
        if (!dictionaryType(planner.input.program, ty)) continue;
        if (writtenRead(planner, pc)) continue;
        const operands = planner.input.analysis.operands[pc] orelse continue;
        if (operands.len < 2) return error.InternalError;
        const position = operands.len - 2;
        const source = operands[position];
        if (source.origin != .local or source.read == none) continue;
        var capture: ?usize = null;
        var callback = false;
        for (source.read + 1..pc) |at| {
            const stack = planner.input.states[at] orelse continue;
            if (capture == null and position < stack.len and stack[position] == ty) capture = at;
            switch (planner.code()[at].op) {
                .call, .invoke => callback = true,
                .buffer_operation => |operation| if (writes(operation.kind)) {
                    callback = true;
                },
                else => {},
            }
        }
        if (callback) if (capture) |at| {
            const stack = planner.input.states[at].?;
            try addDepth(a, &lists[at], @intCast(stack.len - 1 - position));
        };
    }
    for (lists, planner.sites) |*list, *site| site.read_captures = try list.toOwnedSlice(a);
}

/// A dictionary lookup selecting a pending writing path retains that path's
/// identity protocol instead of making an independent read snapshot.
fn writtenRead(planner: *const Planner, pc: usize) bool {
    for (planner.places) |maybe| if (maybe) |place| {
        if (place.base == pc or place.read == pc) return true;
    };
    return false;
}

fn rootNeedsCheck(planner: *const Planner, root: u32) bool {
    return planner.role(root) == .owned or
        (planner.role(root) == .mut_param and !ownership.uniqueParameter(planner.input.function, root));
}

fn testSingleStore(a: std.mem.Allocator, ops: []const Op) !?usize {
    const code = try a.alloc(bytecode.Instruction, ops.len);
    defer a.free(code);
    const states = try a.alloc(?[]const typed.Type, ops.len);
    defer a.free(states);
    for (code, ops, states) |*instruction, op, *state| {
        instruction.* = .{ .span = .{ .start = 0, .end = 0 }, .op = op };
        state.* = &.{};
    }
    // This query reads only the instruction stream and reachability table.
    var planner: Planner = undefined;
    planner.input.function.scope.instructions = code;
    planner.input.states = states;
    return singleStore(&planner, 0);
}

// spec-case: COW-MUT-ARGUMENT-1
test "COW-MUT-ARGUMENT-1 named place permits terminal cleanup but rejects a later read" {
    const local: typed.LocalId = @fromBackingInt(@intCast(0));
    try std.testing.expectEqual(@as(?usize, 0), try testSingleStore(std.testing.allocator, &.{ .{ .store_local = local }, .{ .load_local = local }, .{ .drop_local = local } }));
    try std.testing.expectEqual(@as(?usize, null), try testSingleStore(std.testing.allocator, &.{ .{ .store_local = local }, .{ .drop_local = local }, .{ .load_local = local } }));
    try std.testing.expectEqual(@as(?usize, null), try testSingleStore(std.testing.allocator, &.{ .{ .drop_local = local }, .{ .store_local = local } }));
    try std.testing.expectEqual(@as(?usize, null), try testSingleStore(std.testing.allocator, &.{ .{ .store_local = local }, .{ .drop_local = local }, .{ .store_local = local } }));
}
