/* Runtime support for generated scalar C. No bytecode decoder is linked. */
#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
typedef __int128 V;
typedef unsigned __int128 U;
/* Layout preflight guarantees widths in 1..127 and packed totals <=127.
   Unsigned shifts avoid signed overflow; signed scalar restoration is explicit. */
static U variant_mask(unsigned bits) { return (((U)1) << bits) - 1; }
static V variant_make(V payload, unsigned tag_bits, unsigned payload_bits, size_t tag) {
    return (V)((((U)payload & variant_mask(payload_bits)) << tag_bits) | (U)tag);
}
static V variant_payload(V value, unsigned tag_bits, unsigned payload_bits, int is_signed) {
    U payload = ((U)value >> tag_bits) & variant_mask(payload_bits);
    if (is_signed && (payload & ((U)1 << (payload_bits - 1))))
        return -(V)(((U)1 << payload_bits) - payload);
    return (V)payload;
}
typedef struct Aggregate Aggregate;
typedef struct { V number; Aggregate *object; } Slot;
struct Aggregate {
    size_t refs, count, tag;
    Aggregate *previous, *next, *pending;
    Slot fields[];
};
typedef struct { Slot *locals; size_t base, target, function, call_site, local_count; } Frame;
static Aggregate *objects;
static Slot *values;
static size_t nv, cv, nf, cf, site;
static Frame *frames;
static uint64_t steps, max_steps = 10000000, max_frames = 1024;
static const char *const *source_paths;
static const char *const *function_names;
static const size_t *source_lines, *source_columns;
static void cleanup(void) {
    while (nf) free(frames[--nf].locals);
    /* All heap objects are registered, including temporary and partial values.
       Emergency cleanup frees the registry directly without traversing edges. */
    while (objects) { Aggregate *next = objects->next; free(objects); objects = next; }
    free(frames); free(values);
    frames = NULL; values = NULL;
}
static void host_failure(const char *message) {
    fprintf(stderr, "mylang: host failure: %s\n", message);
    cleanup(); exit(2);
}
static void trap(const char *code) {
    fprintf(stderr, "%s:%zu:%zu: error[%s]\n", source_paths[site], source_lines[site], source_columns[site], code);
    size_t location = site, shown = 0;
    for (size_t i = nf; i && shown < 16; --i, ++shown) {
        Frame f = frames[i - 1];
        fprintf(stderr, "  at %s (%s:%zu:%zu)\n", function_names[f.function], source_paths[location], source_lines[location], source_columns[location]);
        location = f.call_site;
    }
    if (nf > shown) fprintf(stderr, "  ... %zu frames omitted\n", nf - shown);
    cleanup(); exit(1);
}
static void *grow(void *old, size_t *capacity, size_t needed, size_t size) {
    if (needed <= *capacity) return old;
    if (needed > SIZE_MAX / size) host_failure("OutOfMemory");
    size_t next = *capacity ? *capacity : 8;
    while (next < needed) {
        if (next > SIZE_MAX / 2) { next = needed; break; }
        next *= 2;
    }
    if (next > SIZE_MAX / size) next = needed;
    void *result = realloc(old, next * size);
    if (!result) host_failure("OutOfMemory");
    *capacity = next; return result;
}
static Slot copy_value(Slot value) {
    if (value.object) {
        if (value.object->refs == SIZE_MAX) host_failure("OutOfMemory");
        ++value.object->refs;
    }
    return value;
}
static void release_value(Slot value) {
    Aggregate *work = NULL;
    if (value.object && --value.object->refs == 0) work = value.object;
    while (work) {
        Aggregate *object = work;
        work = object->pending;
        for (size_t i = 0; i < object->count; ++i) {
            Aggregate *child = object->fields[i].object;
            if (child && --child->refs == 0) { child->pending = work; work = child; }
        }
        if (object->previous) object->previous->next = object->next;
        else objects = object->next;
        if (object->next) object->next->previous = object->previous;
        free(object);
    }
}
static Aggregate *new_object(size_t count, size_t tag) {
    if (count > (SIZE_MAX - sizeof(Aggregate)) / sizeof(Slot)) host_failure("OutOfMemory");
    Aggregate *object = calloc(1, sizeof(Aggregate) + count * sizeof(Slot));
    if (!object) host_failure("OutOfMemory");
    object->refs = 1; object->count = count; object->tag = tag;
    object->next = objects;
    if (objects) objects->previous = object;
    objects = object;
    return object;
}
static Slot clone_value(Slot value) {
    if (!value.object) host_failure("InternalError");
    Aggregate *object = new_object(value.object->count, value.object->tag);
    for (size_t i = 0; i < object->count; ++i) object->fields[i] = copy_value(value.object->fields[i]);
    return (Slot){0, object};
}
static void push_value(Slot value) {
    if (nv == SIZE_MAX) host_failure("OutOfMemory");
    values = grow(values, &cv, nv + 1, sizeof(Slot));
    values[nv++] = value;
}
static void push(V value) { push_value((Slot){value, NULL}); }
static Slot pop_value(void) {
    if (!nf || nv <= frames[nf - 1].base) host_failure("InternalError");
    return values[--nv];
}
static V pop(void) {
    Slot value = pop_value();
    if (value.object) host_failure("InternalError");
    return value.number;
}
static void clear_values(size_t base) {
    while (nv > base) release_value(values[--nv]);
}
static void store_local(size_t index, Slot value) {
    Slot *local = &frames[nf - 1].locals[index];
    release_value(*local); *local = value;
}
static void load_local(size_t index) { push_value(copy_value(frames[nf - 1].locals[index])); }
static void move_local(size_t index) {
    Slot *local = &frames[nf - 1].locals[index];
    Slot value = *local; *local = (Slot){0}; push_value(value);
}
static Slot field_value(Slot value, size_t index) {
    if (!value.object || index >= value.object->count) host_failure("InternalError");
    return copy_value(value.object->fields[index]);
}
static void get_field(size_t index) {
    Slot owner = pop_value(), value = field_value(owner, index);
    release_value(owner); push_value(value);
}
static void take_field(size_t index, size_t field) {
    Slot *local = &frames[nf - 1].locals[index];
    if (!local->object || field >= local->object->count) host_failure("InternalError");
    if (local->object->refs != 1) {
        Slot unique = clone_value(*local); release_value(*local); *local = unique;
    }
    Slot value = local->object->fields[field];
    local->object->fields[field] = (Slot){0};
    push_value(value);
}
static void make_record(size_t count, const size_t *order) {
    Aggregate *object = new_object(count, 0);
    size_t base = nv - count;
    for (size_t i = 0; i < count; ++i) object->fields[order ? order[i] : i] = values[base + i];
    nv = base; push_value((Slot){0, object});
}
static void update_record(size_t count, const size_t *indices) {
    size_t base = nv - count - 1;
    Slot updated = clone_value(values[base]);
    for (size_t i = 0; i < count; ++i) {
        release_value(updated.object->fields[indices[i]]);
        updated.object->fields[indices[i]] = values[base + 1 + i];
    }
    release_value(values[base]); nv = base; push_value(updated);
}
static size_t array_index(V index, Slot owner) {
    if (!owner.object) host_failure("InternalError");
    if (index < 0 || (U)index >= owner.object->count) trap("R_INDEX_BOUNDS");
    return (size_t)index;
}
static void get_index(void) {
    V index = pop(); Slot owner = pop_value();
    Slot value = field_value(owner, array_index(index, owner));
    release_value(owner); push_value(value);
}
static void replace_index(void) {
    size_t base = nv - 3;
    size_t index = array_index(values[base + 1].number, values[base]);
    Slot updated = clone_value(values[base]);
    release_value(updated.object->fields[index]);
    updated.object->fields[index] = values[base + 2];
    release_value(values[base]); nv = base; push_value(updated);
}
static void array_length(void) {
    Slot value = pop_value();
    if (!value.object) host_failure("InternalError");
    size_t count = value.object->count;
    release_value(value); push((V)count);
}
static Slot boxed_variant(size_t tag, Slot payload, int has_payload) {
    Aggregate *object = new_object(has_payload ? 1 : 0, tag);
    if (has_payload) object->fields[0] = payload;
    return (Slot){0, object};
}
static void enter(size_t function, size_t locals, size_t arguments, size_t target) {
    if (nf >= max_frames) trap("R_FRAME_LIMIT");
    if (arguments > nv || (nf && arguments > nv - frames[nf - 1].base)) host_failure("InternalError");
    if (nf == SIZE_MAX || locals > SIZE_MAX / sizeof(Slot)) host_failure("OutOfMemory");
    frames = grow(frames, &cf, nf + 1, sizeof(Frame));
    Slot *storage = calloc(locals ? locals : 1, sizeof(Slot));
    if (!storage) host_failure("OutOfMemory");
    size_t base = nv - arguments;
    for (size_t i = 0; i < arguments; ++i) storage[i] = values[base + i];
    frames[nf++] = (Frame){storage, base, target, function, site, locals};
    nv = base;
}
static size_t leave(Slot result) {
    Frame f = frames[--nf];
    for (size_t i = 0; i < f.local_count; ++i) release_value(f.locals[i]);
    free(f.locals); clear_values(f.base);
    push_value(result); return f.target;
}
static void tick(size_t location) {
    site = location;
    if (steps == max_steps) trap("R_STEP_LIMIT");
    ++steps;
}
static V checked(V value, V minimum, V maximum) {
    if (value < minimum || value > maximum) trap("R_OVERFLOW");
    return value;
}
static V arithmetic(int operation, V a, V b, V minimum, V maximum) {
    V result = 0;
    int overflow = 0;
    switch (operation) {
        case 0: overflow = __builtin_add_overflow(a, b, &result); break;
        case 1: overflow = __builtin_sub_overflow(a, b, &result); break;
        case 2: overflow = __builtin_mul_overflow(a, b, &result); break;
        case 3: if (!b) trap("R_DIVISION_BY_ZERO"); result = a / b; break;
        case 4: if (!b) trap("R_DIVISION_BY_ZERO"); result = a % b; break;
        default: host_failure("InternalError");
    }
    if (overflow) trap("R_OVERFLOW");
    return checked(result, minimum, maximum);
}
static uint64_t budget(const char *text) {
    uint64_t result = 0;
    if (!*text) host_failure("InvalidBudget");
    for (; *text; ++text) {
        if (*text < '0' || *text > '9' || result > (UINT64_MAX - (unsigned)(*text - '0')) / 10) host_failure("InvalidBudget");
        result = result * 10 + (unsigned)(*text - '0');
    }
    if (!result) host_failure("InvalidBudget");
    return result;
}
static void options(int argc, char **argv) {
    int saw_steps = 0, saw_frames = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strncmp(argv[i], "--max-steps=", 12) && !saw_steps++) max_steps = budget(argv[i] + 12);
        else if (!strncmp(argv[i], "--max-frames=", 13) && !saw_frames++) max_frames = budget(argv[i] + 13);
        else host_failure("InvalidBudget");
    }
}
