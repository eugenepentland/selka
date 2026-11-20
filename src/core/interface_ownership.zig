//! The Core half of the interface oracle (work item W9, goal G7: a caller is judged from signatures alone). `selka
//! interfaces oracle` checks each module twice, once in the whole program (every dependency a full source) and once
//! against its imports' interfaces (a dependency's ordinary body replaced by `pass`, its declaration standing in). The
//! front-end half (`src/module_interface_oracle.zig`) compares what the front end concludes. This half gives, for one of
//! those checks, the refusals Core would make: its ownership pass (`single_owner.checkEvery`, what `validate` reports)
//! and its allocation contracts (`allocation_contract.collectProgram`, what a build reports for `@noalloc`), each located
//! in its module's own source, so the oracle can require the two checks to agree.
//!
//! It lives in the core because the front end may not import the core (the core imports the front end as `selka`).
//! Core never reads an interface in a real build or check: every command checks the merged program of full sources. The
//! interface-only side is the oracle's own per-module check, whose program this half is handed.
const std = @import("std");
const language = @import("selka");
const single_owner = @import("single_owner.zig");
const allocation_contract = @import("allocation_contract.zig");
const oracle = language.module_interface_oracle;
const typed = language.typed;

/// A change for tests only that makes a caller's verdict depend on a callee's body, so a test can show that the
/// comparison sees such a dependence. Every command runs `none`.
pub const Mutant = enum {
    /// Core as it is.
    none,
    /// Also refuse every call, in a judged body, to a function whose body declares a local beyond its parameters.
    callee_locals,
};

/// One check's program, where its positions lie (`oracle.Locator`), and which of its bodies to judge.
pub const Subject = struct {
    program: typed.Program,
    locator: oracle.Locator,
    /// One flag per function (`oracle.Whole.judged`, `oracle.Single.judged`).
    judged: []const bool,
    mutant: Mutant = .none,
};

/// The code of the mutant's refusal; not a diagnostic code, since no command prints it.
pub const mutant_code = "w9-mutant";

/// Every refusal Core makes of `subject`, sorted by its text, each once: the ownership pass and the `@noalloc` promises of
/// the judged bodies (a promise is judged over everything its function calls, as a build judges it). `a` holds the result and may be an
/// arena; `work` takes each function's transient work and must free (`single_owner.Every.work`).
pub fn refusals(a: std.mem.Allocator, work: std.mem.Allocator, subject: Subject) error{OutOfMemory}![]const oracle.Refusal {
    var out: std.ArrayList(oracle.Refusal) = .empty;
    var every: single_owner.Every = .{ .work = work };
    try single_owner.checkEvery(a, subject.program, subject.judged, subject.locator.compilation.src, &every);
    for (single_owner.distinct(&every)) |failure| {
        if (try oracle.refusalAt(a, subject.locator, failure.span, failure.code, failure.message)) |refusal| try out.append(a, refusal);
    }
    for (try allocation_contract.collectProgram(a, try promisesJudged(a, subject), subject.locator.compilation.src)) |failure| {
        const item = try allocation_contract.diagnostic(a, failure);
        if (try oracle.refusalAt(a, subject.locator, item.span, item.code, item.message)) |refusal| try out.append(a, refusal);
    }
    if (subject.mutant == .callee_locals) try mutantRefusals(a, subject, &out);
    std.mem.sort(oracle.Refusal, out.items, {}, before);
    var kept: usize = 0;
    for (out.items) |item| {
        if (kept != 0 and std.mem.eql(u8, out.items[kept - 1].text, item.text)) continue;
        out.items[kept] = item;
        kept += 1;
    }
    return out.items[0..kept];
}

/// `subject`'s program with the `@noalloc` promises of the bodies it does not judge left out: a function an interface's
/// declaration stood in for has no body to keep a promise with, and its own module's check judges it.
fn promisesJudged(a: std.mem.Allocator, subject: Subject) error{OutOfMemory}!typed.Program {
    const functions = try a.dupe(typed.Function, subject.program.functions);
    for (functions, subject.judged) |*function, judged| if (!judged) {
        function.policy.noalloc = null;
    };
    var program = subject.program;
    program.functions = functions;
    return program;
}

/// The `callee_locals` mutant: a call in a judged body is refused when its callee's body declares a local of its own.
/// A callee an interface stood in for has only its parameters, so the two checks of a caller disagree.
fn mutantRefusals(a: std.mem.Allocator, subject: Subject, out: *std.ArrayList(oracle.Refusal)) error{OutOfMemory}!void {
    const program = subject.program;
    for (program.functions, subject.judged) |caller, judged| {
        if (!judged) continue;
        const body = program.statements[@backingInt(caller.scope.body)].span;
        for (program.nodes) |node| {
            if (node.data != .call) continue;
            if (node.span.start < body.start or node.span.end > body.end) continue;
            const callee = program.functions[@backingInt(node.data.call.function)];
            if (callee.scope.locals.len <= callee.signature.parameter_count) continue;
            const message = try std.fmt.allocPrint(a, "the call reads the body of {s} (W9 mutant)", .{callee.name});
            if (try oracle.refusalAt(a, subject.locator, node.span, mutant_code, message)) |refusal| try out.append(a, refusal);
        }
    }
}

fn before(_: void, left: oracle.Refusal, right: oracle.Refusal) bool {
    return std.mem.lessThan(u8, left.text, right.text);
}
