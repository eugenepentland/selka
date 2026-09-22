#define _POSIX_C_SOURCE 200809L
#include "qbe_runtime.h"
#include <stdio.h>
#include <time.h>
typedef struct { uint64_t a,b; } pair;
typedef struct { uint64_t a,b,c,d,e,f; } six;
static uint64_t now(void) { struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return (uint64_t)t.tv_sec*1000000000+t.tv_nsec; }
extern pair __real_myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5(uint64_t a0,uint64_t a1);
pair __wrap_myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5(uint64_t a0,uint64_t a1) {
 MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;
 size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();
 pair result=__real_myl_f_b5d931620df636deef979a0d59c3f9f39f360f8d212025d8bcb427e874f639a5(a0,a1);
 uint64_t elapsed=now()-begin;
 fprintf(stderr,"PHASE main::main ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);
 return result;
}
extern pair __real_myl_f_d6735a295f5be71bdb8498bcf63ea790a7ebeb1d118836b4d07ed8f0fb3d31b6(uint64_t a0,uint64_t a1,uint64_t a2);
pair __wrap_myl_f_d6735a295f5be71bdb8498bcf63ea790a7ebeb1d118836b4d07ed8f0fb3d31b6(uint64_t a0,uint64_t a1,uint64_t a2) {
 MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;
 size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();
 pair result=__real_myl_f_d6735a295f5be71bdb8498bcf63ea790a7ebeb1d118836b4d07ed8f0fb3d31b6(a0,a1,a2);
 uint64_t elapsed=now()-begin;
 fprintf(stderr,"PHASE sexpr::parse ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);
 return result;
}
extern six __real_myl_f_df4898a1bbd9e5a1d1490497c2d1ad436c20e0128fef8685202e7b38f47f6bfe(uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,uint64_t a4);
six __wrap_myl_f_df4898a1bbd9e5a1d1490497c2d1ad436c20e0128fef8685202e7b38f47f6bfe(uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,uint64_t a4) {
 MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;
 size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();
 six result=__real_myl_f_df4898a1bbd9e5a1d1490497c2d1ad436c20e0128fef8685202e7b38f47f6bfe(a0,a1,a2,a3,a4);
 uint64_t elapsed=now()-begin;
 fprintf(stderr,"PHASE schematic::build ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);
 return result;
}
extern uint64_t __real_myl_f_f66f96ab3ccadb725e348d6f28efae14faedf4c19796022fd6eaee59796c3c81(uint64_t a0,uint64_t a1,uint64_t a2);
uint64_t __wrap_myl_f_f66f96ab3ccadb725e348d6f28efae14faedf4c19796022fd6eaee59796c3c81(uint64_t a0,uint64_t a1,uint64_t a2) {
 MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;
 size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();
 uint64_t result=__real_myl_f_f66f96ab3ccadb725e348d6f28efae14faedf4c19796022fd6eaee59796c3c81(a0,a1,a2);
 uint64_t elapsed=now()-begin;
 fprintf(stderr,"PHASE svg::render ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);
 return result;
}
extern uint64_t __real_myl_f_e8263610c03ef032bd2fe5e8f8b4f8830389ca02c6dd59726aee8e82cbe3390e(uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3);
uint64_t __wrap_myl_f_e8263610c03ef032bd2fe5e8f8b4f8830389ca02c6dd59726aee8e82cbe3390e(uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3) {
 MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;
 size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();
 uint64_t result=__real_myl_f_e8263610c03ef032bd2fe5e8f8b4f8830389ca02c6dd59726aee8e82cbe3390e(a0,a1,a2,a3);
 uint64_t elapsed=now()-begin;
 fprintf(stderr,"PHASE layout::build ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);
 return result;
}
extern uint64_t __real_myl_f_2dceb51af4f7b4e7f12fda9fe900476cf42e43fc35c2c279537b2a0a8222ca67(uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,uint64_t a4,uint64_t a5);
uint64_t __wrap_myl_f_2dceb51af4f7b4e7f12fda9fe900476cf42e43fc35c2c279537b2a0a8222ca67(uint64_t a0,uint64_t a1,uint64_t a2,uint64_t a3,uint64_t a4,uint64_t a5) {
 MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;
 size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();
 uint64_t result=__real_myl_f_2dceb51af4f7b4e7f12fda9fe900476cf42e43fc35c2c279537b2a0a8222ca67(a0,a1,a2,a3,a4,a5);
 uint64_t elapsed=now()-begin;
 fprintf(stderr,"PHASE layout_routes::build ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);
 return result;
}
