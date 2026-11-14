/* Probe 17: the R-free check phase and ZIP directory check under ASan/UBSan over the hunt corpora,
   each file also with every single-byte mutation (x3 values) and every truncation. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "znp_check.h"
#include "znp_zip.h"
static unsigned long accepted = 0, runs = 0;
static void one(const uint8_t *d, size_t n, int zip)
{
    /* exact-size heap copy so ASan sees any over-read */
    uint8_t *c = malloc(n ? n : 1); memcpy(c, d, n);
    runs++;
    if (!zip) {
        znp_limits lim = { (uint64_t)1 << 31, 10000, 32, 1024, 0 };
        znp_plan plan; znp_fault f; size_t need;
        if (znp_check_prefix(c, n, &lim, &plan, &need, &f) == ZNP_OK) {
            void *s = malloc(need ? need : 1);
            if (znp_check(c, n, &lim, s, need, &plan, &f) == ZNP_OK) {
                accepted++;
                if (plan.data_offset + plan.data_bytes != n) { fprintf(stderr, "INVARIANT size\n"); abort(); }
                for (int i = 0; i < plan.n_fields; i++)
                    if (plan.fields[i].offset + plan.fields[i].size > plan.itemsize) { fprintf(stderr, "INVARIANT field\n"); abort(); }
            }
            free(s);
        }
    } else {
        znp_zip_limits lim; lim.max_size = (uint64_t)1 << 31; lim.max_members = 10000;
        uint64_t count = 0, got = 0; znp_fault f;
        if (znp_zip_count(c, n, &lim, &count, &f) == ZNP_OK) {
            znp_member *m = malloc((count ? count : 1) * sizeof *m);
            if (znp_zip_check(c, n, &lim, m, count, &got, &f) == ZNP_OK) {
                accepted++;
                for (uint64_t i = 0; i < got; i++) {
                    if (m[i].data_offset + m[i].csize > n) { fprintf(stderr, "INVARIANT member\n"); abort(); }
                    if ((const uint8_t *)m[i].name < c || (const uint8_t *)m[i].name + m[i].name_len > c + n) { fprintf(stderr, "INVARIANT name\n"); abort(); }
                    volatile unsigned char x = 0; for (size_t j = 0; j < m[i].name_len; j++) x ^= (unsigned char)m[i].name[j];
                }
            }
            free(m);
        }
    }
    free(c);
}
int main(int argc, char **argv)
{
    for (int a = 1; a < argc; a++) {
        FILE *fp = fopen(argv[a], "rb"); if (!fp) continue;
        static uint8_t buf[1 << 20]; size_t n = fread(buf, 1, sizeof buf, fp); fclose(fp);
        int zip = n >= 2 && buf[0] == 'P' && buf[1] == 'K';
        one(buf, n, zip);
        size_t lim = n < 3000 ? n : 3000;       /* head */
        for (size_t i = 0; i < lim; i++) {
            uint8_t o = buf[i];
            buf[i] = o ^ 0xff; one(buf, n, zip);
            buf[i] = (uint8_t)(o + 1); one(buf, n, zip);
            buf[i] = 0; one(buf, n, zip);
            buf[i] = o;
        }
        size_t t0 = n > 1500 ? n - 1500 : 0;    /* tail: the ZIP directory */
        if (zip) for (size_t i = t0 > lim ? t0 : lim; i < n; i++) {
            uint8_t o = buf[i];
            buf[i] = o ^ 0xff; one(buf, n, zip);
            buf[i] = (uint8_t)(o + 1); one(buf, n, zip);
            buf[i] = 0xff; one(buf, n, zip);
            buf[i] = o;
        }
        for (size_t k = 0; k < (n < 400 ? n : 400); k++) one(buf, n - k, zip);
        for (size_t k = 0; k < (n < 200 ? n : 200); k++) one(buf, k, zip);
    }
    printf("runs %lu accepted %lu\n", runs, accepted);
    return 0;
}
