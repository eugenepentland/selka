/* Python-style rendering of native values, byte-identical to src/io_render.zig.
   A float renders positionally, so its frame must hold the longest finite
   double: a sign, `0.`, the 323 zeros before the smallest subnormal's digit and
   up to 17 significant digits, or the 309 integer digits of the largest double.
   Both renderers use the same frame, so no finite value is ever unprintable. */
#include "native_print.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define FLOAT_FRAME 352u
/* Make room for `length` more bytes, doubling the buffer until they fit. A line
   that cannot grow is marked failed and keeps the bytes it already holds. */
static int reserve(MylPrint *out, size_t length) {
    if (length > SIZE_MAX - out->length) { out->failed = 1; return 0; }
    if (length <= out->capacity - out->length) return 1;
    size_t capacity = out->capacity ? out->capacity : 64;
    while (capacity - out->length < length) {
        if (capacity > SIZE_MAX / 2) { out->failed = 1; return 0; }
        capacity *= 2;
    }
    unsigned char *grown = realloc(out->bytes, capacity);
    if (!grown) { out->failed = 1; return 0; }
    out->bytes = grown;
    out->capacity = capacity;
    return 1;
}
void myl_print_raw(MylPrint *out, const void *bytes, size_t length) {
    if (out->failed || !length) return;
    if (!reserve(out, length)) return;
    memcpy(out->bytes + out->length, bytes, length);
    out->length += length;
}
static void literal(MylPrint *out, const char *text) { myl_print_raw(out, text, strlen(text)); }
static void byte(MylPrint *out, unsigned char value) { myl_print_raw(out, &value, 1); }
int myl_print_deep(MylPrint *out, unsigned depth) {
    if (depth <= MYL_PRINT_MAX_DEPTH) return 0;
    literal(out, "...");
    return 1;
}
void myl_print_integer(MylPrint *out, const void *value, unsigned depth, unsigned width, int is_signed) {
    if (myl_print_deep(out, depth)) return;
    uint64_t bits = 0;
    memcpy(&bits, value, width);
    uint64_t mask = width >= 8 ? UINT64_MAX : (UINT64_C(1) << (width * 8)) - 1;
    bits &= mask;
    char buffer[24];
    int length;
    if (is_signed) {
        if (width < 8 && (bits >> (width * 8 - 1)) & 1) bits |= ~mask;
        int64_t signed_value;
        memcpy(&signed_value, &bits, 8);
        length = snprintf(buffer, sizeof buffer, "%lld", (long long)signed_value);
    } else length = snprintf(buffer, sizeof buffer, "%llu", (unsigned long long)bits);
    if (length > 0) myl_print_raw(out, buffer, (size_t)length);
}
void myl_print_bool(MylPrint *out, const void *value, unsigned depth) {
    if (myl_print_deep(out, depth)) return;
    unsigned char flag = 0;
    memcpy(&flag, value, 1);
    literal(out, flag ? "True" : "False");
}
void myl_print_unprintable(MylPrint *out, const void *value, unsigned depth) {
    (void)value;
    (void)depth;
    out->unprintable = 1;
}
void myl_print_unit(MylPrint *out, const void *value, unsigned depth) {
    (void)value;
    if (myl_print_deep(out, depth)) return;
    literal(out, "None");
}
/* Shortest round-tripping digits, then plain decimal notation without an
   exponent, matching the VM's `{d}` float rendering. */
static size_t shortest(double number, char *digits, int *exponent) {
    char buffer[40];
    for (int precision = 1; precision <= 17; ++precision) {
        snprintf(buffer, sizeof buffer, "%.*e", precision - 1, number);
        if (strtod(buffer, NULL) != number && precision != 17) continue;
        const char *marker = strchr(buffer, 'e');
        if (!marker) return 0;
        *exponent = atoi(marker + 1);
        size_t count = 0;
        for (const char *cursor = buffer; cursor < marker; ++cursor)
            if (*cursor >= '0' && *cursor <= '9') digits[count++] = *cursor;
        return count;
    }
    return 0;
}
static size_t decimal(double number, char *frame, size_t capacity) {
    char digits[20];
    int exponent = 0;
    size_t count = shortest(fabs(number), digits, &exponent), at = 0;
    if (!count) return capacity + 1;
    if (signbit(number) && at < capacity) frame[at++] = '-';
    if (exponent < 0) {
        if (at < capacity) frame[at++] = '0';
        if (at < capacity) frame[at++] = '.';
        for (int i = 0; i < -exponent - 1; ++i)
            if (at < capacity) frame[at++] = '0'; else return capacity + 1;
    }
    for (size_t i = 0; i < count; ++i) {
        if (exponent >= 0 && i == (size_t)exponent + 1 && at < capacity) frame[at++] = '.';
        if (at >= capacity) return capacity + 1;
        frame[at++] = digits[i];
    }
    for (size_t i = count; exponent >= 0 && i <= (size_t)exponent; ++i)
        if (at < capacity) frame[at++] = '0'; else return capacity + 1;
    return at > capacity ? capacity + 1 : at;
}
void myl_print_float(MylPrint *out, const void *value, unsigned depth) {
    if (myl_print_deep(out, depth)) return;
    double number;
    memcpy(&number, value, sizeof number);
    if (isnan(number)) { literal(out, "nan"); return; }
    if (isinf(number)) { literal(out, number < 0 ? "-inf" : "inf"); return; }
    char frame[FLOAT_FRAME];
    size_t length = decimal(number, frame, sizeof frame);
    if (length > sizeof frame) { out->unprintable = 1; return; }
    myl_print_raw(out, frame, length);
    if (!memchr(frame, '.', length)) literal(out, ".0");
}
static int escaped(uint32_t scalar) {
    if (scalar == '\n') return 'n';
    if (scalar == '\r') return 'r';
    if (scalar == '\t') return 't';
    return 0;
}
void myl_print_text(MylPrint *out, const void *value, unsigned depth) {
    if (myl_print_deep(out, depth)) return;
    myl_native_text *text;
    memcpy(&text, value, sizeof text);
    const unsigned char *payload = myl_native_text_storage(text);
    if (!depth) {
        /* Raw top-level text needs no quoting or escaping, so the whole payload
           is copied straight into the line buffer: one sizing read, one reserve
           and one fill, instead of a call, a capacity test and a branch per
           scalar. */
        if (out->failed) return;
        if (!text->bytes || !reserve(out, text->bytes)) return;
        memcpy(out->bytes + out->length, payload, text->bytes);
        out->length += text->bytes;
        return;
    }
    byte(out, '\'');
    /* Only an ASCII octet can need quoting or escaping: the octets of a
       non-ASCII scalar are all at or above 0x80, so copying them through
       reproduces exactly what encoding the scalar wrote. */
    for (size_t i = 0; i < text->bytes; ++i) {
        unsigned char octet = payload[i];
        if (octet == '\'' || octet == '\\') byte(out, '\\');
        if (escaped(octet)) {
            byte(out, '\\');
            byte(out, (unsigned char)escaped(octet));
            continue;
        }
        byte(out, octet);
    }
    byte(out, '\'');
}
void myl_print_bytes(MylPrint *out, const void *value, unsigned depth) {
    if (myl_print_deep(out, depth)) return;
    myl_native_list *raw;
    memcpy(&raw, value, sizeof raw);
    literal(out, "b'");
    const unsigned char *octets = raw->storage;
    for (size_t i = 0; i < raw->length; ++i) {
        unsigned char octet = octets[i];
        if (octet == '\'' || octet == '\\') { byte(out, '\\'); byte(out, octet); }
        else if (escaped(octet)) { byte(out, '\\'); byte(out, (unsigned char)escaped(octet)); }
        else if (octet >= 0x20 && octet < 0x7f) byte(out, octet);
        else {
            char frame[5];
            snprintf(frame, sizeof frame, "\\x%02x", octet);
            myl_print_raw(out, frame, 4);
        }
    }
    byte(out, '\'');
}
void myl_print_list(MylPrint *out, const void *value, unsigned depth, MylPrintFn element) {
    if (myl_print_deep(out, depth)) return;
    myl_native_list *list;
    memcpy(&list, value, sizeof list);
    byte(out, '[');
    for (size_t i = 0; i < list->length; ++i) {
        if (i) literal(out, ", ");
        element(out, (const unsigned char *)list->storage + i * list->element->size, depth + 1);
    }
    byte(out, ']');
}
void myl_print_dictionary(MylPrint *out, const void *value, unsigned depth, MylPrintFn key, MylPrintFn item) {
    if (myl_print_deep(out, depth)) return;
    myl_native_dictionary *dict;
    memcpy(&dict, value, sizeof dict);
    byte(out, '{');
    for (size_t i = 0; i < dict->entries->length; ++i) {
        const unsigned char *entry = (const unsigned char *)dict->entries->storage + i * dict->entry_type.size;
        if (i) literal(out, ", ");
        key(out, entry, depth + 1);
        literal(out, ": ");
        item(out, entry + dict->value_offset, depth + 1);
    }
    byte(out, '}');
}

void myl_print_array(MylPrint *out, const void *value, unsigned depth, size_t count, size_t stride, MylPrintFn element) {
    if (myl_print_deep(out, depth)) return;
    byte(out, '[');
    for (size_t i = 0; i < count; ++i) {
        if (i) literal(out, ", ");
        element(out, (const unsigned char *)value + i * stride, depth + 1);
    }
    byte(out, ']');
}
void myl_print_record(MylPrint *out, const void *value, unsigned depth, const char *name, const MylPrintField *fields, size_t count) {
    if (myl_print_deep(out, depth)) return;
    literal(out, name);
    byte(out, '(');
    for (size_t i = 0; i < count; ++i) {
        if (i) literal(out, ", ");
        literal(out, fields[i].name);
        byte(out, '=');
        fields[i].render(out, (const unsigned char *)value + fields[i].offset, depth + 1);
    }
    byte(out, ')');
}
void myl_print_class(MylPrint *out, const void *slot, unsigned depth, const char *name, const MylPrintField *fields, size_t count) {
    const void *body;
    memcpy(&body, slot, sizeof body);
    myl_print_record(out, body, depth, name, fields, count);
}
void myl_print_domain(MylPrint *out, const void *value, unsigned depth, const char *name, MylPrintFn inner) {
    if (myl_print_deep(out, depth)) return;
    literal(out, name);
    byte(out, '(');
    inner(out, value, depth + 1);
    byte(out, ')');
}
void myl_print_variant(MylPrint *out, const void *value, unsigned depth, const MylPrintField *cases, size_t count) {
    if (myl_print_deep(out, depth)) return;
    uint32_t tag = 0;
    memcpy(&tag, value, sizeof tag);
    for (size_t i = 0; i < count; ++i) {
        if (cases[i].tag != tag) continue;
        literal(out, cases[i].name);
        if (!cases[i].render) return;
        byte(out, '(');
        cases[i].render(out, (const unsigned char *)value + cases[i].offset, depth + 1);
        byte(out, ')');
        return;
    }
    literal(out, "...");
}
