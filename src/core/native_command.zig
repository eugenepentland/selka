//! `selka native show`: print the system libraries built programs load, as builds key them (`native_closure.zig`), the
//! closure's digest, and whether native results are reused here and, when not, why. `selka native approve` is gone
//! (GH-3b): there is nothing to approve, because every machine reuses under keys made from its own libraries' bytes. For
//! one release it says so and exits 0, so a script that still runs it does not break.
const std = @import("std");
const product = @import("selka").product;
const tool_identity = @import("tool_identity.zig");
const zig_lookup = @import("zig_lookup.zig");

/// The command's usage text.
pub const usage =
    \\usage: selka native show [--zig PATH] [--digest]
    \\
    \\Print the system libraries that built programs load (the loader, and every file the loader's cache lists for
    \\libc, libm, libgcc_s and libpthread, plus what /etc/ld.so.preload names), each with what it resolves to and its
    \\SHA-256, then the closure's digest and whether native results are reused on this machine. Native results are
    \\keyed by these files' bytes, so a library update makes the next build cold once; nothing needs approving.
    \\--zig names the toolchain (default: SELKA_ZIG, the Zig bundled with the install, ZIG, zig on PATH).
    \\--digest prints the "toolchain identity" alone, its 64 hexadecimal digits and a newline, and nothing else (a script
    \\that keys its own results by the toolchain, as the component builder does, reads this line).
    \\Two machines share native results exactly when the "toolchain identity" line is the same.
    \\Exit status: 0 printed, 1 the toolchain was not found, 2 usage.
    \\
;

/// What `selka native approve` prints, for one release after it went.
pub const approve_gone = "selka native approve is no longer needed: native results are keyed by the digest of the system " ++
    "libraries, so every machine reuses its own; `selka native show` prints them.\n";

/// The work directory a tool-identity request names; nothing here writes it.
const work_directory = product.work_dir;

/// Run `selka native ARGS` and return its exit status.
pub fn run(init: std.process.Init, args: []const []const u8) u8 {
    if (args.len != 0 and std.mem.eql(u8, args[0], "approve")) {
        print(init, std.Io.File.stdout(), approve_gone);
        return 0;
    }
    const options = parse(args) orelse {
        print(init, std.Io.File.stderr(), usage);
        return 2;
    };
    return show(init, options) catch |err| {
        print(init, std.Io.File.stderr(), because(init, "selka native show: {s}\n", .{@errorName(err)}));
        return 2;
    };
}

/// What `selka native show ARGS` asks for.
const Options = struct {
    /// The toolchain it names ("" for the default).
    zig: []const u8 = "",
    /// Print the toolchain identity alone.
    digest: bool = false,
};

/// The options `selka native show ARGS` gives, or null for a usage error.
fn parse(args: []const []const u8) ?Options {
    if (args.len == 0 or !std.mem.eql(u8, args[0], "show")) return null;
    var options: Options = .{};
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--digest")) {
            options.digest = true;
        } else if (std.mem.eql(u8, arg, "--zig") and index + 1 < args.len) {
            index += 1;
            options.zig = args[index];
        } else if (std.mem.startsWith(u8, arg, "--zig=") and arg.len > "--zig=".len) {
            options.zig = arg["--zig=".len..];
        } else return null;
    }
    return options;
}

fn print(init: std.process.Init, file: std.Io.File, text: []const u8) void {
    file.writeStreamingAll(init.io, text) catch return;
}

fn say(init: std.process.Init, comptime format: []const u8, values: anytype) void {
    print(init, std.Io.File.stdout(), because(init, format, values));
}

fn because(init: std.process.Init, comptime format: []const u8, values: anytype) []const u8 {
    return std.fmt.allocPrint(init.arena.allocator(), format, values) catch "out of memory";
}

fn show(init: std.process.Init, options: Options) tool_identity.Error!u8 {
    const a = init.arena.allocator();
    const zig = if (options.zig.len != 0) options.zig else zig_lookup.fromEnvironment(init.io, a, init.environ_map);
    const request: tool_identity.Request = .{ .arena = a, .io = init.io, .environment = init.environ_map, .executable = zig, .cache = work_directory };
    if (options.digest) return showDigest(init, request, zig);
    const root = tool_identity.builtSystemRoot();
    if (root.len != 0) say(init, "test build: this compiler reads the system libraries below {s}, not /\n", .{root});
    const system = try tool_identity.system(request);
    say(init, "the system libraries built programs load (their bytes key every native result):\n", .{});
    for (system.files) |file| say(init, "  {s} -> {s}\n      {s}\n", .{ file.path, file.resolved, file.sha256 });
    say(init, "  and {d} candidates in the loader's default directories, keyed as absent\n", .{system.absent});
    if (system.preloaded.len == 0) say(init, "/etc/ld.so.preload names nothing that is there\n", .{}) else say(init, "/etc/ld.so.preload names:\n", .{});
    for (system.preloaded) |file| say(init, "  {s} -> {s}\n      {s}\n", .{ file.path, file.resolved, file.sha256 });
    if (system.cache_keyed)
        say(init, "/etc/ld.so.cache: not parsed; its bytes are keyed too\n", .{})
    else
        say(init, "/etc/ld.so.cache: keyed through the files it names\n", .{});
    say(init, "closure digest: {s} (these files alone)\n", .{&system.digest});
    const identity = tool_identity.capture(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        say(init, "reuse: unknown: cannot identify the Zig toolchain `{s}` ({s}); name it with --zig PATH\n{s}", .{ zig, @errorName(err), zig_lookup.hintFor(err) });
        return 1;
    };
    // The digest every native key holds: the closure above with the CPU and the toolchain. Two machines share results
    // exactly when it is the same.
    say(init, "toolchain: {s}\n", .{identity.path});
    say(init, "toolchain identity: {s} (what native keys hold: these files, the CPU and the toolchain)\n", .{&std.fmt.bytesToHex(identity.digest, .lower)});
    if (try tool_identity.reuseRefusal(request, identity)) |why| say(init, "reuse: off: {s}\n", .{why}) else say(init, "reuse: on\n", .{});
    return 0;
}

/// `--digest`: the toolchain identity alone on stdout, or the reason it cannot be had on stderr and status 1.
fn showDigest(init: std.process.Init, request: tool_identity.Request, zig: []const u8) tool_identity.Error!u8 {
    const identity = tool_identity.capture(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        print(init, std.Io.File.stderr(), because(init, "selka native show --digest: cannot identify the Zig toolchain `{s}` ({s})\n{s}", .{ zig, @errorName(err), zig_lookup.hintFor(err) }));
        return 1;
    };
    say(init, "{s}\n", .{&std.fmt.bytesToHex(identity.digest, .lower)});
    return 0;
}
