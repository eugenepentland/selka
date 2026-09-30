//! RC-SCOPE-IL-1: production journal operations with the native failure path.
const runtime = @import("runtime_mode.zig");
const prefix = @import("qbe_rc_prefix.zig");
const Error = @import("qbe_rc_unique.zig").Error;
const store_word = " storel %v{d}, %v{d}\n";
const load_count = " %v{d} =" ++ prefix.count_type ++ " " ++ prefix.count_load ++ " %v{d}\n";
const change_count = load_count ++ " %v{d} =" ++ prefix.count_type ++ " add %v{d}, {d}\n " ++ prefix.count_store ++ " %v{d}, %v{d}\n";
const arena: u64 = @as(u64, 1) << 62;
const pinned: u64 = @as(u64, 1) << 60;
const special: u64 = arena | 2 | 1;
const entry_bytes = 40;
const state_offset = 5640;
const metadata_bytes = 48;
const scopes = 248;
const spare = 256;
const spare_count = 264;
const deaths = 200;
const heap_bytes = 24;
const heap_limit = 88;
const heap_region = 112;

/// Link the initialized frame record before any fallible capture.
pub fn begin(comptime E: type, self: *E, scope: usize) Error!bool {
    if (runtime.counting()) return false;
    try self.print(" # RC-SCOPE-IL-1 begin\n storel %heap, %v{d}\n", .{scope});
    const rc = try state(E, self);
    const head = try address(E, self, rc, scopes);
    const previous = try load(E, self, head);
    try store(E, self, scope, 8, previous);
    try self.print(" storel 0, %v{d}\n", .{try self.address(scope, 16)});
    const region = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n storew 1, %v{d}\n storew %v{d}, %v{d}\n storel %v{d}, %v{d}\n", .{ region, try addressHeap(E, self, heap_region), try self.address(scope, 24), region, try self.address(scope, 28), scope, head });
    return true;
}

const Capture = struct { scope: usize, payload: usize, label: usize, rc: usize, node: usize, mark: usize, backing: usize };
/// Reuse an admitted spare for a counted list, preserving native slow refusals.
pub fn pin(comptime E: type, self: *E, scope: usize, payload: usize) Error!bool {
    if (runtime.counting()) return false;
    const label = self.temp();
    try self.print(" # RC-SCOPE-IL-1 pin\n jnz %v{d}, @rcspinmark{d}, @rcspindone{d}\n@rcspinmark{d}\n", .{ try truth64(E, self, payload), label, label, label });
    const mark = try below(E, self, payload, 16);
    const immortal = self.temp();
    try self.print(" %v{d} =l and %v{d}, 2\n", .{ immortal, mark });
    try self.print(" jnz %v{d}, @rcspindone{d}, @rcspintype{d}\n@rcspintype{d}\n", .{ try truth64(E, self, immortal), label, label, label });
    try ordinary(E, self, payload, mark, label, "pin");
    const descriptor = try load(E, self, try belowAddress(E, self, payload, 8));
    const list_type = self.temp();
    const is_list = self.temp();
    try self.print(" %v{d} =l loadl $myl_native_list_header_type\n %v{d} =w ceql %v{d}, %v{d}\n", .{ list_type, is_list, descriptor, list_type });
    try guard(E, self, is_list, label, "pin");
    const rc = try state(E, self);
    const node = try load(E, self, try address(E, self, rc, spare));
    try guard(E, self, try truth64(E, self, node), label, "pin");
    const bytes = try load(E, self, try addressHeap(E, self, heap_bytes));
    const total = self.temp();
    const fits = self.temp();
    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =w cugel %v{d}, %v{d}\n", .{ total, bytes, entry_bytes, fits, total, bytes });
    try guard(E, self, fits, label, "pin");
    const limit = try load(E, self, try addressHeap(E, self, heap_limit));
    const unbounded = self.temp();
    const below_limit = self.temp();
    const admitted = self.temp();
    try self.print(" %v{d} =w ceql %v{d}, 0\n %v{d} =w culel %v{d}, %v{d}\n %v{d} =w or %v{d}, %v{d}\n", .{ unbounded, limit, below_limit, total, limit, admitted, unbounded, below_limit });
    try guard(E, self, admitted, label, "pin");
    try available(E, self, payload, label, "pin");
    const backing = try load(E, self, try self.address(payload, 32));
    try self.print(" jnz %v{d}, @rcspinbacking{d}, @rcspincommit{d}\n@rcspinbacking{d}\n", .{ try truth64(E, self, backing), label, label, label });
    try ordinary(E, self, backing, try below(E, self, backing, 16), label, "pin");
    try available(E, self, backing, label, "pin");
    try self.print("@rcspincommit{d}\n", .{label});
    try capture(E, self, .{ .scope = scope, .payload = payload, .label = label, .rc = rc, .node = node, .mark = mark, .backing = backing });
    try self.print(" jmp @rcspindone{d}\n@rcspinslow{d}\n", .{ label, label });
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_qbe_rc_scope_pin(l %ctx, l %v{d}, l %v{d})\n", .{ done, scope, payload });
    try @import("qbe_rc_unique.zig").success(E, self, done);
    try self.print("@rcspindone{d}\n", .{label});
    return true;
}

fn capture(comptime E: type, self: *E, value: Capture) Error!void {
    const next = try load(E, self, value.node);
    try storeRuntime(E, self, value.rc, spare, next);
    try bump(E, self, try address(E, self, value.rc, spare_count), -1);
    try bump(E, self, try addressHeap(E, self, heap_bytes), entry_bytes);
    try bump(E, self, try address(E, self, value.rc, metadata_bytes), entry_bytes);
    try increment(E, self, value.payload, 1);
    try self.print(" jnz %v{d}, @rcspinhold{d}, @rcspinjournal{d}\n@rcspinhold{d}\n", .{ try truth64(E, self, value.backing), value.label, value.label, value.label });
    try increment(E, self, value.backing, 1);
    try self.print("@rcspinjournal{d}\n", .{value.label});
    const old_pin = self.temp();
    const new_mark = self.temp();
    try self.print(" %v{d} =l and %v{d}, {d}\n %v{d} =l or %v{d}, {d}\n", .{ old_pin, value.mark, pinned, new_mark, value.mark, pinned });
    try writeBelow(E, self, value.payload, 16, new_mark);
    try storeRuntime(E, self, value.node, 0, try load(E, self, try self.address(value.scope, 16)));
    try storeRuntime(E, self, value.node, 8, value.payload);
    try storeRuntime(E, self, value.node, 16, old_pin);
    try self.print(" storew 1, %v{d}\n", .{try address(E, self, value.node, 24)});
    try storeRuntime(E, self, value.node, 32, value.backing);
    try store(E, self, value.scope, 16, value.node);
}

const Release = struct { scope: usize, label: usize, rc: usize, node: usize, payload: usize, backing: usize, mark: usize };
/// Restore a single pin and return nonfinal holds; all deaths use native unwind.
pub fn end(comptime E: type, self: *E, scope: usize) Error!bool {
    if (runtime.counting()) return false;
    const label = self.temp();
    const active = self.temp();
    try self.print(" # RC-SCOPE-IL-1 end\n %v{d} =w loaduw %v{d}\n jnz %v{d}, @rcsendactive{d}, @rcsenddone{d}\n@rcsendactive{d}\n", .{ active, try self.address(scope, 24), active, label, label, label });
    const rc = try state(E, self);
    const current = try load(E, self, try address(E, self, rc, scopes));
    const nested = self.temp();
    try self.print(" %v{d} =w ceql %v{d}, %v{d}\n", .{ nested, current, scope });
    try guard(E, self, nested, label, "end");
    try zero(E, self, try load(E, self, try address(E, self, rc, deaths)), label, "end");
    const node = try load(E, self, try self.address(scope, 16));
    try self.print(" jnz %v{d}, @rcsendnode{d}, @rcsendunlink{d}\n@rcsendnode{d}\n", .{ try truth64(E, self, node), label, label, label });
    try zero(E, self, try load(E, self, try address(E, self, node, 0)), label, "end");
    const count = try load(E, self, try address(E, self, rc, spare_count));
    const room = self.temp();
    try self.print(" %v{d} =w cultl %v{d}, 32\n", .{ room, count });
    try guard(E, self, room, label, "end");
    const payload = try load(E, self, try address(E, self, node, 8));
    try guard(E, self, try truth64(E, self, payload), label, "end");
    const mark = try below(E, self, payload, 16);
    try ordinary(E, self, payload, mark, label, "end");
    try nonfinal(E, self, payload, label);
    const backing = try load(E, self, try address(E, self, node, 32));
    try self.print(" jnz %v{d}, @rcsendbacking{d}, @rcsendcommit{d}\n@rcsendbacking{d}\n", .{ try truth64(E, self, backing), label, label, label });
    try ordinary(E, self, backing, try below(E, self, backing, 16), label, "end");
    try nonfinal(E, self, backing, label);
    try self.print("@rcsendcommit{d}\n", .{label});
    try release(E, self, .{ .scope = scope, .label = label, .rc = rc, .node = node, .payload = payload, .backing = backing, .mark = mark });
    try self.print("@rcsendunlink{d}\n", .{label});
    try storeRuntime(E, self, rc, scopes, try load(E, self, try self.address(scope, 8)));
    try self.print(" storew 0, %v{d}\n storel 0, %v{d}\n", .{ try self.address(scope, 24), try self.address(scope, 8) });
    try self.print(" jmp @rcsenddone{d}\n@rcsendslow{d}\n call $myl_qbe_rc_scope_end(l %ctx, l %v{d})\n@rcsenddone{d}\n", .{ label, label, scope, label });
    return true;
}

fn release(comptime E: type, self: *E, value: Release) Error!void {
    const was_pinned = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n jnz %v{d}, @rcsendrestore{d}, @rcsendreturned{d}\n@rcsendrestore{d}\n", .{ was_pinned, try address(E, self, value.node, 24), was_pinned, value.label, value.label, value.label });
    const previous = try load(E, self, try address(E, self, value.node, 16));
    const restored = self.temp();
    const clear = self.temp();
    try self.print(" %v{d} =l and %v{d}, {d}\n %v{d} =l or %v{d}, %v{d}\n", .{ clear, value.mark, ~pinned, restored, clear, previous });
    try writeBelow(E, self, value.payload, 16, restored);
    try self.print("@rcsendreturned{d}\n storel 0, %v{d}\n", .{ value.label, try self.address(value.scope, 16) });
    const old_spare = try load(E, self, try address(E, self, value.rc, spare));
    try storeRuntime(E, self, value.node, 0, old_spare);
    try storeRuntime(E, self, value.rc, spare, value.node);
    try bump(E, self, try address(E, self, value.rc, spare_count), 1);
    try bump(E, self, try addressHeap(E, self, heap_bytes), -entry_bytes);
    try bump(E, self, try address(E, self, value.rc, metadata_bytes), -entry_bytes);
    try self.print(" jnz %v{d}, @rcsenddropbacking{d}, @rcsenddroppayload{d}\n@rcsenddropbacking{d}\n", .{ try truth64(E, self, value.backing), value.label, value.label, value.label });
    try increment(E, self, value.backing, -1);
    try self.print("@rcsenddroppayload{d}\n", .{value.label});
    try increment(E, self, value.payload, -1);
}

fn state(comptime E: type, self: *E) Error!usize {
    return load(E, self, try addressHeap(E, self, state_offset));
}
fn addressHeap(comptime E: type, self: *E, offset: u64) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l add %heap, {d}\n # myl-rc-state %v{d}\n", .{ result, offset, result });
    return result;
}
fn address(comptime E: type, self: *E, base: usize, offset: u64) Error!usize {
    const result = try self.address(base, offset);
    try self.print(" # myl-rc-state %v{d}\n", .{result});
    return result;
}
fn load(comptime E: type, self: *E, pointer: usize) Error!usize {
    const value = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n", .{ value, pointer });
    return value;
}
fn store(comptime E: type, self: *E, base: usize, offset: u64, value: usize) Error!void {
    try self.print(store_word, .{ value, try self.address(base, offset) });
}
fn storeRuntime(comptime E: type, self: *E, base: usize, offset: u64, value: usize) Error!void {
    try self.print(store_word, .{ value, try address(E, self, base, offset) });
}
fn belowAddress(comptime E: type, self: *E, payload: usize, offset: u64) Error!usize {
    const result = self.temp();
    try self.print(" %v{d} =l sub %v{d}, {d}\n # myl-rc %v{d}\n", .{ result, payload, offset, result });
    return result;
}
fn below(comptime E: type, self: *E, payload: usize, offset: u64) Error!usize {
    return load(E, self, try belowAddress(E, self, payload, offset));
}
fn writeBelow(comptime E: type, self: *E, payload: usize, offset: u64, value: usize) Error!void {
    try self.print(store_word, .{ value, try belowAddress(E, self, payload, offset) });
}
fn bump(comptime E: type, self: *E, pointer: usize, amount: i64) Error!void {
    const value = try load(E, self, pointer);
    const updated = self.temp();
    try self.print(" %v{d} =l add %v{d}, {d}\n storel %v{d}, %v{d}\n", .{ updated, value, amount, updated, pointer });
}
fn increment(comptime E: type, self: *E, payload: usize, amount: i64) Error!void {
    const pointer = try belowAddress(E, self, payload, prefix.holds_offset);
    const value = self.temp();
    const updated = self.temp();
    try self.print(change_count, .{ value, pointer, updated, value, amount, updated, pointer });
}
fn loadCount(comptime E: type, self: *E, payload: usize, offset: u64) Error!usize {
    const value = self.temp();
    try self.print(load_count, .{ value, try belowAddress(E, self, payload, offset) });
    return value;
}
// QBE jnz inspects one word, so pointers and u64 counts first need a boolean.
fn truth64(comptime E: type, self: *E, value: usize) Error!usize {
    const condition = self.temp();
    try self.print(" %v{d} =w cnel %v{d}, 0\n", .{ condition, value });
    return condition;
}
fn guard(comptime E: type, self: *E, condition: usize, label: usize, operation: []const u8) Error!void {
    const next = self.temp();
    try self.print(" jnz %v{d}, @rcs{d}, @rcs{s}slow{d}\n@rcs{d}\n", .{ condition, next, operation, label, next });
}
fn zero(comptime E: type, self: *E, value: usize, label: usize, operation: []const u8) Error!void {
    const condition = self.temp();
    try self.print(" %v{d} =w ceql %v{d}, 0\n", .{ condition, value });
    try guard(E, self, condition, label, operation);
}
fn ordinary(comptime E: type, self: *E, payload: usize, mark: usize, label: usize, operation: []const u8) Error!void {
    _ = payload;
    const flagged = self.temp();
    try self.print(" %v{d} =l and %v{d}, {d}\n", .{ flagged, mark, special });
    try zero(E, self, flagged, label, operation);
}
fn available(comptime E: type, self: *E, payload: usize, label: usize, operation: []const u8) Error!void {
    const holds = try loadCount(E, self, payload, prefix.holds_offset);
    const condition = self.temp();
    try self.print(" %v{d} =w cne" ++ prefix.count_type ++ " %v{d}, {d}\n", .{ condition, holds, prefix.count_max });
    try guard(E, self, condition, label, operation);
}
fn nonfinal(comptime E: type, self: *E, payload: usize, label: usize) Error!void {
    const holds = try loadCount(E, self, payload, prefix.holds_offset);
    try guard(E, self, try truth64(E, self, holds), label, "end");
    const owners = try loadCount(E, self, payload, prefix.owners_offset);
    const retained = self.temp();
    const sharing = self.temp();
    const live = self.temp();
    try self.print(" %v{d} =w cugt" ++ prefix.count_type ++ " %v{d}, 1\n %v{d} =w cne" ++ prefix.count_type ++ " %v{d}, 0\n %v{d} =w or %v{d}, %v{d}\n", .{ retained, holds, sharing, owners, live, retained, sharing });
    try guard(E, self, live, label, "end");
}
