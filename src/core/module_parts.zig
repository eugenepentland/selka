//! The parts of one module's syntax (spec `docs/design/incremental-engine.md` §17.2, `module-syntax`): a digest for the
//! module's header, one for each declaration's head and one for each function's body, and the digests of its import list,
//! its export directives and its whole text.
//!
//! The parts of a module's text are cut so that every byte after the module's first declaration belongs to exactly one
//! `decl:` or `body:` part and every byte before it to `header`: a declaration's region runs from the start of its first line
//! (its attribute lines included) to the start of the next declaration's, and a function's region is split where its body
//! begins. So a change to any byte of the file changes at least one part, however the declarations are named, and an
//! edit inside one function's body changes that body's part alone. `imports`, `exports` and `module` are views of the
//! same text for readers that depend on those facts only, and are not part of the partition. `heads` is the digest of every
//! declaration's head (and of a constant's value) taken together: what other modules can see of the module, which a
//! function body's edit leaves alone.
//!
//! This file computes parts from a module the front end has loaded and parsed. The engine's `module-syntax` kind hands
//! them back as its result (`kinds/module_syntax.zig`), which is what the shadow compares.
const std = @import("std");
const language = @import("selka");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const ast = language.ast;
const Digest = digest_rules.Digest;

/// The domain string every part digest starts with.
pub const domain = "selka-module-part-v1";
/// The first line of the payload.
pub const payload_magic = "selka-module-syntax-v1";

/// One part: its name and the digest of what it covers (the engine's own, so the kind publishes it as it is).
pub const Part = record.Part;

/// Everything the engine records about one module's syntax.
pub const Parts = struct {
    /// The digest of the module's bytes, which the kind checks against the file it reads.
    source_digest: Digest,
    /// The payload: the magic line, the source digest and the import list.
    payload: []const u8,
    /// The parts, in byte order of their names.
    parts: []const Part,
};

/// A declaration found in the module's syntax.
const Declaration = struct {
    start: usize,
    kind: []const u8,
    name: []const u8,
    /// Where the body begins, for a function; null for any other declaration.
    body_start: ?usize,
    /// A constant: its body is its value, so it is part of what other modules see.
    constant: bool = false,
};

/// The first byte of the line that holds `offset`.
fn lineStart(bytes: []const u8, offset: usize) usize {
    var at = @min(offset, bytes.len);
    while (at > 0 and bytes[at - 1] != '\n') at -= 1;
    return at;
}

/// The digest of `bytes` under the part domain and a tag saying which kind of region it is.
fn partDigest(tag: []const u8, bytes: []const u8) Digest {
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(domain);
    const tag_length: [1]u8 = .{@intCast(tag.len)};
    state.update(&tag_length);
    state.update(tag);
    state.update(bytes);
    var out: Digest = undefined;
    state.final(&out);
    return out;
}

fn before(_: void, left: Declaration, right: Declaration) bool {
    if (left.start != right.start) return left.start < right.start;
    const kinds = std.mem.order(u8, left.kind, right.kind);
    if (kinds != .eq) return kinds == .lt;
    return std.mem.lessThan(u8, left.name, right.name);
}

fn partBefore(_: void, left: Part, right: Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// Every declaration of `syntax`, in source order.
fn declarationsOf(a: std.mem.Allocator, module: language.project.Module, syntax: ast.Program) std.mem.Allocator.Error![]Declaration {
    const bytes = module.src.bytes;
    var found: std.ArrayList(Declaration) = .empty;
    for (syntax.functions) |function| {
        const body = syntax.statements.items[@backingInt(function.body)].span;
        try found.append(a, .{
            .start = lineStart(bytes, ast.declarationStart(syntax, function.name)),
            .kind = "function",
            .name = module.src.text(function.name),
            .body_start = body.start,
            .constant = function.policy.constant,
        });
    }
    for (syntax.types.records) |declared| try found.append(a, typed(module, syntax, "record", declared.name));
    for (syntax.types.variants) |declared| try found.append(a, typed(module, syntax, if (declared.is_union) "union" else "variant", declared.name));
    for (syntax.types.domains) |declared| try found.append(a, typed(module, syntax, "domain", declared.name));
    for (syntax.types.resources) |declared| try found.append(a, typed(module, syntax, "resource", declared.name));
    for (syntax.types.constraints) |declared| try found.append(a, typed(module, syntax, "constraint", declared.name));
    for (syntax.types.expressions.aliases) |declared| try found.append(a, typed(module, syntax, "alias", declared.name));
    std.mem.sort(Declaration, found.items, {}, before);
    return found.items;
}

fn typed(module: language.project.Module, syntax: ast.Program, kind: []const u8, name: language.source.Span) Declaration {
    return .{
        .start = lineStart(module.src.bytes, ast.declarationStart(syntax, name)),
        .kind = kind,
        .name = module.src.text(name),
        .body_start = null,
    };
}

/// A named, contiguous range of the module's bytes that one part covers.
pub const Region = struct {
    name: []const u8,
    tag: []const u8,
    begin: usize,
    end: usize,
    /// Whether the region is part of what other modules can see of the module: a declaration's head, and a constant's value.
    head: bool = false,
};

/// The regions the `header`, `decl:` and `body:` parts cover, in source order: together they tile the module's bytes
/// exactly, with no gap and no overlap.
pub fn regionsOf(a: std.mem.Allocator, module: language.project.Module, syntax: ast.Program) std.mem.Allocator.Error![]const Region {
    const bytes = module.src.bytes;
    const declarations = try declarationsOf(a, module, syntax);
    var regions: std.ArrayList(Region) = .empty;
    var names: std.ArrayList(Part) = .empty;
    const first = if (declarations.len == 0) bytes.len else @min(declarations[0].start, bytes.len);
    try regions.append(a, .{ .name = "header", .tag = "header", .begin = 0, .end = first });
    var cursor = first;
    for (declarations, 0..) |declared, at| {
        const begin = @max(@min(declared.start, bytes.len), cursor);
        const end = if (at + 1 < declarations.len) @min(@max(declarations[at + 1].start, begin), bytes.len) else bytes.len;
        const label = try uniqueName(a, names.items, declared);
        try names.append(a, .{ .name = try std.fmt.allocPrint(a, "decl:{s}", .{label}), .digest = @splat(0) });
        if (declared.body_start) |body| {
            const split = std.math.clamp(body, begin, end);
            try regions.append(a, .{ .name = names.items[names.items.len - 1].name, .tag = "decl", .begin = begin, .end = split, .head = true });
            try regions.append(a, .{ .name = try std.fmt.allocPrint(a, "body:{s}", .{label}), .tag = "body", .begin = split, .end = end, .head = declared.constant });
        } else {
            try regions.append(a, .{ .name = names.items[names.items.len - 1].name, .tag = "decl", .begin = begin, .end = end, .head = true });
        }
        cursor = end;
    }
    return regions.items;
}

/// The parts of `module`, parsed as `syntax`, with everything allocated in `a`.
pub fn compute(a: std.mem.Allocator, module: language.project.Module, syntax: ast.Program) std.mem.Allocator.Error!Parts {
    const bytes = module.src.bytes;
    var parts: std.ArrayList(Part) = .empty;
    var heads = std.crypto.hash.Blake3.init(.{});
    heads.update(domain);
    heads.update("heads\x00");
    for (try regionsOf(a, module, syntax)) |region| {
        const digest = partDigest(region.tag, bytes[region.begin..region.end]);
        try parts.append(a, .{ .name = region.name, .digest = digest });
        if (!region.head) continue;
        heads.update(region.name);
        heads.update("\x00");
        heads.update(&digest);
    }
    var heads_digest: Digest = undefined;
    heads.final(&heads_digest);
    try parts.append(a, .{ .name = "heads", .digest = heads_digest });
    const imports = try importsText(a, module);
    const exports = try exportsText(a, module);
    try parts.append(a, .{ .name = "imports", .digest = partDigest("imports", imports) });
    try parts.append(a, .{ .name = "exports", .digest = partDigest("exports", exports) });
    try parts.append(a, .{ .name = "module", .digest = partDigest("module", bytes) });
    std.mem.sort(Part, parts.items, {}, partBefore);
    const source_digest = digest_rules.hash(bytes);
    const payload = try std.fmt.allocPrint(a, "{s}\n{s}\n{s}", .{ payload_magic, digest_rules.hex(source_digest), imports });
    return .{ .source_digest = source_digest, .payload = payload, .parts = parts.items };
}

/// `kind:name`, with `#2`, `#3` and so on for a name a module declares more than once (an error the check reports, but the
/// parts still have to be distinct).
fn uniqueName(a: std.mem.Allocator, so_far: []const Part, declared: Declaration) std.mem.Allocator.Error![]const u8 {
    const plain = try std.fmt.allocPrint(a, "{s}:{s}", .{ declared.kind, declared.name });
    var tries: usize = 1;
    var label = plain;
    while (taken(so_far, label)) : (tries += 1) label = try std.fmt.allocPrint(a, "{s}#{d}", .{ plain, tries + 1 });
    return label;
}

fn taken(so_far: []const Part, label: []const u8) bool {
    for (so_far) |part| {
        if (part.name.len > "decl:".len and std.mem.eql(u8, part.name["decl:".len..], label)) return true;
    }
    return false;
}

/// The import list as text: one `name as alias` line per import, in source order.
pub fn importsText(a: std.mem.Allocator, module: language.project.Module) std.mem.Allocator.Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (module.imports) |imported| try text.print(a, "{s} as {s}\n", .{ imported.name, imported.alias });
    return text.items;
}

/// The export directives as text: one `alias.name` (or `name`) line per directive, in source order.
fn exportsText(a: std.mem.Allocator, module: language.project.Module) std.mem.Allocator.Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (module.exports) |exported| {
        if (exported.alias) |alias| try text.print(a, "{s}.{s}\n", .{ alias, exported.name }) else try text.print(a, "{s}\n", .{exported.name});
    }
    return text.items;
}
