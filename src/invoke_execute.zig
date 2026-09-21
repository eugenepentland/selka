//! Checked project preparation and one bounded native child invocation.
//!
//! `mylang invoke` reuses the native test runner's machinery rather than a
//! parallel copy of it: the same immutable source snapshot, the same retained
//! `native-test-compile` session (facts, then a selective lower), the same
//! `mylang build --library` selective link, the same copied-value codec, and
//! the same child request/response protocol. Nothing here caches a call: every
//! requested invocation executes, and only the compiled artifacts are reused.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const sessions = @import("native_test_session.zig");
const snapshot = @import("native_test_snapshot.zig");
const execute = @import("native_test_execute.zig");
const invoke = @import("invoke.zig");
const budget = @import("memory_budget");
const Value = std.json.Value;

/// Checked-project and child-process failures an invocation can report.
pub const Error = sessions.Error || snapshot.Error || execute.Error;

/// Whether a prepared invocation may build and run native code. `frontend`
/// resolves no toolchain, so `--describe` answers without zig or qbe.
pub const Setup = enum { frontend, native };

/// One checked entry for a single `mylang invoke` process. The session owns the
/// temporary directory the materialized snapshot, the selective build and the
/// child request live under; the caller removes it when the answer is written.
pub const Prepared = struct {
    /// The invocation-owned session: paths, tool hashes and captured sources.
    session: sessions.Session,
    /// The checked project graph, with its executor once the build has run.
    project: sessions.Project,
};

/// The result of checking one entry: a retained project, or the compiler's own
/// located diagnostics when the project does not check.
pub const Check = union(enum) {
    /// A checked project whose facts are available.
    ok: Prepared,
    /// The compiler refused the project; the text is its own located output.
    rejected: []const u8,
};

/// Check the entry, patch a library entry with the test main stub, materialize
/// the snapshot and request its checked facts. A refusal returns the compiler's
/// own located diagnostics instead of only a status code, so the response can
/// carry the source-mapped failure. The selective build starts its own retained
/// compiler child from the shared query cache when the request executes.
pub fn check(context: fs.Context, opts: options.Options, setup: Setup) Error!Check {
    var session = switch (setup) {
        .frontend => try sessions.Session.initFrontend(context, opts),
        .native => try sessions.Session.init(context, opts),
    };
    errdefer context.remove(session.temporary);
    const patched = try snapshot.withTestEntry(context, session.source);
    const captured = try snapshot.materialize(context, patched, try context.temporary(session.temporary));
    const facts = try session.factsText(captured.entry_path);
    const project = switch (facts) {
        // A refusal is answered from the located text alone, so the temporary
        // copy of the project is released before the caller writes its response.
        .rejected => |diagnostics| {
            context.remove(session.temporary);
            return .{ .rejected = diagnostics };
        },
        .manifest => |bytes| try session.projectFromManifest(captured.entry_path, bytes),
    };
    return .{ .ok = .{ .session = session, .project = project } };
}

/// The checked schema document one prepared project publishes.
pub fn schema(prepared: *Prepared) Value {
    return prepared.project.schema;
}

/// Source, compiler, schema and ABI identities for one response. The schema
/// digest is the SHA-256 of the checked `language-schema-v1` document the
/// compiler published, so a caller can tell two contracts apart.
pub fn identities(prepared: *Prepared) Error!invoke.Identities {
    const a = prepared.session.context.allocator;
    const encoded = v.text(v.get(prepared.project.manifest, "schema"));
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(encoded, &digest, .{});
    return .{
        .source = prepared.session.source.identity,
        .compiler = prepared.session.hashes[0],
        .schema = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)),
        .abi = v.text(v.get(prepared.project.manifest, "abi")),
    };
}

/// The effective quotas one call runs under, after flag, environment and
/// built-in default are resolved against each other.
pub fn limits(resolved: execute.Limits) invoke.Limits {
    return .{
        .max_steps = resolved.max_steps,
        .max_frames = resolved.max_frames,
        .max_calls = resolved.max_calls,
        .timeout_ms = resolved.timeout_ms,
        .max_memory = resolved.max_memory orelse budget.test_default,
    };
}

/// What the project's declared interface says about one qualified name the
/// checked schema did not expose. A generic template and a private declaration
/// are both absent from the invokable schema, and the caller can only tell them
/// apart by reading the published contract manifest.
pub const Declaration = enum {
    /// The module is published but no declaration of that name is exported.
    private_target,
    /// The name is a generic template, so no concrete signature exists yet.
    generic_template,
    /// No published module carries that name at all.
    unknown,
};

/// Classify one unselectable target by reading the declared interface. The
/// extra compiler child runs only on this failure path; a refusal to answer
/// leaves the target unknown rather than failing the request twice.
pub fn declaration(prepared: *Prepared, qualified: []const u8) Declaration {
    const at = std.mem.indexOf(u8, qualified, "::") orelse return .unknown;
    const contracts = prepared.session.interfaceCheck(prepared.project.source) catch return .unknown;
    for (v.array(v.get(contracts, "modules"))) |module| {
        if (!std.mem.eql(u8, v.text(v.get(module, "name")), qualified[0..at])) continue;
        for (v.array(v.get(module, "declarations"))) |item| {
            if (!std.mem.eql(u8, v.text(v.get(item, "name")), qualified[at + 2 ..])) continue;
            return if (v.text(v.get(item, "generics")).len != 0) .generic_template else .private_target;
        }
        return .private_target;
    }
    return .unknown;
}

/// Build the selected export into a fresh native library and return its
/// executor, reusing the retained compilation for the selective lower.
pub fn build(prepared: *Prepared, qualified: []const u8) Error!void {
    const a = prepared.session.context.allocator;
    const path = try std.fs.path.join(a, &.{ prepared.project.directory, "native-invocation-select.txt" });
    try prepared.session.context.write(path, try selection(a, prepared.project.manifest, qualified));
    _ = try prepared.session.executor(&prepared.project, path);
}

/// The names one selective build must lower for `qualified`: the target and every
/// function it transitively reaches, resolved through the same dependency
/// closure the native-test planner uses for a test. Writing only the target left
/// its callees unlowered, so an export whose body called another function could
/// not be built at all — the emitter referenced a function that was never
/// emitted, and the failure surfaced as a bare `InternalError`. A name that the
/// manifest does not carry is refused rather than written, because the selection
/// is what the emitter trusts.
fn selection(a: std.mem.Allocator, manifest: Value, qualified: []const u8) Error![]const u8 {
    const functions = v.array(v.get(manifest, "functions"));
    var symbol: ?[]const u8 = null;
    for (functions) |function| {
        if (!std.mem.eql(u8, v.text(v.get(function, "name")), qualified)) continue;
        symbol = v.text(v.get(function, "symbol"));
    }
    const target = symbol orelse return error.ProjectConfigurationFailed;
    if (target.len == 0) return error.ProjectConfigurationFailed;
    // The context key only feeds the planner's result-cache digest, which this
    // caller never reads: it wants the closure, and a closure does not depend on
    // the key.
    const planned = @import("native_test_plan.zig").plan(a, manifest, target, qualified) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.ProjectConfigurationFailed,
    };
    defer planned.deinit(a);
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(a);
    for (planned.dependencies) |wanted| {
        for (functions) |function| {
            if (!std.mem.eql(u8, v.text(v.get(function, "symbol")), wanted)) continue;
            try text.appendSlice(a, v.text(v.get(function, "name")));
            try text.append(a, '\n');
        }
    }
    return text.toOwnedSlice(a);
}

/// Execute exactly one requested call in a fresh bounded child process. Every
/// requested invocation executes: this neither consults nor records a cached
/// call result, and it never retries. A missing executor after a successful
/// build is reported as a host failure rather than a crash.
pub fn run(prepared: *Prepared, function: Value, arguments: Value, quotas: execute.Limits) Error!execute.Attempt {
    const executor = prepared.project.executor orelse return .{
        .outcome = .{ .status = "infrastructure-failure", .diagnostics = "InvalidExecutor" },
    };
    return executor.attempt(function, arguments, quotas);
}
