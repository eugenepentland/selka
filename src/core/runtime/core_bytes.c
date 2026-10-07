/* S3 port of native_bytes.c: octet algorithms adapted to the Core leaf header.
   kind 5 is mutable bytes, reserved=0; immutable snapshots own independent data. */
#define MYL_KIND_BUFFER 5u

myl_block *myl_core_buffer_new(uint64_t capacity) {
    if (capacity > INT64_MAX) out_of_memory();
    return block_new(MYL_KIND_BUFFER, (int64_t)capacity, 1);
}
myl_block *myl_core_buffer_copy(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->cap);
    out->len = source->len;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
static myl_block *core_buffer_grow(myl_block *buffer, int64_t needed) {
    if (needed <= buffer->cap) return buffer;
    int64_t capacity = buffer->cap < 8 ? 8 : buffer->cap;
    while (capacity < needed) {
        if (capacity > INT64_MAX / 2) { capacity = needed; break; }
        capacity *= 2;
    }
    myl_block *out = myl_core_buffer_new((uint64_t)capacity);
    out->len = buffer->len;
    memcpy(block_data(out), block_data(buffer), (size_t)buffer->len);
    block_free(buffer);
    return out;
}
myl_block *myl_core_buffer_push(myl_block *buffer, uint8_t value) {
    if (buffer->len == INT64_MAX) out_of_memory();
    buffer = core_buffer_grow(buffer, buffer->len + 1);
    block_data(buffer)[buffer->len++] = value;
    return buffer;
}
myl_block *myl_core_buffer_set(myl_block *buffer, uint64_t index, uint8_t value) {
    block_data(buffer)[index] = value;
    return buffer;
}
myl_block *myl_core_buffer_pop(myl_block *buffer) { --buffer->len; return buffer; }
uint64_t myl_core_buffer_capacity(myl_block *buffer) { return (uint64_t)buffer->cap; }
myl_block *myl_core_buffer_from_bytes(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->len);
    out->len = source->len;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
myl_block *myl_core_buffer_from_list(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->len);
    const int64_t *values = (const int64_t *)block_data(source);
    for (int64_t i = 0; i < source->len; ++i) block_data(out)[i] = (uint8_t)values[i];
    out->len = source->len;
    return out;
}
myl_block *myl_core_buffer_snapshot(myl_block *source) {
    myl_block *out = str_new(source->len);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
bool myl_core_buffer_range_valid(myl_block *source, int64_t start, int64_t end) {
    return start >= 0 && end >= start && end <= source->len;
}
bool myl_core_buffer_reserve_valid(myl_block *source, int64_t extra) {
    return extra >= 0 && extra <= INT64_MAX - source->len;
}
myl_block *myl_core_buffer_reserved(myl_block *source, int64_t extra) {
    myl_block *out = myl_core_buffer_copy(source);
    return core_buffer_grow(out, out->len + extra);
}
myl_block *myl_core_buffer_reverse(myl_block *source) {
    myl_block *out = myl_core_buffer_copy(source);
    for (int64_t i = 0; i < out->len / 2; ++i) {
        unsigned char c = block_data(out)[i];
        block_data(out)[i] = block_data(out)[out->len - 1 - i];
        block_data(out)[out->len - 1 - i] = c;
    }
    return out;
}
/* Port of myl_native_bytes_hex: two lowercase ASCII digits per octet. */
myl_block *myl_core_bytes_hex(myl_block *source) {
    static const unsigned char digits[] = "0123456789abcdef";
    if (source->len > INT64_MAX / 2) out_of_memory();
    myl_block *out = str_new(source->len * 2);
    out->kind |= 1u << 8;
    for (int64_t i = 0; i < source->len; ++i) {
        block_data(out)[i * 2] = digits[block_data(source)[i] >> 4];
        block_data(out)[i * 2 + 1] = digits[block_data(source)[i] & 15];
    }
    return out;
}
static int core_hex_digit(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}
bool myl_core_from_hex_valid(myl_block *source) {
    if (source->len % 2) return false;
    for (int64_t i = 0; i < source->len; ++i) if (core_hex_digit(block_data(source)[i]) < 0) return false;
    return true;
}
myl_block *myl_core_from_hex(myl_block *source) {
    myl_block *out = str_new(source->len / 2);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    for (int64_t i = 0; i < out->len; ++i) block_data(out)[i] = (unsigned char)(core_hex_digit(block_data(source)[i * 2]) * 16 + core_hex_digit(block_data(source)[i * 2 + 1]));
    return out;
}

/* S4 numeric append: one checked reserve and one fragment copy, no text block. */
myl_block *myl_core_buffer_append_spelled(myl_block *buffer, const unsigned char *bytes, size_t length) {
    if (length > (size_t)(INT64_MAX - buffer->len)) out_of_memory();
    buffer = core_buffer_grow(buffer, buffer->len + (int64_t)length);
    memcpy(block_data(buffer) + buffer->len, bytes, length);
    buffer->len += (int64_t)length;
    return buffer;
}
/* A buffer handed over to an append (an owned argument, `Signature.owned` bit 0): it is
   updated in place when it holds the only reference, else copied first and the caller's
   reference released. The builder emits these as one call between the read of a `mut`
   place's buffer and its write-back, so the ownership pass takes the field over. */
static myl_block *core_buffer_owned(myl_block *buffer) {
    if (buffer->count == 1) return buffer;
    myl_block *copy = myl_core_buffer_copy(buffer);
    myl_core_release(buffer);
    return copy;
}
/* `buffer.append_range(source, start, end)`: the octets `source[start:end]` when the range
   is valid, else nothing (the caller reports the validity it computed separately). */
myl_block *myl_core_buffer_append_checked(myl_block *buffer, myl_block *source, int64_t start, int64_t end) {
    if (start < 0 || end <= start || end > source->len) return buffer;
    buffer = core_buffer_owned(buffer);
    return myl_core_buffer_append_spelled(buffer, block_data(source) + start, (size_t)(end - start));
}
/* `buffer.append_byte(value)`: one octet when `value` is in 0..255, else nothing. */
myl_block *myl_core_buffer_push_checked(myl_block *buffer, int64_t value) {
    if (value < 0 || value > 255) return buffer;
    buffer = core_buffer_owned(buffer);
    return myl_core_buffer_push(buffer, (uint8_t)value);
}
myl_block *myl_core_buffer_append_i64(myl_block *buffer, int64_t value) {
    unsigned char bytes[20];
    bool negative = value < 0;
    uint64_t magnitude = negative ? -(uint64_t)value : (uint64_t)value;
    unsigned length = core_number_length(magnitude) + negative;
    core_number_write(bytes + length, magnitude);
    if (negative) bytes[0] = '-';
    return myl_core_buffer_append_spelled(buffer, bytes, length);
}
