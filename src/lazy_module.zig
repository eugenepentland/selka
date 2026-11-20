//! A module whose stored syntax was read as far as its declaration part: the bodies are decoded when something asks for them.
//!
//! `frontend_cache` reads the prefix of a stored entry (`syntax_store.zig`: the header, the declaration part and the table of body
//! extents) and hands it back as a `Module`; `interfaces` keeps it on the module's `Unit`; `lazy_loader.zig` fills a body of the merged
//! program from it. The entry's bytes are in memory when the entry came from the shared tier or was small enough to be read with its
//! prefix; otherwise the first body that is asked for reads the whole file once (`fetch`).
const std = @import("std");
const ast = @import("ast.zig");
const syntax_store = @import("syntax_store.zig");

/// Where the rest of an entry is read from when it is not in memory yet.
pub const Fetch = struct {
    context: ?*anyopaque,
    /// The whole encoded entry, or null when it is no longer stored (the caller then parses the module again).
    read: *const fn (context: ?*anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8,
};

/// How a build treats the bodies of the modules it reads from the syntax store.
pub const Mode = enum {
    /// Decode every module completely, as a build always did.
    eager,
    /// Decode the declaration part and fill a body when something asks for it.
    lazy,
    /// `lazy`, with every body that is not filled holding a sentinel instead of what the memory held: the mode of a verify run, in which a
    /// reader that missed its `ensureBody` reads garbage the comparison with `--no-cache` finds.
    lazy_sentinel,

    /// Whether bodies are filled on demand.
    pub fn isLazy(self: Mode) bool {
        return self != .eager;
    }
};

/// The byte a table entry that was not filled holds in a build that checks for the reads that missed their `ensureBody`: an enum tag, a
/// span and an id no node or statement has.
pub const sentinel: u8 = 0xAA;

/// One module's stored syntax, read as far as its declaration part.
pub const Module = struct {
    declarations: syntax_store.Declarations,
    /// The whole encoded entry, once it is in memory.
    whole: ?[]const u8,
    fetch: ?Fetch,

    /// The whole encoded entry, read now if it is not in memory yet; null when it has gone from the store.
    pub fn entry(self: *Module, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
        if (self.whole) |bytes| return bytes;
        const source = self.fetch orelse return null;
        self.whole = try source.read(source.context, allocator);
        return self.whole;
    }

    /// The nodes and statements the module's tables have: the lengths of the merged program's runs for this module.
    pub fn counts(self: Module) struct { nodes: usize, statements: usize } {
        return .{ .nodes = self.declarations.header.node_count, .statements = self.declarations.header.statement_count };
    }

    /// A program holding this module's declaration tables and, in tables of the full length, only the trees outside every lazy body: the
    /// nodes and statements of the unfilled bodies are not written. `fill` is the sentinel byte (null leaves them as the allocator gave them).
    pub fn sparseProgram(self: Module, allocator: std.mem.Allocator, fill: ?u8) syntax_store.Error!ast.Program {
        return syntax_store.withoutBodies(allocator, self.declarations, fill);
    }
};
