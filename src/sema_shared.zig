//! Declarations the semantic checker's modules share: diagnostic codes and
//! messages, and the small value types that cross module boundaries.
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
