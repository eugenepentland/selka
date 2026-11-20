//! Stored syntax, version 2: a module's parse as a declaration part and one section per function body.
//!
//! The parser appends a function's tree contiguously, so the nodes and statements a body reaches lie in one interval of ids (the
//! copies `ast_subtree` makes for `case a | b:` alternatives included). `encode` finds those intervals and writes everything outside
//! them, with the declarations, in the declaration part, and each body's two intervals as a section of its own with its checksum. A
//! reader that wants the declarations reads `Header.size` bytes, then `Header.prefixLen` bytes, and decodes the declaration part
//! without touching a body; a body is decoded alone from its section when something asks for it (`decodeBody`), or re-parsed from the
//! module's bytes when its section is gone or damaged, since a re-parse yields the same ids (`bodyOfParse`).
//!
//! A function whose reach is not an interval of its own (two functions share a node, a declaration-level tree lies inside the interval,
//! the intervals overlap, a constant) keeps its tree in the declaration part: never wrong, only not lazy. Ids stay as the parser gave
//! them, so a module reassembled from its parts is the parse (`reassemble`). This is a cache encoding: `selka dump-syntax` and
//! `frontend_cache.encodeSyntax` keep printing the parse-order tables.
const std = @import("std");
const ast = @import("ast.zig");
const codec = @import("persist_codec.zig");
const source = @import("source.zig");
const literals_fact = @import("ast_literals.zig");

/// Failures of reading an entry: a malformed or truncated encoding, or a section whose checksum is not the recorded one.
pub const Error = codec.DecodeError || error{Damaged};

/// A half-open run of table ids.
pub const Interval = struct { start: u32, end: u32 };

/// One lazy function body: the function it belongs to and the two intervals of ids its tree occupies.
pub const BodyRef = struct { function: u32, nodes: Interval, statements: Interval };

/// A run of consecutive table entries kept in the declaration part, starting at id `start`.
pub fn Run(comptime T: type) type {
    return struct { start: u32, items: []T };
}

/// Where one body section lies in the entry: its offset from the first body byte, its length and its checksum.
pub const Extent = struct { offset: u64, len: u64, checksum: u64 };

/// The declaration tables a module holds besides its expression and statement tables.
pub const Tables = struct {
    types: ast.TypeDeclarations,
    functions: []const ast.Function,
    lambdas: []const ast.Lambda,
    attributes: []const ast.DeclarationAttributes,
    docstrings: []const ast.DeclarationDoc,
};

/// What a scan of the whole module would find, noted when the module is encoded so that a reader of the declaration part need not scan: the
/// literals the type catalog registers, in node order, and the retired constructs a rejection looks for.
pub const Facts = struct { literals: []const ast.Literal, retired: ast.Retired };

/// The declaration part as it is encoded: the tables, which functions are lazy, the nodes and statements outside every body and the facts.
const Stored = struct {
    tables: Tables,
    bodies: []const BodyRef,
    node_runs: []const Run(ast.Node),
    statement_runs: []const Run(ast.Statement),
    facts: Facts,
};

/// The nodes and statements of one body, in the order of their ids from the start of its intervals.
pub const Body = struct { nodes: []ast.Node, statements: []ast.Statement };

const magic: u32 = 0x3249_4e53;
const version: u32 = 2;
const extent_size = 24;

/// The fixed-size front of an entry: how many ids each table has, how long the declaration part is and its checksum.
pub const Header = struct {
    node_count: u32,
    statement_count: u32,
    body_count: u32,
    declaration_len: u64,
    declaration_checksum: u64,

    /// Bytes of the header.
    pub const size = 40;

    /// Read the header at the start of `bytes`.
    pub fn parse(bytes: []const u8) Error!Header {
        if (bytes.len < size) return error.Truncated;
        if (std.mem.readInt(u32, bytes[0..4], .little) != magic or std.mem.readInt(u32, bytes[4..8], .little) != version) return error.InvalidEncoding;
        return .{
            .node_count = std.mem.readInt(u32, bytes[8..12], .little),
            .statement_count = std.mem.readInt(u32, bytes[12..16], .little),
            .body_count = std.mem.readInt(u32, bytes[16..20], .little),
            .declaration_len = std.mem.readInt(u64, bytes[24..32], .little),
            .declaration_checksum = std.mem.readInt(u64, bytes[32..40], .little),
        };
    }

    /// Bytes from the start of the entry to the first body byte: the header, the declaration part and the table of body extents. Reading
    /// this prefix is enough for `decodeDeclarations`.
    pub fn prefixLen(self: Header) u64 {
        return size + self.declaration_len + extent_size * @as(u64, self.body_count);
    }
};

/// A decoded declaration part: the declaration tables, the nodes and statements outside every lazy body, and where each body lies.
pub const Declarations = struct {
    header: Header,
    tables: Tables,
    bodies: []const BodyRef,
    extents: []const Extent,
    node_runs: []const Run(ast.Node),
    statement_runs: []const Run(ast.Statement),
    facts: Facts,

    /// The position in `bodies` of the lazy body of function `function`, or null for a function whose tree is in the declaration part.
    pub fn bodyOf(self: Declarations, function: u32) ?usize {
        for (self.bodies, 0..) |body, position| if (body.function == function) return position;
        return null;
    }

    /// The section bytes of lazy body `position` inside the whole entry `entry`.
    pub fn section(self: Declarations, entry: []const u8, position: usize) Error![]const u8 {
        if (position >= self.extents.len) return error.InvalidEncoding;
        const extent = self.extents[position];
        const start = std.math.add(u64, self.header.prefixLen(), extent.offset) catch return error.InvalidEncoding;
        const end = std.math.add(u64, start, extent.len) catch return error.InvalidEncoding;
        if (end > entry.len) return error.Truncated;
        return entry[@intCast(start)..@intCast(end)];
    }
};

/// Read the declaration part of an entry from `prefix`, which holds at least `Header.prefixLen` bytes of it.
pub fn decodeDeclarations(allocator: std.mem.Allocator, prefix: []const u8) Error!Declarations {
    const header = try Header.parse(prefix);
    const declaration_end = std.math.add(u64, Header.size, header.declaration_len) catch return error.InvalidEncoding;
    if (prefix.len < header.prefixLen()) return error.Truncated;
    const declaration = prefix[Header.size..@intCast(declaration_end)];
    if (codec.checksum(declaration) != header.declaration_checksum) return error.Damaged;
    var reader = codec.Reader.init(allocator, declaration);
    const stored = try reader.read(Stored);
    if (!reader.done() or stored.bodies.len != header.body_count) return error.InvalidEncoding;
    const extents = try allocator.alloc(Extent, header.body_count);
    var table = codec.Reader.init(allocator, prefix[@intCast(declaration_end)..@intCast(header.prefixLen())]);
    for (extents) |*extent| extent.* = .{ .offset = try table.integer(u64), .len = try table.integer(u64), .checksum = try table.integer(u64) };
    return .{ .header = header, .tables = stored.tables, .bodies = stored.bodies, .extents = extents, .node_runs = stored.node_runs, .statement_runs = stored.statement_runs, .facts = stored.facts };
}

/// Decode the section `bytes` of lazy body `position`, verifying its checksum first. A damaged or short section is `Damaged` or
/// `Truncated`: the caller re-parses the module and takes `bodyOfParse`.
pub fn decodeBody(allocator: std.mem.Allocator, declarations: Declarations, position: usize, bytes: []const u8) Error!Body {
    if (position >= declarations.extents.len) return error.InvalidEncoding;
    if (codec.checksum(bytes) != declarations.extents[position].checksum) return error.Damaged;
    var reader = codec.Reader.init(allocator, bytes);
    const body = try reader.read(Body);
    if (!reader.done()) return error.InvalidEncoding;
    const reference = declarations.bodies[position];
    if (body.nodes.len != reference.nodes.end - reference.nodes.start or body.statements.len != reference.statements.end - reference.statements.start) return error.InvalidEncoding;
    return body;
}

/// The body `reference` names, taken from a parse of the module: what a re-parse supplies for a section that is gone or damaged. The
/// slices borrow the parse's tables.
pub fn bodyOfParse(program: ast.Program, reference: BodyRef) Body {
    return .{
        .nodes = program.nodes.items[reference.nodes.start..reference.nodes.end],
        .statements = program.statements.items[reference.statements.start..reference.statements.end],
    };
}

/// The program an entry holds with its bodies left out: the declaration tables, and node and statement tables of the full length that
/// hold only the trees outside every lazy body (`Declarations.node_runs`, `statement_runs`). A body's entries are as the allocator gave
/// them, or `fill` where it is given (the sentinel of a build that looks for reads that missed their fill). All storage is `allocator`'s.
pub fn withoutBodies(allocator: std.mem.Allocator, declarations: Declarations, fill: ?u8) Error!ast.Program {
    const nodes = try allocator.alloc(ast.Node, declarations.header.node_count);
    const statements = try allocator.alloc(ast.Statement, declarations.header.statement_count);
    if (fill) |byte| {
        @memset(std.mem.sliceAsBytes(nodes), byte);
        @memset(std.mem.sliceAsBytes(statements), byte);
    }
    for (declarations.node_runs) |run| _ = try place(ast.Node, nodes, run.start, run.items);
    for (declarations.statement_runs) |run| _ = try place(ast.Statement, statements, run.start, run.items);
    return .{
        .types = declarations.tables.types,
        .nodes = std.ArrayList(ast.Node).fromOwnedSlice(nodes),
        .statements = std.ArrayList(ast.Statement).fromOwnedSlice(statements),
        .functions = declarations.tables.functions,
        .lambdas = declarations.tables.lambdas,
        .attributes = declarations.tables.attributes,
        .docstrings = declarations.tables.docstrings,
    };
}

/// The program an entry holds: the declaration tables, and the two tables filled from the declaration part's runs and every body
/// section. All storage is allocated from `allocator`. `entry` is the whole encoding.
pub fn reassemble(allocator: std.mem.Allocator, entry: []const u8) Error!ast.Program {
    const declarations = try decodeDeclarations(allocator, entry);
    const program = try withoutBodies(allocator, declarations, null);
    var node_filled: usize = 0;
    var statement_filled: usize = 0;
    for (declarations.node_runs) |run| node_filled += run.items.len;
    for (declarations.statement_runs) |run| statement_filled += run.items.len;
    for (declarations.bodies, 0..) |reference, position| {
        const body = try decodeBody(allocator, declarations, position, try declarations.section(entry, position));
        node_filled += try place(ast.Node, program.nodes.items, reference.nodes.start, body.nodes);
        statement_filled += try place(ast.Statement, program.statements.items, reference.statements.start, body.statements);
    }
    // Every id is in exactly one run or body.
    if (node_filled != program.nodes.items.len or statement_filled != program.statements.items.len) return error.InvalidEncoding;
    return program;
}

fn place(comptime T: type, table: []T, start: u32, items: []const T) Error!usize {
    const end = std.math.add(usize, start, items.len) catch return error.InvalidEncoding;
    if (end > table.len) return error.InvalidEncoding;
    @memcpy(table[start..end], items);
    return items.len;
}

/// What `encode` decided: the lazy bodies in function order and how many functions keep their tree in the declaration part.
pub const Layout = struct { bodies: []const BodyRef, eager: usize };

/// Decide which functions are lazy: those whose body reaches an interval of ids that no other function and no declaration-level tree
/// (a parameter default, a field default, an attribute condition, a lambda, a constant's body) touches. All storage is `allocator`'s.
pub fn layout(allocator: std.mem.Allocator, program: ast.Program) std.mem.Allocator.Error!Layout {
    const functions = program.functions;
    var marks = try Marks.init(allocator, program);
    defer marks.deinit(allocator);
    const tainted = try allocator.alloc(bool, functions.len);
    defer allocator.free(tainted);
    @memset(tainted, false);
    const reach = try allocator.alloc(Reach, functions.len);
    defer allocator.free(reach);
    // Declaration-level trees first, so a body that reaches one is the one that gives way.
    marks.current = Marks.declaration;
    marks.walk(ast.TypeDeclarations, program.types);
    marks.walk([]const ast.Lambda, program.lambdas);
    marks.walk([]const ast.DeclarationAttributes, program.attributes);
    for (functions) |function| {
        marks.walk(ast.FunctionSignature, function.signature);
        if (function.policy.constant) marks.statement(function.body);
    }
    for (functions, 0..) |function, index| {
        if (function.policy.constant) {
            tainted[index] = true;
            reach[index] = .{};
            continue;
        }
        marks.begin(@intCast(index));
        marks.statement(function.body);
        reach[index] = marks.reach.normalized();
        // The body's root statement stays in the declaration part, so a reader that wants only a body's span or its first level (the
        // placement of a stand-in, a cache region) finds it without the body. The parser appends a block after its children, so the root
        // is the last statement of the reach; a root that is not (or a tree of the root alone) leaves nothing to load lazily.
        const root: u32 = @intCast(@backingInt(function.body));
        if (reach[index].statements.end == root + 1 and reach[index].statements.start < root) {
            reach[index].statements.end = root;
        } else {
            tainted[index] = true;
        }
    }
    for (marks.conflict, tainted) |met, *taint| taint.* = taint.* or met;
    // Intervals must be disjoint, and every id inside one belongs to its function or to nobody; a function that fails either test gives
    // way, which can in turn spoil another, so repeat until the set is stable.
    var changed = true;
    while (changed) {
        changed = false;
        const order = try allocator.alloc(u32, functions.len);
        defer allocator.free(order);
        var count: usize = 0;
        for (functions, 0..) |_, index| if (!tainted[index] and !reach[index].empty()) {
            order[count] = @intCast(index);
            count += 1;
        };
        std.mem.sort(u32, order[0..count], reach, struct {
            fn lessThan(context: []const Reach, left: u32, right: u32) bool {
                return context[left].nodes.start < context[right].nodes.start;
            }
        }.lessThan);
        var covered: u32 = 0;
        var previous: ?u32 = null;
        for (order[0..count]) |index| {
            if (reach[index].nodes.start == reach[index].nodes.end) continue;
            if (previous != null and reach[index].nodes.start < covered) {
                tainted[index] = true;
                tainted[previous.?] = true;
                changed = true;
            }
            if (reach[index].nodes.end > covered) {
                covered = reach[index].nodes.end;
                previous = index;
            }
        }
        for (order[0..count]) |index| {
            if (tainted[index]) continue;
            if (marks.foreign(index, reach[index])) {
                tainted[index] = true;
                changed = true;
            }
        }
        // Statement intervals must not overlap either.
        std.mem.sort(u32, order[0..count], reach, struct {
            fn lessThan(context: []const Reach, left: u32, right: u32) bool {
                return context[left].statements.start < context[right].statements.start;
            }
        }.lessThan);
        covered = 0;
        previous = null;
        for (order[0..count]) |index| {
            if (tainted[index] or reach[index].statements.start == reach[index].statements.end) continue;
            if (previous != null and reach[index].statements.start < covered) {
                tainted[index] = true;
                tainted[previous.?] = true;
                changed = true;
            }
            if (reach[index].statements.end > covered) {
                covered = reach[index].statements.end;
                previous = index;
            }
        }
    }
    var bodies: std.ArrayList(BodyRef) = .empty;
    var eager: usize = 0;
    for (functions, 0..) |_, index| {
        if (tainted[index] or reach[index].empty()) {
            eager += 1;
            continue;
        }
        try bodies.append(allocator, .{ .function = @intCast(index), .nodes = reach[index].nodes, .statements = reach[index].statements });
    }
    return .{ .bodies = try bodies.toOwnedSlice(allocator), .eager = eager };
}

/// The nodes and statements one walk reached, as the smallest intervals that hold them.
const Reach = struct {
    nodes: Interval = .{ .start = std.math.maxInt(u32), .end = 0 },
    statements: Interval = .{ .start = std.math.maxInt(u32), .end = 0 },

    fn empty(self: Reach) bool {
        return self.nodes.start >= self.nodes.end and self.statements.start >= self.statements.end;
    }

    /// The reach with an interval that holds nothing written as the empty run at zero, so it can be sliced and ordered.
    fn normalized(self: Reach) Reach {
        var out = self;
        if (out.nodes.start >= out.nodes.end) out.nodes = .{ .start = 0, .end = 0 };
        if (out.statements.start >= out.statements.end) out.statements = .{ .start = 0, .end = 0 };
        return out;
    }
};

/// Who reached each node and statement: a function by its index, the declaration part, or nobody.
const Marks = struct {
    const none = std.math.maxInt(u32);
    const declaration = std.math.maxInt(u32) - 1;
    program: ast.Program,
    node_owner: []u32,
    statement_owner: []u32,
    current: u32 = declaration,
    reach: Reach = .{},
    /// Per function: whether its walk met an id another owner had reached, or another owner met one of its.
    conflict: []bool,

    fn init(allocator: std.mem.Allocator, program: ast.Program) std.mem.Allocator.Error!Marks {
        const nodes = try allocator.alloc(u32, program.nodes.items.len);
        errdefer allocator.free(nodes);
        const statements = try allocator.alloc(u32, program.statements.items.len);
        errdefer allocator.free(statements);
        const conflict = try allocator.alloc(bool, program.functions.len);
        @memset(nodes, none);
        @memset(statements, none);
        @memset(conflict, false);
        return .{ .program = program, .node_owner = nodes, .statement_owner = statements, .conflict = conflict };
    }

    fn deinit(self: *Marks, allocator: std.mem.Allocator) void {
        allocator.free(self.node_owner);
        allocator.free(self.statement_owner);
        allocator.free(self.conflict);
    }

    fn begin(self: *Marks, owner: u32) void {
        self.current = owner;
        self.reach = .{};
    }

    /// Whether any id inside `reach` belongs to another function or to a declaration-level tree.
    fn foreign(self: *const Marks, index: u32, reach: Reach) bool {
        for (self.node_owner[reach.nodes.start..reach.nodes.end]) |owner| if (owner != none and owner != index) return true;
        for (self.statement_owner[reach.statements.start..reach.statements.end]) |owner| if (owner != none and owner != index) return true;
        return false;
    }

    fn claim(self: *Marks, owners: []u32, id: usize) bool {
        if (owners[id] == none) {
            owners[id] = self.current;
            return true;
        }
        if (owners[id] != self.current) {
            if (owners[id] < self.conflict.len) self.conflict[owners[id]] = true;
            if (self.current < self.conflict.len) self.conflict[self.current] = true;
        }
        return false;
    }

    fn statement(self: *Marks, id: ast.StatementId) void {
        const at = @backingInt(id);
        if (at >= self.statement_owner.len or !self.claim(self.statement_owner, at)) return;
        self.reach.statements.start = @min(self.reach.statements.start, @as(u32, @intCast(at)));
        self.reach.statements.end = @max(self.reach.statements.end, @as(u32, @intCast(at + 1)));
        self.walk(ast.Statement, self.program.statements.items[at]);
    }

    fn node(self: *Marks, id: ast.NodeId) void {
        const at = @backingInt(id);
        if (at >= self.node_owner.len or !self.claim(self.node_owner, at)) return;
        self.reach.nodes.start = @min(self.reach.nodes.start, @as(u32, @intCast(at)));
        self.reach.nodes.end = @max(self.reach.nodes.end, @as(u32, @intCast(at + 1)));
        self.walk(ast.Node, self.program.nodes.items[at]);
    }

    /// Visit every node and statement id inside `value`, whatever its shape.
    fn walk(self: *Marks, comptime T: type, value: T) void {
        if (T == ast.NodeId) return self.node(value);
        if (T == ast.StatementId) return self.statement(value);
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names, @typeInfo(T).@"struct".field_types) |name, Field| self.walk(Field, @field(value, name)),
            .@"union" => inline for (@typeInfo(T).@"union".field_names, @typeInfo(T).@"union".field_types) |name, Field| {
                if (std.meta.activeTag(value) == @field(std.meta.Tag(T), name)) self.walk(Field, @field(value, name));
            },
            .optional => |optional| if (value) |present| self.walk(optional.child, present),
            .pointer => |pointer| {
                if (pointer.size != .slice) @compileError("syntax walking needs owned slices, not pointers");
                if (pointer.child == u8) return;
                for (value) |item| self.walk(pointer.child, item);
            },
            .array => |array| for (value) |item| self.walk(array.child, item),
            else => {},
        }
    }
};

/// The facts of `program`, a module parsed from `src`: found by one pass over its tables, in node order.
pub fn factsOf(allocator: std.mem.Allocator, src: source.Source, program: ast.Program) std.mem.Allocator.Error!Facts {
    var literals: std.ArrayList(ast.Literal) = .empty;
    errdefer literals.deinit(allocator);
    var retired: ast.Retired = .{};
    for (program.nodes.items) |node| {
        if (literals_fact.of(src, node)) |literal| try literals.append(allocator, literal);
        retired = retired.merge(.ofNode(node));
    }
    for (program.statements.items) |statement| retired = retired.merge(.ofStatement(statement));
    return .{ .literals = try literals.toOwnedSlice(allocator), .retired = retired };
}

/// Encode `program`, a module's parse of `src`, as an entry: the header, the declaration part, the table of body extents and the body sections.
pub fn encode(allocator: std.mem.Allocator, src: source.Source, program: ast.Program) std.mem.Allocator.Error![]u8 {
    const decided = try layout(allocator, program);
    defer allocator.free(decided.bodies);
    const facts = try factsOf(allocator, src, program);
    defer allocator.free(facts.literals);
    var node_runs: std.ArrayList(Run(ast.Node)) = .empty;
    defer node_runs.deinit(allocator);
    var statement_runs: std.ArrayList(Run(ast.Statement)) = .empty;
    defer statement_runs.deinit(allocator);
    try outside(ast.Node, allocator, program.nodes.items, decided.bodies, .nodes, &node_runs);
    try outside(ast.Statement, allocator, program.statements.items, decided.bodies, .statements, &statement_runs);
    var declaration = codec.Writer.init(allocator);
    defer declaration.deinit();
    try declaration.write(Stored, .{
        .tables = .{ .types = program.types, .functions = program.functions, .lambdas = program.lambdas, .attributes = program.attributes, .docstrings = program.docstrings },
        .bodies = decided.bodies,
        .node_runs = node_runs.items,
        .statement_runs = statement_runs.items,
        .facts = facts,
    });
    var sections = codec.Writer.init(allocator);
    defer sections.deinit();
    var table = codec.Writer.init(allocator);
    defer table.deinit();
    for (decided.bodies) |reference| {
        var section = codec.Writer.init(allocator);
        defer section.deinit();
        try section.write(Body, bodyOfParse(program, reference));
        try table.integer(@as(u64, sections.bytes.items.len));
        try table.integer(@as(u64, section.bytes.items.len));
        try table.integer(codec.checksum(section.bytes.items));
        try sections.raw(section.bytes.items);
    }
    var out = codec.Writer.init(allocator);
    errdefer out.deinit();
    try out.integer(magic);
    try out.integer(version);
    try out.integer(@as(u32, @intCast(program.nodes.items.len)));
    try out.integer(@as(u32, @intCast(program.statements.items.len)));
    try out.integer(@as(u32, @intCast(decided.bodies.len)));
    try out.integer(@as(u32, 0));
    try out.integer(@as(u64, declaration.bytes.items.len));
    try out.integer(codec.checksum(declaration.bytes.items));
    try out.raw(declaration.bytes.items);
    try out.raw(table.bytes.items);
    try out.raw(sections.bytes.items);
    return out.bytes.toOwnedSlice(allocator);
}

const Which = enum { nodes, statements };

/// The runs of `items` that lie outside every body's interval of `which`.
fn outside(comptime T: type, allocator: std.mem.Allocator, items: []T, bodies: []const BodyRef, comptime which: Which, runs: *std.ArrayList(Run(T))) std.mem.Allocator.Error!void {
    const intervals = try allocator.alloc(Interval, bodies.len);
    defer allocator.free(intervals);
    for (bodies, intervals) |body, *interval| interval.* = if (which == .nodes) body.nodes else body.statements;
    std.mem.sort(Interval, intervals, {}, struct {
        fn lessThan(_: void, left: Interval, right: Interval) bool {
            return left.start < right.start;
        }
    }.lessThan);
    var at: u32 = 0;
    for (intervals) |interval| {
        if (interval.start > at) try runs.append(allocator, .{ .start = at, .items = items[at..interval.start] });
        at = @max(at, interval.end);
    }
    if (at < items.len) try runs.append(allocator, .{ .start = at, .items = items[at..] });
}
