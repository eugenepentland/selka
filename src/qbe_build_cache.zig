//! Content-addressed native objects and direct assembler/compiler invocations.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const ownership_contract = @import("runtime_contract");
const frame_map = @import("qbe_frame_map.zig");
const options = @import("qbe_build_options.zig");
/// Cache and native tool failures.
pub const Error = fs.Error || error{ EmptyNativeObject, InvalidRuntimeContract };
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
fn blakeFrame(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}
/// The identity of one published file — inode, size and modification time,
/// each as 16 hex digits — or null when it cannot be read or is empty. A file
/// written, truncated or replaced since the stamp was taken has another one.
fn fileStamp(context: fs.Context, path: []const u8) ?[48]u8 {
    const stat = std.Io.Dir.cwd().statFile(context.io, path, .{}) catch return null;
    if (stat.kind != .file or stat.size == 0) return null;
    const modified: u64 = @bitCast(@as(i64, @truncate(stat.mtime.nanoseconds)));
    var out: [48]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{x:0>16}{x:0>16}{x:0>16}", .{ @as(u64, @truncate(stat.inode)), stat.size, modified }) catch return null;
    return out;
}
/// The version every object key starts with. `v3` moved the key from SHA-256
/// to BLAKE3 and frames the contract fields instead of their fingerprint, so
/// no key an older driver published can ever be looked up by this one. `v4`
/// compiles a generated C unit with its job directory mapped away
/// (BUILD-REPRODUCIBLE-1), so no object that still names one is reused.
const object_key_version = "mylang-object-key-v4";

/// QBE-FRAMEMAP-1: a runtime or generated C function that can sit between a
/// guest frame and the runtime's `fail` keeps a frame pointer wherever it
/// calls, so a trap in a frame-map program can walk from `fail` to the guest
/// frame that called into the runtime. A leaf calls nothing, so it never sits
/// in between.
const frame_pointer_flags = [_][]const u8{ "-fno-omit-frame-pointer", "-momit-leaf-frame-pointer" };
/// Whether the runtime unit `name` can reach `fail` and so needs frame
/// pointers. Every `qbe_*` unit reports traps; of the `native_*` data-structure
/// layer the text methods (a located `R_TEXT_SCALAR`) and value copies
/// (allocation failure) do. The rest —
/// the heap, the collector, lists, dictionaries, text, bytes, arenas — return
/// a status the generated code turns into a trap itself, and they keep every
/// register: the collector and allocator are where an allocation-heavy program
/// spends its time. `qbe_build.zig`'s bundled-source test keeps this list
/// honest.
pub fn keepsFramePointers(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "qbe_") or std.mem.eql(u8, name, "native_text_methods.c") or std.mem.eql(u8, name, "native_value_copy.c");
}
/// Annotate assembly for the frame map, reporting a call positioned in another
/// unit's function — a guest body inlined into another guest body, whose
/// caller frame a trace would then miss — as a failed native tool. `known`
/// names the units whose probe descriptors another module holds (ThinLTO).
pub fn annotateText(context: fs.Context, text: []const u8, known: ?*const frame_map.Names) Error![]u8 {
    return frame_map.annotateKnowing(context.allocator, text, known) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FrameMapMismatch => {
            if (context.environ.get("MYLANG_FRAME_MAP_KEEP")) |keep| try context.write(keep, text);
            try std.Io.File.stderr().writeStreamingAll(context.io, "mylang: a call site's frame-map position names another guest function than the one it was compiled into\n");
            return error.NativeToolFailed;
        },
    };
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
        if (try self.cached(key)) |hit| return .{ .hit = hit };
        return .{ .miss = try self.stageAt(key, input, flavor, environment) };
    }
    /// Prepare the tool invocation that builds `input` into the object `key`
    /// names, without running it.
    pub fn stageAt(self: Cache, key: []const u8, input: []const u8, flavor: Flavor, environment: ?*const std.process.Environ.Map) Error!Job {
        const path = try self.entry(key, ".o");
        const work = try self.context.temporary(self.temporary);
        const candidate = try std.fs.path.join(self.context.allocator, &.{ work, "object.o" });
        const scratch: Scratch = .{ .key = key, .path = path, .candidate = candidate, .work = work };
        return self.prepare(scratch, input, flavor, environment);
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
        if (job.assemble) |argv| {
            try self.annotateAssembly(try std.fs.path.join(self.context.allocator, &.{ job.work, "unit.s" }));
            try self.context.command(argv, null);
        }
        return self.store(job.key, job.path, job.candidate);
    }
    /// Give a unit's assembly its frame-map table before it is assembled
    /// (QBE-FRAMEMAP-1). Assembly with no call-site positions is left untouched.
    pub fn annotateAssembly(self: Cache, path: []const u8) Error!void {
        const text = try self.context.read(path);
        const annotated = try annotateText(self.context, text, null);
        if (!std.mem.eql(u8, text, annotated)) try self.context.write(path, annotated);
    }
    /// Reclaim a staged job that a failed wave will not finish.
    pub fn discard(self: Cache, job: Job) void {
        self.context.remove(job.work);
    }
    /// Build the tool invocation for one staged object. The QBE flavor names a
    /// per-unit `.ssa` and a second assembler call; the C and Zig flavors write
    /// their source and run one tool. (The LLVM arm translates in process and
    /// never stages a tool here: `qbe_build_llvm_compile.zig`.)
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
                const argv = try a.dupe([]const u8, &.{ self.codegen.tool, "-t", "amd64_sysv", "-o", assembly, source });
                const assemble = try a.dupe([]const u8, &.{ self.zig, "cc", "-g0", "-c", assembly, "-o", candidate });
                return .{ .key = key, .path = path, .candidate = candidate, .work = work, .argv = argv, .environment = environment, .assemble = assemble };
            },
            .c_text => {
                const source = try std.fs.path.join(a, &.{ work, "unit.c" });
                try self.context.write(source, input);
                var argv: std.ArrayList([]const u8) = .empty;
                try argv.appendSlice(a, try self.generatedFlags());
                // BUILD-REPRODUCIBLE-1: the unit's own path (which a Debug
                // assertion spells) is its job's private directory, mapped away,
                // and a Debug unit's sanitizer source locations keep only file
                // names (the prefix maps do not reach them), so the object is
                // the same whichever job and cache directory compiled it.
                try argv.appendSlice(a, &.{
                    try std.fmt.allocPrint(a, "-ffile-prefix-map={s}=mylang-unit", .{work}),
                    try std.fmt.allocPrint(a, "-fdebug-prefix-map={s}=mylang-unit", .{work}),
                    "-fsanitize-undefined-strip-path-components=-1",
                });
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
        if (self.codegen.lto.on()) {
            var archive: std.ArrayList([]const u8) = .empty;
            try archive.appendSlice(a, &.{ self.zig, "ar", "rcs", candidate });
            for (sources) |name| {
                const source = try std.fs.path.join(a, &.{ self.assets, name });
                const member = try std.fs.path.join(a, &.{ work, try std.fmt.allocPrint(a, "{s}.o", .{name}) });
                var args: std.ArrayList([]const u8) = .empty;
                try args.appendSlice(a, try self.cFlags(keepsFramePointers(name)));
                try args.appendSlice(a, &.{ "-c", source, "-o", member });
                try self.context.command(args.items, null);
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
        try argv.appendSlice(a, &.{ self.zig, "build-obj", "-fPIC", "-lc", zig_mode, "-I", self.assets });
        const common = [_][]const u8{
            "-std=c11",        optimization, "-g0",        "-fno-ident",                             "-ffunction-sections",
            "-fdata-sections", shared,       shared_debug, "-fdebug-compilation-dir=mylang-runtime",
        };
        // `-cflags ... --` applies to the sources after it, so the units that can
        // reach `fail` form one group with frame pointers and the rest another.
        for ([_]bool{ true, false }) |pointers| {
            var any = false;
            for (sources) |source| any = any or keepsFramePointers(source) == pointers;
            if (!any) continue;
            try argv.append(a, "-cflags");
            try argv.appendSlice(a, &common);
            try argv.appendSlice(a, (try ownership_contract.parse(self.context.environ.get(ownership_contract.variable))).cFlags());
            if (pointers) try argv.appendSlice(a, &frame_pointer_flags);
            try argv.append(a, "--");
            for (sources) |source| if (keepsFramePointers(source) == pointers) try argv.append(a, try std.fs.path.join(a, &.{ self.assets, source }));
        }
        if (self.codegen.lto.flag()) |flag| try argv.append(a, flag);
        try argv.append(a, try std.fmt.allocPrint(a, "-femit-bin={s}", .{output}));
        return argv.items;
    }
    /// The key a guest unit's own IL has under this build's environment and
    /// cache contract: the identity a per-function object was published under.
    pub fn unitKey(self: Cache, il: []const u8) Error![]const u8 {
        return self.identity("function", il);
    }
    /// The key of a guest unit named by the hex digest of its IL rather than the
    /// IL itself (`QBE-FRAGMENT-REUSE-1`): a lean manifest carries only that
    /// digest, so its objects are found without reading any unit text, and an
    /// inline unit with the same text reaches the same key.
    pub fn digestKey(self: Cache, digest: []const u8) Error![]const u8 {
        return self.identity("function-digest", digest);
    }
    /// A key derived from other keys of this cache, under its own `kind`.
    pub fn derived(self: Cache, kind: []const u8, input: []const u8) Error![]const u8 {
        return self.identity(kind, input);
    }
    /// The object published under `key`, when it is on disk and its fingerprint matches.
    pub fn cached(self: Cache, key: []const u8) Error!?Object {
        const path = try self.entry(key, ".o");
        if (!self.valid(path, try self.entry(key, ".digest"))) return null;
        return .{ .key = key, .path = path, .reused = true };
    }
    /// Publish an object a caller built itself under `key`, with its fingerprint.
    pub fn keep(self: Cache, key: []const u8, candidate: []const u8) Error!Object {
        return self.store(key, try self.entry(key, ".o"), candidate);
    }
    /// BLAKE3 over the build environment, every cache contract field, the kind
    /// and the input, each length-framed so no two different tuples share a
    /// byte stream. The input is hashed where it lies: JSON-encoding every
    /// unit's IL first cost a warm 50,000-line build a quarter of its driver
    /// time. A warm build keys every guest unit and batch, so the key is BLAKE3
    /// (BUILD-KEYS-1): the pinned toolchain's SHA-256 runs at about 14 MB/s on
    /// this project's build hosts, and it used to run twice per key (once more
    /// for the contract fingerprint, whose fields are now framed directly).
    fn identity(self: Cache, kind: []const u8, input: []const u8) Error![]const u8 {
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update(object_key_version);
        blakeFrame(&hash, self.environment);
        inline for (@typeInfo(Contract).@"struct".field_names) |name| blakeFrame(&hash, @field(self.contract, name));
        blakeFrame(&hash, kind);
        blakeFrame(&hash, input);
        var digest: [32]u8 = undefined;
        hash.final(&digest);
        return self.context.allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
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
        // BUILD-VERIFY-1: the fingerprint also records the published file's
        // identity, so a later build accepts the untouched file by `stat`.
        const sealed = if (fileStamp(self.context, path)) |stamp| try std.fmt.allocPrint(self.context.allocator, "{s}\n{s}", .{ digest, &stamp }) else digest;
        try self.context.atomic(try self.entry(key, ".digest"), sealed);
        return .{ .key = key, .path = path, .reused = false };
    }
    /// BUILD-VERIFY-1: a stored object is accepted when its fingerprint file
    /// records exactly the inode, size and modification time the file has now —
    /// nothing wrote, truncated or replaced it since its bytes were fingerprinted
    /// — and otherwise only when its bytes match the recorded length and hash. A
    /// warm build consults every batch object of the program, and reading and
    /// hashing all of them cost a 200,000-line build about a tenth of a second.
    fn valid(self: Cache, path: []const u8, checksum: []const u8) bool {
        const recorded = self.context.read(checksum) catch return false;
        const split = std.mem.indexOfScalar(u8, recorded, '\n');
        const expected = recorded[0 .. split orelse recorded.len];
        if (split) |at| if (fileStamp(self.context, path)) |stamp| {
            if (std.mem.eql(u8, recorded[at + 1 ..], &stamp)) return true;
        };
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
        return self.cFlags(true);
    }
    /// The flags a generated C unit — the entry and the metadata tables — is
    /// compiled with. Under ThinLTO it stays machine code (LLVM-THINLTO-1): as
    /// bitcode the entry would import guest functions and inline them into a
    /// module with no pseudo-probe descriptors, where LLVM drops their call
    /// positions, and the frame-map tables of every module name the metadata
    /// records, which a native object keeps global.
    pub fn generatedFlags(self: Cache) Error![]const []const u8 {
        const all = try self.flags();
        if (self.codegen.lto != .thin) return all;
        const thin = options.Lto.thin.flag() orelse "";
        var kept: std.ArrayList([]const u8) = .empty;
        for (all) |flag| if (!std.mem.eql(u8, flag, thin)) try kept.append(self.context.allocator, flag);
        return kept.items;
    }
    /// `flags`, with the frame-pointer flags only when `pointers` is set: a
    /// runtime unit that cannot reach `fail` keeps every register.
    fn cFlags(self: Cache, pointers: bool) Error![]const []const u8 {
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
        try result.appendSlice(a, (try ownership_contract.parse(self.context.environ.get(ownership_contract.variable))).cFlags());
        if (pointers) try result.appendSlice(a, &frame_pointer_flags);
        if (self.codegen.lto.flag()) |flag| try result.append(a, flag);
        return result.toOwnedSlice(a);
    }
};
/// Resolved native code generator and optimization policy.
pub const Codegen = struct {
    tool: []const u8,
    llvm: bool = false,
    optimization: []const u8 = "default",
    lto: options.Lto = .off,
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

// spec-case: QBE-FRAMEMAP-1
test "only the runtime units that can reach fail keep frame pointers" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "ReleaseFast", .codegen = .{ .tool = "/qbe" } };
    const joined = try std.mem.join(context.allocator, " ", try cache.mergeCommand(&.{ "native_heap.c", "qbe_runtime.c", "native_text_methods.c" }, "/tmp/out.o"));
    // One group with frame pointers names the units that report traps; the
    // heap and collector group keeps every register.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, joined, "-fno-omit-frame-pointer"));
    const pointers = std.mem.indexOf(u8, joined, "-fno-omit-frame-pointer").?;
    const second = std.mem.lastIndexOf(u8, joined, "-cflags").?;
    try std.testing.expect(pointers < std.mem.indexOf(u8, joined, "/assets/qbe_runtime.c").?);
    try std.testing.expect(std.mem.indexOf(u8, joined, "/assets/native_text_methods.c").? < second);
    try std.testing.expect(second < std.mem.indexOf(u8, joined, "/assets/native_heap.c").?);
    try std.testing.expect(keepsFramePointers("qbe_stack.c") and !keepsFramePointers("native_heap.c"));
    const loose = try std.mem.join(context.allocator, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, loose, "-fno-omit-frame-pointer") != null);
}

// spec: VALUE-SEMANTICS-9
test "value copies retain frame pointers when they report an allocation failure" {
    try std.testing.expect(keepsFramePointers("native_value_copy.c"));
}

// spec: QBE-STRIP-1
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

// spec-case: INCREMENTAL-KEYS-1
test "object keys frame their parts, so moving bytes between kind, input and environment moves the key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "Debug", .codegen = .{ .tool = "/qbe" } };
    const whole = try cache.identity("function", "il");
    try std.testing.expectEqual(@as(usize, 64), whole.len);
    try std.testing.expect(!std.mem.eql(u8, whole, try cache.identity("functioni", "l")));
    try std.testing.expect(!std.mem.eql(u8, whole, try cache.identity("function", "il ")));
    var moved = cache;
    moved.environment = "envfunction";
    try std.testing.expect(!std.mem.eql(u8, whole, try moved.identity("", "il")));
    // A unit's key is exactly the key a staged per-function object carries.
    try std.testing.expectEqualStrings(whole, try cache.unitKey("il"));
    try std.testing.expectEqualStrings(try cache.identity("qbe-batch-v1", "a\nb"), try cache.derived("qbe-batch-v1", "a\nb"));
}

// spec: BUILD-KEYS-1
test "an object key is the BLAKE3 of its framed environment, contract fields, kind and input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "Debug", .codegen = .{ .tool = "/qbe" } };
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("mylang-object-key-v4");
    const contract = Contract.default;
    const parts = [_][]const u8{ "env", contract.bootstrap_language, contract.target, contract.runtime_abi, contract.effects, contract.flags, contract.compiler_identity, "function-digest", "abc" };
    for (parts) |part| blakeFrame(&hash, part);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    try std.testing.expectEqualStrings(&std.fmt.bytesToHex(digest, .lower), try cache.digestKey("abc"));
    // Every contract field reaches the key, not only its fingerprint.
    var flagged = cache;
    flagged.contract.flags = "-x";
    try std.testing.expect(!std.mem.eql(u8, try cache.digestKey("abc"), try flagged.digestKey("abc")));
}

// spec: BUILD-VERIFY-1
test "a stored object is accepted by its recorded file identity and otherwise only by its bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const cache: Cache = .{ .context = context, .directory = root, .temporary = root, .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "Debug", .codegen = .{ .tool = "/qbe" } };
    const candidate = try std.fs.path.join(a, &.{ root, "candidate.o" });
    try context.write(candidate, "object bytes");
    const stored = try cache.keep("k", candidate);
    try std.testing.expect(try cache.cached("k") != null);
    // An untouched file is accepted by `stat` alone: a fingerprint whose hash
    // half no longer matches does not matter while the identity does.
    const sidecar = try std.fs.path.join(a, &.{ root, "k.digest" });
    const recorded = try context.read(sidecar);
    const split = std.mem.indexOfScalar(u8, recorded, '\n').?;
    try context.write(sidecar, try std.mem.concat(a, u8, &.{ "mylang-object-v2:0:0", recorded[split..] }));
    try std.testing.expect(try cache.cached("k") != null);
    // A replaced file has another identity, so its bytes decide: equal bytes
    // under the original fingerprint are accepted, other bytes are not.
    try context.write(sidecar, recorded);
    const same = try std.fs.path.join(a, &.{ root, "same.o" });
    try context.write(same, "object bytes");
    try context.rename(same, stored.path);
    try std.testing.expect(try cache.cached("k") != null);
    const other = try std.fs.path.join(a, &.{ root, "other.o" });
    try context.write(other, "object BYTES");
    try context.rename(other, stored.path);
    try std.testing.expectEqual(@as(?Object, null), try cache.cached("k"));
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
        .codegen = .{ .tool = "/zig", .llvm = true, .optimization = "3", .lto = .full },
    };
    const joined = try std.mem.join(context.allocator, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, joined, "-O3") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-flto") != null);
    try std.testing.expectEqualStrings(joined, try std.mem.join(context.allocator, " ", try cache.generatedFlags()));
}

// spec-case: LLVM-THINLTO-1
test "under ThinLTO the runtime is thin bitcode and the generated C units stay machine code" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "ReleaseFast", .codegen = .{ .tool = "/zig", .llvm = true, .optimization = "3" } };
    cache.codegen.lto = .thin;
    const runtime = try std.mem.join(context.allocator, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, runtime, "-flto=thin") != null);
    const merged = try std.mem.join(context.allocator, " ", try cache.mergeCommand(&.{"qbe_runtime.c"}, "/tmp/out.o"));
    try std.testing.expect(std.mem.indexOf(u8, merged, "-flto=thin") != null);
    const generated = try std.mem.join(context.allocator, " ", try cache.generatedFlags());
    try std.testing.expect(std.mem.indexOf(u8, generated, "-flto") == null);
    try std.testing.expect(std.mem.indexOf(u8, generated, "-O3") != null);
}

test "native object cache mirror uses the effects-v4 contract" {
    const testing = std.testing;
    try testing.expectEqualStrings("effects-v4", Contract.default.effects);
}

// spec-case: RC-RUNTIME-CONTRACT-1
test "RC runtime contract reaches generated C and each merged archive source group" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const a = context.allocator;
    const cache: Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/zig", .mode = "ReleaseFast", .codegen = .{ .tool = "/qbe" } };
    // RC-DEFAULT-1: an absent carrier compiles for the RC default.
    const default = try std.mem.join(a, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, default, "-DMYL_NATIVE_RC=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, default, "MYL_NATIVE_RC_COUNTING") == null);
    try environment.put(ownership_contract.variable, "gc-v1");
    const gc = try std.mem.join(a, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, gc, "MYL_NATIVE_RC") == null);
    try environment.put(ownership_contract.variable, "rc-v5-counting");
    const counted = try std.mem.join(a, " ", try cache.generatedFlags());
    try std.testing.expect(std.mem.indexOf(u8, counted, "-DMYL_NATIVE_RC=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, counted, "-DMYL_NATIVE_RC_COUNTING=1") != null);
    const merged = try std.mem.join(a, " ", try cache.mergeCommand(&.{ "qbe_runtime.c", "native_heap.c" }, "out.o"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, merged, "-DMYL_NATIVE_RC=1"));
    try environment.put(ownership_contract.variable, "rc-v5");
    const plain = try std.mem.join(a, " ", try cache.flags());
    try std.testing.expect(std.mem.indexOf(u8, plain, "-DMYL_NATIVE_RC=1") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "MYL_NATIVE_RC_COUNTING") == null);
    try environment.put(ownership_contract.variable, "rc-v2");
    try std.testing.expectError(error.InvalidRuntimeContract, cache.flags());
}
