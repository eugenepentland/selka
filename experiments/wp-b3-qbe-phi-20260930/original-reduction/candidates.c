#include <stdint.h>
#include <stdio.h>
#include <inttypes.h>
__attribute__((noinline)) static void prime_stack(void) { volatile uint64_t dust[128]; for(unsigned i=0;i<128;i++) dust[i]=UINT64_C(0x9876543212345678); __asm__ volatile("" : : "m"(dust) : "memory"); }
typedef uint64_t (*Test)(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce1(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce2(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce3(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce4(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce5(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce6(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce7(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce8(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce9(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce10(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce11(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce12(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce13(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce14(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce15(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce16(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce17(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce18(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce19(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce20(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce21(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce22(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce23(uint64_t,uint64_t *,uint64_t *);
extern uint64_t reduce24(uint64_t,uint64_t *,uint64_t *);
int main(void) {
 const Test tests[]={reduce1,reduce2,reduce3,reduce4,reduce5,reduce6,reduce7,reduce8,reduce9,reduce10,reduce11,reduce12,reduce13,reduce14,reduce15,reduce16,reduce17,reduce18,reduce19,reduce20,reduce21,reduce22,reduce23,reduce24};
 uint64_t values[24],sum=0; for(unsigned i=0;i<24;i++) values[i]=i+1;
 for(unsigned n=1;n<=24;n++) {
  sum+=values[n-1]; unsigned failures=0;
  for(unsigned x=0;x<2;x++) { uint64_t out=0; prime_stack(); uint64_t actual=tests[n-1](x,values,&out),expected=sum+x;
   if(actual!=expected) failures++; printf("N=%u x=%u got=%"PRIu64" expected=%"PRIu64" branch=%u\n",n,x,actual,expected,(unsigned)out);
  }
  printf("SUMMARY N=%u failed=%u\n",n,failures);
 }
 return 0;
}
