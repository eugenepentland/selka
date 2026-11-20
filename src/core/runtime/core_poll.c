/* The event loop's runtime half (docs/design/event-loop-2026-10-18.md).
 *
 * One CorePoller owns a listening socket (none, for a client's poller), an epoll set and a table of accepted
 * and dialled connections. The guest holds a single `Poller` resource and names connections
 * by small integer ids; it drives the poller with the resource builtins. A
 * `write_resource` is one command and the next `read_resource` returns that
 * command's response, so no new compiler builtin carries the traffic.
 *
 * Command (little-endian): 16-byte header {op, what, pad, pad, id u32, a u32, b u32}
 * then, for a send, the payload bytes. Response: 12-byte header {status u32,
 * value u32, extra u32}, then received bytes or 8-byte event records {id u32,
 * flags u32}. Every socket is non-blocking and every operation returns at once
 * except `wait`, which blocks for at most the timeout the guest named.
 *
 * This file is concatenated after core_io.c and uses its provider types; the
 * scoped network provider (core_io_scoped_*) is the only caller. It reads the
 * monotonic clock to time idle connections and never reports the time. */
#include <sys/epoll.h>
#include <sys/resource.h>
#include <netinet/tcp.h>

/* The soft descriptor limit this program had before a poller first raised it (set once, under the provider lock that makes
   pollers). A program this one starts gets it back (core_process_spawn): the raise is for this program's connections, and a
   program that uses `select` breaks above 1,024. */
static struct rlimit core_poll_started_descriptors;
static bool core_poll_started_noted;
/* A poller holds as many connections as the process may open descriptors, less CORE_POLL_RESERVED_FDS, and at most
   1 << CORE_POLL_MAX_SLOT_BITS. Its table starts at CORE_POLL_INITIAL_SLOTS (or its limit, when that is lower) and
   doubles as connections arrive. */
#define CORE_POLL_MAX_SLOT_BITS 20u
#define CORE_POLL_INITIAL_SLOTS 1024u
/* Descriptors kept for the rest of the process (streams, caches, files). */
#define CORE_POLL_RESERVED_FDS 64u
/* A connection id is never 0 (the listener) and never names a newer connection that reused a slot: it carries the slot's
   generation, which is at least 1. A slot below CORE_POLL_LOW_SLOTS has the id it always had, generation << 10 | slot, so a
   poller of up to 1,024 connections gives the ids it gave before the table could grow. A slot from CORE_POLL_LOW_SLOTS on has
   CORE_POLL_EXTENDED | generation << extended_bits | (slot - CORE_POLL_LOW_SLOTS), where `extended_bits` holds what the
   poller's limit needs. */
#define CORE_POLL_LOW_SLOTS 1024u
#define CORE_POLL_LOW_BITS 10u
#define CORE_POLL_LOW_GENERATIONS (1u << 21)
#define CORE_POLL_EXTENDED (1u << 31)
/* Events returned by one wait; the response is 12 + 8 * 255 bytes. */
#define CORE_POLL_MAX_EVENTS 255u
/* Bytes moved by one receive or send command. */
#define CORE_POLL_TRANSFER (64u * 1024u)
#define CORE_POLL_COMMAND_HEADER 16u
#define CORE_POLL_RESPONSE_HEADER 12u
/* The longest wait or idle timeout the runtime honours (one day). */
#define CORE_POLL_LONGEST_MS 86400000u
/* The epoll data of the stop's wake-up descriptor (core_stop.c), which no connection id can equal. */
#define CORE_POLL_STOP_TOKEN UINT64_MAX

typedef enum {
    CORE_POLL_OK = 0, CORE_POLL_WOULD_BLOCK = 1, CORE_POLL_CLOSED = 2, CORE_POLL_FAILED = 3,
    CORE_POLL_UNKNOWN = 4, CORE_POLL_FULL = 5, CORE_POLL_BAD = 6
} CorePollStatus;
typedef enum {
    CORE_POLL_WAIT = 1, CORE_POLL_ACCEPT = 2, CORE_POLL_RECV = 3, CORE_POLL_SEND = 4,
    CORE_POLL_CLOSE = 5, CORE_POLL_INFO = 6, CORE_POLL_CONFIG = 7, CORE_POLL_DIAL_TOKEN = 8
} CorePollOp;
enum { CORE_POLL_READABLE = 1, CORE_POLL_WRITABLE = 2, CORE_POLL_HANGUP = 4, CORE_POLL_ERROR = 8, CORE_POLL_IDLE = 16, CORE_POLL_CONNECTED = 32 };
/* A connection is open (accepted, or dialled and connected), connecting (dialled, the connect not finished) or failed
   (dialled, and the connect was refused, unreachable or ran out of its limit: `failure` is the errno). */
enum { CORE_POLL_OPEN = 0, CORE_POLL_CONNECTING = 1, CORE_POLL_DIAL_FAILED = 2 };

/* `idle_ms` is the connection's own idle timeout: CORE_POLL_IDLE_INHERIT (the poller's), 0 (never) or milliseconds.
   `deadline_ms` is a connecting connection's connect limit on the monotonic clock (0: none). */
typedef struct { int fd; uint32_t generation; unsigned interest; int64_t active_ms, idle_ms, deadline_ms; unsigned char state; int failure; } CorePollEntry;
#define CORE_POLL_IDLE_INHERIT (-1)
struct CorePoller {
    int epoll_fd, listener_fd;
    unsigned listener_interest;
    int listener_armed;
    CorePollEntry *entries;
    /* `at` is a scratch table of `capacity` slots for `wait`, all zero between waits. */
    uint16_t *at;
    /* `capacity` slots are allocated, `limit` is the most the table grows to, and `open` of them hold a connection. */
    size_t open, capacity, limit;
    size_t cursor;
    unsigned extended_bits;
    /* The idle timeout of every connection that sets none, and how many open connections set their own. */
    int64_t idle_ms;
    size_t own_idle;
    /* The token a dial names this poller by, and how many of its connections are still connecting. */
    uint32_t token;
    size_t dialing;
    unsigned char *response;
    size_t response_length, response_position;
    /* Whether the stop's wake-up descriptor is in the epoll set (FR5b): from the poller's start in a program that
       declared a `Stop`, until the program has read its stop. */
    int stop_armed;
    /* The monotonic time (ms) at which the last run of waits that found nothing ready began; 0 while the last wait found something. */
    int64_t quiet_ms;
};

/* The idle timeout that applies to `entry`: its own, or the poller's; 0 is none. */
static int64_t core_poll_idle_of(const CorePoller *poller, const CorePollEntry *entry) {
    return entry->idle_ms == CORE_POLL_IDLE_INHERIT ? poller->idle_ms : entry->idle_ms;
}
/* Whether any open connection can go idle or is connecting, so `wait` must time the connections. */
static int core_poll_timing(const CorePoller *poller) {
    return poller->idle_ms > 0 || poller->own_idle > 0 || poller->dialing > 0;
}
/* The last token handed out; a poller's token is never 0. Pollers are made under the provider lock. */
static uint32_t core_poll_tokens;
static int64_t core_poll_now_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}
static uint32_t core_poll_get(const unsigned char *at) {
    return (uint32_t)at[0] | (uint32_t)at[1] << 8 | (uint32_t)at[2] << 16 | (uint32_t)at[3] << 24;
}
static void core_poll_put(unsigned char *at, uint32_t value) {
    at[0] = (unsigned char)value; at[1] = (unsigned char)(value >> 8);
    at[2] = (unsigned char)(value >> 16); at[3] = (unsigned char)(value >> 24);
}
/* Start a response of `payload` bytes after the header. */
static unsigned char *core_poll_reply(CorePoller *poller, CorePollStatus status, uint32_t value, uint32_t extra, size_t payload) {
    core_poll_put(poller->response, (uint32_t)status);
    core_poll_put(poller->response + 4, value);
    core_poll_put(poller->response + 8, extra);
    poller->response_length = CORE_POLL_RESPONSE_HEADER + payload;
    poller->response_position = 0;
    return poller->response + CORE_POLL_RESPONSE_HEADER;
}
static void core_poll_fail(CorePoller *poller, int error) {
    core_poll_reply(poller, CORE_POLL_FAILED, (uint32_t)error, 0, 0);
}
static uint32_t core_poll_epoll_events(unsigned interest) {
    uint32_t events = 0;
    if (interest & CORE_POLL_READABLE) events |= EPOLLIN | EPOLLRDHUP;
    if (interest & CORE_POLL_WRITABLE) events |= EPOLLOUT;
    return events;
}
static uint32_t core_poll_id(const CorePoller *poller, size_t slot) {
    uint32_t generation = poller->entries[slot].generation;
    if (slot < CORE_POLL_LOW_SLOTS) return generation << CORE_POLL_LOW_BITS | (uint32_t)slot;
    return CORE_POLL_EXTENDED | generation << poller->extended_bits | (uint32_t)(slot - CORE_POLL_LOW_SLOTS);
}
/* The slot an id names, and in `generation` the generation it was made with. */
static size_t core_poll_slot_of(const CorePoller *poller, uint32_t id, uint32_t *generation) {
    if (id & CORE_POLL_EXTENDED) {
        uint32_t rest = id & ~CORE_POLL_EXTENDED;
        if (generation) *generation = rest >> poller->extended_bits;
        return CORE_POLL_LOW_SLOTS + (rest & ((1u << poller->extended_bits) - 1));
    }
    if (generation) *generation = id >> CORE_POLL_LOW_BITS;
    return id & (CORE_POLL_LOW_SLOTS - 1);
}
/* The generation the next connection of `slot` has: one more, back to 1 after the last one an id has room for. */
static uint32_t core_poll_next_generation(const CorePoller *poller, size_t slot) {
    uint32_t after = slot < CORE_POLL_LOW_SLOTS ? CORE_POLL_LOW_GENERATIONS : 1u << (31 - poller->extended_bits);
    uint32_t generation = poller->entries[slot].generation;
    return generation + 1 >= after ? 1 : generation + 1;
}
/* The open connection an id names, or NULL for 0 (the listener), a stale id or a
   slot that is not open. */
static CorePollEntry *core_poll_entry(CorePoller *poller, uint32_t id) {
    uint32_t generation;
    size_t slot = core_poll_slot_of(poller, id, &generation);
    if (generation == 0 || slot >= poller->capacity) return NULL;
    CorePollEntry *entry = &poller->entries[slot];
    return entry->fd >= 0 && entry->generation == generation ? entry : NULL;
}
/* Keep the listener in the epoll set only while the guest wants accepts and a slot
   is free, so a full server does not spin on a listener it cannot serve. A client's poller has no listener. */
static void core_poll_sync_listener(CorePoller *poller) {
    int want = poller->listener_fd >= 0 && (poller->listener_interest & CORE_POLL_READABLE) && poller->open < poller->limit;
    if (want && !poller->listener_armed) {
        struct epoll_event event = {.events = EPOLLIN, .data.u64 = 0};
        if (epoll_ctl(poller->epoll_fd, EPOLL_CTL_ADD, poller->listener_fd, &event) == 0) poller->listener_armed = 1;
    } else if (!want && poller->listener_armed) {
        epoll_ctl(poller->epoll_fd, EPOLL_CTL_DEL, poller->listener_fd, NULL);
        poller->listener_armed = 0;
    }
}

/* Build a poller around a bound, listening socket, which it now owns, or around none (`listener` is -1: a client's poller,
   which only holds connections it dials). The epoll
   descriptor is returned through `poller->epoll_fd` and belongs to the caller's
   handle, which closes it after core_poll_destroy. NULL when memory or
   descriptors run out; the caller then still owns the listener. */
static CorePoller *core_poll_create(int listener) {
    struct rlimit descriptors;
    size_t limit = (size_t)1 << CORE_POLL_MAX_SLOT_BITS;
    if (getrlimit(RLIMIT_NOFILE, &descriptors) == 0) {
        /* The soft limit is raised to the hard one (or to what the largest table needs): the process may open that many. */
        rlim_t wanted = limit + CORE_POLL_RESERVED_FDS;
        if (descriptors.rlim_cur != RLIM_INFINITY && descriptors.rlim_cur < wanted) {
            if (!core_poll_started_noted) { core_poll_started_descriptors = descriptors; core_poll_started_noted = true; }
            struct rlimit raised = descriptors;
            raised.rlim_cur = descriptors.rlim_max == RLIM_INFINITY || descriptors.rlim_max > wanted ? wanted : descriptors.rlim_max;
            if (raised.rlim_cur > descriptors.rlim_cur && setrlimit(RLIMIT_NOFILE, &raised) == 0) descriptors = raised;
        }
        if (descriptors.rlim_cur != RLIM_INFINITY) {
            size_t available = descriptors.rlim_cur > CORE_POLL_RESERVED_FDS ? (size_t)descriptors.rlim_cur - CORE_POLL_RESERVED_FDS : 1;
            if (available < limit) limit = available;
        }
    }
    int flags = listener >= 0 ? fcntl(listener, F_GETFL) : 0;
    if (listener >= 0 && (flags < 0 || fcntl(listener, F_SETFL, flags | O_NONBLOCK) < 0)) return NULL;
    CorePoller *poller = calloc(1, sizeof *poller);
    if (!poller) return NULL;
    size_t capacity = limit < CORE_POLL_INITIAL_SLOTS ? limit : CORE_POLL_INITIAL_SLOTS;
    poller->entries = calloc(capacity, sizeof *poller->entries);
    poller->at = calloc(capacity, sizeof *poller->at);
    poller->response = malloc(CORE_POLL_RESPONSE_HEADER + CORE_POLL_TRANSFER);
    poller->epoll_fd = epoll_create1(EPOLL_CLOEXEC);
    if (!poller->entries || !poller->at || !poller->response || poller->epoll_fd < 0) {
        if (poller->epoll_fd >= 0) close(poller->epoll_fd);
        free(poller->entries); free(poller->at); free(poller->response); free(poller);
        return NULL;
    }
    for (size_t i = 0; i < capacity; ++i) poller->entries[i].fd = -1;
    poller->listener_fd = listener;
    poller->token = ++core_poll_tokens ? core_poll_tokens : ++core_poll_tokens;
    poller->listener_interest = CORE_POLL_READABLE;
    poller->limit = limit;
    poller->capacity = capacity;
    while (limit > CORE_POLL_LOW_SLOTS && limit - CORE_POLL_LOW_SLOTS > (size_t)1 << poller->extended_bits) ++poller->extended_bits;
    core_poll_sync_listener(poller);
    if (listener >= 0 && !poller->listener_armed) {
        close(poller->epoll_fd); free(poller->entries); free(poller->at); free(poller->response); free(poller);
        return NULL;
    }
    if (core_stop_wake_descriptor() >= 0) {
        struct epoll_event wake = {.events = EPOLLIN, .data.u64 = CORE_POLL_STOP_TOKEN};
        poller->stop_armed = epoll_ctl(poller->epoll_fd, EPOLL_CTL_ADD, core_stop_wake_descriptor(), &wake) == 0;
    }
    core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0);
    return poller;
}
/* The epoll descriptor, which the owning scoped handle closes after core_poll_destroy. */
static int core_poll_epoll_descriptor(const CorePoller *poller) { return poller->epoll_fd; }
/* Close the listener (if it has one) and every connection and free the poller's memory. */
static void core_poll_destroy(CorePoller *poller) {
    for (size_t i = 0; i < poller->capacity; ++i) if (poller->entries[i].fd >= 0) close(poller->entries[i].fd);
    if (poller->listener_fd >= 0) close(poller->listener_fd);
    free(poller->entries); free(poller->at); free(poller->response); free(poller);
}

/* The next free slot after the last one handed out, so a slot's generation climbs
   slowly and a stale id stays stale. */
/* Double the table, up to the limit, and start the next search at its first new slot. 0 when the table is at its
   limit or memory ran out (the poller then holds what it has). */
static int core_poll_grow(CorePoller *poller) {
    if (poller->capacity >= poller->limit) return 0;
    size_t wanted = poller->capacity > poller->limit / 2 ? poller->limit : poller->capacity * 2;
    uint16_t *at = realloc(poller->at, wanted * sizeof *at);
    if (!at) return 0;
    poller->at = at;
    CorePollEntry *entries = realloc(poller->entries, wanted * sizeof *entries);
    if (!entries) return 0;
    memset(at + poller->capacity, 0, (wanted - poller->capacity) * sizeof *at);
    memset(entries + poller->capacity, 0, (wanted - poller->capacity) * sizeof *entries);
    for (size_t i = poller->capacity; i < wanted; ++i) entries[i].fd = -1;
    poller->entries = entries;
    poller->cursor = poller->capacity;
    poller->capacity = wanted;
    return 1;
}
static int core_poll_find_slot(CorePoller *poller, size_t *slot) {
    if (poller->open >= poller->capacity && !core_poll_grow(poller)) return 0;
    for (size_t i = 0; i < poller->capacity; ++i) {
        size_t candidate = (poller->cursor + i) % poller->capacity;
        if (poller->entries[candidate].fd >= 0) continue;
        *slot = candidate;
        return 1;
    }
    return 0;
}
static void core_poll_accept(CorePoller *poller) {
    size_t slot;
    /* A client's poller has no listener: there is never anything to accept. */
    if (poller->listener_fd < 0) { core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0); return; }
    if (poller->open >= poller->capacity && poller->capacity < poller->limit) {
        /* The table would grow for this connection: only when one is waiting, so a poller that holds exactly as many as
           its table has slots does not double it for an accept that finds nothing. */
        struct pollfd pending = {.fd = poller->listener_fd, .events = POLLIN};
        if (poll(&pending, 1, 0) <= 0) { core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0); return; }
    }
    if (!core_poll_find_slot(poller, &slot)) { core_poll_reply(poller, CORE_POLL_FULL, 0, 0, 0); return; }
    int fd;
    for (;;) {
        fd = accept4(poller->listener_fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC);
        if (fd >= 0) break;
        if (errno == EINTR || errno == ECONNABORTED) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) { core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0); return; }
        /* Out of descriptors (the process's or the system's) is a full table, not a failure: the connection stays in the
           backlog and the next accept after a close takes it. */
        if (errno == EMFILE || errno == ENFILE) { core_poll_reply(poller, CORE_POLL_FULL, 0, 0, 0); return; }
        core_poll_fail(poller, errno);
        return;
    }
    int yes = 1;
    (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof yes);
    CorePollEntry *entry = &poller->entries[slot];
    entry->generation = core_poll_next_generation(poller, slot);
    entry->fd = fd;
    entry->interest = CORE_POLL_READABLE;
    entry->active_ms = core_poll_now_ms();
    entry->idle_ms = CORE_POLL_IDLE_INHERIT;
    entry->state = CORE_POLL_OPEN;
    entry->deadline_ms = 0;
    entry->failure = 0;
    uint32_t id = core_poll_id(poller, slot);
    struct epoll_event event = {.events = core_poll_epoll_events(entry->interest), .data.u64 = id};
    if (epoll_ctl(poller->epoll_fd, EPOLL_CTL_ADD, fd, &event) < 0) {
        int error = errno;
        close(fd);
        entry->fd = -1;
        core_poll_fail(poller, error);
        return;
    }
    ++poller->open;
    poller->cursor = (slot + 1) % poller->capacity;
    core_poll_sync_listener(poller);
    core_poll_reply(poller, CORE_POLL_OK, id, 0, 0);
}
/* The token `network.dial` names this poller by in its acquisition request. */
static uint32_t core_poll_token(const CorePoller *poller) { return poller->token; }
/* A dial that failed before it had a connection: the poller's next response is FAILED with the errno. */
static void core_poll_dial_failed(CorePoller *poller, int error) { core_poll_fail(poller, error); }
/* Take the socket of a nonblocking connect the provider just started and name it by a new id, answered as the poller's
   next response. It is watched for writable until the connect finishes; `wait` then reports CORE_POLL_CONNECTED, or an
   error when it was refused, unreachable or not finished within `connect_ms` (0: no limit). */
static void core_poll_adopt(CorePoller *poller, int fd, uint32_t connect_ms) {
    size_t slot;
    poller->response_length = poller->response_position = 0;
    if (!core_poll_find_slot(poller, &slot)) { close(fd); core_poll_reply(poller, CORE_POLL_FULL, 0, 0, 0); return; }
    int yes = 1;
    (void)setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof yes);
    CorePollEntry *entry = &poller->entries[slot];
    entry->generation = core_poll_next_generation(poller, slot);
    entry->fd = fd;
    entry->interest = CORE_POLL_READABLE;
    entry->active_ms = core_poll_now_ms();
    entry->idle_ms = CORE_POLL_IDLE_INHERIT;
    entry->state = CORE_POLL_CONNECTING;
    entry->deadline_ms = connect_ms ? entry->active_ms + (connect_ms > CORE_POLL_LONGEST_MS ? CORE_POLL_LONGEST_MS : connect_ms) : 0;
    entry->failure = 0;
    uint32_t id = core_poll_id(poller, slot);
    struct epoll_event event = {.events = EPOLLOUT, .data.u64 = id};
    if (epoll_ctl(poller->epoll_fd, EPOLL_CTL_ADD, fd, &event) < 0) {
        int error = errno;
        close(fd);
        entry->fd = -1;
        core_poll_fail(poller, error);
        return;
    }
    ++poller->open;
    ++poller->dialing;
    poller->cursor = (slot + 1) % poller->capacity;
    core_poll_sync_listener(poller);
    core_poll_reply(poller, CORE_POLL_OK, id, 0, 0);
}
/* A connecting connection's connect has failed with `error`: it leaves the epoll set (a failed socket reports an error
   for ever) and its next receive or send reports the errno. The bits `wait` reports for it. */
static uint32_t core_poll_connect_failed(CorePoller *poller, CorePollEntry *entry, int error) {
    epoll_ctl(poller->epoll_fd, EPOLL_CTL_DEL, entry->fd, NULL);
    entry->state = CORE_POLL_DIAL_FAILED;
    entry->failure = error ? error : ECONNREFUSED;
    --poller->dialing;
    return CORE_POLL_ERROR | (entry->interest & CORE_POLL_READABLE);
}
/* A connecting connection was reported writable or in error: finish its connect. The bits `wait` reports for it. */
static uint32_t core_poll_connect_finished(CorePoller *poller, CorePollEntry *entry, uint32_t id) {
    int error = 0;
    socklen_t width = sizeof error;
    if (getsockopt(entry->fd, SOL_SOCKET, SO_ERROR, &error, &width) < 0) error = errno;
    if (error) return core_poll_connect_failed(poller, entry, error);
    struct epoll_event event = {.events = core_poll_epoll_events(entry->interest), .data.u64 = id};
    if (epoll_ctl(poller->epoll_fd, EPOLL_CTL_MOD, entry->fd, &event) < 0) return core_poll_connect_failed(poller, entry, errno);
    entry->state = CORE_POLL_OPEN;
    entry->active_ms = core_poll_now_ms();
    --poller->dialing;
    return CORE_POLL_CONNECTED;
}
static void core_poll_drop(CorePoller *poller, CorePollEntry *entry) {
    if (entry->state == CORE_POLL_CONNECTING) --poller->dialing;
    entry->state = CORE_POLL_OPEN;
    epoll_ctl(poller->epoll_fd, EPOLL_CTL_DEL, entry->fd, NULL);
    close(entry->fd);
    entry->fd = -1;
    if (entry->idle_ms != CORE_POLL_IDLE_INHERIT) --poller->own_idle;
    entry->idle_ms = CORE_POLL_IDLE_INHERIT;
    --poller->open;
    core_poll_sync_listener(poller);
}
/* Take the stop's wake-up descriptor out of the poller's set: it stays readable for ever once written. */
static void core_poll_disarm_stop(CorePoller *poller) {
    epoll_ctl(poller->epoll_fd, EPOLL_CTL_DEL, core_stop_fd, NULL);
    poller->stop_armed = 0;
}
/* epoll_wait for `wait`, -1 for no limit; an error is an empty wait. In a program that declared a `Stop` (FR5b) the wake-up
   descriptor is in the set from the poller's start, so a pending stop ends a wait at once on whichever thread the signal
   reached, and a stop that came before the wait ends it before it blocks. It does so once per poller: the wait it ends
   takes the descriptor out of the set, as does the program's reading of the stop, so a later wait lasts its time and a
   program that never reads its stop does not spin. An interruption that ends nothing (a dropped copy of a stop, or a
   stop this poller has already woken for) waits again for the rest of the time. */
__attribute__((always_inline)) static inline int core_poll_epoll_wait(CorePoller *poller, struct epoll_event *raw, int max, int64_t timeout) {
    if (!core_stop_installed()) {
        int ready = epoll_wait(poller->epoll_fd, raw, max, (int)timeout);
        return ready < 0 ? 0 : ready;
    }
    if (poller->stop_armed && core_stop_wake_descriptor() < 0) core_poll_disarm_stop(poller);
    if (poller->stop_armed && core_stop_pending()) timeout = 0;
    int64_t deadline = timeout > 0 ? core_poll_now_ms() + timeout : 0;
    for (;;) {
        int ready = epoll_wait(poller->epoll_fd, raw, max, (int)timeout);
        int woken = poller->stop_armed && core_stop_pending();
        if (woken) core_poll_disarm_stop(poller);
        if (ready >= 0) return ready;
        if (errno != EINTR || woken) return 0;
        if (timeout > 0) {
            timeout = deadline - core_poll_now_ms();
            if (timeout <= 0) return 0;
        }
    }
}
/* RUNTIME-HEAP-RETURN-1: whether the loop is idle for a wait about to block for `timeout` ms (-1: no limit): the wait itself
   is long (a second or more, or none), or the waits before it found nothing ready for a second. A busy loop is not idle,
   because its last wait found something and `quiet_ms` is 0. `wait` asks only once enough large blocks have been freed
   since the last look (`core_heap_look_due`), and the answer costs a few instructions: a busy server asks every time. */
enum { CORE_POLL_QUIET_MS = 1000 };
__attribute__((always_inline)) static inline int core_poll_idle(const CorePoller *poller, int64_t timeout) {
    return timeout < 0 || timeout >= CORE_POLL_QUIET_MS ||
           (poller->quiet_ms != 0 && core_poll_now_ms() - poller->quiet_ms >= CORE_POLL_QUIET_MS);
}
__attribute__((noinline)) static int core_poll_epoll_wait_apart(CorePoller *poller, struct epoll_event *raw, int max, int64_t timeout) {
    return core_poll_epoll_wait(poller, raw, max, timeout);
}
/* The epoll wait of an idle loop that has freed enough: one look without blocking, so that a ready event is never delayed by a
   trim, then the trim (`core_heap_trim`, unless the last one is too recent), then the wait for what is left of the time. */
static int core_poll_idle_wait(CorePoller *poller, struct epoll_event *raw, int max, int64_t timeout) {
    if (!core_heap_look_allowed()) return core_poll_epoll_wait_apart(poller, raw, max, timeout);
    int ready = core_poll_epoll_wait_apart(poller, raw, max, 0);
    if (ready != 0) return ready;
    int64_t began = timeout > 0 ? core_poll_now_ms() : 0;
    core_heap_trim();
    if (timeout > 0) {
        timeout -= core_poll_now_ms() - began;
        if (timeout < 0) timeout = 0;
    }
    return core_poll_epoll_wait_apart(poller, raw, max, timeout);
}
static void core_poll_wait(CorePoller *poller, uint32_t timeout_word, uint32_t max_word) {
    int64_t timeout = timeout_word == UINT32_MAX ? -1 : timeout_word > CORE_POLL_LONGEST_MS ? CORE_POLL_LONGEST_MS : timeout_word;
    size_t max = max_word == 0 ? 1 : max_word > CORE_POLL_MAX_EVENTS ? CORE_POLL_MAX_EVENTS : max_word;
    if (core_poll_timing(poller) && poller->open > 0) {
        int64_t now = core_poll_now_ms(), deadline = INT64_MAX;
        for (size_t i = 0; i < poller->capacity; ++i) {
            if (poller->entries[i].fd < 0 || poller->entries[i].state == CORE_POLL_DIAL_FAILED) continue;
            if (poller->entries[i].state == CORE_POLL_CONNECTING) {
                if (poller->entries[i].deadline_ms > 0 && poller->entries[i].deadline_ms < deadline) deadline = poller->entries[i].deadline_ms;
                continue;
            }
            int64_t idle = core_poll_idle_of(poller, &poller->entries[i]);
            if (idle > 0 && poller->entries[i].active_ms + idle < deadline) deadline = poller->entries[i].active_ms + idle;
        }
        int64_t remaining = deadline > now ? deadline - now : 0;
        if (deadline != INT64_MAX && (timeout < 0 || remaining < timeout)) timeout = remaining;
    }
    struct epoll_event raw[CORE_POLL_MAX_EVENTS];
    if (timeout != 0) core_flush_before_wait();
    int ready = timeout != 0 && core_heap_look_due() && core_poll_idle(poller, timeout)
                    ? core_poll_idle_wait(poller, raw, (int)max, timeout)
                    : core_poll_epoll_wait(poller, raw, (int)max, timeout);
    if (ready > 0) poller->quiet_ms = 0;
    else if (poller->quiet_ms == 0) poller->quiet_ms = core_poll_now_ms();
    uint32_t ids[CORE_POLL_MAX_EVENTS], flags[CORE_POLL_MAX_EVENTS];
    /* Which event (plus one) names a slot, so the idle scan can merge into it: `poller->at`, cleared again below. */
    uint16_t *at = poller->at;
    size_t count = 0;
    for (int i = 0; i < ready; ++i) {
        if (raw[i].data.u64 == CORE_POLL_STOP_TOKEN) continue;
        uint32_t id = (uint32_t)raw[i].data.u64;
        CorePollEntry *entry = id ? core_poll_entry(poller, id) : NULL;
        if (id && !entry) continue;
        uint32_t bits = 0, events = raw[i].events;
        unsigned interest = entry ? entry->interest : poller->listener_interest;
        if (entry && entry->state == CORE_POLL_CONNECTING) {
            ids[count] = id;
            flags[count] = core_poll_connect_finished(poller, entry, id);
            at[core_poll_slot_of(poller, id, NULL)] = (uint16_t)(count + 1);
            ++count;
            continue;
        }
        if (events & EPOLLIN) bits |= CORE_POLL_READABLE;
        if (events & EPOLLOUT) bits |= CORE_POLL_WRITABLE;
        if (events & (EPOLLRDHUP | EPOLLHUP)) bits |= CORE_POLL_HANGUP;
        if (events & EPOLLERR) bits |= CORE_POLL_ERROR;
        /* A hangup or error completes the next receive at once, so it reads as readable. */
        if ((bits & (CORE_POLL_HANGUP | CORE_POLL_ERROR)) && (interest & CORE_POLL_READABLE)) bits |= CORE_POLL_READABLE;
        ids[count] = id;
        flags[count] = bits;
        if (entry) at[core_poll_slot_of(poller, id, NULL)] = (uint16_t)(count + 1);
        ++count;
    }
    if (core_poll_timing(poller)) {
        int64_t now = core_poll_now_ms();
        for (size_t slot = 0; slot < poller->capacity; ++slot) {
            CorePollEntry *entry = &poller->entries[slot];
            if (entry->fd < 0 || entry->state == CORE_POLL_DIAL_FAILED) continue;
            if (entry->state == CORE_POLL_CONNECTING) {
                /* A connect that has not finished within its limit fails as timed out. */
                if (entry->deadline_ms <= 0 || now < entry->deadline_ms || (!at[slot] && count >= max)) continue;
                uint32_t bits = core_poll_connect_failed(poller, entry, ETIMEDOUT);
                if (at[slot]) flags[at[slot] - 1] |= bits;
                else { ids[count] = core_poll_id(poller, slot); flags[count] = bits; ++count; }
                continue;
            }
            int64_t idle = core_poll_idle_of(poller, entry);
            if (idle <= 0 || now - entry->active_ms < idle) continue;
            if (at[slot]) flags[at[slot] - 1] |= CORE_POLL_IDLE;
            else if (count < max) {
                ids[count] = core_poll_id(poller, slot);
                flags[count] = CORE_POLL_IDLE;
                ++count;
            } else continue;
            entry->active_ms = now;
        }
    }
    unsigned char *out = core_poll_reply(poller, CORE_POLL_OK, (uint32_t)count, 0, count * 8);
    for (size_t i = 0; i < count; ++i) {
        core_poll_put(out + i * 8, ids[i]);
        core_poll_put(out + i * 8 + 4, flags[i]);
        at[core_poll_slot_of(poller, ids[i], NULL)] = 0;
    }
}
static void core_poll_receive(CorePoller *poller, uint32_t id, uint32_t limit) {
    CorePollEntry *entry = core_poll_entry(poller, id);
    if (!entry) { core_poll_reply(poller, CORE_POLL_UNKNOWN, 0, 0, 0); return; }
    if (entry->state == CORE_POLL_CONNECTING) { core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0); return; }
    if (entry->state == CORE_POLL_DIAL_FAILED) { core_poll_fail(poller, entry->failure); return; }
    if (limit > CORE_POLL_TRANSFER) limit = CORE_POLL_TRANSFER;
    if (limit == 0) { core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0); return; }
    ssize_t width;
    do width = recv(entry->fd, poller->response + CORE_POLL_RESPONSE_HEADER, limit, MSG_DONTWAIT); while (width < 0 && errno == EINTR);
    if (width > 0) { entry->active_ms = core_poll_now_ms(); core_poll_reply(poller, CORE_POLL_OK, (uint32_t)width, 0, (size_t)width); }
    else if (width == 0) core_poll_reply(poller, CORE_POLL_CLOSED, 0, 0, 0);
    else if (errno == EAGAIN || errno == EWOULDBLOCK) core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0);
    else core_poll_fail(poller, errno);
}
static void core_poll_send(CorePoller *poller, uint32_t id, const unsigned char *data, size_t length) {
    CorePollEntry *entry = core_poll_entry(poller, id);
    if (!entry) { core_poll_reply(poller, CORE_POLL_UNKNOWN, 0, 0, 0); return; }
    if (entry->state == CORE_POLL_CONNECTING) { core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0); return; }
    if (entry->state == CORE_POLL_DIAL_FAILED) { core_poll_fail(poller, entry->failure); return; }
    if (!length) { core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0); return; }
    ssize_t width;
    do width = send(entry->fd, data, length, MSG_NOSIGNAL | MSG_DONTWAIT); while (width < 0 && errno == EINTR);
    if (width >= 0) { if (width > 0) entry->active_ms = core_poll_now_ms(); core_poll_reply(poller, CORE_POLL_OK, (uint32_t)width, 0, 0); }
    else if (errno == EAGAIN || errno == EWOULDBLOCK) core_poll_reply(poller, CORE_POLL_WOULD_BLOCK, 0, 0, 0);
    else core_poll_fail(poller, errno);
}
static void core_poll_info(CorePoller *poller, unsigned what, uint32_t id) {
    struct sockaddr_in address;
    socklen_t width = sizeof address;
    if (what == 3) { core_poll_reply(poller, CORE_POLL_OK, (uint32_t)poller->limit, (uint32_t)poller->open, 0); return; }
    if (what != 1 && what != 2) { core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0); return; }
    CorePollEntry *entry = id ? core_poll_entry(poller, id) : NULL;
    if (id && !entry) { core_poll_reply(poller, CORE_POLL_UNKNOWN, 0, 0, 0); return; }
    if (what == 2 && !entry) { core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0); return; }
    if (!entry && poller->listener_fd < 0) { core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0); return; }
    int fd = entry ? entry->fd : poller->listener_fd;
    int status = what == 1 ? getsockname(fd, (struct sockaddr *)&address, &width) : getpeername(fd, (struct sockaddr *)&address, &width);
    if (status < 0 || address.sin_family != AF_INET) { core_poll_fail(poller, status < 0 ? errno : EAFNOSUPPORT); return; }
    if (what == 1) core_poll_reply(poller, CORE_POLL_OK, ntohs(address.sin_port), 0, 0);
    else core_poll_reply(poller, CORE_POLL_OK, ntohl(address.sin_addr.s_addr), ntohs(address.sin_port), 0);
}
static void core_poll_config(CorePoller *poller, unsigned what, uint32_t id, uint32_t value) {
    if (what == 1) {
        int64_t millis = value > CORE_POLL_LONGEST_MS ? CORE_POLL_LONGEST_MS : value;
        if (poller->idle_ms == 0 && millis > 0) {
            int64_t now = core_poll_now_ms();
            for (size_t i = 0; i < poller->capacity; ++i) if (poller->entries[i].fd >= 0) poller->entries[i].active_ms = now;
        }
        poller->idle_ms = millis;
        core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0);
        return;
    }
    if (what == 3) {
        /* One connection's own idle timeout: UINT32_MAX returns it to the poller's, 0 never times it out. Setting it
           restarts the connection's timer. */
        CorePollEntry *entry = id ? core_poll_entry(poller, id) : NULL;
        if (!entry) { core_poll_reply(poller, id ? CORE_POLL_UNKNOWN : CORE_POLL_BAD, 0, 0, 0); return; }
        int64_t millis = value > CORE_POLL_LONGEST_MS ? (int64_t)CORE_POLL_LONGEST_MS : (int64_t)value;
        if (value == UINT32_MAX) millis = CORE_POLL_IDLE_INHERIT;
        if (entry->idle_ms == CORE_POLL_IDLE_INHERIT && millis != CORE_POLL_IDLE_INHERIT) ++poller->own_idle;
        if (entry->idle_ms != CORE_POLL_IDLE_INHERIT && millis == CORE_POLL_IDLE_INHERIT) --poller->own_idle;
        entry->idle_ms = millis;
        entry->active_ms = core_poll_now_ms();
        core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0);
        return;
    }
    if (what != 2 || (value & ~(unsigned)(CORE_POLL_READABLE | CORE_POLL_WRITABLE))) { core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0); return; }
    if (id == 0) {
        if (poller->listener_fd < 0) { core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0); return; }
        poller->listener_interest = value & CORE_POLL_READABLE;
        core_poll_sync_listener(poller);
        core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0);
        return;
    }
    CorePollEntry *entry = core_poll_entry(poller, id);
    if (!entry) { core_poll_reply(poller, CORE_POLL_UNKNOWN, 0, 0, 0); return; }
    /* A connecting connection is watched for its connect; the interest applies once it is open. */
    if (entry->state != CORE_POLL_OPEN) { entry->interest = value; core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0); return; }
    struct epoll_event event = {.events = core_poll_epoll_events(value), .data.u64 = id};
    if (epoll_ctl(poller->epoll_fd, EPOLL_CTL_MOD, entry->fd, &event) < 0) { core_poll_fail(poller, errno); return; }
    entry->interest = value;
    core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0);
}
/* Run one command and leave its response for the next read. A malformed command
   is answered in band (`bad`), never by failing the write. */
static CoreIoResourceWrite core_poll_command(CorePoller *poller, const uint8_t *command, size_t length) {
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_OK, length};
    poller->response_length = poller->response_position = 0;
    if (length < CORE_POLL_COMMAND_HEADER) { core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0); return result; }
    unsigned op = command[0], what = command[1];
    uint32_t id = core_poll_get(command + 4), a = core_poll_get(command + 8), b = core_poll_get(command + 12);
    switch (op) {
    case CORE_POLL_WAIT: core_poll_wait(poller, a, b); break;
    case CORE_POLL_ACCEPT: core_poll_accept(poller); break;
    case CORE_POLL_RECV: core_poll_receive(poller, id, a); break;
    case CORE_POLL_SEND: core_poll_send(poller, id, command + CORE_POLL_COMMAND_HEADER, length - CORE_POLL_COMMAND_HEADER); break;
    case CORE_POLL_CLOSE: {
        CorePollEntry *entry = id ? core_poll_entry(poller, id) : NULL;
        if (!entry) core_poll_reply(poller, id ? CORE_POLL_UNKNOWN : CORE_POLL_BAD, 0, 0, 0);
        else if (what == 1) {
            if (shutdown(entry->fd, SHUT_WR) < 0) core_poll_fail(poller, errno); else core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0);
        } else { core_poll_drop(poller, entry); core_poll_reply(poller, CORE_POLL_OK, 0, 0, 0); }
        break;
    }
    case CORE_POLL_INFO: core_poll_info(poller, what, id); break;
    case CORE_POLL_CONFIG: core_poll_config(poller, what, id, a); break;
    case CORE_POLL_DIAL_TOKEN: core_poll_reply(poller, CORE_POLL_OK, poller->token, 0, 0); break;
    default: core_poll_reply(poller, CORE_POLL_BAD, 0, 0, 0);
    }
    return result;
}
/* Hand back the last command's response, up to `capacity` bytes at a time; `eof`
   is set once the whole response has been delivered. */
static CoreIoResourceRead core_poll_response(CorePoller *poller, uint8_t *out, size_t capacity) {
    size_t remaining = poller->response_length - poller->response_position;
    size_t take = remaining < capacity ? remaining : capacity;
    if (take) memcpy(out, poller->response + poller->response_position, take);
    poller->response_position += take;
    CoreIoResourceRead result = {CORE_IO_PROVIDER_OK, take, poller->response_position == poller->response_length};
    return result;
}
