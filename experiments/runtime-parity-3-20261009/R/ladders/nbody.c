/* R6: same five-body arithmetic and checksum, dynamic N versus fixed-N facts.
 * Build with -O3 -ffp-contract=off and -DRUNG=0/1/2. Rung 2 explicitly asks
 * LLVM to unroll the fixed pair loop; no unsafe floating-point flags. */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#ifndef RUNG
#define RUNG 0
#endif
typedef struct { double x,y,z,vx,vy,vz,mass; } Body;
static const double pi=3.141592653589793, dpy=365.24;
static double energy(Body *b, size_t n) {
    double e=0;
    for(size_t i=0;i<n;i++) {
        e += 0.5*b[i].mass*(b[i].vx*b[i].vx+b[i].vy*b[i].vy+b[i].vz*b[i].vz);
        for(size_t j=i+1;j<n;j++) {
            double dx=b[i].x-b[j].x,dy=b[i].y-b[j].y,dz=b[i].z-b[j].z;
            e -= b[i].mass*b[j].mass/sqrt(dx*dx+dy*dy+dz*dz);
        }
    }
    return e;
}
__attribute__((noinline)) static void advance(Body *b, size_t length) {
    const size_t n=RUNG ? 5 : length;
#if RUNG == 2
#pragma clang loop unroll(full)
#endif
    for(size_t i=0;i<n;i++) {
#if RUNG == 2
#pragma clang loop unroll(full)
#endif
        for(size_t j=i+1;j<n;j++) {
            double dx=b[i].x-b[j].x,dy=b[i].y-b[j].y,dz=b[i].z-b[j].z;
            double d2=dx*dx+dy*dy+dz*dz,mag=0.01/(d2*sqrt(d2));
            b[i].vx-=dx*b[j].mass*mag; b[i].vy-=dy*b[j].mass*mag; b[i].vz-=dz*b[j].mass*mag;
            b[j].vx+=dx*b[i].mass*mag; b[j].vy+=dy*b[i].mass*mag; b[j].vz+=dz*b[i].mass*mag;
        }
    }
    for(size_t i=0;i<n;i++) { b[i].x+=0.01*b[i].vx; b[i].y+=0.01*b[i].vy; b[i].z+=0.01*b[i].vz; }
}
int main(int argc,char **argv) {
    size_t n=argc>1 ? (size_t)strtoul(argv[1],0,10) : 5;
    if(n!=5) return 2;
    double sm=4.0*pi*pi;
    Body b[5]={
        {0,0,0,0,0,0,sm},
        {4.84143144246472090,-1.16032004402742839,-0.103622044471231109,0.00166007664274403694*dpy,0.00769901118419740425*dpy,-0.0000690460016972063023*dpy,0.000954791938424326609*sm},
        {8.34336671824457987,4.12479856412430479,-0.403523417114321381,-0.00276742510726862411*dpy,0.00499852801234917238*dpy,0.0000230417297573763929*dpy,0.000285885980666130812*sm},
        {12.8943695621391310,-15.1111514016986312,-0.223307578892655734,0.00296460137564761618*dpy,0.00237847173959480950*dpy,-0.0000296589568540237556*dpy,0.0000436624404335156298*sm},
        {15.3796971148509165,-25.9193146099879641,0.179258772950371181,0.00268067772490389322*dpy,0.00162824170038242295*dpy,-0.0000951592254519715870*dpy,0.0000515138902046611451*sm}
    };
    double px=0,py=0,pz=0;
    for(size_t i=0;i<n;i++) { px+=b[i].vx*b[i].mass; py+=b[i].vy*b[i].mass; pz+=b[i].vz*b[i].mass; }
    b[0].vx=-px/sm; b[0].vy=-py/sm; b[0].vz=-pz/sm;
    printf("%lld\n",(long long)(energy(b,n)*1e9));
    /* Volatile prevents main's n==5 guard specializing rung 0 across the call. */
    volatile size_t unknown=n;
    for(size_t step=0;step<5000000;step++) advance(b,unknown);
    printf("%lld\n",(long long)(energy(b,n)*1e9));
}
