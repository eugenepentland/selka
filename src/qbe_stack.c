/* Linux AMD64 execution stacks stay on the calling thread. Pages are committed
 * on demand; two guard pages bound the mapping. Logical frame budgets and sized
 * frame checks remain active rather than translating SIGSEGV into guest traps. */
#define _GNU_SOURCE
#include "qbe_runtime.h"
#include <setjmp.h>
#include <stdlib.h>
#include <ucontext.h>
#include <inttypes.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <unistd.h>
/* Native stack mapped for every frame a `--max-frames` budget allows, and the
   headroom beyond that share. `src/memory_budget.zig` mirrors both so the CLI can
   refuse a budget the address space cannot back before it starts a guest. */
#define FRAME_STACK_BYTES 32768
#define STACK_SLACK (8u*1024u*1024u)
typedef struct {
    uint64_t (*entry)(void *);
    MylQbeContext *context;
    uint64_t result;
    jmp_buf unwind;
} StackCall;
/* Run the entry with one armed non-local exit. A trap is fatal: the first
   `fail` builds the trace on the generated stack and then longjmps back here,
   so the recursion unwinds without running guest code after the failure. The
   call pointer is volatile because longjmp restores callee-saved registers
   only, and `low`/`high` arrive in caller-saved ones. */
static void launch(unsigned low,unsigned high) {
    uintptr_t pointer=(uintptr_t)low|((uintptr_t)high<<32);
    StackCall *volatile call=(StackCall *)pointer;
    if (setjmp(call->unwind)==0) {
        call->context->unwind=&call->unwind;
        call->result=call->entry(call->context);
    } else call->result=0;
    call->context->unwind=NULL;
}
/* The address space could not back the execution stack. A call-depth budget the
   ceiling cannot hold is a configuration mistake, so name the reservation, the
   limit in force and the two ways out instead of the bare `OutOfMemory`. */
static void stack_refused(MylQbeContext *ctx,size_t size) {
    struct rlimit limit;
    if (ctx->frame_limit==MYL_QBE_UNBOUNDED || getrlimit(RLIMIT_AS,&limit)) { myl_qbe_fail(ctx,"OutOfMemory");return; }
    char need[48],bound[64];
    if (size==SIZE_MAX) snprintf(need,sizeof need,"more native stack than can be addressed");
    else snprintf(need,sizeof need,"%.1f GiB of native stack",(double)size/1073741824.0);
    if (limit.rlim_cur==RLIM_INFINITY) snprintf(bound,sizeof bound,"the system refused the mapping");
    else snprintf(bound,sizeof bound,"this process may map only %.1f GiB",(double)limit.rlim_cur/1073741824.0);
    fprintf(stderr,"mylang: a call-depth budget of %" PRIu64 " frames (--max-frames) reserves %s (%u KiB per frame), but %s; "
        "raise --max-memory (and MYLANG_HOST_MEMORY_LIMIT, which a guest inherits) or lower --max-frames\n",
        ctx->max_frames,need,(unsigned)(FRAME_STACK_BYTES>>10),bound);
    ctx->reported=1;
    myl_qbe_fail(ctx,"OutOfMemory");
}
uint64_t myl_qbe_on_stack(uint64_t (*entry)(void *),MylQbeContext *ctx) {
    long page_size=sysconf(_SC_PAGESIZE);
    if (page_size<=0) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    size_t page=(size_t)page_size;
    const size_t slack=STACK_SLACK;
    if (page>SIZE_MAX/4 || slack>SIZE_MAX-2*page || ctx->max_frames>(SIZE_MAX-slack-2*page)/FRAME_STACK_BYTES) {
        stack_refused(ctx,SIZE_MAX);return 0;
    }
    size_t usable=(size_t)ctx->max_frames*FRAME_STACK_BYTES+slack;
    if (usable>SIZE_MAX-(page-1)) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    usable=(usable+page-1)/page*page;
    if (usable>SIZE_MAX-2*page) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    size_t size=usable+2*page;
    void *mapping=mmap(NULL,size,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_STACK,-1,0);
    if (mapping==MAP_FAILED) { stack_refused(ctx,size);return 0; }
    unsigned char *bottom=(unsigned char *)mapping+page;
    uint64_t result=0;
    ucontext_t caller,target;
    StackCall call={.entry=entry,.context=ctx};
    if (mprotect(bottom,usable,PROT_READ|PROT_WRITE) || getcontext(&target)) {
        myl_qbe_fail(ctx,"OutOfMemory");goto done;
    }
    ctx->native_stack_limit=usable-slack;
    ctx->native_stack_bottom=(uintptr_t)bottom;
    ctx->native_stack_top=(uintptr_t)bottom+usable;
    /* Generated frame records compare their own address against this floor,
       which keeps the same 64 KiB headroom above the guard page the sized C
       entry point used. */
    ctx->frame_floor=(uintptr_t)bottom+65536;
    target.uc_stack.ss_sp=bottom;
    target.uc_stack.ss_size=usable;
    target.uc_stack.ss_flags=0;
    target.uc_link=&caller;
    uintptr_t pointer=(uintptr_t)&call;
    makecontext(&target,(void (*)(void))launch,2,(unsigned)pointer,(unsigned)(pointer>>32));
    if (swapcontext(&caller,&target)) myl_qbe_fail(ctx,"OutOfMemory");
    else result=call.result;
done:
    ctx->native_stack_bottom=0;
    ctx->native_stack_top=0;
    ctx->frame_floor=0;
    munmap(mapping,size);
    return result;
}
