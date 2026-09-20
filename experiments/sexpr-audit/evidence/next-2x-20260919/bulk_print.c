#include "native_print.h"
#include "native_text.h"
#include <stdlib.h>
#include <string.h>
/* Audit prototype: reserve once and encode raw top-level text into the sink. */
void audit_bulk_print_text(MylPrint *out, const void *value, unsigned depth) {
    if (depth) { myl_print_text(out, value, depth); return; }
    if (out->failed) return;
    myl_native_text *text;
    memcpy(&text, value, sizeof text);
    size_t count = myl_native_text_utf8(text, NULL, 0);
    if (!count) return;
    if (count == SIZE_MAX || count > SIZE_MAX - out->length) { out->failed = 1; return; }
    if (count > out->capacity - out->length) {
        size_t capacity = out->capacity ? out->capacity : 64;
        while (capacity - out->length < count) {
            if (capacity > SIZE_MAX / 2) { out->failed = 1; return; }
            capacity *= 2;
        }
        unsigned char *grown = realloc(out->bytes, capacity);
        if (!grown) { out->failed = 1; return; }
        out->bytes = grown;
        out->capacity = capacity;
    }
    myl_native_text_utf8(text, out->bytes + out->length, count);
    out->length += count;
}
