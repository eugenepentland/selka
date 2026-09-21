//! Content-addressed native objects and direct assembler/compiler invocations.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
/// Cache and native tool failures.
pub const Error = fs.Error || error{EmptyNativeObject};
/// Wave-3 contract mirrored for the native-build module.
///
/// The canonical `cache_key.Contract` lives in the `mylang` module. A Zig file
/// may not belong to two modules, and the native-build module deliberately does
/// not import `mylang`, so this shadow keeps the object cache's key dimensions
/// without crossing that boundary. `fingerprintHex` is byte-for-byte the
/// same domain-separated encoding as `cache_key.Contract`; the invalidation
/// matrix cross-checks the two defaults so they cannot drift silently.
pub const Contract = struct {
    bootstrap_language: []const u8,
    target: []const u8,
    runtime_abi: []const u8,
    effects: []const u8,
    flags: []const u8,
    compiler_identity: []const u8,

    /// Conservative default matching `cache_key.Contract.default`.
    pub const default: Contract = .{
        .bootstrap_language = "bootstrap-v1",
        .target = "native",
        .runtime_abi = "runtime-abi-v3",
        .effects = "effects-v4",
        .flags = "",
        .compiler_identity = "",
    };

    /// Allocate the lowercase hex SHA-256 of the canonical contract encoding.
    pub fn fingerprint(self: Contract, allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        var hex: [64]u8 = undefined;
        self.fingerprintHex(&hex);
        return allocator.dupe(u8, &hex) catch error.OutOfMemory;
    }

    /// Allocation-free hex fingerprint; identical encoding to the canonical cache key.
    // twin-drift-ok: the native-build module cannot import the `mylang` module's
    // cache_key.zig (a file may belong to only one Zig module), so this shadow
    // deliberately duplicates the encoding; the invalidation matrix cross-checks
    // both defaults so they cannot silently diverge.
    pub fn fingerprintHex(self: Contract, out: *[64]u8) void {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("mylang-cache-contract-v1");
        frame(&hash, self.bootstrap_language);
        frame(&hash, self.target);
        frame(&hash, self.runtime_abi);
        frame(&hash, self.effects);
        frame(&hash, self.flags);
        frame(&hash, self.compiler_identity);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        const hex = std.fmt.bytesToHex(digest, .lower);
        @memcpy(out, &hex);
    }
};

fn frame(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// Native compilation tools and invocation-local runtime source directory.
pub const Cache = struct {
    context: fs.Context,
    directory: []const u8,
    temporary: []const u8,
    assets: []const u8,
    environment: []const u8,
    zig: []const u8,
    mode: []const u8,
    codegen: Codegen,
    /// Full Wave-3 contract; its fingerprint is part of every object key so a
    /// bootstrap-language, target, runtime-ABI, effects, flags or compiler change
    /// can never reuse an incompatible native object.
    contract: Contract = .default,
    /// Cache hits are accepted only when their independent checksum matches.
    pub fn object(self: Cache, kind: []const u8, input: []const u8, flavor: Flavor) Error!Object {
        return switch (try self.stage(kind, input, flavor, null)) {
            .hit => |hit| hit,
            .miss => |job| try self.finish(job),
        };
    }
    /// Stage one object: report a cache hit, or prepare the tool invocation that
    /// produces it without running the tool. A caller that stages many objects
    /// can then start their tools together and finish each one.
    pub fn stage(self: Cache, kind: []const u8, input: []const u8, flavor: Flavor, environment: ?*const std.process.Environ.Map) Error!Staged {
        const key = try self.identity(kind, input);
        const path = try self.entry(key, ".o");
        if (self.valid(path, try self.entry(key, ".digest"))) return .{ .hit = .{ .key = key, .path = path, .reused = true } };
        const work = try self.context.temporary(self.temporary);
        const candidate = try std.fs.path.join(self.context.allocator, &.{ work, "object.o" });
        const scratch: Scratch = .{ .key = key, .path = path, .candidate = candidate, .work = work };
        return .{ .miss = try self.prepare(scratch, input, flavor, environment) };
    }
    /// Run a staged job's primary tool and its optional assembler, then publish
    /// its object. This is the sequential path a single `object` takes.
    pub fn finish(self: Cache, job: Job) Error!Object {
        try self.context.command(job.argv, job.environment);
        return self.complete(job);
    }
    /// Publish a staged job whose primary tool a concurrent wave already started,
    /// running only its optional assembler and reclaiming its scratch.
    pub fn publish(self: Cache, job: Job) Error!Object {
        return self.complete(job);
    }
    /// Run the assembler a flavor defers to, then store the object and reclaim
    /// the job's private scratch whether or not the tool succeeded.
    fn complete(self: Cache, job: Job) Error!Object {
        defer self.context.remove(job.work);
        if (job.assemble) |argv| try self.context.command(argv, null);
        return self.store(job.key, job.path, job.candidate);
    }
    /// Reclaim a staged job that a failed wave will not finish.
    pub fn discard(self: Cache, job: Job) void {
        self.context.remove(job.work);
    }
    /// Build the tool invocation for one staged object. The QBE flavor names a
    /// per-unit `.ssa` and, unless full LTO emits the object directly, a second
    /// assembler call; the C and Zig flavors write their source and run one tool.
    fn prepare(self: Cache, scratch: Scratch, input: []const u8, flavor: Flavor, environment: ?*const std.process.Environ.Map) Error!Job {
        const a = self.context.allocator;
        const key = scratch.key;
        const path = scratch.path;
        const work = scratch.work;
        const candidate = scratch.candidate;
        switch (flavor) {
            .qbe => {
                const source = try std.fs.path.join(a, &.{ work, "unit.ssa" });
                const assembly = try std.fs.path.join(a, &.{ work, "unit.s" });
                try self.context.write(source, input);
                const env = environment orelse try self.adapterEnvironment();
                const adapter_output = if (self.codegen.lto and self.codegen.llvm) candidate else assembly;
                const argv = try a.dupe([]const u8, &.{ self.codegen.tool, "-t", "amd64_sysv", "-o", adapter_output, source });
                const assemble: ?[]const []const u8 = if (!self.codegen.lto or !self.codegen.llvm)
                    try a.dupe([]const u8, &.{ self.zig, "cc", "-g0", "-c", assembly, "-o", candidate })
                else
                    null;
                return .{ .key = key, .path = path, .candidate = candidate, .work = work, .argv = argv, .environment = env, .assemble = assemble };
            },
            .c_text => {
                const source = try std.fs.path.join(a, &.{ work, "unit.c" });
                try self.context.write(source, input);
                var argv: std.ArrayList([]const u8) = .empty;
                try argv.appendSlice(a, try self.flags());
                try argv.appendSlice(a, &.{ "-c", source, "-o", candidate });
                return .{ .key = key, .path = path, .candidate = candidate, .work = work, .argv = argv.items, .environment = null, .assemble = null };
            },
            .zig_file => {
                const source = try std.fs.path.join(a, &.{ self.assets, input });
                const emit = try std.fmt.allocPrint(a, "-femit-bin={s}", .{candidate});
                const argv = try a.dupe([]const u8, &.{ self.zig, "build-obj", source, "-lc", "-fPIC", "-fstrip", "-O", self.mode, emit });
                return .{ .key = key, .path = path, .candidate = candidate, .work = work, .argv = argv, .environment = null, .assemble = null };
            },
        }
    }
    /// The environment every LLVM adapter invocation of one build shares: the
    /// optimization level, Zig driver, runtime sources, signature sidecar and the
    /// exact target CPU policy the final link will use.
    pub fn adapterEnvironment(self: Cache) Error!*const std.process.Environ.Map {
        const a = self.context.allocator;
        const environment = try a.create(std.process.Environ.Map);
        environment.* = try self.context.environ.clone(a);
        if (!self.codegen.llvm) return environment;
        try environment.put("MYLANG_QBE_LLVM_OPT", try std.fmt.allocPrint(a, "-O{s}", .{self.codegen.optimization}));
        try environment.put("MYLANG_QBE_LLVM_ZIG", self.zig);
        try environment.put("MYLANG_QBE_LLVM_RUNTIME_SOURCES", self.assets);
        try environment.put("MYLANG_QBE_LLVM_SIGNATURES", try self.signatureSidecar());
        try environment.put("MYLANG_QBE_LLVM_TARGET_CPU", self.codegen.target_cpu);
        try environment.put("MYLANG_QBE_LLVM_TARGET_FEATURES", self.codegen.target_features);
        if (self.codegen.lto) try environment.put("MYLANG_QBE_LLVM_EMIT_LTO_OBJECT", "1");
        return environment;
    }
    /// The per-build JSON sidecar the adapter reads and writes for call-site
    /// signatures; it lives in this build's private temporary directory.
    pub fn signatureSidecar(self: Cache) Error![]const u8 {
        return std.fs.path.join(self.context.allocator, &.{ self.temporary, "llvm-signatures.json" });
    }
    /// Publish every unit's signature into the adapter's sidecar before any unit
    /// is translated. A concurrent build cannot rely on unit order, so this makes
    /// the table complete first and every call site declares its callee exactly
    /// as a sequential build would have. It is a no-op outside the LLVM arm.
    pub fn declareSignatures(self: Cache, units: []const []const u8, environment: *const std.process.Environ.Map) Error!void {
        if (!self.codegen.llvm) return;
        const a = self.context.allocator;
        const work = try self.context.temporary(self.temporary);
        defer self.context.remove(work);
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ self.codegen.tool, "-t", "amd64_sysv", "--signatures-only", "-o", try self.signatureSidecar() });
        for (units, 0..) |input, index| {
            const path = try std.fs.path.join(a, &.{ work, try std.fmt.allocPrint(a, "{d}.ssa", .{index}) });
            try self.context.write(path, input);
            try argv.append(a, path);
        }
        try self.context.command(argv.items, environment);
    }
    /// Publish the fixed runtime translation units as one archive whose single
    /// member merges every unit. `zig build-obj` compiles all C sources in one
    /// process — a cold build pays one toolchain start, not one per unit — and a
    /// relocatable link preserves each unit's function and data sections, so the
    /// final `--gc-sections` link still drops runtime a program never reaches. The
    /// linker verifies one archive entry instead of every runtime object.
    pub fn library(self: Cache, kind: []const u8, sources: []const []const u8) Error!Object {
        const a = self.context.allocator;
        const key = try self.identity(kind, try std.mem.join(a, "\x00", sources));
        const path = try self.entry(key, ".a");
        if (self.valid(path, try self.entry(key, ".digest"))) return .{ .key = key, .path = path, .reused = true };
        const work = try self.context.temporary(self.temporary);
        defer self.context.remove(work);
        const candidate = try std.fs.path.join(a, &.{ work, "runtime.a" });
        if (self.codegen.lto) {
            var archive: std.ArrayList([]const u8) = .empty;
            try archive.appendSlice(a, &.{ self.zig, "ar", "rcs", candidate });
            for (sources) |name| {
                const source = try std.fs.path.join(a, &.{ self.assets, name });
                const member = try std.fs.path.join(a, &.{ work, try std.fmt.allocPrint(a, "{s}.o", .{name}) });
                try self.compileC(source, member, null);
                try archive.append(a, member);
            }
            try self.context.command(archive.items, null);
        } else {
            const merged = try std.fs.path.join(a, &.{ work, "runtime.o" });
            try self.mergeC(sources, merged);
            try self.context.command(&.{ self.zig, "ar", "rcs", candidate, merged }, null);
        }
        return self.store(key, path, candidate);
    }
    /// Compile every runtime C source into one relocatable object with a single
    /// `zig build-obj`, then leave the merge command to run it.
    fn mergeC(self: Cache, sources: []const []const u8, output: []const u8) Error!void {
        try self.context.command(try self.mergeCommand(sources, output), null);
    }
    /// The single-invocation `zig build-obj` command that merges the runtime units.
    /// Per-unit optimization, debug suppression, section splitting and path mapping
    /// match the loose `zig cc` path so the merged member links identically, and one
    /// process start replaces one per unit on a cold build.
    fn mergeCommand(self: Cache, sources: []const []const u8, output: []const u8) Error![]const []const u8 {
        const a = self.context.allocator;
        const zig_mode = if (std.mem.eql(u8, self.mode, "Debug")) "-ODebug" else "-OReleaseFast";
        // A Debug build stays unoptimized on every backend: `zig cc` derives its mode
        // from this flag, and a Debug link is what pulls in the UBSan runtime the
        // Debug-compiled C objects reference. The LLVM level applies to release builds.
        const optimization = if (std.mem.eql(u8, self.mode, "Debug")) "-O0" else if (self.codegen.llvm) try std.fmt.allocPrint(a, "-O{s}", .{self.codegen.optimization}) else "-O2";
        const shared = try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-runtime", .{self.assets});
        const shared_debug = try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-runtime", .{self.assets});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{
            self.zig,                                 "build-obj",       "-fPIC",     "-lc",
            zig_mode,                                 "-I",              self.assets, "-cflags",
            "-std=c11",                               optimization,      "-g0",       "-fno-ident",
            "-ffunction-sections",                    "-fdata-sections", shared,      shared_debug,
            "-fdebug-compilation-dir=mylang-runtime", "--",
        });
        if (self.codegen.lto) try argv.append(a, "-flto");
        for (sources) |source| try argv.append(a, try std.fs.path.join(a, &.{ self.assets, source }));
        try argv.append(a, try std.fmt.allocPrint(a, "-femit-bin={s}", .{output}));
        return argv.items;
    }
    fn identity(self: Cache, kind: []const u8, input: []const u8) Error![]const u8 {
        const contract = try self.contract.fingerprint(self.context.allocator);
        const encoded = try std.json.Stringify.valueAlloc(self.context.allocator, .{ self.environment, contract, kind, input }, .{});
        return fs.hash(self.context.allocator, encoded);
    }
    fn entry(self: Cache, key: []const u8, extension: []const u8) Error![]const u8 {
        return std.fmt.allocPrint(self.context.allocator, "{s}/{s}{s}", .{ self.directory, key, extension });
    }
    /// Publish a freshly built artifact and its fingerprint. A generation directory
    /// a concurrent sweep removed while this object was compiling is recreated and
    /// leased again by `republish`, so publication heals instead of failing.
    fn store(self: Cache, key: []const u8, path: []const u8, candidate: []const u8) Error!Object {
        const bytes = try self.context.read(candidate);
        const digest = try objectDigest(self.context.allocator, bytes);
        try self.context.republish(candidate, path);
        try self.context.atomic(try self.entry(key, ".digest"), digest);
        return .{ .key = key, .path = path, .reused = false };
    }
    fn valid(self: Cache, path: []const u8, checksum: []const u8) bool {
        const expected = self.context.read(checksum) catch return false;
        const bytes = self.context.read(path) catch return false;
        if (bytes.len == 0) return false;
        const actual = fs.digest(self.context.allocator, bytes) catch return false;
        return std.mem.eql(u8, expected, actual);
    }
    /// Fresh provider compilations use private Zig caches to observe external inputs.
    pub fn compileC(self: Cache, source: []const u8, output: []const u8, environment: ?*const std.process.Environ.Map) Error!void {
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(self.context.allocator, try self.flags());
        try args.appendSlice(self.context.allocator, &.{ "-c", source, "-o", output });
        try self.context.command(args.items, environment);
    }
    /// Common native flags keep generated output independent of private directory
    /// names and free of debug information: `-g0` leaves only code and data in every
    /// object, so the cache holds what a program runs and nothing it never reads.
    pub fn flags(self: Cache) Error![]const []const u8 {
        const a = self.context.allocator;
        // A Debug build stays unoptimized on every backend: `zig cc` derives its mode
        // from this flag, and a Debug link is what pulls in the UBSan runtime the
        // Debug-compiled C objects reference. The LLVM level applies to release builds.
        const optimization = if (std.mem.eql(u8, self.mode, "Debug")) "-O0" else if (self.codegen.llvm) try std.fmt.allocPrint(a, "-O{s}", .{self.codegen.optimization}) else "-O2";
        const files = try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-qbe", .{self.temporary});
        const debug = try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-qbe", .{self.temporary});
        const shared = try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-runtime", .{self.assets});
        const shared_debug = try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-runtime", .{self.assets});
        var result: std.ArrayList([]const u8) = .empty;
        try result.appendSlice(a, &.{
            self.zig,                             "cc",    "-std=c11",            optimization,      "-g0",
            "-fno-ident",                         "-fPIC", "-ffunction-sections", "-fdata-sections", files,
            "-fdebug-compilation-dir=mylang-qbe", debug,   shared,                shared_debug,      "-I",
            self.assets,
        });
        if (self.codegen.lto) try result.append(a, "-flto");
        return result.toOwnedSlice(a);
    }
};
/// Resolved native code generator and optimization policy.
pub const Codegen = struct {
    tool: []const u8,
    llvm: bool = false,
    optimization: []const u8 = "default",
    lto: bool = false,
    target_cpu: []const u8 = "",
    target_features: []const u8 = "",
};
/// Ways to lower an object without routing a guest function through C.
pub const Flavor = enum { qbe, c_text, zig_file };
/// One validated object-cache result.
pub const Object = struct { key: []const u8, path: []const u8, reused: bool };
/// The content-addressed destination and private scratch of one staged object.
const Scratch = struct { key: []const u8, path: []const u8, candidate: []const u8, work: []const u8 };
/// One content-addressed object whose input is staged but whose tool has not run
/// yet, so a caller can start several tools at once and finish each afterwards.
pub const Job = struct {
    key: []const u8,
    path: []const u8,
    candidate: []const u8,
    work: []const u8,
    argv: []const []const u8,
    environment: ?*const std.process.Environ.Map,
    /// A second tool call (the assembler) for a flavor whose first tool emits
    /// assembly rather than the final object.
    assemble: ?[]const []const u8 = null,
};
/// The result of staging one object: it was already cached, or it needs a tool.
pub const Staged = union(enum) { hit: Object, miss: Job };

fn objectDigest(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    if (bytes.len == 0) return error.EmptyNativeObject;
    return fs.digest(allocator, bytes);
}
test "empty native tool output cannot enter the object cache" {
    try std.testing.expectError(error.EmptyNativeObject, objectDigest(std.testing.allocator, ""));
}
// spec: QBE-RUNTIME-MERGE-1
test "the runtime units merge in one build-obj invocation naming every source" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "ReleaseFast", .codegen = .{ .tool = "/qbe" } };
    const argv = try cache.mergeCommand(&.{ "qbe_runtime.c", "native_heap.c" }, "/tmp/out.o");
    const joined = try std.mem.join(context.allocator, " ", argv);
    try std.testing.expectEqualStrings("build-obj", argv[1]);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, joined, "build-obj"));
    try std.testing.expect(std.mem.indexOf(u8, joined, "/assets/qbe_runtime.c") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "/assets/native_heap.c") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-O2") != null);
    try std.testing.expectEqualStrings("-femit-bin=/tmp/out.o", argv[argv.len - 1]);
}

// spec-case: QBE-STRIP-1
test "native compile commands emit no debug information" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "Debug", .codegen = .{ .tool = "/qbe" } };
    const loose = try std.mem.join(context.allocator, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, loose, " -g0 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, loose, " -O0 ") != null);
    const merged = try std.mem.join(context.allocator, " ", try cache.mergeCommand(&.{"qbe_runtime.c"}, "/tmp/out.o"));
    try std.testing.expect(std.mem.indexOf(u8, merged, " -g0 ") != null);
    try std.testing.expect(std.mem.indexOf(u8, merged, " -ODebug ") != null);
}

// spec-case: INCREMENTAL-KEYS-1
test "qbe object cache identity folds the wave 3 contract dimensions" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "ReleaseFast", .codegen = .{ .tool = "/qbe" } };
    const base = try cache.identity("qbe", "unit");
    defer context.allocator.free(base);
    const repeat = try cache.identity("qbe", "unit");
    defer context.allocator.free(repeat);
    try std.testing.expectEqualStrings(base, repeat);
    var changed = cache;
    changed.contract.runtime_abi = "runtime-abi-v4";
    const other = try changed.identity("qbe", "unit");
    defer context.allocator.free(other);
    try std.testing.expect(!std.mem.eql(u8, base, other));
}

test "LLVM full LTO carries O3 and flto through generated C and final link flags" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{
        .context = context,
        .directory = "objects",
        .temporary = "work",
        .assets = "/assets",
        .environment = "env",
        .zig = "/zig",
        .mode = "ReleaseFast",
        .codegen = .{ .tool = "/adapter.py", .llvm = true, .optimization = "3", .lto = true },
    };
    const joined = try std.mem.join(context.allocator, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, joined, "-O3") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-flto") != null);
}

test "native object cache mirror uses the effects-v4 contract" {
    const testing = std.testing;
    try testing.expectEqualStrings("effects-v4", Contract.default.effects);
}
