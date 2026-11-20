//! The `binary` record codec from the host side: exact octets, a mixed record round trip, and clean failure on a short
//! or malformed input (the language-level suite is tests/lang/binary_codec.selka).
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");

test "binary writes LEB128 and zigzag octets and reads a mixed record back" {
    try fixture.run(t.allocator, "import binary\n" ++
        "import byte_builder\n" ++
        "import hex\n" ++
        "func main() -> int:\n" ++
        "    mut builder = byte_builder.create()\n" ++
        "    binary.put_uvarint(mut builder, 300u64)\n" ++
        "    binary.put_varint(mut builder, -64)\n" ++
        "    binary.put_u16_le(mut builder, 0xabcdu16)\n" ++
        "    binary.put_i32_le(mut builder, i32(-2))\n" ++
        "    binary.put_text(mut builder, \"ok\")\n" ++
        "    binary.put_bytes(mut builder, b\"\\x01\\x02\")\n" ++
        "    const data = byte_builder.finish(builder)\n" ++
        "    if hex.encode(data) != \"ac027fcdabfeffffff026f6b020102\":\n" ++
        "        return 1\n" ++
        "    mut at = 0\n" ++
        "    match binary.get_uvarint(data, mut at):\n" ++
        "        case Ok(value):\n" ++
        "            if value != 300u64 or at != 2:\n" ++
        "                return 2\n" ++
        "        case Err(_):\n" ++
        "            return 3\n" ++
        "    return 42\n", 42);
}

test "binary reports a truncated, overlong or non-UTF-8 field and leaves the position where it was" {
    try fixture.run(t.allocator, "import binary\n" ++
        "func main() -> int:\n" ++
        "    mut at = 0\n" ++
        "    match binary.get_u32_le(b\"\\x01\\x02\", mut at):\n" ++
        "        case Ok(_):\n" ++
        "            return 1\n" ++
        "        case Err(error):\n" ++
        "            if error != binary.Error.Truncated or at != 0:\n" ++
        "                return 2\n" ++
        "    match binary.get_uvarint(b\"\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x80\\x01\", mut at):\n" ++
        "        case Ok(_):\n" ++
        "            return 3\n" ++
        "        case Err(error):\n" ++
        "            if error != binary.Error.Overlong or at != 0:\n" ++
        "                return 4\n" ++
        "    match binary.get_text(b\"\\x02\\xc3\\x28\", mut at):\n" ++
        "        case Ok(_):\n" ++
        "            return 5\n" ++
        "        case Err(error):\n" ++
        "            if error != binary.Error.Text or at != 0:\n" ++
        "                return 6\n" ++
        "    return 42\n", 42);
}
