#define _GNU_SOURCE
#include "native_bytes.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>
int main(void) {
    size_t page=(size_t)sysconf(_SC_PAGESIZE);
    unsigned char *base=mmap(NULL,page*3,PROT_NONE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    assert(base!=MAP_FAILED && !mprotect(base+page,page,PROT_READ|PROT_WRITE));
    for(size_t i=0;i<page;i++)base[page+i]=(unsigned char)(i*37+11);
    uint64_t checksum=0; size_t cases=0;
    for(size_t length=0;length<=1041;length++)for(unsigned mask=0;mask<256;mask++) {
        const unsigned char *start=base+2*page-length;
        uint64_t expected=0;
        for(size_t i=0;i<length;i++)expected+=(unsigned char)(start[i]^mask);
        assert(myl_native_bytes_sum_xor(start,length,mask)==expected);
        checksum+=expected; cases++;
    }
    assert(myl_native_bytes_sum_xor(NULL,0,255)==0);
    assert(!munmap(base,page*3));
    printf("cases=%zu checksum=%llu\n",cases,(unsigned long long)checksum);
}
