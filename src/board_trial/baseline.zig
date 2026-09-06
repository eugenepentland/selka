//! Standalone Zig implementation of the fixed trial contract, not the full EDA DRC.
const std = @import("std");
const m = @import("model.zig");
const Kernel = @import("kernel.zig").Kernel;
fn has(comptime T: type, values: []const T, needle: T) bool {
    return std.mem.indexOfScalar(T, values, needle) != null;
}
fn catalog(comptime T: type, values: []const T, duplicate: m.InputProblem) ?m.InputProblem {
    for (values, 0..) |id, index| {
        if (@backingInt(id) == 0) return .invalid_id;
        if (has(T, values[0..index], id)) return duplicate;
    }
    return null;
}
fn preflight(board: m.Board) ?m.InputProblem {
    if (!m.valid(board.outline)) return .invalid_bounds;
    if (catalog(m.ComponentId, board.components, .duplicate_component)) |problem| return problem;
    if (catalog(m.NetId, board.nets, .duplicate_net)) |problem| return problem;
    for (board.regions) |region| {
        if (!m.valid(region.rect)) return .invalid_bounds;
        if (!(region.blocks.component or region.blocks.track or region.blocks.via)) return .empty_blocks;
        for (region.allow_nets) |net| if (!has(m.NetId, board.nets, net)) return .unknown_allow_net;
    }
    for (board.features) |feature| {
        if (!m.valid(m.rectangle(feature))) return .invalid_bounds;
        switch (feature) {
            .component => |value| if (!has(m.ComponentId, board.components, value.id)) {
                return .missing_component;
            },
            .track => |value| if (!has(m.NetId, board.nets, value.net)) {
                return .missing_net;
            },
            .via => |value| if (!has(m.NetId, board.nets, value.net)) {
                return .missing_net;
            },
        }
    }
    return null;
}
fn coversSide(region: m.RegionFace, side: m.Face) bool {
    return switch (region) {
        .both => true,
        .top => side == .top,
        .bottom => side == .bottom,
    };
}
fn coversLayer(region: m.RegionFace, layer: m.Layer) bool {
    if (region == .both) return true;
    return switch (layer) {
        .front => region == .top,
        .back => region == .bottom,
        .inner => false,
    };
}
fn applies(region: m.Region, feature: m.Feature) bool {
    return switch (feature) {
        .component => |value| region.blocks.component and coversSide(region.face, value.face),
        .track => |value| region.blocks.track and coversLayer(region.face, value.layer) and !has(m.NetId, region.allow_nets, value.net),
        .via => |value| region.blocks.via and !has(m.NetId, region.allow_nets, value.net),
    };
}
fn inside(outer: m.Rect, inner: m.Rect) bool {
    if (@backingInt(inner.x) < @backingInt(outer.x) or @backingInt(inner.y) < @backingInt(outer.y)) return false;
    if (@backingInt(inner.x) + @backingInt(inner.width) > @backingInt(outer.x) + @backingInt(outer.width)) return false;
    return @backingInt(inner.y) + @backingInt(inner.height) <= @backingInt(outer.y) + @backingInt(outer.height);
}
/// Validate all input first, then visit features and regions in contract order.
pub fn validate(board: m.Board, kernel: *Kernel) m.Outcome {
    if (preflight(board)) |problem| return .{ .err = .{ .input = problem } };
    var report: m.Report = .{};
    for (board.features, 0..) |feature, index| {
        const rect = m.rectangle(feature);
        if (!inside(board.outline, rect)) m.add(&report, index, .outside_board, null);
        for (board.regions, 0..) |region, region_index| {
            if (!applies(region, feature)) continue;
            switch (kernel.intersect(rect, region.rect)) {
                .err => |problem| return .{ .err = .{ .geometry = problem } },
                .ok => |hit| if (hit) {
                    m.add(&report, index, .keepout, region_index);
                },
            }
        }
    }
    return .{ .ok = report };
}
