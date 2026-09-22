/* Copy of experiments/svg-slowdown-20260921/sample.c with ONE change, marked
   "AUDIT CHANGE" below: the first expiration starts inside the first kernel
   tick instead of 0.5-2.0 ms in, because the SVG run is only about 2 ms of CPU
   and the original start left its first half unsampled. Everything else --
   handler, hashing, output format -- is byte-identical.

   Diagnostic userspace PC sampler for the unchanged dynamic guest binaries.
   No perf permissions required. SIGPROF samples CPU time, not blocked I/O.
   Output maps exact instruction pointers to ELF virtual addresses via the
   main executable's dl_iterate_phdr load address. No allocation in handler. */
#define _GNU_SOURCE
#include <link.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>
#include <ucontext.h>
#include <unistd.h>

#define SLOTS (1u << 17)
static uintptr_t pcs[SLOTS], load_base, text_start, text_end;
static unsigned counts[SLOTS], outside, overflow, samples;
static const char *output_path;

static int locate(struct dl_phdr_info *info, size_t size, void *unused) {
    (void)size; (void)unused;
    if (info->dlpi_name[0]) return 0;
    load_base=info->dlpi_addr;
    for (int i=0;i<info->dlpi_phnum;i++) {
        const ElfW(Phdr) *p=&info->dlpi_phdr[i];
        if (p->p_type==PT_LOAD && (p->p_flags&PF_X)) {
            text_start=load_base+p->p_vaddr;
            text_end=text_start+p->p_memsz;
        }
    }
    return 1;
}

static void sample(int signal, siginfo_t *info, void *context) {
    (void)signal; (void)info;
    uintptr_t pc=(uintptr_t)((ucontext_t *)context)->uc_mcontext.gregs[REG_RIP];
    samples++;
    if (pc<text_start || pc>=text_end) { outside++; return; }
    pc-=load_base;
    size_t slot=((pc>>2)^(pc>>16))&(SLOTS-1);
    for (size_t n=0;n<SLOTS;n++,slot=(slot+1)&(SLOTS-1)) {
        if (!pcs[slot] || pcs[slot]==pc) { pcs[slot]=pc; counts[slot]++; return; }
    }
    overflow++;
}

static void finish(void) {
    struct itimerval timer={0};
    setitimer(ITIMER_PROF,&timer,NULL);
    FILE *out=fopen(output_path,"a");
    if (!out) return;
    fprintf(out,"run %ld samples %u outside %u overflow %u\n",(long)getpid(),samples,outside,overflow);
    for (size_t i=0;i<SLOTS;i++) if (counts[i])
        fprintf(out,"%lx %u\n",(unsigned long)pcs[i],counts[i]);
    fclose(out);
}

__attribute__((constructor)) static void start(void) {
    output_path=getenv("MYLANG_AUDIT_SAMPLES");
    if (!output_path) return;
    dl_iterate_phdr(locate,NULL);
    if (!text_start) return;
    struct sigaction action={0};
    action.sa_sigaction=sample;
    action.sa_flags=SA_SIGINFO|SA_RESTART;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGPROF,&action,NULL)) return;
    atexit(finish);
    /* Kernel tick granularity limits the effective rate; report actual counts.
       AUDIT CHANGE: vary the first expiration to reduce repeated-start alignment
       bias, but inside one tick, so no prefix of the run goes unsampled. */
    struct itimerval timer={.it_interval={0,500},.it_value={0,1}};
    setitimer(ITIMER_PROF,&timer,NULL);
}
