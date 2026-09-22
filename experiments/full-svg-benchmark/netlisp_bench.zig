//! Thin benchmark entry point for EDA's production NetLisp evaluator and SVG renderer.
//! Copy this file into the EDA `src/` directory before compiling it as a root module.

const std = @import("std");
const Evaluator = @import("eval/evaluator.zig").Evaluator;
const modules = @import("eval/modules.zig");
const env = @import("eval/env.zig");
const render_html = @import("render_html.zig");
const json = @import("json_writer.zig");

pub var process_io: std.Io = .failing;

pub fn main(init: std.process.Init) !void {
    process_io = init.io;
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4 and args.len != 6) return error.InvalidArguments;
    if (args.len == 6 and !std.mem.eql(u8, args[4], "--verify")) return error.InvalidArguments;

    const project_dir = args[1];
    const module_name = args[2];
    const output_path = args[3];

    var evaluator = Evaluator.init(allocator, project_dir);
    defer evaluator.deinit();
    const value = try modules.instantiateStandalone(&evaluator, module_name);
    const block = switch (value) {
        .design_block => |built| built,
        else => return error.ExpectedDesignBlock,
    };

    var ctx = try render_html.setupRenderCtx(allocator, block);
    ctx.project_dir = project_dir;
    var pin_groups: std.ArrayList(env.PinGroup) = .empty;
    try collectPinGroups(allocator, block, &pin_groups);

    var svg: std.Io.Writer.Allocating = .init(allocator);
    defer svg.deinit();
    for (ctx.hub_order.items) |hub_ref| {
        _ = try render_html.renderHubSvgForView(
            &ctx,
            &svg.writer,
            allocator,
            pin_groups.items,
            hub_ref,
            .functional,
        );
    }
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = svg.written() });

    if (args.len == 6) try writeVerification(init.io, allocator, block, args[5]);
}

fn collectPinGroups(
    allocator: std.mem.Allocator,
    block: *const env.DesignBlock,
    out: *std.ArrayList(env.PinGroup),
) !void {
    for (block.sections) |section| {
        try out.appendSlice(allocator, section.pin_groups);
        for (section.sub_sections) |sub| try out.appendSlice(allocator, sub.pin_groups);
    }
    for (block.sub_blocks) |sub| try collectPinGroups(allocator, sub.block, out);
}

fn writeVerification(io: std.Io, allocator: std.mem.Allocator, block: *const env.DesignBlock, path: []const u8) !void {
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const w = &output.writer;
    try w.writeAll("{\"instances\":[");
    for (block.instances, 0..) |instance, i| {
        if (i != 0) try w.writeByte(',');
        try w.writeAll("{\"ref\":");
        try json.writeString(w, instance.ref_des);
        try w.writeAll(",\"component\":");
        try json.writeString(w, instance.component);
        try w.writeByte('}');
    }
    try w.writeAll("],\"nets\":[");
    for (block.nets, 0..) |net, i| {
        if (i != 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try json.writeString(w, net.name);
        try w.writeAll(",\"pins\":[");
        for (net.pins, 0..) |pin, j| {
            if (j != 0) try w.writeByte(',');
            try w.writeAll("{\"ref\":");
            try json.writeString(w, pin.ref_des);
            try w.writeAll(",\"pin\":");
            try json.writeString(w, pin.pin);
            try w.writeByte('}');
        }
        try w.writeAll("]}");
    }
    try w.writeAll("],\"ports\":[");
    for (block.ports, 0..) |port, i| {
        if (i != 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        try json.writeString(w, port.name);
        try w.writeAll(",\"net\":");
        try json.writeString(w, port.net);
        try w.writeAll(",\"direction\":");
        try json.writeString(w, port.direction);
        try w.writeByte('}');
    }
    try w.writeAll("]}\n");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = output.written() });
}
