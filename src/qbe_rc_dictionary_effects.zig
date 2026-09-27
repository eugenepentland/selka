//! Shared physical effects veto for closed dictionary emission certificates.
const cow = @import("cow_plan.zig");
const model = @import("rc_dictionary_tail.zig");

/// Only the old root check may run before the original terminal write.
pub fn quiet(comptime E: type, self: *E, proof: model.Certificate, pc: usize) bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    if (site.capture or site.fill or site.unique_field != null) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0 or state.plan.entry(pc).len != 0) return false;
    if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
    if (pc == proof.start) {
        if (site.unique.len != 1 or site.unique[0].local != proof.root or site.unique[0].alias != cow.none) return false;
    } else if (site.unique.len != 0) return false;
    return !intercepted(E, self, pc);
}

/// Separate lowering certificates may redirect a store or projection.
pub fn intercepted(comptime E: type, self: *E, pc: usize) bool {
    const plan = self.cow.?.rc.?.plan;
    for (plan.records.transfers) |transfer| if (transfer.projection == pc or transfer.commit == pc) return true;
    for (plan.records.writes) |write| if (pc >= write.start and pc < write.start + 8) return true;
    return false;
}

/// Keep the old release schedule. A proved empty guard may still be dropped.
pub fn releases(comptime E: type, self: *E, pc: usize, empty: []const usize) bool {
    for (self.cow.?.rc.?.plan.locals.edges) |edge| {
        if (edge.from != pc or edge.to != pc + 1) continue;
        for (edge.releases) |release| {
            const at = @backingInt(release.storage);
            var harmless = false;
            for (empty) |local| harmless = harmless or at == local;
            if (harmless) continue;
            if (@import("qbe_rc_edges.zig").releasesAt(E, self, pc, at) catch true) return true;
        }
    }
    return false;
}

/// No implicit clone installation or recovered place may publish this local.
pub fn unwritten(comptime E: type, self: *E, local: usize) bool {
    const plan = self.cow.?.plan;
    for (plan.sites) |site| {
        for (site.unique) |unique| if (unique.local == local or unique.alias == local) return false;
        if (site.unique_field) |place| if (place.parent == local) return false;
    }
    for (plan.loops.entries) |entries| for (entries) |entry| if (entry.local == local) return false;
    for (plan.aliases) |parent| if (parent == local) return false;
    for (plan.places) |maybe| if (maybe) |place| {
        if (place.parent == local) return false;
        if (place.box) |box| if (box.owner == local) return false;
    };
    return true;
}
