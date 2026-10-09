#include "core_rt_all.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *make(size_t chars) {
    size_t n = chars * 2; char *buf = malloc(n);
    for (size_t i = 0; i < chars; ++i) { buf[2*i] = (char)0xc3; buf[2*i+1] = (char)0xa9; }
    myl_block *t = str_from(buf, n); free(buf); return t;
}
int main(void) {
    for (int shared = 0; shared < 2; ++shared) {
        myl_block *t = make(20000);
        if (shared) myl_core_share(t);
        uint64_t before = core_text_walked;
        uint64_t sum = 0;
        for (uint64_t i = 0; i < 20000; ++i) sum += myl_core_str_offset(t, i);
        printf("%s: octets walked for 20000 sequential s[i] = %llu (sum %llu)\n", shared ? "shared" : "plain ", (unsigned long long)(core_text_walked - before), (unsigned long long)sum);
    }
    return 0;
}
