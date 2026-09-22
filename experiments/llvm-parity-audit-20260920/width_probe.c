/* Diagnostic substitutes for three guest width helpers in the frozen arena arm.
 * These preserve valid-input width results, not allocation-failure accounting.
 * No production ABI or runtime source is changed. Names come from the manifest. */
#include "native_bytes.h"
#include <stdint.h>

typedef struct { myl_native_bytes *source; int64_t start, end; } AuditView;
_Static_assert(sizeof(AuditView) == 24, "frozen guest View layout");

static size_t endpoint(size_t length, int64_t value) {
    if (value >= 0) return (uint64_t)value > length ? length : (size_t)value;
    uint64_t distance = (uint64_t)(-(value + 1)) + 1;
    return distance > length ? 0 : length - (size_t)distance;
}

int64_t AUDIT_SCALAR_NAME(uint64_t context, uint64_t address) {
    (void)context;
    const AuditView *view = (const AuditView *)(uintptr_t)address;
    size_t first = endpoint(view->source->length, view->start);
    size_t last = endpoint(view->source->length, view->end);
    size_t count = last > first ? last - first : 0;
    const unsigned char *bytes = view->source->storage;
    if (count) bytes += first;
    int status = MYL_BYTES_OK;
    int64_t width = myl_native_bytes_scalar_count_range(bytes, count, &status);
    return status == MYL_BYTES_OK ? width : 0;
}

int64_t AUDIT_LITERAL_NAME(uint64_t context, uint64_t address) {
    int64_t count = AUDIT_SCALAR_NAME(context, address);
    return count ? count : 12;
}

int64_t AUDIT_INT_NAME(uint64_t context, int64_t value) {
    (void)context;
    uint64_t magnitude = value < 0 ? (uint64_t)(-(value + 1)) + 1 : (uint64_t)value;
    int64_t width = 1 + (value < 0);
    while (magnitude >= 10) { magnitude /= 10; ++width; }
    return width;
}
