/* Core-owned property trial transport. The old generation/counting/shrinking
 * algorithms stay in Zig. Fork gives a fatal Core trap a bounded copied-value
 * trial boundary without skipping reference-count cleanup on a longjmp. */
#include <sys/wait.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <signal.h>
#include <errno.h>
#include <ucontext.h>
#if defined(__linux__)
#include <sys/prctl.h>
#endif
static FILE *core_test_input, *core_test_output, *core_test_values;
static char *core_test_path;
static uint64_t core_test_trials;
static uint64_t core_test_steps;
static bool core_test_bounded;
/* Compatible additive helpers; existing runtime signatures and layouts stay fixed. */
/* A trial's wall-clock limit is exact to the millisecond: the trials of a batch
 * (NEW-CORE-TEST-BATCH-1) are each held to `--timeout-ms`, as a test alone is. */
void myl_core_test_limits(uint64_t steps, uint32_t timeout_ms) {
    core_test_steps=steps;core_test_bounded=steps!=0;
    struct itimerval timer={{0,0},{(time_t)(timeout_ms/1000),(suseconds_t)(timeout_ms%1000)*1000}};
    (void)setitimer(ITIMER_REAL,&timer,NULL);
}
void myl_core_test_tick(uint64_t cost) {
    if(!core_test_bounded)return;
    if(cost>core_test_steps)core_io_fail("R_STEP_LIMIT");
    core_test_steps-=cost;
}
/* Call-depth and byte ceilings (`--max-frames`, `--max-memory`), installed by the
 * test entry before its first trial. Every call of an original function enters one
 * frame and leaves it before returning; the trial runs on a stack mapped for the
 * whole budget, 32 KiB per frame plus 8 MiB, as the old core maps it, so a budget
 * that is honest about depth is never cut short by the native stack. */
enum { CORE_TEST_FRAME_STACK = 32768, CORE_TEST_STACK_SLACK = 8 << 20 };
static uint64_t core_test_frame_limit, core_test_depth;
void myl_core_test_ceilings(uint32_t frames, uint64_t memory) {
    core_test_frame_limit = frames;
    if (!memory) return;
    heap_ceiling = memory;
    /* The kernel's backstop: the address space at the ceiling plus 256 MiB, never loosened. */
    const uint64_t headroom = 256u << 20;
    struct rlimit limit;
    if (memory > UINT64_MAX - headroom || getrlimit(RLIMIT_AS, &limit)) return;
    rlim_t wanted = (rlim_t)(memory + headroom);
    if (limit.rlim_max != RLIM_INFINITY && wanted > limit.rlim_max) wanted = limit.rlim_max;
    if (limit.rlim_cur != RLIM_INFINITY && limit.rlim_cur <= wanted) return;
    limit.rlim_cur = wanted;
    (void)setrlimit(RLIMIT_AS, &limit);
}
/* `mylang run`'s budgets (NEW-CORE-S5-RUN-1), installed once by the program's entry:
 * steps and frames as a test's, the byte ceiling with its `RLIMIT_AS` backstop, and a
 * wall-clock limit that ends the process as the old core's `--timeout` does. */
static void core_run_timed_out(int signal_number) {
    (void)signal_number;
    static const char message[] = "R_TIMEOUT: wall-clock budget exhausted; raise it with --timeout=SECONDS\n";
    ssize_t ignored = write(STDERR_FILENO, message, sizeof message - 1);
    (void)ignored;
    _exit(1);
}
static void core_run_arm(uint64_t timeout_seconds) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = core_run_timed_out;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL)) {
        static const char refused[] = "mylang: cannot arm the --timeout wall-clock guard\n";
        ssize_t ignored = write(STDERR_FILENO, refused, sizeof refused - 1);
        (void)ignored;
        _exit(2);
    }
    alarm((unsigned)(timeout_seconds > UINT32_MAX ? UINT32_MAX : timeout_seconds));
}
void myl_core_run_controls(uint64_t steps, uint32_t frames, uint64_t memory, uint32_t timeout_seconds) {
    static bool installed;
    if (installed) return;
    installed = true;
    core_test_steps = steps;
    core_test_bounded = steps != 0;
    myl_core_test_ceilings(frames, memory);
    if (timeout_seconds) core_run_arm(timeout_seconds);
}

/* ---- A built program's runtime options (NATIVE-ARGV-1) -------------------------- */

/* One positive decimal budget `prefix`VALUE into `slot`; zero, a non-number or a repeat
   ends the process with status 2. Whether `arg` spells this budget at all. */
static bool core_start_budget(const char *arg, const char *prefix, uint64_t *slot) {
    size_t width = strlen(prefix);
    if (strncmp(arg, prefix, width)) return false;
    if (*slot) core_io_option_error("mylang: MYLANG_OPTIONS names %s twice\n", prefix);
    uint64_t value = 0;
    const char *digit = arg + width;
    if (!*digit) core_io_option_error("mylang: MYLANG_OPTIONS names %s, which is not a positive budget\n", arg);
    for (; *digit; ++digit) {
        if (*digit < '0' || *digit > '9' || value > (UINT64_MAX - (uint64_t)(*digit - '0')) / 10)
            core_io_option_error("mylang: MYLANG_OPTIONS names %s, which is not a positive budget\n", arg);
        value = value * 10 + (uint64_t)(*digit - '0');
    }
    if (!value) core_io_option_error("mylang: MYLANG_OPTIONS names %s, which is not a positive budget\n", arg);
    *slot = value;
    return true;
}
/* `MYLANG_MEMORY_LIMIT` in bytes (digits and an optional K, M or G), or 0 when unset or unreadable. */
static uint64_t core_start_memory_limit(void) {
    const char *text = getenv("MYLANG_MEMORY_LIMIT");
    uint64_t value = 0, scale = 1;
    if (!text || !*text) return 0;
    const char *at = text;
    for (; *at >= '0' && *at <= '9'; ++at) {
        if (value > (UINT64_MAX - (uint64_t)(*at - '0')) / 10) return 0;
        value = value * 10 + (uint64_t)(*at - '0');
    }
    if (at == text) return 0;
    if (*at == 'K' || *at == 'k') scale = 1u << 10;
    else if (*at == 'M' || *at == 'm') scale = 1u << 20;
    else if (*at == 'G' || *at == 'g') scale = 1u << 30;
    else if (*at) return 0;
    if (*at && at[1]) return 0;
    return value > UINT64_MAX / scale ? 0 : value * scale;
}
/* A frame budget reserves 32 KiB of native stack per frame plus 8 MiB and two guard
   pages, as the old core maps it. One the address space cannot back (the process's
   `RLIMIT_AS`, or `MYLANG_MEMORY_LIMIT` plus 256 MiB of headroom) is reported with the
   reservation and the limit, and ends the process with status 2 (RUN-FRAME-BUDGET-1). */
static void core_start_frame_reservation(uint64_t frames) {
    long page_size = sysconf(_SC_PAGESIZE);
    uint64_t page = page_size > 0 ? (uint64_t)page_size : 4096;
    uint64_t fixed = (uint64_t)CORE_TEST_STACK_SLACK + 3 * page;
    bool addressable = frames <= (UINT64_MAX - fixed) / CORE_TEST_FRAME_STACK;
    uint64_t need = addressable ? ((frames * CORE_TEST_FRAME_STACK + CORE_TEST_STACK_SLACK + page - 1) / page + 2) * page : UINT64_MAX;
    uint64_t limit = UINT64_MAX;
    struct rlimit current;
    if (!getrlimit(RLIMIT_AS, &current) && current.rlim_cur != RLIM_INFINITY) limit = (uint64_t)current.rlim_cur;
    uint64_t budget = core_start_memory_limit();
    const uint64_t headroom = 256u << 20;
    if (budget && budget <= UINT64_MAX - headroom && budget + headroom < limit) limit = budget + headroom;
    if (limit == UINT64_MAX || need <= limit) return;
    char reserved[64];
    if (addressable) snprintf(reserved, sizeof reserved, "%.1f GiB of native stack", (double)need / 1073741824.0);
    else snprintf(reserved, sizeof reserved, "more native stack than can be addressed");
    flush_all();
    fprintf(stderr, "mylang: a call-depth budget of %llu frames (--max-frames) reserves %s (32 KiB per frame), but this process may map only %.1f GiB; "
        "raise --max-memory (and MYLANG_HOST_MEMORY_LIMIT, which a guest inherits) or lower --max-frames\n", (unsigned long long)frames, reserved, (double)limit / 1073741824.0);
    fflush(stderr);
    os_exit(2);
}
/* A budget this build cannot enforce: the old core's report and record, status 1. */
static void core_start_refuse(const char *code, const char *description, const char *advice) {
    char text[512];
    int length = snprintf(text, sizeof text, "error[%s]: %s: %s\n", code, description, advice);
    stream_write(&streams[1], text, (size_t)(length < (int)sizeof text ? length : (int)sizeof text - 1));
    char record[512];
    stream_write(&streams[1], record, core_operation_record(record, sizeof record, advice));
    flush_all();
    os_exit(1);
}
/* Read a built program's runtime options before `main` runs, as the old core read them
   (NATIVE-ARGV-1): grants and `--print-result` are their readers' (`core_io_initialize`,
   `myl_core_exit`), `--timeout=SECONDS` arms the wall-clock guard, and an unknown option
   or an unterminated quote ends the process with status 2. A built program carries no
   step or frame accounting (`mylang run` compiles a budget in instead), so
   `--max-steps`/`--max-frames` are refused rather than ignored: `R_NO_STEP_ACCOUNTING`,
   `R_NO_FRAME_ACCOUNTING`, after a frame reservation the address space cannot back. */
/* ---- The native stack's floor (QBE-FRAMEMAP-1) ------------------------------------
 * A program without a frame budget recurses until the stack's guard page. The fault is
 * reported as the old core's stack-floor guard reports it: `R_FRAME_LIMIT` located at the
 * innermost call site, with at most 16 frames, exit status 1. Any other fault keeps
 * its default action. The report runs on its own signal stack. */
enum { CORE_FLOOR_FRAMES = 16 };
static uintptr_t core_stack_top;
/* The report's signal stack is mapped at start, not a 256 KiB .bss array: a static array
   that large moves where the program's heap begins, which made allocation-heavy rows run
   slower or faster from one run to the next. */
enum { CORE_FLOOR_STACK = 256 << 10 };
static void core_floor_default(int signal_number) {
    signal(signal_number, SIG_DFL);
}
static void core_floor_fault(int signal_number, siginfo_t *info, void *context) {
    (void)context;
    struct rlimit limit;
    uintptr_t at = (uintptr_t)info->si_addr;
    const uintptr_t slack = 1u << 20;
    bool overflow = core_stack_top && !getrlimit(RLIMIT_STACK, &limit) && limit.rlim_cur != RLIM_INFINITY && at <= core_stack_top &&
        core_stack_top - at + slack >= (uintptr_t)limit.rlim_cur && core_stack_top - at <= (uintptr_t)limit.rlim_cur + slack;
    if (!overflow) {
        core_floor_default(signal_number);
        return;
    }
    void *pcs[160];
    int count = os_stack(pcs, 160);
    /* The interrupted instruction follows the signal frame: a `call` that could not push
       its return address is the caller's own call site; anything else is the prologue of
       the frame it would have entered, which is not reported. */
    char caller[1024] = "";
    trap_capture = caller;
    trap_capture_size = sizeof caller;
    int first = 0;
    while (first < count && dwarf_frames((uintptr_t)pcs[first], 0) == 0) ++first;
    bool calling = first < count && *(const unsigned char *)pcs[first] == 0xe8;
    if (first < count && !calling) {
        caller[0] = 0;
        ++first;
        if (first < count) dwarf_frames((uintptr_t)pcs[first] - 1, 0);
    }
    trap_capture = NULL;
    const char *where = strstr(caller, " at ");
    size_t named = strlen(caller);
    char text[1400];
    int length = where && named > 1 ? snprintf(text, sizeof text, "%.*s: error[R_FRAME_LIMIT]: %s\n", (int)(caller + named - 1 - (where + 4)), where + 4, core_budget_hint("R_FRAME_LIMIT"))
                                    : snprintf(text, sizeof text, "error[R_FRAME_LIMIT]: %s\n", core_budget_hint("R_FRAME_LIMIT"));
    stream_flush(&streams[0]);
    stream_write(&streams[1], text, (size_t)(length < (int)sizeof text ? length : (int)sizeof text - 1));
    trap_lines_left = CORE_FLOOR_FRAMES;
    for (int i = first; i < count && trap_lines_left != 0; ++i) {
        uintptr_t pc = (uintptr_t)pcs[i] - (i == first && calling ? 0 : 1);
        if (dwarf_frames(pc, 0) == 0) break;
    }
    flush_all();
    _exit(1);
}
static void core_floor_install(void) {
    unsigned char here;
    core_stack_top = (uintptr_t)&here;
    void *floor_stack = mmap(NULL, CORE_FLOOR_STACK, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (floor_stack == MAP_FAILED) return;
    stack_t alternate = { .ss_sp = floor_stack, .ss_size = CORE_FLOOR_STACK, .ss_flags = 0 };
    if (sigaltstack(&alternate, NULL)) return;
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = core_floor_fault;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    (void)sigaction(SIGSEGV, &action, NULL);
}
void myl_core_start(void) {
    core_floor_install();
    const char *options = getenv("MYLANG_OPTIONS");
    if (!options || !*options) return;
    char *copy = strdup(options);
    if (!copy) out_of_memory();
    char *cursor = copy, *arg;
    uint64_t steps = 0, frames = 0, timeout = 0;
    while ((arg = core_io_next_option(&cursor))) {
        if (!strcmp(arg, "--print-result") || !strcmp(arg, "--restrict") || !strncmp(arg, "--allow-", 8)) continue;
        if (core_start_budget(arg, "--max-steps=", &steps) || core_start_budget(arg, "--max-frames=", &frames) || core_start_budget(arg, "--timeout=", &timeout)) continue;
        core_io_option_error("mylang: MYLANG_OPTIONS names %s, which is not a runtime option\n", arg);
    }
    free(copy);
    if (frames) core_start_frame_reservation(frames);
    if (steps) core_start_refuse("R_NO_STEP_ACCOUNTING", "this build omits instruction-budget accounting", "run it under `mylang run --max-steps=N`");
    if (frames) core_start_refuse("R_NO_FRAME_ACCOUNTING", "this build omits call-depth accounting", "run it under `mylang run --max-frames=N`");
    if (timeout) core_run_arm(timeout);
}
void myl_core_test_enter(void) {
    if (++core_test_depth > core_test_frame_limit && core_test_frame_limit) core_io_fail("R_FRAME_LIMIT");
}
void myl_core_test_leave(void) { --core_test_depth; }
/* The program frames live now, when a frame budget counts them; else 0. */
static uint64_t core_test_frames_live(void) {
    if (!core_test_frame_limit) return 0;
    return core_test_depth > core_test_frame_limit ? core_test_frame_limit : core_test_depth;
}
static void (*core_test_body)(void);
static void core_test_launch(void) { core_test_body(); }
/* Run `trial` on the budget's stack, with one guard page below it. A mapping the
 * address space cannot hold is refused the way the old runtime refuses it. */
static void core_test_on_stack(void (*trial)(void)) {
    if (!core_test_frame_limit) { trial(); return; }
    long page_size = sysconf(_SC_PAGESIZE);
    size_t page = page_size > 0 ? (size_t)page_size : 4096;
    size_t usable = ((size_t)core_test_frame_limit * CORE_TEST_FRAME_STACK + CORE_TEST_STACK_SLACK + page - 1) / page * page;
    unsigned char *mapping = aligned_alloc(page, usable + page);
    ucontext_t caller, callee;
    if (!mapping || mprotect(mapping, page, PROT_NONE) || getcontext(&callee)) {
        flush_all();
        fprintf(stderr, "mylang: a call-depth budget of %llu frames (--max-frames) reserves %.1f GiB of native stack (32 KiB per frame), "
            "but the test's address space cannot hold it; raise --max-memory or lower --max-frames\n", (unsigned long long)core_test_frame_limit, (double)usable / 1073741824.0);
        fflush(stderr);
        _exit(1);
    }
    callee.uc_stack.ss_sp = mapping + page;
    callee.uc_stack.ss_size = usable;
    callee.uc_stack.ss_flags = 0;
    callee.uc_link = &caller;
    core_test_body = trial;
    makecontext(&callee, core_test_launch, 0);
    if (swapcontext(&caller, &callee)) _exit(70);
    /* The child exits after its trial; the mapping is never reused or freed. */
}
static uint64_t core_test_word(FILE *file) {
    unsigned char bytes[8];
    if (!file || fread(bytes, 1, 8, file) != 8) _exit(70);
    uint64_t word = 0;
    for (unsigned i = 0; i < 8; ++i) word |= (uint64_t)bytes[i] << (8 * i);
    return word;
}
static void core_test_put(FILE *file, uint64_t word) {
    unsigned char bytes[8];
    for (unsigned i = 0; i < 8; ++i) bytes[i] = (unsigned char)(word >> (8 * i));
    if (!file || fwrite(bytes, 1, 8, file) != 8) _exit(70);
}
uint64_t myl_core_test_read(void) { return core_test_word(core_test_input); }
void myl_core_test_write(uint64_t word) { core_test_put(core_test_values, word); }
bool myl_core_test_read_bool(void){uint64_t bits=myl_core_test_read();(void)myl_core_test_read();return bits!=0;}
void myl_core_test_write_bool(bool value){myl_core_test_write(value?1:0);myl_core_test_write(0);}
double myl_core_test_read_float(void) {
    uint64_t bits = myl_core_test_read(); (void)myl_core_test_read();
    double value; memcpy(&value, &bits, 8); return value;
}
void myl_core_test_write_float(double value) {
    uint64_t bits; memcpy(&bits, &value, 8);
    myl_core_test_write(bits); myl_core_test_write(0);
}
static unsigned core_test_scalar(unsigned char *out, uint32_t point) {
    if (point < 0x80) {out[0]=(unsigned char)point; return 1;}
    if (point < 0x800) {out[0]=(unsigned char)(0xc0|(point>>6));out[1]=(unsigned char)(0x80|(point&63));return 2;}
    if (point < 0x10000 && !(point>=0xd800 && point<=0xdfff)) {
        out[0]=(unsigned char)(0xe0|(point>>12));out[1]=(unsigned char)(0x80|((point>>6)&63));out[2]=(unsigned char)(0x80|(point&63));return 3;
    }
    if (point<=0x10ffff) {
        out[0]=(unsigned char)(0xf0|(point>>18));out[1]=(unsigned char)(0x80|((point>>12)&63));out[2]=(unsigned char)(0x80|((point>>6)&63));out[3]=(unsigned char)(0x80|(point&63));return 4;
    }
    _exit(70);
}
static myl_block *core_test_read_octets(bool bytes) {
    (void)myl_core_test_read(); uint64_t count=myl_core_test_read();
    if (count>4096) _exit(70);
    size_t capacity=(size_t)count*(bytes?1:4);
    myl_block *text=block_new(bytes?MYL_KIND_BYTES:MYL_KIND_STR,(int64_t)capacity+1,1);
    size_t used=0;
    for(uint64_t i=0;i<count;++i){
        uint64_t point=myl_core_test_read(); (void)myl_core_test_read();
        if(bytes){if(point>255)_exit(70);block_data(text)[used++]=(unsigned char)point;}
        else used+=core_test_scalar(block_data(text)+used,(uint32_t)point);
    }
    text->len=(int64_t)used;block_data(text)[used]=0;
    if(!bytes)core_text_publish(text);
    return text;
}
myl_block *myl_core_test_read_text(void){return core_test_read_octets(false);}
myl_block *myl_core_test_read_bytes(void){return core_test_read_octets(true);}
void myl_core_test_write_text(myl_block *text,uint32_t bytes){
    const unsigned char *p=block_data(text);size_t n=(size_t)text->len;
    uint64_t count=0;
    if(bytes)count=n;else for(size_t i=0;i<n;++i)if((p[i]&0xc0)!=0x80)++count;
    myl_core_test_write(0);myl_core_test_write(count);
    for(size_t i=0;i<n;){
        uint32_t point=p[i++];
        if(!bytes&&point>=0xc0){
            unsigned tails=point<0xe0?1:point<0xf0?2:3;
            point&=tails==1?31:tails==2?15:7;
            for(unsigned j=0;j<tails;++j){if(i>=n)_exit(70);point=(point<<6)|(p[i++]&63);}
        }
        myl_core_test_write(point);myl_core_test_write(0);
    }
}
static char *core_test_named(const char *suffix){
    size_t a=strlen(core_test_path),b=strlen(suffix);char *path=malloc(a+b+1);
    if(!path)out_of_memory();memcpy(path,core_test_path,a);memcpy(path+a,suffix,b+1);return path;
}
static void core_test_copy(FILE *target,FILE *source){
    if(fflush(source)||fseek(source,0,SEEK_END))_exit(70);
    long size=ftell(source);if(size<0||fseek(source,0,SEEK_SET))_exit(70);
    core_test_put(target,(uint64_t)size);
    unsigned char bytes[4096];size_t count;
    while((count=fread(bytes,1,sizeof bytes,source)))if(fwrite(bytes,1,count,target)!=count)_exit(70);
}
static void core_test_capture(const char *suffix,int descriptor){
    char *path=core_test_named(suffix);int fd=open(path,O_RDWR|O_CREAT|O_TRUNC,0600);free(path);
    if(fd<0||dup2(fd,descriptor)<0)_exit(70);close(fd);
}
static void core_test_file(FILE *target,const char *suffix){
    char *path=core_test_named(suffix);FILE *file=fopen(path,"rb");free(path);
    if(!file){core_test_put(target,0);return;}core_test_copy(target,file);fclose(file);
}
static void core_test_record(uint64_t status,FILE *values){
    core_test_put(core_test_output,status);
    if(values)core_test_copy(core_test_output,values);else core_test_put(core_test_output,0);
    core_test_file(core_test_output,".out");core_test_file(core_test_output,".err");core_test_file(core_test_output,".trace");
    if(fflush(core_test_output))_exit(70);
}
static bool core_test_trapped(void){
    char *path=core_test_named(".err");FILE *file=fopen(path,"rb");free(path);
    if(!file)return false;
    static const unsigned char marker[]="\036MYLANG-TRAP ";
    unsigned matched=0;int byte;bool found=false;
    while((byte=fgetc(file))!=EOF){
        if(byte==marker[matched]){
            if(marker[++matched]==0){found=true;break;}
        }else matched=byte==marker[0]?1:0;
    }
    fclose(file);return found;
}
static void core_test_stderr(void){
    char *path=core_test_named(".err");FILE *file=fopen(path,"rb");free(path);
    if(!file)return;
    unsigned char bytes[4096];size_t count;
    while((count=fread(bytes,1,sizeof bytes,file)))if(fwrite(bytes,1,count,stderr)!=count)_exit(70);
    fclose(file);if(fflush(stderr))_exit(70);
}
/* Source traces are kept apart from arbitrary stderr output. */
void myl_core_test_trace(void){
    stream_flush(&streams[1]);int saved=dup(2);core_test_capture(".trace",2);
    trace_write();stream_flush(&streams[1]);if(dup2(saved,2)<0)_exit(70);close(saved);
}
/* The executable's dispatch table (NEW-CORE-TEST-BATCH-1): its entry registers every
 * selected test's trial wrapper in table order before serving one request, and each
 * trial of the request names the row it calls, so one process answers several tests. */
static void (**core_test_table)(void);
static uint64_t core_test_rows,core_test_capacity;
void myl_core_test_register(void (*trial)(void)){
    if(core_test_rows==core_test_capacity){
        uint64_t capacity=core_test_capacity?core_test_capacity*2:64;
        void (**grown)(void)=realloc(core_test_table,(size_t)capacity*sizeof *grown);
        if(!grown)out_of_memory();
        core_test_table=grown;core_test_capacity=capacity;
    }
    core_test_table[core_test_rows++]=trial;
}
bool myl_core_test_open(myl_block *input,myl_block *output){
    core_test_input=fopen((const char *)block_data(input),"rb");
    core_test_output=fopen((const char *)block_data(output),"wb");
    core_test_path=strdup((const char *)block_data(output));
    core_trap_marks_all=true;
    if(!core_test_input||!core_test_output||!core_test_path)return false;
    core_test_trials=core_test_word(core_test_input);return true;
}
int64_t myl_core_test_run(void){
    for(uint64_t i=0;i<core_test_trials;++i){
        uint64_t row=core_test_word(core_test_input);
        if(row>=core_test_rows)_exit(70);
        void (*trial)(void)=core_test_table[row];
        uint64_t words=core_test_word(core_test_input);long start=ftell(core_test_input);
        if(words>1000000||start<0)_exit(70);
        const char *suffixes[]={".out",".err",".trace"};
        for(unsigned j=0;j<3;++j){char *path=core_test_named(suffixes[j]);FILE *empty=fopen(path,"wb");free(path);if(empty)fclose(empty);}
        flush_all();if(fflush(NULL))_exit(70);
        int64_t baseline=live_count();pid_t parent=getpid();pid_t child=fork();if(child<0)_exit(70);
        if(child==0){
#if defined(__linux__)
            if(prctl(PR_SET_PDEATHSIG,SIGKILL)<0||getppid()!=parent)_exit(70);
#else
            (void)parent;
#endif
            core_test_values=tmpfile();if(!core_test_values)_exit(70);
            core_test_capture(".out",1);core_test_capture(".err",2);
            alarm(60);error_trace.origin=NULL;error_trace.count=0;core_test_on_stack(trial);alarm(0);flush_all();
            core_io_cleanup();
            const char *check=getenv("MYL_CORE_LEAKCHECK");
            if(check&&strcmp(check,"0")&&live_count()!=baseline){
                fprintf(stderr,"myl-core leakcheck: %lld blocks remain after trial\n",(long long)(live_count()-baseline));fflush(stderr);
                core_test_record(4,core_test_values);_exit(0);
            }
            core_test_record(0,core_test_values);_exit(0);
        }
        int status;while(waitpid(child,&status,0)<0){if(errno!=EINTR)_exit(70);}
        if(WIFSIGNALED(status)){
            /* A signal cuts off the batch exactly like the old harness. Its
             * completed prefix is durable; the Zig search retries this input
             * alone before classifying it or adopting a shrink candidate. */
            int caught=WTERMSIG(status);core_test_stderr();fclose(core_test_input);fclose(core_test_output);
            signal(caught,SIG_DFL);raise(caught);_exit(70);
        }
        if(WEXITSTATUS(status)!=0){
            if(core_test_trapped())core_test_record(1,NULL);
            else {
                /* An arbitrary native exit did not answer this trial. Keep
                 * its status and the completed prefix for old retry grading. */
                int code=WEXITSTATUS(status);core_test_stderr();fclose(core_test_input);fclose(core_test_output);_exit(code);
            }
        }
        if(fseek(core_test_input,start+(long)(words*8),SEEK_SET))_exit(70);
    }
    fclose(core_test_input);fclose(core_test_output);free(core_test_path);
    core_test_input=NULL;core_test_output=NULL;core_test_path=NULL;return 0;
}
