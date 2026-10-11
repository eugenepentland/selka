/* Developer-only bounded native fixture: capture authentic exchanges or forge replies. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/wait.h>
#define LIMIT (64u * 1024u * 1024u)
static int copy(FILE *from, FILE *to) {
    unsigned char bytes[8192]; size_t n, total = 0;
    while ((n = fread(bytes, 1, sizeof bytes, from))) {
        total += n;
        if (total > LIMIT || fwrite(bytes, 1, n, to) != n) return 2;
    }
    return ferror(from) ? 2 : 0;
}
static void put(unsigned char *p, uint32_t value) {
    for (unsigned i=0;i<4;i++) p[i]=(unsigned char)(value>>(i*8));
}
int main(int argc, char **argv) {
    if (argc != 3 || strcmp(argv[1], "--exchange")) return 2;
    const char *forge=getenv("BODY_REPLY");
    if (forge) {
        FILE *request=fopen(argv[2],"rb"), *reply=fopen(forge,"rb");
        unsigned char header[64];
        if (!request || !reply || fread(header,1,64,request)!=64) return 2;
        if (fseek(reply,0,SEEK_END)!=0) return 2;
        long size=ftell(reply);
        if (size<0 || size>LIMIT-64 || fseek(reply,0,SEEK_SET)!=0) return 2;
        put(header+16,1);put(header+20,(uint32_t)size);
        if (fwrite(header,1,64,stdout)!=64 || copy(reply,stdout)) return 2;
        return fclose(request) || fclose(reply) ? 2 : 0;
    }
    const char *real=getenv("BODY_REAL"), *request_path=getenv("BODY_REQUEST"), *reply_path=getenv("BODY_CAPTURE");
    if (!real || !request_path || !reply_path) return 2;
    FILE *request=fopen(argv[2],"rb"), *saved=fopen(request_path,"wb"), *capture=fopen(reply_path,"w+b");
    if (!request || !saved || !capture || copy(request,saved) || fclose(saved) || fclose(request)) return 2;
    pid_t child=fork();
    if (child<0) return 2;
    if (!child) {
        if (dup2(fileno(capture),STDOUT_FILENO)<0) _exit(2);
        execl(real,real,"--exchange",argv[2],(char *)0);_exit(2);
    }
    int status;
    if (waitpid(child,&status,0)!=child || !WIFEXITED(status) || WEXITSTATUS(status)) return 2;
    const char *mutate=getenv("BODY_MUTATE");
    if (mutate && unlink(mutate)) return 2;
    if (fseek(capture,0,SEEK_SET) || copy(capture,stdout)) return 2;
    return fclose(capture) ? 2 : 0;
}
