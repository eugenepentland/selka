//! One raw receiver capture cannot invalidate its immediately preceding check.
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const runtime = @import("runtime_mode.zig");

/// RC-UNIQUE-CAPTURE-1: keep the first exact root check and omit only the
/// duplicate at its adjacent empty receiver store. Unknown physical effects,
/// incoming edges, counted instrumentation and speculative emission refuse.
pub fn store(comptime E: type, self: *E, local: usize, parent: usize) bool {
    if (!runtime.enabled() or runtime.counting() or self.arenas) return false;
    if (self.version != null or self.original != null or self.fused != null) return false;
    const state = frame.get(E, self) orelse return false;
    if (state.readonly or state.contract.result == .borrowed) return false;
    if (!frame.emptyLocal(E, self, local)) return false;
    if (!@import("qbe_rc_inert_receiver.zig").emptyLocal(E, self, local)) return false;
    const plan = self.cow.?.plan;
    if (local >= plan.aliases.len or plan.aliases[local] != parent) return false;
    // This separate input proof fixes the descriptor, named ordinary root,
    // adjacent producer, single definition and exact physical storage.
    if (!@import("qbe_rc_nonheld_capture.zig").proven(E, self, local, self.pc)) return false;
    const previous = self.function.scope.instructions[self.pc - 1].op;
    if (@backingInt(previous.load_local) != parent) return false;
    // A physical hoist can suppress localCall despite a semantic unique site.
    // This proof deliberately requires an actual first check at the producer.
    if (hoisted(plan, self.pc - 1, parent)) return false;
    if (!quiet(E, self, self.pc - 1, parent, true) or !quiet(E, self, self.pc, parent, false)) return false;
    // The existing empty-local proof makes receiverCleanup a no-op: the
    // raw load acquired no operand token, and the target never owns one.
    return true;
}

fn hoisted(plan: cow.Plan, pc: usize, parent: usize) bool {
    for (plan.loops.entries, 0..) |entries, head| {
        if (pc <= head or pc > plan.loops.back[head]) continue;
        for (entries) |entry| if (!entry.elements and entry.local == parent) return true;
    }
    return false;
}

fn quiet(comptime E: type, self: *E, pc: usize, parent: usize, first: bool) bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    if (!siteQuiet(site, parent, first) or state.plan.entry(pc).len != 0) return false;
    if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
    const records = state.rc.?.plan.records;
    for (records.transfers) |proof| if (proof.intercepts(pc)) return false;
    for (records.writes) |proof| if (pc >= proof.start and pc < proof.start + 8) return false;
    for (records.reads) |proof| if (pc >= proof.start and pc <= proof.end) return false;
    return true;
}

fn siteQuiet(site: cow.Site, parent: usize, first: bool) bool {
    if (site.capture or site.fill or site.unique_field != null) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0) return false;
    if (!first) return site.unique.len == 0;
    return site.unique.len == 1 and site.unique[0].local == parent and site.unique[0].alias == cow.none;
}

// spec-case: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture requires one exact root check and no publication" {
    const t = @import("std").testing;
    const check = [_]cow.Unique{.{ .local = 2 }};
    var site: cow.Site = .{ .unique = &check };
    try t.expect(siteQuiet(site, 2, true));
    try t.expect(!siteQuiet(site, 3, true));
    try t.expect(!siteQuiet(site, 2, false));
    site.unique = &.{.{ .local = 2, .alias = 1 }};
    try t.expect(!siteQuiet(site, 2, true));
    site.unique = &.{ .{ .local = 2 }, .{ .local = 2 } };
    try t.expect(!siteQuiet(site, 2, true));
    site.unique = &.{};
    try t.expect(siteQuiet(site, 2, false));
    site.capture = true;
    try t.expect(!siteQuiet(site, 2, false));
    site = .{ .unique = &check, .fill = true };
    try t.expect(!siteQuiet(site, 2, true));
    site = .{ .unique = &check, .shares = &.{0} };
    try t.expect(!siteQuiet(site, 2, true));
    site = .{ .unique = &check, .read_captures = &.{0} };
    try t.expect(!siteQuiet(site, 2, true));
    site = .{ .unique = &check, .unique_field = .{ .parent = 2, .step = .field, .base = 0, .fill = 2 } };
    try t.expect(!siteQuiet(site, 2, true));
}

// spec-case: RC-UNIQUE-CAPTURE-1
test "RC duplicate capture refuses producer checks suppressed by a physical hoist" {
    const t = @import("std").testing;
    var entry = [_]cow.Hoisted{.{ .local = 2, .elements = false }};
    const plan: cow.Plan = .{ .loops = .{ .entries = &.{ &.{}, &entry, &.{}, &.{}, &.{} }, .back = &.{ cow.none, 3, cow.none, cow.none, cow.none } } };
    try t.expect(!hoisted(plan, 1, 2));
    try t.expect(hoisted(plan, 2, 2));
    try t.expect(hoisted(plan, 3, 2));
    try t.expect(!hoisted(plan, 4, 2));
    try t.expect(!hoisted(plan, 2, 3));
    entry[0].elements = true;
    try t.expect(!hoisted(plan, 2, 2));
}
