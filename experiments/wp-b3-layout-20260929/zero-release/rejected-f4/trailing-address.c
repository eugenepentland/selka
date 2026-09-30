#include <stdint.h>
#include <stdio.h>
uint64_t review_global[2]={123,456};
extern int trailing_address(uint64_t,uint64_t,uint64_t*);
int main(void) {
 uint64_t out[2]={0};int got=trailing_address(UINT64_MAX,1,out);
 printf("zero result: got=%d expected=0 payload=%llu branch=%llu\n",got,(unsigned long long)out[0],(unsigned long long)out[1]);
 return got!=0 || out[0]!=456 || out[1]!=23;
}
