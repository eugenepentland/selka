/* Core-owned property trial transport. The old generation/counting/shrinking
 * algorithms stay in Zig. Fork gives a fatal Core trap a bounded copied-value
 * trial boundary without skipping reference-count cleanup on a longjmp. */
#include <sys/wait.h>
#include <sys/resource.h>
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
void myl_core_test_limits(uint64_t steps, uint32_t timeout_ms) {
    core_test_steps=steps;core_test_bounded=steps!=0;
    alarm((unsigned)((uint64_t)timeout_ms+999)/1000);
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
void myl_core_test_enter(void) {
    if (++core_test_depth > core_test_frame_limit && core_test_frame_limit) core_io_fail("R_FRAME_LIMIT");
}
void myl_core_test_leave(void) { --core_test_depth; }
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
bool myl_core_test_open(myl_block *input,myl_block *output){
    core_test_input=fopen((const char *)block_data(input),"rb");
    core_test_output=fopen((const char *)block_data(output),"wb");
    core_test_path=strdup((const char *)block_data(output));
    if(!core_test_input||!core_test_output||!core_test_path)return false;
    core_test_trials=core_test_word(core_test_input);return true;
}
int64_t myl_core_test_run(void (*trial)(void)){
    for(uint64_t i=0;i<core_test_trials;++i){
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
