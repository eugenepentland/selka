//! Loop range facts (`QBE-LOOP-FACTS-1`): what one counted innermost loop
//! lets the native emitter prove about its bounds and overflow checks, and the
//! runtime guard under which a check-free copy of the loop is exact.
//!
//! The analysis reads the checked bytecode of one function. A candidate loop is
//! an innermost loop in the shape every `for i in range(...)`, `for x in xs`,
//! `enumerate(...)` and `while i < n: ...; i = i + step` lowers to:
//!
//!     head:     load_local counter
//!               load_local bound | push_i64 bound
//!               cmp_i64 lt | le
//!               jump_if_false exit
//!               ... body ...
//!     back - 1: store_local counter       (value: counter + step)
//!     back:     jump head                  (exit = back + 1)
//!
//! Every instruction of the loop must come from a short allow-list: no call,
//! no allocation, no collection operation other than a length, an element read
//! or write and an iteration check — plus at most one append of a plain scalar,
//! in a straight-line body, to a list type the loop otherwise never touches (a
//! comprehension's fill). Such a loop changes the length of no collection it
//! reads and moves no element storage, so every list and byte string it reads
//! keeps its length and its storage address for as long as it runs, and the
//! appended list keeps its storage while its spare capacity lasts.
//!
//! A symbolic pass then names the value of every operand and local in the
//! body: constants, locals the body never writes (the same value throughout),
//! the counter (between its entry value and the bound), accumulators (a local
//! whose one write adds a bounded increment), sums, differences and products
//! of those, collection lengths, and elements read from a stable collection at
//! an invariant position of a type the loop never writes. From those it
//! derives:
//!
//! * index facts: an index affine in the counter (`i`, `i + c`, `k - i`,
//!   `i * w + j` with `i`, `w` invariant) is in bounds on every iteration when
//!   its extreme values are, which one comparison of each extreme before the
//!   loop decides; a proven index also makes the frontend's negative-index
//!   normalization branch dead;
//! * overflow facts: once every leaf value the loop computes from is bounded by
//!   `2^bits` in magnitude, a sum or product of a known degree is bounded too,
//!   so its overflow check cannot fire; the guard checks the leaves;
//! * iteration facts: a `for x in xs` loop's length checks hold throughout
//!   when they hold on entry, because nothing in the loop can resize `xs`;
//! * hoisting facts: an invariant element read (the row `c[i]` of `c[i][j]`)
//!   and a stable collection's storage address are the same on every
//!   iteration, so the guard reads them once.
//!
//! The emitter (`qbe_loop_version.zig`) evaluates the guard where the loop is
//! entered, runs a copy of the loop lowered under the facts when it holds, and
//! otherwise runs the original loop, unchanged, so every trap still fires at
//! the same iteration with the same message and trace.
//!
//! API for consumers (the emitter here; an LLVM adapter pass could read the
//! same facts): `plan` returns a `Plan`; `Plan.at(pc)` names the loop whose
//! header is at `pc`; `Loop.guard` is the ordered list of `Step`s, each over
//! `Plan.nodes`; `Loop.actions[pc - head]` is what one instruction of the
//! check-free copy may assume.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");

/// Failures while planning; an unsupported shape is never an error, only an
/// unversioned loop.
pub const Error = error{OutOfMemory};

/// Index of one symbolic value in `Plan.nodes`.
pub const NodeId = u32;

/// A value named by a local, the counter, or an integer type's range.
pub const Leaf = struct {
    kind: enum {
        /// A local the loop never writes: one value at every point of the loop.
        local,
        /// The value a local the loop writes holds when the loop is entered.
        /// Only guard steps name it.
        entry,
        /// A local the loop writes, as it stood at the top of this iteration.
        carried,
        /// The loop counter at this point of an iteration, before its update.
        counter,
        /// An integer whose type bounds its magnitude by `2^slot`.
        narrow,
    },
    /// The local slot (or, for `narrow`, the bit width; unused for `counter`).
    slot: u32 = 0,
};

/// An exact integer operation over two values; the guard excludes wrap. A
/// `quotient` is a division by a nonzero constant, which keeps its own checks
/// and is bounded by its dividend; no guard computes one.
pub const Operation = struct { operator: enum { add, sub, mul, quotient }, left: NodeId, right: NodeId };

/// An element read the guard can perform once: the stable receiver, the
/// invariant position, and the receiver's collection type (for its stride).
pub const Element = struct { receiver: NodeId, index: NodeId, collection: typed.Type };

/// One symbolic value. Nodes are interned, so equal values share an id.
pub const Node = union(enum) {
    /// Nothing is known.
    unknown,
    /// A literal.
    constant: i64,
    leaf: Leaf,
    /// The element count of a stable collection.
    length: NodeId,
    /// An element the loop reads at an invariant position of a collection
    /// whose slots it never writes.
    element: Element,
    operation: Operation,
    /// The boolean `value < 0`.
    negative: NodeId,
};

/// One condition the guard evaluates before choosing the check-free copy.
/// Each is a plain comparison of values computed from locals and stable
/// collections; the first that fails selects the original loop.
pub const Step = union(enum) {
    /// `-2^bits <= value <= 2^bits`, with `bits` from the loop.
    bounded: NodeId,
    /// `value >= minimum`.
    at_least: struct { value: NodeId, minimum: i64 },
    /// `value <relation> limit`.
    order: Order,
    /// `bound > entry` and `bound - entry >= minimum`, computed without
    /// wrapping: the counter has at least that many values to run through.
    spans: struct { entry: NodeId, bound: NodeId, minimum: u32 },
    /// The list's spare capacity, `capacity - length`, holds one element per
    /// iteration: at least `bound - entry`, plus one for an inclusive bound.
    room: struct { list: NodeId, entry: NodeId, bound: NodeId, inclusive: bool },
};

/// One comparison of a computed value against a limit.
pub const Order = struct {
    relation: enum {
        /// `value <= limit`, signed.
        at_most,
        /// `value < limit`, signed.
        below,
        /// `value < limit`, unsigned: `0 <= value < limit`.
        within,
        /// `value == limit`.
        equal,
    },
    value: NodeId,
    limit: NodeId,
};

/// What one instruction of the check-free copy may assume.
pub const Action = struct {
    /// Lower without the instruction's value guards: none can fail.
    unchecked: bool = false,
    /// The index operand is non-negative, so no from-end correction applies.
    nonnegative: bool = false,
    /// How the copy lowers the instruction beyond dropping its checks.
    effect: enum {
        none,
        /// A `jump_if_false` whose condition is false on every iteration.
        taken,
        /// An iteration check that holds on every iteration.
        settled,
        /// An append the list's spare capacity holds: a store and a length
        /// bump, with no capacity test and no growth path.
        presized,
    } = .none,
    /// The stable receiver whose element storage address the guard computed.
    receiver: ?NodeId = null,
    /// The element value the guard read in place of this read.
    value: ?NodeId = null,
    /// No path through the copy reaches the instruction: it lies behind a
    /// branch the guard proved always taken, so the copy omits it.
    dead: bool = false,
};

/// One loop the emitter versions.
pub const Loop = struct {
    /// Program counter of the header's counter load; every entry lands here.
    head: usize,
    /// Program counter of the back jump; the exit is `back + 1`.
    back: usize,
    /// Magnitude bound, in bits, every `bounded` step checks.
    bits: u6,
    /// Guard conditions in evaluation order.
    guard: []const Step,
    /// Per instruction `head..back`, what the check-free copy assumes.
    actions: []const Action,
};

/// Every versioned loop of one function and the values their guards name.
pub const Plan = struct {
    nodes: []const Node = &.{},
    loops: []const Loop = &.{},
    /// The loop whose header is at `pc`, if one is versioned.
    pub fn at(self: *const Plan, pc: usize) ?*const Loop {
        for (self.loops) |*loop| if (loop.head == pc) return loop;
        return null;
    }
};

/// What the analysis reads: the checked function, the program's type table and
/// the operand stack types at every instruction (null where unreachable).
pub const Input = struct {
    program: bytecode.Program,
    function: bytecode.Function,
    states: []const ?[]const typed.Type,
    /// Box projections can clone pinned children under value semantics.
    box_cow: bool = false,
};

/// Loop bodies longer than this many instructions are left alone. The copy
/// doubles their code, and in a body this long the checks are a small part of
/// the work: `nbody`'s 730-instruction pair loop ran 7% slower with an
/// unused copy beside it (the loop runs 4 times per entry) and no faster with
/// a used one.
pub const max_body = 200;
/// The fewest counter values between the entry value and the bound for which
/// the check-free copy runs. A shorter loop saves fewer checks than its guard
/// costs, and a check-free copy of a few iterations can become a library call
/// (`memmove`) that costs more than the loop did.
pub const min_span = 16;
/// The largest leaf magnitude a guard asks for, and the smallest it accepts
/// before giving a check up instead.
const widest_bits = 60;
const narrowest_bits = 20;

/// Whether `pc` is the +/-1 update at a structural counted-loop latch.
/// This is a performance hint only: it grants no range or unchecked authority.
pub fn inductionAt(code: []const bytecode.Instruction, pc: usize) bool {
    if (pc < 2 or pc >= code.len or code.len - pc <= 3) return false;
    const slot = switch (code[pc - 2].op) {
        .load_local => |local| local,
        else => return false,
    };
    const step = unitStep(code[pc - 1].op) orelse return false;
    const add = switch (code[pc].op) {
        .add_i64_checked => true,
        .sub_i64_checked => false,
        .binary_integer => |operation| if (operation.ty == .i64 and (operation.op == .add or operation.op == .sub)) operation.op == .add else return false,
        else => return false,
    };
    const upward = add == (step == 1);
    if (code[pc + 1].op != .store_local or code[pc + 1].op.store_local != slot) return false;
    const head = switch (code[pc + 2].op) {
        .jump => |target| target,
        else => return false,
    };
    if (head >= pc - 2 or pc - 2 - head <= 3) return false;
    if (code[head].op != .load_local or code[head].op.load_local != slot) return false;
    switch (code[head + 1].op) {
        .load_local, .push_i64, .push_integer => {},
        else => return false,
    }
    const predicate = switch (code[head + 2].op) {
        .cmp_i64 => |comparison| comparison,
        else => return false,
    };
    if (upward and predicate != .lt and predicate != .le) return false;
    if (!upward and predicate != .gt and predicate != .ge) return false;
    return code[head + 3].op == .jump_if_false and code[head + 3].op.jump_if_false == pc + 3;
}

fn unitStep(op: @FieldType(bytecode.Instruction, "op")) ?i64 {
    const value = switch (op) {
        .push_i64 => |literal| literal,
        .push_integer => |number| if (number.ty == .i64) std.math.cast(i64, number.value) orelse return null else return null,
        else => return null,
    };
    return if (value == 1 or value == -1) value else null;
}

/// Find and plan every versionable loop of one function.
pub fn plan(allocator: std.mem.Allocator, input: Input) Error!Plan {
    const code = input.function.scope.instructions;
    if (code.len != input.states.len) return .{};
    var interner: Interner = .{ .allocator = allocator };
    var loops: std.ArrayList(Loop) = .empty;
    for (code, 0..) |instruction, pc| {
        const head = switch (instruction.op) {
            .jump => |target| target,
            else => continue,
        };
        if (head >= pc or input.states[pc] == null) continue;
        var analyzer: Analyzer = .{ .allocator = allocator, .input = input, .nodes = &interner, .head = head, .back = pc };
        if (try analyzer.run()) |loop| try loops.append(allocator, loop);
    }
    return .{ .nodes = interner.list.items, .loops = try loops.toOwnedSlice(allocator) };
}

/// The interned node table shared by every loop of one function.
const Interner = struct {
    allocator: std.mem.Allocator,
    list: std.ArrayList(Node) = .empty,
    index: std.AutoHashMapUnmanaged(Node, NodeId) = .empty,
    fn intern(self: *Interner, node: Node) Error!NodeId {
        if (self.index.get(node)) |id| return id;
        const id: NodeId = @intCast(self.list.items.len);
        try self.list.append(self.allocator, node);
        try self.index.put(self.allocator, node, id);
        return id;
    }
};

/// The magnitude bound `|v| <= coefficient * X^degree` for a leaf bound `X`.
const Magnitude = struct {
    coefficient: u64,
    degree: u8,
    const one: Magnitude = .{ .coefficient = 1, .degree = 1 };
    fn sum(a: Magnitude, b: Magnitude) Magnitude {
        return .{ .coefficient = std.math.add(u64, a.coefficient, b.coefficient) catch std.math.maxInt(u64), .degree = @max(a.degree, b.degree) };
    }
    fn product(a: Magnitude, b: Magnitude) Magnitude {
        return .{ .coefficient = std.math.mul(u64, a.coefficient, b.coefficient) catch std.math.maxInt(u64), .degree = a.degree +| b.degree };
    }
    /// Whether every value this bounds fits a signed 64-bit integer when
    /// `X = 2^bits`: `coefficient * 2^(bits * degree) <= 2^63 - 1`.
    fn fits(self: Magnitude, bits: u6) bool {
        const shift = @as(u32, bits) * self.degree;
        if (shift >= 63) return false;
        const room = (@as(u64, 1) << @intCast(63 - shift)) - 1;
        return self.coefficient <= room;
    }
    /// The widest leaf bound at which this still fits, or null below the narrowest.
    fn widest(self: Magnitude) ?u6 {
        var bits: u6 = widest_bits;
        while (bits >= narrowest_bits) : (bits -= 1) if (self.fits(bits)) return bits;
        return null;
    }
};

/// Symbolic stack and locals at one instruction.
const State = struct {
    stack: []NodeId,
    locals: []NodeId,
};

/// A checked `+ - *` the copy may lower unchecked when its bound fits.
const Arithmetic = struct { pc: usize, value: NodeId };

/// Per-local write facts of one loop body.
const Writes = struct {
    /// Whether the body stores the local.
    written: []bool = &.{},
    /// How many store instructions the body has for the local.
    stores: []u32 = &.{},
    /// The bounded increment of an accumulator's one write.
    increments: []?NodeId = &.{},
    /// Collection types whose element slots the body writes.
    elements: std.ArrayList(typed.Type) = .empty,
    /// The list type the body appends to, and how many appends it has.
    appended: ?typed.Type = null,
    appends: u32 = 0,
};

/// The counter's shape: its local, bound, comparison and step.
const Counter = struct {
    slot: u32 = 0,
    bound: NodeId = 0,
    inclusive: bool = false,
    step: NodeId = 0,
};

/// Analysis of one candidate loop.
const Analyzer = struct {
    allocator: std.mem.Allocator,
    input: Input,
    nodes: *Interner,
    head: usize,
    back: usize,
    counter: Counter = .{},
    writes: Writes = .{},
    states: []?State = &.{},
    actions: []Action = &.{},
    requirements: std.ArrayList(Step) = .empty,
    arithmetic: std.ArrayList(Arithmetic) = .empty,
    /// Set when the body does not have the stack discipline the pass assumes.
    broken: bool = false,

    fn code(self: *const Analyzer) []const bytecode.Instruction {
        return self.input.function.scope.instructions;
    }
    fn localType(self: *const Analyzer, slot: u32) typed.Type {
        return self.input.function.scope.locals[slot].ty;
    }
    fn node(self: *Analyzer, value: Node) Error!NodeId {
        return self.nodes.intern(value);
    }
    fn get(self: *const Analyzer, id: NodeId) Node {
        return self.nodes.list.items[id];
    }
    fn fail(self: *Analyzer) void {
        self.broken = true;
    }
    fn leaf(self: *Analyzer, kind: @FieldType(Leaf, "kind"), slot: u32) Error!NodeId {
        return self.node(.{ .leaf = .{ .kind = kind, .slot = slot } });
    }
    fn constant(self: *Analyzer, value: i64) Error!NodeId {
        return self.node(.{ .constant = value });
    }
    fn isLeaf(self: *const Analyzer, id: NodeId, kind: @FieldType(Leaf, "kind")) bool {
        return switch (self.get(id)) {
            .leaf => |value| value.kind == kind,
            else => false,
        };
    }
    fn constantOf(self: *const Analyzer, id: NodeId) ?i64 {
        return switch (self.get(id)) {
            .constant => |value| value,
            else => null,
        };
    }
    /// `left <operator> right`, with the identities `x + 0`, `0 + x` and
    /// `x - 0` folded so a guard compares a plain local where it can.
    fn operate(self: *Analyzer, operator: @FieldType(Operation, "operator"), left: NodeId, right: NodeId) Error!NodeId {
        if (operator != .mul and self.constantOf(right) == 0) return left;
        if (operator == .add and self.constantOf(left) == 0) return right;
        return self.node(.{ .operation = .{ .operator = operator, .left = left, .right = right } });
    }

    /// Plan the loop, or return null when its shape or contents rule it out
    /// or when the copy would prove nothing.
    fn run(self: *Analyzer) Error!?Loop {
        if (self.back - self.head > max_body or self.back < self.head + 5) return null;
        if (!try self.header()) return null;
        if (!try self.contents()) return null;
        if (!self.entered()) return null;
        if (!try self.evaluate()) return null;
        return self.finish();
    }

    /// The four header instructions and the counter's store before the back
    /// jump.
    fn header(self: *Analyzer) Error!bool {
        const all = self.code();
        const header_state = self.input.states[self.head] orelse return false;
        if (header_state.len != 0) return false;
        self.counter.slot = switch (all[self.head].op) {
            .load_local => |slot| slotOf(slot),
            else => return false,
        };
        if (self.localType(self.counter.slot) != .i64) return false;
        self.counter.inclusive = switch (all[self.head + 2].op) {
            .cmp_i64 => |predicate| switch (predicate) {
                .lt => false,
                .le => true,
                else => return false,
            },
            else => return false,
        };
        const exit = switch (all[self.head + 3].op) {
            .jump_if_false => |target| target,
            else => return false,
        };
        const store = switch (all[self.back - 1].op) {
            .store_local => |slot| slotOf(slot),
            else => return false,
        };
        return exit == self.back + 1 and store == self.counter.slot;
    }

    /// The allow-list, the body's own jumps, and the bound's invariance.
    fn contents(self: *Analyzer) Error!bool {
        const all = self.code();
        const locals = self.input.function.scope.locals.len;
        self.writes.written = try self.allocator.alloc(bool, locals);
        @memset(self.writes.written, false);
        self.writes.stores = try self.allocator.alloc(u32, locals);
        @memset(self.writes.stores, 0);
        for (all[self.head .. self.back + 1], self.head..) |instruction, pc| {
            if (self.input.states[pc] == null) return false;
            if (!try self.allowed(pc, instruction.op)) return false;
            switch (instruction.op) {
                .store_local => |slot| {
                    self.writes.written[slotOf(slot)] = true;
                    self.writes.stores[slotOf(slot)] += 1;
                },
                // Inside the body every jump goes forward; only the back jump
                // returns to the header, and nothing skips the counter's
                // update by jumping straight to it.
                .jump, .jump_if_false => |target| if (pc != self.back and (target <= pc or target == self.back)) return false,
                else => {},
            }
        }
        if (self.writes.stores[self.counter.slot] != 1) return false;
        if (!self.presizable()) return false;
        switch (all[self.head + 1].op) {
            .load_local => |slot| {
                if (self.writes.written[slotOf(slot)]) return false;
                if (self.localType(slotOf(slot)) != .i64) return false;
                self.counter.bound = try self.leaf(.local, slotOf(slot));
            },
            .push_i64 => |value| self.counter.bound = try self.constant(value),
            else => return false,
        }
        return true;
    }

    /// Whether the header is the loop's only entry: nothing outside the loop
    /// jumps into its body.
    fn entered(self: *const Analyzer) bool {
        for (self.code(), 0..) |instruction, pc| {
            if (pc >= self.head and pc <= self.back) continue;
            switch (instruction.op) {
                .jump, .jump_if_false => |target| if (self.within(target)) return false,
                .try_result => |propagate| if (self.within(propagate.error_target)) return false,
                .switch_variant => |dispatch| for (dispatch.arms) |arm| {
                    if (self.within(arm.target)) return false;
                },
                else => {},
            }
        }
        return true;
    }
    fn within(self: *const Analyzer, target: usize) bool {
        return target > self.head and target <= self.back;
    }

    /// Whether one instruction may appear in a versioned loop. The list admits
    /// nothing that calls guest code, allocates, or resizes a collection.
    fn allowed(self: *Analyzer, pc: usize, op: @FieldType(bytecode.Instruction, "op")) Error!bool {
        return switch (op) {
            .push_i64, .push_bool, .push_unit, .push_integer => true,
            .load_local, .store_local, .pop, .acknowledge => true,
            .jump, .jump_if_false => true,
            .cmp_i64, .cmp_bool, .cmp_enum, .cmp_domain, .not_bool => true,
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked => true,
            .wrap_domain, .unwrap_domain, .assert_true, .unary_float => true,
            .get_field => {
                if (!self.input.box_cow) return true;
                const stack = self.input.states[pc] orelse return false;
                if (stack.len == 0) return false;
                const owner = stack[stack.len - 1];
                return !owner.isAggregate() or !self.input.program.records[owner.recordIndex()].collection.box;
            },
            .binary_integer => |binary| binary.ty.isInteger(),
            .cast_integer, .neg_integer => |ty| ty.isInteger(),
            .array_length => |ty| !self.managed(ty),
            .make_record => |record| !self.managed(record.ty),
            .update_record => |update| !self.managed(update.ty),
            .get_index => |access| self.indexable(access.ty),
            .replace_index => |access| try self.elementWrite(access.ty, self.indexable(access.ty)),
            .buffer_operation => |operation| switch (operation.kind) {
                .length, .read, .iteration_check => self.sequence(self.localType(slotOf(operation.owner))),
                .write => try self.elementWrite(self.localType(slotOf(operation.owner)), self.sequence(self.localType(slotOf(operation.owner)))),
                .append => try self.appendable(self.localType(slotOf(operation.owner))),
                else => false,
            },
            else => false,
        };
    }
    /// Admit an append to a list of plain scalars (an integer, `bool` or
    /// float), noting its type: `presizable` then requires it to be the only
    /// append and the only access to lists of that type.
    fn appendable(self: *Analyzer, ty: typed.Type) Error!bool {
        if (!ty.isAggregate()) return false;
        const record = self.input.program.records[ty.recordIndex()];
        if (!record.isCollection() or record.collection.kind != .list) return false;
        if (!self.plainScalar(record.shape.buffer.?)) return false;
        self.writes.appended = ty;
        self.writes.appends += 1;
        return self.elementWrite(ty, true);
    }
    /// An integer, `bool`, or a domain over an integer (`float`): one word
    /// the collector never traces.
    fn plainScalar(self: *const Analyzer, ty: typed.Type) bool {
        if (ty.integer() != null or ty == .bool) return true;
        if (!ty.isAggregate()) return false;
        const record = self.input.program.records[ty.recordIndex()];
        const backing = record.shape.domain orelse return false;
        return !record.managed and backing.integer() != null;
    }
    /// A loop that appends runs the check-free copy only when the append is
    /// its one access to lists of that type — so nothing in the loop observes
    /// the growing length — and runs on every iteration: the body is straight
    /// line, with no jump that could skip it.
    fn presizable(self: *const Analyzer) bool {
        const appended = self.writes.appended orelse return true;
        if (self.writes.appends != 1) return false;
        for (self.code()[self.head + 4 .. self.back]) |instruction| switch (instruction.op) {
            .jump, .jump_if_false => return false,
            .get_index, .replace_index => |access| if (access.ty == appended) return false,
            .buffer_operation => |operation| {
                if (operation.kind != .append and self.localType(slotOf(operation.owner)) == appended) return false;
            },
            else => {},
        };
        return true;
    }
    /// Admit an element write when `admitted`, noting a collection type whose
    /// slots the loop then writes.
    fn elementWrite(self: *Analyzer, ty: typed.Type, admitted: bool) Error!bool {
        if (admitted and self.managed(ty)) try self.writes.elements.append(self.allocator, ty);
        return admitted;
    }
    fn managed(self: *const Analyzer, ty: typed.Type) bool {
        return ty.isAggregate() and self.input.program.records[ty.recordIndex()].managed;
    }
    /// A list or byte string: one header whose element storage the native
    /// layout reads in place. Text and dictionaries are excluded.
    fn sequence(self: *const Analyzer, ty: typed.Type) bool {
        if (!ty.isAggregate()) return false;
        const record = self.input.program.records[ty.recordIndex()];
        if (!record.isCollection()) return false;
        return record.collection.kind == .list or record.collection.kind == .bytes;
    }
    /// A receiver whose element read allocates nothing: a list, a byte string or
    /// a fixed array (not an enum-keyed table).
    fn indexable(self: *const Analyzer, ty: typed.Type) bool {
        if (!ty.isAggregate()) return false;
        const record = self.input.program.records[ty.recordIndex()];
        if (record.shape.array) |array| return array.key == null;
        return self.sequence(ty);
    }

    /// The symbolic pass over the body, in program order: every jump in the
    /// body goes forward, so each instruction's state is final when reached.
    fn evaluate(self: *Analyzer) Error!bool {
        const count = self.back - self.head + 1;
        self.states = try self.allocator.alloc(?State, count);
        @memset(self.states, null);
        self.actions = try self.allocator.alloc(Action, count);
        @memset(self.actions, .{});
        const locals = self.input.function.scope.locals.len;
        self.writes.increments = try self.allocator.alloc(?NodeId, locals);
        @memset(self.writes.increments, null);
        const first = try self.allocator.alloc(NodeId, locals);
        for (first, 0..) |*value, index| {
            const slot: u32 = @intCast(index);
            value.* = if (slot == self.counter.slot)
                try self.leaf(.counter, 0)
            else if (self.writes.written[index])
                try self.leaf(.carried, slot)
            else
                try self.leaf(.local, slot);
        }
        self.states[4] = .{ .stack = &.{}, .locals = first };
        var pc = self.head + 4;
        while (pc < self.back) : (pc += 1) {
            const state = self.states[pc - self.head] orelse continue;
            if (!try self.execute(pc, state) or self.broken) return false;
        }
        return self.stepOf();
    }

    /// The counter's one update must add a positive constant or a local to it.
    fn stepOf(self: *Analyzer) bool {
        const last = self.states[self.back - 1 - self.head] orelse return false;
        if (last.stack.len == 0) return false;
        const update = switch (self.get(last.stack[last.stack.len - 1])) {
            .operation => |operation| operation,
            else => return false,
        };
        if (update.operator != .add) return false;
        const step = if (self.isLeaf(update.left, .counter)) update.right else if (self.isLeaf(update.right, .counter)) update.left else return false;
        if (self.constantOf(step)) |value| {
            if (value < 1) return false;
        } else if (!self.isLeaf(step, .local) or self.localType(self.get(step).leaf.slot) != .i64) return false;
        // An append's room counts one element per counter value, which a
        // constant step of at least one never exceeds.
        if (self.writes.appended != null and self.constantOf(step) == null) return false;
        self.counter.step = step;
        return true;
    }

    /// Hand a state to the instruction at `pc`, merging with any state already
    /// there: a value two paths disagree on becomes unknown.
    fn flow(self: *Analyzer, pc: usize, state: State) Error!void {
        if (pc <= self.head or pc >= self.back) return;
        const slot = &self.states[pc - self.head];
        const existing = slot.* orelse {
            slot.* = .{ .stack = try self.allocator.dupe(NodeId, state.stack), .locals = try self.allocator.dupe(NodeId, state.locals) };
            return;
        };
        if (existing.stack.len != state.stack.len) {
            self.broken = true;
            return;
        }
        const unknown = try self.node(.unknown);
        for (existing.stack, state.stack) |*mine, theirs| if (mine.* != theirs) {
            mine.* = unknown;
        };
        for (existing.locals, state.locals) |*mine, theirs| if (mine.* != theirs) {
            mine.* = unknown;
        };
    }

    /// Evaluate one instruction and pass its result state on. Returns false
    /// when the loop cannot be planned.
    fn execute(self: *Analyzer, pc: usize, before: State) Error!bool {
        var machine: Machine = .{ .analyzer = self, .pc = pc };
        try machine.stack.appendSlice(self.allocator, before.stack);
        machine.locals = try self.allocator.dupe(NodeId, before.locals);
        const next = try machine.step() orelse return false;
        if (!next) return true;
        const expected = self.input.states[pc + 1] orelse return true;
        if (expected.len != machine.stack.items.len) return false;
        try self.flow(pc + 1, .{ .stack = machine.stack.items, .locals = machine.locals });
        return true;
    }

    /// Record the increment of a local's one write, when that write adds a
    /// bounded amount to the local's own value at the top of the iteration.
    fn noteIncrement(self: *Analyzer, slot: u32, value: NodeId) Error!void {
        if (self.writes.stores[slot] != 1 or slot == self.counter.slot) return;
        const operation = switch (self.get(value)) {
            .operation => |operation| operation,
            else => return,
        };
        const own = try self.leaf(.carried, slot);
        const additive = operation.operator == .add or operation.operator == .sub;
        const increment = if (additive and operation.left == own)
            operation.right
        else if (operation.operator == .add and operation.right == own)
            operation.left
        else
            return;
        // An increment that reads a carried local, the accumulator's own value
        // included, has no bound of its own.
        if (self.carries(increment, 0)) return;
        self.writes.increments[slot] = increment;
    }
    fn carries(self: *const Analyzer, id: NodeId, depth: u8) bool {
        if (depth > 24) return true;
        return switch (self.get(id)) {
            .unknown => true,
            .leaf => |value| value.kind == .carried,
            .operation => |operation| self.carries(operation.left, depth + 1) or self.carries(operation.right, depth + 1),
            else => false,
        };
    }

    /// A value of a narrow integer type is bounded by that type even when
    /// nothing else is known about it.
    fn narrowed(self: *Analyzer, pc: usize, fallback: NodeId) Error!NodeId {
        const after = self.input.states[pc] orelse return fallback;
        if (after.len == 0) return fallback;
        const info = after[after.len - 1].integer() orelse return fallback;
        if (info.bits >= 64) return fallback;
        return self.leaf(.narrow, info.bits);
    }

    /// Whether a value names a collection whose length and storage stay put
    /// for the whole loop: a list or byte string held by a local the loop
    /// never writes, or one read out of such a collection once by the guard.
    fn stable(self: *const Analyzer, id: NodeId) bool {
        return switch (self.get(id)) {
            .leaf => |value| value.kind == .local and self.sequence(self.localType(value.slot)),
            .element => |element| self.sequence(self.input.program.records[element.collection.recordIndex()].shape.buffer.?),
            else => false,
        };
    }

    /// Whether the guard can compute a value before the loop runs.
    fn computable(self: *const Analyzer, id: NodeId) bool {
        return switch (self.get(id)) {
            .constant, .element => true,
            .leaf => |value| value.kind == .local,
            .length => |object| self.stable(object),
            .operation => |operation| operation.operator != .quotient and self.computable(operation.left) and self.computable(operation.right),
            else => false,
        };
    }

    /// `alpha * counter + beta` for `alpha` in -1, 0, 1 and a computable `beta`.
    const Affine = struct { alpha: i2, beta: NodeId };
    fn affine(self: *Analyzer, id: NodeId) Error!?Affine {
        if (self.isLeaf(id, .counter)) return .{ .alpha = 1, .beta = try self.constant(0) };
        if (self.computable(id)) return .{ .alpha = 0, .beta = id };
        const operation = switch (self.get(id)) {
            .operation => |operation| operation,
            else => return null,
        };
        if (operation.operator == .quotient) return null;
        const left = try self.affine(operation.left) orelse return null;
        const right = try self.affine(operation.right) orelse return null;
        if (operation.operator == .mul) return self.scaled(left, right);
        const adding = operation.operator == .add;
        const alpha = @as(i4, left.alpha) + (if (adding) @as(i4, right.alpha) else -@as(i4, right.alpha));
        if (alpha < -1 or alpha > 1) return null;
        return .{ .alpha = @intCast(alpha), .beta = try self.operate(operation.operator, left.beta, right.beta) };
    }
    /// The product of two affine values, affine only when one of them is the
    /// constant 1 or -1 times the other.
    fn scaled(self: *Analyzer, left: Affine, right: Affine) Error!?Affine {
        if (left.alpha != 0 and right.alpha != 0) return null;
        const counted = if (left.alpha != 0) left else right;
        const factor = if (left.alpha != 0) right else left;
        const unit = self.constantOf(factor.beta) orelse return null;
        if (unit != 1 and unit != -1) return null;
        const alpha = @as(i4, counted.alpha) * @as(i4, @intCast(unit));
        return .{ .alpha = @intCast(alpha), .beta = try self.operate(.mul, counted.beta, factor.beta) };
    }

    /// Record the guard step that makes an affine index non-negative on every
    /// iteration: its smallest value is at least zero.
    fn requireNonNegative(self: *Analyzer, index: Affine) Error!void {
        const entry = try self.leaf(.entry, self.counter.slot);
        switch (index.alpha) {
            0 => try self.require(.{ .at_least = .{ .value = index.beta, .minimum = 0 } }),
            1 => try self.require(.{ .at_least = .{ .value = try self.operate(.add, index.beta, entry), .minimum = 0 } }),
            // beta - last >= 0, with last = bound - 1 for `<`.
            else => try self.require(.{ .at_least = .{ .value = try self.operate(.sub, index.beta, self.counter.bound), .minimum = if (self.counter.inclusive) 0 else -1 } }),
        }
    }
    /// Record the guard step that keeps an affine index's largest value below
    /// `limit` on every iteration.
    fn requireBelow(self: *Analyzer, index: Affine, limit: NodeId) Error!void {
        const entry = try self.leaf(.entry, self.counter.slot);
        switch (index.alpha) {
            0 => try self.require(.{ .order = .{ .relation = .within, .value = index.beta, .limit = limit } }),
            // beta + last < limit; with last = bound - 1 for `<`, beta + bound <= limit.
            1 => {
                const top = try self.operate(.add, index.beta, self.counter.bound);
                try self.require(.{ .order = .{ .relation = if (self.counter.inclusive) .below else .at_most, .value = top, .limit = limit } });
            },
            else => try self.require(.{ .order = .{ .relation = .below, .value = try self.operate(.sub, index.beta, entry), .limit = limit } }),
        }
    }

    /// Whether `value < 0` is false on every iteration, recording the guard
    /// step that makes it so.
    fn provenNonNegative(self: *Analyzer, condition: NodeId) Error!bool {
        const value = switch (self.get(condition)) {
            .negative => |v| v,
            else => return false,
        };
        const index = try self.affine(value) orelse return false;
        try self.requireNonNegative(index);
        return true;
    }

    const Access = struct { receiver: NodeId, index: NodeId, ty: typed.Type, read: bool };
    /// Plan one element access: prove its index, choose the storage the copy
    /// addresses it through, and hoist an invariant element read. Returns the
    /// value a read pushes.
    fn elementAccess(self: *Analyzer, pc: usize, request: Access) Error!NodeId {
        const unknown = try self.node(.unknown);
        const record = self.input.program.records[request.ty.recordIndex()];
        const result = if (request.read) try self.narrowed(pc + 1, unknown) else unknown;
        const index = try self.affine(request.index) orelse return result;
        const limit = if (record.shape.array) |array|
            try self.constant(@intCast(array.length))
        else if (self.stable(request.receiver))
            try self.node(.{ .length = request.receiver })
        else
            return result;
        if (index.alpha != 0) try self.requireNonNegative(index);
        try self.requireBelow(index, limit);
        const action = &self.actions[pc - self.head];
        action.unchecked = true;
        action.nonnegative = true;
        if (record.shape.array != null) return result;
        action.receiver = request.receiver;
        if (!request.read or index.alpha != 0) return result;
        if (!self.sequence(record.shape.buffer.?)) return result;
        for (self.writes.elements.items) |written| if (written == request.ty) return result;
        const hoisted = try self.node(.{ .element = .{ .receiver = request.receiver, .index = index.beta, .collection = request.ty } });
        action.value = hoisted;
        return hoisted;
    }

    /// A `for x in xs` length check: nothing in the loop can resize `xs`, so
    /// it holds on every iteration when it holds on entry.
    fn iterationCheck(self: *Analyzer, pc: usize, owner: NodeId, expected: NodeId) Error!void {
        if (!self.stable(owner) or !self.computable(expected)) return;
        try self.require(.{ .order = .{ .relation = .equal, .value = try self.node(.{ .length = owner }), .limit = expected } });
        self.actions[pc - self.head].effect = .settled;
    }

    fn require(self: *Analyzer, step: Step) Error!void {
        for (self.requirements.items) |existing| if (std.meta.eql(existing, step)) return;
        try self.requirements.append(self.allocator, step);
    }

    /// The magnitude of a value in terms of the leaf bound, collecting the
    /// leaves the guard must bound. Null when no bound is known.
    fn magnitude(self: *Analyzer, id: NodeId, leaves: *std.ArrayList(NodeId), depth: u8) Error!?Magnitude {
        if (depth > 24) return null;
        switch (self.get(id)) {
            .constant => |value| return .{ .coefficient = @abs(value), .degree = 0 },
            .length => {
                try addLeaf(self.allocator, leaves, id);
                return Magnitude.one;
            },
            .leaf => |value| return self.leafMagnitude(id, value, leaves, depth),
            .operation => |operation| {
                const left = try self.magnitude(operation.left, leaves, depth + 1) orelse return null;
                const right = try self.magnitude(operation.right, leaves, depth + 1) orelse return null;
                return switch (operation.operator) {
                    .mul => Magnitude.product(left, right),
                    // |floor(a / d)| <= |a| for every integer d with |d| >= 1.
                    .quotient => left,
                    .add, .sub => Magnitude.sum(left, right),
                };
            },
            else => return null,
        }
    }
    fn leafMagnitude(self: *Analyzer, id: NodeId, value: Leaf, leaves: *std.ArrayList(NodeId), depth: u8) Error!?Magnitude {
        switch (value.kind) {
            .narrow => return .{ .coefficient = @as(u64, 1) << @intCast(value.slot), .degree = 0 },
            .local, .entry => {
                if (self.localType(value.slot) != .i64) return null;
                try addLeaf(self.allocator, leaves, id);
                return Magnitude.one;
            },
            // Between its entry value and its bound, both bounded.
            .counter => {
                try self.counterLeaves(leaves);
                return Magnitude.one;
            },
            // An accumulator: |a| <= |a0| + trips * |e|, trips <= 2X + 1 <= 3X.
            .carried => {
                const increment = self.writes.increments[value.slot] orelse return null;
                if (self.localType(value.slot) != .i64) return null;
                const each = try self.magnitude(increment, leaves, depth + 1) orelse return null;
                try self.counterLeaves(leaves);
                try addLeaf(self.allocator, leaves, try self.leaf(.entry, value.slot));
                const trips: Magnitude = .{ .coefficient = 3, .degree = 1 };
                return Magnitude.sum(Magnitude.one, Magnitude.product(trips, each));
            },
        }
    }
    fn counterLeaves(self: *Analyzer, leaves: *std.ArrayList(NodeId)) Error!void {
        try addLeaf(self.allocator, leaves, try self.leaf(.entry, self.counter.slot));
        try addLeaf(self.allocator, leaves, self.counter.bound);
        try addLeaf(self.allocator, leaves, self.counter.step);
    }

    /// Choose the leaf bound, keep the arithmetic that fits it, and assemble
    /// the guard. Null when the copy would assume nothing.
    fn finish(self: *Analyzer) Error!?Loop {
        var leaves: std.ArrayList(NodeId) = .empty;
        var bits: u6 = widest_bits;
        // Every compared value the guard computes must fit, or the loop is not
        // versioned at all: an element hoist may depend on any comparison.
        for (self.requirements.items) |step| for (stepValues(step)) |value| {
            const id = value orelse continue;
            if (self.plain(id)) continue;
            const bound = try self.magnitude(id, &leaves, 0) orelse return null;
            bits = @min(bits, bound.widest() orelse return null);
        };
        // Arithmetic that does not fit keeps its check.
        var accepted: usize = 0;
        for (self.arithmetic.items) |candidate| {
            var trial: std.ArrayList(NodeId) = .empty;
            const bound = try self.magnitude(candidate.value, &trial, 0) orelse continue;
            bits = @min(bits, bound.widest() orelse continue);
            for (trial.items) |id| try addLeaf(self.allocator, &leaves, id);
            self.actions[candidate.pc - self.head].unchecked = true;
            accepted += 1;
        }
        var useful = accepted != 0;
        for (self.actions) |action| useful = useful or action.unchecked or action.effect != .none;
        if (!useful) return null;
        // The body proper starts after the four header instructions; the
        // back jump is reached from the counter's update, which is live.
        for (self.states[4 .. self.back - self.head], self.actions[4 .. self.back - self.head]) |state, *action| {
            action.dead = state == null;
        }
        var guard: std.ArrayList(Step) = .empty;
        // First, so a short loop pays one comparison and runs the original.
        try guard.append(self.allocator, .{ .spans = .{ .entry = try self.leaf(.entry, self.counter.slot), .bound = self.counter.bound, .minimum = min_span } });
        for (leaves.items) |id| if (self.get(id) == .leaf) try guard.append(self.allocator, .{ .bounded = id });
        if (self.constantOf(self.counter.step) == null) {
            try guard.append(self.allocator, .{ .at_least = .{ .value = self.counter.step, .minimum = if (self.accumulates(leaves.items)) 1 else 0 } });
        }
        try guard.appendSlice(self.allocator, self.requirements.items);
        // A length is loaded from its collection, which an earlier step may
        // have had to bound the position of first.
        for (leaves.items) |id| if (self.get(id) == .length) try guard.append(self.allocator, .{ .bounded = id });
        return .{ .head = self.head, .back = self.back, .bits = bits, .guard = try guard.toOwnedSlice(self.allocator), .actions = self.actions };
    }
    /// A compared value that is one leaf or constant: the comparison computes
    /// nothing that could wrap.
    fn plain(self: *const Analyzer, id: NodeId) bool {
        return switch (self.get(id)) {
            .constant, .leaf, .length => true,
            else => false,
        };
    }
    /// Whether an accumulator's bound is among the leaves: its trip count then
    /// needs a step of at least one.
    fn accumulates(self: *const Analyzer, leaves: []const NodeId) bool {
        for (leaves) |id| switch (self.get(id)) {
            .leaf => |value| if (value.kind == .entry and value.slot != self.counter.slot) return true,
            else => {},
        };
        return false;
    }
};

/// The operand stack and locals one instruction transforms.
const Machine = struct {
    analyzer: *Analyzer,
    pc: usize,
    stack: std.ArrayList(NodeId) = .empty,
    locals: []NodeId = &.{},

    fn push(self: *Machine, id: NodeId) Error!void {
        try self.stack.append(self.analyzer.allocator, id);
    }
    fn pop(self: *Machine) ?NodeId {
        return self.stack.pop();
    }
    /// Drop `count` operands and push one unknown value (or its type's bound).
    fn consume(self: *Machine, count: usize) Error!?bool {
        for (0..count) |_| _ = self.pop() orelse return null;
        try self.push(try self.analyzer.narrowed(self.pc + 1, try self.analyzer.node(.unknown)));
        return true;
    }

    /// Transform the state by one instruction. Returns null when the loop
    /// cannot be planned, false when the instruction does not fall through,
    /// and true when it does.
    fn step(self: *Machine) Error!?bool {
        const a = self.analyzer;
        switch (a.code()[self.pc].op) {
            .push_i64 => |value| try self.push(try a.constant(value)),
            .push_integer => |number| try self.push(if (std.math.cast(i64, number.value)) |value| try a.constant(value) else try a.node(.unknown)),
            .push_bool, .push_unit => try self.push(try a.node(.unknown)),
            .load_local => |slot| try self.push(self.locals[slotOf(slot)]),
            .store_local => |slot| {
                const value = self.pop() orelse return null;
                self.locals[slotOf(slot)] = value;
                try a.noteIncrement(slotOf(slot), value);
            },
            .pop, .acknowledge, .assert_true => _ = self.pop() orelse return null,
            .jump => |target| {
                try a.flow(target, .{ .stack = self.stack.items, .locals = self.locals });
                return false;
            },
            .jump_if_false => |target| return self.branch(target),
            .cmp_i64 => |predicate| {
                const right = self.pop() orelse return null;
                const left = self.pop() orelse return null;
                try self.push(if (predicate == .lt and a.constantOf(right) == 0) try a.node(.{ .negative = left }) else try a.node(.unknown));
            },
            .cmp_bool, .cmp_enum, .cmp_domain, .rem_i64_checked => return self.consume(2),
            .div_i64_checked => return self.quotient(),
            .not_bool, .unary_float, .get_field, .neg_i64_checked, .neg_integer => return self.consume(1),
            .wrap_domain, .unwrap_domain => {},
            .add_i64_checked => try self.arith(.add),
            .sub_i64_checked => try self.arith(.sub),
            .mul_i64_checked => try self.arith(.mul),
            .binary_integer => |binary| {
                if (binary.ty != .i64) return self.consume(2);
                switch (binary.op) {
                    .add => try self.arith(.add),
                    .sub => try self.arith(.sub),
                    .mul => try self.arith(.mul),
                    .div, .floor_div => return self.quotient(),
                    else => return self.consume(2),
                }
            },
            // A cast that does not trap leaves the mathematical value as it
            // was; its own range test stays in the copy.
            .cast_integer => {
                const value = self.pop() orelse return null;
                if (a.get(value) == .unknown) try self.push(try a.narrowed(self.pc + 1, value)) else try self.push(value);
            },
            .array_length => |ty| {
                _ = self.pop() orelse return null;
                try self.push(try a.constant(@intCast(a.input.program.records[ty.recordIndex()].count())));
            },
            .make_record => |record| return self.consume(record.fields),
            .update_record => |update| return self.consume(update.indices.len + 1),
            .get_index => |access| {
                const index = self.pop() orelse return null;
                const receiver = self.pop() orelse return null;
                try self.push(try a.elementAccess(self.pc, .{ .receiver = receiver, .index = index, .ty = access.ty, .read = true }));
            },
            .replace_index => |access| {
                _ = self.pop() orelse return null;
                const index = self.pop() orelse return null;
                const receiver = self.pop() orelse return null;
                _ = try a.elementAccess(self.pc, .{ .receiver = receiver, .index = index, .ty = access.ty, .read = false });
                try self.push(try a.node(.unknown));
            },
            .buffer_operation => |operation| return self.buffer(operation),
            else => return null,
        }
        return true;
    }

    /// A division, bounded by its dividend when the divisor is a nonzero
    /// constant. Its own zero and `MIN // -1` checks stay in the copy.
    fn quotient(self: *Machine) Error!?bool {
        const a = self.analyzer;
        if (self.stack.items.len < 2) return null;
        const divisor = self.stack.items[self.stack.items.len - 1];
        const value = a.constantOf(divisor) orelse return self.consume(2);
        if (value == 0) return self.consume(2);
        _ = self.pop() orelse return null;
        const dividend = self.pop() orelse return null;
        try self.push(try a.node(.{ .operation = .{ .operator = .quotient, .left = dividend, .right = divisor } }));
        return true;
    }

    fn arith(self: *Machine, operator: @FieldType(Operation, "operator")) Error!void {
        const a = self.analyzer;
        const right = self.pop() orelse return a.fail();
        const left = self.pop() orelse return a.fail();
        const value = try a.node(.{ .operation = .{ .operator = operator, .left = left, .right = right } });
        try a.arithmetic.append(a.allocator, .{ .pc = self.pc, .value = value });
        try self.push(value);
    }

    /// A conditional jump: both successors, unless the guard can prove the
    /// condition false on every iteration (a proven index's `< 0` test).
    fn branch(self: *Machine, target: usize) Error!?bool {
        const a = self.analyzer;
        const condition = self.pop() orelse return null;
        const state: State = .{ .stack = self.stack.items, .locals = self.locals };
        try a.flow(target, state);
        if (try a.provenNonNegative(condition)) {
            a.actions[self.pc - a.head].effect = .taken;
            return false;
        }
        try a.flow(self.pc + 1, state);
        return false;
    }

    fn buffer(self: *Machine, operation: @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation")) Error!?bool {
        const a = self.analyzer;
        const owner = self.locals[slotOf(operation.owner)];
        const ty = a.localType(slotOf(operation.owner));
        switch (operation.kind) {
            .length => try self.push(if (a.stable(owner)) try a.node(.{ .length = owner }) else try a.node(.unknown)),
            .read => {
                const index = self.pop() orelse return null;
                try self.push(try a.elementAccess(self.pc, .{ .receiver = owner, .index = index, .ty = ty, .read = true }));
            },
            .write => {
                _ = self.pop() orelse return null;
                const index = self.pop() orelse return null;
                _ = try a.elementAccess(self.pc, .{ .receiver = owner, .index = index, .ty = ty, .read = false });
                try self.push(try a.node(.unknown));
            },
            .iteration_check => {
                const expected = self.pop() orelse return null;
                try a.iterationCheck(self.pc, owner, expected);
                try self.push(try a.node(.unknown));
            },
            // An append to a list the loop holds in one local: the guard
            // checks its spare capacity holds every iteration's element.
            .append => {
                _ = self.pop() orelse return null;
                if (!a.stable(owner)) return null;
                try a.require(.{ .room = .{ .list = owner, .entry = try a.leaf(.entry, a.counter.slot), .bound = a.counter.bound, .inclusive = a.counter.inclusive } });
                const action = &a.actions[self.pc - a.head];
                action.effect = .presized;
                action.receiver = owner;
                try self.push(try a.node(.unknown));
            },
            else => return null,
        }
        return true;
    }
};

fn stepValues(step: Step) [2]?NodeId {
    return switch (step) {
        .bounded => |value| .{ value, null },
        .at_least => |bound| .{ bound.value, null },
        .order => |order| .{ order.value, order.limit },
        .spans, .room => .{ null, null },
    };
}

fn addLeaf(allocator: std.mem.Allocator, leaves: *std.ArrayList(NodeId), id: NodeId) Error!void {
    for (leaves.items) |existing| if (existing == id) return;
    try leaves.append(allocator, id);
}

fn slotOf(id: anytype) u32 {
    return @intCast(@backingInt(id));
}
