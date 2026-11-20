//! The frame of a resident component worker (component-worker-v1): a 64-octet header and a payload over standard
//! input and output, the envelope of component-protocol-v1 with its own magic. `selfhost/worker/frame.selka` writes and
//! reads the same octets; `docs/tooling/component-protocol.md` states the contract.
//!
//!   offset  width  meaning
//!   0       8      magic `SLKWRK01`
//!   8       4      envelope version, 1
//!   12      4      operation schema, 1 (the echo operation)
//!   16      4      message kind: 0 request, 1 reply, 2 quit
//!   20      4      payload length, at most `max_payload`, 0 for a quit
//!   24      8      request id, opaque, echoed unchanged
//!   32      32     snapshot identity, opaque, echoed unchanged
//!
//! All integers are unsigned little-endian.
const std = @import("std");

/// Octets of a header.
pub const header_len = 64;
/// Largest payload either side accepts: 16 MiB.
pub const max_payload: u32 = 16 * 1024 * 1024;
/// The eight octets every frame opens with.
pub const magic = "SLKWRK01";

/// What a frame is.
pub const Kind = enum(u32) { request = 0, reply = 1, quit = 2 };

/// The fields of a header. The identity octets are opaque to both ends.
pub const Header = struct {
    kind: Kind,
    payload_length: u32,
    request_id: [8]u8,
    snapshot: [32]u8,
};

/// Why a header is refused.
pub const DecodeError = error{ BadMagic, UnsupportedVersion, UnsupportedSchema, UnknownKind, PayloadTooLarge, QuitWithPayload };

/// The 64 octets of `header`.
pub fn encodeHeader(header: Header) [header_len]u8 {
    var out: [header_len]u8 = undefined;
    @memcpy(out[0..8], magic);
    std.mem.writeInt(u32, out[8..12], 1, .little);
    std.mem.writeInt(u32, out[12..16], 1, .little);
    std.mem.writeInt(u32, out[16..20], @backingInt(header.kind), .little);
    std.mem.writeInt(u32, out[20..24], header.payload_length, .little);
    @memcpy(out[24..32], &header.request_id);
    @memcpy(out[32..64], &header.snapshot);
    return out;
}

/// Validate 64 octets and read the fields; a header that breaks any rule is refused whole.
pub fn decodeHeader(bytes: *const [header_len]u8) DecodeError!Header {
    if (!std.mem.eql(u8, bytes[0..8], magic)) return error.BadMagic;
    if (std.mem.readInt(u32, bytes[8..12], .little) != 1) return error.UnsupportedVersion;
    if (std.mem.readInt(u32, bytes[12..16], .little) != 1) return error.UnsupportedSchema;
    const kind = std.enums.fromInt(Kind, std.mem.readInt(u32, bytes[16..20], .little)) orelse return error.UnknownKind;
    const length = std.mem.readInt(u32, bytes[20..24], .little);
    if (length > max_payload) return error.PayloadTooLarge;
    if (kind == .quit and length != 0) return error.QuitWithPayload;
    return .{ .kind = kind, .payload_length = length, .request_id = bytes[24..32].*, .snapshot = bytes[32..64].* };
}
