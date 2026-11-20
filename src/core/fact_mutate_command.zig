//! `mutate-fact-certificates FILE OUTDIR` (plan package C7.4): the single-edit fault mutants of the accepted functions of a fact
//! certificate file, one file each, for the gate to give to both checkers (`fact_mutants.zig` says what each class falsifies).
const std = @import("std");
const text = @import("fact_text.zig");
const validate = @import("validate_facts.zig");
const mutants = @import("fact_mutants.zig");

/// What the command can fail with beyond a status.
pub const Error = std.mem.Allocator.Error || std.Io.File.Writer.Error || error{ReadFailed};

/// The longest certificate file the command reads.
const file_limit: usize = 1 << 30;

/// `mutate-fact-certificates FILE OUTDIR [--per-class N]`: for every function of FILE the validator accepts, up to N (default 3)
/// single-edit mutants of each class (`fact_mutants.zig`), each written as a whole certificate file `OUTDIR/<n>.fact-certificate`,
/// and a manifest on standard output, one line `<n>.fact-certificate <class> <function>` per mutant. Exit 0.
pub fn mutateCommand(init: std.process.Init, arguments: []const []const u8) Error!u8 {
    var positional: [2][]const u8 = undefined;
    var found: usize = 0;
    var per_class: usize = 3;
    var at: usize = 0;
    while (at < arguments.len) : (at += 1) {
        if (std.mem.eql(u8, arguments[at], "--per-class")) {
            at += 1;
            if (at >= arguments.len) return 2;
            per_class = std.fmt.parseInt(usize, arguments[at], 10) catch return 2;
        } else if (found < 2) {
            positional[found] = arguments[at];
            found += 1;
        } else return 2;
    }
    if (found != 2) return 2;
    const allocator = init.arena.allocator();
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, positional[0], allocator, .limited(file_limit)) catch return error.ReadFailed;
    var problem: text.Problem = .{};
    const module = text.parse(allocator, bytes, &problem) catch return 2;
    std.Io.Dir.cwd().createDirPath(init.io, positional[1]) catch return error.ReadFailed;
    const verdicts = try validate.validate(allocator, init.gpa, module, null);
    const accepted = try allocator.alloc(bool, verdicts.len);
    for (verdicts, accepted) |verdict, *flag| flag.* = verdict == .accepted;
    var manifest: std.ArrayList(u8) = .empty;
    var written: usize = 0;
    for (std.enums.values(mutants.Class)) |class| {
        var made: mutants.Mutants = .empty;
        try mutants.mutate(allocator, init.gpa, module, .{ .class = class, .accepted = accepted, .limit = per_class }, &made);
        for (made.items) |mutant| {
            var file: std.ArrayList(u8) = .empty;
            try text.write(allocator, &file, mutant.module);
            const name = try std.fmt.allocPrint(allocator, "{d}.fact-certificate", .{written});
            const path = try std.fs.path.join(allocator, &.{ positional[1], name });
            std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = file.items }) catch return error.ReadFailed;
            try manifest.print(allocator, "{s} {s} ", .{ name, @tagName(class) });
            try text.writeName(allocator, &manifest, module.functions[mutant.function].header.name);
            try manifest.append(allocator, '\n');
            written += 1;
        }
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, manifest.items);
    return 0;
}
