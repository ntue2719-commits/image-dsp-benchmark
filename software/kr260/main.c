
#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64

/*
 * KR260 Linux AXI4-Lite Image DSP Debug
 *
 * Build:
 * gcc -O2 -std=c11 -Wall -Wextra main.c -o main
 *
 * Default:
 * sudo ./main --probe
 *
 * IMPORTANT:
 * RTL currently expects WSTRB = 4'b0001 for CTRL/input writes.
 * Therefore, use 8-bit MMIO writes for these accesses.
 *
 * Register and output reads use 32-bit MMIO.
 *
 * A faulty AXI transaction may hang the board.
 * Test individual actions before running a whole frame.
 */

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

/* ============================================================
 * AXI ADDRESS MAP
 * ============================================================ */

#ifndef DSP_BASE_PHYS
#define DSP_BASE_PHYS UINT64_C(0x00A0000000)
#endif

#define WINDOW_SIZE UINT64_C(0x02000000)

#define REG_CTRL             0x00000000u
#define REG_STATUS           0x00000004u
#define REG_INFO_WIDTH       0x00000008u
#define REG_INFO_HEIGHT      0x0000000Cu
#define REG_INFO_THRESHOLD   0x00000010u

#define INPUT_BASE           0x00100000u
#define OUTPUT_BASE          0x01100000u

/* Commands */
#define CMD_LOAD             0x01u
#define CMD_START            0x02u
#define CMD_STOP             0x04u

/* Status bits */
#define ST_IDLE              0x01u
#define ST_LOAD              0x02u
#define ST_EXEC              0x04u
#define ST_READ              0x08u
#define ST_DONE              0x20u
#define ST_ERROR             0x40u

/* ============================================================
 * GLOBAL VARIABLES
 * ============================================================ */

struct mapped {
    volatile uint8_t *ptr;
    size_t len;
};

static struct mapped regs;
static struct mapped in_mem;
static struct mapped out_mem;

static FILE *logfile = NULL;
static int memfd = -1;

static bool full_trace = false;

static uint32_t width;
static uint32_t height;

static size_t num_in;
static size_t num_out;

/* ============================================================
 * TIME
 * ============================================================ */

static uint64_t ns_now(void)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
        perror("clock_gettime");
        exit(EXIT_FAILURE);
    }

    return (uint64_t)ts.tv_sec * UINT64_C(1000000000)
         + (uint64_t)ts.tv_nsec;
}

/* ============================================================
 * DEBUG LOGGING
 * ============================================================ */

static void logline(const char *fmt, ...)
{
    uint64_t t = ns_now();

    va_list ap;
    va_list copy;

    va_start(ap, fmt);
    va_copy(copy, ap);

    fprintf(stderr,
            "[%" PRIu64 ".%03" PRIu64 "] ",
            (uint64_t)(t / 1000000000u),
            (uint64_t)((t / 1000000u) % 1000u));

    vfprintf(stderr, fmt, ap);

    fputc('\n', stderr);
    fflush(stderr);

    if (logfile) {

        fprintf(logfile,
                "[%" PRIu64 ".%03" PRIu64 "] ",
                (uint64_t)(t / 1000000000u),
                (uint64_t)((t / 1000000u) % 1000u));

        vfprintf(logfile, fmt, copy);

        fputc('\n', logfile);
        fflush(logfile);

        if (fsync(fileno(logfile)) < 0) {
            perror("fsync debug log");
        }
    }

    va_end(copy);
    va_end(ap);
}

/* ============================================================
 * MMIO MAPPING
 * ============================================================ */

static bool map_region(
    struct mapped *m,
    uint32_t offset,
    size_t bytes,
    bool writable
)
{
    uint64_t pa = DSP_BASE_PHYS + offset;

    long page = sysconf(_SC_PAGESIZE);

    if (page <= 0 ||
        pa % (uint64_t)page ||
        !bytes ||
        (uint64_t)offset + bytes > WINDOW_SIZE) {

        logline("Invalid mapping: off=0x%08" PRIx32
                " bytes=%zu", offset, bytes);

        return false;
    }

    int prot = PROT_READ |
               (writable ? PROT_WRITE : 0);

    void *p = mmap(
        NULL,
        bytes,
        prot,
        MAP_SHARED,
        memfd,
        (off_t)pa
    );

    if (p == MAP_FAILED) {

        logline("mmap(0x%010" PRIx64 ", %zu): %s",
                pa, bytes, strerror(errno));

        return false;
    }

    m->ptr = (volatile uint8_t *)p;
    m->len = bytes;

    return true;
}

/* ============================================================
 * AXI MMIO READ / WRITE
 * ============================================================ */

static uint32_t read32(
    const struct mapped *m,
    uint32_t offset,
    const char *label,
    bool trace
)
{
    if (trace) {
        logline("BEFORE READ %s offset=0x%08" PRIx32,
                label, offset);
    }

    uint32_t value =
        *(volatile const uint32_t *)(m->ptr + offset);

    if (trace) {
        logline("AFTER  READ %s = 0x%08" PRIx32,
                label, value);
    }

    return value;
}

/*
 * Byte write:
 * On the current AArch64 AXI path, an aligned byte store
 * is expected to generate WSTRB = 0001.
 */

static void write8(
    const struct mapped *m,
    uint32_t offset,
    uint8_t value,
    const char *label,
    bool trace
)
{
    if (trace) {
        logline("BEFORE WRITE8 %s offset=0x%08" PRIx32
                " data=0x%02x",
                label,
                offset,
                (unsigned)value);
    }

    *(volatile uint8_t *)(m->ptr + offset) = value;

    if (trace) {
        logline("AFTER  WRITE8 %s", label);
    }
}

/* ============================================================
 * STATUS / FSM
 * ============================================================ */

static uint32_t status(bool trace)
{
    return read32(
        &regs,
        REG_STATUS,
        "STATUS",
        trace
    );
}

static bool state_is(uint32_t bit, const char *wanted)
{
    uint32_t s = status(true);

    if ((s & ST_ERROR) || !(s & bit)) {

        logline("State check FAILED: wanted %s; "
                "STATUS=0x%08" PRIx32,
                wanted, s);

        if (s & ST_ERROR) {
            logline("Sticky ERROR detected. "
                    "Reset/reload IP before retrying.");
        }

        return false;
    }

    return true;
}

static bool wait_for(uint32_t bits, uint64_t ms)
{
    uint64_t deadline =
        ns_now() + ms * UINT64_C(1000000);

    uint32_t last = 0;

    logline("WAIT STATUS mask=0x%08" PRIx32
            " timeout=%" PRIu64 "ms",
            bits, ms);

    while (ns_now() < deadline) {

        last = status(false);

        if (last & ST_ERROR) {

            logline("FAILED: sticky STATUS.ERROR "
                    "(0x%08" PRIx32 ")",
                    last);

            return false;
        }

        if ((last & bits) == bits) {

            logline("WAIT OK STATUS=0x%08" PRIx32,
                    last);

            return true;
        }

        struct timespec pause = {
            .tv_sec = 0,
            .tv_nsec = 1000000
        };

        nanosleep(&pause, NULL);
    }

    logline("TIMEOUT last STATUS=0x%08" PRIx32,
            last);

    return false;
}

/* ============================================================
 * HEX FILE I/O
 * ============================================================ */

static bool read_image_hex(
    const char *path,
    uint8_t *buf,
    size_t count
)
{
    FILE *f = fopen(path, "r");

    if (!f) {
        logline("open %s: %s", path, strerror(errno));
        return false;
    }

    char line[256];

    for (size_t i = 0; i < count; ++i) {

        unsigned int x;
        char extra;

        if (!fgets(line, sizeof line, f) ||
            sscanf(line, " %x %c", &x, &extra) != 1 ||
            x > 255) {

            logline("Bad/missing HEX line at index "
                    "%zu in %s", i, path);

            fclose(f);
            return false;
        }

        buf[i] = (uint8_t)x;
    }

    while (fgets(line, sizeof line, f)) {

        if (strspn(line, " \t\r\n") != strlen(line)) {

            logline("Extra pixel after %zu lines in %s",
                    count, path);

            fclose(f);
            return false;
        }
    }

    fclose(f);

    return true;
}

static bool save_image_hex(
    const char *path,
    const uint8_t *buf,
    size_t count
)
{
    FILE *f = fopen(path, "w");

    if (!f) {
        logline("open %s: %s", path, strerror(errno));
        return false;
    }

    for (size_t i = 0; i < count; i++) {

        if (fprintf(f, "%02X\n", buf[i]) < 0) {

            logline("write %s failed", path);

            fclose(f);
            return false;
        }
    }

    if (fclose(f) != 0) {
        logline("close %s failed", path);
        return false;
    }

    return true;
}

/* ============================================================
 * CTRL COMMAND
 * ============================================================ */

static bool ctrl(
    uint8_t command,
    uint32_t target,
    const char *what
)
{
    if (!state_is(target, what)) {
        return false;
    }

    logline("Issuing %s "
            "(8-bit store, WSTRB expected=0001)",
            what);

    write8(
        &regs,
        REG_CTRL,
        command,
        "CTRL",
        true
    );

    logline("CTRL write returned to userspace");

    return true;
}

/* ============================================================
 * INPUT MEMORY
 * ============================================================ */

static bool write_pixel(
    size_t index,
    uint8_t value,
    bool trace
)
{
    if (index >= num_in) {

        logline("Bad input index %zu >= %zu",
                index, num_in);

        return false;
    }

    uint32_t offset = (uint32_t)(4 * index);

    write8(
        &in_mem,
        offset,
        value,
        "INPUT",
        trace
    );

    return true;
}

static bool write_frame(const char *path)
{
    if (!state_is(ST_LOAD, "LOAD")) {
        return false;
    }

    uint8_t *in = calloc(num_in, 1);

    if (!in) {
        logline("Input allocation failed");
        return false;
    }

    if (path && !read_image_hex(path, in, num_in)) {
        free(in);
        return false;
    }

    logline("BEGIN input write %zu pixels (%s)",
            num_in,
            path ? path : "all zeros");

    uint64_t begin = ns_now();

    for (size_t i = 0; i < num_in; ++i) {

        bool trace =
            full_trace ||
            (i < 8) ||
            (i + 1 == num_in) ||
            (i % 256 == 0);

        if (trace) {
            logline("INPUT pixel %zu / %zu",
                    i, num_in);
        }

        if (!write_pixel(i, in[i], trace)) {
            free(in);
            return false;
        }

        if ((i + 1) % 256 == 0 ||
            i + 1 == num_in) {

            if (full_trace) {
                logline("Completed %zu input pixels",
                        i + 1);
            }

            if (status(false) & ST_ERROR) {

                logline("STATUS.ERROR after pixel %zu",
                        i);

                free(in);
                return false;
            }
        }
    }

    logline("END input write; %.3f ms",
            (double)(ns_now() - begin) / 1e6);

    free(in);

    return true;
}

/* ============================================================
 * OUTPUT MEMORY
 * ============================================================ */

static bool read_pixel(size_t index)
{
    if (!state_is(ST_READ, "READ")) {
        return false;
    }

    if (index >= num_out) {

        logline("Bad output index %zu >= %zu",
                index, num_out);

        return false;
    }

    uint32_t word = read32(
        &out_mem,
        (uint32_t)(4 * index),
        "OUTPUT",
        true
    );

    logline("OUTPUT k=%zu x=%zu y=%zu "
            "word=0x%08" PRIx32,
            index,
            2 + index % (width - 4),
            2 + index / (width - 4),
            word);

    return (word & ~UINT32_C(0xff)) == 0;
}

static bool read_frame(
    const char *golden_path,
    const char *out_path,
    bool is_zero
)
{
    if (!state_is(ST_READ, "READ")) {
        return false;
    }

    uint8_t *golden = NULL;

    if (golden_path) {

        golden = malloc(num_in);

        if (!golden) {
            logline("Golden allocation failed");
            return false;
        }

        if (!read_image_hex(
                golden_path,
                golden,
                num_in)) {

            free(golden);
            return false;
        }
    }

    uint8_t *output = malloc(num_out);

    if (!output) {
        free(golden);
        return false;
    }

    size_t errors = 0;

    logline("BEGIN output read %zu pixels", num_out);

    uint64_t begin = ns_now();

    for (size_t i = 0; i < num_out; ++i) {

        bool trace =
            full_trace ||
            (i < 8) ||
            (i + 1 == num_out) ||
            (i % 256 == 0);

        if (trace) {
            logline("OUTPUT pixel %zu / %zu",
                    i, num_out);
        }

        uint32_t word = read32(
            &out_mem,
            (uint32_t)(4 * i),
            "OUTPUT",
            trace
        );

        output[i] = (uint8_t)word;

        size_t x = 2 + i % (width - 4);
        size_t y = 2 + i / (width - 4);

        uint8_t want = golden
            ? golden[y * width + x]
            : 0;

        bool compare = golden != NULL || is_zero;

        if ((word & ~UINT32_C(0xff)) ||
            (compare && output[i] != want)) {

            ++errors;

            if (errors <= 10) {

                logline(
                    "MISMATCH k=%zu x=%zu y=%zu "
                    "read=0x%08" PRIx32
                    " want=0x%02x",
                    i, x, y,
                    word,
                    want
                );
            }
        }
    }

    logline("END output read; %.3f ms; errors=%zu",
            (double)(ns_now() - begin) / 1e6,
            errors);

    bool ok = errors == 0;

    if (out_path &&
        !save_image_hex(out_path, output, num_out)) {
        ok = false;
    }

    free(output);
    free(golden);

    return ok;
}

/* ============================================================
 * ARGUMENTS
 * ============================================================ */

static void usage(const char *exe)
{
    fprintf(stderr,
        "Usage: %s [--log debug.log] "
        "[--trace-all] ACTION [args]\n"
        "\n"
        "  --probe                         Read-only\n"
        "  --load                          IDLE -> LOAD\n"
        "  --write-pixel INDEX BYTE        Write one pixel\n"
        "  --write-frame [noisy.hex]       Write frame\n"
        "  --start                         LOAD -> EXEC -> READ\n"
        "  --read-pixel INDEX              Read one output\n"
        "  --read-frame [golden [out]]     Read output frame\n"
        "  --stop                          READ -> IDLE\n"
        "  --run [input [golden [out]]]    Full workflow\n"
        "\n"
        "Default action: --probe\n",
        exe
    );
}

static bool parse_size(
    const char *s,
    size_t *result
)
{
    if (!s || s[0] == '-') {
        return false;
    }

    errno = 0;

    char *end = NULL;

    unsigned long long v =
        strtoull(s, &end, 0);

    if (errno ||
        !end ||
        *end ||
        end == s ||
        v > SIZE_MAX) {

        return false;
    }

    *result = (size_t)v;

    return true;
}

/* ============================================================
 * MAIN
 * ============================================================ */

int main(int argc, char **argv)
{
    int i = 1;

    while (i < argc) {

        if (strcmp(argv[i], "--log") == 0 &&
            i + 1 < argc) {

            logfile = fopen(argv[i + 1], "a");

            if (!logfile) {
                perror("open log");
                return EXIT_FAILURE;
            }

            i += 2;

        } else if (strcmp(argv[i], "--trace-all") == 0) {

            full_trace = true;
            i++;

        } else {
            break;
        }
    }

    const char *action =
        i < argc ? argv[i++] : "--probe";

    int nargs = argc - i;

    bool writable =
        strcmp(action, "--probe") != 0 &&
        strcmp(action, "--read-pixel") != 0 &&
        strcmp(action, "--read-frame") != 0;

    int rc = EXIT_FAILURE;

    /* Open /dev/mem */

    memfd = open(
        "/dev/mem",
        (writable ? O_RDWR : O_RDONLY) | O_SYNC
    );

    if (memfd < 0) {

        logline("open /dev/mem failed: %s",
                strerror(errno));

        goto done;
    }

    /* Map register page */

    if (!map_region(&regs, 0, 4096, writable)) {
        goto done;
    }

    logline("DSP base 0x%010" PRIx64
            ", action %s",
            (uint64_t)DSP_BASE_PHYS,
            action);

    /* Read IP information */

    width = read32(
        &regs,
        REG_INFO_WIDTH,
        "INFO_WIDTH",
        true
    );

    height = read32(
        &regs,
        REG_INFO_HEIGHT,
        "INFO_HEIGHT",
        true
    );

    uint32_t threshold = read32(
        &regs,
        REG_INFO_THRESHOLD,
        "INFO_THRESHOLD",
        true
    );

    uint32_t s = status(true);

    logline(
        "DSP INFO width=%" PRIu32
        " height=%" PRIu32
        " threshold=%" PRIu32
        " STATUS=0x%08" PRIx32,
        width, height, threshold, s
    );

    /* Validate dimensions */

    if (width < 5 ||
        height < 5 ||
        width > 4096 ||
        height > 4096 ||
        (uint64_t)width * height > UINT64_C(8388608)) {

        logline("INVALID INFO - check bitstream/address map");
        goto done;
    }

    num_in = (size_t)width * height;
    num_out = (size_t)(width - 4) * (height - 4);

    if ((uint64_t)INPUT_BASE + 4u * num_in > OUTPUT_BASE ||
        (uint64_t)OUTPUT_BASE + 4u * num_out > WINDOW_SIZE) {

        logline("Frame too large for AXI address windows");
        goto done;
    }

    logline("Image: input=%zu output=%zu",
            num_in, num_out);

    /* ========================================================
     * T1: READ-ONLY PROBE
     * ======================================================== */

    if (strcmp(action, "--probe") == 0 &&
        nargs == 0) {

        logline("PASS read-only probe; no writes performed");
        rc = EXIT_SUCCESS;
    }

    /* ========================================================
     * T2: LOAD COMMAND
     * ======================================================== */

    else if (strcmp(action, "--load") == 0 &&
             nargs == 0) {

        if (ctrl(CMD_LOAD, ST_IDLE, "IDLE")) {

            rc = wait_for(ST_LOAD, 2000)
                ? EXIT_SUCCESS
                : EXIT_FAILURE;
        }
    }

    /* ========================================================
     * T3: WRITE ONE INPUT PIXEL
     * ======================================================== */

    else if (strcmp(action, "--write-pixel") == 0 &&
             nargs == 2) {

        size_t idx;
        size_t val;

        if (!parse_size(argv[i], &idx) ||
            !parse_size(argv[i + 1], &val) ||
            val > 255) {

            logline("Expected INDEX and BYTE "
                    "(decimal or 0x-prefixed hex)");

            goto done;
        }

        if (!state_is(ST_LOAD, "LOAD") ||
            !map_region(
                &in_mem,
                INPUT_BASE,
                num_in * 4,
                true)) {

            goto done;
        }

        if (!write_pixel(
                idx,
                (uint8_t)val,
                true)) {

            goto done;
        }

        logline("Checking STATUS after pixel write");

        if (state_is(ST_LOAD, "LOAD")) {
            rc = EXIT_SUCCESS;
        }
    }

    /* ========================================================
     * T4: WRITE WHOLE INPUT FRAME
     * ======================================================== */

    else if (strcmp(action, "--write-frame") == 0 &&
             nargs <= 1) {

        if (!state_is(ST_LOAD, "LOAD") ||
            !map_region(
                &in_mem,
                INPUT_BASE,
                num_in * 4,
                true)) {

            goto done;
        }

        rc = write_frame(
            nargs ? argv[i] : NULL
        ) ? EXIT_SUCCESS : EXIT_FAILURE;
    }

    /* ========================================================
     * T5: START DSP
     * ======================================================== */

    else if (strcmp(action, "--start") == 0 &&
             nargs == 0) {

        if (!ctrl(CMD_START, ST_LOAD, "LOAD")) {
            goto done;
        }

        rc = wait_for(
            ST_READ | ST_DONE,
            10000
        ) ? EXIT_SUCCESS : EXIT_FAILURE;
    }

    /* ========================================================
     * T6: READ ONE OUTPUT PIXEL
     * ======================================================== */

    else if (strcmp(action, "--read-pixel") == 0 &&
             nargs == 1) {

        size_t idx;

        if (!parse_size(argv[i], &idx)) {
            logline("Invalid output pixel index");
            goto done;
        }

        if (!state_is(ST_READ, "READ") ||
            !map_region(
                &out_mem,
                OUTPUT_BASE,
                num_out * 4,
                false)) {

            goto done;
        }

        rc = read_pixel(idx)
            ? EXIT_SUCCESS
            : EXIT_FAILURE;
    }

    /* ========================================================
     * T7: READ OUTPUT FRAME
     * ======================================================== */

    else if (strcmp(action, "--read-frame") == 0 &&
             nargs <= 2) {

        if (!state_is(ST_READ, "READ") ||
            !map_region(
                &out_mem,
                OUTPUT_BASE,
                num_out * 4,
                false)) {

            goto done;
        }

        rc = read_frame(
            nargs >= 1 ? argv[i] : NULL,
            nargs >= 2 ? argv[i + 1] : NULL,
            false
        ) ? EXIT_SUCCESS : EXIT_FAILURE;
    }

    /* ========================================================
     * T8: STOP DSP
     * ======================================================== */

    else if (strcmp(action, "--stop") == 0 &&
             nargs == 0) {

        if (!ctrl(CMD_STOP, ST_READ, "READ")) {
            goto done;
        }

        rc = wait_for(ST_IDLE, 2000)
            ? EXIT_SUCCESS
            : EXIT_FAILURE;
    }

    /* ========================================================
     * FULL WORKFLOW
     * ======================================================== */

    else if (strcmp(action, "--run") == 0 &&
             nargs <= 3) {

        logline("FULL RUN started");

        if (!ctrl(CMD_LOAD, ST_IDLE, "IDLE") ||
            !wait_for(ST_LOAD, 2000)) {

            goto done;
        }

        if (!map_region(
                &in_mem,
                INPUT_BASE,
                num_in * 4,
                true)) {

            goto done;
        }

        if (!write_frame(
                nargs >= 1 ? argv[i] : NULL)) {

            goto done;
        }

        if (!ctrl(CMD_START, ST_LOAD, "LOAD") ||
            !wait_for(ST_READ | ST_DONE, 10000)) {

            goto done;
        }

        if (!map_region(
                &out_mem,
                OUTPUT_BASE,
                num_out * 4,
                false)) {

            goto done;
        }

        if (!read_frame(
                nargs >= 2 ? argv[i + 1] : NULL,
                nargs >= 3 ? argv[i + 2] : NULL,
                nargs == 0)) {

            goto done;
        }

        if (!ctrl(CMD_STOP, ST_READ, "READ") ||
            !wait_for(ST_IDLE, 2000)) {

            goto done;
        }

        logline("PASS full run completed");
        rc = EXIT_SUCCESS;
    }

    else {
        usage(argv[0]);
    }

    if (rc == EXIT_SUCCESS) {
        logline("ACTION SUCCESS");
    } else {
        logline("ACTION FAILED");
    }

/* ============================================================
 * CLEANUP
 * ============================================================ */

done:

    if (out_mem.ptr) {
        munmap((void *)out_mem.ptr, out_mem.len);
    }

    if (in_mem.ptr) {
        munmap((void *)in_mem.ptr, in_mem.len);
    }

    if (regs.ptr) {
        munmap((void *)regs.ptr, regs.len);
    }

    if (memfd >= 0) {
        close(memfd);
    }

    if (logfile) {
        fclose(logfile);
    }

    return rc;
}
