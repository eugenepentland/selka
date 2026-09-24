//! Build receipts (`BUILD-NOOP-1`): an unchanged build returns as soon as it
//! knows nothing changed, without parsing its manifest, staging objects or
//! consulting the link.
//!
//! After a successful build the driver records, beside the output, a key over
//! everything that decides the output's bytes — the manifest the frontend
//! handed it, the build environment (tools, mode, target, backend, runtime and
//! driver identity) and every link argument — together with the output file's
//! identity (inode, size, modification time). A later build whose key matches
//! and whose output still has that identity is done. Anything else — a changed
//! manifest, a different tool or flag, an output someone replaced, touched or
//! deleted — takes the ordinary path, which rebuilds exactly what changed.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const options = @import("qbe_build_options.zig");
const native_link = @import("native_link.zig");

const Blake = std.crypto.hash.Blake3;
const version = "qbe-build-receipt-v1";

/// What a recorded receipt says about the output now.
pub const State = enum { fresh, replaced, unknown };

/// One build's receipt: where it lives and the key it must carry.
pub const Receipt = struct {
    context: fs.Context,
    output: []const u8,
    key: [64]u8,

    /// The receipt of this build, or null when this build must not skip:
    /// `--run` publishes a temporary, `--report` promises a per-function
    /// account, and a provider or explicit link input can change without
    /// changing the manifest.
    pub fn init(context: fs.Context, parsed: options.Options, identity: []const u8, manifest: []const u8, output: []const u8) ?Receipt {
        if (parsed.run or parsed.report or parsed.provider != null) return null;
        if (native_link.hasInputs(parsed.link_arguments)) return null;
        var hash = Blake.init(.{});
        frame(&hash, version);
        frame(&hash, identity);
        frame(&hash, output);
        frame(&hash, if (parsed.library) "library" else "executable");
        frame(&hash, parsed.mode);
        frame(&hash, parsed.target);
        for (parsed.link_arguments) |argument| frame(&hash, argument);
        frame(&hash, manifest);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        return .{ .context = context, .output = output, .key = std.fmt.bytesToHex(digest, .lower) };
    }

    /// Whether the output is still exactly what the recorded build produced.
    pub fn fresh(self: Receipt) bool {
        return self.state() == .fresh;
    }

    /// What the recorded receipt says about the output now: `fresh` when this
    /// key built it and nobody touched it since, `replaced` when this key built
    /// the file that was there but the file there now is another one, and
    /// `unknown` otherwise. A replaced output must not be kept by the link's own
    /// reuse check, which trusts the sidecar beside it.
    pub fn state(self: Receipt) State {
        const recorded = self.context.read(self.path() catch return .unknown) catch return .unknown;
        if (!std.mem.startsWith(u8, recorded, &self.key)) return .unknown;
        const current = self.line() catch return .replaced;
        return if (std.mem.eql(u8, recorded, current)) .fresh else .replaced;
    }

    /// Remove an output this key did not leave behind, so the build links a
    /// new one rather than keeping whatever replaced it.
    pub fn discard(self: Receipt) void {
        std.Io.Dir.cwd().deleteFile(self.context.io, self.output) catch |err| switch (err) {
            error.FileNotFound => return,
            // A file that cannot be removed is overwritten by the link anyway.
            else => return,
        };
    }

    /// Record this build's key and its output's identity. Best effort: a
    /// receipt that cannot be written only costs the next build its shortcut.
    pub fn record(self: Receipt) void {
        const current = self.line() catch return;
        const file = self.path() catch return;
        self.context.atomic(file, current) catch return;
    }

    fn path(self: Receipt) fs.Error![]const u8 {
        return std.fmt.allocPrint(self.context.allocator, "{s}.qbe-receipt", .{self.output});
    }
    /// The key and the output's current inode, size and modification time.
    fn line(self: Receipt) fs.Error![]const u8 {
        const stat = try std.Io.Dir.cwd().statFile(self.context.io, self.output, .{});
        if (stat.kind != .file) return error.FileNotFound;
        return std.fmt.allocPrint(self.context.allocator, "{s}\n{d} {d} {d}\n", .{ &self.key, stat.inode, stat.size, stat.mtime.nanoseconds });
    }
};

fn frame(hash: *Blake, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

// spec: BUILD-NOOP-1
test "a receipt holds only while the key and the output's identity are unchanged" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const output = try std.fs.path.join(context.allocator, &.{ root, "program" });
    try context.write(output, "binary");
    const parsed: options.Options = .{ .source = "main.my", .output = output, .mode = "Debug" };
    const receipt = Receipt.init(context, parsed, "environment", "{\"functions\":[]}", output).?;
    try std.testing.expect(!receipt.fresh());
    receipt.record();
    try std.testing.expect(receipt.fresh());
    // Another manifest, environment or flag is another key.
    try std.testing.expect(!Receipt.init(context, parsed, "environment", "{\"functions\":[1]}", output).?.fresh());
    try std.testing.expect(!Receipt.init(context, parsed, "other tools", "{\"functions\":[]}", output).?.fresh());
    var library = parsed;
    library.library = true;
    try std.testing.expect(!Receipt.init(context, library, "environment", "{\"functions\":[]}", output).?.fresh());
    // A replaced output is not the recorded one, and a missing output never is.
    try context.write(output, "another binary");
    try std.testing.expect(!receipt.fresh());
    try std.testing.expectEqual(State.replaced, receipt.state());
    receipt.discard();
    try std.testing.expect(!context.exists(output));
    try std.testing.expectEqual(State.replaced, receipt.state());
    try std.testing.expectEqual(State.unknown, Receipt.init(context, parsed, "environment", "{}", output).?.state());
    // Builds that promise work or read inputs the manifest does not name never skip.
    var reported = parsed;
    reported.report = true;
    try std.testing.expect(Receipt.init(context, reported, "environment", "{}", output) == null);
    var running = parsed;
    running.run = true;
    try std.testing.expect(Receipt.init(context, running, "environment", "{}", output) == null);
}
