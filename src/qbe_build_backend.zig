//! Resolve native code-generation policy and make it part of cache identity.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const options = @import("qbe_build_options.zig");

/// Fully resolved native code generator and its cache dimensions.
pub const Resolved = struct {
    name: []const u8,
    tool: []const u8,
    tool_identity: []const u8,
    optimization: []const u8,
    lto: bool,
    target_cpu: []const u8,
    target_features: []const u8,
};

/// Resolve tools and effective optimization before opening an object cache.
pub fn resolve(context: fs.Context, parsed: options.Options, zig: []const u8) fs.Error!Resolved {
    if (parsed.codegen == .qbe) {
        const qbe = try context.executable(parsed.codegen.qbe);
        if (std.mem.eql(u8, std.fs.path.basename(qbe), "qbe_llvm.py")) {
            const target = try llvmTarget(context, zig, parsed.target);
            const legacy = context.environ.get("MYLANG_QBE_LLVM_OPT") orelse "-O2";
            const optimization = if (std.mem.startsWith(u8, legacy, "-O")) legacy[2..] else legacy;
            if (!validOptimization(optimization)) return error.NativeToolFailed;
            return .{ .name = "llvm", .tool = qbe, .tool_identity = try adapterIdentity(context, qbe, zig), .optimization = optimization, .lto = false, .target_cpu = target.cpu, .target_features = target.features };
        }
        return .{ .name = "qbe", .tool = qbe, .tool_identity = try context.stamp(qbe), .optimization = "default", .lto = false, .target_cpu = "", .target_features = "" };
    }
    const adapter = if (parsed.codegen.llvm.adapter.len != 0)
        try context.executable(parsed.codegen.llvm.adapter)
    else installed: {
        if (context.self_directory.len == 0) return error.ToolNotFound;
        const candidate = try std.fs.path.resolve(context.allocator, &.{ context.self_directory, "../lib/mylang-llvm/qbe_llvm.py" });
        break :installed try context.executable(candidate);
    };
    const target = try llvmTarget(context, zig, parsed.target);
    return .{
        .name = "llvm",
        .tool = adapter,
        .tool_identity = try adapterIdentity(context, adapter, zig),
        .optimization = effectiveOpt(parsed),
        .lto = parsed.codegen.llvm.lto,
        .target_cpu = target.cpu,
        .target_features = target.features,
    };
}

const LlvmTarget = struct { cpu: []const u8, features: []const u8 };

/// Ask the selected Zig/Clang driver for the exact CPU policy it already uses.
/// LLVM IR function attributes must carry this policy because a later LTO link
/// cannot recover it from the command that originally ingested textual IR.
fn llvmTarget(context: fs.Context, zig: []const u8, target: []const u8) fs.Error!LlvmTarget {
    if (!std.mem.eql(u8, target, "amd64_sysv")) return error.NativeToolFailed;
    const result = try context.captureQuiet(&.{ zig, "cc", "-###", "-S", "-x", "c", "/dev/null", "-o", "/dev/null" });
    if (fs.exitCode(result.term) != 0) {
        try std.Io.File.stderr().writeStreamingAll(context.io, "mylang: Zig could not resolve the LLVM target CPU policy\n");
        return error.NativeToolFailed;
    }
    return parseTarget(context.allocator, result.stderr) catch {
        try std.Io.File.stderr().writeStreamingAll(context.io, "mylang: Zig reported an incompatible or malformed LLVM target CPU policy\n");
        return error.NativeToolFailed;
    };
}

fn parseTarget(allocator: std.mem.Allocator, text: []const u8) error{ OutOfMemory, InvalidTargetProbe }!LlvmTarget {
    const triple = extractQuotedValue(text, "\"-triple\" \"") orelse return error.InvalidTargetProbe;
    if (!validTriple(triple)) return error.InvalidTargetProbe;
    const cpu = extractQuotedValue(text, "\"-target-cpu\" \"") orelse return error.InvalidTargetProbe;
    if (!validTargetToken(cpu)) return error.InvalidTargetProbe;
    var features: std.ArrayList(u8) = .empty;
    errdefer features.deinit(allocator);
    var rest = text;
    const marker = "\"-target-feature\" \"";
    while (std.mem.indexOf(u8, rest, marker)) |at| {
        rest = rest[at + marker.len ..];
        const end = std.mem.indexOfScalar(u8, rest, '"') orelse return error.InvalidTargetProbe;
        const feature = rest[0..end];
        if (!validTargetToken(feature) or feature.len < 2) return error.InvalidTargetProbe;
        if (feature[0] != '+' and feature[0] != '-') return error.InvalidTargetProbe;
        if (features.items.len != 0) try features.append(allocator, ',');
        try features.appendSlice(allocator, feature);
        rest = rest[end + 1 ..];
    }
    const owned_cpu = try allocator.dupe(u8, cpu);
    errdefer allocator.free(owned_cpu);
    return .{ .cpu = owned_cpu, .features = try features.toOwnedSlice(allocator) };
}

fn validTriple(triple: []const u8) bool {
    return std.mem.startsWith(u8, triple, "x86_64-unknown-linux") and std.mem.indexOf(u8, triple, "gnu") != null;
}

fn extractQuotedValue(text: []const u8, marker: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, text, marker) orelse return null;
    const rest = text[at + marker.len ..];
    const end = std.mem.indexOfScalar(u8, rest, '"') orelse return null;
    return rest[0..end];
}

fn validTargetToken(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and std.mem.indexOfScalar(u8, "+-._", byte) == null) return false;
    return true;
}
fn validOptimization(value: []const u8) bool {
    return value.len == 1 and std.mem.indexOfScalar(u8, "0123sz", value[0]) != null;
}

/// Hash every Python source beside the adapter. Installed adapter packages keep
/// their local imports in this directory; conservatively including all siblings
/// also invalidates the cache when a newly imported helper replaces an old one.
fn adapterIdentity(context: fs.Context, adapter: []const u8, zig: []const u8) fs.Error![]const u8 {
    const directory_name = std.fs.path.dirname(adapter) orelse ".";
    var directory = try std.Io.Dir.cwd().openDir(context.io, directory_name, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(context.io);
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterate();
    while (try iterator.next(context.io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".py")) continue;
        try names.append(context.allocator, try context.allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mylang-llvm-adapter-v1\x00");
    hash.update(try context.stamp(zig));
    for (names.items) |name| {
        const path = try std.fs.path.join(context.allocator, &.{ directory_name, name });
        hash.update(name);
        hash.update("\x00");
        hash.update(try context.read(path));
        hash.update("\x00");
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return context.allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

test "LLVM defaults to O3 for ReleaseFast and O0 for Debug" {
    try std.testing.expectEqualStrings("3", effectiveOpt(.{ .codegen = .{ .llvm = .{ .adapter = "adapter" } }, .mode = "ReleaseFast" }));
    try std.testing.expectEqualStrings("0", effectiveOpt(.{ .codegen = .{ .llvm = .{ .adapter = "adapter" } }, .mode = "Debug" }));
    try std.testing.expectEqualStrings("2", effectiveOpt(.{ .codegen = .{ .llvm = .{ .adapter = "adapter", .optimization = "2" } } }));
}

test "LLVM target probe retains CPU and positive and negative features" {
    const parsed = try parseTarget(std.testing.allocator, "clang \"-triple\" \"x86_64-unknown-linux-gnu\" \"-target-cpu\" \"x86-64-v3\" \"-target-feature\" \"+avx2\" \"-target-feature\" \"-avx512f\"\n");
    defer std.testing.allocator.free(parsed.cpu);
    defer std.testing.allocator.free(parsed.features);
    try std.testing.expectEqualStrings("x86-64-v3", parsed.cpu);
    try std.testing.expectEqualStrings("+avx2,-avx512f", parsed.features);
    const baseline = try parseTarget(std.testing.allocator, "clang \"-triple\" \"x86_64-unknown-linux-gnu\" \"-target-cpu\" \"x86-64\"\n");
    defer std.testing.allocator.free(baseline.cpu);
    defer std.testing.allocator.free(baseline.features);
    try std.testing.expectEqualStrings("x86-64", baseline.cpu);
    try std.testing.expectEqualStrings("", baseline.features);
    try std.testing.expectError(error.InvalidTargetProbe, parseTarget(std.testing.allocator, "clang \"-triple\" \"aarch64-unknown-linux-gnu\" \"-target-cpu\" \"generic\"\n"));
}

test "LLVM adapter identity changes when an imported sibling changes" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const adapter = try std.fs.path.join(context.allocator, &.{ directory, "adapter.py" });
    const helper = try std.fs.path.join(context.allocator, &.{ directory, "helper.py" });
    try context.write(adapter, "import helper\n");
    try context.write(helper, "VALUE = 1\n");
    const first = try context.allocator.dupe(u8, try adapterIdentity(context, adapter, "/bin/sh"));
    try context.write(helper, "VALUE = 2\n");
    const second = try adapterIdentity(context, adapter, "/bin/sh");
    try std.testing.expect(!std.mem.eql(u8, first, second));
}
/// Return the explicit or mode-derived LLVM optimization level.
pub fn effectiveOpt(parsed: options.Options) []const u8 {
    return parsed.codegen.llvm.optimization orelse if (std.mem.eql(u8, parsed.mode, "Debug")) "0" else "3";
}
