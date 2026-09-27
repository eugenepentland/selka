//! Compose an immutable list key loan with an already admitted dictionary tail.
const cow = @import("cow_plan.zig");
const model = @import("rc_dictionary_tail.zig");
const flow = @import("rc_dictionary_key.zig");
const reads = @import("qbe_rc_read_loans.zig");
const effects = @import("qbe_rc_dictionary_effects.zig");

/// All checks precede the atomic canonical-to-anchored authority replacement.
/// Private journals remain allocated; this certificate removes publications only.
pub fn certify(comptime E: type, self: *E, proof: model.Certificate) ?model.Key {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or proof.key_authority != .canonical) return null;
    const key = flow.discover(code, proof) orelse return null;
    if (proof.start + 5 - key.capture > 256) return null;
    if (!types(E, self, proof, key) or !homes(E, self, proof, key)) return null;
    const source = @backingInt(key.anchor.storage);
    const definition = flow.definition(code, source) orelse return null;
    if (!flow.uses(code, proof, key) or !flow.flow(code, key, definition, proof.start + 4)) return null;
    if (!@import("qbe_rc_nonheld_capture.zig").ordinaryInput(E, self, key.receiver, key.capture)) return null;
    if (!effects.unwritten(E, self, key.receiver) or !effects.unwritten(E, self, proof.key)) return null;
    if (effects.intercepted(E, self, definition)) return null;
    for (definition..key.capture) |pc| switch (code[pc].op) {
        .begin_arena, .end_arena => return null,
        else => {},
    };
    for (key.capture - 1..proof.start + 5) |pc| {
        if (!operation(E, self, proof, key, pc) or !effects.quiet(E, self, proof, pc)) return null;
        if (effects.releases(E, self, pc, &.{ key.receiver, proof.key })) return null;
    }
    return key;
}

fn types(comptime E: type, self: *E, proof: model.Certificate, key: model.Key) bool {
    const locals = self.function.scope.locals;
    const text = locals[proof.key].ty;
    if (!text.isAggregate()) return false;
    const string = self.program.records[text.recordIndex()];
    if (!string.isCollection() or string.collection.kind != .string or string.collection.box) return false;
    const list_type = locals[key.receiver].ty;
    if (!list_type.isAggregate()) return false;
    const list = self.program.records[list_type.recordIndex()];
    if (!list.isCollection() or list.collection.kind != .list) return false;
    if (list.collection.box or list.shape.buffer != text) return false;
    const code = self.function.scope.instructions;
    const read = code[key.projection].op.buffer_operation;
    const inputs = self.states[key.projection] orelse return false;
    if (read.output != text or inputs.len != 1 or !inputs[0].isInteger()) return false;
    const input = self.states[key.projection + 1] orelse return false;
    return input.len == 1 and input[0] == text and !self.isBranchTarget(key.projection + 1);
}

fn homes(comptime E: type, self: *E, proof: model.Certificate, key: model.Key) bool {
    const locals = self.function.scope.locals;
    const source = @backingInt(key.anchor.storage);
    const state = self.cow.?.rc.?;
    if (source == proof.root or key.receiver == proof.receiver or proof.key == key.receiver) return false;
    if (locals[proof.key].usage.temporary or locals[proof.key].origin != .collection_copy) return false;
    if (self.byReference(proof.key) or self.callerStorage(proof.key) or self.moves.resolve(proof.key) != proof.key) return false;
    if (self.moves.resolve(source) != source or self.moves.resolve(key.receiver) != key.receiver) return false;
    if (self.cow.?.plan.place(proof.key) != null or self.cow.?.plan.aliases[proof.key] != cow.none) return false;
    if (cow.iterationOwner(self.function, proof.key) or cow.iterationOwner(self.function, key.receiver)) return false;
    if (@import("qbe_rc_holds.zig").mayHold(E, self, locals[proof.key].ty)) return false;
    for ([_]usize{ proof.key, key.receiver }) |local| {
        const entry = state.plan.locals.entry[local];
        if (@backingInt(entry.storage) != local or entry.ownership != .empty) return false;
    }
    return true;
}

fn operation(comptime E: type, self: *E, proof: model.Certificate, key: model.Key, pc: usize) bool {
    const instruction = self.function.scope.instructions[pc];
    const op = instruction.op;
    if (instruction.inline_origin != null or self.states[pc] == null) return false;
    if (pc == key.capture - 1 or pc == key.capture or pc == key.projection or pc == key.projection + 1) return true;
    // The old exact five-op proof supplies root/value/raw capture/write grammar.
    if (pc >= proof.start) return true;
    if (op == .load_local and @backingInt(op.load_local) == proof.key) return pc > key.projection + 1;
    if (op == .buffer_operation) {
        const operation_ = op.buffer_operation;
        if (operation_.kind == .length and @backingInt(operation_.owner) == key.receiver) return pc < key.projection;
        if (operation_.kind != .get or @backingInt(operation_.owner) != proof.root) return false;
        if (operation_.output != self.function.scope.locals[proof.value].ty or pc <= key.projection + 1) return false;
        const stack = self.states[pc].?;
        return stack.len == 2 and stack[0] == self.function.scope.locals[proof.key].ty and stack[1] == operation_.output;
    }
    if (op == .cast_integer) {
        const stack = self.states[pc].?;
        if (stack.len == 0 or !stack[stack.len - 1].isInteger()) return false;
    }
    return reads.scalar(E, self, op, &self.cow.?.rc.?.catalog) catch false;
}
