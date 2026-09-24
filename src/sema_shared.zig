//! Declarations the semantic checker's modules share: diagnostic codes and
//! messages, and the small value types that cross module boundaries.
const std = @import("std");
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const source = @import("source.zig");
const typed = @import("typed.zig");
const ast = @import("ast.zig");
const option_flow = @import("option_flow.zig");
pub const call_argument_code = "E_CALL_ARGUMENT";
pub const eCollectionMethod = "E_COLLECTION_METHOD";
pub const eFileArgument = "E_FILE_ARGUMENT";
/// The ownership-transfer state of one local at a control-flow checkpoint.
pub const Pending = struct { available: bool, transfer_span: ?source.Span };
/// One pending node on the expression work queue, with the context it is checked in.
pub const Work = struct { default_value: bool = false, id: ast.NodeId, emit: bool = false, checkpoint: ?option_flow.Guard = null, sorted_key: bool = false, verify: ?struct { pending: []const Pending, facts: []const usize } = null };
/// The `lambda_types` entry of a sort-key lambda whose key type could not be
/// inferred (LAMBDA-KEY-INFER-1). No callback type is `unit`, so the marker
/// never collides with a real slot; its `E_SORT_KEY` already names the lambda.
pub const uninferred_lambda: typed.Type = .unit;
/// Whether a callee declares a `mut` footprint at this parameter position.
pub fn markerPositionDeclared(positions: []const u16, position: u16) bool {
    for (positions) |candidate| if (candidate == position) return true;
    return false;
}
/// Whether a managed byte-kind schema is the mutable octet buffer rather than an
/// immutable byte string.
pub fn isMutableBytes(schema: typed.Record) bool {
    return schema.collection.kind == .bytes and std.mem.eql(u8, schema.name, byte_buffer_name);
}
pub const eCellEquality = "E_CELL_EQUALITY";
/// One diagnostic for every rejected `Option` operation, so the intrinsic
/// methods and the `is None` test report the same code.
pub const eOptionTest = "E_OPTION_TEST";
pub const bufferOperation = "buffer_operation";
pub const eArenaBinding = "E_ARENA_BINDING";
pub const eEnvironmentName = "E_ENVIRONMENT_NAME";
pub const eWithResource = "E_WITH_RESOURCE";
pub const lambda_context_code = "E_LAMBDA_CONTEXT";
pub const variantDeclaredHere = "variant declared here";
/// One name a lambda body reads from its enclosing function.
pub const LambdaCapture = struct { name: []const u8 };
/// How a checked statement leaves control flow: whether it terminates, loops forever,
/// and which owned locals it must clean up.
pub const StatementFlow = struct {
    terminates: bool = false,
    /// A loop the checker proved never exits ends control flow without making a
    /// following statement a mistake, because its exit is inferred, not written.
    looping: bool = false,
    owned_cleanup: []const typed.LocalId = &.{},
};
