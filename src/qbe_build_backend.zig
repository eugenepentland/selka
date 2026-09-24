//! Resolve native code-generation policy and make it part of cache identity.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const options = @import("qbe_build_options.zig");
const llvm = @import("qbe_build_llvm.zig");

/// Fully resolved native code generator and its cache dimensions.
pub const Resolved = struct {
    name: []const u8,
    tool: []const u8,
    tool_identity: []const u8,
    optimization: []const u8,
    lto: options.Lto,
    target_cpu: []const u8,
    target_features: []const u8,
};

/// Resolve tools and effective optimization before opening an object cache.
pub fn resolve(context: fs.Context, parsed: options.Options, zig: []const u8) fs.Error!Resolved {
    switch (parsed.codegen) {
        // No backend was named: build with QBE in either optimize mode. An
        // edit-build loop wants the compile that takes a second, not the LTO
        // link that takes many; `--release` names the LLVM path explicitly.
        .auto => return resolveQbe(context, parsed, zig, "qbe"),
        .qbe => |path| return resolveQbe(context, parsed, zig, path),
        .llvm => |controls| return resolveLlvm(context, parsed, zig, controls),
    }
}

/// The basename of the retired Python adapter. `--qbe PATH` naming a file of
/// this name is the legacy spelling of the LLVM backend at its legacy `-O2`
/// without LTO; it selects the built-in translator and never reads, resolves
/// or executes the file (LLVM-ZIG-1).
pub const legacy_adapter = "qbe_llvm.py";

/// Whether a `--qbe` path is the legacy spelling of the LLVM backend.
pub fn legacyLlvm(path: []const u8) bool {
    return std.mem.eql(u8, std.fs.path.basename(path), legacy_adapter);
}

/// The optimization level the legacy spelling builds at: `MYLANG_QBE_LLVM_OPT`
/// (default `-O2`), without its `-O`.
pub fn legacyOptimization(environ: *const std.process.Environ.Map) ?[]const u8 {
    const legacy = environ.get("MYLANG_QBE_LLVM_OPT") orelse "-O2";
    const optimization = if (std.mem.startsWith(u8, legacy, "-O")) legacy[2..] else legacy;
    return if (validOptimization(optimization)) optimization else null;
}

/// The identity the LLVM arm's objects are keyed by: the translator's version
/// and whichever of its switches the environment turns off. The translator is
/// part of this compiler, so its code is also in the driver identity.
pub fn translatorIdentity(environ: *const std.process.Environ.Map) []const u8 {
    return llvm.Toggles.read(environ).identity();
}

/// Resolve the QBE tool; the legacy `--qbe qbe_llvm.py` spelling resolves the
/// built-in LLVM translator instead of any file.
fn resolveQbe(context: fs.Context, parsed: options.Options, zig: []const u8, path: []const u8) fs.Error!Resolved {
    if (legacyLlvm(path)) {
        const target = try llvmTarget(context, zig, parsed.target);
        const optimization = legacyOptimization(context.environ) orelse return error.NativeToolFailed;
        return .{ .name = "llvm", .tool = zig, .tool_identity = translatorIdentity(context.environ), .optimization = optimization, .lto = .off, .target_cpu = target.cpu, .target_features = target.features };
    }
    const qbe = try context.executable(path);
    return .{ .name = "qbe", .tool = qbe, .tool_identity = try context.stamp(qbe), .optimization = "default", .lto = .off, .target_cpu = "", .target_features = "" };
}

/// Resolve the built-in LLVM backend (LLVM-ZIG-1): the translator runs in this
/// process and its IR is compiled by the bundled clang, so nothing but Zig
/// itself has to be found.
fn resolveLlvm(context: fs.Context, parsed: options.Options, zig: []const u8, controls: options.Llvm) fs.Error!Resolved {
    const target = try llvmTarget(context, zig, parsed.target);
    return .{
        .name = "llvm",
        .tool = zig,
        .tool_identity = translatorIdentity(context.environ),
        .optimization = controls.optimization orelse defaultOpt(parsed.mode),
        .lto = controls.lto,
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

test "LLVM defaults to O3 for ReleaseFast and O0 for Debug" {
    try std.testing.expectEqualStrings("3", effectiveOpt(.{ .codegen = .{ .llvm = .{} }, .mode = "ReleaseFast" }));
    try std.testing.expectEqualStrings("0", effectiveOpt(.{ .codegen = .{ .llvm = .{} }, .mode = "Debug" }));
    try std.testing.expectEqualStrings("2", effectiveOpt(.{ .codegen = .{ .llvm = .{ .optimization = "2" } } }));
}

/// A stand-in for `zig` whose `cc -###` reports a baseline x86-64 target.
fn fakeZig(context: fs.Context, directory: []const u8) ![]const u8 {
    const zig = try std.fs.path.join(context.allocator, &.{ directory, "zig" });
    try context.write(zig, "#!/bin/sh\necho ' \"clang\" \"-cc1\" \"-triple\" \"x86_64-unknown-linux-gnu\" \"-target-cpu\" \"x86-64\"' >&2\n");
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, zig, .executable_file, .{});
    return zig;
}

// spec: BUILD-BACKEND-2
test "an unnamed backend resolves QBE in either mode and an LLVM build resolves no tool beyond Zig" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const qbe = try std.fs.path.join(context.allocator, &.{ directory, "qbe" });
    try context.write(qbe, "#!/bin/sh\nexit 0\n");
    try std.Io.Dir.cwd().setFilePermissions(std.testing.io, qbe, .executable_file, .{});
    try environment.put("PATH", directory);
    context.self_directory = "";
    const zig = try fakeZig(context, directory);
    // An unnamed backend is QBE whatever the mode.
    try std.testing.expectEqualStrings("qbe", (try resolve(context, .{ .mode = "Debug" }, zig)).name);
    try std.testing.expectEqualStrings("qbe", (try resolve(context, .{ .mode = "ReleaseFast" }, zig)).name);
    // The release build is the translator inside this compiler: with nothing
    // installed beside it, it resolves Zig's target policy and names no other tool.
    const release = try resolve(context, .{ .mode = "ReleaseFast", .codegen = options.release_codegen }, zig);
    try std.testing.expectEqualStrings("llvm", release.name);
    try std.testing.expectEqualStrings(zig, release.tool);
    try std.testing.expectEqualStrings(llvm.version, release.tool_identity);
    try std.testing.expectEqualStrings("x86-64", release.target_cpu);
    try std.testing.expectEqual(options.Lto.full, release.lto);
}

// spec: BUILD-BACKEND-5
test "no LLVM build resolves an adapter, and the legacy qbe_llvm.py spelling names the built-in translator" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    context.self_directory = "";
    const directory = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const zig = try fakeZig(context, directory);
    // The retired variable names nothing that is read.
    try environment.put("MYLANG_LLVM_ADAPTER", "/no/such/adapter.py");
    try std.testing.expectEqualStrings(llvm.version, (try resolve(context, .{ .codegen = options.release_codegen }, zig)).tool_identity);
    // A `--qbe` path named like the old adapter is the LLVM backend at `-O2`
    // without LTO; the file does not exist and is never looked at.
    const legacy = try resolve(context, .{ .codegen = .{ .qbe = "/no/such/dir/qbe_llvm.py" } }, zig);
    try std.testing.expectEqualStrings("llvm", legacy.name);
    try std.testing.expectEqualStrings("2", legacy.optimization);
    try std.testing.expectEqual(options.Lto.off, legacy.lto);
    try environment.put("MYLANG_QBE_LLVM_OPT", "-O3");
    try std.testing.expectEqualStrings("3", (try resolve(context, .{ .codegen = .{ .qbe = "qbe_llvm.py" } }, zig)).optimization);
    try environment.put("MYLANG_QBE_LLVM_OPT", "-O9");
    try std.testing.expectError(error.NativeToolFailed, resolve(context, .{ .codegen = .{ .qbe = "qbe_llvm.py" } }, zig));
}

// spec-case: LLVM-ZIG-1
test "the translator identity names every switch that is off" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expectEqualStrings("mylang-llvm-translator-v1", translatorIdentity(&environment));
    try environment.put("MYLANG_QBE_LLVM_STICKY", "0");
    try std.testing.expectEqualStrings("mylang-llvm-translator-v1;sticky=0", translatorIdentity(&environment));
    try environment.put("MYLANG_QBE_LLVM_ALIAS", "0");
    try environment.put("MYLANG_QBE_LLVM_ELEMENT_GEP", "0");
    try std.testing.expectEqualStrings("mylang-llvm-translator-v1;alias=0;gep=0;sticky=0", translatorIdentity(&environment));
    try environment.put("MYLANG_QBE_LLVM_ALIAS", "1");
    try std.testing.expectEqualStrings("mylang-llvm-translator-v1;gep=0;sticky=0", translatorIdentity(&environment));
}

/// Return the explicit or mode-derived LLVM optimization level.
pub fn effectiveOpt(parsed: options.Options) []const u8 {
    return switch (parsed.codegen) {
        .llvm => |controls| controls.optimization orelse defaultOpt(parsed.mode),
        .auto, .qbe => defaultOpt(parsed.mode),
    };
}
/// The optimization level a mode implies: unoptimized Debug, otherwise O3.
fn defaultOpt(mode: []const u8) []const u8 {
    return if (std.mem.eql(u8, mode, "Debug")) "0" else "3";
}
