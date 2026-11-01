#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint64_t now_ns(void) {
    struct timespec ts;
#ifdef CLOCK_MONOTONIC_RAW
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
#else
    clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static int cmp_u8(const void *a, const void *b) {
    int aa = *(const uint8_t *)a;
    int bb = *(const uint8_t *)b;
    return (aa > bb) - (aa < bb);
}

static int read_hex(const char *path, uint8_t *buf, size_t n) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); return -1; }
    char line[128];
    size_t i = 0;
    while (fgets(line, sizeof line, f)) {
        char *end = NULL;
        errno = 0;
        unsigned long v = strtoul(line, &end, 16);
        if (errno || end == line || v > 255) {
            fprintf(stderr, "%s: invalid hex at line %zu\n", path, i + 1);
            fclose(f); return -1;
        }
        if (i >= n) {
            fprintf(stderr, "%s: too many pixels (expected %zu)\n", path, n);
            fclose(f); return -1;
        }
        buf[i++] = (uint8_t)v;
    }
    fclose(f);
    if (i != n) {
        fprintf(stderr, "%s: expected %zu pixels, got %zu\n", path, n, i);
        return -1;
    }
    return 0;
}

static int write_hex(const char *path, const uint8_t *buf, size_t n) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); return -1; }
    for (size_t i = 0; i < n; ++i) fprintf(f, "%02X\n", buf[i]);
    fclose(f);
    return 0;
}

static void usage(const char *p) {
    fprintf(stderr, "Usage: %s INPUT_HEX OUTPUT_DENSE_HEX WIDTH HEIGHT [THRESHOLD]\n", p);
}

int main(int argc, char **argv) {
    if (argc < 5 || argc > 6) { usage(argv[0]); return 2; }
    const char *input_path = argv[1];
    const char *output_path = argv[2];
    int w = atoi(argv[3]);
    int h = atoi(argv[4]);
    int threshold = argc == 6 ? atoi(argv[5]) : 100;
    if (w < 5 || h < 5 || threshold < 0 || threshold > 4095) {
        fprintf(stderr, "invalid width/height/threshold\n"); return 2;
    }

    size_t n = (size_t)w * (size_t)h;
    size_t out_n = (size_t)(w - 4) * (size_t)(h - 4);
    uint8_t *in = calloc(n, 1);
    uint8_t *med = calloc(n, 1);
    uint8_t *out = calloc(out_n, 1);
    if (!in || !med || !out) { fprintf(stderr, "allocation failed\n"); return 3; }
    if (read_hex(input_path, in, n)) return 4;

    uint64_t t0 = now_ns();
    for (int y = 1; y < h - 1; ++y) {
        for (int x = 1; x < w - 1; ++x) {
            uint8_t a[9]; int q = 0;
            for (int yy = y - 1; yy <= y + 1; ++yy)
                for (int xx = x - 1; xx <= x + 1; ++xx)
                    a[q++] = in[(size_t)yy * w + xx];
            qsort(a, 9, sizeof(uint8_t), cmp_u8);
            med[(size_t)y * w + x] = a[4];
        }
    }

    size_t k = 0;
    for (int y = 2; y < h - 2; ++y) {
        for (int x = 2; x < w - 2; ++x) {
            int p00 = med[(size_t)(y-1)*w + x-1];
            int p01 = med[(size_t)(y-1)*w + x];
            int p02 = med[(size_t)(y-1)*w + x+1];
            int p10 = med[(size_t)y*w + x-1];
            int p12 = med[(size_t)y*w + x+1];
            int p20 = med[(size_t)(y+1)*w + x-1];
            int p21 = med[(size_t)(y+1)*w + x];
            int p22 = med[(size_t)(y+1)*w + x+1];
            int gx = -p00 + p02 - 2*p10 + 2*p12 - p20 + p22;
            int gy = -p00 - 2*p01 - p02 + p20 + 2*p21 + p22;
            int mag = abs(gx) + abs(gy);
            out[k++] = mag >= threshold ? 255 : 0;
        }
    }
    uint64_t t1 = now_ns();

    if (write_hex(output_path, out, out_n)) return 5;
    printf("CPU_COMPUTE_NS=%" PRIu64 "\n", t1 - t0);
    printf("CPU_COMPUTE_MS=%.6f\n", (double)(t1 - t0) / 1e6);
    printf("INPUT_PIXELS=%zu\n", n);
    printf("OUTPUT_PIXELS=%zu\n", out_n);

    free(in); free(med); free(out);
    return 0;
}
