/* S3 port of native_bytes.c: octet algorithms adapted to the Core leaf header.
   kind 5 is mutable bytes, reserved=0; immutable snapshots own independent data. */

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
/* The buffer with room for `needed` octets, grown (the caller's old pointer is dead). Kept
   out of line, so the room test of `core_buffer_grow` inlines into every append. */
__attribute__((noinline)) static myl_block *core_buffer_regrow(myl_block *buffer, int64_t needed) {
    int64_t capacity = buffer->cap < 8 ? 8 : buffer->cap;
    while (capacity < needed) {
        if (capacity > INT64_MAX / 2) { capacity = needed; break; }
        capacity *= 2;
    }
    if (class_of(buffer) == 0) {
        /* A large buffer grows with `realloc`, like a large list: the C library remaps a
           large block instead of copying it, so neither its octets nor fresh pages are
           touched again; it moves to a fresh aligned block when `realloc` loses the
           alignment (NEW-CORE-U1-GROW-1). */
        size_t bytes = MYL_HEADER + block_data_size(capacity, 1, false);
        if (heap_ceiling) heap_refund(malloc_usable_size(buffer));
        myl_block *grown = realloc(buffer, bytes);
        if (!grown) out_of_memory();
        if (((uintptr_t)grown & (MYL_ALIGN - 1)) != 0) {
            myl_block *aligned = aligned_alloc(MYL_ALIGN, (bytes + MYL_ALIGN - 1) & ~(size_t)(MYL_ALIGN - 1));
            if (!aligned) out_of_memory();
            memcpy(aligned, grown, MYL_HEADER + (size_t)grown->len);
            free(grown);
            grown = aligned;
        }
        if (heap_ceiling) heap_charge(malloc_usable_size(grown));
        grown->cap = capacity;
        return grown;
    }
    myl_block *out = myl_core_buffer_new((uint64_t)capacity);
    out->len = buffer->len;
    memcpy(block_data(out), block_data(buffer), (size_t)buffer->len);
    block_free(buffer);
    return out;
}
static inline myl_block *core_buffer_grow(myl_block *buffer, int64_t needed) {
    return needed <= buffer->cap ? buffer : core_buffer_regrow(buffer, needed);
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
/* The octets `source[start:end]` of a buffer as a new buffer (FR27): the bounds clamp to the length and a reversed range is
   empty, as a bytes slice's do, and a negative bound traps. */
myl_block *myl_core_buffer_slice(myl_block *source, int64_t start, int64_t end) {
    if (start < 0) myl_core_negative_position(start, source->len, false);
    if (end < 0) myl_core_negative_position(end, source->len, false);
    if (start > source->len) start = source->len;
    if (end > source->len) end = source->len;
    int64_t count = end > start ? end - start : 0;
    myl_block *out = myl_core_buffer_new((uint64_t)count);
    out->len = count;
    memcpy(block_data(out), block_data(source) + start, (size_t)count);
    return out;
}
myl_block *myl_core_buffer_from_bytes(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->len);
    out->len = source->len;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
/* A buffer of the `count` integers at `values` (C9 lists): a list block or a list view, read in place. */
myl_block *myl_core_span_buffer_from_list(const int64_t *values, int64_t count) {
    myl_block *out = myl_core_buffer_new((uint64_t)count);
    for (int64_t i = 0; i < count; ++i) block_data(out)[i] = (uint8_t)values[i];
    out->len = count;
    return out;
}
myl_block *myl_core_buffer_from_list(myl_block *source) {
    return myl_core_span_buffer_from_list((const int64_t *)block_data(source), source->len);
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
/* The receiver is consumed (`writableReceiverOf` moved it out of its owner), so growing and
   reversing it in place is the same value as a copy that replaces it: no hidden copy. */
myl_block *myl_core_buffer_reserved(myl_block *source, int64_t extra) {
    if (!(extra >= 0 && extra <= INT64_MAX - source->len)) return source;
    return core_buffer_grow(source, source->len + extra);
}
/* `buffers.clear`: the octets go and the storage stays (len 0, cap unchanged). The receiver is consumed like the reverse's. */
myl_block *myl_core_buffer_clear(myl_block *source) {
    source->len = 0;
    return source;
}
myl_block *myl_core_buffer_reverse(myl_block *source) {
    for (int64_t i = 0; i < source->len / 2; ++i) {
        unsigned char c = block_data(source)[i];
        block_data(source)[i] = block_data(source)[source->len - 1 - i];
        block_data(source)[source->len - 1 - i] = c;
    }
    return source;
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
/* `bytes.sha256()` and `str.sha256()`: the 32 octets of the SHA-256 digest of the receiver's own octets (core_sha256.c). */
myl_block *myl_core_bytes_sha256(myl_block *source) {
    myl_block *out = myl_core_digest_new();
    core_sha256(block_data(source), (uint64_t)source->len, block_data(out));
    return out;
}
/* The span form of `myl_core_bytes_sha256`: a borrowed view's octets are hashed in place. */
myl_block *myl_core_span_bytes_sha256(const unsigned char *data, uint64_t length) {
    myl_block *out = myl_core_digest_new();
    core_sha256(data, length, block_data(out));
    return out;
}
static int core_hex_digit(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}
/* The span forms (C9 str): the source is its borrowed (data, length). */
bool myl_core_span_from_hex_valid(const unsigned char *data, uint64_t length) {
    if (length % 2) return false;
    for (uint64_t i = 0; i < length; ++i) if (core_hex_digit(data[i]) < 0) return false;
    return true;
}
myl_block *myl_core_span_from_hex(const unsigned char *data, uint64_t length) {
    myl_block *out = str_new((int64_t)(length / 2));
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    for (int64_t i = 0; i < out->len; ++i) block_data(out)[i] = (unsigned char)(core_hex_digit(data[i * 2]) * 16 + core_hex_digit(data[i * 2 + 1]));
    return out;
}
bool myl_core_from_hex_valid(myl_block *source) {
    return myl_core_span_from_hex_valid(block_data(source), (uint64_t)source->len);
}
myl_block *myl_core_from_hex(myl_block *source) {
    return myl_core_span_from_hex(block_data(source), (uint64_t)source->len);
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
    return buffer;
}
/* `buffer.append_range(source, start, end)`: negative endpoints trap; a valid
   nonnegative range appends its octets, otherwise nothing (the caller reports validity). */
myl_block *myl_core_buffer_append_checked(myl_block *buffer, myl_block *source, int64_t start, int64_t end) {
    if (start < 0) myl_core_negative_position(start, source->len, false);
    if (end < 0) myl_core_negative_position(end, source->len, false);
    if (end <= start || end > source->len) return buffer;
    buffer = core_buffer_owned(buffer);
    return myl_core_buffer_append_spelled(buffer, block_data(source) + start, (size_t)(end - start));
}
/* `buffer.append_array(array, start, end)`: the octets `start..end` of an inline array of `total`
   octets at `data`, copied in one step. Like `append_range`, a negative endpoint traps and any
   other range outside 0 <= start <= end <= total appends nothing. */
myl_block *myl_core_buffer_append_octets(myl_block *buffer, const unsigned char *data, int64_t total, int64_t start, int64_t end) {
    if (start < 0) myl_core_negative_position(start, total, false);
    if (end < 0) myl_core_negative_position(end, total, false);
    if (end <= start || end > total) return buffer;
    buffer = core_buffer_owned(buffer);
    return myl_core_buffer_append_spelled(buffer, data + start, (size_t)(end - start));
}
/* Synchronous immutable octets: the destination is the sole transferred owner. */
bool myl_core_span_buffer_range_valid(const unsigned char *data, uint64_t length, int64_t start, int64_t end) {
    (void)data;
    return start >= 0 && end >= start && (uint64_t)end <= length;
}
myl_block *myl_core_buffer_append_span_checked(myl_block *buffer, const unsigned char *data, uint64_t length, int64_t start, int64_t end) {
    if (start < 0) myl_core_negative_position(start, (int64_t)length, false);
    if (end < 0) myl_core_negative_position(end, (int64_t)length, false);
    if (end <= start || (uint64_t)end > length) return buffer;
    buffer = core_buffer_owned(buffer);
    return myl_core_buffer_append_spelled(buffer, data + start, (size_t)(end - start));
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

/* A synchronous borrowed octet reader; preserve the written index for bounds checks. */
uint64_t myl_core_span_bytes_index_offset(const unsigned char *data, uint64_t len, int64_t index) {
    (void)data;
    (void)len;
    return (uint64_t)index;
}
