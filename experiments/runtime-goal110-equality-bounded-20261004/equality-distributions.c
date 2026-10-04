#define _POSIX_C_SOURCE 200809L
#include "native_text.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
/* A diagnostic of the actual runtime comparator, independent of the frozen
 * four-pair fixture. Build the same harness against before/after native_text.c.
 * Each pair has a distinct payload. Modes cover equal values, first/middle/last
 * differences, and varying mismatch positions; arguments also select views and
 * valid multi-octet UTF-8. This is helper timing, not campaign acceptance. */
enum { PAIRS=256 };
static uint64_t now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC,&t)) abort();
    return (uint64_t)t.tv_sec*UINT64_C(1000000000)+(uint64_t)t.tv_nsec;
}
int main(int argc, char **argv) {
    if (argc!=6) return 2;
    const size_t length=(size_t)strtoull(argv[1],NULL,10);
    const unsigned mode=(unsigned)strtoul(argv[2],NULL,10);
    const int views=atoi(argv[3]), wide=atoi(argv[4]);
    const size_t iterations=(size_t)strtoull(argv[5],NULL,10);
    if (length>65536 || mode>4 || !iterations) return 2;
    myl_native_text *left[PAIRS], *right[PAIRS];
    myl_native_text_view left_views[PAIRS], right_views[PAIRS];
    for (size_t pair=0;pair<PAIRS;pair++) {
        const size_t offset=views ? 1+pair%7 : 0;
        left[pair]=malloc(sizeof(myl_native_text)+offset+length);
        right[pair]=malloc(sizeof(myl_native_text)+offset+length);
        if (!left[pair] || !right[pair]) abort();
        const size_t scalars=wide?(length+1)/2:length;
        *left[pair]=(myl_native_text){.length=offset+scalars,.bytes=offset+length,.flags=wide?0:MYL_TEXT_ASCII};
        *right[pair]=*left[pair];
        memset(left[pair]+1,'z',offset); memset(right[pair]+1,'z',offset);
        unsigned char *a=(unsigned char *)(left[pair]+1)+offset;
        unsigned char *b=(unsigned char *)(right[pair]+1)+offset;
        for (size_t at=0;at<length;at++) {
            if (wide && at+1<length) { a[at]=b[at]=0xc3; at++; a[at]=b[at]=(unsigned char)(0xa0+(pair%16)); }
            else a[at]=b[at]=(unsigned char)('a'+(pair+at)%23);
        }
        if (mode && length) {
            size_t at=mode==1?0:mode==2?length/2:mode==3?length-1:pair%length;
            /* Change a continuation's low bit, or change an ASCII scalar.
             * The UTF-8 lead remains the same, so both texts stay valid. */
            if (wide && b[at]==0xc3) at++;
            b[at]^=1;
        }
        if (views) {
            left_views[pair]=(myl_native_text_view){.text={.length=scalars,.bytes=length,.flags=MYL_TEXT_VIEW|(wide?0:MYL_TEXT_ASCII),.hash=(uint32_t)offset},.owner=left[pair]};
            right_views[pair]=left_views[pair]; right_views[pair].owner=right[pair];
        }
    }
    uint64_t checksum=0, start=now();
    for (size_t i=0;i<iterations;i++) {
        const size_t pair=(i*137)&(PAIRS-1);
        checksum+=(unsigned)myl_native_text_equal(views?&left_views[pair].text:left[pair],views?&right_views[pair].text:right[pair]);
    }
    const uint64_t elapsed=now()-start;
    printf("%llu %llu\n",(unsigned long long)checksum,(unsigned long long)elapsed);
    for (size_t pair=0;pair<PAIRS;pair++) { free(right[pair]); free(left[pair]); }
    return checksum==((!mode || !length)?iterations:0)?0:1;
}
