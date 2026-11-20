/* POLLER-LIMIT-1: a poller holds as many connections as the process may open descriptors, not 1,024. The fixture runs the
   runtime's poller natively against real loopback sockets and checks each answer with `assert`; a mode that holds is
   one line on stdout. Modes: grow, bound, full, descriptors. */
#define _GNU_SOURCE
#include "core_rt.c"
#undef NDEBUG
#include <assert.h>
#include <sys/resource.h>
#include <sys/wait.h>

myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }

/* One answer of the poller: its three header words and the bytes after them. */
typedef struct { uint32_t status, value, extra; unsigned char data[2304]; size_t length; } Reply;

static Reply ask(CorePoller *poller, unsigned op, unsigned what, uint32_t id, uint32_t a, uint32_t b) {
    unsigned char command[CORE_POLL_COMMAND_HEADER] = {0};
    command[0] = (unsigned char)op;
    command[1] = (unsigned char)what;
    core_poll_put(command + 4, id);
    core_poll_put(command + 8, a);
    core_poll_put(command + 12, b);
    CoreIoResourceWrite written = core_poll_command(poller, command, sizeof command);
    assert(written.status == CORE_IO_PROVIDER_OK);
    unsigned char raw[CORE_POLL_RESPONSE_HEADER + sizeof(((Reply *)0)->data)];
    CoreIoResourceRead read = core_poll_response(poller, raw, sizeof raw);
    assert(read.status == CORE_IO_PROVIDER_OK && read.eof && read.length >= CORE_POLL_RESPONSE_HEADER);
    Reply reply = {core_poll_get(raw), core_poll_get(raw + 4), core_poll_get(raw + 8), {0}, read.length - CORE_POLL_RESPONSE_HEADER};
    memcpy(reply.data, raw + CORE_POLL_RESPONSE_HEADER, reply.length);
    return reply;
}
static void send_text(CorePoller *poller, uint32_t id, const char *text) {
    unsigned char command[CORE_POLL_COMMAND_HEADER + 64] = {0};
    command[0] = CORE_POLL_SEND;
    core_poll_put(command + 4, id);
    size_t width = strlen(text);
    memcpy(command + CORE_POLL_COMMAND_HEADER, text, width);
    CoreIoResourceWrite written = core_poll_command(poller, command, CORE_POLL_COMMAND_HEADER + width);
    assert(written.status == CORE_IO_PROVIDER_OK);
    unsigned char raw[CORE_POLL_RESPONSE_HEADER];
    CoreIoResourceRead read = core_poll_response(poller, raw, sizeof raw);
    assert(read.eof && core_poll_get(raw) == CORE_POLL_OK && core_poll_get(raw + 4) == width);
}
static void expect_text(CorePoller *poller, uint32_t id, const char *text) {
    Reply got = ask(poller, CORE_POLL_RECV, 0, id, 64, 0);
    assert(got.status == CORE_POLL_OK && got.length == strlen(text) && !memcmp(got.data, text, got.length));
}

static int listen_on_loopback(uint16_t *port) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    socklen_t width = sizeof address;
    assert(listener >= 0 && bind(listener, (struct sockaddr *)&address, sizeof address) == 0 && listen(listener, 4096) == 0);
    assert(getsockname(listener, (struct sockaddr *)&address, &width) == 0);
    *port = ntohs(address.sin_port);
    return listener;
}
static int dial_loopback(uint16_t port) {
    int client = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    assert(client >= 0 && connect(client, (struct sockaddr *)&address, sizeof address) == 0);
    return client;
}
static void limit_descriptors(rlim_t both) {
    struct rlimit set = {both, both};
    assert(setrlimit(RLIMIT_NOFILE, &set) == 0);
}
static uint32_t held_limit(CorePoller *poller, uint32_t *open) {
    Reply info = ask(poller, CORE_POLL_INFO, 3, 0, 0, 0);
    assert(info.status == CORE_POLL_OK);
    if (open) *open = info.extra;
    return info.value;
}
/* The id of the first connection of `slot`: the id it always had below 1,024 slots, an extended id from there. */
static uint32_t first_id(const CorePoller *poller, size_t slot) {
    if (slot < 1024) return (1u << 10) | (uint32_t)slot;
    return (1u << 31) | (1u << poller->extended_bits) | (uint32_t)(slot - 1024);
}
/* Connect and accept clients `from` up to `to`; each is the first connection of the next slot. */
static void take(CorePoller *poller, uint16_t port, int *clients, uint32_t *ids, int from, int to) {
    for (int i = from; i < to; ++i) {
        clients[i] = dial_loopback(port);
        Reply accepted = ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0);
        assert(accepted.status == CORE_POLL_OK && accepted.value != 0);
        ids[i] = accepted.value;
        assert(ids[i] == first_id(poller, (size_t)i));
    }
}
/* The flags `wait` reported for `id`, or -1 when it reported none. */
static long flags_of(const Reply *waited, uint32_t id) {
    for (uint32_t i = 0; i < waited->value; ++i)
        if (core_poll_get(waited->data + i * 8) == id) return (long)core_poll_get(waited->data + i * 8 + 4);
    return -1;
}
static void close_clients(int *clients, int count) { for (int i = 0; i < count; ++i) close(clients[i]); }
static void finish(CorePoller *poller) {
    int epoll = core_poll_epoll_descriptor(poller);
    core_poll_destroy(poller);
    close(epoll);
}

/* More than 1,024 connections in one poller, a message each way on the last, and the table's growth. */
static void grow(void) {
    enum { HELD = 1100 };
    static int clients[HELD];
    static uint32_t ids[HELD];
    uint16_t port;
    struct rlimit now;
    /* Start from the soft limit a shell gives, 1,024: opening the poller raises it toward the hard one. */
    assert(getrlimit(RLIMIT_NOFILE, &now) == 0);
    if (now.rlim_cur > 1024) {
        now.rlim_cur = 1024;
        assert(setrlimit(RLIMIT_NOFILE, &now) == 0);
    }
    CorePoller *poller = core_poll_create(listen_on_loopback(&port));
    assert(poller && poller->capacity == 1024);
    assert(getrlimit(RLIMIT_NOFILE, &now) == 0);
    size_t bound = (size_t)now.rlim_cur - CORE_POLL_RESERVED_FDS;
    if (bound > (size_t)1 << CORE_POLL_MAX_SLOT_BITS) bound = (size_t)1 << CORE_POLL_MAX_SLOT_BITS;
    uint32_t open;
    assert(held_limit(poller, &open) == bound && bound > 1024 && open == 0);
    take(poller, port, clients, ids, 0, 1024);
    /* The table is exactly full, and an accept that finds no client waiting does not grow it. */
    assert(ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0).status == CORE_POLL_WOULD_BLOCK && poller->capacity == 1024);
    take(poller, port, clients, ids, 1024, HELD);
    assert(poller->capacity == 2048 && held_limit(poller, &open) == bound && open == HELD);
    assert(send(clients[HELD - 1], "hello", 5, 0) == 5);
    /* Wait reports the last connection readable; the slot it named is clear again for the next wait. */
    Reply waited = ask(poller, CORE_POLL_WAIT, 0, 0, 0, 255);
    assert(waited.status == CORE_POLL_OK && waited.value == 1 && core_poll_get(waited.data) == ids[HELD - 1]);
    assert(core_poll_get(waited.data + 4) == CORE_POLL_READABLE);
    expect_text(poller, ids[HELD - 1], "hello");
    send_text(poller, ids[HELD - 1], "world");
    char heard[8] = {0};
    assert(recv(clients[HELD - 1], heard, sizeof heard, 0) == 5 && !memcmp(heard, "world", 5));
    /* Idle timeouts merge into the events of the same wait, and a wait leaves nothing of its merge for the next one. */
    assert(ask(poller, CORE_POLL_CONFIG, 1, 0, 1, 0).status == CORE_POLL_OK);
    usleep(5000);
    assert(send(clients[5], "x", 1, 0) == 1);
    Reply merged = ask(poller, CORE_POLL_WAIT, 0, 0, 0, 255);
    assert(merged.value == 255 && flags_of(&merged, ids[5]) == (CORE_POLL_READABLE | CORE_POLL_IDLE));
    expect_text(poller, ids[5], "x");
    usleep(5000);
    Reply alone = ask(poller, CORE_POLL_WAIT, 0, 0, 0, 255);
    assert(alone.value == 255 && flags_of(&alone, ids[5]) == CORE_POLL_IDLE);
    assert(ask(poller, CORE_POLL_CONFIG, 1, 0, 0, 0).status == CORE_POLL_OK);
    /* An id goes stale once its connection closes, below 1,024 slots and above. */
    assert(ask(poller, CORE_POLL_CLOSE, 0, ids[0], 0, 0).status == CORE_POLL_OK);
    assert(ask(poller, CORE_POLL_RECV, 0, ids[0], 64, 0).status == CORE_POLL_UNKNOWN);
    assert(ask(poller, CORE_POLL_CLOSE, 0, ids[HELD - 1], 0, 0).status == CORE_POLL_OK);
    assert(ask(poller, CORE_POLL_RECV, 0, ids[HELD - 1], 64, 0).status == CORE_POLL_UNKNOWN);
    for (size_t slot = 0; slot < poller->capacity; ++slot) assert(poller->at[slot] == 0);
    close_clients(clients, HELD);
    finish(poller);
    printf("grow: held %d connections past 1,024, the last answered, the bound above 1,024\n", HELD);
}

/* The bound is the descriptor limit less 64 (at most 1 << 20), and the first connection's id is the one it always had. */
static void bound(void) {
    static const rlim_t limits[] = {4000, 1100, 600, 100};
    static const uint32_t bounds[] = {3936, 1036, 536, 36};
    for (size_t i = 0; i < sizeof limits / sizeof limits[0]; ++i) {
        limit_descriptors(limits[i]);
        uint16_t port;
        int clients[1];
        uint32_t ids[1];
        CorePoller *poller = core_poll_create(listen_on_loopback(&port));
        assert(poller && held_limit(poller, NULL) == bounds[i]);
        take(poller, port, clients, ids, 0, 1);
        assert(ids[0] == 1024);
        close_clients(clients, 1);
        finish(poller);
    }
    printf("bound: the connection limit is the descriptor limit less 64\n");
}

/* A poller at its limit answers full, leaves the next client in the backlog, and takes it once a connection closes. */
static void full(void) {
    enum { LIMIT = 1236, CLIENTS = LIMIT + 1 };
    limit_descriptors(LIMIT + CORE_POLL_RESERVED_FDS);
    uint16_t port;
    int listener = listen_on_loopback(&port), ready[2];
    assert(pipe(ready) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        static int sockets[CLIENTS];
        close(listener);
        for (int i = 0; i < CLIENTS; ++i) sockets[i] = dial_loopback(port);
        assert(send(sockets[LIMIT - 1], "last", 4, 0) == 4 && write(ready[1], "r", 1) == 1);
        char done[4];
        assert(recv(sockets[LIMIT - 1], done, sizeof done, MSG_WAITALL) == 4 && !memcmp(done, "done", 4));
        _exit(0);
    }
    char byte;
    assert(read(ready[0], &byte, 1) == 1);
    CorePoller *poller = core_poll_create(listener);
    assert(poller);
    uint32_t open, first = 0, last = 0;
    assert(held_limit(poller, &open) == LIMIT);
    for (int i = 0; i < LIMIT; ++i) {
        Reply accepted = ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0);
        assert(accepted.status == CORE_POLL_OK);
        if (i == 0) first = accepted.value;
        last = accepted.value;
    }
    assert(first == first_id(poller, 0) && last == first_id(poller, LIMIT - 1));
    assert(poller->capacity == LIMIT && !poller->listener_armed);
    assert(held_limit(poller, &open) == LIMIT && open == LIMIT);
    assert(ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0).status == CORE_POLL_FULL);
    expect_text(poller, last, "last");
    send_text(poller, last, "done");
    assert(ask(poller, CORE_POLL_CLOSE, 0, first, 0, 0).status == CORE_POLL_OK && poller->listener_armed);
    Reply taken = ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0);
    assert(taken.status == CORE_POLL_OK && taken.value != first);
    int status = 0;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
    finish(poller);
    printf("full: %d connections held, the next answered full and taken after a close\n", LIMIT);
}

/* An accept the process has no descriptor for answers full, not failed, and the client is taken once one is free. */
static void descriptors(void) {
    uint16_t port;
    CorePoller *poller = core_poll_create(listen_on_loopback(&port));
    assert(poller);
    int client = dial_loopback(port);
    struct rlimit before, after;
    assert(getrlimit(RLIMIT_NOFILE, &before) == 0);
    int probe = dup(0);
    assert(probe >= 0);
    close(probe);
    after = before;
    after.rlim_cur = (rlim_t)probe;
    assert(setrlimit(RLIMIT_NOFILE, &after) == 0);
    assert(ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0).status == CORE_POLL_FULL);
    assert(setrlimit(RLIMIT_NOFILE, &before) == 0);
    Reply taken = ask(poller, CORE_POLL_ACCEPT, 0, 0, 0, 0);
    assert(taken.status == CORE_POLL_OK && taken.value != 0);
    close(client);
    finish(poller);
    printf("descriptors: an accept without a descriptor answers full\n");
}

int main(int argc, char **argv) {
    assert(argc == 2);
    if (!strcmp(argv[1], "grow")) grow();
    else if (!strcmp(argv[1], "bound")) bound();
    else if (!strcmp(argv[1], "full")) full();
    else if (!strcmp(argv[1], "descriptors")) descriptors();
    else assert(0);
    return 0;
}
