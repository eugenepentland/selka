/* The bare runtime's platform hooks for QEMU's mps2-an385 board (a Cortex-M3; the image is built for the
 * Cortex-M0+ and runs unchanged), through Arm semihosting: `myl_bare_write` writes to QEMU's own standard output or
 * standard error and `myl_bare_exit` ends QEMU with the program's status (SYS_EXIT_EXTENDED). Run QEMU with
 * `-semihosting-config enable=on,target=native`. */
#include <stddef.h>
#include <stdint.h>

static int semihost(int operation, const void *argument) {
    register int r0 __asm__("r0") = operation;
    register const void *r1 __asm__("r1") = argument;
    __asm__ volatile("bkpt 0xab" : "+r"(r0) : "r"(r1) : "memory");
    return r0;
}

enum { SYS_OPEN = 0x01, SYS_WRITE = 0x05, SYS_EXIT_EXTENDED = 0x20 };

/* The Cortex-M3 allows most unaligned loads and stores; the Cortex-M0+ faults on every one. Trap them here too
   (SCB CCR.UNALIGN_TRP), so QEMU refuses what the RP2040 refuses. */
void myl_bare_platform_start(void) { *(volatile uint32_t *)0xE000ED14u |= 1u << 3; }

/* ":tt" opened for writing is standard output, opened for appending standard error. */
static int handles[2] = {-1, -1};

void myl_bare_write(int stream, const unsigned char *bytes, size_t length) {
    const int which = stream == 2 ? 1 : 0;
    if (handles[which] < 0) {
        const uint32_t open[3] = {(uint32_t)(uintptr_t)":tt", which ? 8u : 4u, 3u};
        handles[which] = semihost(SYS_OPEN, open);
    }
    const uint32_t write[3] = {(uint32_t)handles[which], (uint32_t)(uintptr_t)bytes, (uint32_t)length};
    (void)semihost(SYS_WRITE, write);
}

__attribute__((noreturn)) void myl_bare_exit(int status) {
    const uint32_t stop[2] = {0x20026u /* ADP_Stopped_ApplicationExit */, (uint32_t)status};
    for (;;) (void)semihost(SYS_EXIT_EXTENDED, stop);
}
