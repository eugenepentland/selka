//! `selka dump-syntax`: the command line of the stage-1 syntax oracle (`syntax_dump.zig`).
const std = @import("std");
const input_probe = @import("input_probe.zig");

const usage = "usage: selka dump-syntax <file.selka> [--module | --program] [--trusted] [--store-check]\n" ++
    "       selka dump-syntax --layout\n" ++
    "       selka dump-syntax --diff REFERENCE CANDIDATE\n";

/// The command, built over the compiler module `language` (the executable's `selka` module, or `compiler.zig` in a test root).
pub fn Command(comptime language: type) type {
    return struct {
        /// What the command line asked for.
        const Request = union(enum) {
            dump: struct { path: []const u8, options: language.syntax_dump.Options },
            layout,
            diff: struct { reference: []const u8, candidate: []const u8 },
        };

        /// Read the arguments after the command name; null when they are not one of the three forms.
        pub fn parse(args: []const []const u8) ?Request {
            var path: ?[]const u8 = null;
            var options: language.syntax_dump.Options = .{};
            var layout = false;
            var index: usize = 0;
            while (index < args.len) : (index += 1) {
                const arg = args[index];
                if (std.mem.eql(u8, arg, "--layout")) {
                    layout = true;
                } else if (std.mem.eql(u8, arg, "--module")) {
                    options.mode = .module;
                } else if (std.mem.eql(u8, arg, "--program")) {
                    options.mode = .program;
                } else if (std.mem.eql(u8, arg, "--trusted")) {
                    options.trusted = true;
                } else if (std.mem.eql(u8, arg, "--store-check")) {
                    options.store_check = true;
                } else if (std.mem.eql(u8, arg, "--diff")) {
                    if (args.len != 3 or index != 0) return null;
                    return .{ .diff = .{ .reference = args[1], .candidate = args[2] } };
                } else if (std.mem.startsWith(u8, arg, "--") or path != null) {
                    return null;
                } else path = arg;
            }
            if (layout) return if (path == null) .layout else null;
            const file = path orelse return null;
            return .{ .dump = .{ .path = file, .options = options } };
        }

        /// Run `selka dump-syntax` with the arguments after the command name. A file
        /// that does not parse is still a successful dump (its frame says `refused`), so
        /// the status is 0 whenever the file could be read; `--diff` exits 1 when the two
        /// frames differ and prints how, and 0 when they are the same bytes.
        pub fn run(process: std.process.Init, args: []const []const u8) !u8 {
            const request = parse(args) orelse {
                try std.Io.File.stderr().writeStreamingAll(process.io, usage);
                return 2;
            };
            const allocator = process.gpa;
            switch (request) {
                .layout => {
                    const description = try language.syntax_dump.layout(allocator);
                    defer allocator.free(description);
                    try std.Io.File.stdout().writeStreamingAll(process.io, description);
                    return 0;
                },
                .dump => |dump| {
                    if (try input_probe.check(allocator, process.io, "dump-syntax", dump.path, false)) |refusal| {
                        defer allocator.free(refusal);
                        try std.Io.File.stderr().writeStreamingAll(process.io, refusal);
                        return input_probe.refused_status;
                    }
                    const bytes = try std.Io.Dir.cwd().readFileAlloc(process.io, dump.path, allocator, .limited(16 * 1024 * 1024));
                    defer allocator.free(bytes);
                    if (dump.options.store_check) {
                        const verdict = try language.syntax_dump.storeCheck(allocator, dump.path, bytes, dump.options);
                        defer allocator.free(verdict.line);
                        try std.Io.File.stdout().writeStreamingAll(process.io, verdict.line);
                        return if (verdict.ok) 0 else 1;
                    }
                    const document = try language.syntax_dump.frame(allocator, dump.path, bytes, dump.options);
                    defer allocator.free(document);
                    try std.Io.File.stdout().writeStreamingAll(process.io, document);
                    return 0;
                },
                .diff => |diff| return compare(process, allocator, diff.reference, diff.candidate),
            }
        }

        fn compare(process: std.process.Init, allocator: std.mem.Allocator, reference_path: []const u8, candidate_path: []const u8) !u8 {
            for ([_][]const u8{ reference_path, candidate_path }) |path| {
                if (try input_probe.check(allocator, process.io, "dump-syntax", path, false)) |refusal| {
                    defer allocator.free(refusal);
                    try std.Io.File.stderr().writeStreamingAll(process.io, refusal);
                    return input_probe.refused_status;
                }
            }
            const reference = try std.Io.Dir.cwd().readFileAlloc(process.io, reference_path, allocator, .limited(1 << 30));
            defer allocator.free(reference);
            const candidate = try std.Io.Dir.cwd().readFileAlloc(process.io, candidate_path, allocator, .limited(1 << 30));
            defer allocator.free(candidate);
            const told = try language.syntax_dump.difference(allocator, reference, candidate) orelse return 0;
            defer allocator.free(told);
            try std.Io.File.stdout().writeStreamingAll(process.io, told);
            try std.Io.File.stdout().writeStreamingAll(process.io, "\n");
            return 1;
        }
    };
}
