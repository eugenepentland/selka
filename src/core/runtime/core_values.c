/* Core aggregate adapters; comparisons use UTF-8's order-preserving octets. */
#include <inttypes.h>
int64_t myl_core_octets_compare(const myl_block *a, const myl_block *b) {
    size_t n = (size_t)(a->len < b->len ? a->len : b->len);
    int order = memcmp((const unsigned char *)a + SELKA_HEADER, (const unsigned char *)b + SELKA_HEADER, n);
    return order ? (order > 0 ? 1 : -1) : (a->len > b->len) - (a->len < b->len);
}

myl_block *myl_core_octets_repeat_unsigned(const myl_block *source, uint64_t count) {
    if (source->len && count > (uint64_t)INT64_MAX / (uint64_t)source->len) out_of_memory();
    size_t n = (size_t)((uint64_t)source->len * count);
    myl_block *result = block_new(SELKA_KIND_STR, (int64_t)n + 1, 1);
    result->len = (int64_t)n;
    unsigned char *data = block_data(result);
    for (size_t at = 0; at < n; at += (size_t)source->len) memcpy(data + at, (const unsigned char *)source + SELKA_HEADER, (size_t)source->len);
    data[n] = 0;
    return result;
}

myl_block *myl_core_octets_repeat_signed(const myl_block *source, int64_t count) {
    return myl_core_octets_repeat_unsigned(source, count > 0 ? (uint64_t)count : 0);
}

/* Descriptor graph is generated per concrete type. Tags precede payload reads,
 * padding never participates and boxes/list elements are traversed iteratively. */
typedef struct core_value_shape core_value_shape;
struct core_value_shape {
    uint32_t kind, size, count, aux;
    const core_value_shape *const *children;
    const uint32_t *offsets;
    const char *const *names;
};
typedef struct { const core_value_shape *shape; const void *left, *right; uint64_t hash; } core_value_memo_entry;
typedef struct { core_value_memo_entry *entries; size_t count, capacity; } core_value_memo;

static uint64_t value_mix(uint64_t bits) { return bits * UINT64_C(0x9e3779b97f4a7c15); }
static size_t value_memo_slot(const core_value_shape *shape, const void *left, const void *right, size_t capacity) {
    return (size_t)(value_mix((uintptr_t)shape) ^ value_mix((uintptr_t)left) ^ value_mix((uintptr_t)right >> 3)) & (capacity - 1);
}
static void value_memo_grow(core_value_memo *memo) {
    size_t capacity = memo->capacity ? memo->capacity * 2 : 64;
    if (capacity < memo->capacity || capacity > SIZE_MAX / sizeof *memo->entries) out_of_memory();
    core_value_memo_entry *entries = calloc(capacity, sizeof *entries);
    if (!entries) out_of_memory();
    for (size_t i = 0; i < memo->capacity; ++i) {
        core_value_memo_entry entry = memo->entries[i];
        if (!entry.shape) continue;
        size_t slot = value_memo_slot(entry.shape, entry.left, entry.right, capacity);
        while (entries[slot].shape) slot = (slot + 1) & (capacity - 1);
        entries[slot] = entry;
    }
    free(memo->entries);
    memo->entries = entries;
    memo->capacity = capacity;
}
static core_value_memo_entry *value_memo(core_value_memo *memo, const core_value_shape *shape, const void *left, const void *right, bool insert) {
    if (!memo->capacity || (insert && memo->count >= memo->capacity / 2)) value_memo_grow(memo);
    size_t slot = value_memo_slot(shape, left, right, memo->capacity);
    while (memo->entries[slot].shape) {
        core_value_memo_entry *entry = &memo->entries[slot];
        if (entry->shape == shape && entry->left == left && entry->right == right) return entry;
        slot = (slot + 1) & (memo->capacity - 1);
    }
    if (!insert) return NULL;
    ++memo->count;
    memo->entries[slot] = (core_value_memo_entry){shape, left, right, 0};
    return &memo->entries[slot];
}
static const myl_block *value_block(const void *at) {
    const myl_block *block;
    memcpy(&block, at, sizeof block);
    return block;
}
static uint64_t value_tag(const core_value_shape *shape, const void *at) {
    if (shape->aux) return value_block(at) ? 2 - shape->aux : shape->aux - 1;
    uint64_t tag;
    memcpy(&tag, at, sizeof tag);
    return tag;
}
static const unsigned char *value_payload(const core_value_shape *shape, const void *at) {
    return (const unsigned char *)at + (shape->aux ? 0 : 8);
}

typedef struct { const core_value_shape *shape; const unsigned char *left, *right; } core_equal_work;
typedef struct { core_equal_work *items; size_t count, capacity; } core_equal_stack;
static void value_equal_push(core_equal_stack *stack, const core_value_shape *shape, const void *left, const void *right) {
    if (stack->count == stack->capacity) {
        size_t capacity = stack->capacity ? stack->capacity * 2 : 64;
        if (capacity < stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) out_of_memory();
        core_equal_work *items = realloc(stack->items, capacity * sizeof *items);
        if (!items) out_of_memory();
        stack->items = items;
        stack->capacity = capacity;
    }
    stack->items[stack->count++] = (core_equal_work){shape, left, right};
}

bool myl_core_values_equal(const core_value_shape *root, const void *left, const void *right) {
    core_equal_stack stack = {0};
    core_value_memo memo = {0};
    bool same = true;
    value_equal_push(&stack, root, left, right);
    while (same && stack.count) {
        core_equal_work work = stack.items[--stack.count];
        const core_value_shape *shape = work.shape;
        switch (shape->kind) {
        case 0: break;
        case 1: case 10: same = memcmp(work.left, work.right, shape->size) == 0; break;
        case 2: {
            double a, b;
            memcpy(&a, work.left, 8); memcpy(&b, work.right, 8);
            same = a == b;
            break;
        }
        case 3: same = myl_core_str_eq(value_block(work.left), value_block(work.right)); break;
        case 4:
            for (uint32_t i = 0; i < shape->count; ++i)
                value_equal_push(&stack, shape->children[i], work.left + shape->offsets[i], work.right + shape->offsets[i]);
            break;
        case 5: {
            uint64_t tag = value_tag(shape, work.left);
            same = tag == value_tag(shape, work.right);
            if (same && tag < shape->count) value_equal_push(&stack, shape->children[tag], value_payload(shape, work.left), value_payload(shape, work.right));
            else if (tag >= shape->count) abort();
            break;
        }
        case 6: case 7: case 9: {
            const myl_block *a = value_block(work.left), *b = value_block(work.right);
            if (shape->kind != 6 && a->len != b->len) { same = false; break; }
            /* A repeated pair's children are already scheduled or checked. This
             * never treats identical pointers as equal: an embedded NaN is checked. */
            if (value_memo(&memo, shape, a, b, false)) break;
            (void)value_memo(&memo, shape, a, b, true);
            if (shape->kind == 6) {
                value_equal_push(&stack, shape->children[0], (const unsigned char *)a + SELKA_HEADER, (const unsigned char *)b + SELKA_HEADER);
            } else if (shape->kind == 7) {
                uint32_t stride = shape->children[0]->size;
                for (int64_t i = 0; i < a->len; ++i)
                    value_equal_push(&stack, shape->children[0], (const unsigned char *)a + SELKA_HEADER + (size_t)i * stride, (const unsigned char *)b + SELKA_HEADER + (size_t)i * stride);
            } else {
                core_dict_meta *ma = dict_meta(a), *mb = dict_meta(b);
                for (uint64_t i = 0; same && i < ma->elen; ++i) {
                    if (!dict_live(ma, i)) continue;
                    unsigned char *entry = dict_entry(a, i);
                    uint64_t hash = dict_hash(mb->desc, entry);
                    int64_t found = myl_core_dict_find(b, entry, hash);
                    if (found < 0) { same = false; break; }
                    value_equal_push(&stack, shape->children[1], entry + ma->desc->value_offset, dict_entry(b, (uint64_t)found) + mb->desc->value_offset);
                }
            }
            break;
        }
        case 8:
            for (uint32_t i = 0; i < shape->count; ++i)
                value_equal_push(&stack, shape->children[0], work.left + (size_t)i * shape->children[0]->size, work.right + (size_t)i * shape->children[0]->size);
            break;
        default: abort();
        }
    }
    free(stack.items);
    free(memo.entries);
    return same;
}

typedef struct { const core_value_shape *shape; const unsigned char *at; uint64_t index, hash; const void *memo; } core_hash_work;
typedef struct { core_hash_work *items; size_t count, capacity; } core_hash_stack;
static void value_hash_push(core_hash_stack *stack, const core_value_shape *shape, const void *at) {
    if (stack->count == stack->capacity) {
        size_t capacity = stack->capacity ? stack->capacity * 2 : 64;
        if (capacity < stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) out_of_memory();
        core_hash_work *items = realloc(stack->items, capacity * sizeof *items);
        if (!items) out_of_memory();
        stack->items = items;
        stack->capacity = capacity;
    }
    stack->items[stack->count++] = (core_hash_work){shape, at, UINT64_MAX, 0, NULL};
}
static uint64_t value_scalar_hash(const core_value_shape *shape, const void *at) {
    uint64_t bits = 0;
    if (shape->kind == 3) bits = myl_core_str_hash(value_block(at));
    else if (shape->kind == 2) {
        double value;
        memcpy(&value, at, 8);
        if (value == 0.0) bits = 0;
        else if (value != value) bits = UINT64_C(0x7ff8000000000000);
        else memcpy(&bits, at, 8);
    } else memcpy(&bits, at, shape->size);
    uint64_t mixed = value_mix(bits);
    return mixed ^ (mixed >> 32);
}

uint64_t myl_core_values_hash(const core_value_shape *root, const void *at) {
    core_hash_stack stack = {0};
    core_value_memo memo = {0};
    uint64_t returned = 0;
    value_hash_push(&stack, root, at);
    while (stack.count) {
        core_hash_work *work = &stack.items[stack.count - 1];
        const core_value_shape *shape = work->shape;
        if (shape->kind <= 3 || shape->kind == 10) {
            returned = shape->kind ? value_scalar_hash(shape, work->at) : 0;
            --stack.count;
            continue;
        }
        if (work->index == UINT64_MAX) {
            work->index = 0;
            if (shape->kind == 6 || shape->kind == 7 || shape->kind == 9) {
                const myl_block *block = value_block(work->at);
                core_value_memo_entry *known = value_memo(&memo, shape, block, NULL, false);
                if (known) { returned = known->hash; --stack.count; continue; }
                work->memo = block;
                work->at = (const unsigned char *)block + SELKA_HEADER;
            }
            if (shape->kind == 5) work->hash = value_mix(value_tag(shape, work->at));
        } else if (work->index) {
            work->hash = value_mix(work->hash) ^ returned;
        }
        const core_value_shape *child = NULL;
        const unsigned char *part = NULL;
        uint64_t index = work->index++;
        switch (shape->kind) {
        case 4:
            if (index < shape->count) { child = shape->children[index]; part = work->at + shape->offsets[index]; }
            break;
        case 5:
            if (index == 0) {
                uint64_t tag = value_tag(shape, work->at);
                if (tag >= shape->count) abort();
                child = shape->children[tag]; part = value_payload(shape, work->at);
            }
            break;
        case 6:
            if (index == 0) { child = shape->children[0]; part = work->at; }
            break;
        case 7: {
            const myl_block *block = work->memo;
            if (index < (uint64_t)block->len) { child = shape->children[0]; part = work->at + index * child->size; }
            break;
        }
        case 8:
            if (index < shape->count) { child = shape->children[0]; part = work->at + index * child->size; }
            break;
        case 9: abort(); /* Mutable tables are not accepted as dictionary keys. */
        default: abort();
        }
        if (child) {
            value_hash_push(&stack, child, part);
        } else {
            returned = work->hash;
            if (work->memo) value_memo(&memo, shape, work->memo, NULL, true)->hash = returned;
            --stack.count;
        }
    }
    free(stack.items);
    free(memo.entries);
    return returned;
}

bool myl_core_same_block(const myl_block *left, const myl_block *right) { return left == right; }

/* The old print/str spelling from io_render.zig and native_render.zig.
 * Source rendering descriptors retain unit payload presence in union offsets,
 * dictionary/set identity in aux and domain names in kind 11. Their child sizes
 * remain physical strides, including one-byte unit placeholders.
 * Depth is bounded at 24, and
 * transparent boxes do not consume depth. The graph traversal above remains
 * iterative for equality/hashing, where no rendering depth cap applies. */
typedef struct { char *data; size_t count, capacity; } core_render_buffer;
static void value_render_bytes(core_render_buffer *output, const void *bytes, size_t count) {
    if (count > SIZE_MAX - output->count) out_of_memory();
    size_t wanted = output->count + count;
    if (wanted > output->capacity) {
        size_t capacity = output->capacity ? output->capacity : 64;
        while (capacity < wanted) {
            if (capacity > SIZE_MAX / 2) out_of_memory();
            capacity *= 2;
        }
        char *data = realloc(output->data, capacity);
        if (!data) out_of_memory();
        output->data = data;
        output->capacity = capacity;
    }
    if (count) memcpy(output->data + output->count, bytes, count);
    output->count = wanted;
}
static void value_render_text(core_render_buffer *output, const char *text) {
    value_render_bytes(output, text, strlen(text));
}
static void value_render_octets(core_render_buffer *output, const myl_block *block, bool bytes, unsigned depth) {
    bool quoted = bytes || depth != 0;
    if (bytes) value_render_text(output, "b");
    if (quoted) value_render_text(output, "'");
    const unsigned char *data = (const unsigned char *)block + SELKA_HEADER;
    for (int64_t i = 0; i < block->len; ++i) {
        unsigned char byte = data[i];
        if (quoted && (byte == '\'' || byte == '\\')) {
            value_render_text(output, "\\");
            value_render_bytes(output, &byte, 1);
        } else if (quoted && (byte == '\n' || byte == '\r' || byte == '\t')) {
            char escape[2] = {'\\', byte == '\n' ? 'n' : byte == '\r' ? 'r' : 't'};
            value_render_bytes(output, escape, 2);
        } else if (bytes && (byte < 0x20 || byte >= 0x7f)) {
            const char hex[] = "0123456789abcdef";
            char escape[4] = {'\\', 'x', hex[byte >> 4], hex[byte & 15]};
            value_render_bytes(output, escape, 4);
        } else value_render_bytes(output, &byte, 1);
    }
    if (quoted) value_render_text(output, "'");
}
extern myl_block *myl_core_str_from_f64(double value) __attribute__((weak));
static void value_render(core_render_buffer *output, const core_value_shape *shape, const unsigned char *at, unsigned depth) {
    if (depth > 24) { value_render_text(output, "..."); return; }
    switch (shape->kind) {
    case 0: value_render_text(output, "None"); break;
    case 1: {
        uint64_t bits = 0;
        memcpy(&bits, at, shape->size);
        if (shape->aux == 1) { value_render_text(output, bits ? "True" : "False"); break; }
        char number[32];
        if (shape->aux == 2) {
            unsigned width = shape->size * 8;
            if (width < 64 && (bits & (UINT64_C(1) << (width - 1)))) bits |= UINT64_MAX << width;
            int64_t signed_value;
            memcpy(&signed_value, &bits, 8);
            snprintf(number, sizeof number, "%" PRId64, signed_value);
        } else snprintf(number, sizeof number, "%" PRIu64, bits);
        value_render_text(output, number);
        break;
    }
    case 2: {
        if (!myl_core_str_from_f64) abort();
        double value;
        memcpy(&value, at, 8);
        myl_block *text = myl_core_str_from_f64(value);
        value_render_bytes(output, block_data(text), (size_t)text->len);
        myl_core_release(text);
        break;
    }
    case 3: value_render_octets(output, value_block(at), shape->aux != 0, depth); break;
    case 4:
        if (!shape->names) abort();
        if (!shape->aux) value_render_text(output, shape->names[0]);
        value_render_text(output, "(");
        for (uint32_t i = 0; i < shape->count; ++i) {
            if (i) value_render_text(output, ", ");
            if (!shape->aux) { value_render_text(output, shape->names[i + 1]); value_render_text(output, "="); }
            value_render(output, shape->children[i], at + shape->offsets[i], depth + 1);
        }
        value_render_text(output, ")");
        break;
    case 5: {
        uint64_t tag = value_tag(shape, at);
        if (tag >= shape->count || !shape->names) abort();
        /* Named case fields already have their constructor in the payload descriptor. */
        if (shape->offsets && shape->offsets[tag] == 2) {
            value_render(output, shape->children[tag], value_payload(shape, at), depth + 1);
            break;
        }
        value_render_text(output, shape->names[tag]);
        if (shape->offsets ? shape->offsets[tag] != 0 : shape->children[tag]->kind != 0) {
            value_render_text(output, "(");
            value_render(output, shape->children[tag], value_payload(shape, at), depth + 1);
            value_render_text(output, ")");
        }
        break;
    }
    case 6:
        value_render(output, shape->children[0], (const unsigned char *)value_block(at) + SELKA_HEADER, depth);
        break;
    case 7: case 8: {
        const unsigned char *data = at;
        uint64_t count = shape->count;
        if (shape->kind == 7) {
            const myl_block *block = value_block(at);
            data = (const unsigned char *)block + SELKA_HEADER;
            count = (uint64_t)block->len;
        }
        value_render_text(output, "[");
        for (uint64_t i = 0; i < count; ++i) {
            if (i) value_render_text(output, ", ");
            value_render(output, shape->children[0], data + i * shape->children[0]->size, depth + 1);
        }
        value_render_text(output, "]");
        break;
    }
    case 9: {
        const myl_block *dict = value_block(at);
        bool set = shape->aux ? shape->aux == 1 : shape->children[1]->kind == 0;
        if (set && !dict->len) { value_render_text(output, "set()"); break; }
        core_dict_meta *meta = dict_meta(dict);
        value_render_text(output, "{");
        bool first = true;
        for (uint64_t i = 0; i < meta->elen; ++i) {
            if (!dict_live(meta, i)) continue;
            if (!first) value_render_text(output, ", ");
            first = false;
            unsigned char *entry = dict_entry(dict, i);
            value_render(output, shape->children[0], entry, depth + 1);
            if (!set) {
                value_render_text(output, ": ");
                value_render(output, shape->children[1], entry + meta->desc->value_offset, depth + 1);
            }
        }
        value_render_text(output, "}");
        break;
    }
    case 11:
        value_render_text(output, shape->names[0]);
        value_render_text(output, "(");
        value_render(output, shape->children[0], at, depth + 1);
        value_render_text(output, ")");
        break;
    default: abort();
    }
}
myl_block *myl_core_values_render(const core_value_shape *shape, const void *at) {
    core_render_buffer output = {0};
    value_render(&output, shape, at, 0);
    myl_block *text = str_from(output.data, output.count);
    free(output.data);
    return text;
}
myl_block *myl_core_none_text(void) { return str_from("None", 4); }
