#include <assert.h>
#include <stdint.h>
#include <stdio.h>
extern int byte_guard(void*);
int main(void) { uint64_t guards[16]={0}; uint32_t inputs[]={0,1,8,16,65536,0x80000000u,0xffffffffu};
 for(unsigned i=0;i<sizeof(inputs)/sizeof(inputs[0]);i++){guards[40/8]=inputs[i]; int result=byte_guard(guards); assert(result==(inputs[i]==0));assert(guards[40/8]==inputs[i]);printf("%u %d %llu\n",inputs[i],result,(unsigned long long)guards[40/8]);}return 0;}
