//! Dedicated native-build options avoid coupling the semantic CLI to tool policy.
const std = @import("std");
/// Malformed or unsupported command-line build controls.
pub const Error = error{InvalidBuildArguments};
/// Whether `argument` is a runtime/authority control that `build --run` should
/// forward to the temporary executable instead of interpreting as a build flag.
pub fn runtimeControl(argument: []const u8) bool {
    if (std.mem.eql(u8, argument, "--restrict")) return true;
    if (std.mem.eql(u8, argument, "--allow-clock")) return true;
    if (std.mem.eql(u8, argument, "--allow-host")) return true;
    if (std.mem.eql(u8, argument, "--allow-all")) return true;
    if (std.mem.eql(u8, argument, "--gc-stress")) return true;
    if (std.mem.eql(u8, argument, "--print-result")) return true;
    inline for (.{ "--allow-read=", "--allow-write=", "--allow-endpoint=", "--allow-random", "--allow-env", "--max-steps=", "--max-frames=", "--timeout=" }) |prefix| {
        if (std.mem.startsWith(u8, argument, prefix)) return true;
        if (std.mem.eql(u8, argument, prefix[0 .. prefix.len - 1])) return true;
    }
    return false;
}
/// Whether a build asked to keep the linked executable's symbol table, which is
/// what lets `perf report` attribute samples to guest functions. A measurement
/// switch: it changes no generated code and no cached object, only the link.
pub fn keepSymbols(args: []const []const u8) bool {
    for (args) |argument| if (std.mem.eql(u8, argument, "--keep-symbols")) return true;
    return false;
}
/// The refusal every building or executing command answers `--unchecked` with
/// (`RELEASE-CHECKED-1`). The policy made a would-be trap undefined behaviour,
/// so an optimized build could compute a different result than a checked one;
/// it is gone, and naming it is a usage error rather than an unknown flag.
pub const unchecked_removed = "--unchecked was removed: every build keeps overflow, cast and bounds checks so optimization never changes a program's result\n";
/// Whether the command's own arguments name the removed `--unchecked` switch,
/// bare or with a value. Guest arguments after `--` are never read, so a guest
/// may still receive the spelling.
pub fn uncheckedRequested(args: []const []const u8) bool {
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) return false;
        if (std.mem.eql(u8, argument, "--unchecked") or std.mem.startsWith(u8, argument, "--unchecked=")) return true;
    }
    return false;
}
/// Whether a build asked for `phase-timings-v1` JSON Lines on stderr. The
/// request travels in the build arguments because it is observation only: it
/// changes no generated code, no cached object and no linked artifact. Guest
/// arguments after `--` belong to a `--run` guest, so they are never read.
pub fn timingsJson(args: []const []const u8) bool {
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) return false;
        if (std.mem.eql(u8, argument, "--timings=json")) return true;
    }
    return false;
}
/// The per-project object cache used when no `--cache-dir` selects another; a build
/// left at this default may share its runtime tree with other projects, while an
/// explicit `--cache-dir` keeps every artifact hermetically under that directory.
pub const default_cache = ".mylang-cache/qbe";
/// Optimize mode a native build uses when no `--mode` selects another: `mylang
/// build` and `mylang run` are asked for speed, so the fast mode is the default
/// and an unoptimized build is a deliberate `--mode Debug`.
pub const default_mode = "ReleaseFast";
/// `cache` value that disables frontend reuse for one invocation; `--no-cache`
/// selects it without adding another build-option field. It contains a NUL so it
/// can never collide with a directory name a caller could actually pass.
pub const no_cache = "\x00frontend-no-cache";
/// The flag that selects an explicit cache directory; repeated in usage and parse.
const cache_dir_flag = "--cache-dir=";
/// Whether this build disables frontend reuse, independently of where native
/// objects are published. An explicit directory can accompany `--no-cache`.
pub fn noCache(parsed: Options) bool {
    if (std.mem.eql(u8, parsed.cache, no_cache)) return true;
    for (parsed.link_arguments) |argument| {
        if (std.mem.eql(u8, argument, "--")) break;
        if (std.mem.eql(u8, argument, "--no-cache")) return true;
    }
    return false;
}
/// The native driver preserves the Python prototype's build controls.
pub const Options = struct {
    link_arguments: []const []const u8 = &.{},
    source: []const u8 = "",
    output: []const u8 = "",
    project: bool = false,
    library: bool = false,
    provider: ?[]const u8 = null,
    zig: []const u8 = "zig",
    codegen: Codegen = .auto,
    mode: []const u8 = default_mode,
    target: []const u8 = "amd64_sysv",
    cache: []const u8 = default_cache,
    report: bool = false,
    run: bool = false,
    max_memory: ?u64 = null,
    arguments: []const []const u8 = &.{},
};
/// Native code generator selected for this build. `.auto` means the caller named
/// none, and `qbe_build_backend.resolve` builds it with QBE in either optimize
/// mode, because an edit-build loop wants the fast compile. `--release` and
/// `--backend llvm` name `.llvm`; an explicit `.qbe` or `.llvm` is never changed
/// behind the caller's back.
pub const Codegen = union(enum) {
    auto,
    qbe: []const u8,
    llvm: Llvm,
};
/// Explicit controls of the built-in LLVM backend (LLVM-ZIG-1).
pub const Llvm = struct { optimization: ?[]const u8 = null, lto: Lto = .off };
/// Link-time optimization of an LLVM build: none, one merged module (`--lto`,
/// `--lto=full`), or per-module summaries optimized in parallel
/// (`--lto=thin`, LLVM-THINLTO-1).
pub const Lto = enum {
    off,
    full,
    thin,

    /// Whether the link sees bitcode at all.
    pub fn on(self: Lto) bool {
        return self != .off;
    }
    /// The compiler flag that emits this kind of bitcode, or null for none.
    pub fn flag(self: Lto) ?[]const u8 {
        return switch (self) {
            .off => null,
            .full => "-flto",
            .thin => "-flto=thin",
        };
    }
};
/// The bare switch that selects the release build, like `cargo build --release`.
pub const release_flag = "--release";
/// The build `--release` stands for: `--mode ReleaseFast --backend llvm
/// --llvm-opt 3 --lto`.
pub const release_codegen: Codegen = .{ .llvm = .{ .optimization = "3", .lto = .full } };
/// The LTO a bare `--lto`, `--lto=full` or `--lto=thin` switch asks for, or
/// null for any other argument.
pub fn ltoSwitch(argument: []const u8) ?Lto {
    if (std.mem.eql(u8, argument, "--lto") or std.mem.eql(u8, argument, "--lto=full")) return .full;
    if (std.mem.eql(u8, argument, "--lto=thin")) return .thin;
    return null;
}
/// Whether the arguments ask for the release build. Guest arguments after `--`
/// belong to a `--run` guest, so they are never read.
pub fn release(args: []const []const u8) bool {
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) return false;
        if (std.mem.eql(u8, argument, release_flag)) return true;
    }
    return false;
}
/// Whether the arguments also spell a control that `--release` already names,
/// in either order. Accepting one would make the shorthand mean something else
/// depending on where it was written, so the pair is refused instead.
pub fn restatesRelease(args: []const []const u8) bool {
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) return false;
        const name = argument[0 .. std.mem.indexOfScalar(u8, argument, '=') orelse argument.len];
        inline for (.{ "--mode", "--backend", "--qbe", "--llvm-opt", "--lto" }) |named| {
            if (std.mem.eql(u8, name, named)) return true;
        }
    }
    return false;
}
/// Build usage is independent of run-time guest budgets.
pub const usage = "usage: mylang build <file.my> (-o <output> | --run) [--project] [--library]\n" ++
    "  --link FILE --link-library NAME --library-path DIR (repeatable)\n" ++
    "  --provider FILE  trusted native provider (executables only)\n" ++
    "  --backend qbe|llvm  --llvm-opt 0|1|2|3|s|z  --lto[=full|thin]\n" ++
    "  a build that names no backend uses QBE in either mode (the fast compile)\n" ++
    "  --release  the optimized build: --mode ReleaseFast --backend llvm --llvm-opt 3 --lto\n" ++
    "  --qbe PATH --zig PATH --mode Debug|ReleaseFast (default ReleaseFast) --target amd64_sysv\n" ++
    "  " ++ cache_dir_flag ++ "DIR  --no-cache  --report\n" ++
    "  --timings=json  phase-timings-v1 JSON Lines on stderr (frontend/codegen/link/native)\n" ++
    "  --keep-symbols  keep the guest symbol table so `perf report` names functions\n" ++
    "  --max-memory BYTES  byte ceiling for --run (K/M/G suffixes; default 4G)\n" ++
    "  --timeout=SECONDS  wall-clock ceiling for --run (no default; a run past it exits 1 with R_TIMEOUT)\n" ++
    "  --run instead of -o: execute temporarily; pass guest arguments after --\n";
/// Parse explicit build flags, rejecting unknown controls.
pub fn parse(args: []const []const u8) Error!Options {
    var result: Options = .{ .link_arguments = args };
    var no_cache_seen = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const argument = args[index];
        if (std.mem.eql(u8, argument, "--")) {
            // Keep the delimiter so the launcher can tell this command's runtime
            // options from the guest's arguments: the options travel in
            // `MYLANG_OPTIONS`, and the child's argv carries only the values after
            // it, including one that happens to spell `--print-result`.
            result.arguments = args[index..];
            break;
        }
        if (runtimeControl(argument)) continue;
        if (!std.mem.startsWith(u8, argument, "-")) {
            if (result.source.len != 0) return error.InvalidBuildArguments;
            result.source = argument;
            continue;
        }
        // `--no-cache` is a bare switch with no value; it selects the sentinel
        // `cache` value so no additional field is needed.
        if (std.mem.eql(u8, argument, "--no-cache")) {
            if (no_cache_seen) return error.InvalidBuildArguments;
            no_cache_seen = true;
            if (std.mem.eql(u8, result.cache, default_cache)) result.cache = no_cache;
            continue;
        }
        // `--step-accounting` is a build-policy request, not a build control: the
        // host application that always runs its guest under `--max-steps=` asks
        // for the accounting that enforces it. It rides in `link_arguments` so
        // the frozen Options field set does not grow.
        if (std.mem.eql(u8, argument, "--step-accounting")) continue;
        // `--keep-symbols` is a measurement-only link policy, not a build
        // control. Like `--step-accounting` it rides in
        // `link_arguments`, which the driver already scans, so the frozen
        // Options field set does not grow for a profiling switch.
        if (std.mem.eql(u8, argument, "--keep-symbols")) continue;
        // Internal `--module-objects` (MODULE-COMPILE-1) compiles one module's
        // units and links nothing; it rides in `link_arguments` the same way.
        if (std.mem.eql(u8, argument, "--module-objects")) continue;
        // `--timings=json` is an observation request, not a build control. Like
        // `--keep-symbols` it rides in `link_arguments`, which the driver already
        // scans, so the frozen Options field set does not grow for a switch that
        // changes no artifact.
        if (std.mem.eql(u8, argument, "--timings=json")) continue;
        if (std.mem.eql(u8, argument, "--diagnostics=json") or std.mem.eql(u8, argument, "--diagnostics=text")) continue;
        // `--release` is a bare switch that stands for four controls; `validate`
        // refuses it beside any control it already names.
        if (std.mem.eql(u8, argument, release_flag)) {
            result.mode = default_mode;
            result.codegen = release_codegen;
            continue;
        }
        if (ltoSwitch(argument)) |lto| {
            switch (result.codegen) {
                .llvm => |*llvm| llvm.lto = lto,
                .auto, .qbe => return error.InvalidBuildArguments,
            }
            continue;
        }
        const split = std.mem.indexOfScalar(u8, argument, '=') orelse argument.len;
        const name = argument[0..split];
        const option = std.meta.stringToEnum(Flag, name) orelse return error.InvalidBuildArguments;
        if (boolean(&result, option)) {
            if (split != argument.len) return error.InvalidBuildArguments;
            continue;
        }
        const value = if (split < argument.len) argument[split + 1 ..] else value: {
            index += 1;
            if (index == args.len) return error.InvalidBuildArguments;
            break :value args[index];
        };
        if (value.len == 0) return error.InvalidBuildArguments;
        if (@import("native_link.zig").isFlag(@tagName(option)) and !@import("native_link.zig").valid(@tagName(option), value)) return error.InvalidBuildArguments;
        try assign(&result, option, value);
    }
    try validate(result);
    return result;
}
fn validate(result: Options) Error!void {
    if (result.source.len == 0) return error.InvalidBuildArguments;
    if (release(result.link_arguments) and restatesRelease(result.link_arguments)) return error.InvalidBuildArguments;
    if (result.run) {
        if (result.output.len != 0 or result.library) return error.InvalidBuildArguments;
    } else {
        if (result.output.len == 0 or result.arguments.len != 0) return error.InvalidBuildArguments;
    }
    if (result.library and result.provider != null) return error.InvalidBuildArguments;
    if (!std.mem.eql(u8, result.target, "amd64_sysv")) return error.InvalidBuildArguments;
    if (!std.mem.eql(u8, result.mode, "Debug") and !std.mem.eql(u8, result.mode, "ReleaseFast")) return error.InvalidBuildArguments;
    switch (result.codegen) {
        .auto, .qbe => {},
        .llvm => |llvm| {
            if (llvm.optimization) |opt| if (!validLlvmOpt(opt)) return error.InvalidBuildArguments;
        },
    }
}
fn validLlvmOpt(value: []const u8) bool {
    return value.len == 1 and std.mem.indexOfScalar(u8, "0123sz", value[0]) != null;
}
const Flag = enum {
    @"--link",
    @"--link-library",
    @"--library-path",
    @"-o",
    @"--output",
    @"--project",
    @"--library",
    @"--provider",
    @"--qbe",
    @"--zig",
    @"--backend",
    @"--llvm-opt",
    @"--mode",
    @"--target",
    @"--cache-dir",
    @"--select-file",
    @"--manifest-file",
    @"--report",
    @"--run",
    @"--max-memory",
};
fn boolean(result: *Options, flag: Flag) bool {
    switch (flag) {
        .@"--project" => result.project = true,
        .@"--library" => result.library = true,
        .@"--report" => result.report = true,
        .@"--run" => result.run = true,
        else => return false,
    }
    return true;
}
fn assign(result: *Options, flag: Flag, value: []const u8) Error!void {
    switch (flag) {
        .@"--link", .@"--link-library", .@"--library-path" => {},
        .@"-o", .@"--output" => {
            result.output = value;
        },
        .@"--provider" => result.provider = value,
        .@"--qbe" => result.codegen = .{ .qbe = value },
        .@"--zig" => result.zig = value,
        .@"--backend" => {
            if (std.mem.eql(u8, value, "qbe")) result.codegen = .{ .qbe = "qbe" } else if (std.mem.eql(u8, value, "llvm")) result.codegen = .{ .llvm = .{} } else return error.InvalidBuildArguments;
        },
        .@"--llvm-opt" => switch (result.codegen) {
            .llvm => |*llvm| llvm.optimization = value,
            .auto, .qbe => return error.InvalidBuildArguments,
        },
        .@"--mode" => result.mode = value,
        .@"--target" => result.target = value,
        .@"--cache-dir" => {
            // Reuse policy and native artifact location are independent.
            result.cache = value;
        },
        // The selective frontend input travels in `link_arguments`, which the
        // build driver forwards without adding another frozen Options field.
        .@"--select-file" => {},
        // An already-checked frontend manifest also travels in `link_arguments`:
        // the build driver links it directly instead of re-running the frontend.
        .@"--manifest-file" => {},
        .@"--max-memory" => result.max_memory = @import("memory_budget").parse(value) catch return error.InvalidBuildArguments,
        else => unreachable,
    }
}

test "build options accept equals syntax and later tool overrides" {
    const parsed = try parse(&.{ "main.my", "-o", "out", "--qbe=first", "--qbe", "second", "--mode=ReleaseFast", "--project", "--report" });
    try std.testing.expectEqualStrings("second", parsed.codegen.qbe);
    try std.testing.expectEqualStrings("ReleaseFast", parsed.mode);
    try std.testing.expect(parsed.project and parsed.report);
}

test "LLVM backend has explicit optimization and full LTO controls" {
    const parsed = try parse(&.{ "main.my", "-o", "out", "--backend", "llvm", "--llvm-opt", "3", "--lto" });
    try std.testing.expectEqualStrings("3", parsed.codegen.llvm.optimization.?);
    try std.testing.expectEqual(Lto.full, parsed.codegen.llvm.lto);
}
// spec: LLVM-THINLTO-1
test "--lto=thin asks for per-module ThinLTO and --lto=full for the merged module" {
    const thin = try parse(&.{ "main.my", "-o", "out", "--backend", "llvm", "--llvm-opt", "3", "--lto=thin" });
    try std.testing.expectEqual(Lto.thin, thin.codegen.llvm.lto);
    try std.testing.expectEqualStrings("-flto=thin", Lto.thin.flag().?);
    const full = try parse(&.{ "main.my", "-o", "out", "--backend", "llvm", "--lto=full" });
    try std.testing.expectEqual(Lto.full, full.codegen.llvm.lto);
    try std.testing.expectEqualStrings("-flto", Lto.full.flag().?);
    try std.testing.expectEqual(@as(?[]const u8, null), Lto.off.flag());
    try std.testing.expect(!Lto.off.on());
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--backend", "llvm", "--lto=partial" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--lto=thin" }));
    try std.testing.expect(std.mem.indexOf(u8, usage, "--lto[=full|thin]") != null);
}
// spec: BUILD-BACKEND-1
test "a build that names no backend leaves it unnamed in either mode and the usage says QBE" {
    const plain = try parse(&.{ "main.my", "-o", "out" });
    try std.testing.expectEqual(std.meta.activeTag(plain.codegen), .auto);
    try std.testing.expectEqual(std.meta.activeTag((try parse(&.{ "main.my", "--run" })).codegen), .auto);
    try std.testing.expectEqual(std.meta.activeTag((try parse(&.{ "main.my", "-o", "out", "--mode", "Debug" })).codegen), .auto);
    try std.testing.expectEqual(std.meta.activeTag((try parse(&.{ "main.my", "-o", "out", "--mode", "ReleaseFast" })).codegen), .auto);
    // An explicit backend is never changed, whichever spelling selects it.
    try std.testing.expectEqualStrings("qbe", (try parse(&.{ "main.my", "-o", "out", "--backend", "qbe" })).codegen.qbe);
    try std.testing.expectEqualStrings("/opt/qbe", (try parse(&.{ "main.my", "-o", "out", "--qbe", "/opt/qbe" })).codegen.qbe);
    try std.testing.expectEqual(std.meta.activeTag((try parse(&.{ "main.my", "-o", "out", "--backend", "llvm" })).codegen), .llvm);
    try std.testing.expect(std.mem.indexOf(u8, usage, "names no backend uses QBE in either mode") != null);
    // An LLVM-only control still needs the explicit LLVM backend.
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--llvm-opt", "3" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--lto" }));
}
// spec: BUILD-RELEASE-1
test "--release names ReleaseFast LLVM O3 with LTO and refuses a control it already names" {
    const asked = try parse(&.{ "main.my", "-o", "out", "--release" });
    try std.testing.expectEqualStrings("ReleaseFast", asked.mode);
    try std.testing.expectEqualStrings("3", asked.codegen.llvm.optimization.?);
    try std.testing.expectEqual(Lto.full, asked.codegen.llvm.lto);
    try std.testing.expect(release(asked.link_arguments));
    try std.testing.expect(!release((try parse(&.{ "main.my", "-o", "out" })).link_arguments));
    // A guest argument that spells the switch after `--` belongs to the guest.
    try std.testing.expectEqual(std.meta.activeTag((try parse(&.{ "main.my", "--run", "--", "--release" })).codegen), .auto);
    try std.testing.expect(std.mem.indexOf(u8, usage, "--release  the optimized build: --mode ReleaseFast --backend llvm --llvm-opt 3 --lto") != null);
    const restated = [_][]const []const u8{
        &.{ "a.my", "-o", "out", "--release", "--mode", "Debug" },  &.{ "a.my", "-o", "out", "--mode=ReleaseFast", "--release" },
        &.{ "a.my", "-o", "out", "--release", "--backend", "qbe" }, &.{ "a.my", "-o", "out", "--qbe=/opt/qbe", "--release" },
        &.{ "a.my", "-o", "out", "--release", "--llvm-opt", "2" },  &.{ "a.my", "-o", "out", "--release", "--lto" },
        &.{ "a.my", "-o", "out", "--lto", "--release" },            &.{ "a.my", "-o", "out", "--release=yes" },
    };
    for (restated) |args| try std.testing.expectError(error.InvalidBuildArguments, parse(args));
}
// spec: BUILD-MODE-1
test "a build that names no optimize mode uses the fast one and Debug stays explicit" {
    const plain = try parse(&.{ "main.my", "-o", "out" });
    try std.testing.expectEqualStrings(default_mode, plain.mode);
    try std.testing.expectEqualStrings("ReleaseFast", (try parse(&.{ "main.my", "--run" })).mode);
    try std.testing.expectEqualStrings("Debug", (try parse(&.{ "main.my", "-o", "out", "--mode", "Debug" })).mode);
    try std.testing.expect(std.mem.indexOf(u8, usage, "default ReleaseFast") != null);
}
test "build options reject missing values unsupported targets and incompatible provider controls" {
    const invalid = [_][]const []const u8{
        &.{},                                        &.{ "a.my", "b.my", "-o", "out" },         &.{ "a.my", "-o" },
        &.{ "a.my", "--unknown" },                   &.{ "a.my", "-o=" },                       &.{ "a.my", "-o", "out", "--report=true" },
        &.{ "a.my", "-o", "out", "--target=arm64" }, &.{ "a.my", "-o", "out", "--mode=other" }, &.{ "a.my", "-o", "out", "--library", "--provider=x.c" },
    };
    for (invalid) |args| try std.testing.expectError(error.InvalidBuildArguments, parse(args));
}

// spec-case: NETWORK-ENDPOINT-1
test "temporary native runs accept runtime options and reject persistent output" {
    const parsed = try parse(&.{ "main.my", "--run", "--", "--max-steps=12", "--gc-stress" });
    try std.testing.expect(parsed.run);
    try std.testing.expectEqualStrings("--", parsed.arguments[0]);
    try std.testing.expectEqualStrings("--max-steps=12", parsed.arguments[1]);
    try std.testing.expectEqual(@as(usize, 3), parsed.arguments.len);
    try std.testing.expect(runtimeControl("--allow-endpoint=127.0.0.1:8000"));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "-o", "out" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--library" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--", "--gc-stress" }));
}

// spec: CLI-CACHE-ISOLATION-1
test "build options keep no-cache reuse policy independent of the object directory" {
    const parsed = try parse(&.{ "main.my", "-o", "out", "--no-cache" });
    try std.testing.expectEqualStrings(no_cache, parsed.cache);
    const first = try parse(&.{ "main.my", "-o", "out", "--no-cache", "--cache-dir=dir" });
    const second = try parse(&.{ "main.my", "-o", "out", "--cache-dir=dir", "--no-cache" });
    try std.testing.expectEqualStrings("dir", first.cache);
    try std.testing.expectEqualStrings("dir", second.cache);
    try std.testing.expect(noCache(first));
    try std.testing.expect(noCache(second));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--no-cache", "--no-cache" }));
}

test "build options carry an internal already-checked manifest without a new field" {
    const parsed = try parse(&.{ "main.my", "--project", "--library", "-o", "lib.so", "--manifest-file=checked.json" });
    try std.testing.expect(parsed.project and parsed.library);
    try std.testing.expectEqualStrings("--manifest-file=checked.json", parsed.link_arguments[5]);
}

// spec-case: MEMORY-CEILING-1
test "a temporary native run accepts a suffixed byte ceiling and rejects malformed text" {
    try std.testing.expectEqual(@as(?u64, 64 << 20), (try parse(&.{ "main.my", "--run", "--max-memory=64M" })).max_memory);
    try std.testing.expectEqual(@as(?u64, 1 << 30), (try parse(&.{ "main.my", "--run", "--max-memory", "1G" })).max_memory);
    // Unresolved by default, so MYLANG_MEMORY_LIMIT and the built-in default still apply.
    try std.testing.expectEqual(@as(?u64, null), (try parse(&.{ "main.my", "--run" })).max_memory);
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--max-memory=eight" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--max-memory" }));
}

// spec: QBE-SYMBOLS-1
test "a profile build keeps the guest symbol table the default strips" {
    const stripped = try parse(&.{ "main.my", "-o", "out" });
    try std.testing.expect(!keepSymbols(stripped.link_arguments));
    const kept = try parse(&.{ "main.my", "-o", "out", "--keep-symbols" });
    try std.testing.expect(keepSymbols(kept.link_arguments));
    try std.testing.expect(std.mem.indexOf(u8, usage, "--keep-symbols") != null);
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--keep-symbols=yes" }));
}

// spec: BUILD-TIMINGS-1
test "a build accepts the phase-timings request without a new build option field" {
    const asked = try parse(&.{ "main.my", "-o", "out", "--timings=json" });
    try std.testing.expect(timingsJson(asked.link_arguments));
    try std.testing.expectEqualStrings("main.my", asked.source);
    try std.testing.expectEqualStrings("out", asked.output);
    try std.testing.expect(!timingsJson((try parse(&.{ "main.my", "-o", "out" })).link_arguments));
    try std.testing.expect(std.mem.indexOf(u8, usage, "--timings=json") != null);
    // A guest argument that spells the switch after `--` belongs to the guest.
    const run = try parse(&.{ "main.my", "--run", "--", "--timings=json" });
    try std.testing.expect(!timingsJson(run.link_arguments));
    // Only the documented spelling is accepted; a bare `--timings` is not a
    // build control, and a value is never attached to it.
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--timings" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--timings=json=1" }));
}

test "native link controls are repeatable and reject injected compiler switches" {
    _ = try parse(&.{ "main.my", "--run", "--link=a.c", "--link", "b.o", "--library-path", "lib", "--link-library=m" });
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--link-library=-shared" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--link=-Wl,bad" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--library-path" }));
}

// spec-case: RELEASE-CHECKED-1
test "every build refuses --unchecked as removed and a guest may still receive it" {
    try std.testing.expect(uncheckedRequested(&.{ "main.my", "-o", "out", "--unchecked" }));
    try std.testing.expect(uncheckedRequested(&.{ "main.my", "--run", "--release", "--unchecked" }));
    try std.testing.expect(uncheckedRequested(&.{ "main.my", "-o", "out", "--unchecked=yes" }));
    try std.testing.expect(!uncheckedRequested(&.{ "main.my", "-o", "out", "--release" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "-o", "out", "--unchecked" }));
    try std.testing.expectError(error.InvalidBuildArguments, parse(&.{ "main.my", "--run", "--release", "--unchecked" }));
    try std.testing.expect(std.mem.indexOf(u8, usage, "--unchecked") == null);
    try std.testing.expect(std.mem.startsWith(u8, unchecked_removed, "--unchecked was removed: every build keeps overflow, cast and bounds checks"));
    // A guest argument that spells the switch after `--` belongs to the guest.
    try std.testing.expect(!uncheckedRequested(&.{ "main.my", "--run", "--", "--unchecked" }));
    const guest = try parse(&.{ "main.my", "--run", "--", "--unchecked" });
    try std.testing.expectEqualStrings("--unchecked", guest.arguments[1]);
}
// spec-case: BUILD-RELEASE-1
test "a link input written after a bare switch is still linked" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try @import("qbe_build_io.zig").Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const native_link = @import("native_link.zig");
    var forwarded: std.ArrayList([]const u8) = .empty;
    try native_link.append(context, &.{ "main.my", "--release", "--link-library", "m", "--lto", "--link-library=z", "--no-cache", "--library-path", "/lib" }, &forwarded, false);
    try std.testing.expectEqual(@as(usize, 3), forwarded.items.len);
    try std.testing.expectEqualStrings("-lm", forwarded.items[0]);
    try std.testing.expectEqualStrings("-lz", forwarded.items[1]);
    try std.testing.expectEqualStrings("-L/lib", forwarded.items[2]);
    try std.testing.expect(native_link.hasInputs(&.{ "main.my", "--release", "--link", "a.c" }));
}
