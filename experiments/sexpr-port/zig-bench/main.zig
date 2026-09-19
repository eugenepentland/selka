//! Benchmark driver for the Zig S-expression reader.
//!
//! It is the Zig side of `experiments/sexpr-port/bench` and mirrors `main.my`'s
//! two workloads exactly:
//!
//!   zig-bench <input.sexp>             print a node census (parse + walk)
//!   zig-bench <input.sexp> --render    print the canonical rendering
//!
//! Both implementations therefore read the same file, parse it with the same
//! grammar, and either walk the tree once or render it once. The project
//! contains only the sexpr closure (`src/sexpr` plus the one `infra/fs.zig` the
//! printer imports) so its `zig build` time is comparable to building the
//! mylang port rather than to building the whole EDA application.
//!
//! `pub var process_io` must live in the root file because `infra/fs.zig` reads
//! it through `@import("root")`, and `main` takes `std.process.Init` to install
//! the I/O capability for reading the input and writing stdout.

const std = @import("std");
const ast = @import("src/sexpr/ast.zig");
const sexpr_tokenizer = @import("src/sexpr/tokenizer.zig");
const sexpr_parser = @import("src/sexpr/parser.zig");
const printer = @import("src/sexpr/printer.zig");

/// Process I/O capability handed to the rest of the source graph.
pub var process_io: std.Io = .failing;

/// Upper bound on an input file; matches the golden harness.
const max_input_bytes: u64 = 256 * 1024 * 1024;

/// Node census produced by the default workload, field-for-field the one
/// `main.my` prints so the two sides do the same traversal work.
const Census = struct {
    forms: usize = 0,
    nodes: usize = 0,
    atoms: usize = 0,
    strings: usize = 0,
    ints: usize = 0,
    floats: usize = 0,
    measures: usize = 0,
    depth: usize = 0,
    values: f64 = 0,
};

fn tally(counts: *Census, node: ast.Node, depth: usize) void {
    counts.nodes += 1;
    if (depth > counts.depth) counts.depth = depth;
    switch (node.tag) {
        .list => |children| {
            counts.forms += 1;
            for (children) |child| tally(counts, child, depth + 1);
        },
        .atom => counts.atoms += 1,
        .string => counts.strings += 1,
        .int => counts.ints += 1,
        .float => counts.floats += 1,
        .unit_val => counts.measures += 1,
    }
    if (node.asNumber()) |value| counts.values += value;
}

fn fail(init: std.process.Init, message: []const u8, code: u8) noreturn {
    std.Io.File.stderr().writeStreamingAll(init.io, message) catch {};
    std.process.exit(code);
}

pub fn main(init: std.process.Init) !void {
    process_io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) fail(init, "usage: zig-bench <input.sexp> [--read|--tokens|--parse|--render]\n", 2);

    const path = args[1];
    const mode = if (args.len > 2) args[2] else "";

    const source = std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .limited64(max_input_bytes)) catch |err| {
        fail(init, @errorName(err), 2);
    };

    var buffer: [256]u8 = undefined;
    if (std.mem.eql(u8, mode, "--read")) {
        const line = try std.fmt.bufPrint(&buffer, "bytes={d}\n", .{source.len});
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return;
    }
    // Micro workloads that mirror the audit drivers h_loop and e_scan: an empty
    // loop over the byte count, and a byte scan with the same two comparisons.
    if (std.mem.eql(u8, mode, "--loop")) {
        var index: usize = 0;
        while (index < source.len) : (index += 1) {}
        const line = try std.fmt.bufPrint(&buffer, "bytes={d} index={d}\n", .{ source.len, index });
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return;
    }
    if (std.mem.eql(u8, mode, "--scan")) {
        var count: usize = 0;
        var index: usize = 0;
        while (index < source.len) : (index += 1) {
            if (source[index] == '(' or source[index] == ')') count += 1;
        }
        const line = try std.fmt.bufPrint(&buffer, "bytes={d} delims={d}\n", .{ source.len, count });
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return;
    }
    if (std.mem.eql(u8, mode, "--tokens")) {
        var tokenizer = sexpr_tokenizer.Tokenizer.init(source);
        var count: usize = 0;
        while (true) {
            const token = tokenizer.next() catch |err| fail(init, @errorName(err), 1);
            if (token.tag == .eof) break;
            count += 1;
        }
        const line = try std.fmt.bufPrint(&buffer, "tokens={d}\n", .{count});
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return;
    }

    const nodes = sexpr_parser.parse(arena, source) catch |err| {
        fail(init, @errorName(err), 1);
    };
    if (std.mem.eql(u8, mode, "--parse")) {
        const line = try std.fmt.bufPrint(&buffer, "roots={d}\n", .{nodes.len});
        try std.Io.File.stdout().writeStreamingAll(init.io, line);
        return;
    }

    if (std.mem.eql(u8, mode, "--render")) {
        const text = try printer.print(arena, nodes);
        try std.Io.File.stdout().writeStreamingAll(init.io, text);
        try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
        return;
    }

    var counts: Census = .{};
    for (nodes) |node| tally(&counts, node, 0);
    const line = try std.fmt.bufPrint(
        &buffer,
        "forms={d} nodes={d} atoms={d} strings={d} ints={d} floats={d} measures={d} max_depth={d} value_sum={d}\n",
        .{ counts.forms, counts.nodes, counts.atoms, counts.strings, counts.ints, counts.floats, counts.measures, counts.depth, counts.values },
    );
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}
