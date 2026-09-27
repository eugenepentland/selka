//! Bounded live-view reachability for ownership projection proofs.
const typed = @import("typed.zig");

const Search = struct {
    path: [128]usize = undefined,
    remaining: usize = 4096,
};

/// Whether any physical or logical child can contain a live dictionary view.
/// Cycles already on the path add no new children; exhausted bounds refuse
/// ownership-based copy elision rather than assuming an independent value.
pub fn contains(records: []const typed.Record, ty: typed.Type) bool {
    var search: Search = .{};
    return visit(records, ty, &search, 0);
}

fn visit(records: []const typed.Record, ty: typed.Type, search: *Search, depth: usize) bool {
    if (!ty.isAggregate()) return false;
    const index = ty.recordIndex();
    if (index >= records.len) return true;
    for (search.path[0..depth]) |prior| if (prior == index) return false;
    if (depth == search.path.len or search.remaining == 0) return true;
    search.remaining -= 1;
    search.path[depth] = index;
    const record = records[index];
    if (record.shape.builtin == .live_view) return true;
    if (record.contract.callback != null or record.shape.resource != null) return false;
    if (record.shape.domain) |backing| return visit(records, backing, search, depth + 1);
    if (record.shape.array) |array| return visit(records, array.element, search, depth + 1);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (visit(records, payload, search, depth + 1)) return true;
        return false;
    }
    if (record.collection.key) |key| if (visit(records, key, search, depth + 1)) return true;
    if (record.shape.buffer) |element| if (visit(records, element, search, depth + 1)) return true;
    for (record.fields) |field| if (visit(records, field.ty, search, depth + 1)) return true;
    return false;
}
