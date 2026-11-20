//! The component-worker-v1 frame: the golden octets `selfhost/worker/frame_test.selka` also asserts, and every refusal.
const std = @import("std");
const frame = @import("worker_frame.zig");

const request_id: [8]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8 };
const snapshot: [32]u8 = @splat(171);

fn header(kind: frame.Kind, length: u32) [frame.header_len]u8 {
    return frame.encodeHeader(.{ .kind = kind, .payload_length = length, .request_id = request_id, .snapshot = snapshot });
}

test "worker frame: a request header is the documented octets" {
    const eight = "\xab\xab\xab\xab\xab\xab\xab\xab";
    const expected = "SLKWRK01" ++ "\x01\x00\x00\x00" ++ "\x01\x00\x00\x00" ++ "\x00\x00\x00\x00" ++ "\x02\x00\x00\x00" ++ "\x01\x02\x03\x04\x05\x06\x07\x08" ++ eight ++ eight ++ eight ++ eight;
    try std.testing.expectEqualSlices(u8, expected, &header(.request, 2));
    try std.testing.expectEqual(@as(usize, 64), expected.len);
}

test "worker frame: a header decodes to the fields it was written from" {
    const got = try frame.decodeHeader(&header(.reply, 3));
    try std.testing.expectEqual(frame.Kind.reply, got.kind);
    try std.testing.expectEqual(@as(u32, 3), got.payload_length);
    try std.testing.expectEqualSlices(u8, &request_id, &got.request_id);
    try std.testing.expectEqualSlices(u8, &snapshot, &got.snapshot);
    const quit = try frame.decodeHeader(&header(.quit, 0));
    try std.testing.expectEqual(frame.Kind.quit, quit.kind);
    const limit = try frame.decodeHeader(&header(.request, frame.max_payload));
    try std.testing.expectEqual(frame.max_payload, limit.payload_length);
}

test "worker frame: BadMagic: any other opening eight octets" {
    var bytes = header(.request, 0);
    bytes[7] = '2';
    try std.testing.expectError(error.BadMagic, frame.decodeHeader(&bytes));
    bytes = header(.request, 0);
    bytes[0] = 'X';
    try std.testing.expectError(error.BadMagic, frame.decodeHeader(&bytes));
}

test "worker frame: UnsupportedVersion and UnsupportedSchema: only 1 and 1" {
    var bytes = header(.request, 0);
    bytes[8] = 2;
    try std.testing.expectError(error.UnsupportedVersion, frame.decodeHeader(&bytes));
    bytes = header(.request, 0);
    bytes[12] = 2;
    try std.testing.expectError(error.UnsupportedSchema, frame.decodeHeader(&bytes));
}

test "worker frame: UnknownKind: a kind past quit" {
    var bytes = header(.request, 0);
    bytes[16] = 3;
    try std.testing.expectError(error.UnknownKind, frame.decodeHeader(&bytes));
    bytes[19] = 1;
    try std.testing.expectError(error.UnknownKind, frame.decodeHeader(&bytes));
}

test "worker frame: PayloadTooLarge: one past the limit and the largest length" {
    var bytes = header(.request, 0);
    std.mem.writeInt(u32, bytes[20..24], frame.max_payload + 1, .little);
    try std.testing.expectError(error.PayloadTooLarge, frame.decodeHeader(&bytes));
    std.mem.writeInt(u32, bytes[20..24], std.math.maxInt(u32), .little);
    try std.testing.expectError(error.PayloadTooLarge, frame.decodeHeader(&bytes));
}

test "worker frame: QuitWithPayload: a quit frame announces no payload" {
    try std.testing.expectError(error.QuitWithPayload, frame.decodeHeader(&header(.quit, 1)));
}
