/* The Python file surface for the native backend, mirroring
   src/file_resources.zig: every operation goes through the injected filesystem
   resource provider, so no ambient authority exists here. */
#include "qbe_files.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define PATH_LIMIT 4094u
static const myl_native_type pointer_type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
void myl_qbe_fail_file(void *context) { myl_qbe_fail(context, "R_FILE"); }
/* Readable explanation of a provider status, used in `Result` error text. */
static const char *reason(int status) {
    if (status == 1) return "no filesystem authority is available";
    if (status == 2) return "denied: outside the granted directories, or the mode needs a write grant";
    if (status == 4) return "too many files are open";
    if (status == 5) return "the bytes read are not valid UTF-8 text";
    return "failed: the path does not exist or could not be used";
}
static const char *verb_of(unsigned kind) {
    switch (kind) {
        case MYL_FILE_OPEN: return "open";
        case MYL_FILE_READ_FILE: case MYL_FILE_READ_TEXT: return "read";
        case MYL_FILE_WRITE_FILE: case MYL_FILE_WRITE_TEXT: return "write";
        case MYL_FILE_EXISTS: return "stat";
        case MYL_FILE_LISTDIR: return "listdir";
        case MYL_FILE_MKDIR: return "mkdir";
        default: return "remove";
    }
}
static unsigned char letter_of(unsigned kind, unsigned mode) {
    switch (kind) {
        case MYL_FILE_OPEN: return (unsigned char)mode;
        case MYL_FILE_READ_FILE: case MYL_FILE_READ_TEXT: return 'r';
        case MYL_FILE_WRITE_FILE: case MYL_FILE_WRITE_TEXT: return 'w';
        case MYL_FILE_EXISTS: return 'm';
        case MYL_FILE_LISTDIR: return 'l';
        case MYL_FILE_MKDIR: return 'k';
        default: return 'x';
    }
}
/* One caller-owned host copy of a managed text or byte string. */
typedef struct { unsigned char *bytes; size_t length; int failed; } Owned;
static Owned borrow(const void *value, int text) {
    Owned owned = {NULL, 0, 0};
    if (!value) return owned;
    if (!text) {
        const myl_native_bytes *raw = value;
        owned.length = raw->length;
        owned.bytes = malloc(owned.length ? owned.length : 1);
        if (!owned.bytes) { owned.failed = 1; return owned; }
        if (owned.length) memcpy(owned.bytes, raw->storage, owned.length);
        return owned;
    }
    const myl_native_text *input = value;
    owned.length = myl_native_text_utf8(input, NULL, 0);
    if (owned.length == SIZE_MAX) { owned.failed = 1; return owned; }
    owned.bytes = malloc(owned.length ? owned.length : 1);
    if (!owned.bytes) { owned.failed = 1; return owned; }
    myl_native_text_utf8(input, owned.bytes, owned.length);
    return owned;
}
/* Build the managed error text `verb 'path': reason`. */
static myl_native_text *failure_text(void *context, unsigned kind, Owned path, int status) {
    const char *verb = verb_of(kind), *why = reason(status);
    size_t length = strlen(verb) + strlen(why) + path.length + 5;
    char *message = malloc(length + 1);
    if (!message) { myl_qbe_fail_allocation(context); return NULL; }
    size_t at = (size_t)snprintf(message, length + 1, "%s '", verb);
    memcpy(message + at, path.bytes, path.length);
    at += path.length;
    at += (size_t)snprintf(message + at, length + 1 - at, "': %s", why);
    myl_native_text *text = myl_native_text_from_utf8(myl_qbe_heap(context), (const unsigned char *)message, at);
    free(message);
    if (!text) myl_qbe_fail_allocation(context);
    return text;
}
/* Acquire one resource, spelling `w` as exclusive create then truncate. */
static int acquire(void *context, uint64_t authority, unsigned char mode, Owned path, myl_native_resource **owner) {
    if (path.length > PATH_LIMIT) return 2;
    unsigned char frame[PATH_LIMIT + 2];
    frame[1] = ':';
    if (path.length) memcpy(frame + 2, path.bytes, path.length);
    if (mode != 'w') {
        frame[0] = mode;
        return myl_qbe_resource_new(context, authority, 0, frame, path.length + 2, owner);
    }
    frame[0] = 'c';
    int status = myl_qbe_resource_new(context, authority, 0, frame, path.length + 2, owner);
    if (status <= 0) return status;
    frame[0] = 't';
    return myl_qbe_resource_new(context, authority, 0, frame, path.length + 2, owner);
}
/* Read a whole resource into caller-owned bytes, honouring the size ceiling. */
static int read_all(void *context, myl_native_resource *owner, size_t limit, Owned *out) {
    unsigned char chunk[16 * 1024];
    size_t capacity = 0;
    out->bytes = NULL;
    out->length = 0;
    while (out->length < limit) {
        size_t wanted = sizeof chunk < limit - out->length ? sizeof chunk : limit - out->length;
        size_t width = 0;
        int eof = 0;
        int status = myl_qbe_resource_read(context, owner, chunk, wanted, &width, &eof);
        if (status) { free(out->bytes); out->bytes = NULL; return status; }
        if (out->length + width > MYL_FILE_MAX_BYTES) { free(out->bytes); out->bytes = NULL; return 2; }
        if (width) {
            if (out->length + width > capacity) {
                size_t grown = capacity ? capacity * 2 : 16 * 1024;
                while (grown < out->length + width) grown *= 2;
                unsigned char *bytes = realloc(out->bytes, grown);
                if (!bytes) { free(out->bytes); out->bytes = NULL; myl_qbe_fail_allocation(context); return -1; }
                out->bytes = bytes;
                capacity = grown;
            }
            memcpy(out->bytes + out->length, chunk, width);
            out->length += width;
        }
        if (eof || !width) break;
    }
    return 0;
}
/* Read up to one line, keeping its terminator, without provider pushback. */
static int read_line(void *context, myl_native_resource *owner, Owned *out) {
    size_t capacity = 0;
    out->bytes = NULL;
    out->length = 0;
    while (out->length < MYL_FILE_MAX_BYTES) {
        unsigned char octet = 0;
        size_t width = 0;
        int eof = 0;
        int status = myl_qbe_resource_read(context, owner, &octet, 1, &width, &eof);
        if (status) { free(out->bytes); out->bytes = NULL; return status; }
        if (!width) break;
        if (out->length == capacity) {
            size_t grown = capacity ? capacity * 2 : 128;
            unsigned char *bytes = realloc(out->bytes, grown);
            if (!bytes) { free(out->bytes); out->bytes = NULL; myl_qbe_fail_allocation(context); return -1; }
            out->bytes = bytes;
            capacity = grown;
        }
        out->bytes[out->length++] = octet;
        if (octet == '\n' || eof) break;
    }
    return 0;
}
/* Write every byte, looping over the provider's reported partial progress. */
static int write_all(void *context, myl_native_resource *owner, Owned input, size_t *written) {
    *written = 0;
    while (*written < input.length) {
        size_t width = 0;
        int status = myl_qbe_resource_write(context, owner, input.bytes + *written, input.length - *written, &width);
        if (status) return status;
        if (!width) return 3;
        *written += width;
    }
    return 0;
}
static void *sequence(void *context, const unsigned char *bytes, size_t length, int text, int *status) {
    myl_native_heap *heap = myl_qbe_heap(context);
    if (!text) {
        myl_native_bytes *value = myl_native_bytes_new(heap, bytes, length);
        if (!value) *status = -1;
        return value;
    }
    if (!myl_native_text_valid_utf8(bytes, length)) { *status = 5; return NULL; }
    myl_native_text *value = myl_native_text_from_utf8(heap, bytes, length);
    if (!value) *status = -1;
    return value;
}
/* Decode one `l:` directory snapshot into a managed list of entry names. */
static myl_native_list *listing(void *context, Owned raw, int *status) {
    myl_native_heap *heap = myl_qbe_heap(context);
    myl_native_list *list = myl_native_list_new(heap, &pointer_type, 0);
    if (!list) { *status = -1; return NULL; }
    if (!raw.length || raw.bytes[0] != 1) *status = -2;
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    size_t cursor = 1;
    while (!*status && cursor + 3 <= raw.length) {
        size_t width = (size_t)raw.bytes[cursor + 1] | ((size_t)raw.bytes[cursor + 2] << 8);
        cursor += 3;
        if (cursor + width > raw.length) { *status = -2; break; }
        myl_native_text *name = myl_native_text_from_utf8(heap, raw.bytes + cursor, width);
        int appended = name && myl_native_list_append(heap, list, &name);
        if (myl_rc_enabled(heap)) {
            if (appended) myl_rc_owner_release(heap, name);
            else myl_rc_construction_abort(heap, name);
        }
        if (!appended) { *status = -1; break; }
        cursor += width;
    }
    myl_native_root_pop(heap, &root);
    if (*status) {
        if (myl_rc_enabled(heap)) myl_rc_construction_abort(heap, list);
        return NULL;
    }
    return list;
}
/* Split a whole read into lines, keeping each terminator. */
static myl_native_list *lines(void *context, Owned raw, int text, int *status) {
    myl_native_heap *heap = myl_qbe_heap(context);
    myl_native_list *list = myl_native_list_new(heap, &pointer_type, 0);
    if (!list) { *status = -1; return NULL; }
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    size_t start = 0;
    while (start < raw.length) {
        const unsigned char *found = memchr(raw.bytes + start, '\n', raw.length - start);
        size_t end = found ? (size_t)(found - raw.bytes) + 1 : raw.length;
        void *line = sequence(context, raw.bytes + start, end - start, text, status);
        int appended = line && myl_native_list_append(heap, list, &line);
        if (myl_rc_enabled(heap)) {
            if (appended) myl_rc_owner_release(heap, line);
            else myl_rc_construction_abort(heap, line);
        }
        if (!appended) { if (!*status) *status = -1; break; }
        start = end;
    }
    myl_native_root_pop(heap, &root);
    if (*status) {
        if (myl_rc_enabled(heap)) myl_rc_construction_abort(heap, list);
        return NULL;
    }
    return list;
}
/* Run the body of one whole-path helper against an acquired resource. */
static int finish(void *context, myl_native_resource *owner, unsigned request, Owned input, uint64_t *value) {
    unsigned kind = request & 0xff;
    int text = (request >> 16) & 1;
    int status = 0;
    Owned raw = {NULL, 0, 0};
    if (kind == MYL_FILE_WRITE_FILE || kind == MYL_FILE_WRITE_TEXT) {
        size_t written = 0;
        status = write_all(context, owner, input, &written);
        *value = 0;
        return status;
    }
    if (kind == MYL_FILE_EXISTS || kind == MYL_FILE_MKDIR || kind == MYL_FILE_REMOVE) {
        *value = 0;
        return 0;
    }
    status = read_all(context, owner, MYL_FILE_MAX_BYTES, &raw);
    if (status) return status;
    void *payload = kind == MYL_FILE_LISTDIR ? (void *)listing(context, raw, &status) : sequence(context, raw.bytes, raw.length, text, &status);
    free(raw.bytes);
    if (!payload) return myl_qbe_failed(context) ? -1 : status;
    *value = (uint64_t)(uintptr_t)payload;
    return 0;
}
int myl_qbe_file_access(void *context, uint64_t authority, unsigned request, myl_native_text *path, const void *input, uint64_t *value) {
    unsigned kind = request & 0xff;
    *value = 0;
    /* Only a write helper consumes a payload, and the request's text bit says
       whether that payload arrived as text or as octets. `open` alone receives a
       nonempty operand here without consuming it — its mode spelling, whose
       text-ness is the handle's, never the operand's — so borrowing it would
       describe the wrong value. */
    Owned spelling = borrow(path, 1);
    Owned payload = {NULL, 0, 0};
    if (kind == MYL_FILE_WRITE_FILE || kind == MYL_FILE_WRITE_TEXT) payload = borrow(input, (request >> 16) & 1);
    int status = 0;
    if (spelling.failed || payload.failed) { myl_qbe_fail_allocation(context); status = -1; }
    myl_native_resource *owner = NULL;
    if (!status) status = acquire(context, authority, letter_of(kind, (request >> 8) & 0xff), spelling, &owner);
    /* A helper opens, uses and closes its resource within the call, so a failure
       leaves no handle behind; `open` hands its live handle to the guest. */
    if (!status && kind == MYL_FILE_OPEN) *value = (uint64_t)(uintptr_t)owner;
    if (!status && kind != MYL_FILE_OPEN) {
        status = finish(context, owner, request, payload, value);
        int completion = myl_qbe_resource_complete(context, owner);
        if (!status && completion < 0) status = -1;
    }
    free(payload.bytes);
    if (status < 0 || myl_qbe_failed(context)) {
        free(spelling.bytes);
        if (!myl_qbe_failed(context)) {
            if (status == -2) myl_qbe_fail(context, "InvalidProvider");
            else myl_qbe_fail_allocation(context);
        }
        return -1;
    }
    if (kind == MYL_FILE_EXISTS) {
        *value = status == 0;
        free(spelling.bytes);
        return 0;
    }
    if (!status) { free(spelling.bytes); return 0; }
    myl_native_text *message = failure_text(context, kind, spelling, status);
    free(spelling.bytes);
    if (!message) return -1;
    *value = (uint64_t)(uintptr_t)message;
    return 1;
}
int myl_qbe_file_method(void *context, void *owner, unsigned request, int64_t count, const void *input, uint64_t *value) {
    unsigned kind = request & 0xff;
    int text = (request >> 16) & 1;
    *value = 0;
    if (!owner) { myl_qbe_fail_file(context); return -1; }
    if (kind == MYL_FILE_FLUSH) return 0;
    if (kind == MYL_FILE_CLOSE) {
        if (myl_qbe_resource_complete(context, owner)) { if (!myl_qbe_failed(context)) myl_qbe_fail_file(context); return -1; }
        return 0;
    }
    if (kind == MYL_FILE_WRITE) {
        Owned bytes = borrow(input, text);
        size_t written = 0;
        int status = bytes.failed ? -1 : write_all(context, owner, bytes, &written);
        free(bytes.bytes);
        if (status) { if (!myl_qbe_failed(context)) myl_qbe_fail_file(context); return -1; }
        *value = (uint64_t)written;
        return 0;
    }
    Owned raw = {NULL, 0, 0};
    /* Python spells "read everything" as a negative count. */
    size_t limit = kind == MYL_FILE_READ && count >= 0 ? (size_t)count : MYL_FILE_MAX_BYTES;
    int status = kind == MYL_FILE_READLINE ? read_line(context, owner, &raw) : read_all(context, owner, limit, &raw);
    if (status) { if (!myl_qbe_failed(context)) myl_qbe_fail_file(context); return -1; }
    void *payload = kind == MYL_FILE_READLINES ? (void *)lines(context, raw, text, &status) : sequence(context, raw.bytes, raw.length, text, &status);
    free(raw.bytes);
    if (!payload) {
        if (!myl_qbe_failed(context)) {
            if (status < 0) myl_qbe_fail_allocation(context);
            else myl_qbe_fail_file(context);
        }
        return -1;
    }
    *value = (uint64_t)(uintptr_t)payload;
    return 0;
}
