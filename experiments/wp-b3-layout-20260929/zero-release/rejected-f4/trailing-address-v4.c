#include <stdint.h>
#include <stdio.h>
uint64_t review_global[2]={123,456};
extern uint64_t trailing_address(uint64_t,uint64_t,uint64_t*);
int main(void) {
 uint64_t out=0;uint64_t payload=trailing_address(UINT64_MAX,1,&out);
 printf("zero result: payload=%llu expected=456 branch=%llu expected=23\n",(unsigned long long)payload,(unsigned long long)out);
 return payload!=456 || out!=23;
}
