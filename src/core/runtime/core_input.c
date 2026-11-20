/* The Input capability (stage-1 lane B, S2a): standard input and in-memory inputs behind one `int64` handle, the way a
 * Stream is a handle. Handle 0 is the process's standard input, handle -1 an input that is empty from the first read
 * (what a test's `Input` parameter holds), and handle -2 - i the i-th input `input_from(bytes)` built. Every read blocks
 * until it has an answer; a read the operating system refuses traps `R_INPUT` (status 1), the way a refused write
 * traps `R_OUTPUT`. An Input needs no grant: `--restrict` cannot take it away.
 *
 *   read(max)       up to `max` octets, one wait at most: whatever is buffered, else whatever the next read(2) brings;
 *                   an empty answer means the end of the input
 *   read_exact(n)   exactly `n` octets, waiting for more as needed; fewer only when the input ends first
 *   read_line()     through the next newline, or the final unterminated line; empty only at the end
 *
 * The answers are plain octet blocks; the compiler turns "fewer than asked" and "empty" into `None`. */
#include <errno.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    int descriptor;        /* the descriptor to read, or -1 for an in-memory input */
    unsigned char *data;   /* the buffered octets, from `position` up to `length` */
    size_t position, length, capacity;
    int ended;             /* no octet will ever follow what is buffered */
} CoreInput;

#define CORE_INPUT_CHUNK 65536

static CoreInput core_input_stdin = { 0, NULL, 0, 0, 0, 0 };
static CoreInput core_input_none = { -1, NULL, 0, 0, 0, 1 };
static CoreInput **core_inputs;
static size_t core_input_count, core_input_slots;
static MYL_TLS char core_input_message[192];

__attribute__((cold, noinline)) static void core_input_refused(const char *reason) {
    snprintf(core_input_message, sizeof core_input_message, "standard input could not be read: %s", reason);
    core_failure_detail = core_input_message;
    core_io_failure("R_INPUT");
}

static CoreInput *core_input_for(int64_t handle) {
    if (handle == 0) return &core_input_stdin;
    if (handle == -1) return &core_input_none;
    if (handle <= -2) {
        uint64_t index = (uint64_t)(-(handle + 2));
        if (index < core_input_count) return core_inputs[index];
    }
    core_io_fail("InvalidCapability");
    __builtin_unreachable();
}

/* The octets ready to take. A descriptor input with none buffered waits for the next read(2); 0 means the end. */
static size_t core_input_fill(CoreInput *input) {
    size_t available = input->length - input->position;
    if (available || input->descriptor < 0 || input->ended) return available;
    if (!input->data) {
        input->data = malloc(CORE_INPUT_CHUNK);
        if (!input->data) out_of_memory();
        input->capacity = CORE_INPUT_CHUNK;
    }
    input->position = input->length = 0;
    core_flush_before_wait();
    for (;;) {
        ssize_t got = read(input->descriptor, input->data, input->capacity);
        if (got > 0) { input->length = (size_t)got; return (size_t)got; }
        if (got == 0) { input->ended = 1; return 0; }
        if (errno != EINTR) core_input_refused(strerror(errno));
    }
}

static myl_block *core_input_block(const unsigned char *bytes, size_t count) {
    return core_io_string(count ? (const void *)bytes : (const void *)"", count, 0);
}

/* The next `count` buffered octets as a new block. */
static myl_block *core_input_take(CoreInput *input, size_t count) {
    myl_block *block = core_input_block(input->data + input->position, count);
    input->position += count;
    return block;
}

typedef struct { unsigned char *bytes; size_t used, capacity; } CoreInputGather;

static void core_input_gather(CoreInputGather *gathered, const unsigned char *bytes, size_t count) {
    if (count > SIZE_MAX - gathered->used) out_of_memory();
    if (gathered->used + count > gathered->capacity) {
        size_t capacity = gathered->capacity ? gathered->capacity : 4096;
        while (capacity < gathered->used + count) {
            if (capacity > SIZE_MAX / 2) out_of_memory();
            capacity *= 2;
        }
        unsigned char *grown = realloc(gathered->bytes, capacity);
        if (!grown) out_of_memory();
        gathered->bytes = grown;
        gathered->capacity = capacity;
    }
    memcpy(gathered->bytes + gathered->used, bytes, count);
    gathered->used += count;
}

static myl_block *core_input_finish(CoreInputGather *gathered) {
    myl_block *block = core_input_block(gathered->bytes, gathered->used);
    free(gathered->bytes);
    return block;
}

myl_block *myl_core_input_read(int64_t handle, int64_t most) {
    CORE_IO_GUARD;
    if (most < 0) core_input_refused("a read size cannot be negative");
    CoreInput *input = core_input_for(handle);
    size_t available = most ? core_input_fill(input) : 0;
    size_t count = (uint64_t)most < available ? (size_t)most : available;
    return core_input_take(input, count);
}

myl_block *myl_core_input_read_exact(int64_t handle, int64_t wanted) {
    CORE_IO_GUARD;
    if (wanted < 0) core_input_refused("a read size cannot be negative");
    CoreInput *input = core_input_for(handle);
    size_t available = wanted ? core_input_fill(input) : 0;
    if (available >= (uint64_t)wanted) return core_input_take(input, (size_t)wanted);
    CoreInputGather gathered = { NULL, 0, 0 };
    while (gathered.used < (uint64_t)wanted) {
        available = core_input_fill(input);
        if (!available) break;
        size_t count = available < (uint64_t)wanted - gathered.used ? available : (size_t)((uint64_t)wanted - gathered.used);
        core_input_gather(&gathered, input->data + input->position, count);
        input->position += count;
    }
    return core_input_finish(&gathered);
}

myl_block *myl_core_input_read_line(int64_t handle) {
    CORE_IO_GUARD;
    CoreInput *input = core_input_for(handle);
    size_t available = core_input_fill(input);
    if (!available) return core_input_block(NULL, 0);
    const unsigned char *newline = memchr(input->data + input->position, '\n', available);
    if (newline) return core_input_take(input, (size_t)(newline - (input->data + input->position)) + 1);
    CoreInputGather gathered = { NULL, 0, 0 };
    while (available) {
        const unsigned char *start = input->data + input->position;
        newline = memchr(start, '\n', available);
        size_t count = newline ? (size_t)(newline - start) + 1 : available;
        core_input_gather(&gathered, start, count);
        input->position += count;
        if (newline) break;
        available = core_input_fill(input);
    }
    return core_input_finish(&gathered);
}

/* A new in-memory input holding a copy of `bytes`, and its handle. */
static int64_t core_input_register(const unsigned char *bytes, size_t length) {
    CoreInput *input = calloc(1, sizeof *input);
    if (!input) out_of_memory();
    input->descriptor = -1;
    input->ended = 1;
    input->data = malloc(length ? length : 1);
    if (!input->data) out_of_memory();
    if (length) memcpy(input->data, bytes, length);
    input->length = input->capacity = length;
    if (core_input_count == core_input_slots) {
        size_t slots = core_input_slots ? core_input_slots * 2 : 8;
        CoreInput **grown = realloc(core_inputs, slots * sizeof *grown);
        if (!grown) out_of_memory();
        core_inputs = grown;
        core_input_slots = slots;
    }
    core_inputs[core_input_count] = input;
    return -2 - (int64_t)core_input_count++;
}

int64_t myl_core_input_memory(myl_block *data) {
    CORE_IO_GUARD;
    return core_input_register(block_data(data), (size_t)data->len);
}

int64_t myl_core_span_input_memory(const unsigned char *data, uint64_t length) {
    CORE_IO_GUARD;
    return core_input_register(data, (size_t)length);
}
