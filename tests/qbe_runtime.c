/* Standalone runtime boundary checks; compile with qbe_runtime.c and -lm. */
#include "qbe_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

static unsigned calls;
static uint64_t recurse(void *context) {
    myl_qbe_enter(context);
    if (myl_qbe_failed(context)) return 0;
    uint64_t result = ++calls == 32 ? 0 : recurse(context);
    myl_qbe_leave(context);
    return result;
}
static uint64_t loop(void *context) {
    myl_qbe_enter(context);
    if (myl_qbe_failed(context)) return 0;
    while (!myl_qbe_failed(context)) myl_qbe_step(context);
    myl_qbe_leave(context);
    return 0;
}
static uint64_t failing_entry(void *context) {
    myl_qbe_enter(context);
    if (myl_qbe_failed(context)) return 0;
    void *first=myl_qbe_frame_allocate(context,65536);
    void *second=myl_qbe_frame_allocate(context,65536);
    assert(first && second);
    myl_qbe_frame_release(context,first);
    /* The remaining frame must be reclaimed on a trap. */
    uint64_t result = myl_qbe_int_binary(context, 3, 1, 64, 1, 0);
    myl_qbe_leave(context);
    return result;
}
static uint64_t successful_entry(void *context) {
    myl_qbe_enter(context);
    if (myl_qbe_failed(context)) return 0;
    myl_qbe_step(context);
    myl_qbe_leave(context);
    return 42;
}
int main(int argc, char **argv) {
    MylQbeContext context = {.max_steps=10000000, .max_frames=1024};
    if (argc == 2) {
        if (!strcmp(argv[1], "overflow")) myl_qbe_int_binary(&context, 0, 1, 64, INT64_MAX, 1);
        else if (!strcmp(argv[1], "unsigned-overflow")) myl_qbe_int_binary(&context, 2, 0, 64, UINT64_MAX, UINT64_MAX);
        else if (!strcmp(argv[1], "division")) myl_qbe_int_binary(&context, 3, 1, 64, 1, 0);
        else if (!strcmp(argv[1], "division-overflow")) myl_qbe_int_binary(&context, 3, 1, 64, (uint64_t)INT64_MIN, (uint64_t)-1);
        else if (!strcmp(argv[1], "cast")) myl_qbe_int_cast(&context, 0, 1, 64, UINT64_MAX);
        else if (!strcmp(argv[1], "shift")) myl_qbe_int_binary(&context, 18, 0, 64, 1, 64);
        else if (!strcmp(argv[1], "float-cast")) myl_qbe_float_unary(&context, 9, UINT64_C(0x7ff0000000000000));
        else if (!strcmp(argv[1], "frames")) {
            char *options[] = {argv[0], "--max-frames=8"};
            return mylang_qbe_run_options(recurse, 2, options);
        } else if (!strcmp(argv[1], "steps")) {
            char *options[] = {argv[0], "--max-steps=8"};
            return mylang_qbe_run_options(loop, 2, options);
        }
        if (context.trap) {
            fprintf(stderr, "%s: QBE runtime failure\n", context.trap);
            return 1;
        }
        return 99; /* Every requested failure must trap. */
    }
    MylQbeResult trapped, succeeded;
    assert(mylang_qbe_execute(failing_entry, 100, 10, &trapped) == 1);
    assert(!strcmp(trapped.code, "R_DIVISION_BY_ZERO"));
    assert(mylang_qbe_execute(successful_entry, 100, 10, &succeeded) == 0);
    assert(succeeded.value == 42 && succeeded.steps == 1 && succeeded.code == NULL);
    MylQbeActiveFrame frames[2]={0};
    MylQbeContext sized={.max_steps=1,.max_frames=2,.frame_data=frames};
    myl_qbe_enter_at_sized(&sized,NULL,1048576);
    assert(!sized.trap && sized.native_stack_bytes==1048576);
    myl_qbe_enter_at_sized(&sized,NULL,1);
    assert(sized.trap && !strcmp(sized.trap,"R_FRAME_LIMIT") && sized.frames==1);
    myl_qbe_leave(&sized);
    assert(sized.native_stack_bytes==0);
    assert(myl_qbe_int_binary(&context, 5, 1, 64, (uint64_t)-7, 3) == (uint64_t)-3);
    assert(myl_qbe_int_binary(&context, 6, 1, 64, (uint64_t)-7, 3) == 2);
    assert(myl_qbe_int_binary(&context, 5, 1, 64, 7, (uint64_t)-3) == (uint64_t)-3);
    assert(myl_qbe_int_binary(&context, 6, 1, 64, 7, (uint64_t)-3) == (uint64_t)-2);
    assert(myl_qbe_int_binary(&context, 4, 1, 64, (uint64_t)INT64_MIN, (uint64_t)-1) == 0);
    assert(myl_qbe_int_binary(&context, 3, 0, 64, UINT64_MAX, 1) == UINT64_MAX);
    assert(myl_qbe_int_binary(&context, 20, 1, 8, 127, 1) == (uint64_t)-128);
    assert(myl_qbe_int_binary(&context, 22, 0, 64, UINT64_MAX, UINT64_MAX) == 1);
    assert(myl_qbe_int_binary(&context, 25, 0, 64, UINT64_MAX, UINT64_MAX) == UINT64_MAX);
    assert(myl_qbe_int_binary(&context, 24, 1, 8, (uint64_t)-128, 1) == (uint64_t)-128);
    assert(myl_qbe_int_binary(&context, 19, 1, 64, (uint64_t)-7, 1) == (uint64_t)-4);
    assert(myl_qbe_int_cast(&context, 1, 1, 8, (uint64_t)-128) == (uint64_t)-128);
    assert(myl_qbe_int_neg(&context, 1, 8, 127) == (uint64_t)-127);
    assert(myl_qbe_float_binary(&context, 29, 0, 0) == UINT64_C(0x7ff8000000000000));
    assert(myl_qbe_float_unary(&context, 10, (uint64_t)-1) == UINT64_C(0xbff0000000000000));
    assert(myl_qbe_float_unary(&context, 11, UINT64_C(0xbff8000000000000)) == (uint64_t)-1);
    return 0;
}
