//! Bounded trial input/output types; identities and units remain distinct in Zig.
/// Nominal identity in the component catalog.
pub const ComponentId = enum(u64) { _ };
/// Nominal identity in the electrically distinct net catalog.
pub const NetId = enum(u64) { _ };
/// Signed physical coordinate or extent in micrometres.
pub const Micrometres = enum(i64) { _ };
/// Placement side of a component.
pub const Face = enum { top, bottom };
/// Faces covered by one keepout region.
pub const RegionFace = enum { top, bottom, both };
/// Routing layer of a track footprint.
pub const Layer = enum { front, back, inner };
/// Axis-aligned footprint with checked signed endpoints.
pub const Rect = struct { x: Micrometres, y: Micrometres, width: Micrometres, height: Micrometres };
/// Independent applicability flags for each feature family.
pub const Blocks = struct { component: bool = false, track: bool = false, via: bool = false };
/// Component identity, placement side and footprint.
pub const Component = struct { id: ComponentId, face: Face, rect: Rect };
/// Net identity, routing layer and rectangular footprint.
pub const Track = struct { net: NetId, layer: Layer, rect: Rect };
/// Through-via identity and footprint; regions apply on either face.
pub const Via = struct { net: NetId, rect: Rect };
/// Exhaustive input feature families and their distinct payloads.
pub const Feature = union(enum) { component: Component, track: Track, via: Via };
/// Keepout footprint, face policy, family flags and admitted nets.
pub const Region = struct { rect: Rect, face: RegionFace, blocks: Blocks, allow_nets: []const NetId };
/// Borrowed bounded snapshot; transport owns every backing slice.
pub const Board = struct { outline: Rect, components: []const ComponentId, nets: []const NetId, regions: []const Region, features: []const Feature };
/// Logical preflight failures in contract traversal order.
pub const InputProblem = enum { invalid_bounds, invalid_id, duplicate_component, duplicate_net, empty_blocks, unknown_allow_net, missing_component, missing_net };
/// Declared recoverable rectangle-service failures.
pub const GeometryFailure = enum { invalid_bounds, unavailable };
/// Separate malformed board state from a failed geometry service.
pub const Failure = union(enum) { input: InputProblem, geometry: GeometryFailure };
/// Board-boundary and keepout violations remain distinguishable.
pub const ViolationKind = enum { outside_board, keepout };
/// First offending feature and its optional keepout region.
pub const Violation = struct { feature: u64, kind: ViolationKind, region: ?u64 };
/// Complete count and optional first violation in stable order.
pub const Report = struct { violations: u64 = 0, first: ?Violation = null };
/// A complete report or declared failure, never a partial success.
pub const Outcome = union(enum) { ok: Report, err: Failure };
/// One validator outcome and its exact geometry invocation count.
pub const Observation = struct { outcome: Outcome, calls: u64 };
/// All callers must validate axes before adding their endpoints in i64.
pub fn valid(rect: Rect) bool {
    return axis(rect.x, rect.width) and axis(rect.y, rect.height);
}
fn axis(origin: Micrometres, extent: Micrometres) bool {
    const x = @backingInt(origin);
    const size = @backingInt(extent);
    const bound = 1_000_000_000;
    if (x < -bound or x > bound) return false;
    if (size < 1 or size > bound) return false;
    return x + size <= bound;
}
/// Access a feature footprint without erasing its identity-bearing payload.
pub fn rectangle(feature: Feature) Rect {
    return switch (feature) {
        inline else => |value| value.rect,
    };
}
/// Accumulate a report in stable traversal order.
pub fn add(report: *Report, feature: usize, kind: ViolationKind, region: ?usize) void {
    report.violations += 1;
    if (report.first == null) report.first = .{ .feature = feature, .kind = kind, .region = region };
}
