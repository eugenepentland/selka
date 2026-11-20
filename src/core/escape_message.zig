//! One message for every refusal of the Escape rule: a lent value cannot be stored or given anywhere that outlives its lender.
//!
//! The checker finds the refusals at many sites, under four codes and ten rule ids. Each site gathers the same facts and
//! calls `compose`, so the message says the same four things in the same order and on one line: what is lent (the expression
//! as the source spells it), who lends it, where it would outlive the lender, and the repairs. The codes, rule ids, locations
//! and fixes belong to the sites and do not change here; a repair the message names is the edit the site's fix makes.
//!
//! Lane OC's change of `mut c = place` into a borrow reports the later write through `c` with `composeWrite`.
const std = @import("std");
const language = @import("selka");
const pattern_message = @import("pattern_message.zig");

/// Who lends the value: the place the lent expression reads its storage from.
pub const Lender = union(enum) {
    /// A plain parameter: the caller's storage, read-only for the call.
    plain_parameter: []const u8,
    /// A `mut` parameter: the caller's storage, held exclusively for the call.
    mut_parameter: []const u8,
    /// An `own` parameter: an owner the callee may give away.
    own_parameter: []const u8,
    /// A local: an owner that may be given away until it is used again.
    local: []const u8,
    /// The value a nested pattern matched, named by the pattern the author wrote (`Ok(Some(v))`), never by the local the compiler
    /// keeps its layers in.
    matched: []const u8,
    /// A lender the checker has no name for, such as a compiler temporary.
    unnamed,
    /// The hidden owner of a fresh record (a constructor or a call's result) whose field is read within one statement.
    fresh_record,

    /// The lender's own name, when it has one.
    pub fn name(self: Lender) ?[]const u8 {
        return switch (self) {
            .plain_parameter, .mut_parameter, .own_parameter, .local => |text| text,
            .unnamed, .fresh_record, .matched => null,
        };
    }

    /// Whether the lender is the caller's storage, which outlives the call.
    fn callers(self: Lender) bool {
        return self == .plain_parameter or self == .mut_parameter;
    }
};

/// A named local binding, whether it was declared `mut`, and whether it certainly outlives the lender (a local declared outside
/// the loop that makes the lender again in each iteration).
pub const Binding = struct { name: []const u8, mutable: bool, outlives: bool = false };

/// Where the value would outlive its lender, or what the place it goes to needs.
pub const Destination = union(enum) {
    /// A named local binding.
    binding: Binding,
    /// A field of a record under construction or assigned; `leaves` when that record outlives the call.
    field: struct { record: []const u8, name: []const u8, leaves: bool },
    /// A list, dictionary or set that takes the value as an element; `leaves` when the collection outlives the call.
    element: struct { noun: []const u8, name: []const u8, leaves: bool },
    /// The value the function returns.
    returned,
    /// An `own` argument of a call.
    argument: struct { callee: []const u8, parameter: []const u8 },
    /// An argument the call only reads, where a moved value is a compiler-made wrapper such as an implicit `Some`.
    call_argument,
    /// A store the site cannot name more closely.
    elsewhere,
    /// A value built only to be compared (`found == Some(wanted)`), which keeps nothing once the comparison is made but
    /// needs its own value while it exists (F-11).
    compared: Compared,

    /// Whether the destination certainly outlives the lender.
    fn outlives(self: Destination) bool {
        return switch (self) {
            .returned => true,
            .field => |field| field.leaves,
            .element => |element| element.leaves,
            .binding => |binding| binding.outlives,
            .argument, .call_argument, .elsewhere, .compared => false,
        };
    }
};

/// The operand of a comparison that is built for it: its constructor as the source spells it (`Some`, `Ok`, `Tag`) and
/// whether it is a case of an enum, whose payload a `match` compares without building anything, or a record, whose
/// fields compare one by one.
pub const Compared = struct { constructor: []const u8, case: bool };

/// What the fix does about a written `own` that a lent value cannot use.
pub const WrittenOwn = union(enum) {
    /// Removing it leaves a program that checks: lend instead, or copy.
    lend,
    /// Removing it is the fix, though the value still needs a copy where it is kept.
    then_copy,
    /// At a return the signature already covers: remove it to return the declared borrow, or copy.
    borrow,
    /// At a return no `from` clause covers: remove it and declare these sources, or copy.
    declare: []const u8,
};

/// The repair at a binding that only lends what it was initialized from.
pub const BindingRepair = union(enum) {
    /// A `mut` binding of an element read that is never changed: bind it as `const`, or copy.
    constant: []const u8,
    /// A `mut` binding of an element read that is changed: write the binding back into the element, or copy.
    write_back: []const u8,
    /// A `const` alias of a place, repaired at its initializer: `own` there when the owner can give it, and copy.
    initializer: struct { binding: []const u8, give: bool },
    /// A `mut` local assigned from places: copy what each assignment reads.
    each_assignment: []const u8,
    /// A `mut` binding of an element of a writable owner that a later line writes through or passes with `mut` (W2): a copy
    /// would take that write and leave the element unchanged, so the message offers the copy and the element write as two
    /// spellings and no repair is automatic.
    lost_write: LostWrite,
    /// A binding of a nested pattern, which has no initializer: match the layers one at a time with `match own`, or copy. No fix:
    /// the edit is not local to the use.
    pattern: PatternBinding,
};

/// The binding a later line writes through, and that line's number, for `BindingRepair.lost_write`.
pub const LostWrite = struct { binding: []const u8, line: usize };

/// A `from` clause a return needs: the sources it names, and whether the check found that no caller in the program keeps
/// the result (F-15), so the message offers the clause alone rather than beside the copy.
pub const DeclareFrom = struct { sources: []const u8, alone: bool = false };

/// The form without a copy that a plain parameter allows, once the checker has rechecked the function with it: the parameter
/// declared `own` and the lent value written `own`.
pub const TakeParameter = struct {
    /// The parameter's name.
    parameter: []const u8,
    /// The parameter as its declaration spells it with `own` before it (`own name: str`); null when the source text is not at hand.
    declared: ?[]const u8 = null,
};

/// A moved argument that a later argument of the same call only reads (FR41): the call written with the reads first.
pub const ReadFirst = struct {
    /// The argument that gives the value, as the repair writes it, label included (`mem=own plain`).
    moved: []const u8,
    /// The arguments that now come before it, as the source writes them (`total=len(plain)`).
    reads: []const u8,
};

/// A form without a copy that the checker proved before it names it: where the repairs are the copy alone, the message offers it first.
pub const Form = union(enum) {
    /// The plain parameter taken `own` (COPY-B1).
    take_parameter: TakeParameter,
    /// The argument that gives the value written after the arguments that read it (FR41).
    read_first: ReadFirst,
};

/// A binding of a nested pattern, which has no initializer to give or copy: the pattern as the `case` line writes it, where the
/// binding lies in it, and what can give the matched value's payloads.
pub const PatternBinding = struct {
    binding: []const u8,
    pattern: []const u8,
    at: usize,
    matched: pattern_message.Matched,
};

/// The repairs a message offers, each the edit the site's fix makes when it has one.
pub const Repairs = union(enum) {
    /// `own LENT` gives it and `copy(LENT)` keeps both; `waits` names the refusal the repair waits for (FR61).
    give_or_copy: GiveOrCopy,
    /// Only `copy(LENT)`: the lender cannot give the value away.
    copy,
    /// A return no `from` clause covers: declare these sources, or copy.
    declare_from: DeclareFrom,
    /// A written `own` that a lent value cannot use.
    written_own: WrittenOwn,
    /// A binding that only lends what it was initialized from.
    binding: BindingRepair,
    /// A record of borrows: copy the borrowed fields, or give them with `own`.
    fields,
    /// A view assigned different sources on two branches: copy what each branch assigns.
    each_branch,
};

/// The 1-based line and column of the refusal a withheld repair waits for.
pub const Waits = struct { line: usize, column: usize };

/// The `give_or_copy` repairs, and the other refusal of the function that keeps them from being proven, if one does (FR61).
pub const GiveOrCopy = struct { waits: ?Waits = null };

/// The facts a refusal site gathers.
pub const Facts = struct {
    /// The lent expression as the source spells it, a written `own` marker included; empty when the check has no source text.
    lent: []const u8,
    lender: Lender,
    /// A second lender when the value reads two places, as a selection between two owners or a join of two branches.
    other: ?Lender = null,
    destination: Destination,
    repairs: Repairs,
    /// F-71: the `options.take_or` call that moves the value a binding of `o.unwrap_or(d)` only lends, when the option is
    /// one the function owns, and the `unwrap_or` it replaces; the message offers it before the other repairs.
    take_or: ?TakeOr = null,
    /// A form without a copy that a recheck proved (COPY-B1: the lender is a plain parameter that the function can take `own`; FR41: the
    /// value is read again by a later argument of the call that gives it). Where the repairs are the copy alone, the message names it
    /// first. The fix is the site's own: the copy for COPY-B1, the call written with the reads first for FR41.
    form: ?Form = null,
};

/// The spelling of `options.take_or(own o, d)` and of the `o.unwrap_or(d)` it replaces (F-71).
pub const TakeOr = struct { call: []const u8, replaced: []const u8 };

/// The longest lent expression a message quotes before it elides the rest.
const quote_limit = 48;

/// A quoted expression, whether it was cut (or never known), and whether the source wrote `own` before it.
const Quoted = struct { text: []const u8, cut: bool, marked: bool };

fn quoted(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!Quoted {
    if (text.len == 0) return .{ .text = "this value", .cut = true, .marked = false };
    var start: usize = 0;
    var marked = false;
    if (std.mem.startsWith(u8, text, "own") and text.len > 3 and std.ascii.isWhitespace(text[3])) {
        marked = true;
        start = 3;
        while (start < text.len and std.ascii.isWhitespace(text[start])) start += 1;
    }
    const body = std.mem.trim(u8, text[start..], " \t\r\n");
    const line_end = std.mem.indexOfAny(u8, body, "\r\n") orelse body.len;
    const cut = @min(line_end, quote_limit);
    if (cut == body.len) return .{ .text = try a.dupe(u8, body), .cut = false, .marked = marked };
    const kept = std.mem.trimEnd(u8, body[0..cut], " \t");
    return .{ .text = try std.fmt.allocPrint(a, "{s}...", .{kept}), .cut = true, .marked = marked };
}

/// The expression without a leading `own` marker and without line breaks, cut at the quote limit with `...`.
pub fn quote(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return (try quoted(a, text)).text;
}

/// Who lends a value, as a message names it: "the local `xs`", "the plain parameter `p`", "a temporary value".
pub fn lenderText(a: std.mem.Allocator, lender: Lender) std.mem.Allocator.Error![]const u8 {
    return lenderPhrase(a, lender);
}

fn lenderPhrase(a: std.mem.Allocator, lender: Lender) std.mem.Allocator.Error![]const u8 {
    return switch (lender) {
        .plain_parameter => |name| std.fmt.allocPrint(a, "the plain parameter `{s}`", .{name}),
        .mut_parameter => |name| std.fmt.allocPrint(a, "the `mut` parameter `{s}`", .{name}),
        .own_parameter => |name| std.fmt.allocPrint(a, "the `own` parameter `{s}`", .{name}),
        .local => |name| if (pattern_message.hidden(name)) a.dupe(u8, "a temporary value") else std.fmt.allocPrint(a, "the local `{s}`", .{name}),
        .matched => |pattern| std.fmt.allocPrint(a, "the value that `case {s}` matched", .{try quote(a, pattern)}),
        .unnamed, .fresh_record => a.dupe(u8, "a temporary value"),
    };
}

fn endPhrase(a: std.mem.Allocator, lender: Lender) std.mem.Allocator.Error![]const u8 {
    if (lender.callers()) return a.dupe(u8, "after the call returns");
    return switch (lender) {
        .own_parameter, .local => |name| if (pattern_message.hidden(name)) a.dupe(u8, "after the statement ends") else std.fmt.allocPrint(a, "after `{s}` ends", .{name}),
        .matched => a.dupe(u8, "after the match ends"),
        else => a.dupe(u8, "after the statement ends"),
    };
}

fn destinationPhrase(a: std.mem.Allocator, destination: Destination) std.mem.Allocator.Error![]const u8 {
    return switch (destination) {
        .binding => |binding| if (pattern_message.hidden(binding.name))
            a.dupe(u8, "the place it moves into")
        else
            std.fmt.allocPrint(a, "the {s}local `{s}`", .{ if (binding.mutable) "`mut` " else "", binding.name }),
        // The record's checked name (`m::Box<i64>`) as the source spells it (`Box[int]`), made when the message is.
        .field => |field| std.fmt.allocPrint(a, "field `{s}` of `{s}`", .{ field.name, try language.display_name.spelled(a, field.record) }),
        .element => |element| if (element.name.len == 0)
            std.fmt.allocPrint(a, "the {s}", .{element.noun})
        else
            std.fmt.allocPrint(a, "the {s} `{s}`", .{ element.noun, element.name }),
        .returned => a.dupe(u8, "the returned value"),
        .argument => |argument| std.fmt.allocPrint(a, "the `own` parameter `{s}` of `{s}`", .{ argument.parameter, argument.callee }),
        .call_argument => a.dupe(u8, "the argument of the call"),
        .elsewhere => a.dupe(u8, "the place it moves into"),
        .compared => |built| std.fmt.allocPrint(a, "the `{s}(...)` built for this comparison", .{built.constructor}),
    };
}

/// The spelling that compares without building the operand (F-11): a `match` on the other side for a case of an enum,
/// the fields for a record.
fn withoutBuilding(a: std.mem.Allocator, built: Compared, lent: Quoted) std.mem.Allocator.Error![]const u8 {
    const value = if (lent.cut) "the value" else try std.fmt.allocPrint(a, "`{s}`", .{lent.text});
    if (built.case) return std.fmt.allocPrint(
        a,
        "match on the other side and compare its payload with {s} (`case {s}(found): found == ...`) to compare without a copy",
        .{ value, built.constructor },
    );
    return std.fmt.allocPrint(a, "compare the other side's fields with {s} one by one to compare without a copy", .{value});
}

/// The name a message gives the set a store fills, or null when it is not a set or has no name.
fn setName(destination: Destination) ?[]const u8 {
    return switch (destination) {
        .element => |element| if (std.mem.eql(u8, element.noun, "set") and element.name.len != 0) element.name else null,
        else => null,
    };
}

/// Whether the store fills a set, whose own way to keep a lent value is `sets.include`.
pub fn fillsSet(destination: Destination) bool {
    return switch (destination) {
        .element => |element| std.mem.eql(u8, element.noun, "set"),
        else => false,
    };
}

/// The action that keeps both the lent value and the store's own copy: `copy(LENT)`, except into a set. `sets.add(mut s, copy(x))`
/// draws the warning that `sets.include(mut s, x)` stores the same element and copies it only when the set does not hold it yet,
/// so a store into a set names that call at once.
fn keepBoth(a: std.mem.Allocator, lent: Quoted, destination: Destination) std.mem.Allocator.Error![]const u8 {
    if (fillsSet(destination)) {
        if (lent.cut) return a.dupe(u8, "pass it to `sets.include` to keep both (it copies the value only when the set does not hold it yet)");
        const set = setName(destination) orelse return std.fmt.allocPrint(a, "pass `{s}` to `sets.include` to keep both (it copies `{s}` only when the set does not hold it yet)", .{ lent.text, lent.text });
        return std.fmt.allocPrint(a, "write `sets.include(mut {s}, {s})` to keep both (it copies `{s}` only when the set does not hold it yet)", .{ set, lent.text, lent.text });
    }
    if (lent.cut) return a.dupe(u8, "wrap it in `copy(...)` to keep both");
    return std.fmt.allocPrint(a, "write `copy({s})` to keep both", .{lent.text});
}

/// The advice of a borrowed value that a live borrow keeps from moving (R7): `copy it with copy(value)`, except into a set,
/// where `sets.include` keeps both and copies only an element the set does not hold yet (W8's open item, closed by W2).
pub fn movedBorrowAdvice(a: std.mem.Allocator, lent: []const u8, destination: Destination) std.mem.Allocator.Error![]const u8 {
    if (!fillsSet(destination)) return a.dupe(u8, "copy it with copy(value)");
    return std.fmt.allocPrint(a, "{s},", .{try keepBoth(a, try quoted(a, lent), destination)});
}

/// What the repairs say about `lent`: spelled out when the whole expression is quoted, else in words that need no cut text.
fn repairPhrase(a: std.mem.Allocator, repairs: Repairs, lent: Quoted, destination: Destination, form: ?Form) std.mem.Allocator.Error![]const u8 {
    const copy = try keepBoth(a, lent, destination);
    return switch (repairs) {
        .give_or_copy => |give| if (give.waits) |at| std.fmt.allocPrint(a, "the repair waits for the error at line {d}, column {d}: once that is repaired, {s}", .{
            at.line,
            at.column,
            try repairPhrase(a, .{ .give_or_copy = .{} }, lent, destination, form),
        }) else if (lent.cut)
            std.fmt.allocPrint(a, "write `own` before it to give it, or {s}", .{copy})
        else if (fillsSet(destination))
            std.fmt.allocPrint(a, "write `own {s}` to give it, or {s}", .{ lent.text, copy })
        else
            std.fmt.allocPrint(a, "write `own {s}` to give it, or `copy({s})` to keep both", .{ lent.text, lent.text }),
        .copy => if (form) |found| (if (lent.cut or fillsSet(destination)) copy else switch (found) {
            .take_parameter => |parameter| takeParameterPhrase(a, parameter, lent, copy),
            .read_first => |read| readFirstPhrase(a, read, lent, copy),
        }) else copy,
        .declare_from => |declared| if (declared.alone)
            std.fmt.allocPrint(a, "declare the result `from {s}`: no caller in the program keeps the result, so none needs a copy", .{declared.sources})
        else
            std.fmt.allocPrint(a, "declare the result `from {s}`, or {s}", .{ declared.sources, copy }),
        .written_own => |written| switch (written) {
            .lend => std.fmt.allocPrint(a, "remove `own` to lend it, or {s}", .{copy}),
            .then_copy => std.fmt.allocPrint(a, "remove `own`, then {s}", .{copy}),
            .borrow => std.fmt.allocPrint(a, "remove `own` to return the declared borrow, or {s}", .{copy}),
            .declare => |sources| std.fmt.allocPrint(a, "remove `own` and declare the result `from {s}`, or {s}", .{ sources, copy }),
        },
        .binding => |repair| bindingPhrase(a, repair, copy, lent, destination),
        .fields => a.dupe(u8, "wrap the borrowed fields in `copy(...)` to keep both, or write `own` before them to give them"),
        .each_branch => a.dupe(u8, "wrap what each branch assigns in `copy(...)` to keep both"),
    };
}

/// The parameter form before the copy: the declaration, the marker at the store, what a caller then writes, and the copy.
fn takeParameterPhrase(a: std.mem.Allocator, take: TakeParameter, lent: Quoted, copy: []const u8) std.mem.Allocator.Error![]const u8 {
    const declare = if (take.declared) |declared|
        try std.fmt.allocPrint(a, "declare `{s}` as `{s}`", .{ take.parameter, declared })
    else
        try std.fmt.allocPrint(a, "declare `{s}` as an `own` parameter", .{take.parameter});
    return std.fmt.allocPrint(
        a,
        "{s} and write `own {s}` here to take it (a caller then gives it with `own {s}`, or copies if it reads it again), or {s}",
        .{ declare, lent.text, take.parameter, copy },
    );
}

/// The moved argument after the arguments that read the value, and the copy: the order that reads first.
fn readFirstPhrase(a: std.mem.Allocator, read: ReadFirst, lent: Quoted, copy: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "write `{s}` after `{s}` so that `{s}` is read before it moves, or {s}", .{ read.moved, read.reads, lent.text, copy });
}

/// The repairs of a binding that a nested pattern made: give the payload by matching each layer on its own with `match own`
/// (the check owns a payload one layer at a time), or copy it. A value that no `match own` can give leaves the copy alone.
fn patternBindingPhrase(a: std.mem.Allocator, repair: PatternBinding, copy: []const u8, lent: Quoted, destination: Destination) std.mem.Allocator.Error![]const u8 {
    const steps = (try pattern_message.matchOwnSteps(a, repair.pattern, repair.at, repair.matched)) orelse return copy;
    const use = if (destination == .returned)
        try std.fmt.allocPrint(a, "return `{s}`", .{repair.binding})
    else if (lent.marked)
        try std.fmt.allocPrint(a, "keep `own {s}`", .{repair.binding})
    else
        try std.fmt.allocPrint(a, "write `own {s}`", .{repair.binding});
    const ends = switch (repair.matched) {
        .owner => |owner| try std.fmt.allocPrint(a, "; that gives `{s}` away", .{owner}),
        else => "",
    };
    return std.fmt.allocPrint(a, "to give it, match one layer at a time ({s}, and {s}{s}), or {s}", .{ steps, use, ends, copy });
}

fn bindingPhrase(a: std.mem.Allocator, repair: BindingRepair, copy: []const u8, lent: Quoted, destination: Destination) std.mem.Allocator.Error![]const u8 {
    return switch (repair) {
        .constant => |binding| std.fmt.allocPrint(a, "bind `{s}` as `const` to read it, or {s}", .{ binding, copy }),
        .write_back => |binding| std.fmt.allocPrint(a, "write `{s}` back into the element after changing it, or {s}", .{ binding, copy }),
        .initializer => |initializer| if (initializer.give)
            std.fmt.allocPrint(a, "write `own` in the initializer of `{s}` to give it, or wrap that initializer in `copy(...)` to keep both", .{initializer.binding})
        else
            std.fmt.allocPrint(a, "wrap the initializer of `{s}` in `copy(...)` to keep both", .{initializer.binding}),
        .each_assignment => |binding| std.fmt.allocPrint(a, "wrap what each assignment of `{s}` reads in `copy(...)` to keep both", .{binding}),
        .lost_write => |lost| lostWritePhrase(a, lost.binding, lost.line, lent),
        .pattern => |pattern| patternBindingPhrase(a, pattern, copy, lent, destination),
    };
}

/// The two spellings of a `mut` binding of an element that a line writes through (W2): a private copy, or a change of the
/// element itself. `line` is the write's line, or 0 when the refusal is at the write. No repair is automatic, because a copy
/// would take the write and leave the element unchanged.
fn lostWritePhrase(a: std.mem.Allocator, binding: []const u8, line: usize, lent: Quoted) std.mem.Allocator.Error![]const u8 {
    const place = if (lent.cut) "the element" else try std.fmt.allocPrint(a, "`{s}`", .{lent.text});
    const written = if (line == 0) try a.dupe(u8, "this write") else try std.fmt.allocPrint(a, "the write to `{s}` at line {d}", .{ binding, line });
    const private = if (lent.cut)
        try std.fmt.allocPrint(a, "wrap the initializer of `{s}` in `copy(...)`", .{binding})
    else
        try std.fmt.allocPrint(a, "write `mut {s} = copy({s})`", .{ binding, lent.text });
    return std.fmt.allocPrint(
        a,
        "a copy would keep {s} out of {s}, so no repair is automatic: {s} if `{s}` is a private copy, or change {s} itself " ++
            "(or store `{s}` back into it) if the element should change",
        .{ written, place, private, binding, place, binding },
    );
}

/// The one message of an Escape refusal, allocated from `a`.
pub fn compose(a: std.mem.Allocator, facts: Facts) std.mem.Allocator.Error![]const u8 {
    const lent = try quoted(a, facts.lent);
    const lender = if (facts.other) |other| try std.fmt.allocPrint(a, "{s} or {s}", .{ try lenderPhrase(a, facts.lender), try lenderPhrase(a, other) }) else try lenderPhrase(a, facts.lender);
    const own_name = if (facts.lender.name()) |name| facts.other == null and !lent.cut and std.mem.eql(u8, name, lent.text) else false;
    const first = if (own_name and lent.marked)
        try std.fmt.allocPrint(a, "`own {s}` cannot give {s}, which only lends it", .{ lent.text, lender })
    else if (own_name)
        try std.fmt.allocPrint(a, "a bare `{s}` only lends {s}", .{ lent.text, lender })
    else if (lent.text.len != 0 and std.mem.eql(u8, lent.text, "this value") and lent.cut)
        try std.fmt.allocPrint(a, "this value is lent by {s}", .{lender})
    else
        try std.fmt.allocPrint(a, "`{s}` is lent by {s}", .{ lent.text, lender });
    const destination = try destinationPhrase(a, facts.destination);
    const second = if (facts.destination.outlives())
        try std.fmt.allocPrint(a, "{s} would keep it {s}", .{ destination, try endPhrase(a, facts.lender) })
    else
        try std.fmt.allocPrint(a, "{s} needs its own value", .{destination});
    const repairs = try repairPhrase(a, facts.repairs, lent, facts.destination, facts.form);
    const bound = if (facts.lender == .fresh_record) try freshRecordAdvice(a, repairs, facts.lent, facts.destination) else repairs;
    const advice = switch (facts.destination) {
        .compared => |built| try std.fmt.allocPrint(a, "{s}, or {s}", .{ try withoutBuilding(a, built, lent), bound }),
        else => if (facts.take_or) |take|
            try std.fmt.allocPrint(a, "write `{s}` in place of `{s}` to move the value out of the option (`import options`), or {s}", .{ take.call, take.replaced, bound })
        else
            bound,
    };
    return std.fmt.allocPrint(a, "{s}, and {s}; {s}", .{ first, second, advice });
}

/// A field moved out of a record that the move of another field consumed (FR63).
pub const Consumed = struct {
    /// The record's name.
    record: []const u8,
    /// The first move as the source writes it, `own` included or not (`own state.lat`).
    first: []const u8,
    /// Where the first move stands: the line and column of the record's local in it.
    at: Waits,
    /// Whether the refusal is on that same line, so that the message need not give the line.
    same_line: bool,
    /// The places the `take` repair writes (`state.lat`), empty where the repair is not certain.
    takes: []const []const u8,
    /// Where the refused move stands against the first (FR91B), which chooses the way out the message names.
    shape: ConsumedShape = .separate,
    /// The moves written in one statement: the writer's own call or constructor when the repair joins the statements, else
    /// `f(own p.lo, own p.hi)` of the two moves (FR91B).
    together: []const u8 = "",
};

/// Where a refused field move stands against the move that consumed its record (FR91B).
pub const ConsumedShape = enum {
    /// In another statement: the moves go in one statement.
    separate,
    /// In the same statement, where it runs only on some paths (after `and` or `or`).
    conditional,
    /// In the same statement, inside an operation whose operands no group reaches (`append(mut xs, f(own p.a, own p.b))`).
    operand,
    /// In a branch that the first move's statement is outside of.
    branch,
    /// The same field again.
    twice,
};

/// The message of a second field moved out of one record: the first move that consumed it, then the moves that work (`take(mut
/// place)` of each field, which leaves its default, when that repair is certain; else every move in the one statement, FR91,
/// in the words of the program at hand, FR91B), and the copy last (COPY-B1).
pub fn consumedMessage(a: std.mem.Allocator, facts: Consumed) std.mem.Allocator.Error![]const u8 {
    const first = try quoted(a, facts.first);
    const place = if (facts.same_line)
        try std.fmt.allocPrint(a, "at column {d}", .{facts.at.column})
    else
        try std.fmt.allocPrint(a, "at line {d}, column {d}", .{ facts.at.line, facts.at.column });
    const head = try std.fmt.allocPrint(a, "'{s}' was moved or is unavailable on this path; `own {s}` {s} consumed `{s}`", .{ facts.record, first.text, place, facts.record });
    if (facts.takes.len == 0) return switch (facts.shape) {
        .separate => std.fmt.allocPrint(a, "{s}; move its fields in one statement, each once, as in `{s}`, or write copy(...) to keep both", .{ head, facts.together }),
        .conditional => std.fmt.allocPrint(
            a,
            "{s}; fields leave one record together only when every move runs, and this one runs only on some paths: pass them to one " ++
                "function, `{s}`, and test inside it, or write copy(...) to keep both",
            .{ head, facts.together },
        ),
        .branch => std.fmt.allocPrint(
            a,
            "{s}; fields leave one record together only in one statement that runs every move: move them in one statement inside this " ++
                "branch, as in `{s}`, and the same on each other path that needs them, or write copy(...) to keep both",
            .{ head, facts.together },
        ),
        .operand => std.fmt.allocPrint(
            a,
            "{s}; fields leave one record together only as arguments, fields or operands the statement itself runs, and this " ++
                "place is inside another operation: write `const value = {s}` in a statement before it and use `value`, or write copy(...) to keep both",
            .{ head, facts.together },
        ),
        .twice => std.fmt.allocPrint(a, "{s}; a field moves out once: write `copy({s})` at the first use to keep both", .{ head, first.text }),
    };
    var list: std.ArrayList(u8) = .empty;
    for (facts.takes, 0..) |take, index| {
        if (index != 0) try list.appendSlice(a, if (index + 1 == facts.takes.len) " and " else ", ");
        try list.appendSlice(a, try std.fmt.allocPrint(a, "`take(mut {s})`", .{take}));
    }
    return std.fmt.allocPrint(a, "{s}; write {s} to move each field out and leave its default, or write copy(...) to keep both", .{ head, list.items });
}

/// What a lent expression takes from the record it reads: a slice of a field, an element of a list field, or the field itself.
pub const Projection = enum { slice, element, field };

/// The projection the source spells for `lent`, read from the last bracket group at its end: a slice when it holds a `:` that is
/// not inside brackets, parentheses, braces or a quote, an element otherwise, and a field when nothing is indexed (FR27).
pub fn projectionOf(lent: []const u8) Projection {
    const text = std.mem.trimEnd(u8, lent, " \t");
    if (text.len == 0 or text[text.len - 1] != ']') return .field;
    var depth: usize = 0;
    var open: usize = text.len;
    var at = text.len;
    while (at > 0) {
        at -= 1;
        switch (text[at]) {
            ']' => depth += 1,
            '[' => {
                depth -= 1;
                if (depth == 0) {
                    open = at;
                    break;
                }
            },
            else => {},
        }
    }
    if (open == text.len) return .field;
    var nested: usize = 0;
    var inside: u8 = 0;
    var index = open + 1;
    while (index + 1 < text.len) : (index += 1) {
        const byte = text[index];
        if (inside != 0) {
            if (byte == '\\') index += 1 else if (byte == inside) inside = 0;
            continue;
        }
        switch (byte) {
            '"', '\'' => inside = byte,
            '[', '(', '{' => nested += 1,
            ']', ')', '}' => nested -|= 1,
            ':' => if (nested == 0) return .slice,
            else => {},
        }
    }
    return .element;
}

/// The advice that follows the repairs when a lent value is read from a field of a fresh record (a constructor, or a call's result):
/// the record lives only as long as the statement, so binding it to a local first gives the value an owner. The sentence names what
/// the refused expression reads, a slice, an element or a field, and is left out where binding the record would not help: a value
/// that is returned still lends it after the local ends, and a slice that is stored is still a slice of it (FR27). A `const` slice of
/// an element of a local record is a view, as its field's is (FR69), so one sentence serves a `const` and a `mut` binding.
fn freshRecordAdvice(a: std.mem.Allocator, repairs: []const u8, lent: []const u8, destination: Destination) std.mem.Allocator.Error![]const u8 {
    const unmarked = std.mem.trimStart(u8, lent, " \t");
    const text = if (std.mem.startsWith(u8, unmarked, "own ")) std.mem.trimStart(u8, unmarked[4..], " \t") else unmarked;
    const shape = projectionOf(text);
    if (destination == .returned or (shape == .slice and destination != .binding)) return repairs;
    const read = switch (shape) {
        .slice => " and slice that local's field",
        .element => " and read the element from that local",
        .field => " and read that local's field",
    };
    return std.fmt.allocPrint(a, "{s}, or bind the record to a local first{s}", .{ repairs, read });
}

/// The facts of a write through a binding that only lends a place, which lane OC's rule reports at the write.
pub const WriteFacts = struct {
    /// The binding written through (`c` in `mut c = place`).
    binding: []const u8,
    /// The place the binding was initialized from, as the source spells it.
    place: []const u8,
    lender: Lender,
    /// Whether `own PLACE` is a possible repair at the binding.
    can_give: bool,
    /// The place is an element of a writable owner (W2): a copy would keep the write out of it, so the message offers the
    /// copy and the element write as two spellings.
    element: bool = false,
};

/// The message at a write through a binding that only lends its place: the binding, who lends it, that the write needs the
/// binding to hold its own value, and both repairs at the binding (`mut c = own place`, `mut c = copy(place)`).
pub fn composeWrite(a: std.mem.Allocator, facts: WriteFacts) std.mem.Allocator.Error![]const u8 {
    const place = try quoted(a, facts.place);
    const lender = try lenderPhrase(a, facts.lender);
    if (facts.element) {
        const both = try lostWritePhrase(a, facts.binding, 0, place);
        return std.fmt.allocPrint(a, "`{s}` is lent by {s}, and a write through `{s}` needs its own value; {s}", .{ facts.binding, lender, facts.binding, both });
    }
    const copy = if (place.cut)
        try a.dupe(u8, "wrap its initializer in `copy(...)` to keep both")
    else
        try std.fmt.allocPrint(a, "write `mut {s} = copy({s})` to keep both", .{ facts.binding, place.text });
    const repairs = if (!facts.can_give)
        copy
    else if (place.cut)
        try std.fmt.allocPrint(a, "write `own` before its initializer to give it, or {s}", .{copy})
    else
        try std.fmt.allocPrint(a, "write `mut {s} = own {s}` to give it, or `mut {s} = copy({s})` to keep both", .{ facts.binding, place.text, facts.binding, place.text });
    return std.fmt.allocPrint(a, "`{s}` is lent by {s}, and a write through `{s}` needs its own value; {s}", .{ facts.binding, lender, facts.binding, repairs });
}

/// How a change to a slice view's source came about: a write or a call that takes it `mut` leaves the source readable, a move gives
/// it away.
pub const ChangeKind = enum { write, move };

/// A place in the source, 1-based.
pub const Place = struct { line: usize, column: usize };

/// The change that made a slice view unreadable: its kind, the source text of the write, move or call argument, and where it is.
pub const Change = struct { kind: ChangeKind, text: []const u8, at: Place };

/// The facts of a slice view that a change to its source made unreadable (FR57, rule V3).
pub const InvalidatedFacts = struct {
    /// The view binding (`piece`).
    view: []const u8,
    /// The slice as the source spells it (`r.buf[r.pos:end]`), empty when the check has no source text.
    slice: []const u8,
    lender: Lender,
    change: Change,
    /// The read that is refused; null where the checker finds the view live at the change and does not know the read.
    read: ?Place = null,
    /// Whether the change lies after the binding and before the read in the source, so that reading first is a reorder.
    reorder: bool,
    /// Whether the source stays readable and is an owner the slice names directly, so keeping the span and slicing again where it
    /// is read gives the view anew.
    respan: bool,
};

fn joinOr(a: std.mem.Allocator, items: []const []const u8) std.mem.Allocator.Error![]const u8 {
    if (items.len == 1) return items[0];
    if (items.len == 2) return std.fmt.allocPrint(a, "{s}, or {s}", .{ items[0], items[1] });
    const head = try std.mem.join(a, ", ", items[0 .. items.len - 1]);
    return std.fmt.allocPrint(a, "{s}, or {s}", .{ head, items[items.len - 1] });
}

/// Whether `text` begins with the identifier `name`: `r.buf[1:]` begins with `r`, not with `r2` and not with `buf`.
pub fn startsWithName(text: []const u8, name: []const u8) bool {
    const body = std.mem.trimStart(u8, text, " \t");
    if (name.len == 0 or !std.mem.startsWith(u8, body, name)) return false;
    return body.len == name.len or !(std.ascii.isAlphanumeric(body[name.len]) or body[name.len] == '_');
}

/// Whether the `=` at `at` is an assignment's: not the second `=` of `==`, and not the end of `<=`, `>=` or `!=`.
fn assignsAt(body: []const u8, at: usize) bool {
    if (at + 1 < body.len and body[at + 1] == '=') return false;
    return at == 0 or std.mem.indexOfScalar(u8, "=!<>", body[at - 1]) == null;
}

/// The place a write names: the text before the `=` of a statement (`r.pos` of `r.pos = end + 1`), the argument after `mut `, or the text
/// itself; the operator of `r.n += 1` is left out. An `=` inside brackets, a quote or a comparison (`==`, `<=`, `>=`, `!=`) is not the assignment.
fn writtenPlace(text: []const u8) []const u8 {
    const body = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.startsWith(u8, body, "mut ")) return std.mem.trim(u8, body[4..], " \t");
    var depth: usize = 0;
    var inside: u8 = 0;
    var at: usize = 0;
    while (at < body.len) : (at += 1) {
        const byte = body[at];
        if (inside != 0) {
            if (byte == '\\') at += 1 else if (byte == inside) inside = 0;
            continue;
        }
        switch (byte) {
            '"', '\'' => inside = byte,
            '[', '(', '{' => depth += 1,
            ']', ')', '}' => depth -|= 1,
            '=' => if (depth == 0 and assignsAt(body, at)) return std.mem.trimEnd(u8, std.mem.trimEnd(u8, body[0..at], " \t"), "+-*/%&|^ \t"),
            else => {},
        }
    }
    return body;
}

/// The message of a slice view that a change to its source made unreadable: the view and what it slices, its lender, the write or
/// move that changed the lender with its line and column, the read that is refused, and the repairs in the order that copies
/// nothing first: read the view before the change, keep the span and slice again, and the copy last (FR57). A repair that does not
/// apply to the case is left out: the reorder needs the change between the binding and the read, the span needs the source to stay
/// readable, and an `own` parameter or a `from` result does not help a view that dies at a change inside the function.
pub fn composeInvalidated(a: std.mem.Allocator, facts: InvalidatedFacts) std.mem.Allocator.Error![]const u8 {
    const lender = try lenderPhrase(a, facts.lender);
    const slice = try quoted(a, facts.slice);
    const first = if (facts.slice.len == 0 or slice.cut)
        try std.fmt.allocPrint(a, "`{s}` is a slice view lent by {s}", .{ facts.view, lender })
    else
        try std.fmt.allocPrint(a, "`{s}` is the slice `{s}`, lent by {s}", .{ facts.view, slice.text, lender });
    const owner = facts.lender.name() orelse "it";
    const text = (try quoted(a, facts.change.text)).text;
    const place = try std.fmt.allocPrint(a, "line {d}, column {d}", .{ facts.change.at.line, facts.change.at.column });
    const changed = switch (facts.change.kind) {
        .write => blk: {
            const target = writtenPlace(text);
            const what = if (std.mem.startsWith(u8, text, "mut "))
                try std.fmt.allocPrint(a, "the `mut` argument `{s}`", .{target})
            else
                try std.fmt.allocPrint(a, "the write to `{s}`", .{target});
            const whole = if (std.mem.eql(u8, target, owner)) "" else " as a whole";
            break :blk try std.fmt.allocPrint(a, "{s} at {s} changes `{s}`{s}", .{ what, place, owner, whole });
        },
        .move => if (std.mem.eql(u8, text, owner))
            try std.fmt.allocPrint(a, "`{s}` is given away at {s}", .{ owner, place })
        else
            try std.fmt.allocPrint(a, "`{s}` at {s} gives `{s}` away", .{ text, place, owner }),
    };
    const outcome = if (facts.read) |read|
        try std.fmt.allocPrint(a, "so `{s}` cannot be read at line {d}, column {d}", .{ facts.view, read.line, read.column })
    else
        try std.fmt.allocPrint(a, "while `{s}` is still read after it", .{facts.view});
    var repairs: std.ArrayList([]const u8) = .empty;
    if (facts.reorder) try repairs.append(a, try std.fmt.allocPrint(a, "{s} `{s}` before line {d}", .{ if (facts.read == null) "finish with" else "use", facts.view, facts.change.at.line }));
    if (facts.respan) try repairs.append(a, try a.dupe(u8, "keep its span (the start and length) and slice again where it is read"));
    try repairs.append(a, try bindingPhrase(a, .{ .initializer = .{ .binding = facts.view, .give = false } }, "", slice, .elsewhere));
    return std.fmt.allocPrint(a, "{s}, and {s}, {s}; {s}", .{ first, changed, outcome, try joinOr(a, repairs.items) });
}
