//! The engine's own kinds, with the code identities the build computed for them (`build_identity.kind_identities`).
//!
//! A kind's identity is not written here: the build forms it from the import closure of the roots listed in
//! `build_identity_rules.engine_kinds`, so a kind registered here without an entry there does not compile.
const std = @import("std");
const build_identity = @import("build_identity");
const context = @import("context.zig");
const digest_rules = @import("digest.zig");
const probe_kind = @import("kinds/probe.zig");
const probe_size_kind = @import("kinds/probe_size.zig");
const probe_class_kind = @import("kinds/probe_class.zig");
const test_exec_kind = @import("kinds/test_exec.zig");
const module_tokens_kind = @import("kinds/module_tokens.zig");
const test_report_kind = @import("kinds/test_report.zig");
const module_syntax_kind = @import("kinds/module_syntax.zig");
const project_graph_kind = @import("kinds/project_graph.zig");
const module_interface_kind = @import("kinds/module_interface.zig");
const module_check_kind = @import("kinds/module_check.zig");
const noalloc_closure_kind = @import("kinds/noalloc_closure.zig");
const module_passes_kind = @import("kinds/module_passes.zig");
const program_diagnostics_kind = @import("kinds/program_diagnostics.zig");
const unit_lower_kind = @import("kinds/unit_lower.zig");
const program_facts_kind = @import("kinds/program_facts.zig");
const unit_optimize_kind = @import("kinds/unit_optimize.zig");
const unit_emit_kind = @import("kinds/unit_emit.zig");
const ownership_proof_kind = @import("kinds/ownership_proof.zig");
const test_facts_kind = @import("kinds/test_facts.zig");
const test_graph_kind = @import("kinds/test_graph.zig");

/// The code identity the build computed for the engine kind called `name`.
pub fn identityOf(comptime name: []const u8) digest_rules.Digest {
    comptime {
        for (build_identity.kind_names, build_identity.kind_identities) |known, hex| {
            if (!std.mem.eql(u8, known, name)) continue;
            var out: digest_rules.Digest = undefined;
            _ = std.fmt.hexToBytes(&out, hex) catch @compileError("malformed engine kind identity");
            return out;
        }
        @compileError("no engine kind named " ++ name ++ " in build_identity_rules.engine_kinds");
    }
}

/// The size and digest of a file.
pub const probe: context.Kind = .{ .name = "engine-probe", .identity = identityOf("engine-probe"), .run = probe_kind.run };

/// The size of a file, through the probe.
pub const probe_size: context.Kind = .{ .name = "engine-probe-size", .identity = identityOf("engine-probe-size"), .run = probe_size_kind.run, .data = &probe };

/// Whether a file is small or large, through the size.
pub const probe_class: context.Kind = .{ .name = "engine-probe-class", .identity = identityOf("engine-probe-class"), .run = probe_class_kind.run, .data = &probe_size };

/// A test's verdict under a linked program (spec section 13). Its data, the source of the runner's answers, is set by the
/// shadow that registers it; this template has none, so a query through `selka engine` fails.
pub const test_exec: context.Kind = .{
    .name = "test-exec",
    .identity = identityOf("test-exec"),
    .run = test_exec_kind.run,
    .expensive = true,
    .result_digest = test_exec_kind.resultDigest,
};

/// A module source as the check reads it: the digest of its tokens without comments, blank lines and line numbers (test-loop
/// stage 6). It has no data until a `selka test` process registers it, so a query through `selka engine` fails.
pub const module_tokens: context.Kind = .{ .name = "module-tokens", .identity = identityOf("module-tokens"), .run = module_tokens_kind.run };

/// The report of an entry's complete, successful run (spec section 13), with no data until a `selka test` process registers it.
pub const test_report: context.Kind = .{ .name = "test-report", .identity = identityOf("test-report"), .run = test_report_kind.run };

/// The parts of one module's syntax (spec section 17.2): a digest for its header, each declaration, each function body and its
/// import list. It has no data until the front end's shadow registers it, so a query through `selka engine` fails.
pub const module_syntax: context.Kind = .{ .name = "module-syntax", .identity = identityOf("module-syntax"), .run = module_syntax_kind.run };

/// The modules of a program and their order (spec section 17.2), reading each module's import list. Its data, the front end's
/// answer and the `module-syntax` kind, is set by the shadow that registers it.
pub const project_graph: context.Kind = .{ .name = "project-graph", .identity = identityOf("project-graph"), .run = project_graph_kind.run };

/// What a module declares that another module can see, one part per name (spec section 17.2). Its data, the front end's answer
/// and the `module-syntax` kind, is set by the shadow that registers it.
pub const module_interface: context.Kind = .{ .name = "module-interface", .identity = identityOf("module-interface"), .run = module_interface_kind.run };

/// Which bodies of a module are checked and under what each was checked (spec section 17.2). Its data, the front end's answer and
/// the `module-syntax` and `module-interface` kinds, is set by the shadow that registers it.
pub const module_check: context.Kind = .{ .name = "module-check", .identity = identityOf("module-check"), .run = module_check_kind.run };

/// Whether one `@noalloc` function keeps its promise, judged over the bodies of every function Core reaches from it (spec section
/// 17.2, step G2i). Its data, the front end's check of the promise and the `module-check` kind whose body parts it reads, is set by
/// the shadow that registers it.
pub const noalloc_closure: context.Kind = .{ .name = "noalloc-closure", .identity = identityOf("noalloc-closure"), .run = noalloc_closure_kind.run };

/// What the whole-program passes concluded about each function of a module (spec section 17.2). Its data, the front end's answer
/// and the `module-check` kind, is set by the shadow that registers it.
pub const module_passes: context.Kind = .{ .name = "module-passes", .identity = identityOf("module-passes"), .run = module_passes_kind.run };

/// What `check` prints for a program: every module's warnings, in module order (spec section 17.2). Its data, the front end's answer
/// and the `project-graph` and `module-passes` kinds, is set by the shadow that registers it.
pub const program_diagnostics: context.Kind = .{ .name = "program-diagnostics", .identity = identityOf("program-diagnostics"), .run = program_diagnostics_kind.run };

/// The lowered functions of one unit, a module or a generic instance (spec section 17.2): one part per function, the digest of its
/// artifact in canonical form. Its data, lowering's answer and the `module-check`, `module-interface` and `module-syntax` kinds
/// it reads, is set by the shadow that registers it.
pub const unit_lower: context.Kind = .{ .name = "unit-lower", .identity = identityOf("unit-lower"), .run = unit_lower_kind.run };

/// What the optimizer joins across functions (spec section 17.2, step G3h): parameter hulls, return intervals, effects, field
/// intervals, whether the program is closed and the runtime helpers. Its data, the optimizer's joins and the `unit-lower` kind it
/// reads, is set by the shadow that registers it.
pub const program_facts: context.Kind = .{ .name = "program-facts", .identity = identityOf("program-facts"), .run = program_facts_kind.run };

/// The optimized functions of one unit (spec section 17.2, step G3e): one part per function, the canonical digest of its final
/// body. Its data, the optimizer's answer and the `unit-lower` and `program-facts` kinds it reads, is set by the shadow that
/// registers it.
pub const unit_optimize: context.Kind = .{ .name = "unit-optimize", .identity = identityOf("unit-optimize"), .run = unit_optimize_kind.run };

/// The LLVM text of one unit (spec section 17.2, step G4a): the digest of the text the emitter made of a module, a generic instance or
/// a runtime helper. Its data, the emitter's answer and the `unit-optimize` kind whose parts it reads, is set by the shadow that
/// registers it.
pub const unit_emit: context.Kind = .{ .name = "unit-emit", .identity = identityOf("unit-emit"), .run = unit_emit_kind.run };

/// Which functions of a module have passed the ownership check, and the digest of the inputs each was checked under (spec section
/// 14). Its data, the answer the ownership cache publishes, is set by the cache's proofs that register it, so a query through
/// `selka engine` fails.
pub const ownership_proof: context.Kind = .{ .name = "ownership-proof", .identity = identityOf("ownership-proof"), .run = ownership_proof_kind.run };

/// The planning facts the test runner records for a lowered function, and the chunks of callee identities they point to (spec
/// section 17.7, step G4e). Its data, the runner's values, is set by the `selka test` process that registers it.
pub const test_facts: context.Kind = .{ .name = "test-facts", .identity = identityOf("test-facts"), .run = test_facts_kind.run };

/// The logical call graph the test runner records for a test entry: its head and the chunks of its nodes, tests and indexes (spec
/// section 17.7, step G4e). Its data, the runner's values, is set by the `selka test` process that registers it.
pub const test_graph: context.Kind = .{ .name = "test-graph", .identity = identityOf("test-graph"), .run = test_graph_kind.run };

/// Every engine kind, in the order of `build_identity.kind_names`.
pub const all = [_]*const context.Kind{
    &probe,
    &probe_size,
    &probe_class,
    &test_exec,
    &module_tokens,
    &test_report,
    &module_syntax,
    &project_graph,
    &module_interface,
    &module_check,
    &noalloc_closure,
    &module_passes,
    &program_diagnostics,
    &unit_lower,
    &program_facts,
    &unit_optimize,
    &unit_emit,
    &ownership_proof,
    &test_facts,
    &test_graph,
};

comptime {
    if (all.len != build_identity.kind_names.len) @compileError("the kinds here and the kinds the build knows differ in number");
    for (all, build_identity.kind_names) |kind, name| {
        if (!std.mem.eql(u8, kind.name, name)) @compileError("the kinds here and the kinds the build knows differ in order: " ++ name);
    }
}

/// The kinds and identities that are current, for retention.
pub fn current(a: std.mem.Allocator) std.mem.Allocator.Error![]const @import("retention.zig").Current {
    const out = try a.alloc(@import("retention.zig").Current, all.len);
    for (all, out) |kind, *slot| slot.* = .{ .kind = kind.name, .identity = kind.identity };
    return out;
}

/// The kind called `name`, or null.
pub fn byName(name: []const u8) ?*const context.Kind {
    for (all) |kind| if (std.mem.eql(u8, kind.name, name)) return kind;
    return null;
}

/// The files the identity of `kind` covers, relative to `src` (`code` are the ones the kind implements, which the scan
/// reads; the others are runner code it covers), and the identity as hexadecimal text.
pub const Closure = struct { files: []const []const u8, code: []const []const u8, identity: []const u8 };

/// The closure of the engine kind called `name`, or null when there is no such kind.
pub fn closureOf(name: []const u8) ?Closure {
    inline for (build_identity.kind_names, build_identity.kind_inputs, build_identity.kind_code, build_identity.kind_identities) |known, files, code, hex| {
        if (std.mem.eql(u8, known, name)) return .{ .files = files, .code = code, .identity = hex };
    }
    return null;
}

test "every engine kind carries the identity the build computed, which is not zero" {
    const zero: digest_rules.Digest = @splat(0);
    try std.testing.expect(!std.mem.eql(u8, &probe.identity, &zero));
    try std.testing.expect(!std.mem.eql(u8, &probe.identity, &probe_size.identity));
    try std.testing.expectEqualStrings(build_identity.kind_identities[1], &digest_rules.hex(probe_size.identity));
    try std.testing.expectEqual(@as(?*const context.Kind, &probe), byName("engine-probe"));
    try std.testing.expectEqual(@as(?*const context.Kind, null), byName("no-such-kind"));
}

test "the closure of a kind names the engine runtime it runs on, and not the compiler" {
    const closure = closureOf("engine-probe").?;
    var names_context = false;
    var names_compiler = false;
    for (closure.files) |path| {
        names_context = names_context or std.mem.eql(u8, path, "core/engine/context.zig");
        names_compiler = names_compiler or std.mem.eql(u8, path, "compiler.zig");
    }
    try std.testing.expect(names_context);
    try std.testing.expect(!names_compiler);
    try std.testing.expectEqual(@as(usize, 64), closure.identity.len);
    try std.testing.expectEqual(@as(?Closure, null), closureOf("no-such-kind"));
}
