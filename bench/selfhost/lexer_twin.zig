//! Zig twin of selfhost/frontend/lexer_bench.selka: the Zig lexer over the same files held in memory.
//!
//!     lexer_twin LIST ROUNDS
//!
//! LIST names one source file per line. All files are read first; then each of ROUNDS+1 rounds (round 0
//! warms up) times, over every file, `lexRange` (the tokenizing pass alone), `lex` (tokenizing plus the
//! layout pass) and, by difference, the layout pass. One JSON line per round is written to standard output.
const std = @import("std");
const lexer = @import("lexer");

const Sink = @typeInfo(@typeInfo(@TypeOf(lexer.lex)).@"fn".param_types[2].?).pointer.child;

fn nanoseconds(io: std.Io, since: std.Io.Timestamp) i96 {
    return since.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.Usage;
    const rounds = try std.fmt.parseInt(usize, args[2], 10);
    const list = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], gpa, .limited(64 << 20));
    defer gpa.free(list);
    var files: std.ArrayList([]u8) = .empty;
    defer {
        for (files.items) |bytes| gpa.free(bytes);
        files.deinit(gpa);
    }
    var total_bytes: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, list, '\n');
    while (lines.next()) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, gpa, .limited(16 << 20));
        total_bytes += bytes.len;
        try files.append(gpa, bytes);
    }
    var buffer: [1024]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    for (0..rounds + 1) |round| {
        var tokens: usize = 0;
        _ = arena.reset(.retain_capacity);
        var started = std.Io.Timestamp.now(init.io, .awake);
        for (files.items) |bytes| {
            var sink: Sink = .{ .allocator = arena.allocator() };
            _ = lexer.lexRange(arena.allocator(), bytes, .{ .start = 0, .end = bytes.len }, &sink) catch return error.LexFailed;
        }
        const tokenize_ns = nanoseconds(init.io, started);
        _ = arena.reset(.retain_capacity);
        started = std.Io.Timestamp.now(init.io, .awake);
        for (files.items) |bytes| {
            var sink: Sink = .{ .allocator = arena.allocator() };
            const got = lexer.lex(arena.allocator(), bytes, &sink) catch return error.LexFailed;
            tokens += got.len;
        }
        const lex_ns = nanoseconds(init.io, started);
        try out.interface.print("{{\"arm\":\"zig\",\"round\":{d},\"files\":{d},\"bytes\":{d},\"tokens\":{d},\"tokenize_ns\":{d},\"lex_ns\":{d}}}\n", .{ round, files.items.len, total_bytes, tokens, tokenize_ns, lex_ns });
        try out.interface.flush();
    }
}
