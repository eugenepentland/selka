/* The simulated register bank behind `registers.simulated()` (MCU-B1; experiments/mcu-20261118/B1.md).
 *
 * A `Registers` on this target names one bank: a little-endian memory of bytes kept as 32-bit words in an open-addressed
 * table, and a log of every write, oldest first. The handle is the bank's address. `simulated()` allocates the whole
 * bank at once (room for CORE_REGISTERS_WORDS distinct words and CORE_REGISTERS_LOG writes), so a read, a write or a poke
 * only indexes storage that exists and allocates nothing (`cost.zig`, `registersAllocationFree`); a bank or a log that is
 * full traps with R_REGISTER_BANK rather than grow. An address never written or poked reads 0. A write of any width
 * stores its bytes and appends one log entry; a poke stores and logs nothing. Banks are independent, are never freed by
 * the program (a handle is a scalar, 5C), and are all freed when the process or the test trial ends
 * (`core_registers_cleanup`, called by `core_io_cleanup`), so the leak check and ASan stay clean.
 *
 * Modelled hardware (MCU-B1D): a word may hold a script, values its next reads answer in order before the stored word
 * again (a running timer, a status that changes), copied when `script32` gives it, so a read allocates nothing; and pinned
 * bits, which every read answers with the pinned value whatever was written or poked (a PLL's lock bit). A read answers
 * per word it touches: the script's next value or the stored word, then the pinned bits.
 *
 * A bank is not shared between threads: a `parallel` task cannot take a `Registers` (E_TASK_CAPABILITY). A task may make
 * its own, so the list of banks is pushed onto atomically.
 *
 * The `cpu` operations (MCU-NOC1) do nothing to the machine on a bank and return at once, a wait too: each appends one
 * entry to the bank's event log (its kind, how many writes the bank had logged before it, and whether interrupts are off
 * after it), allocated with the bank, so a test reads how many of each ran and which writes happened with interrupts
 * held off. `interrupts_off` answers the bank's simulated PRIMASK before it, and `interrupts_restore` sets it back. */

#define CORE_REGISTERS_WORDS 4096u
/* Twice the words, a power of two: the probe sequence of a full table stays short. */
#define CORE_REGISTERS_SLOTS 8192u
#define CORE_REGISTERS_LOG 16384u
#define CORE_REGISTERS_EVENTS 16384u

/* The kinds of a recorded `cpu` operation, the order of `cpu.event_operation`'s names. */
enum { CORE_CPU_WAIT_FOR_EVENT, CORE_CPU_WAIT_FOR_INTERRUPT, CORE_CPU_SEND_EVENT, CORE_CPU_BARRIER, CORE_CPU_BREAKPOINT, CORE_CPU_INTERRUPTS_OFF, CORE_CPU_INTERRUPTS_RESTORE };

typedef struct { uint32_t address; uint32_t value; uint8_t width; } CoreRegisterWrite;
/* The values a word's next reads answer, `next` the first not yet answered. */
typedef struct { uint32_t length, next; uint32_t values[]; } CoreRegisterScript;
typedef struct { uint32_t writes_before; uint8_t kind; uint8_t off_after; } CoreCpuEvent;
typedef struct CoreRegisterBank {
    struct CoreRegisterBank *next;
    uint32_t words;
    uint32_t writes;
    uint32_t keys[CORE_REGISTERS_SLOTS];
    uint32_t values[CORE_REGISTERS_SLOTS];
    uint32_t pin_mask[CORE_REGISTERS_SLOTS];
    uint32_t pin_value[CORE_REGISTERS_SLOTS];
    CoreRegisterScript *scripts[CORE_REGISTERS_SLOTS];
    uint8_t used[CORE_REGISTERS_SLOTS];
    CoreRegisterWrite log[CORE_REGISTERS_LOG];
    uint32_t events;
    uint32_t interrupts_off;
    CoreCpuEvent event_log[CORE_REGISTERS_EVENTS];
} CoreRegisterBank;

static CoreRegisterBank *core_registers_banks;
static MYL_TLS char core_registers_message[160];

__attribute__((cold, noinline)) static void core_registers_fail(const char *code, const char *message) {
    core_failure_detail = message;
    core_io_failure(code);
}

static inline CoreRegisterBank *core_registers_bank(int64_t handle) { return (CoreRegisterBank *)(uintptr_t)handle; }

/* The slot of the word at `word` (a multiple of 4), or the free slot where it would go. */
static uint32_t core_registers_slot(const CoreRegisterBank *bank, uint32_t word) {
    uint32_t slot = (word >> 2) * 2654435761u & (CORE_REGISTERS_SLOTS - 1);
    while (bank->used[slot] && bank->keys[slot] != word) slot = (slot + 1) & (CORE_REGISTERS_SLOTS - 1);
    return slot;
}

/* The slot of the word at `word`, made (reading 0) if the bank has none yet; a full bank traps. */
static uint32_t core_registers_claim(CoreRegisterBank *bank, uint32_t word) {
    uint32_t slot = core_registers_slot(bank, word);
    if (!bank->used[slot]) {
        if (bank->words == CORE_REGISTERS_WORDS) core_registers_fail("R_REGISTER_BANK", "the simulated register bank is full: it holds 4096 distinct words");
        bank->used[slot] = 1;
        bank->keys[slot] = word;
        bank->values[slot] = 0;
        bank->words += 1;
    }
    return slot;
}

/* What one read answers for the word at `word`: its script's next value while one is left, else the stored word, with
 * its pinned bits in place. Each read that touches a scripted word takes one value. */
static uint32_t core_registers_answer(CoreRegisterBank *bank, uint32_t word) {
    uint32_t slot = core_registers_slot(bank, word);
    if (!bank->used[slot]) return 0;
    uint32_t value = bank->values[slot];
    CoreRegisterScript *script = bank->scripts[slot];
    if (script && script->next < script->length) value = script->values[script->next++];
    return (value & ~bank->pin_mask[slot]) | (bank->pin_value[slot] & bank->pin_mask[slot]);
}

static void core_registers_store_byte(CoreRegisterBank *bank, uint32_t address, uint8_t value) {
    uint32_t slot = core_registers_claim(bank, address & ~3u);
    uint32_t shift = (address & 3u) * 8u;
    bank->values[slot] = (bank->values[slot] & ~(0xffu << shift)) | ((uint32_t)value << shift);
}

/* Store the low `width` bits of `value` at `address`, little-endian; addresses wrap at 2^32. */
static void core_registers_store(CoreRegisterBank *bank, uint32_t address, uint32_t value, unsigned width) {
    for (unsigned octet = 0; octet < width / 8u; ++octet) core_registers_store_byte(bank, address + octet, (uint8_t)(value >> (octet * 8u)));
}

/* The low `width` bits at `address`, little-endian, from the one or two words the read touches (addresses wrap at 2^32). */
static uint32_t core_registers_load(CoreRegisterBank *bank, uint32_t address, unsigned width) {
    uint32_t word = address & ~3u, shift = (address & 3u) * 8u;
    uint64_t both = core_registers_answer(bank, word);
    if (shift + width > 32u) both |= (uint64_t)core_registers_answer(bank, word + 4u) << 32;
    return (uint32_t)((both >> shift) & ((1ull << width) - 1u));
}

static void core_registers_write(int64_t handle, uint32_t address, uint32_t value, unsigned width) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    if (bank->writes == CORE_REGISTERS_LOG) core_registers_fail("R_REGISTER_BANK", "the simulated register bank's write log is full: it holds 16384 writes");
    core_registers_store(bank, address, value, width);
    bank->log[bank->writes++] = (CoreRegisterWrite){ .address = address, .value = value, .width = (uint8_t)width };
}

static const CoreRegisterWrite *core_registers_entry(int64_t handle, int64_t index) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    if (index < 0 || index >= (int64_t)bank->writes) {
        snprintf(core_registers_message, sizeof core_registers_message, index < 0 ? "index out of range (index %lld, length %lld) (negative indexes are not allowed)" : "index out of range (index %lld, length %lld)", (long long)index, (long long)bank->writes);
        core_registers_fail("R_LIST_BOUNDS", core_registers_message);
    }
    return &bank->log[index];
}

/* A fresh bank: every address reads 0 and the log is empty. */
int64_t myl_core_registers_simulated(void) {
    CoreRegisterBank *bank = calloc(1, sizeof *bank);
    if (!bank) core_registers_fail("R_MEMORY_BUDGET", "memory budget exhausted");
    /* A `parallel` task may make a bank while another thread makes one. */
    bank->next = __atomic_load_n(&core_registers_banks, __ATOMIC_RELAXED);
    while (!__atomic_compare_exchange_n(&core_registers_banks, &bank->next, bank, true, __ATOMIC_RELEASE, __ATOMIC_RELAXED)) {}
    return (int64_t)(uintptr_t)bank;
}

uint8_t myl_core_registers_read8(int64_t handle, uint32_t address) { return (uint8_t)core_registers_load(core_registers_bank(handle), address, 8); }
uint16_t myl_core_registers_read16(int64_t handle, uint32_t address) { return (uint16_t)core_registers_load(core_registers_bank(handle), address, 16); }
uint32_t myl_core_registers_read32(int64_t handle, uint32_t address) { return core_registers_load(core_registers_bank(handle), address, 32); }
void myl_core_registers_write8(int64_t handle, uint32_t address, uint8_t value) { core_registers_write(handle, address, value, 8); }
void myl_core_registers_write16(int64_t handle, uint32_t address, uint16_t value) { core_registers_write(handle, address, value, 16); }
void myl_core_registers_write32(int64_t handle, uint32_t address, uint32_t value) { core_registers_write(handle, address, value, 32); }
/* Set what a read answers, as the hardware would: no log entry. */
void myl_core_registers_poke32(int64_t handle, uint32_t address, uint32_t value) { core_registers_store(core_registers_bank(handle), address, value, 32); }
/* The next reads of the word holding `address` answer `values` in order, then the stored word; the values are copied
 * now, replacing any left of an earlier script, and an empty list ends the word's script. */
void myl_core_registers_script32(int64_t handle, uint32_t address, const uint32_t *values, int64_t length) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    uint32_t slot = core_registers_claim(bank, address & ~3u);
    free(bank->scripts[slot]);
    bank->scripts[slot] = NULL;
    if (length == 0) return;
    if (length > (int64_t)UINT32_MAX) core_registers_fail("R_REGISTER_BANK", "a register script holds at most 4294967295 values");
    CoreRegisterScript *script = malloc(sizeof *script + (size_t)length * sizeof(uint32_t));
    if (!script) core_registers_fail("R_MEMORY_BUDGET", "memory budget exhausted");
    script->length = (uint32_t)length;
    script->next = 0;
    memcpy(script->values, values, (size_t)length * sizeof(uint32_t));
    bank->scripts[slot] = script;
}
/* Every read of the word holding `address` answers the bits of `mask` from `value`, whatever is written or poked there. */
void myl_core_registers_pin32(int64_t handle, uint32_t address, uint32_t mask, uint32_t value) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    uint32_t slot = core_registers_claim(bank, address & ~3u);
    bank->pin_mask[slot] = mask;
    bank->pin_value[slot] = value & mask;
}
int64_t myl_core_registers_write_count(int64_t handle) { return (int64_t)core_registers_bank(handle)->writes; }
uint32_t myl_core_registers_write_address(int64_t handle, int64_t index) { return core_registers_entry(handle, index)->address; }
uint32_t myl_core_registers_write_value(int64_t handle, int64_t index) { return core_registers_entry(handle, index)->value; }
int64_t myl_core_registers_write_width(int64_t handle, int64_t index) { return (int64_t)core_registers_entry(handle, index)->width; }

/* A list index out of range, as `core_registers_entry` reports one. */
static void core_registers_bounds(int64_t index, uint32_t length) {
    if (index >= 0 && index < (int64_t)length) return;
    snprintf(core_registers_message, sizeof core_registers_message, index < 0 ? "index out of range (index %lld, length %lld) (negative indexes are not allowed)" : "index out of range (index %lld, length %lld)", (long long)index, (long long)length);
    core_registers_fail("R_LIST_BOUNDS", core_registers_message);
}

static void core_cpu_record(int64_t handle, uint8_t kind) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    if (bank->events == CORE_REGISTERS_EVENTS) core_registers_fail("R_REGISTER_BANK", "the simulated register bank's event log is full: it holds 16384 cpu operations");
    bank->event_log[bank->events++] = (CoreCpuEvent){ .writes_before = bank->writes, .kind = kind, .off_after = (uint8_t)bank->interrupts_off };
}

void myl_core_registers_cpu_wait_for_event(int64_t handle) { core_cpu_record(handle, CORE_CPU_WAIT_FOR_EVENT); }
void myl_core_registers_cpu_wait_for_interrupt(int64_t handle) { core_cpu_record(handle, CORE_CPU_WAIT_FOR_INTERRUPT); }
void myl_core_registers_cpu_send_event(int64_t handle) { core_cpu_record(handle, CORE_CPU_SEND_EVENT); }
void myl_core_registers_cpu_barrier(int64_t handle) { core_cpu_record(handle, CORE_CPU_BARRIER); }
void myl_core_registers_cpu_breakpoint(int64_t handle) { core_cpu_record(handle, CORE_CPU_BREAKPOINT); }
/* PRIMASK before, 1 when interrupts were off already; they are off after. */
uint32_t myl_core_registers_cpu_interrupts_disable(int64_t handle) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    uint32_t before = bank->interrupts_off;
    bank->interrupts_off = 1;
    core_cpu_record(handle, CORE_CPU_INTERRUPTS_OFF);
    return before;
}
void myl_core_registers_cpu_interrupts_set(int64_t handle, uint32_t primask) {
    core_registers_bank(handle)->interrupts_off = primask & 1u;
    core_cpu_record(handle, CORE_CPU_INTERRUPTS_RESTORE);
}
int64_t myl_core_registers_cpu_event_count(int64_t handle) { return (int64_t)core_registers_bank(handle)->events; }
int64_t myl_core_registers_cpu_event_kind(int64_t handle, int64_t index) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    core_registers_bounds(index, bank->events);
    return (int64_t)bank->event_log[index].kind;
}
int64_t myl_core_registers_cpu_event_writes_before(int64_t handle, int64_t index) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    core_registers_bounds(index, bank->events);
    return (int64_t)bank->event_log[index].writes_before;
}
int64_t myl_core_registers_cpu_interrupts_now(int64_t handle) { return (int64_t)core_registers_bank(handle)->interrupts_off; }
/* Whether write `index` came while interrupts were off: the state after the newest operation recorded before it. */
int64_t myl_core_registers_cpu_write_interrupts_off(int64_t handle, int64_t index) {
    CoreRegisterBank *bank = core_registers_bank(handle);
    core_registers_bounds(index, bank->writes);
    int64_t off = 0;
    for (uint32_t event = 0; event < bank->events && (int64_t)bank->event_log[event].writes_before <= index; ++event) off = bank->event_log[event].off_after;
    return off;
}

/* Free every bank: the process or the test trial is ending. */
static void core_registers_cleanup(void) {
    while (core_registers_banks) {
        CoreRegisterBank *bank = core_registers_banks;
        core_registers_banks = bank->next;
        for (uint32_t slot = 0; slot < CORE_REGISTERS_SLOTS; ++slot) free(bank->scripts[slot]);
        free(bank);
    }
}
