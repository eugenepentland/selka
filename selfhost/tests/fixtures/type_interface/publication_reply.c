/* Developer-only native boundary race; forwards an unchanged valid reply. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
int main(int argc, char **argv) {
    const char *real = getenv("TYPE_INTERFACE_REAL");
    const char *mutate = getenv("TYPE_INTERFACE_MUTATE");
    if (argc != 3 || strcmp(argv[1], "--exchange") || !real || !mutate) return 2;
    const char *capture_path = getenv("TYPE_INTERFACE_CAPTURE");
    if (!capture_path) return 2;
    FILE *capture = fopen(capture_path, "w+b");
    if (!capture) return 2;
    pid_t child = fork();
    if (child < 0) return 2;
    if (child == 0) {
        if (dup2(fileno(capture), STDOUT_FILENO) < 0) _exit(2);
        execl(real, real, "--exchange", argv[2], (char *)0);
        _exit(2);
    }
    int status = 0;
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) return 2;
    if (unlink(mutate) != 0 || fseek(capture, 0, SEEK_SET) != 0) return 2;
    unsigned char buffer[8192];
    size_t total = 0, count;
    while ((count = fread(buffer, 1, sizeof(buffer), capture)) != 0) {
        total += count;
        if (total > 64u * 1024u * 1024u || fwrite(buffer, 1, count, stdout) != count) return 2;
    }
    return ferror(capture) || fclose(capture) != 0 ? 2 : 0;
}
