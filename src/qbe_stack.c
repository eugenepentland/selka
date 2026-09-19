/* Linux AMD64 execution stacks stay on the calling thread. Pages are committed
 * on demand; two guard pages bound the mapping. Logical frame budgets and sized
 * frame checks remain active rather than translating SIGSEGV into guest traps. */
#define _GNU_SOURCE
#include "qbe_runtime.h"
#include <stdlib.h>
#include <ucontext.h>
#include <sys/mman.h>
#include <unistd.h>
typedef struct {
    uint64_t (*entry)(void *);
    MylQbeContext *context;
    uint64_t result;
} StackCall;
static void launch(unsigned low,unsigned high) {
    uintptr_t pointer=(uintptr_t)low|((uintptr_t)high<<32);
    StackCall *call=(StackCall *)pointer;
    call->result=call->entry(call->context);
}
uint64_t myl_qbe_on_stack(uint64_t (*entry)(void *),MylQbeContext *ctx) {
    long page_size=sysconf(_SC_PAGESIZE);
    if (page_size<=0) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    size_t page=(size_t)page_size;
    const size_t slack=8*1024*1024;
    if (page>SIZE_MAX/4 || slack>SIZE_MAX-2*page || ctx->max_frames>(SIZE_MAX-slack-2*page)/32768) {
        myl_qbe_fail(ctx,"OutOfMemory");return 0;
    }
    size_t usable=(size_t)ctx->max_frames*32768+slack;
    if (usable>SIZE_MAX-(page-1)) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    usable=(usable+page-1)/page*page;
    if (usable>SIZE_MAX-2*page) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    size_t size=usable+2*page;
    void *mapping=mmap(NULL,size,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS|MAP_STACK,-1,0);
    if (mapping==MAP_FAILED) { myl_qbe_fail(ctx,"OutOfMemory");return 0; }
    unsigned char *bottom=(unsigned char *)mapping+page;
    uint64_t result=0;
    ucontext_t caller,target;
    StackCall call={.entry=entry,.context=ctx};
    if (mprotect(bottom,usable,PROT_READ|PROT_WRITE) || getcontext(&target)) {
        myl_qbe_fail(ctx,"OutOfMemory");goto done;
    }
    ctx->native_stack_limit=usable-slack;
    ctx->native_stack_bottom=(uintptr_t)bottom;
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
    ctx->frame_floor=0;
    munmap(mapping,size);
    return result;
}
